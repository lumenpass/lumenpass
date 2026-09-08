import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;

import '../../../app/routes.dart';
import '../../../core/repository/providers.dart';
import '../../../core/repository/vault_write_scheduler_provider.dart';
import '../../../core/services/app_runtime_info.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/services/release_api_client.dart';

import '../../../core/ui/app_snack_bar.dart';
import '../../../core/ui/floating_glass_search_bar.dart';

import '../../unlock/application/database_registry.dart';
import '../../autofill/presentation/autofill_reminder_sheet.dart';
import '../../settings/application/vault_security_provider.dart';
import '../../startup/presentation/startup_router.dart';
import '../../unlock/presentation/unlock_vault_screen.dart';
import '../../vault/application/vault_entries_providers.dart';
import '../../vault/application/vault_items_list_providers.dart';
import '../../vault/presentation/vault_create_item.dart';
import '../../vault/presentation/vault_create_item_models.dart';
import '../../vault/presentation/vault_create_item_shared.dart';
import '../../vault/presentation/vault_entry_avatar.dart';
import '../../vault/presentation/vault_entry_context_menu.dart';
import '../../vault/presentation/vault_entry_list_tile.dart';
import '../../vault/presentation/vault_all_items_screen.dart';
import '../../vault/presentation/vault_item_details_modal.dart';
import '../../vault/presentation/vault_items_tab.dart';
import '../../vault/presentation/vault_search_screen.dart';
import '../../vault/presentation/vault_toast.dart';
import '../application/home_vault_providers.dart';
import '../application/mobile_home_tab_provider.dart';
import 'password_generator_modal.dart';
import 'profile_tab.dart';
import 'vault_settings_modal.dart';
import 'version_changelog_modal.dart';

const _homeBackground = Color(0xFFF4F9FA);
const _homeSurface = Colors.white;
const _homeInk = Color(0xFF0A3B48);
const _homeText = Color(0xFF163640);
const _homeMuted = Color(0xFF6B858D);
const _homeBorder = Color(0xFFE3EAF0);
const _floatingHeaderTopInset = 10.0;
const _floatingHeaderHeight = 68.0;
const _floatingHeaderContentTopPadding =
    _floatingHeaderTopInset + _floatingHeaderHeight + 14.0;
const _homeContentBottomPadding = 96.0;

bool _entryIsLoginOrSecureNote(KdbxEntry entry) {
  final t = classifyVaultItemType(entry);
  return t == VaultItemType.login || t == VaultItemType.secureNote;
}

void _openUnlockForVault(BuildContext context, DatabaseRecord record) {
  final navigator = Navigator.of(context);
  navigator.pushNamedAndRemoveUntil(Routes.vaults, (route) => false);
  navigator.push(
    MaterialPageRoute<void>(builder: (_) => UnlockVaultScreen(record: record)),
  );
}

void _clearActiveVaultSession(WidgetRef ref) {
  // Drop any pending-write state: the in-memory database is about to be
  // disposed, so a stale scheduled save would target the wrong (or closed)
  // vault. Lock paths flush first; this reset is the safety net.
  ref.read(vaultWriteSchedulerProvider).reset();
  ref.read(kdbxRepositoryProvider).closeDatabase();
  ref.read(activeDatabaseProvider.notifier).state = null;
  ref.read(cachedMasterPasswordProvider.notifier).state = null;
  ref.read(vaultSearchUiStateProvider.notifier).clear();
  ref.read(vaultSelectedGroupProvider.notifier).state = kCategoryFilterAll;
  ref.read(vaultItemsSelectedEntryUuidProvider.notifier).state = null;
}

bool _isCloudBackedRecord(DatabaseRecord record) {
  if (record.cloudFileId == null || record.cloudFileId!.isEmpty) return false;
  return record.storageType == 'googleDrive' ||
      record.storageType == 'dropbox' ||
      record.storageType == 'oneDrive' ||
      record.storageType == 'webdav' ||
      record.storageType == 'sftp' ||
      record.storageType == 's3';
}

Future<void> _flushCloudSyncBeforeLock(
  BuildContext context,
  DatabaseRecord? record,
) async {
  if (record == null || !_isCloudBackedRecord(record)) return;

  final status = CloudSyncService.instance.statusFor(record.databasePath);
  final dirty = await CloudSyncService.instance.isDirty(record.databasePath);
  if (!status.isBusy && !dirty) return;
  if (!context.mounted) return;

  final rootNavigator = Navigator.of(context, rootNavigator: true);
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const _CloudSyncLockDialog(),
  );

  try {
    await CloudSyncService.instance.flush(record);
    await CloudSyncService.instance.awaitPending(record.databasePath);
  } finally {
    if (rootNavigator.canPop()) {
      rootNavigator.pop();
    }
    await dialog;
  }

  if (!context.mounted) return;
  final settled = CloudSyncService.instance.statusFor(record.databasePath);
  final stillDirty = await CloudSyncService.instance.isDirty(
    record.databasePath,
  );
  if (!context.mounted) return;
  if (settled.phase == CloudSyncPhase.error || stillDirty) {
    AppSnackBar.error(
      context,
      'Cloud sync is still pending. Your latest changes stay on this device and will retry on the next sync.',
    );
  }
}

void _showQuickSwitchVaultSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _QuickSwitchVaultSheet(
      onVaultSelected: (record) {
        Navigator.of(sheetContext).pop();
        _switchVaultFromHome(context, ref, record);
      },
    ),
  );
}

void _switchVaultFromHome(
  BuildContext context,
  WidgetRef ref,
  DatabaseRecord record,
) {
  final activeRecord = ref.read(homeVaultRecordProvider);
  if (activeRecord != null && activeRecord.id == record.id) {
    return;
  }

  final activePath = ref.read(activeDatabaseProvider)?.path;
  if (activePath != null && _vaultPathsMatch(record.databasePath, activePath)) {
    return;
  }

  _clearActiveVaultSession(ref);
  _openUnlockForVault(context, record);
}

String _vaultStorageIconAsset(String storageType) {
  return switch (storageType) {
    'googleDrive' => 'assets/images/google-drive.png',
    'dropbox' => 'assets/images/dropbox.png',
    'oneDrive' => 'assets/images/onedrive.png',
    'webdav' => 'assets/images/webdav.png',
    _ => 'assets/images/dir.png',
  };
}

bool _vaultPathsMatch(String a, String b) {
  return p.normalize(a) == p.normalize(b);
}

String _cleanVaultDisplayName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return trimmed.replaceFirst(
    RegExp(r'_[a-f0-9]{12}$', caseSensitive: false),
    '',
  );
}

String _quickSwitchVaultName(DatabaseRecord record) {
  final nickname = _cleanVaultDisplayName(record.nickname);
  if (nickname.isNotEmpty) {
    return nickname;
  }

  final cloudFileName = _cleanVaultDisplayName(record.cloudFileName ?? '');
  if (cloudFileName.isNotEmpty) {
    return p.basenameWithoutExtension(cloudFileName);
  }

  final basename = p.basenameWithoutExtension(record.databasePath);
  if (basename.isNotEmpty && basename != '.' && basename != '/') {
    return _cleanVaultDisplayName(basename);
  }

  return 'Vault';
}

String _quickSwitchVaultLocationLabel(DatabaseRecord record) {
  final cloudFileName = (record.cloudFileName ?? '').trim();
  switch (record.storageType) {
    case 'googleDrive':
      return cloudFileName.isEmpty
          ? 'Google Drive'
          : 'Google Drive · $cloudFileName';
    case 'dropbox':
      return cloudFileName.isEmpty ? 'Dropbox' : 'Dropbox · $cloudFileName';
    case 'oneDrive':
      return cloudFileName.isEmpty ? 'OneDrive' : 'OneDrive · $cloudFileName';
    case 'webdav':
      return cloudFileName.isEmpty ? 'WebDAV' : 'WebDAV · $cloudFileName';
    default:
      return p.basename(record.databasePath);
  }
}

bool _isActiveQuickSwitchVault(
  DatabaseRecord record, {
  required DatabaseRecord? activeRecord,
  required String? activePath,
}) {
  if (activeRecord != null && activeRecord.id == record.id) {
    return true;
  }
  if (activePath == null) {
    return false;
  }
  return _vaultPathsMatch(record.databasePath, activePath);
}

List<DatabaseRecord> _sortedQuickSwitchVaults(
  List<DatabaseRecord> records, {
  required DatabaseRecord? activeRecord,
  required String? activePath,
}) {
  final copy = List<DatabaseRecord>.of(records);
  copy.sort((a, b) {
    final aIsActive = _isActiveQuickSwitchVault(
      a,
      activeRecord: activeRecord,
      activePath: activePath,
    );
    final bIsActive = _isActiveQuickSwitchVault(
      b,
      activeRecord: activeRecord,
      activePath: activePath,
    );
    if (aIsActive != bIsActive) {
      return aIsActive ? -1 : 1;
    }
    final aTime = a.lastOpenedAt;
    final bTime = b.lastOpenedAt;
    if (aTime == null && bTime != null) {
      return 1;
    }
    if (aTime != null && bTime == null) {
      return -1;
    }
    if (aTime != null && bTime != null) {
      final byRecent = bTime.compareTo(aTime);
      if (byRecent != 0) {
        return byRecent;
      }
    }
    final byName = _quickSwitchVaultName(
      a,
    ).toLowerCase().compareTo(_quickSwitchVaultName(b).toLowerCase());
    if (byName != 0) {
      return byName;
    }
    return b.addedAt.compareTo(a.addedAt);
  });
  return copy;
}

Future<void> _confirmLockVault(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lock vault?',
              style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF0B1F26),
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You will need your master password to open this vault again.',
              style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF243047),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _homeInk,
                      side: const BorderSide(color: Color(0xFFD1DEE5)),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: _homeInk,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Lock',
                      style: TextStyle(fontWeight: FontWeight.w700),
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
  if (ok != true || !context.mounted) return;

  // Capture the record BEFORE tearing down providers.
  final lockedRecord = ref.read(homeVaultRecordProvider);
  // Persist any pending background writes before flushing cloud sync so the
  // upload picks up the latest local state.
  await ref.read(vaultWriteSchedulerProvider).flushNow();
  if (!context.mounted) return;
  await _flushCloudSyncBeforeLock(context, lockedRecord);
  if (!context.mounted) return;

  _clearActiveVaultSession(ref);

  if (!context.mounted) return;

  if (lockedRecord != null) {
    _openUnlockForVault(context, lockedRecord);
    return;
  }

  // No matching registry record (shouldn't happen in practice) — fall back
  // to the vault picker so the user has a way forward.
  ref.read(mobileHomeTabProvider.notifier).state = MobileHomeTab.home;
  Navigator.of(
    context,
  ).pushNamedAndRemoveUntil(Routes.vaults, (route) => false);
}

class _CloudSyncLockDialog extends StatelessWidget {
  const _CloudSyncLockDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Syncing your latest vault changes…',
                  style: TextStyle(
                    color: Color(0xFF12232C),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  DateTime? _unlockTime;
  Timer? _autoLockTimer;
  late final AppLifecycleListener _lifecycleListener;
  bool _bottomNavCollapsed = false;
  final ReleaseApiClient _releaseApi = ReleaseApiClient();

  @override
  void initState() {
    super.initState();
    _unlockTime = DateTime.now();

    // Apply pending default-tab from startup router + nudge AutoFill setup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = ref.read(activeHomeTabAfterUnlockProvider);
      if (pending != null) {
        ref.read(mobileHomeTabProvider.notifier).state = pending;
        ref.read(activeHomeTabAfterUnlockProvider.notifier).state = null;
      }
      _promptAutoFillReminder();
    });

    _lifecycleListener = AppLifecycleListener(
      onResume: _resetAutoLockTimer,
      // Persist pending background writes as soon as the app leaves the
      // foreground so a system kill can't discard unflushed edits. The flush
      // is fire-and-forget: the scheduler serializes saves internally and the
      // lock path flushes again (awaited) if the user locks manually.
      onInactive: () =>
          unawaited(ref.read(vaultWriteSchedulerProvider).flushNow()),
      onPause: () =>
          unawaited(ref.read(vaultWriteSchedulerProvider).flushNow()),
    );

    // Arm the auto-lock timer only after persisted settings have loaded from
    // storage. Reading the provider before _load() completes would return the
    // default (fourHours) even when the user saved "Never", causing a spurious
    // lock. The ref.listen in build() re-arms the timer whenever the setting
    // changes, so this deferred call is only needed for the initial arm.
    unawaited(
      ref.read(vaultSecuritySettingsProvider.notifier).loaded.then((_) {
        if (mounted) _resetAutoLockTimer();
      }),
    );

    unawaited(_checkForNewVersionSilently());
  }

  /// Surfaces the "Turn On AutoFill" sheet right after the vault opens if
  /// the provider isn't enabled yet. Delayed by a frame so the HomeScreen
  /// has time to paint before the modal slides in — avoids flashing the
  /// sheet on top of an empty scaffold.
  void _promptAutoFillReminder() {
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      // ignore: discarded_futures
      maybeShowAutoFillReminder(context, ref);
    });
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    _lifecycleListener.dispose();
    _releaseApi.close();
    super.dispose();
  }

  void _resetAutoLockTimer() {
    _autoLockTimer?.cancel();
    final minutes = ref.read(vaultSecuritySettingsProvider).autoLock.minutes;
    if (minutes == null) return; // "Never"

    final lockAt = (_unlockTime ?? DateTime.now()).add(
      Duration(minutes: minutes),
    );
    final remaining = lockAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _doAutoLock();
      return;
    }
    _autoLockTimer = Timer(remaining, _doAutoLock);
  }

  void _doAutoLock() {
    unawaited(_doAutoLockAsync());
  }

  Future<void> _doAutoLockAsync() async {
    if (!mounted) return;
    final lockedRecord = ref.read(homeVaultRecordProvider);
    await ref.read(vaultWriteSchedulerProvider).flushNow();
    if (!mounted) return;
    await _flushCloudSyncBeforeLock(context, lockedRecord);
    if (!mounted) return;
    _clearActiveVaultSession(ref);

    if (lockedRecord != null) {
      _openUnlockForVault(context, lockedRecord);
      return;
    }

    // Fallback only when the registry lost track of the active vault.
    ref.read(mobileHomeTabProvider.notifier).state = MobileHomeTab.home;
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(Routes.vaults, (route) => false);
  }

  void _collapseBottomNav() {
    if (_bottomNavCollapsed || !mounted) return;
    setState(() => _bottomNavCollapsed = true);
  }

  void _expandBottomNav() {
    if (!_bottomNavCollapsed || !mounted) return;
    setState(() => _bottomNavCollapsed = false);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is UserScrollNotification) {
      switch (notification.direction) {
        case ScrollDirection.reverse:
          // Scrolling down -> hide.
          _collapseBottomNav();
        case ScrollDirection.forward:
          // Scrolling up -> show.
          _expandBottomNav();
        case ScrollDirection.idle:
          break;
      }
    }

    return false;
  }

  Future<void> _checkForNewVersionSilently() async {
    String? platformKey;
    if (Platform.isIOS) {
      platformKey = 'ios';
    } else if (Platform.isAndroid) {
      platformKey = 'android';
    }
    if (platformKey == null) return;

    try {
      final info = await AppRuntimeInfoService.load();
      developer.log(
        'version-check: runtime info = $info',
        name: 'version_check',
      );
      if (info == null) return;
      final localCombined = info.buildNumber.isNotEmpty
          ? '${info.version}+${info.buildNumber}'
          : info.version;
      final latest = await _releaseApi.fetchLatest(platform: platformKey);
      developer.log(
        'version-check: latest=${latest.version} local=$localCombined '
        'cmp=${compareReleaseVersions(latest.version, localCombined)}',
        name: 'version_check',
      );
      if (!mounted) return;
      if (compareReleaseVersions(latest.version, localCombined) > 0) {
        AppSnackBar.info(
          context,
          'A new version is available: v${formatReleaseVersion(latest.version)}',
          onTap: () => showVersionChangeLogModal(context, latest),
        );
      }
    } catch (err, stackTrace) {
      developer.log(
        'version-check failed: $err',
        name: 'version_check',
        error: err,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-arm timer when auto-lock setting changes.
    ref.listen(
      vaultSecuritySettingsProvider.select((s) => s.autoLock),
      (previous, next) => _resetAutoLockTimer(),
    );

    ref.listen<bool>(vaultItemsIsDeletingProvider, (previous, next) {
      if (previous == true && next == false && mounted) {
        showVaultFloatingToast(context, 'Entry deleted');
      }
    });

    // When the vault is re-unlocked (database re-opened) after being locked,
    // reset the auto-lock timer so the next lock is scheduled from now.
    ref.listen<dynamic>(activeDatabaseProvider, (previous, next) {
      if (previous == null && next != null) {
        _unlockTime = DateTime.now();
        _resetAutoLockTimer();
        _promptAutoFillReminder();
      }
    });

    final tab = ref.watch(mobileHomeTabProvider);
    final isDeleting = ref.watch(vaultItemsIsDeletingProvider);

    return Scaffold(
      backgroundColor: _homeBackground,
      body: SafeArea(
        top: tab != MobileHomeTab.profile,
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleScrollNotification,
                    child: switch (tab) {
                      MobileHomeTab.home => ListView(
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          _floatingHeaderContentTopPadding,
                          20,
                          _homeContentBottomPadding,
                        ),
                        children: const [
                          _QuickAccessSection(),
                          SizedBox(height: 14),
                          _ProfileSummaryBar(),
                          SizedBox(height: 14),
                          _LastUsedSection(),
                          SizedBox(height: 14),
                          _RecentCreatedSection(),
                          SizedBox(height: 14),
                          _TagsSection(),
                        ],
                      ),
                      MobileHomeTab.items => const VaultItemsTab(),
                      MobileHomeTab.totp => const _TotpTab(),
                      MobileHomeTab.profile => const ProfileTab(),
                    },
                  ),
                ),
              ],
            ),
            if (tab != MobileHomeTab.profile)
              const Positioned(
                left: 10,
                right: 10,
                top: _floatingHeaderTopInset,
                child: _TopBar(),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomNavBar(
                collapsed: _bottomNavCollapsed,
                onExpand: _expandBottomNav,
              ),
            ),
            if (isDeleting)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x55000000),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _AddTotpStep { input, preview, target }

enum _TotpSaveMode { existingItem, newItem }

void showAddTotpOverlay(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      pageBuilder: (ctx, animation, secondaryAnimation) =>
          _AddTotpOverlay(onClose: () => Navigator.of(ctx).pop()),
    ),
  );
}

class _AddTotpOverlay extends ConsumerStatefulWidget {
  const _AddTotpOverlay({required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<_AddTotpOverlay> createState() => _AddTotpOverlayState();
}

class _AddTotpOverlayState extends ConsumerState<_AddTotpOverlay> {
  static const TOTPService _totpService = TOTPService();

  _AddTotpStep _step = _AddTotpStep.input;
  final TextEditingController _manualCtrl = TextEditingController();
  final TextEditingController _itemSearchCtrl = TextEditingController();
  // New-item form controllers (used when _saveMode == newItem).
  final TextEditingController _newTitleCtrl = TextEditingController();
  final TextEditingController _newEmailCtrl = TextEditingController();
  final TextEditingController _newWebsiteCtrl = TextEditingController();
  bool _newItemDefaultsApplied = false;
  Timer? _timer;
  DateTime _now = DateTime.now();
  String? _otpauthUrl;
  String? _error;
  String _itemQuery = '';
  String? _selectedEntryUuid;
  _TotpSaveMode _saveMode = _TotpSaveMode.existingItem;
  bool _isLaunchingScanner = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _timer?.cancel();
    _manualCtrl.dispose();
    _itemSearchCtrl.dispose();
    _newTitleCtrl.dispose();
    _newEmailCtrl.dispose();
    _newWebsiteCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  String? _normalizeOtpAuth(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri?.scheme == 'otpauth') {
      return trimmed;
    }
    final clean = trimmed.replaceAll(' ', '').toUpperCase();
    if (RegExp(r'^[A-Z2-7=]{8,}$').hasMatch(clean)) {
      return 'otpauth://totp/Account?secret=$clean&issuer=Added manually';
    }
    return null;
  }

  ({String issuer, String account}) _parseOtpInfo(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return (issuer: '', account: '');
    }
    final path = Uri.decodeComponent(uri.path.replaceFirst('/', '')).trim();
    String issuer = uri.queryParameters['issuer']?.trim() ?? '';
    String account = path;
    if (path.contains(':')) {
      final parts = path.split(':');
      if (issuer.isEmpty) {
        issuer = parts.first.trim();
      }
      account = parts.sublist(1).join(':').trim();
    }
    if (issuer.isEmpty) {
      issuer = account;
    }
    if (account == issuer) {
      account = '';
    }
    return (issuer: issuer, account: account);
  }

  void _goToPreviewFromInput(String rawInput) {
    final normalized = _normalizeOtpAuth(rawInput);
    if (normalized == null) {
      setState(
        () => _error = 'Enter a valid otpauth:// URL or Base32 TOTP secret.',
      );
      return;
    }
    setState(() {
      _otpauthUrl = normalized;
      _error = null;
      _step = _AddTotpStep.preview;
    });
    _startTimer();
  }

  void _goToPreview() => _goToPreviewFromInput(_manualCtrl.text);

  Future<void> _scanWithCamera() async {
    if (_isLaunchingScanner || _isSaving) return;
    setState(() {
      _isLaunchingScanner = true;
      _error = null;
    });
    final scanned = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _TotpCameraScannerSheet(),
    );
    if (!mounted) return;
    setState(() => _isLaunchingScanner = false);
    if (scanned == null || scanned.trim().isEmpty) return;
    _manualCtrl.text = scanned.trim();
    _goToPreviewFromInput(scanned);
  }

  void _goToTarget() {
    final entries = _sortedEntries(
      ref
          .read(vaultVisibleEntriesProvider)
          .where(_entryIsLoginOrSecureNote)
          .toList(),
    );
    _seedNewItemDefaults();
    setState(() {
      _step = _AddTotpStep.target;
      if (entries.isEmpty) {
        _saveMode = _TotpSaveMode.newItem;
        _selectedEntryUuid = null;
      } else {
        _saveMode = _TotpSaveMode.existingItem;
        _selectedEntryUuid = null;
      }
    });
  }

  /// Pre-fills the new-item form from the parsed otpauth info the first time
  /// the target step is shown, so the title is never blank.
  void _seedNewItemDefaults() {
    if (_newItemDefaultsApplied) return;
    final url = _otpauthUrl;
    if (url == null) return;
    final info = _parseOtpInfo(url);
    if (_newTitleCtrl.text.trim().isEmpty) {
      _newTitleCtrl.text = info.issuer.isNotEmpty
          ? info.issuer
          : (info.account.isNotEmpty ? info.account : 'Authenticator');
    }
    if (_newEmailCtrl.text.trim().isEmpty &&
        info.account.isNotEmpty &&
        info.account.toLowerCase() != 'account') {
      _newEmailCtrl.text = info.account;
    }
    _newItemDefaultsApplied = true;
  }

  bool _isOtpFieldKey(String key) {
    final normalized = key.trim().toLowerCase();
    return normalized == 'otp' ||
        normalized == 'otpauth' ||
        normalized == 'otp auth' ||
        normalized.contains('otpauth') ||
        normalized.contains('otp auth');
  }

  String _preferredOtpFieldKey(KdbxEntry entry) {
    for (final field in entry.fields) {
      if (_isOtpFieldKey(field.key)) return field.key;
    }
    return 'otp';
  }

  List<KdbxEntry> _sortedEntries(List<KdbxEntry> entries) {
    final copy = List<KdbxEntry>.of(entries);
    copy.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return copy;
  }

  List<KdbxEntry> _filterEntries(List<KdbxEntry> entries, String query) {
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    if (terms.isEmpty) return entries;
    return entries
        .where((entry) {
          final haystack = [
            entry.title,
            entry.username ?? '',
            entry.url ?? '',
            entry.notes ?? '',
            ...entry.tags,
          ].join(' ').toLowerCase();
          return terms.every(haystack.contains);
        })
        .toList(growable: false);
  }

  Future<void> _saveToExistingItem({
    required KdbxEntry entry,
    required String otpAuthUrl,
  }) async {
    final repository = ref.read(kdbxRepositoryProvider);
    final preserved = <EntryField>[
      for (final field in entry.fields)
        if (!_isOtpFieldKey(field.key)) field,
    ];
    preserved.add(
      EntryField(
        key: _preferredOtpFieldKey(entry),
        value: otpAuthUrl,
        isProtected: true,
        isStandard: true,
      ),
    );
    await repository.updateEntry(
      entryUuid: entry.uuid,
      fields: preserved,
      notes: entry.notes,
      tags: List<String>.unmodifiable(entry.tags),
    );
  }

  Future<void> _createNewItemWithTotp({required String otpAuthUrl}) async {
    final repository = ref.read(kdbxRepositoryProvider);
    final categories = ref.read(vaultSidebarCategoriesProvider);
    final selectedGroupUuid = ref.read(vaultSelectedGroupProvider);
    final targetGroupUuid = resolveEffectiveCategoryUuid(
      categories: categories,
      rootGroupUuid: repository.rootGroupUuid,
      selectedGroupUuid: selectedGroupUuid,
    );
    if (targetGroupUuid == null || targetGroupUuid.isEmpty) {
      throw const VaultStateException('Select a category before saving');
    }

    final title = _newTitleCtrl.text.trim();
    final email = _newEmailCtrl.text.trim();
    final website = _newWebsiteCtrl.text.trim();
    final fields = <EntryField>[
      EntryField(key: AppKdbxFieldKeys.title, value: title, isStandard: true),
      if (email.isNotEmpty)
        EntryField(
          key: AppKdbxFieldKeys.userName,
          value: email,
          isStandard: true,
        ),
      if (website.isNotEmpty && website != 'https://')
        EntryField(key: AppKdbxFieldKeys.url, value: website, isStandard: true),
      EntryField(
        key: 'otp',
        value: otpAuthUrl,
        isProtected: true,
        isStandard: true,
      ),
    ];

    await repository.createEntry(groupUuid: targetGroupUuid, fields: fields);
  }

  Future<void> _confirmAddTotp() async {
    final url = _otpauthUrl;
    if (url == null || url.trim().isEmpty || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      final entries = _sortedEntries(
        ref
            .read(vaultVisibleEntriesProvider)
            .where(_entryIsLoginOrSecureNote)
            .toList(),
      );
      if (_saveMode == _TotpSaveMode.existingItem) {
        final selectedUuid = _selectedEntryUuid;
        if (selectedUuid == null) {
          throw const VaultStateException('Select an item to add 2FA');
        }
        KdbxEntry? selected;
        for (final entry in entries) {
          if (entry.uuid == selectedUuid) {
            selected = entry;
            break;
          }
        }
        if (selected == null) {
          throw const VaultStateException('Selected item was not found');
        }
        await _saveToExistingItem(entry: selected, otpAuthUrl: url);
      } else {
        if (_newTitleCtrl.text.trim().isEmpty) {
          throw const VaultStateException('Title is required');
        }
        await _createNewItemWithTotp(otpAuthUrl: url);
      }

      final repository = ref.read(kdbxRepositoryProvider);
      publishAndScheduleSave(ref, repository);

      if (!mounted) return;
      final success = _saveMode == _TotpSaveMode.existingItem
          ? '2FA code added to item'
          : 'New item with 2FA created';
      AppSnackBar.success(context, success);
      widget.onClose();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppSnackBar.error(context, 'Unable to add 2FA code: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: widget.onClose,
        child: Container(
          color: const Color(0x52000000),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
          child: GestureDetector(
            onTap: () {},
            child: switch (_step) {
              _AddTotpStep.input => _buildInputStep(context),
              _AddTotpStep.preview => _buildPreviewStep(context),
              _AddTotpStep.target => _buildTargetStep(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInputStep(BuildContext context) {
    final canContinue = _manualCtrl.text.trim().isNotEmpty;

    return Container(
      width: MediaQuery.sizeOf(context).width - 32,
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDADFE8)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1C172033),
            blurRadius: 44,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Add 2FA Code',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF202939),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Color(0xFF6E7687),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Scan QR with camera or paste an otpauth URL/setup key manually.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF667085),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isLaunchingScanner ? null : _scanWithCamera,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0A3B48),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: _isLaunchingScanner
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.qr_code_scanner_rounded, size: 18),
            label: Text(
              _isLaunchingScanner ? 'Opening camera...' : 'Scan QR With Camera',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(child: Divider(color: Color(0xFFE4E9F2))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'or enter manually',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8A97AC),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: Color(0xFFE4E9F2))),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _manualCtrl,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _goToPreview(),
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'otpauth://totp/... or TOTP secret (Base32)',
              hintStyle: const TextStyle(
                color: Color(0xFF98A2B3),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              fillColor: const Color(0xFFF7F9FB),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD8DEE8)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD8DEE8)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF4B6CFF)),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFE53E3E),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onClose,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3E4A5E),
                    side: const BorderSide(color: Color(0xFFD6DCE6)),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: canContinue ? _goToPreview : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0A3B48),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewStep(BuildContext context) {
    final url = _otpauthUrl!;
    final info = _parseOtpInfo(url);
    final rawCode = _totpService.generateCode(url, timestamp: _now);
    final formattedCode = _formatTotpCode(rawCode);
    final seconds = _totpService.secondsRemaining(url, timestamp: _now);
    final countdownColor = _totpCountdownColor(seconds);
    final progress = seconds / 30.0;

    return Container(
      width: MediaQuery.sizeOf(context).width - 32,
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDADFE8)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1C172033),
            blurRadius: 44,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () {
                  setState(() => _step = _AddTotpStep.input);
                },
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 18,
                    color: Color(0xFF6E7687),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Add 2FA Code',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF202939),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Color(0xFF6E7687),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 16,
                  color: Color(0xFF059669),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '2FA code ready to add',
                    style: TextStyle(
                      color: Color(0xFF065F46),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (info.issuer.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              info.issuer,
              style: const TextStyle(
                color: Color(0xFF202939),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (info.account.isNotEmpty)
              Text(
                info.account,
                style: const TextStyle(
                  color: Color(0xFF73839D),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E9F2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current TOTP Code',
                  style: TextStyle(
                    color: Color(0xFF8A97AC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      formattedCode,
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        height: 1,
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${seconds.toString().padLeft(2, '0')}s',
                          style: TextStyle(
                            color: countdownColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 78,
                          height: 4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: const Color(0xFFE8EDF5),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                countdownColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onClose,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3E4A5E),
                    side: const BorderSide(color: Color(0xFFD6DCE6)),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Dismiss'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _isSaving ? null : _goToTarget,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0A3B48),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text('Next'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTargetStep(BuildContext context) {
    final entries = _sortedEntries(
      ref
          .watch(vaultVisibleEntriesProvider)
          .where(_entryIsLoginOrSecureNote)
          .toList(),
    );
    final filteredEntries = _filterEntries(entries, _itemQuery);
    final hasEntries = entries.isNotEmpty;
    final url = _otpauthUrl!;
    final info = _parseOtpInfo(url);
    final rawCode = _totpService.generateCode(url, timestamp: _now);
    final formattedCode = _formatTotpCode(rawCode);
    final seconds = _totpService.secondsRemaining(url, timestamp: _now);
    final countdownColor = _totpCountdownColor(seconds);
    final canSave =
        !_isSaving &&
        (_saveMode == _TotpSaveMode.newItem || _selectedEntryUuid != null);

    return Container(
      width: MediaQuery.sizeOf(context).width - 32,
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDADFE8)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1C172033),
            blurRadius: 44,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => setState(() => _step = _AddTotpStep.preview),
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 18,
                    color: Color(0xFF6E7687),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Save 2FA Code',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF202939),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Color(0xFF6E7687),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5EAF1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (info.issuer.isNotEmpty)
                        Text(
                          info.issuer,
                          style: const TextStyle(
                            color: Color(0xFF202939),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (info.account.isNotEmpty)
                        Text(
                          info.account,
                          style: const TextStyle(
                            color: Color(0xFF73839D),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        formattedCode,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: countdownColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${seconds.toString().padLeft(2, '0')}s',
                    style: TextStyle(
                      color: countdownColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F6FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD6DCE6)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: hasEntries
                        ? () => setState(
                            () => _saveMode = _TotpSaveMode.existingItem,
                          )
                        : null,
                    child: Container(
                      alignment: Alignment.center,
                      color: _saveMode == _TotpSaveMode.existingItem
                          ? const Color(0xFF0A3B48)
                          : Colors.transparent,
                      child: Text(
                        'Add To Existing Item',
                        style: TextStyle(
                          color: _saveMode == _TotpSaveMode.existingItem
                              ? Colors.white
                              : const Color(0xFF475467),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                Container(width: 1, color: const Color(0xFFD6DCE6)),
                Expanded(
                  child: InkWell(
                    onTap: () =>
                        setState(() => _saveMode = _TotpSaveMode.newItem),
                    child: Container(
                      alignment: Alignment.center,
                      color: _saveMode == _TotpSaveMode.newItem
                          ? const Color(0xFF0A3B48)
                          : Colors.transparent,
                      child: Text(
                        'Create New Item',
                        style: TextStyle(
                          color: _saveMode == _TotpSaveMode.newItem
                              ? Colors.white
                              : const Color(0xFF475467),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_saveMode == _TotpSaveMode.existingItem) ...[
            TextField(
              controller: _itemSearchCtrl,
              onChanged: (value) => setState(() => _itemQuery = value),
              style: const TextStyle(
                color: Color(0xFF1F2937),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Search item to attach this 2FA',
                hintStyle: const TextStyle(
                  color: Color(0xFF98A2B3),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: Color(0xFF6E8A93),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                fillColor: const Color(0xFFF7F9FB),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFD8DEE8)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFD8DEE8)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF4B6CFF)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE4E9F2)),
              ),
              clipBehavior: Clip.antiAlias,
              child: !hasEntries
                  ? const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      child: Text(
                        'No items found in this vault. Choose "Create New Item".',
                        style: TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : filteredEntries.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      child: Text(
                        'No matching items',
                        style: TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      primary: false,
                      padding: EdgeInsets.zero,
                      itemCount: filteredEntries.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1, color: Color(0xFFF0F3F8)),
                      itemBuilder: (context, index) {
                        final entry = filteredEntries[index];
                        final selected = entry.uuid == _selectedEntryUuid;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () =>
                                setState(() => _selectedEntryUuid = entry.uuid),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  VaultEntryAvatar(entry: entry, size: 28),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      entry.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF163640),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    selected
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    size: 18,
                                    color: selected
                                        ? const Color(0xFF0A3B48)
                                        : const Color(0xFF9AA7BA),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ] else ...[
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LoginFormField(
                      label: 'title',
                      controller: _newTitleCtrl,
                      icon: Icons.title_rounded,
                      iconColor: const Color(0xFF0A3B48),
                      hintText: 'Item title (required)',
                    ),
                    const SizedBox(height: 12),
                    LoginFormField(
                      label: 'email',
                      controller: _newEmailCtrl,
                      icon: Icons.alternate_email_rounded,
                      iconColor: const Color(0xFF5C7CFA),
                      hintText: 'name@example.com (optional)',
                    ),
                    const SizedBox(height: 12),
                    LoginFormField(
                      label: 'website / url',
                      controller: _newWebsiteCtrl,
                      icon: Icons.public_rounded,
                      iconColor: const Color(0xFF635BDB),
                      hintText: 'https://example.com (optional)',
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving
                      ? null
                      : () => setState(() => _step = _AddTotpStep.preview),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3E4A5E),
                    side: const BorderSide(color: Color(0xFFD6DCE6)),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: canSave ? _confirmAddTotp : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0A3B48),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _isSaving
                        ? 'Saving...'
                        : (_saveMode == _TotpSaveMode.existingItem
                              ? 'Add To Item'
                              : 'Create Item'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotpCameraScannerSheet extends StatefulWidget {
  const _TotpCameraScannerSheet();

  @override
  State<_TotpCameraScannerSheet> createState() =>
      _TotpCameraScannerSheetState();
}

class _TotpCameraScannerSheetState extends State<_TotpCameraScannerSheet> {
  late final MobileScannerController _controller;
  bool _handled = false;
  bool _torchOn = false;
  bool _frontCamera = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw == null || raw.isEmpty) continue;
      _handled = true;
      Navigator.of(context).pop(raw);
      return;
    }
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (!mounted) return;
    setState(() => _torchOn = !_torchOn);
  }

  Future<void> _switchCamera() async {
    await _controller.switchCamera();
    if (!mounted) return;
    setState(() => _frontCamera = !_frontCamera);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.86,
        decoration: const BoxDecoration(
          color: Color(0xFF0C1820),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
              child: Row(
                children: [
                  const Text(
                    'Scan TOTP QR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _toggleTorch,
                    icon: Icon(
                      _torchOn
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: _switchCamera,
                    icon: Icon(
                      _frontCamera
                          ? Icons.camera_rear_rounded
                          : Icons.camera_front_rounded,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        errorBuilder: (context, error) {
                          return Container(
                            color: const Color(0xFF101A23),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'Camera unavailable. Please allow camera permission in settings, or use manual input.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          );
                        },
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 240,
                            height: 240,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xAAFFFFFF),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 18),
              child: Text(
                'Point the camera at the QR code',
                style: TextStyle(
                  color: Color(0xFFD6E1EC),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _homeText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: _homeMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotpTab extends ConsumerStatefulWidget {
  const _TotpTab();

  @override
  ConsumerState<_TotpTab> createState() => _TotpTabState();
}

class _TotpTabState extends ConsumerState<_TotpTab>
    with WidgetsBindingObserver {
  static const _totp = TOTPService();
  Timer? _clock;

  /// Broadcast ticker. Using a [ValueNotifier] instead of `setState` on every
  /// tick means only the rows that actually show the TOTP countdown rebuild
  /// each second — the surrounding tab, search bar, and entry list stay put.
  late final ValueNotifier<DateTime> _nowNotifier;

  // Cache TOTP codes per entry — codes only rotate every 30 s.
  final Map<String, String?> _codeCache = {};
  int _lastWindow = -1;

  @override
  void initState() {
    super.initState();
    _nowNotifier = ValueNotifier<DateTime>(DateTime.now());
    WidgetsBinding.instance.addObserver(this);
    _startClock();
  }

  @override
  void deactivate() {
    // Fired when the element is removed (tab switch, navigation pop, etc).
    // Stop the ticker immediately so we never tick after the user has left
    // this tab, even in the brief window before `dispose` runs.
    _stopClock();
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopClock();
    _nowNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause the per-second ticker whenever the app is not in the foreground
    // — avoids burning CPU and scheduling frame callbacks while nothing on
    // this screen is visible.
    switch (state) {
      case AppLifecycleState.resumed:
        _startClock();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _stopClock();
        break;
    }
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _stopClock();
        return;
      }
      _nowNotifier.value = DateTime.now();
    });
  }

  void _stopClock() {
    _clock?.cancel();
    _clock = null;
  }

  String? _cachedCode(KdbxEntry entry, DateTime now) {
    final window = now.millisecondsSinceEpoch ~/ 30000;
    if (window != _lastWindow) {
      _codeCache.clear();
      _lastWindow = window;
    }
    return _codeCache.putIfAbsent(
      entry.uuid,
      () => _totp.generateCode(entry.otpAuthUrl, timestamp: now),
    );
  }

  /// Long-press action sheet for a TOTP row: Edit or Delete.
  /// Styled to match the Password Generator sheet (bottom-up slide, white
  /// header card with grab handle, icon + title, circular close button).
  Future<void> _showTotpActions(KdbxEntry entry) async {
    final action = await showModalBottomSheet<_TotpRowAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottom = MediaQuery.paddingOf(sheetContext).bottom;
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Color(0x290A2F3D),
                blurRadius: 24,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(bottom: BorderSide(color: Color(0xFFE1EAF0))),
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCE6EC),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.only(right: 54),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE5EFF3),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.timelapse_rounded,
                                    color: Color(0xFF0A3B48),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    entry.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: _homeText,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 16,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x180F172A),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.white,
                          shape: const CircleBorder(
                            side: BorderSide(color: Color(0xFFD7E2E8)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Navigator.of(sheetContext).pop(),
                            customBorder: const CircleBorder(),
                            child: const SizedBox(
                              width: 38,
                              height: 38,
                              child: Icon(
                                Icons.close_rounded,
                                color: Color(0xFF5E7180),
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(8, 8, 8, 12 + bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TotpActionTile(
                      icon: Icons.edit_rounded,
                      label: 'Edit Item',
                      description: 'Update name, credentials, or details',
                      onTap: () =>
                          Navigator.of(sheetContext).pop(_TotpRowAction.edit),
                    ),
                    _TotpActionTile(
                      icon: Icons.delete_rounded,
                      label: 'Delete Item',
                      description: 'Permanently remove this item',
                      isDestructive: true,
                      onTap: () =>
                          Navigator.of(sheetContext).pop(_TotpRowAction.delete),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    switch (action) {
      case _TotpRowAction.edit:
        showEditItemModal(context, entry: entry);
        break;
      case _TotpRowAction.delete:
        await _confirmDeleteTotp(entry);
        break;
      case null:
        break;
    }
  }

  Future<void> _confirmDeleteTotp(KdbxEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text(
          'Are you sure you want to permanently delete "${entry.title}"? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB42318),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    ref.read(vaultItemsIsDeletingProvider.notifier).state = true;
    try {
      final repo = ref.read(kdbxRepositoryProvider);
      await repo.deleteEntry(entry.uuid);
      publishAndScheduleSave(ref, repo);
      if (!mounted) return;
      AppSnackBar.success(context, 'Deleted ${entry.title}');
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, 'Failed to delete: $e');
    } finally {
      if (mounted) {
        ref.read(vaultItemsIsDeletingProvider.notifier).state = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(vaultVisibleEntriesProvider);
    final totpEntries =
        entries
            .where((e) => _entryIsLoginOrSecureNote(e) && entryHasTotp(e))
            .toList(growable: false)
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );
    final filtered = totpEntries;

    return Stack(
      children: [
        Positioned.fill(
          child: totpEntries.isEmpty
              ? const _PlaceholderTab(
                  title: 'TOTP',
                  message: 'No items with TOTP in this vault yet.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    _floatingHeaderContentTopPadding,
                    20,
                    _homeContentBottomPadding,
                  ),
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    // Each row subscribes individually to the tick so only
                    // the row body rebuilds every second — the list and
                    // surrounding chrome do not.
                    return RepaintBoundary(
                      child: ValueListenableBuilder<DateTime>(
                        valueListenable: _nowNotifier,
                        builder: (context, now, _) {
                          final rawCode = _cachedCode(entry, now);
                          final secondsRemaining = _totp.secondsRemaining(
                            entry.otpAuthUrl,
                            timestamp: now,
                          );
                          final code = _formatTotpCode(rawCode);
                          final accent = _totpCountdownColor(secondsRemaining);

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                final rawToCopy = (rawCode ?? '').replaceAll(
                                  RegExp(r'\s+'),
                                  '',
                                );
                                if (rawToCopy.isEmpty) {
                                  return;
                                }
                                await Clipboard.setData(
                                  ClipboardData(text: rawToCopy),
                                );
                                if (!context.mounted) return;
                                AppSnackBar.success(
                                  context,
                                  'Copied TOTP for ${entry.title}',
                                );
                              },
                              onLongPress: () {
                                HapticFeedback.mediumImpact();
                                _showTotpActions(entry);
                              },
                              child: Ink(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: _homeSurface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _homeBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        VaultEntryAvatar(
                                          entry: entry,
                                          size: 34,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            entry.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: _homeText,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: accent.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.timer_outlined,
                                                size: 13,
                                                color: accent,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${secondsRemaining.toString().padLeft(2, '0')}s',
                                                style: TextStyle(
                                                  color: accent,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      code,
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: 34,
                                        height: 1,
                                        letterSpacing: 1.1,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemCount: filtered.length,
                ),
        ),
      ],
    );
  }
}

String _formatTotpCode(String? raw) {
  final value = (raw ?? '').replaceAll(RegExp(r'\s+'), '');
  if (value.length == 6) {
    return '${value.substring(0, 3)} ${value.substring(3)}';
  }
  return value.isEmpty ? '------' : value;
}

Color _totpCountdownColor(int secondsRemaining) {
  if (secondsRemaining <= 9) {
    return const Color(0xFFDC2626);
  }
  if (secondsRemaining <= 15) {
    return const Color(0xFFF59E0B);
  }
  return const Color(0xFF16A34A);
}

enum _TotpRowAction { edit, delete }

class _TotpActionTile extends StatelessWidget {
  const _TotpActionTile({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? const Color(0xFFB42318) : _homeText;
    return Semantics(
      button: true,
      label: label,
      hint: description,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: _homeMuted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _VaultMenuAction {
  addItem,
  generatePassword,
  settings,
  switchVault,
  lockVault,
}

void _handleVaultMenuAction(
  BuildContext context,
  WidgetRef ref,
  _VaultMenuAction action,
) {
  switch (action) {
    case _VaultMenuAction.addItem:
      showAddNewItemOverlay(context);
      break;
    case _VaultMenuAction.generatePassword:
      showPasswordGeneratorModal(context);
      break;
    case _VaultMenuAction.settings:
      showVaultSettingsModal(context);
      break;
    case _VaultMenuAction.switchVault:
      _showQuickSwitchVaultSheet(context, ref);
      break;
    case _VaultMenuAction.lockVault:
      _confirmLockVault(context, ref);
      break;
  }
}

PopupMenuItem<_VaultMenuAction> _vaultMenuItem(
  _VaultMenuAction value,
  IconData icon,
  String label, {
  bool enabled = true,
}) {
  return PopupMenuItem<_VaultMenuAction>(
    value: value,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: 20, color: enabled ? _homeInk : _homeMuted),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: enabled ? _homeText : _homeMuted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Paints a soft drop shadow that appears only *outside* a rounded-rect
/// footprint. Uses [Canvas.drawShadow] with an opaque occluder so the shadow
/// never bleeds through a translucent child (e.g. a glass surface).
class _OuterShadow extends StatelessWidget {
  const _OuterShadow({
    required this.borderRadius,
    required this.child,
    this.color = const Color(0x2E0B2430),
    this.elevation = 10,
  });

  final double borderRadius;
  final Widget child;
  final Color color;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OuterShadowPainter(
        borderRadius: borderRadius,
        color: color,
        elevation: elevation,
      ),
      child: child,
    );
  }
}

class _OuterShadowPainter extends CustomPainter {
  _OuterShadowPainter({
    required this.borderRadius,
    required this.color,
    required this.elevation,
  });

  final double borderRadius;
  final Color color;
  final double elevation;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(borderRadius),
        ),
      );
    canvas.drawShadow(path, color, elevation, false);
  }

  @override
  bool shouldRepaint(_OuterShadowPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius ||
        oldDelegate.color != color ||
        oldDelegate.elevation != elevation;
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(homeVaultTitleProvider);
    final storageType = ref.watch(homeVaultStorageTypeProvider);
    final vaultIconAsset = _vaultStorageIconAsset(storageType);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 20;

        return _OuterShadow(
          borderRadius: 22,
          color: const Color(0xFF0B2430).withValues(alpha: 0.20),
          elevation: 12,
          child: GlassSurface(
            height: _floatingHeaderHeight,
            width: width,
            borderRadius: 22,
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
            shadowOpacity: 0,
            shadowBlurRadius: 0,
            shadowSpreadRadius: 0,
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
                          vaultIconAsset,
                          width: 22,
                          height: 22,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: const Color(0xFF0B1F26),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<_VaultMenuAction>(
                      tooltip: 'Menu',
                      offset: const Offset(0, 56),
                      color: Colors.white,
                      elevation: 12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: EdgeInsets.zero,
                      onSelected: (action) =>
                          _handleVaultMenuAction(context, ref, action),
                      itemBuilder: (context) => [
                        _vaultMenuItem(
                          _VaultMenuAction.addItem,
                          Icons.add_rounded,
                          'Add Item',
                        ),
                        _vaultMenuItem(
                          _VaultMenuAction.generatePassword,
                          Icons.key_outlined,
                          'Generate Password',
                        ),
                        _vaultMenuItem(
                          _VaultMenuAction.settings,
                          Icons.settings_outlined,
                          'Settings',
                        ),
                        _vaultMenuItem(
                          _VaultMenuAction.switchVault,
                          Icons.swap_horiz_rounded,
                          'Switch Vault',
                        ),
                        _vaultMenuItem(
                          _VaultMenuAction.lockVault,
                          Icons.lock_outline_rounded,
                          'Lock Vault',
                        ),
                      ],
                      child: const _IconAction(
                        icon: Icons.menu_rounded,
                        semanticLabel: 'Menu',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuickSwitchVaultSheet extends ConsumerWidget {
  const _QuickSwitchVaultSheet({required this.onVaultSelected});

  final ValueChanged<DatabaseRecord> onVaultSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(databaseRegistryProvider);
    final activeRecord = ref.watch(homeVaultRecordProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final activePath =
        ref.watch(
          activeDatabaseProvider.select((database) => database?.path),
        ) ??
        activeRecord?.databasePath;
    final sortedVaults = _sortedQuickSwitchVaults(
      registry,
      activeRecord: activeRecord,
      activePath: activePath,
    );
    final hasAnotherVault = sortedVaults.any(
      (record) => !_isActiveQuickSwitchVault(
        record,
        activeRecord: activeRecord,
        activePath: activePath,
      ),
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF7FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x290A2F3D),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: Color(0xFFE1EAF0))),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD2DCE2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.only(right: 54),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE5EFF3),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.swap_horiz_rounded,
                                size: 20,
                                color: _homeInk,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Switch Vault',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: const Color(0xFF0B1F26),
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    hasAnotherVault
                                        ? 'Pick another vault to unlock.'
                                        : 'No other vaults are available yet.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: const Color(0xFF667787),
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 16,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x180F172A),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(
                        side: BorderSide(color: Color(0xFFD7E2E8)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        customBorder: const CircleBorder(),
                        child: const SizedBox(
                          width: 38,
                          height: 38,
                          child: Icon(
                            Icons.close_rounded,
                            color: Color(0xFF5E7180),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + bottomInset),
              child: sortedVaults.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
                        child: Text(
                          'Add another vault from the vault picker to use quick switch.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: _homeMuted,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
                      shrinkWrap: true,
                      itemBuilder: (context, index) {
                        final record = sortedVaults[index];
                        final isActive = _isActiveQuickSwitchVault(
                          record,
                          activeRecord: activeRecord,
                          activePath: activePath,
                        );
                        return _QuickSwitchVaultTile(
                          record: record,
                          isActive: isActive,
                          onTap: isActive
                              ? null
                              : () => onVaultSelected(record),
                        );
                      },
                      separatorBuilder: (_, index) => const SizedBox(height: 8),
                      itemCount: sortedVaults.length,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickSwitchVaultTile extends StatelessWidget {
  const _QuickSwitchVaultTile({
    required this.record,
    required this.isActive,
    this.onTap,
  });

  final DatabaseRecord record;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final background = isActive ? const Color(0xFFE9F3FF) : Colors.white;
    final borderColor = isActive
        ? const Color(0xFF6EA8FF)
        : const Color(0xFFE2EAF0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F6F8),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Image.asset(
                  _vaultStorageIconAsset(record.storageType),
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _quickSwitchVaultName(record),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF122630),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _quickSwitchVaultLocationLabel(record),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF627685),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F7FEA),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Current',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1F26),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Switch',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, this.semanticLabel});

  final IconData icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);

    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        width: 48,
        height: 48,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0B2430).withValues(alpha: 0.12),
                blurRadius: 14,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                color: Colors.white,
                border: Border.all(
                  color: const Color(0xFF0B2430).withValues(alpha: 0.08),
                ),
              ),
              child: Icon(icon, size: 23, color: _homeInk),
            ),
          ),
        ),
      ),
    );
  }
}

class _LastUsedSection extends ConsumerWidget {
  const _LastUsedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(homeRecentEntriesProvider);
    final query = ref.watch(vaultSearchQueryProvider).trim();
    final emptyMessage = query.isNotEmpty
        ? 'No matching items'
        : 'No items in this vault';

    return _HomeEntryCard(
      title: 'Recent Used',
      icon: Icons.history_rounded,
      entries: recent,
      emptyMessage: emptyMessage,
      ref: ref,
    );
  }
}

class _ProfileSummaryBar extends ConsumerWidget {
  const _ProfileSummaryBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final greeting = _profileSummaryGreeting(DateTime.now());

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          ref.read(mobileHomeTabProvider.notifier).state =
              MobileHomeTab.profile;
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: _homeSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE6EDF2)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0B2430).withValues(alpha: 0.05),
                blurRadius: 16,
                spreadRadius: -8,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F1FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.settings_outlined,
                  color: Color(0xFF3366D6),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      greeting,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _homeText,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Manage vault security and app settings",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _homeMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: _homeMuted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _profileSummaryGreeting(DateTime now) {
  final hour = now.hour;
  if (hour < 12) return "Good morning";
  if (hour < 18) return "Good afternoon";
  return "Good evening";
}

class _RecentCreatedSection extends ConsumerWidget {
  const _RecentCreatedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(homeRecentCreatedEntriesProvider);
    final query = ref.watch(vaultSearchQueryProvider).trim();
    final emptyMessage = query.isNotEmpty
        ? 'No matching items'
        : 'No recently created items yet';
    final now = DateTime.now();

    return _HomeEntryCard(
      title: 'Recent Created',
      icon: Icons.add_circle_outline_rounded,
      entries: recent,
      emptyMessage: emptyMessage,
      ref: ref,
      dateLabelForEntry: (entry) => formatVaultEntryListDateLabel(
        now: now,
        updatedAt: null,
        createdAt: entry.createdAt,
      ),
    );
  }
}

class _HomeEntryCard extends StatelessWidget {
  const _HomeEntryCard({
    required this.title,
    required this.icon,
    required this.entries,
    required this.emptyMessage,
    required this.ref,
    this.dateLabelForEntry,
  });

  final String title;
  final IconData icon;
  final List<KdbxEntry> entries;
  final String emptyMessage;
  final WidgetRef ref;
  final String Function(KdbxEntry entry)? dateLabelForEntry;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _homeSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EDF2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: const Color(0xFF4B8591)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: _homeText,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE6EDF2)),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Center(
                child: Text(
                  emptyMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _homeMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
          else
            Column(
              children: [
                for (var i = 0; i < entries.length; i++)
                  VaultEntryListTile(
                    entry: entries[i],
                    selected: false,
                    showBottomBorder: i < entries.length - 1,
                    titleFontSize: 14,
                    dateLabelOverride: dateLabelForEntry?.call(entries[i]),
                    onTap: () async {
                      final categories = ref.read(
                        vaultSidebarCategoriesProvider,
                      );
                      String? categoryName;
                      for (final c in categories) {
                        if (c.uuid == entries[i].groupUuid) {
                          categoryName = c.name;
                          break;
                        }
                      }
                      ref
                          .read(vaultItemsSelectedEntryUuidProvider.notifier)
                          .state = entries[i]
                          .uuid;
                      await showItemDetailsModal(
                        context,
                        entry: entries[i],
                        categoryName: categoryName,
                      );
                    },
                    onLongPress: () =>
                        _showHomeContextMenu(context, ref, entries[i]),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

void _showHomeContextMenu(
  BuildContext context,
  WidgetRef ref,
  KdbxEntry entry,
) {
  ref.read(vaultItemsSelectedEntryUuidProvider.notifier).state = entry.uuid;
  showVaultEntryContextMenuDialog(
    context,
    entry: entry,
    onItemSaved: (uuid) {
      ref.read(vaultItemsSelectedEntryUuidProvider.notifier).state = uuid;
    },
  );
}

class _QuickAccessSection extends ConsumerWidget {
  const _QuickAccessSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(homeQuickAccessCountsProvider);
    final cards = [
      _QuickCardData(
        title: 'All items',
        count: _formatStatisticCount(counts.all),
        icon: Icons.inventory_2_outlined,
        startColor: const Color(0xFF53B76C),
        endColor: const Color(0xFF2D8E55),
        accentColor: const Color(0xFFB6F2C6),
        iconBackground: const Color(0xFFDDF7E4),
        onTap: () => openVaultAllItemsScreen(context),
      ),
      _QuickCardData(
        title: 'Credit Cards',
        count: _formatStatisticCount(counts.creditCards),
        icon: Icons.credit_card_rounded,
        startColor: const Color(0xFF4C78FF),
        endColor: const Color(0xFF2E57D7),
        accentColor: const Color(0xFFBCD2FF),
        iconBackground: const Color(0xFFDCE8FF),
        onTap: () => openVaultAllItemsScreen(
          context,
          title: 'Credit Cards',
          itemTypeId: 'credit-card',
        ),
      ),
      _QuickCardData(
        title: 'TOTP',
        count: _formatStatisticCount(counts.totp),
        icon: Icons.timer_outlined,
        startColor: const Color(0xFFFF9A3D),
        endColor: const Color(0xFFE06724),
        accentColor: const Color(0xFFFFD3A8),
        iconBackground: const Color(0xFFFFE8CF),
        onTap: () {
          ref.read(mobileHomeTabProvider.notifier).state = MobileHomeTab.totp;
        },
      ),
      _QuickCardData(
        title: 'Secure Notes',
        count: _formatStatisticCount(counts.secureNotes),
        icon: Icons.sticky_note_2_outlined,
        startColor: const Color(0xFF8F62E8),
        endColor: const Color(0xFF6B43C6),
        accentColor: const Color(0xFFD7C2FF),
        iconBackground: const Color(0xFFEEE5FF),
        onTap: () => openVaultAllItemsScreen(
          context,
          title: 'Secure Notes',
          itemTypeId: 'secure-note',
        ),
      ),
    ];

    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return _QuickAccessCard(card: cards[index]);
        },
      ),
    );
  }
}

String _formatStatisticCount(int value) {
  final formatted = NumberFormat.decimalPattern('en').format(value);
  return formatted.replaceAll(',', '.');
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({required this.card});

  final _QuickCardData card;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 214,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [card.startColor, card.endColor],
            ),
            boxShadow: [
              BoxShadow(
                color: card.endColor.withValues(alpha: 0.22),
                blurRadius: 18,
                spreadRadius: -6,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: InkWell(
            onTap: card.onTap,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _QuickAccessBackdropPainter(
                      accentColor: card.accentColor,
                      iconBackground: card.iconBackground,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: card.iconBackground.withValues(
                                alpha: 0.92,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              card.icon,
                              size: 18,
                              color: card.endColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              card.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        card.count,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 30,
                              height: 1,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'items',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.86),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickAccessBackdropPainter extends CustomPainter {
  const _QuickAccessBackdropPainter({
    required this.accentColor,
    required this.iconBackground,
  });

  final Color accentColor;
  final Color iconBackground;

  @override
  void paint(Canvas canvas, Size size) {
    final softPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final glowPaint = Paint()
      ..color = iconBackground.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(size.width - 26, 30), 42, softPaint);
    canvas.drawCircle(Offset(size.width - 58, size.height - 18), 52, glowPaint);
    canvas.drawCircle(Offset(size.width - 36, size.height - 28), 28, ringPaint);

    final chipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width - 90, 20, 36, 14),
      const Radius.circular(10),
    );
    canvas.drawRRect(chipRect, softPaint);

    final orbRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width - 108, size.height - 52, 58, 22),
      const Radius.circular(18),
    );
    canvas.drawRRect(orbRect, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _QuickAccessBackdropPainter oldDelegate) {
    return oldDelegate.accentColor != accentColor ||
        oldDelegate.iconBackground != iconBackground;
  }
}

class _TagsSection extends ConsumerWidget {
  const _TagsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(homePopularTagsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tags',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: _homeText,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (tags.isEmpty)
          Text(
            'No tags yet',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _homeMuted,
              fontWeight: FontWeight.w500,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags
                .map(
                  (tag) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCEEF2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tag,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _homeInk,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _BottomNavBar extends ConsumerStatefulWidget {
  const _BottomNavBar({required this.collapsed, required this.onExpand});

  final bool collapsed;
  final VoidCallback onExpand;

  @override
  ConsumerState<_BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends ConsumerState<_BottomNavBar> {
  static const _fadeDuration = Duration(milliseconds: 240);

  // Which child is currently rendered. Lags behind widget.collapsed while a
  // sequential fade-out -> delay -> fade-in transition is running so that only
  // one item is ever visible.
  late bool _displayCollapsed;
  bool _visible = true;
  Timer? _transitionTimer;

  @override
  void initState() {
    super.initState();
    _displayCollapsed = widget.collapsed;
  }

  @override
  void didUpdateWidget(covariant _BottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapsed != _displayCollapsed) {
      _startTransition();
    }
  }

  @override
  void dispose() {
    _transitionTimer?.cancel();
    super.dispose();
  }

  void _startTransition() {
    _transitionTimer?.cancel();
    // 1. Fade the current item out completely.
    setState(() => _visible = false);
    // 2. Once it has fully disappeared, swap + fade the new one in. The new
    //    target is read at fire time so rapid toggles settle on the latest
    //    requested state.
    _transitionTimer = Timer(_fadeDuration, () {
      if (!mounted) return;
      setState(() {
        _displayCollapsed = widget.collapsed;
        _visible = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(mobileHomeTabProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    void select(MobileHomeTab next) {
      ref.read(mobileHomeTabProvider.notifier).state = next;
      if (next == MobileHomeTab.items) {
        final list = ref.read(vaultItemsSortedEntriesProvider);
        final sel = ref.read(vaultItemsSelectedEntryUuidProvider);
        if (sel == null && list.isNotEmpty) {
          ref.read(vaultItemsSelectedEntryUuidProvider.notifier).state =
              list.first.uuid;
        }
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset > 0 ? 16 : 8),
      child: AnimatedOpacity(
        duration: _fadeDuration,
        curve: Curves.easeInOut,
        opacity: _visible ? 1 : 0,
        // The glass background is shader-based, so wrapping the child in a
        // RepaintBoundary rasterizes it into its own layer first. The opacity
        // then fades that cached layer (background included) instead of
        // compositing the shader directly, which would leave the bar opaque
        // while only the icons faded.
        child: RepaintBoundary(
          child: _displayCollapsed
              ? Align(
                  alignment: Alignment.centerRight,
                  child: _CollapsedBottomNavButton(
                    icon: _bottomNavActiveIcon(tab),
                    onTap: widget.onExpand,
                  ),
                )
              : _buildExpandedBar(tab, select),
        ),
      ),
    );
  }

  Widget _buildExpandedBar(
    MobileHomeTab tab,
    void Function(MobileHomeTab) select,
  ) {
    // Light liquid-glass palette, matching the Apple Music / Safari-style
    // bottom bar. The bar's tint is intentionally faint so the screen
    // content shows through as refractive colour, and the package's built-in
    // light-mode drop shadow (controlled by [shadowElevation]) lifts the pill
    // off the surface. The active tab uses a red accent on top of a lighter
    // white indicator pill.
    const defaultLightAngle = 0.75 * math.pi;
    const brandAccent = Color(0xFFFC1F4D);
    const darkInk = Color(0xFF111418);

    return GlassBottomBar(
      verticalPadding: 0,
      horizontalPadding: 8,
      barHeight: 60,
      barBorderRadius: 30,
      iconSize: 25,
      labelFontSize: 0,
      iconLabelSpacing: 0,
      selectedIconColor: brandAccent,
      unselectedIconColor: darkInk,
      indicatorColor: const Color(0x14FC1F4D),
      quality: GlassQuality.premium,
      extraButton: GlassBottomBarExtraButton(
        icon: const Icon(Icons.search_rounded, size: 24),
        iconColor: darkInk,
        label: 'Search',
        size: 60,
        onTap: () => openVaultSearchScreen(context),
      ),
      settings: const LiquidGlassSettings(
        thickness: 38,
        blur: 2.5,
        chromaticAberration: 0.42,
        lightIntensity: 0.30,
        refractiveIndex: 1.59,
        saturation: 1.18,
        ambientStrength: 0.30,
        lightAngle: defaultLightAngle,
        glassColor: Color(0x33FFFFFF),
        shadowElevation: 1.6,
      ),
      indicatorSettings: const LiquidGlassSettings(
        thickness: 32,
        blur: 2.5,
        chromaticAberration: 0.36,
        lightIntensity: 0.32,
        refractiveIndex: 1.59,
        saturation: 1.18,
        ambientStrength: 0.32,
        lightAngle: defaultLightAngle,
        glassColor: Color(0x88FFFFFF),
        shadowElevation: 0,
      ),
      tabs: const [
        GlassBottomBarTab(
          icon: Icon(Icons.house_rounded),
          activeIcon: Icon(Icons.house_rounded),
        ),
        GlassBottomBarTab(
          icon: Icon(Icons.grid_view_rounded),
          activeIcon: Icon(Icons.grid_view_rounded),
        ),
        GlassBottomBarTab(
          icon: Icon(Icons.timer_outlined),
          activeIcon: Icon(Icons.timer_rounded),
        ),
        GlassBottomBarTab(
          icon: Icon(Icons.person_outline_rounded),
          activeIcon: Icon(Icons.person_rounded),
        ),
      ],
      selectedIndex: _mobileHomeTabIndex(tab),
      onTabSelected: (index) => select(_mobileHomeTabFromIndex(index)),
    );
  }
}

class _CollapsedBottomNavButton extends StatelessWidget {
  const _CollapsedBottomNavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open navigation',
      child: GlassSurface(
        height: 60,
        width: 60,
        borderRadius: 30,
        tint: Colors.white.withValues(alpha: 0.62),
        borderColor: Colors.white.withValues(alpha: 0.72),
        blurSigma: 2.5,
        highlightOpacity: 0.22,
        quality: GlassQuality.premium,
        thickness: 38,
        chromaticAberration: 0.42,
        lightIntensity: 0.30,
        saturation: 1.18,
        ambientStrength: 0.30,
        shadowOpacity: 0.16,
        shadowBlurRadius: 20,
        shadowSpreadRadius: -5,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Center(
            child: Icon(icon, color: const Color(0xFF111418), size: 28),
          ),
        ),
      ),
    );
  }
}

int _mobileHomeTabIndex(MobileHomeTab tab) => switch (tab) {
  MobileHomeTab.home => 0,
  MobileHomeTab.items => 1,
  MobileHomeTab.totp => 2,
  MobileHomeTab.profile => 3,
};

MobileHomeTab _mobileHomeTabFromIndex(int index) => switch (index) {
  0 => MobileHomeTab.home,
  1 => MobileHomeTab.items,
  2 => MobileHomeTab.totp,
  _ => MobileHomeTab.profile,
};

IconData _bottomNavActiveIcon(MobileHomeTab tab) => switch (tab) {
  MobileHomeTab.home => Icons.house_rounded,
  MobileHomeTab.items => Icons.grid_view_rounded,
  MobileHomeTab.totp => Icons.timer_rounded,
  MobileHomeTab.profile => Icons.person_rounded,
};

class _QuickCardData {
  const _QuickCardData({
    required this.title,
    required this.count,
    required this.icon,
    required this.startColor,
    required this.endColor,
    required this.accentColor,
    required this.iconBackground,
    this.onTap,
  });

  final String title;
  final String count;
  final IconData icon;
  final Color startColor;
  final Color endColor;
  final Color accentColor;
  final Color iconBackground;
  final VoidCallback? onTap;
}
