import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/app_runtime_info.dart';

import '../../../core/services/vault_auto_sync_controller.dart';
import '../../../core/ui/app_snack_bar.dart';

import 'vault_settings_modal.dart';

const Color _kBackground = Color(0xFFF4F9FA);

const Color _kInk = Color(0xFF0A3B48);
const Color _kText = Color(0xFF163640);
const Color _kMuted = Color(0xFF6B858D);
const Color _kBorder = Color(0xFFE3EAF0);

const double _kFloatingBottomNavClearance = 170;

const String _kAppName = 'LumenPass';
const String _kSupportEmail = 'staff@lumenpass.app';
const String _kWebsiteUrl = 'https://www.lumenpass.app';

class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  AppRuntimeInfo? _runtimeInfo;

  @override
  void initState() {
    super.initState();
    _loadRuntimeInfo();
  }

  Future<void> _loadRuntimeInfo() async {
    final info = await AppRuntimeInfoService.load();
    if (!mounted) return;
    setState(() => _runtimeInfo = info);
  }

  void _openSettings() => showVaultSettingsModal(context);

  Future<void> _openSupportEmail() async {
    await _openUrl(
      Uri(
        scheme: 'mailto',
        path: _kSupportEmail,
        queryParameters: {'subject': 'LumenPass Support'},
      ),
      fallback: 'Could not open your email app.',
    );
  }

  Future<void> _openWebsite() async {
    await _openUrl(
      Uri.parse(_kWebsiteUrl),
      fallback: 'Could not open website.',
    );
  }

  Future<void> _openUrl(Uri uri, {required String fallback}) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _toast(fallback);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    AppSnackBar.info(context, message);
  }

  Future<void> _refreshVaultData() async {
    await ref.read(vaultAutoSyncControllerProvider.notifier).sync();
    final syncState = ref.read(vaultAutoSyncControllerProvider);
    if (syncState.hasError && mounted) {
      AppSnackBar.error(
        context,
        'Sync failed: ${syncState.error ?? 'unknown error'}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bottomPadding =
        (bottomInset > 12 ? bottomInset + 12 : 24.0) +
        _kFloatingBottomNavClearance;
    final version = _runtimeInfo?.version.isNotEmpty == true
        ? _runtimeInfo!.version
        : '—';
    final build = _runtimeInfo?.buildNumber.isNotEmpty == true
        ? _runtimeInfo!.buildNumber
        : '—';

    return RefreshIndicator(
      onRefresh: _refreshVaultData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, topInset + 20, 16, bottomPadding),
        children: [
          const Text(
            'Profile',
            style: TextStyle(
              color: _kInk,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Manage vault preferences, security, support, and app information.',
            style: TextStyle(color: _kMuted, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 20),
          _ProfileMenuGroup(onSettings: _openSettings),
          const SizedBox(height: 8),
          const _VaultSyncStatusRow(),
          const SizedBox(height: 24),
          _ProfileCredits(
            appName: _kAppName,
            appVersion: version,
            buildNumber: build,
            supportEmail: _kSupportEmail,
            website: _kWebsiteUrl,
            onContactEmail: _openSupportEmail,
            onOpenWebsite: _openWebsite,
          ),
        ],
      ),
    );
  }
}

class _ProfileMenuGroup extends StatelessWidget {
  const _ProfileMenuGroup({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onSettings,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _kBorder),
              boxShadow: [
                BoxShadow(
                  color: _kInk.withValues(alpha: 0.06),
                  blurRadius: 24,
                  spreadRadius: -12,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _kBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.settings_outlined,
                    color: _kInk,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: _kText,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: _kMuted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileCredits extends StatelessWidget {
  const _ProfileCredits({
    required this.appName,
    required this.appVersion,
    required this.buildNumber,
    required this.supportEmail,
    required this.website,
    required this.onContactEmail,
    required this.onOpenWebsite,
  });

  final String appName;
  final String appVersion;
  final String buildNumber;
  final String supportEmail;
  final String website;
  final VoidCallback onContactEmail;
  final VoidCallback onOpenWebsite;

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;

    return Center(
      child: Column(
        children: [
          Text(
            '$appName • v$appVersion ($buildNumber)',
            style: const TextStyle(
              color: _kMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: onContactEmail,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                supportEmail,
                style: const TextStyle(
                  color: _kInk,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          InkWell(
            onTap: onOpenWebsite,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                website,
                style: const TextStyle(
                  color: _kInk,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '© $year $appName',
            style: const TextStyle(
              color: _kMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _VaultSyncStatusRow extends ConsumerStatefulWidget {
  const _VaultSyncStatusRow();

  @override
  ConsumerState<_VaultSyncStatusRow> createState() =>
      _VaultSyncStatusRowState();
}

class _VaultSyncStatusRowState extends ConsumerState<_VaultSyncStatusRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _spin.dispose();
    super.dispose();
  }

  void _syncSpinner(VaultSyncState state) {
    if (state.isSyncing) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      if (_spin.isAnimating) {
        _spin.stop();
        _spin.value = 0;
      }
    }
  }

  Future<void> _onPressed() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final controller = ref.read(vaultAutoSyncControllerProvider.notifier);
    await controller.sync();
    if (!mounted) return;
    final state = ref.read(vaultAutoSyncControllerProvider);
    if (state.hasError && messenger != null) {
      AppSnackBar.error(
        context,
        'Sync failed: ${state.error ?? 'unknown error'}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultAutoSyncControllerProvider);
    _syncSpinner(state);

    final disabled = state.isSyncing;
    final label = state.isSyncing
        ? 'Syncing…'
        : (state.hasError
              ? 'Sync failed — tap to retry'
              : formatLastSync(state.lastSyncAt));
    final labelColor = state.hasError ? const Color(0xFFEF4444) : _kMuted;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: state.hasError
                  ? const Color(0xFFFFF1F1)
                  : const Color(0xFFEAF5F7),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.cloud_sync_outlined, size: 16, color: labelColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: labelColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 34,
            height: 34,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: disabled ? null : _onPressed,
                child: Center(
                  child: RotationTransition(
                    turns: _spin,
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 18,
                      color: disabled ? _kMuted : _kInk,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
