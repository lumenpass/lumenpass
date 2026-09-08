import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../features/vault/application/vault_item_type.dart';
import '../models/kdbx_database.dart';
import '../repository/kdbx_repository_provider.dart';

/// Providers consumed by the SSH Agent settings UI and service.
final sshAgentEnabledProvider = StateProvider<bool>((ref) => false);
final sshAgentSocketPathProvider = StateProvider<String>((ref) => '');
final sshAgentConfigStatusProvider =
    StateProvider<SshAgentConfigStatus>((ref) => SshAgentConfigStatus.unknown);

enum SshAgentConfigStatus {
  unknown,
  configured,
  needsAttention,
}

const String _kSshAgentEnabledKey = 'ssh_agent_enabled';
const MethodChannel _kChannel = MethodChannel('lumenpass/ssh_agent');
const MethodChannel _kWindowChannel = MethodChannel('lumenpass/window');

/// Singleton service that manages the macOS SSH agent lifecycle.
///
/// Call [SshAgentService.instance.init] once at app startup.
class SshAgentService {
  SshAgentService._();
  static final SshAgentService instance = SshAgentService._();

  ProviderContainer? _container;
  // Real user home directory, derived from the socket path returned by Swift.
  // Swift uses FileManager.homeDirectoryForCurrentUser which is always the real
  // home (e.g. /Users/alice), NOT the sandboxed container home that
  // Platform.environment['HOME'] returns in a sandboxed macOS app.
  String? _realHome;
  String? _currentSocketPath;
  Timer? _configCheckTimer;
  static const String _managedConfigBegin = '# BEGIN LUMENPASS SSH AGENT';
  static const String _managedConfigEnd = '# END LUMENPASS SSH AGENT';

  Future<void> init(ProviderContainer container) async {
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;
    _container = container;

    _kChannel.setMethodCallHandler(_handleNativeCall);

    // Auto-sync keys whenever the vault opens or closes.
    container.listen<KdbxDatabase?>(activeDatabaseProvider, (_, next) {
      // ignore: avoid_types_on_closure_parameters
      if (!container.read(sshAgentEnabledProvider)) return;

      if (next != null) {
        debugPrint('[SshAgent] vault opened — pushing keys');
        unawaited(_pushKeys());
      } else {
        debugPrint('[SshAgent] vault locked — clearing keys');
        unawaited(_pushKeys()); // returns [] when db is null
      }
    });

    final stored = await container
        .read(localStorageProvider)
        .read(key: _kSshAgentEnabledKey);
    final enabled = stored == 'true';

    container.read(sshAgentEnabledProvider.notifier).state = enabled;

    if (enabled) {
      await _startAgent();
    }
  }

  // Called when user toggles the setting
  Future<void> setEnabled(bool enabled) async {
    final container = _container;
    if (container == null) return;

    await container
        .read(localStorageProvider)
        .write(key: _kSshAgentEnabledKey, value: enabled ? 'true' : 'false');
    container.read(sshAgentEnabledProvider.notifier).state = enabled;

    if (enabled) {
      await _startAgent();
    } else {
      await _stopAgent();
    }
  }

  /// Re-sync keys to the native agent (call after vault open/save).
  Future<void> syncKeys() async {
    final container = _container;
    if (container == null) return;
    if (!(container.read(sshAgentEnabledProvider))) return;

    await _pushKeys();
  }

  // ── Private ──────────────────────────────────────────────────────────────

  Future<void> _startAgent() async {
    try {
      final keys = _collectSshKeys();
      debugPrint('[SshAgent] invoking startAgent with ${keys.length} key(s)');
      final path = await _kChannel.invokeMethod<String>('startAgent', {
        'keys': keys,
      });
      debugPrint('[SshAgent] startAgent returned path: $path');
      _container?.read(sshAgentSocketPathProvider.notifier).state = path ?? '';
      if (path != null && path.isNotEmpty) {
        _currentSocketPath = path;
        if (Platform.isWindows) {
          // Windows OpenSSH talks to the agent over the well-known named pipe
          // \\.\pipe\openssh-ssh-agent automatically, so no ~/.ssh/config
          // edits or status polling are needed.
          _container?.read(sshAgentConfigStatusProvider.notifier).state =
              SshAgentConfigStatus.configured;
        } else {
          // macOS + Linux share the same flow: derive the user's home
          // directory and manage a `Host *` block in ~/.ssh/config so any
          // SSH client (OpenSSH, Git, IDE shells, …) routes through us via
          // IdentityAgent. On macOS we also need to strip the sandbox
          // container suffix from the path Swift hands back.
          var home = path.substring(0, path.lastIndexOf('/'));
          const containerMarker = '/Library/Containers/';
          final containerIdx = home.indexOf(containerMarker);
          if (containerIdx > 0) {
            home = home.substring(0, containerIdx);
          }
          if (Platform.isLinux) {
            // The Linux native runner returns a path inside
            // $XDG_RUNTIME_DIR (e.g. /run/user/1000). That directory is
            // not the user's $HOME, so we resolve $HOME from the
            // environment for ~/.ssh/config management.
            home = Platform.environment['HOME'] ?? home;
          }
          _realHome = home;
          debugPrint('[SshAgent] derived realHome: $_realHome');
          await _ensureSshConfigIdentityAgent(path);
          // Start background polling so the status reflects any manual edits
          // the user makes to ~/.ssh/config.
          _configCheckTimer?.cancel();
          _configCheckTimer = Timer.periodic(
            const Duration(seconds: 4),
            (_) => unawaited(_refreshConfigStatus()),
          );
        }
      }
    } catch (e) {
      debugPrint('[SshAgent] startAgent FAILED: $e');
      _container?.read(sshAgentConfigStatusProvider.notifier).state =
          SshAgentConfigStatus.needsAttention;
    }
  }

  Future<void> _stopAgent() async {
    _configCheckTimer?.cancel();
    _configCheckTimer = null;
    _currentSocketPath = null;
    try {
      await _kChannel.invokeMethod('stopAgent');
    } catch (_) {}
    _container?.read(sshAgentSocketPathProvider.notifier).state = '';
    await _removeManagedSshConfigBlock();
    _container?.read(sshAgentConfigStatusProvider.notifier).state =
        SshAgentConfigStatus.unknown;
  }

  Future<void> _refreshConfigStatus() async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    final socketPath = _currentSocketPath;
    final home = _realHome;
    if (socketPath == null || home == null || home.isEmpty) return;
    try {
      final configFile = File('$home/.ssh/config');
      if (!await configFile.exists()) {
        _container?.read(sshAgentConfigStatusProvider.notifier).state =
            SshAgentConfigStatus.needsAttention;
        return;
      }
      final content = await configFile.readAsString();
      final isValid = content.contains(_managedConfigBegin) &&
          content.contains('IdentityAgent "$socketPath"');
      _container?.read(sshAgentConfigStatusProvider.notifier).state = isValid
          ? SshAgentConfigStatus.configured
          : SshAgentConfigStatus.needsAttention;
    } catch (_) {}
  }

  Future<void> _pushKeys() async {
    try {
      final keys = _collectSshKeys();
      await _kChannel.invokeMethod('setKeys', {'keys': keys});
    } catch (_) {}
  }

  Future<void> _ensureSshConfigIdentityAgent(String socketPath) async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    // Use the real home derived from the socket path. Falling back to
    // Platform.environment['HOME'] would give the sandboxed container path
    // (e.g. ~/Library/Containers/com.tranit.lumenpass.macos/Data) instead of
    // the user's actual home directory.
    final home = _realHome ?? Platform.environment['HOME'];
    if (home == null || home.isEmpty) return;

    try {
      final sshDir = Directory('$home/.ssh');
      if (!await sshDir.exists()) {
        await sshDir.create(recursive: true);
      }

      final configFile = File('${sshDir.path}/config');
      final existing =
          await configFile.exists() ? await configFile.readAsString() : '';
      final cleaned = _stripManagedBlock(existing);

      final block = [
        _managedConfigBegin,
        'Host *',
        '  IdentityAgent "$socketPath"',
        _managedConfigEnd,
        '',
      ].join('\n');

      final next = (cleaned.trimRight().isEmpty)
          ? '$block'
          : '${cleaned.trimRight()}\n\n$block';
      await configFile.writeAsString(next);
      _container?.read(sshAgentConfigStatusProvider.notifier).state =
          SshAgentConfigStatus.configured;
    } catch (e) {
      debugPrint('[SshAgent] failed to write ~/.ssh/config: $e');
      _container?.read(sshAgentConfigStatusProvider.notifier).state =
          SshAgentConfigStatus.needsAttention;
    }
  }

  Future<void> _removeManagedSshConfigBlock() async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    final home = _realHome ?? Platform.environment['HOME'];
    if (home == null || home.isEmpty) return;

    final configFile = File('$home/.ssh/config');
    if (!await configFile.exists()) return;
    try {
      final existing = await configFile.readAsString();
      final cleaned = _stripManagedBlock(existing);
      if (cleaned != existing) {
        await configFile.writeAsString(cleaned.trimRight() + '\n');
      }
    } catch (_) {}
  }

  String _stripManagedBlock(String content) {
    final begin = content.indexOf(_managedConfigBegin);
    if (begin < 0) return content;
    final end = content.indexOf(_managedConfigEnd, begin);
    if (end < 0) {
      // If begin exists but end doesn't, remove from begin to EOF.
      return content.substring(0, begin).trimRight() + '\n';
    }
    final afterEnd = end + _managedConfigEnd.length;
    final before = content.substring(0, begin).trimRight();
    final after = content.substring(afterEnd).trimLeft();
    if (before.isEmpty) return after;
    if (after.isEmpty) return '$before\n';
    return '$before\n\n$after';
  }

  List<Map<String, String>> _collectSshKeys() {
    final container = _container;
    if (container == null) return [];
    final db = container.read(activeDatabaseProvider);
    if (db == null) return [];

    final result = <Map<String, String>>[];
    for (final entry in db.entries) {
      if (classifyVaultItemType(entry) != VaultItemType.sshKey) continue;
      final privateKey = entry.fields
          .where((f) => f.key == 'Private Key')
          .map((f) => f.value)
          .firstOrNull;
      if (privateKey == null || privateKey.trim().isEmpty) continue;
      // Skip passphrase-protected keys (we can't sign with them without unlocking)
      if (_isEncryptedKey(privateKey)) continue;
      result.add({
        'name': entry.title,
        'privateKey': privateKey.trim(),
      });
    }
    return result;
  }

  bool _isEncryptedKey(String pem) {
    final lower = pem.toLowerCase();
    return lower.contains('aes256-ctr') ||
        lower.contains('aes256-cbc') ||
        lower.contains('encrypted private key') ||
        lower.contains('proc-type') ||
        lower.contains('dek-info');
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method != 'onSignRequest') return null;
    final args = Map<String, dynamic>.from(call.arguments as Map);
    final requestId = args['requestId'] as int;
    final keyName = args['keyName'] as String? ?? 'Unknown Key';
    final requesterName =
        args['requesterName'] as String? ?? 'Requesting Process';
    final requesterPid = (args['requesterPid'] as num?)?.toInt();
    final requesterExecutablePath = args['requesterExecutablePath'] as String?;
    debugPrint(
      '[SshAgent] onSignRequest received: requestId=$requestId key=$keyName requester=$requesterName pid=$requesterPid path=$requesterExecutablePath',
    );

    final approved = await _showApprovalDialog(
      keyName: keyName,
      requesterName: requesterName,
      requesterPid: requesterPid,
      requesterExecutablePath: requesterExecutablePath,
    );
    debugPrint('[SshAgent] signResponse: approved=$approved');
    await _kChannel.invokeMethod('signResponse', {
      'requestId': requestId,
      'approved': approved,
    });
    return null;
  }

  Future<bool> _showApprovalDialog({
    required String keyName,
    required String requesterName,
    int? requesterPid,
    String? requesterExecutablePath,
  }) async {
    // Preferred flow: native detached approval window (works even when app is
    // minimized to tray/menu bar).
    try {
      final approved = await _kWindowChannel.invokeMethod<bool>(
        'showSshApprovalWindow',
        <String, dynamic>{
          'keyName': keyName,
          'requesterName': requesterName,
          'requesterPid': requesterPid,
          'requesterExecutablePath': requesterExecutablePath,
        },
      );
      if (approved != null) {
        return approved;
      }
    } catch (e) {
      debugPrint('[SshAgent] native approval window failed: $e');
    }

    final ctx = navigatorKey.currentContext;
    debugPrint(
        '[SshAgent] fallback dialog: ctx=${ctx != null ? 'ok' : 'NULL'}');
    if (ctx == null) return false;

    // Fallback: in-app modal dialog.
    try {
      await _kWindowChannel.invokeMethod<void>('bringToFront');
    } catch (_) {}
    if (!ctx.mounted) return false;

    final result = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) =>
          _SshApprovalDialog(keyName: keyName, requesterName: requesterName),
    );
    return result == true;
  }
}

/// Global navigator key used to show approval dialogs from the service.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ── Approval Dialog ───────────────────────────────────────────────────────

class _SshApprovalDialog extends StatelessWidget {
  const _SshApprovalDialog({
    required this.keyName,
    required this.requesterName,
  });

  final String keyName;
  final String requesterName;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF2F2F7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 24,
      shadowColor: Colors.black38,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Title
              const Text(
                'LumenPass Access Requested',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C1E),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 24),
              // Icon flow: terminal → check → lumenpass shield
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  // Terminal icon (requesting app)
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(51),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      TablerIcons.terminal_2,
                      size: 26,
                      color: Color(0xFF30D158),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Connector line + check
                  Row(
                    children: <Widget>[
                      Container(
                        width: 16,
                        height: 1.5,
                        color: const Color(0xFFD1D1D6),
                      ),
                      Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Color(0xFF34C759),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          TablerIcons.check,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                      Container(
                        width: 16,
                        height: 1.5,
                        color: const Color(0xFFD1D1D6),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  // LumenPass icon
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withAlpha(77),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      TablerIcons.shield_lock,
                      size: 26,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Subtitle
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF3C3C43),
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: 'Allow '),
                    TextSpan(
                      text: requesterName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const TextSpan(text: ' to use '),
                    const TextSpan(
                      text: 'SSH key',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Key card
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F7FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        TablerIcons.key,
                        size: 18,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'SSH KEY',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF8E8E93),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            keyName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1C1C1E),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Buttons
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFE5E5EA),
                        foregroundColor: const Color(0xFF1C1C1E),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Deny',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A3B48),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(TablerIcons.fingerprint, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Allow',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
