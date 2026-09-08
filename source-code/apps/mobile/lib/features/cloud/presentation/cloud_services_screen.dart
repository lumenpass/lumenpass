import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/cloud_database_service.dart';

import '../../../core/ui/app_snack_bar.dart';

import '../../unlock/presentation/webdav_config_page.dart';
import '../../unlock/presentation/sftp_config_page.dart';
import '../../unlock/presentation/s3_config_dialog.dart';
import '../application/cloud_disconnect.dart';
import '../application/cloud_service_provider.dart';

// ── Palette (mirrors vault picker light theme) ────────────────────────────────
const Color _kBackground = Color(0xFFF4F9FA);
const Color _kInk = Color(0xFF0A3B48);
const Color _kTitle = Color(0xFF163640);
const Color _kMuted = Color(0xFF6B858D);
const Color _kBorder = Color(0xFFE3EAF0);

const Color _kOkBg = Color(0xFFE7F6EC);
const Color _kOkBorder = Color(0xFFB7E2C5);
const Color _kOkText = Color(0xFF1B7A3D);
const Color _kWarnBg = Color(0xFFFDECEC);
const Color _kWarnBorder = Color(0xFFF3C2C2);
const Color _kWarnText = Color(0xFFC0392B);
const Color _kAmberBg = Color(0xFFFEF6E7);
const Color _kAmberBorder = Color(0xFFF3DFB0);
const Color _kAmberText = Color(0xFFB7791F);

// ── Public API ──────────────────────────────────────────────────────────────

Future<void> showCloudServicesModal(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: _kBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (modalContext) {
      return const _CloudServicesSheet();
    },
  );
}

// ── Per-provider health-check state ─────────────────────────────────────────

class _ProviderHealth {
  const _ProviderHealth({this.checking = false, this.result});
  final bool checking;
  final CloudCredentialResult? result;
  _ProviderHealth copyWith({bool? checking, CloudCredentialResult? result}) {
    return _ProviderHealth(
      checking: checking ?? this.checking,
      result: result ?? this.result,
    );
  }
}

// ── Sheet content ───────────────────────────────────────────────────────────

class _CloudServicesSheet extends ConsumerStatefulWidget {
  const _CloudServicesSheet();
  @override
  ConsumerState<_CloudServicesSheet> createState() =>
      _CloudServicesSheetState();
}

class _CloudServicesSheetState extends ConsumerState<_CloudServicesSheet> {
  final Map<CloudServiceProvider, _ProviderHealth> _health = {};
  final Set<CloudServiceProvider> _busy = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAll());
  }

  Future<void> _checkAll() async {
    for (final provider in CloudServiceProvider.values) {
      if (provider.isConnected) unawaited(_checkProvider(provider));
    }
  }

  Future<void> _checkProvider(CloudServiceProvider provider) async {
    if (!provider.isConnected) {
      if (mounted) setState(() => _health.remove(provider));
      return;
    }
    if (mounted) {
      setState(() {
        _health[provider] = (_health[provider] ?? const _ProviderHealth())
            .copyWith(checking: true);
      });
    }
    try {
      final result = await CloudDatabaseService.instance
          .verifyCloudCredentialsForStorage(provider.storageType);
      if (!mounted) return;
      setState(() {
        _health[provider] = _ProviderHealth(checking: false, result: result);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _health[provider] = _ProviderHealth(
          checking: false,
          result: CloudCredentialResult(
            CloudCredentialStatus.authExpired,
            providerLabel: provider.label,
            message: 'Could not verify connection: $e',
          ),
        );
      });
    }
  }

  Future<void> _connect(CloudServiceProvider provider) async {
    if (_busy.contains(provider)) return;

    setState(() => _busy.add(provider));
    try {
      switch (provider) {
        case CloudServiceProvider.googleDrive:
          await CloudDatabaseService.instance.connectGoogle();
          break;
        case CloudServiceProvider.dropbox:
          await CloudDatabaseService.instance.connectDropbox();
          break;
        case CloudServiceProvider.oneDrive:
          await CloudDatabaseService.instance.connectOneDrive();
          break;
        case CloudServiceProvider.webdav:
          await Navigator.of(context).push<String?>(
            MaterialPageRoute<String?>(
              builder: (_) => WebDavConfigPage(
                initialConfig:
                    CloudDatabaseService.instance.currentWebDavConfig,
              ),
              fullscreenDialog: true,
            ),
          );
          break;
        case CloudServiceProvider.sftp:
          await Navigator.of(context).push<String?>(
            MaterialPageRoute<String?>(
              builder: (_) => SftpConfigPage(
                initialConfig: CloudDatabaseService.instance.currentSftpConfig,
              ),
              fullscreenDialog: true,
            ),
          );
          break;
        case CloudServiceProvider.s3:
          final label = await Navigator.of(context).push<String?>(
            MaterialPageRoute<String?>(
              builder: (_) => const S3ConfigDialog(),
              fullscreenDialog: true,
            ),
          );
          if (label != null && mounted) {
            ref.read(cloudS3AccountProvider.notifier).state = label;
          }
          break;
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          '${provider.label} connection failed: '
          '${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(provider));
    }
    if (mounted) await _checkProvider(provider);
  }

  Future<void> _disconnect(CloudServiceProvider provider) async {
    if (_busy.contains(provider)) return;
    final confirmed = await confirmCloudDisconnect(context);
    if (!confirmed || !mounted) return;
    setState(() => _busy.add(provider));
    try {
      await performCloudDisconnect(ref, provider);
      if (mounted) setState(() => _health.remove(provider));
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, '${provider.label} disconnect failed: $e');
      }
    } finally {
      if (mounted) setState(() => _busy.remove(provider));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.88,
      child: Column(
        children: <Widget>[
          const _SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Cloud Services',
                    style: TextStyle(
                      color: _kTitle,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _IconAction(
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(
              'Manage where LumenPass syncs your vaults. Connections are '
              'checked automatically when you open this screen.',
              style: TextStyle(color: _kMuted, fontSize: 12.5, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Connected services',
                style: TextStyle(
                  color: _kMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final provider
                      in CloudServiceProvider.values) ...<Widget>[
                    _CloudServiceCard(
                      provider: provider,
                      accountLabel: provider.accountLabel(ref),
                      isConnected: provider.isConnectedFor(ref),

                      health: _health[provider],
                      busy: _busy.contains(provider),
                      onConnect: () => _connect(provider),
                      onDisconnect: () => _disconnect(provider),
                      onRecheck: () => _checkProvider(provider),
                    ),
                    if (provider != CloudServiceProvider.values.last)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sheet handle ────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 36,
        height: 5,
        decoration: BoxDecoration(
          color: _kBorder,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

// ── Cloud service card ──────────────────────────────────────────────────────

class _CloudServiceCard extends StatelessWidget {
  const _CloudServiceCard({
    required this.provider,
    required this.accountLabel,
    required this.isConnected,

    required this.health,
    required this.busy,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRecheck,
  });

  final CloudServiceProvider provider;
  final String? accountLabel;
  final bool isConnected;

  final _ProviderHealth? health;
  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onRecheck;

  bool get _available => provider.isConfigured;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _buildIcon(),
              const SizedBox(width: 12),
              Expanded(child: _buildTitle()),
              const SizedBox(width: 10),
              _buildAction(),
            ],
          ),
          _buildStatus(),
        ],
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _kBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Image.asset(
        provider.assetPath,
        width: 24,
        height: 24,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.cloud_outlined, size: 22, color: _kMuted),
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                provider.label,
                style: const TextStyle(
                  color: _kTitle,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          !_available
              ? 'Not available in this build'
              : (accountLabel != null && isConnected
                    ? accountLabel!
                    : provider.description),
          style: const TextStyle(color: _kMuted, fontSize: 12.5, height: 1.3),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildAction() {
    if (busy) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      );
    }
    if (!_available) {
      return const Text(
        'Unavailable',
        style: TextStyle(
          color: _kMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    if (isConnected) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _IconAction(
            icon: Icons.refresh_rounded,
            tooltip: 'Recheck',
            onTap: onRecheck,
          ),
          const SizedBox(width: 8),
          _IconAction(
            icon: Icons.link_off_rounded,
            tooltip: 'Disconnect',
            danger: true,
            onTap: onDisconnect,
          ),
        ],
      );
    }

    return _PrimaryButton(
      label: 'Connect',
      icon: Icons.power_rounded,
      onTap: onConnect,
    );
  }

  Widget _buildStatus() {
    if (!isConnected || !_available) return const SizedBox.shrink();

    final h = health;
    if (h == null || h.checking) {
      return const _StatusBanner(
        bg: _kBackground,
        border: _kBorder,
        fg: _kMuted,
        icon: Icons.hourglass_empty_rounded,
        text: 'Checking connection...',
      );
    }

    final result = h.result;
    if (result == null) return const SizedBox.shrink();

    switch (result.status) {
      case CloudCredentialStatus.valid:
      case CloudCredentialStatus.notApplicable:
        return _StatusBanner(
          bg: _kOkBg,
          border: _kOkBorder,
          fg: _kOkText,
          icon: Icons.check_circle_rounded,
          text: accountLabel != null
              ? 'Connected as $accountLabel'
              : 'Connected and healthy',
        );
      case CloudCredentialStatus.networkError:
        return _StatusBanner(
          bg: _kAmberBg,
          border: _kAmberBorder,
          fg: _kAmberText,
          icon: Icons.wifi_off_rounded,
          text:
              result.message ??
              "Couldn't verify the connection. Check your network.",
        );
      case CloudCredentialStatus.notSignedIn:
      case CloudCredentialStatus.authExpired:
        return _StatusBanner(
          bg: _kWarnBg,
          border: _kWarnBorder,
          fg: _kWarnText,
          icon: Icons.warning_amber_rounded,
          text:
              result.message ??
              'Connection problem. ${provider.label} rejected the stored '
                  'credentials - please reconnect.',
          action: onConnect,
          actionLabel: 'Reconnect',
        );
    }
  }
}

// ── Shared utility widgets ──────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: _kInk,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) {
    final color = danger ? _kWarnText : _kInk;
    return Semantics(
      button: true,
      label: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: danger ? _kWarnBorder : _kBorder),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.bg,
    required this.border,
    required this.fg,
    required this.icon,
    required this.text,
    this.action,
    this.actionLabel,
  });
  final Color bg;
  final Color border;
  final Color fg;
  final IconData icon;
  final String text;
  final VoidCallback? action;
  final String? actionLabel;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: border),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: fg, fontSize: 12.5, height: 1.35),
              ),
            ),
            if (action != null && actionLabel != null) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: action,
                child: Text(
                  actionLabel!,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    decoration: TextDecoration.underline,
                    decorationColor: fg,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
