import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../../../core/services/biometric_auth_service.dart';
import '../../../core/services/cloud_sync_service.dart';

import '../../../core/repository/providers.dart';
import '../../../core/repository/vault_write_scheduler_provider.dart';
import '../../../core/services/cloud_vault_cache.dart';
import '../../../core/ui/app_snack_bar.dart';
import '../../../core/ui/floating_glass_search_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/presentation/home_screen.dart';
import '../../startup/presentation/startup_router.dart';
import '../application/database_registry.dart';
import 'unlocking_progress_screen.dart';

const _unlockBackground = Color(0xFFF4F9FA);
const _unlockInk = Color(0xFF0A3B48);
const _unlockText = Color(0xFF0B1F26);
const _unlockMuted = Color(0xFF5C7680);
const _unlockSoftBorder = Color(0xFFE1ECF1);
const _unlockField = Color(0xF4F8FBFC);

String _unlockVaultStorageIconAsset(String storageType) {
  return switch (storageType) {
    'googleDrive' => 'assets/images/google-drive.png',
    'dropbox' => 'assets/images/dropbox.png',
    'oneDrive' => 'assets/images/onedrive.png',
    'webdav' => 'assets/images/webdav.png',
    _ => 'assets/images/dir.png',
  };
}

/// Shared [RouteObserver] used by [UnlockVaultScreen] to detect when the
/// screen becomes visible again (e.g. after returning from settings) so it can
/// reload the PIN / biometric availability state.
final unlockRouteObserver = RouteObserver<ModalRoute<void>>();

class UnlockVaultScreen extends ConsumerStatefulWidget {
  const UnlockVaultScreen({super.key, required this.record, this.onUnlocked});

  final DatabaseRecord record;

  /// Optional callback invoked after a successful unlock.  When provided the
  /// screen simply pops itself and calls [onUnlocked]; when null the screen
  /// pushes (and removes all routes below) a new [HomeScreen] — the default
  /// behaviour used from the vault-picker launch flow.
  final VoidCallback? onUnlocked;

  @override
  ConsumerState<UnlockVaultScreen> createState() => _UnlockVaultScreenState();
}

class _UnlockVaultScreenState extends ConsumerState<UnlockVaultScreen>
    with RouteAware {
  final _passwordCtrl = TextEditingController();
  bool _obscurePw = true;
  bool _emptyPassword = false;
  bool _advanced = false;
  bool _isUnlocking = false;
  String? _keyFilePath;
  Uint8List? _keyFileBytes;

  // Quick-unlock availability — reloaded every time the route becomes active.
  bool _pinEnabled = false;
  bool _biometricEnabled = false;

  /// Master password recovered from a valid "stay unlocked" token, used to
  /// auto-unlock on cold start without any prompt. Null when the feature is
  /// off, no token is stored, or the 2-week hard cap has elapsed.
  String? _persistentPassword;

  /// Guards auto-trigger so biometric/PIN is only prompted once on initial
  /// screen open — not again when returning from settings via [didPopNext].
  bool _hasAutoTriggered = false;

  static final _routeObserver = unlockRouteObserver;

  @override
  void initState() {
    super.initState();
    _loadQuickUnlockState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      _routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _routeObserver.unsubscribe(this);
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// Called when a route above this one is popped, making this route visible again.
  @override
  void didPopNext() => _loadQuickUnlockState();

  Future<void> _loadQuickUnlockState() async {
    final svc = ref.read(vaultUnlockServiceProvider);
    final vaultId = await resolvedVaultUnlockId(widget.record, svc);

    // A valid "stay unlocked" token lets us skip the prompt entirely on cold
    // start. Expired tokens are purged inside this call.
    final persistentPassword = await svc.getPersistentUnlockPassword(
      vaultId,
      maxAge: persistentUnlockMaxAge,
    );

    final bio = ref.read(biometricAuthServiceProvider);
    final results = await Future.wait([
      svc.isPinEnabled(vaultId),
      svc.isBiometricEnabled(vaultId),
      bio.isAvailable(),
    ]);
    final pinEnabled = results[0];
    final biometricEnabled = results[1] && results[2];

    if (!mounted) return;
    setState(() {
      _pinEnabled = pinEnabled;
      _biometricEnabled = biometricEnabled;
      _persistentPassword = persistentPassword;
    });

    _maybeAutoTriggerQuickUnlock();
  }

  /// Automatically starts the highest-priority quick-unlock method the vault
  /// has configured, so the user doesn't have to tap the icon manually.
  /// Priority: Persistent ("stay unlocked") → Biometric → PIN → (fall back to
  /// master password input). Runs only once per screen instance.
  void _maybeAutoTriggerQuickUnlock() {
    if (_hasAutoTriggered) return;
    if (_isUnlocking) return;
    if (_persistentPassword == null && !_biometricEnabled && !_pinEnabled) {
      return;
    }
    _hasAutoTriggered = true;

    // Defer to the next frame so the initial layout is visible before the
    // OS biometric sheet / PIN modal takes over.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final persistent = _persistentPassword;
      if (persistent != null) {
        // Cold-start auto-unlock: no re-auth, and it must not refresh the
        // last-manual-unlock timestamp (isManual: false).
        _unlockWithPassword(persistent, isManual: false);
      } else if (_biometricEnabled) {
        _unlockWithBiometric();
      } else if (_pinEnabled) {
        _unlockWithPin();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final hasQuickUnlock = _pinEnabled || _biometricEnabled;

    return Scaffold(
      backgroundColor: _unlockBackground,
      body: Stack(
        children: [
          const _UnlockBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
                final minHeight = constraints.maxHeight > 46
                    ? constraints.maxHeight - 46
                    : 0.0;

                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(20, 18, 20, bottomInset + 28),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _UnlockVaultHeader(
                          vaultName: widget.record.nickname,
                          storageType: widget.record.storageType,
                          onBack: _isUnlocking
                              ? null
                              : () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(height: 30),
                        _UnlockHero(title: l.unlockTitle),
                        const SizedBox(height: 20),
                        _CredentialCard(
                          passwordController: _passwordCtrl,
                          passwordLabel: l.unlockPasswordLabel,
                          passwordHint: l.unlockPasswordHint,
                          emptyPasswordLabel: l.unlockEmptyPassword,
                          advancedLabel: l.unlockAdvancedKeyFile,
                          keyFileLabel: l.unlockKeyFileLabel,
                          chooseKeyFileLabel: l.unlockChooseKeyFile,
                          keyFileName: _keyFilePath?.split('/').last,
                          obscurePassword: _obscurePw,
                          emptyPassword: _emptyPassword,
                          advanced: _advanced,
                          isUnlocking: _isUnlocking,
                          onToggleObscure: () {
                            setState(() => _obscurePw = !_obscurePw);
                          },
                          onEmptyPasswordChanged: (v) {
                            setState(() {
                              _emptyPassword = v;
                              if (v) _passwordCtrl.clear();
                            });
                          },
                          onAdvancedChanged: (v) =>
                              setState(() => _advanced = v),
                          onPickKeyFile: _pickKeyFile,
                          onSubmit: _unlock,
                        ),
                        const SizedBox(height: 22),
                        _UnlockPrimaryButton(
                          label: l.unlockButton,
                          isLoading: _isUnlocking,
                          onPressed: _isUnlocking ? null : _unlock,
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: !_isUnlocking && hasQuickUnlock
                              ? Padding(
                                  key: const ValueKey('quick-unlock'),
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Center(
                                    child: _QuickUnlockRail(
                                      pinEnabled: _pinEnabled,
                                      biometricEnabled: _biometricEnabled,
                                      onPinTap: _unlockWithPin,
                                      onBiometricTap: _unlockWithBiometric,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey('quick-unlock-empty'),
                                ),
                        ),
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickKeyFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    setState(() {
      _keyFilePath = path;
      _keyFileBytes = bytes;
    });
  }

  Future<void> _unlockWithPin() async {
    if (_isUnlocking) return;

    final pin = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PinEntrySheet(
        onSubmit: (digits) => Navigator.of(context).pop(digits),
      ),
    );
    if (pin == null || !mounted) return;

    // Immediate feedback: hide PIN actions and show loading state before work.
    setState(() => _isUnlocking = true);
    await Future<void>.delayed(const Duration(seconds: 1));

    final svc = ref.read(vaultUnlockServiceProvider);
    final vaultId = await resolvedVaultUnlockId(widget.record, svc);
    final password = await svc.getMasterPasswordForPin(vaultId, pin);
    if (password == null) {
      if (mounted) {
        setState(() => _isUnlocking = false);
        AppSnackBar.error(context, 'Incorrect PIN');
      }
      return;
    }
    await _unlockWithPassword(password, startLoading: false);
  }

  Future<void> _unlockWithBiometric() async {
    if (_isUnlocking) return;

    final bio = ref.read(biometricAuthServiceProvider);
    final authenticated = await bio.authenticate(
      reason: 'Authenticate to unlock your vault',
    );
    if (!authenticated || !mounted) return;

    final svc = ref.read(vaultUnlockServiceProvider);
    final vaultId = await resolvedVaultUnlockId(widget.record, svc);
    final password = await svc.getBiometricPassword(vaultId);
    if (password == null) {
      if (mounted) {
        AppSnackBar.error(
          context,
          'Biometric data not found. Please re-enable it in Settings.',
        );
      }
      return;
    }
    await _unlockWithPassword(password);
  }

  Future<void> _unlockWithPassword(
    String password, {
    bool startLoading = true,
    bool isManual = true,
  }) async {
    if (startLoading) {
      setState(() => _isUnlocking = true);
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnlockingProgressScreen(
          vaultName: widget.record.nickname,
          unlockTask: () => _performUnlock(password, isManual: isManual),
          onSuccess: () {
            if (widget.onUnlocked != null) {
              // Called from the lock-vault flow: pop back to the existing
              // HomeScreen and notify it to reset its state.
              Navigator.of(context).pop();
              widget.onUnlocked!();
            } else {
              // Called from the vault-picker launch flow: replace the whole
              // navigation stack with a fresh HomeScreen.
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
                (route) => false,
              );
            }
          },
          onFailure: (msg) {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _isUnlocking = false);
  }

  Future<void> _performUnlock(String password, {bool isManual = true}) async {
    try {
      final repo = ref.read(kdbxRepositoryProvider);
      final databasePath = await resolvedLocalDatabasePath(widget.record);
      final localFile = File(databasePath);
      if (!await localFile.exists()) {
        final r = widget.record;
        if (r.storageType == 'googleDrive' ||
            r.storageType == 'dropbox' ||
            r.storageType == 'oneDrive' ||
            r.storageType == 'webdav') {
          if (r.cloudFileId != null &&
              r.cloudFileId!.isNotEmpty &&
              r.cloudFileName != null &&
              r.cloudFileName!.isNotEmpty) {
            await ensureCloudDatabaseCached(r);
          } else {
            throw const VaultAccessException(
              'The local copy of this cloud vault is missing. Remove it from '
              'your list and add it again from Google Drive or Dropbox.',
            );
          }
        }
      } else if (widget.record.storageType == 'local' &&
          databasePath != widget.record.databasePath) {
        // The resolver healed a stale path (iOS container UUID rotated on
        // rebuild). Persist the current absolute path so saves target it.
        unawaited(
          ref
              .read(databaseRegistryProvider.notifier)
              .updateDatabasePath(widget.record.id, databasePath),
        );
      }
      await CloudSyncService.instance.refreshFromCloud(widget.record);
      final db = await repo.openDatabase(
        databasePath: databasePath,
        password: password.isEmpty ? null : password,
        keyFileBytes: _keyFileBytes,
      );
      ref.read(vaultWriteSchedulerProvider).reset();
      ref.read(activeDatabaseProvider.notifier).state = db;
      ref.read(cachedMasterPasswordProvider.notifier).state = password;
      await applyPostUnlockPreferences(ref, widget.record.id);

      // Refresh the "stay unlocked" token only on a genuine manual unlock, so
      // the 2-week hard cap is measured from real user unlocks. A cold-start
      // auto-unlock (isManual: false) must not reset that clock.
      if (isManual) {
        final svc = ref.read(vaultUnlockServiceProvider);
        final vaultId = await resolvedVaultUnlockId(widget.record, svc);
        unawaited(svc.recordManualUnlock(vaultId, password));
      }

      // Record the last-opened timestamp so this vault sorts by recency.
      unawaited(
        ref
            .read(databaseRegistryProvider.notifier)
            .setLastOpenedAt(widget.record.id),
      );
    } catch (e, st) {
      debugPrint('UNLOCK ERROR: $e\n$st');
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        AppSnackBar.error(
          context,
          msg.isEmpty ? 'Unlock failed. Please try again.' : msg,
        );
      }
      rethrow;
    }
  }

  Future<void> _unlock() async {
    final password = _emptyPassword ? '' : _passwordCtrl.text;
    await _unlockWithPassword(password);
  }
}

class _UnlockBackdrop extends StatelessWidget {
  const _UnlockBackdrop();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF8FCFD),
              _unlockBackground,
              Color(0xFFE9F4F6),
              Color(0xFFF8F4EA),
            ],
            stops: [0, 0.42, 0.74, 1],
          ),
        ),
      ),
    );
  }
}

class _UnlockVaultHeader extends StatelessWidget {
  const _UnlockVaultHeader({
    required this.vaultName,
    required this.storageType,
    required this.onBack,
  });

  final String vaultName;
  final String storageType;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final iconAsset = _unlockVaultStorageIconAsset(storageType);

    return LayoutBuilder(
      builder: (context, constraints) {
        return GlassSurface(
          height: 68,
          width: constraints.maxWidth,
          borderRadius: 32,
          tint: Colors.white.withValues(alpha: 0.38),
          borderColor: Colors.white.withValues(alpha: 0.72),
          blurSigma: 14,
          highlightOpacity: 0.16,
          quality: GlassQuality.premium,
          thickness: 36,
          chromaticAberration: 0.26,
          lightIntensity: 0.5,
          saturation: 1.24,
          ambientStrength: 0.82,
          shadowOpacity: 0.1,
          shadowBlurRadius: 30,
          shadowSpreadRadius: -11,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 58),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        iconAsset,
                        width: 22,
                        height: 22,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          vaultName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: _unlockText,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                                height: 1.1,
                                letterSpacing: 0,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _HeaderAction(
                    icon: Icons.chevron_left_rounded,
                    semanticLabel: 'Back',
                    onTap: onBack,
                  ),
                ),
                const Align(
                  alignment: Alignment.centerRight,
                  child: _HeaderAction(
                    icon: Icons.shield_outlined,
                    semanticLabel: 'Vault protected',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.semanticLabel,
    this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      label: semanticLabel,
      button: onTap != null,
      enabled: onTap != null,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
          boxShadow: [
            BoxShadow(
              color: _unlockInk.withValues(alpha: 0.08),
              blurRadius: 18,
              spreadRadius: -8,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, color: _unlockInk, size: 26),
      ),
    );

    if (onTap == null) return button;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: button,
    );
  }
}

class _UnlockHero extends StatelessWidget {
  const _UnlockHero({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: _unlockText,
            fontSize: 31,
            fontWeight: FontWeight.w800,
            height: 1.05,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _CredentialCard extends StatelessWidget {
  const _CredentialCard({
    required this.passwordController,
    required this.passwordLabel,
    required this.passwordHint,
    required this.emptyPasswordLabel,
    required this.advancedLabel,
    required this.keyFileLabel,
    required this.chooseKeyFileLabel,
    required this.obscurePassword,
    required this.emptyPassword,
    required this.advanced,
    required this.isUnlocking,
    required this.onToggleObscure,
    required this.onEmptyPasswordChanged,
    required this.onAdvancedChanged,
    required this.onPickKeyFile,
    required this.onSubmit,
    this.keyFileName,
  });

  final TextEditingController passwordController;
  final String passwordLabel;
  final String passwordHint;
  final String emptyPasswordLabel;
  final String advancedLabel;
  final String keyFileLabel;
  final String chooseKeyFileLabel;
  final String? keyFileName;
  final bool obscurePassword;
  final bool emptyPassword;
  final bool advanced;
  final bool isUnlocking;
  final VoidCallback onToggleObscure;
  final ValueChanged<bool> onEmptyPasswordChanged;
  final ValueChanged<bool> onAdvancedChanged;
  final VoidCallback onPickKeyFile;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Container(
            width: constraints.maxWidth,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
              boxShadow: [
                BoxShadow(
                  color: _unlockInk.withValues(alpha: 0.1),
                  blurRadius: 30,
                  spreadRadius: -12,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.85),
                  blurRadius: 12,
                  spreadRadius: -4,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PanelLabel(passwordLabel),
                  const SizedBox(height: 10),
                  _PasswordInput(
                    controller: passwordController,
                    hintText: passwordHint,
                    obscureText: obscurePassword,
                    enabled: !emptyPassword && !isUnlocking,
                    onToggleObscure: onToggleObscure,
                    onSubmitted: onSubmit,
                  ),
                  const SizedBox(height: 14),
                  _SwitchRow(
                    title: emptyPasswordLabel,
                    value: emptyPassword,
                    onChanged: isUnlocking ? null : onEmptyPasswordChanged,
                  ),
                  const SizedBox(height: 10),
                  _SwitchRow(
                    title: advancedLabel,
                    value: advanced,
                    onChanged: isUnlocking ? null : onAdvancedChanged,
                  ),
                  if (advanced) ...[
                    const SizedBox(height: 14),
                    _PanelLabel(keyFileLabel),
                    const SizedBox(height: 8),
                    _KeyFileSelector(
                      label: keyFileName ?? chooseKeyFileLabel,
                      hasFile: keyFileName != null,
                      enabled: !isUnlocking,
                      onTap: onPickKeyFile,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PanelLabel extends StatelessWidget {
  const _PanelLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: _unlockMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: 0,
      ),
    );
  }
}

class _PasswordInput extends StatelessWidget {
  const _PasswordInput({
    required this.controller,
    required this.hintText,
    required this.obscureText,
    required this.enabled,
    required this.onToggleObscure,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final bool enabled;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.58,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _unlockField,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: _unlockSoftBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.72),
              blurRadius: 16,
              offset: const Offset(0, -6),
            ),
            BoxShadow(
              color: _unlockInk.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: _unlockInk.withValues(alpha: 0.58),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: obscureText,
                enabled: enabled,
                style: const TextStyle(
                  color: _unlockInk,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: const TextStyle(
                    color: Color(0xFF879AA2),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (_) => onSubmitted(),
              ),
            ),
            Tooltip(
              message: obscureText
                  ? 'Show master password'
                  : 'Hide master password',
              child: TextButton.icon(
                onPressed: enabled ? onToggleObscure : null,
                style: TextButton.styleFrom(
                  foregroundColor: _unlockInk.withValues(alpha: 0.72),
                  disabledForegroundColor: _unlockInk.withValues(alpha: 0.28),
                  minimumSize: const Size(76, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                icon: Icon(
                  obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
                label: Text(obscureText ? 'Show' : 'Hide'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyFileSelector extends StatelessWidget {
  const _KeyFileSelector({
    required this.label,
    required this.hasFile,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool hasFile;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.58,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(17),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _unlockField,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: _unlockSoftBorder),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.key_rounded,
                  size: 18,
                  color: _unlockInk.withValues(alpha: 0.58),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasFile
                          ? _unlockInk
                          : _unlockInk.withValues(alpha: 0.5),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                Icon(
                  Icons.attach_file_rounded,
                  size: 18,
                  color: _unlockInk.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnlockPrimaryButton extends StatelessWidget {
  const _UnlockPrimaryButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.68,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: enabled
                ? const [Color(0xFF105463), _unlockInk, Color(0xFF062F3A)]
                : [
                    _unlockInk.withValues(alpha: 0.68),
                    _unlockInk.withValues(alpha: 0.52),
                  ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: _unlockInk.withValues(alpha: 0.3),
              blurRadius: 28,
              spreadRadius: -10,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(20),
            child: Center(
              child: isLoading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFFF3FCFF),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;

    return Opacity(
      opacity: enabled ? 1 : 0.56,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: enabled ? () => onChanged!(!value) : null,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: _unlockMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                _MiniGlassSwitch(value: value, enabled: enabled),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniGlassSwitch extends StatelessWidget {
  const _MiniGlassSwitch({required this.value, required this.enabled});

  final bool value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 54,
      height: 32,
      padding: const EdgeInsets.all(3),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: value
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF17697A), _unlockInk],
              )
            : null,
        color: value ? null : const Color(0xFFE7EDF0),
        border: Border.all(
          color: value
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.88),
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFFDFEFE),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: enabled ? 0.18 : 0.08),
              blurRadius: 10,
              spreadRadius: -4,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickUnlockRail extends StatelessWidget {
  const _QuickUnlockRail({
    required this.pinEnabled,
    required this.biometricEnabled,
    required this.onPinTap,
    required this.onBiometricTap,
  });

  final bool pinEnabled;
  final bool biometricEnabled;
  final VoidCallback onPinTap;
  final VoidCallback onBiometricTap;

  @override
  Widget build(BuildContext context) {
    final itemCount = (pinEnabled ? 1 : 0) + (biometricEnabled ? 1 : 0);
    final width = itemCount == 1 ? 58.0 : 118.0;

    return GlassSurface(
      height: 54,
      width: width,
      borderRadius: 27,
      tint: Colors.white.withValues(alpha: 0.4),
      borderColor: Colors.white.withValues(alpha: 0.7),
      blurSigma: 12,
      highlightOpacity: 0.22,
      quality: GlassQuality.premium,
      thickness: 34,
      chromaticAberration: 0.18,
      lightIntensity: 0.48,
      saturation: 1.16,
      ambientStrength: 0.76,
      shadowOpacity: 0.08,
      shadowBlurRadius: 22,
      shadowSpreadRadius: -9,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (pinEnabled)
            _MethodButton(
              icon: Icons.dialpad_rounded,
              semanticLabel: 'Unlock with PIN',
              onTap: onPinTap,
            ),
          if (pinEnabled && biometricEnabled) const SizedBox(width: 6),
          if (biometricEnabled)
            _MethodButton(
              icon: Icons.fingerprint_rounded,
              semanticLabel: 'Unlock with biometrics',
              onTap: onBiometricTap,
            ),
        ],
      ),
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, color: _unlockInk, size: 21),
          ),
        ),
      ),
    );
  }
}

// ── PIN entry sheet ──────────────────────────────────────────────────────────

class _PinEntrySheet extends StatefulWidget {
  const _PinEntrySheet({required this.onSubmit});
  final void Function(String digits) onSubmit;

  @override
  State<_PinEntrySheet> createState() => _PinEntrySheetState();
}

class _PinEntrySheetState extends State<_PinEntrySheet> {
  List<int> _digits = const [];

  void _addDigit(int d) {
    if (_digits.length >= 6) return;
    final updated = <int>[..._digits, d];
    setState(() => _digits = updated);
    if (updated.length == 6) {
      widget.onSubmit(updated.map((x) => '$x').join());
    }
  }

  void _removeDigit() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.sublist(0, _digits.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = (MediaQuery.sizeOf(context).height * 0.68)
        .clamp(474.0, 540.0)
        .toDouble();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GlassSurface(
              height: sheetHeight,
              width: constraints.maxWidth,
              borderRadius: 30,
              tint: Colors.white.withValues(alpha: 0.5),
              borderColor: Colors.white.withValues(alpha: 0.72),
              blurSigma: 14,
              highlightOpacity: 0.24,
              quality: GlassQuality.premium,
              thickness: 40,
              chromaticAberration: 0.2,
              lightIntensity: 0.5,
              saturation: 1.18,
              ambientStrength: 0.78,
              shadowOpacity: 0.16,
              shadowBlurRadius: 32,
              shadowSpreadRadius: -10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.28),
                      Colors.white.withValues(alpha: 0.04),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _unlockInk.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Enter your PIN',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: _unlockInk,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List<Widget>.generate(6, (i) {
                          final filled = i < _digits.length;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              width: filled ? 16 : 13,
                              height: filled ? 16 : 13,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: filled ? _unlockInk : Colors.white,
                                border: Border.all(
                                  color: filled
                                      ? _unlockInk
                                      : _unlockInk.withValues(alpha: 0.22),
                                  width: 1.4,
                                ),
                                boxShadow: filled
                                    ? [
                                        BoxShadow(
                                          color: _unlockInk.withValues(
                                            alpha: 0.18,
                                          ),
                                          blurRadius: 8,
                                          spreadRadius: -2,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final row in <List<int>>[
                              [1, 2, 3],
                              [4, 5, 6],
                              [7, 8, 9],
                            ])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: row
                                      .map(
                                        (n) => Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                            ),
                                            child: _PinKey(
                                              label: '$n',
                                              onTap: () => _addDigit(n),
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            Row(
                              children: [
                                const Expanded(child: SizedBox()),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: _PinKey(
                                      label: '0',
                                      onTap: () => _addDigit(0),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: _PinKey(
                                      icon: Icons.backspace_outlined,
                                      enabled: _digits.isNotEmpty,
                                      onTap: _removeDigit,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: _unlockMuted,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PinKey extends StatelessWidget {
  const _PinKey({
    this.label,
    this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.46,
      child: Material(
        color: Colors.white.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.76)),
              boxShadow: [
                BoxShadow(
                  color: _unlockInk.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 22, color: _unlockInk)
                  : Text(
                      label!,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: _unlockInk,
                        letterSpacing: 0,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
