import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../../../core/repository/providers.dart';
import '../../../core/repository/vault_write_scheduler_provider.dart';
import '../../../core/services/biometric_auth_service.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/services/cloud_vault_cache.dart';

import '../../../core/ui/app_snack_bar.dart';
import '../../startup/presentation/startup_router.dart';
import '../application/locked_state_provider.dart';
import '../../unlock/application/database_registry.dart';

const _overlayInk = Color(0xFF0A3B48);
const _overlaySurface = Color(0xFFF4F9FA);

/// Inline unlock surface rendered on top of the home shell when the vault
/// has been locked (auto-lock or manual lock).
///
/// Offers password + PIN + biometric unlock without tearing down the
/// underlying item list state — once unlock succeeds the overlay simply
/// dismisses itself by clearing [mobileLockedRecordProvider].
class LockedVaultOverlay extends ConsumerStatefulWidget {
  const LockedVaultOverlay({super.key, required this.record, this.onUnlocked});

  final DatabaseRecord record;
  final VoidCallback? onUnlocked;

  @override
  ConsumerState<LockedVaultOverlay> createState() => _LockedVaultOverlayState();
}

class _LockedVaultOverlayState extends ConsumerState<LockedVaultOverlay> {
  final _passwordCtrl = TextEditingController();
  bool _obscurePw = true;
  bool _isUnlocking = false;
  bool _pinEnabled = false;
  bool _biometricEnabled = false;
  bool _showPinPad = false;
  List<int> _pinDigits = const [];
  String? _errorMessage;

  /// Guards auto-trigger so biometric/PIN is only prompted once per overlay
  /// instance — not again after rebuild.
  bool _hasAutoTriggered = false;

  @override
  void initState() {
    super.initState();
    _loadQuickUnlockState();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadQuickUnlockState() async {
    final svc = ref.read(vaultUnlockServiceProvider);
    final vaultId = await resolvedVaultUnlockId(widget.record, svc);
    final bio = ref.read(biometricAuthServiceProvider);

    final results = await Future.wait([
      svc.isPinEnabled(vaultId),
      svc.isBiometricEnabled(vaultId),
      bio.isAvailable(),
    ]);

    if (!mounted) return;
    setState(() {
      _pinEnabled = results[0];
      _biometricEnabled = results[1] && results[2];
    });

    _maybeAutoTriggerQuickUnlock();
  }

  /// Automatically starts the highest-priority quick-unlock method the vault
  /// has configured, so the user doesn't have to tap the icon manually.
  /// Priority: Biometric → PIN → (fall back to master password input).
  /// Runs only once per overlay instance.
  void _maybeAutoTriggerQuickUnlock() {
    if (_hasAutoTriggered) return;
    if (_isUnlocking) return;
    if (!_biometricEnabled && !_pinEnabled) return;
    _hasAutoTriggered = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_biometricEnabled) {
        _unlockWithBiometric();
      } else if (_pinEnabled) {
        setState(() {
          _showPinPad = true;
          _errorMessage = null;
        });
      }
    });
  }

  String get _locationLabel => switch (widget.record.storageType) {
    'googleDrive' => 'Google Drive',
    'dropbox' => 'Dropbox',
    'oneDrive' => 'OneDrive',
    'webdav' => 'WebDAV',
    _ => 'Local',
  };

  Future<void> _unlockWithPassword(String password) async {
    setState(() {
      _isUnlocking = true;
      _errorMessage = null;
    });

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
              'your list and add it again.',
            );
          }
        }
      } else if (widget.record.storageType == 'local' &&
          databasePath != widget.record.databasePath) {
        // Heal stored absolute path after iOS container UUID rotation.
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
      );

      ref.read(vaultWriteSchedulerProvider).reset();
      ref.read(activeDatabaseProvider.notifier).state = db;
      ref.read(cachedMasterPasswordProvider.notifier).state = password;
      await applyPostUnlockPreferences(ref, widget.record.id);

      // In-session re-unlock is always manual — refresh the "stay unlocked"
      // token so the 2-week hard cap is measured from this unlock.
      final unlockSvc = ref.read(vaultUnlockServiceProvider);
      final unlockVaultId = await resolvedVaultUnlockId(
        widget.record,
        unlockSvc,
      );
      unawaited(unlockSvc.recordManualUnlock(unlockVaultId, password));

      if (!mounted) return;
      ref.read(mobileLockedRecordProvider.notifier).state = null;
      widget.onUnlocked?.call();
    } catch (e, st) {
      debugPrint('UNLOCK OVERLAY ERROR: $e\n$st');
      if (!mounted) return;
      final raw = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _errorMessage = raw.isEmpty ? 'Unlock failed. Please try again.' : raw;
        _isUnlocking = false;
        _pinDigits = const [];
      });
    }
  }

  Future<void> _unlockWithPin(String pin) async {
    if (_isUnlocking) return;

    setState(() {
      _isUnlocking = true;
      _errorMessage = null;
    });
    final svc = ref.read(vaultUnlockServiceProvider);
    final vaultId = await resolvedVaultUnlockId(widget.record, svc);
    final password = await svc.getMasterPasswordForPin(vaultId, pin);
    if (password == null) {
      if (mounted) {
        setState(() {
          _isUnlocking = false;
          _errorMessage = 'Incorrect PIN — try again.';
          _pinDigits = const [];
        });
      }
      return;
    }
    await _unlockWithPassword(password);
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
          'Biometric data not found. Re-enable it in Settings.',
        );
      }
      return;
    }
    await _unlockWithPassword(password);
  }

  void _addPinDigit(int digit) {
    if (_pinDigits.length >= 6 || _isUnlocking) return;
    final updated = <int>[..._pinDigits, digit];
    setState(() {
      _pinDigits = updated;
      _errorMessage = null;
    });
    if (updated.length == 6) {
      _unlockWithPin(updated.map((d) => '$d').join());
    }
  }

  void _removePinDigit() {
    if (_isUnlocking || _pinDigits.isEmpty) return;
    setState(() {
      _pinDigits = _pinDigits.sublist(0, _pinDigits.length - 1);
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          // Blurred backdrop so the underlying list becomes unreadable yet
          // spatially visible.
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(color: _overlaySurface.withValues(alpha: 0.72)),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(vaultName: widget.record.nickname),
                    const SizedBox(height: 18),
                    if (_showPinPad)
                      _PinPadCard(
                        digits: _pinDigits,
                        errorMessage: _errorMessage,
                        isUnlocking: _isUnlocking,
                        onDigit: _addPinDigit,
                        onBackspace: _removePinDigit,
                        onCancel: () => setState(() {
                          _showPinPad = false;
                          _pinDigits = const [];
                          _errorMessage = null;
                        }),
                      )
                    else ...[
                      _PasswordCard(
                        controller: _passwordCtrl,
                        obscure: _obscurePw,
                        isUnlocking: _isUnlocking,
                        errorMessage: _errorMessage,
                        locationLabel: _locationLabel,
                        nickname: widget.record.nickname,
                        onToggleObscure: () =>
                            setState(() => _obscurePw = !_obscurePw),
                        onSubmit: () => _unlockWithPassword(_passwordCtrl.text),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _isUnlocking
                              ? null
                              : () => _unlockWithPassword(_passwordCtrl.text),
                          style: FilledButton.styleFrom(
                            backgroundColor: _overlayInk,
                            foregroundColor: const Color(0xFFEAF6F9),
                            disabledBackgroundColor: _overlayInk.withValues(
                              alpha: 0.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: _isUnlocking
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Unlock'),
                        ),
                      ),
                      if (!_isUnlocking &&
                          (_pinEnabled || _biometricEnabled)) ...[
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_pinEnabled) ...[
                              _MethodButton(
                                icon: Icons.dialpad_rounded,
                                onTap: () => setState(() {
                                  _showPinPad = true;
                                  _errorMessage = null;
                                }),
                              ),
                              if (_biometricEnabled) const SizedBox(width: 12),
                            ],
                            if (_biometricEnabled)
                              _MethodButton(
                                icon: Icons.fingerprint_rounded,
                                onTap: _unlockWithBiometric,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Subviews ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.vaultName});
  final String vaultName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _overlayInk,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.lock_outline, color: Color(0xFFEAF6F9)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vault locked',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _overlayInk,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                vaultName.isEmpty ? 'Unlock to continue' : vaultName,
                style: const TextStyle(
                  color: Color(0xFF4A6670),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PasswordCard extends StatelessWidget {
  const _PasswordCard({
    required this.controller,
    required this.obscure,
    required this.isUnlocking,
    required this.errorMessage,
    required this.locationLabel,
    required this.nickname,
    required this.onToggleObscure,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool obscure;
  final bool isUnlocking;
  final String? errorMessage;
  final String locationLabel;
  final String nickname;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140A2F3D),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Master password',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF4A6670),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD5E0E5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    obscureText: obscure,
                    enabled: !isUnlocking,
                    style: const TextStyle(
                      color: _overlayInk,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Enter your master password',
                      hintStyle: TextStyle(
                        color: Color(0xFF7A9098),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    autofocus: true,
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
                GestureDetector(
                  onTap: onToggleObscure,
                  child: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: const Color(0xFF7A9098),
                  ),
                ),
              ],
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                errorMessage!,
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '$nickname · $locationLabel',
            style: const TextStyle(
              color: Color(0xFF7A9098),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PinPadCard extends StatelessWidget {
  const _PinPadCard({
    required this.digits,
    required this.errorMessage,
    required this.isUnlocking,
    required this.onDigit,
    required this.onBackspace,
    required this.onCancel,
  });

  final List<int> digits;
  final String? errorMessage;
  final bool isUnlocking;
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140A2F3D),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Enter your PIN',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _overlayInk,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(6, (i) {
              final filled = i < digits.length;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? _overlayInk : Colors.transparent,
                    border: Border.all(
                      color: filled ? _overlayInk : const Color(0xFFB0C4CC),
                      width: 1.5,
                    ),
                  ),
                ),
              );
            }),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 14),
            Text(
              errorMessage!,
              style: const TextStyle(
                color: Color(0xFFB91C1C),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 20),
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
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: _OverlayPinKey(
                            label: '$n',
                            enabled: !isUnlocking,
                            onTap: () => onDigit(n),
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
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _OverlayPinKey(
                    label: '0',
                    enabled: !isUnlocking,
                    onTap: () => onDigit(0),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _OverlayPinKey(
                    icon: Icons.backspace_outlined,
                    enabled: !isUnlocking && digits.isNotEmpty,
                    onTap: onBackspace,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: isUnlocking ? null : onCancel,
            child: const Text(
              'Use master password',
              style: TextStyle(
                color: Color(0xFF6B858D),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayPinKey extends StatelessWidget {
  const _OverlayPinKey({
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
    return Material(
      color: enabled ? const Color(0xFFF5F8FA) : const Color(0xFFEDF1F3),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 52,
          child: Center(
            child: icon != null
                ? Icon(icon, size: 22, color: _overlayInk)
                : Text(
                    label!,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: _overlayInk,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFDCEEF2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: _overlayInk, size: 22),
      ),
    );
  }
}
