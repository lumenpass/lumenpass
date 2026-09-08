import 'dart:convert';
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/dock_icon_assets.dart';
import '../../../core/services/appearance_preferences.dart';
import '../../../core/services/general_preferences.dart';
import '../../../core/services/vault_preferences.dart';
import '../../../core/constants/kdbx_field_keys.dart';
import '../../../core/models/entry_binary_attachment.dart';
import '../../../core/models/entry_field.dart';
import '../../../core/models/entry_attachment.dart';
import '../../../core/models/kdbx_entry.dart';
import '../../../core/models/kdbx_group.dart';
import '../../../core/repository/kdbx_repository.dart';
import '../../../core/repository/kdbx_repository_provider.dart';
import '../../../core/repository/database_save_sync.dart';
import '../../../core/repository/vault_write_scheduler_provider.dart';
import '../../../core/models/database_record.dart';
import '../../../core/services/biometric_auth_service.dart';
import '../../../core/services/bookmark_service.dart';
import '../../../core/services/shortcut_service.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/services/vault_auto_sync_controller.dart';
import '../../../core/services/favicon_persistence_service.dart';
import '../../../core/services/ssh_agent_service.dart';
import '../../../core/services/release_api_client.dart';

import '../../../core/services/support_api_client.dart';
import '../../../core/services/tray_action_provider.dart';
import '../../../core/services/tray_service.dart';
import '../../../core/services/vault_auto_lock_service.dart';
import '../../../core/services/totp_service.dart';
import '../../../core/services/vault_unlock_service.dart';

import '../../import/presentation/import_flow.dart';
import '../../unlock/presentation/unlock_screen.dart';
import '../../unlock/presentation/restore_backups_modal.dart';
import '../../unlock/application/database_registry.dart';
import '../application/vault_item_type.dart';
import '../application/vault_providers.dart';
import '../application/vault_search_ranking.dart';
import '../../../presentation/theme/app_theme.dart';

part 'vault_screen_theme.dart';
part 'vault_screen_models.dart';
part 'vault_screen_sidebar.dart';
part 'vault_screen_list_pane.dart';
part 'vault_screen_detail_pane.dart';
part 'vault_screen_add_item.dart';
part 'vault_screen_add_item_shared.dart';
part 'vault_screen_add_item_login.dart';
part 'vault_screen_add_item_secure_note.dart';
part 'vault_screen_add_item_credit_card.dart';
part 'vault_screen_add_item_bank_account.dart';
part 'vault_screen_add_item_identity.dart';
part 'vault_screen_add_item_ssh_key.dart';
part 'vault_screen_add_category.dart';
part 'vault_screen_edit_item.dart';
part 'vault_screen_title_bar.dart';
part 'vault_screen_dialogs.dart';
part 'vault_screen_scan_totp.dart';
part 'vault_screen_settings.dart';
part 'vault_screen_quick_search.dart';
part 'vault_screen_quick_search_window.dart';
part 'vault_screen_password_generator_dialog.dart';

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  static const String routeName = '/vault';

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

/// Opens the shared SSH Agent explainer modal used by Settings.
void showSshAgentLearnMoreDialog(BuildContext context) {
  _showSshAgentLearnMoreDialog(context);
}

enum _VaultSortField { title, lastEdited }

enum _VaultSortDirection { ascending, descending }

class _VaultScreenState extends ConsumerState<VaultScreen>
    with WidgetsBindingObserver {
  static const double _kVaultWindowWidth = 1040;
  static const double _kVaultWindowHeight = 760;
  static const double _kQuickSearchWindowMinHeight = 178;
  static const double _kQuickSearchGeneratorHeight = 428.0;

  int _selectedIndex = 0;
  // Ticks every second to drive TOTP countdowns. Kept in a ValueNotifier (not
  // `setState`) so only widgets that actually listen (wrapped in
  // ValueListenableBuilder below) rebuild on each tick — NOT the whole
  // VaultScreen, which would otherwise re-run the expensive
  // `_sortEntries(.map(_mockEntryFromKdbx))` every second.
  final ValueNotifier<DateTime> _timeNotifier =
      ValueNotifier<DateTime>(DateTime.now());
  List<_MockEntry> _entries = const [];
  Timer? _ticker;
  Timer? _toastTimer;
  Timer? _autoLockTimer;
  OverlayEntry? _toastOverlayEntry;
  String? _toastMessage;
  bool _toastIsDanger = false;
  _MockEntry? _pendingDeleteEntry;
  bool _isDeletingEntry = false;
  _MockEntry? _pendingPasskeyRemovalEntry;
  bool _isNewItemModalOpen = false;
  bool _isAddCategoryModalOpen = false;
  bool _isEditCategoryModalOpen = false;
  ({String uuid, String name, String notes, int count})? _editingCategory;
  ({String uuid, String name, String notes, int count})? _pendingDeleteCategory;
  bool _isEditItemModalOpen = false;
  _MockEntry? _editingEntry;
  bool _isSettingsOpen = false;
  _SettingsSectionId _settingsInitialSection = _SettingsSectionId.general;
  bool _isScanTotpOpen = false;
  bool _isRefreshing = false;
  _VaultSortField _sortField = _VaultSortField.lastEdited;
  _VaultSortDirection _sortDirection = _VaultSortDirection.descending;
  bool _isQuickSearchOpen = false;
  bool _isQuickSearchStandalone = false;
  bool _quickSearchOpenGenerator = false;
  double _quickSearchWindowHeight = _kQuickSearchWindowMinHeight;

  final ReleaseApiClient _releaseApi = ReleaseApiClient();
  LatestRelease? _pendingUpdate;
  bool _updateBannerDismissed = false;

  final _titleBarKey = GlobalKey<_VaultTitleBarState>();

  static const MethodChannel _windowChannel = MethodChannel('lumenpass/window');

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
      _windowChannel.invokeMethod<void>('hideNativeTitleBar');
      _windowChannel.invokeMethod<void>(
        'setSize',
        <String, double>{
          'width': _kVaultWindowWidth,
          'height': _kVaultWindowHeight,
        },
      );
    }
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      _windowChannel.setMethodCallHandler(_handleWindowMethodCall);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadAndRegisterShortcuts();
      });
    }
    WidgetsBinding.instance.addObserver(this);
    final existing = ref.read(vaultEntriesProvider);
    _entries = _sortEntries(existing.map(_mockEntryFromKdbx).toList());
    // Keep the desktop clock synced with the real 30-second TOTP window.
    // Updating the notifier (instead of setState) keeps the tick cost scoped
    // to widgets that explicitly depend on time (TOTP code + countdown).
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      _timeNotifier.value = DateTime.now();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetAutoLockTimer();
      ref.listen<int?>(vaultAutoLockMinutesProvider, (_, __) {
        _resetAutoLockTimer();
      });
    });
    unawaited(_checkForNewVersionSilently());
  }

  void _resetAutoLockTimer() {
    _autoLockTimer?.cancel();
    if (!mounted) return;

    final activeDatabase = ref.read(activeDatabaseProvider);
    final deadline = computeVaultAutoLockDeadline(
      unlockedAt: activeDatabase?.openedAt,
      autoLockMinutes: ref.read(vaultAutoLockMinutesProvider),
    );
    if (deadline == null) {
      return;
    }

    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _lockVault(reason: VaultLockedReason.timeout);
      return;
    }

    _autoLockTimer = Timer(remaining, () {
      if (!mounted) return;
      _lockVault(reason: VaultLockedReason.timeout);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      _timeNotifier.value = DateTime.now();
      _resetAutoLockTimer();
      _silentRefreshVaultEntries();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Persist pending background writes as soon as the app leaves the
      // foreground so a system kill can't discard unflushed edits. The flush
      // is fire-and-forget: the scheduler serializes saves internally and
      // the lock path flushes again (awaited) if the user locks manually.
      unawaited(ref.read(vaultWriteSchedulerProvider).flushNow());
    }
  }

  Future<void> _silentRefreshVaultEntries() async {
    if (_isRefreshing) return;
    try {
      final repository = ref.read(kdbxRepositoryProvider);
      ref.read(activeDatabaseProvider.notifier).state =
          repository.currentDatabase;
      ref.invalidate(vaultEntriesProvider);
      final kdbxEntries = ref.read(vaultEntriesProvider);
      if (!mounted) return;
      _replaceEntries(kdbxEntries.map(_mockEntryFromKdbx).toList());
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      unawaited(
          _windowChannel.invokeMethod<void>(ShortcutId.spotlight.clearMethod));
      unawaited(
          _windowChannel.invokeMethod<void>(ShortcutId.lockVault.clearMethod));
      _windowChannel.setMethodCallHandler(null);
    }
    _ticker?.cancel();
    _toastTimer?.cancel();
    _autoLockTimer?.cancel();
    _removeToastOverlay();
    _timeNotifier.dispose();
    _clearMockEntryCache();
    _releaseApi.close();
    super.dispose();
  }

  static const int _kHotKeyMaxRetries = 3;
  static const Duration _kHotKeyRetryDelay = Duration(milliseconds: 500);

  Future<void> _checkForNewVersionSilently() async {
    String? platformKey;
    if (Platform.isMacOS) {
      platformKey = 'macos';
    } else if (Platform.isWindows) {
      platformKey = 'windows';
    }
    if (platformKey == null) return;

    try {
      final info = await PackageInfo.fromPlatform();
      final localCombined = info.buildNumber.isNotEmpty
          ? '${info.version}+${info.buildNumber}'
          : info.version;
      final latest = await _releaseApi.fetchLatest(platform: platformKey);
      if (!mounted) return;
      if (compareReleaseVersions(latest.version, localCombined) > 0) {
        setState(() {
          _pendingUpdate = latest;
          _updateBannerDismissed = false;
        });
      }
    } catch (_) {
      // Silent failure — no banner is shown.
    }
  }

  void _dismissUpdateBanner() {
    setState(() {
      _updateBannerDismissed = true;
    });
  }

  Future<void> _openUpdateDownload() async {
    final url = _pendingUpdate?.downloadUrl.trim();
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _loadAndRegisterShortcuts() async {
    ShortcutData? spotlight;
    ShortcutData? lockVault;
    try {
      spotlight =
          await ShortcutService.instance.load(ShortcutId.spotlight.storageKey);
      lockVault =
          await ShortcutService.instance.load(ShortcutId.lockVault.storageKey);
    } catch (e) {
      debugPrint('[HotKey] Failed to load shortcuts from storage: $e');
    }
    spotlight ??= ShortcutData.defaultSpotlight;
    lockVault ??= ShortcutData.defaultLockVault;
    if (!mounted) return;
    ref.read(spotlightShortcutProvider.notifier).state = spotlight;
    ref.read(lockVaultShortcutProvider.notifier).state = lockVault;
    debugPrint(
      '[HotKey] Registering startup hotkeys — '
      'spotlight: ${spotlight.display}, lockVault: ${lockVault.display}',
    );
    final results = await Future.wait([
      _applyHotKeyWithRetry(ShortcutId.spotlight, spotlight),
      _applyHotKeyWithRetry(ShortcutId.lockVault, lockVault),
    ]);
    if (mounted) {
      debugPrint(
        '[HotKey] Startup registration complete — '
        'spotlight: ${results[0] ? 'OK' : 'FAILED'}, '
        'lockVault: ${results[1] ? 'OK' : 'FAILED'}',
      );
    }
  }

  Future<bool> _applyHotKeyWithRetry(ShortcutId id, ShortcutData? data) async {
    for (int attempt = 1; attempt <= _kHotKeyMaxRetries; attempt++) {
      if (!mounted) return false;
      final success = await _applyHotKey(id, data);
      if (success) return true;
      debugPrint(
        '[HotKey] ${id.name} registration attempt $attempt/$_kHotKeyMaxRetries failed, '
        '${attempt < _kHotKeyMaxRetries ? 'retrying in ${_kHotKeyRetryDelay.inMilliseconds}ms...' : 'giving up.'}',
      );
      if (attempt < _kHotKeyMaxRetries) {
        await Future<void>.delayed(_kHotKeyRetryDelay);
      }
    }
    return false;
  }

  Future<bool> _applyHotKey(ShortcutId id, ShortcutData? data) async {
    if (!Platform.isMacOS && !Platform.isWindows) return true;
    try {
      if (data == null) {
        await _windowChannel.invokeMethod<void>(id.clearMethod);
      } else if (Platform.isMacOS) {
        await _windowChannel.invokeMethod<void>(
          id.updateMethod,
          <String, int>{
            'keyCode': data.macKeyCode,
            'modifiers': data.carbonModifiers,
          },
        );
      } else {
        await _windowChannel.invokeMethod<void>(
          id.updateMethod,
          <String, int>{
            'vkCode': data.windowsVkCode,
            'modifiers': data.windowsModifiers,
          },
        );
      }
      return true;
    } catch (e) {
      debugPrint('[HotKey] _applyHotKey(${id.name}) error: $e');
      return false;
    }
  }

  Future<Object?> _handleWindowMethodCall(MethodCall call) async {
    if (!mounted) {
      return null;
    }
    switch (call.method) {
      case 'quickSearchHotkeyPressed':
        if (_isQuickSearchOpen) {
          await _closeQuickSearch();
        } else {
          await _openQuickSearch(requestNativeWindow: false, standalone: true);
        }
        break;
      case 'quickSearchDismissedByOutsideTap':
        if (_isQuickSearchOpen && _isQuickSearchStandalone) {
          await _closeQuickSearch();
        }
        break;
      // ── Relayed from the isolated Quick Search engine (macOS) ──────────
      // The panel runs in a second Flutter engine, so it can't touch the
      // vault directly; native brokers its intents to us here.
      case 'quickSearchRequestSnapshot':
        final args = call.arguments as Map<Object?, Object?>?;
        final openGenerator = args?['openGenerator'] as bool? ?? false;
        _quickSearchOpenGenerator = openGenerator;
        return _buildQuickSearchSnapshotJson(openGenerator: openGenerator);
      case 'quickSearchOpenEntry':
        final uuid = call.arguments as String?;
        if (uuid != null && uuid.isNotEmpty) {
          await _bringMainWindowToFront();
          _openEntryFromQuickSearch(uuid);
        }
        break;
      case 'quickSearchEditEntry':
        final uuid = call.arguments as String?;
        if (uuid != null && uuid.isNotEmpty) {
          await _bringMainWindowToFront();
          await _openEditItemFromQuickSearch(uuid);
        }
        break;
      case 'quickSearchCreateItem':
        await _bringMainWindowToFront();
        await _openNewItemFromQuickSearch();
        break;
      case 'quickSearchPanelClosed':
        _quickSearchOpenGenerator = false;
        break;
      case 'lockVaultHotkeyPressed':
        _lockVault();
        break;
      case 'openSettings':
        _openSettings();
        break;
      case 'checkForUpdate':
        _openSettings(section: _SettingsSectionId.about);
        break;
      case 'trayActionTriggered':
        final action = call.arguments as String?;
        if (action != null) {
          _handleTrayActionFromNative(action);
        }
        break;
      default:
        break;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final appliedSearchQuery = ref.watch(vaultSearchQueryProvider);
    final spotlightShortcut =
        ref.watch(spotlightShortcutProvider) ?? ShortcutData.defaultSpotlight;
    // NOTE: `quickSearchEntries` is computed lazily inside the
    // `_isQuickSearchOpen` branch below — avoids mapping + sorting the full
    // entry list every build (especially on each 1s tick previously, now only
    // when the overlay is actually shown).
    ref.listen<List<KdbxEntry>>(
      vaultEntriesProvider,
      (_, next) {
        if (!mounted) return;
        _replaceEntries(next.map(_mockEntryFromKdbx).toList());
      },
    );
    ref.listen<int>(vaultRefreshTriggerProvider, (_, __) {
      if (!mounted) return;
      _silentRefreshVaultEntries();
    });
    ref.listen<TrayAction?>(pendingTrayActionProvider, (_, action) {
      if (action == null || !mounted) return;
      ref.read(pendingTrayActionProvider.notifier).state = null;
      _handleTrayAction(action);
    });
    ref.listen<String?>(pendingEditItemRequestProvider, (_, entryUuid) {
      if (entryUuid == null || !mounted) return;
      ref.read(pendingEditItemRequestProvider.notifier).state = null;
      unawaited(_openEditItemFromQuickSearch(entryUuid));
    });
    ref.listen<ShortcutData?>(spotlightShortcutProvider, (_, data) {
      if (!mounted) return;
      unawaited(_applyHotKey(ShortcutId.spotlight, data));
    });
    ref.listen<ShortcutData?>(lockVaultShortcutProvider, (_, data) {
      if (!mounted) return;
      unawaited(_applyHotKey(ShortcutId.lockVault, data));
    });
    final isPasswordAuditView = ref.watch(vaultSelectedItemTypeIdProvider) ==
        kQuickFilterPasswordAudits;
    final passwordAuditReport = ref.watch(passwordAuditReportProvider);
    final passwordAuditDuplicatedCount =
        ref.watch(passwordAuditDuplicatedCountProvider);
    final passwordAuditWeakCount = ref.watch(passwordAuditWeakCountProvider);
    final passwordAuditStaleCount = ref.watch(passwordAuditStaleCountProvider);
    final passwordAuditSelection =
        ref.watch(vaultPasswordAuditSelectionProvider);
    final passwordAuditDuplicateGroups =
        ref.watch(passwordAuditDuplicateGroupsProvider);
    final passwordAuditDuplicateGroupSelection =
        ref.watch(vaultPasswordAuditDuplicateGroupSelectionProvider);

    return Scaffold(
      backgroundColor:
          _isQuickSearchStandalone ? Colors.transparent : _VaultColors.canvas,
      body: SafeArea(
        bottom: false,
        child: _TimeScope(
          notifier: _timeNotifier,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: <Widget>[
                  if (!_isQuickSearchStandalone)
                    _VaultWindow(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      entries: _entries,
                      selectedEntry:
                          _entries.isEmpty ? null : _entries[_selectedIndex],
                      selectedIndex: _selectedIndex,
                      onEntrySelected: (index) {
                        final sw = Stopwatch()..start();
                        setState(() {
                          _selectedIndex = index;
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          debugPrint(
                            '[PERF] select->frame committed in '
                            '${sw.elapsedMilliseconds}ms (index=$index)',
                          );
                        });
                      },
                      onOpenNewItemModal: _openNewItemModal,
                      onOpenImport: _openImport,
                      onOpenAddCategoryModal: _openAddCategoryModal,
                      onEditCategory: _openEditCategoryModal,
                      onDeleteCategory: _requestDeleteCategory,
                      onOpenEditItem: _openEditItemModal,
                      onLockVault: _lockVault,
                      onShowToast: _showToast,
                      onRequestDelete: _requestDeleteCurrentEntry,
                      onRequestRemovePasskey: _requestRemovePasskeyCurrentEntry,
                      onRequestRestore: _restoreCurrentEntry,
                      onRequestPermanentDelete: _permanentDeleteCurrentEntry,
                      onOpenSettings: _openSettings,
                      onOpenSshAgentSettings: _openSshAgentSettingsFromItem,
                      onOpenScanTotp: _openScanTotp,
                      onRefreshEntries: _refreshVaultEntries,
                      isRefreshing: _isRefreshing,
                      sortField: _sortField,
                      sortDirection: _sortDirection,
                      onSortChanged: _handleSortChanged,
                      searchQuery: appliedSearchQuery,
                      onClearSearch: _clearAppliedSearch,
                      onEntryRequested: _openEntryByUuid,
                      titleBarKey: _titleBarKey,
                      onOpenEntryWebsite: _openEntryWebsiteFromList,
                      onEditEntry: _editEntryFromList,
                      onDuplicateEntry: _duplicateEntryFromList,
                      onCopyEntryTotp: _copyTotpFromList,
                      onDeleteEntry: _deleteEntryFromList,
                      isPasswordAuditView: isPasswordAuditView,
                      passwordAuditReport: passwordAuditReport,
                      passwordAuditDuplicatedCount:
                          passwordAuditDuplicatedCount,
                      passwordAuditWeakCount: passwordAuditWeakCount,
                      passwordAuditStaleCount: passwordAuditStaleCount,
                      passwordAuditSelection: passwordAuditSelection,
                      passwordAuditDuplicateGroups:
                          passwordAuditDuplicateGroups,
                      passwordAuditDuplicateGroupSelection:
                          passwordAuditDuplicateGroupSelection,
                      onPasswordAuditIssueSelected: (issue) {
                        ref
                            .read(
                                vaultPasswordAuditDuplicateGroupSelectionProvider
                                    .notifier)
                            .state = null;
                        ref
                            .read(vaultPasswordAuditSelectionProvider.notifier)
                            .state = issue;
                      },
                      onPasswordAuditDuplicateGroupSelected: (key) {
                        ref
                            .read(
                                vaultPasswordAuditDuplicateGroupSelectionProvider
                                    .notifier)
                            .state = key;
                      },
                      onPasswordAuditBack: () {
                        final groupSelection = ref.read(
                            vaultPasswordAuditDuplicateGroupSelectionProvider);
                        if (groupSelection != null) {
                          // Level 3 → Level 2: clear group, keep duplicate
                          // issue selection.
                          ref
                              .read(
                                  vaultPasswordAuditDuplicateGroupSelectionProvider
                                      .notifier)
                              .state = null;
                          return;
                        }
                        // Level 2 → Level 1: clear issue selection (also
                        // ensure group selection is null in case anything
                        // got out of sync).
                        ref
                            .read(
                                vaultPasswordAuditDuplicateGroupSelectionProvider
                                    .notifier)
                            .state = null;
                        ref
                            .read(vaultPasswordAuditSelectionProvider.notifier)
                            .state = null;
                      },
                    ),
                  if (_isNewItemModalOpen)
                    Positioned.fill(
                      child: _AddNewItemOverlay(
                        onClose: _dismissNewItemModal,
                        onShowToast: _showToast,
                        onItemCreated: _focusEntryByUuid,
                      ),
                    ),
                  if (_isAddCategoryModalOpen)
                    Positioned.fill(
                      child: _AddCategoryOverlay(
                        onClose: _dismissAddCategoryModal,
                        onShowToast: _showToast,
                        onCategoryCreated: _handleCategoryCreated,
                      ),
                    ),
                  if (_pendingDeleteEntry != null)
                    Positioned.fill(
                      child: _DeleteConfirmationOverlay(
                        entryTitle: _pendingDeleteEntry!.title,
                        isDeleting: _isDeletingEntry,
                        onCancel: _dismissDeleteDialog,
                        onConfirm: _confirmDeleteEntry,
                      ),
                    ),
                  if (_pendingPasskeyRemovalEntry != null)
                    Positioned.fill(
                      child: _RemovePasskeyConfirmationOverlay(
                        entryTitle: _pendingPasskeyRemovalEntry!.title,
                        onCancel: _dismissRemovePasskeyDialog,
                        onConfirm: _confirmRemovePasskeyEntry,
                      ),
                    ),
                  if (_isSettingsOpen)
                    Positioned.fill(
                      child: _SettingsOverlay(
                        onClose: _dismissSettings,
                        initialSection: _settingsInitialSection,
                        onRequestRestore: _handleBackupRestoreRequest,
                      ),
                    ),
                  if (_isScanTotpOpen)
                    Positioned.fill(
                      child: _ScanTotpOverlay(
                        onClose: _dismissScanTotp,
                        onTotpConfirmed: _confirmAddTotp,
                        onShowToast: _showToast,
                      ),
                    ),
                  if (_isEditCategoryModalOpen && _editingCategory != null)
                    Positioned.fill(
                      child: _EditCategoryOverlay(
                        category: _editingCategory!,
                        onClose: _dismissEditCategoryModal,
                        onShowToast: _showToast,
                        onCategoryUpdated: _handleCategoryUpdated,
                      ),
                    ),
                  if (_pendingDeleteCategory != null)
                    Positioned.fill(
                      child: _DeleteCategoryConfirmationOverlay(
                        categoryName: _pendingDeleteCategory!.name,
                        onCancel: _dismissDeleteCategoryDialog,
                        onConfirm: _confirmDeleteCategory,
                      ),
                    ),
                  if (_isEditItemModalOpen && _editingEntry != null)
                    Positioned.fill(
                      child: _EditItemOverlay(
                        entry: _editingEntry!,
                        onClose: _dismissEditItemModal,
                        onShowToast: _showToast,
                        onItemUpdated: _onItemUpdated,
                      ),
                    ),
                  if (_isQuickSearchOpen)
                    Positioned.fill(
                      child: Builder(
                        builder: (_) {
                          // Only map + sort the full entry list when the
                          // overlay is actually visible (B). This was
                          // previously running on every VaultScreen rebuild
                          // (including every 1s tick) — a major source of lag.
                          final quickSearchEntries = _sortEntries(
                            ref
                                .watch(vaultDatabaseEntriesProvider)
                                .map(_mockEntryFromKdbx)
                                .toList(),
                          );
                          return ValueListenableBuilder<DateTime>(
                            valueListenable: _timeNotifier,
                            builder: (_, currentTime, __) =>
                                _QuickSearchOverlay(
                              entries: quickSearchEntries,
                              initialSelectedUuid: (_entries.isNotEmpty &&
                                      _selectedIndex >= 0 &&
                                      _selectedIndex < _entries.length)
                                  ? _entries[_selectedIndex].uuid
                                  : null,
                              onClose: _closeQuickSearch,
                              onEntrySelected: _openEntryFromQuickSearch,
                              onCreateNewItem: _openNewItemFromQuickSearch,
                              onShowToast: _showToast,
                              onEditItem: _openEditItemFromQuickSearch,
                              showBackdrop: !_isQuickSearchStandalone,
                              onPreferredHeightChanged:
                                  _handleQuickSearchHeightChanged,
                              currentTime: currentTime,
                              initialShowGenerator: _quickSearchOpenGenerator,
                              hideCreditCardNumber:
                                  ref.watch(vaultHideCreditCardNumberProvider),
                              shortcutDisplay: spotlightShortcut.display,
                            ),
                          );
                        },
                      ),
                    ),
                  if (_pendingUpdate != null && !_updateBannerDismissed)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: IgnorePointer(
                        ignoring: false,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: _NewVersionBanner(
                            version: _pendingUpdate!.version,
                            onDownload: _openUpdateDownload,
                            onDismiss: _dismissUpdateBanner,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _handleTrayAction(TrayAction action) {
    switch (action) {
      case TrayAction.openDashboard:
        break;
      case TrayAction.quickSearch:
        _openQuickSearch(standalone: true);
      case TrayAction.generatePassword:
        _openQuickSearch(standalone: true, openGenerator: true);
      case TrayAction.newItem:
        _openNewItemModal();
      case TrayAction.switchVaults:
      case TrayAction.lockVault:
        _lockVault();
    }
  }

  void _handleTrayActionFromNative(String action) {
    switch (action) {
      case 'openDashboard':
        break;
      case 'quickSearch':
        _openQuickSearch(standalone: true);
      case 'generatePassword':
        _openQuickSearch(standalone: true, openGenerator: true);
      case 'switchVaults':
        break;
      case 'lockVault':
        _lockVault();
    }
  }

  void _lockVault({VaultLockedReason reason = VaultLockedReason.manual}) {
    unawaited(_lockVaultAsync(reason: reason));
  }

  /// Locks the vault with a guard that first awaits any in-flight cloud
  /// upload so the latest edits are not lost if the user locks immediately
  /// after saving. If the upload is still running we show a blocking
  /// "Syncing…" modal and a toast on failure so the user can reattempt
  /// before leaving the screen.
  Future<void> _lockVaultAsync({
    required VaultLockedReason reason,
  }) async {
    final lockedVaultPath = ref.read(activeDatabaseProvider)?.path;

    // Persist any pending background writes before the cloud-sync guard so
    // the upload (and the dirty check below) sees the latest local state.
    await ref.read(vaultWriteSchedulerProvider).flushNow();
    if (!mounted) return;

    if (lockedVaultPath != null) {
      DatabaseRecord? record;
      for (final r in ref.read(databaseRegistryProvider)) {
        if (databasePathsReferToSameVault(r.databasePath, lockedVaultPath)) {
          record = r;
          break;
        }
      }
      final status = CloudSyncService.instance.statusFor(lockedVaultPath);
      final dirty = await CloudSyncService.instance.isDirty(lockedVaultPath);
      debugPrint(
        '[Lock] reason=${reason.name} path=${p.basename(lockedVaultPath)} '
        'storage=${record?.storageType ?? 'local'} '
        'syncPhase=${status.phase.name} dirty=$dirty',
      );
      if (record != null && (status.isBusy || dirty)) {
        debugPrint(
          '[Lock] blocking on pending cloud sync before lock '
          '(phase=${status.phase.name}, dirty=$dirty)',
        );
        await _runSyncingDialog(record);
        if (!mounted) return;
        final settled = CloudSyncService.instance.statusFor(lockedVaultPath);
        final stillDirty =
            await CloudSyncService.instance.isDirty(lockedVaultPath);
        debugPrint(
          '[Lock] sync settled phase=${settled.phase.name} '
          'dirty=$stillDirty',
        );
        if (settled.phase == CloudSyncPhase.error || stillDirty) {
          debugPrint(
            '[Lock] WARNING: locking with unsynced local changes '
            '(phase=${settled.phase.name}, dirty=$stillDirty, '
            'error=${settled.error})',
          );
          _showToast(
            'Cloud sync is not up to date — your changes are kept locally and will retry on next save.',
            danger: true,
          );
        }
      }
    }

    if (!mounted) return;
    BookmarkService.instance.stopAll();
    BackupService.instance.cancelForLockedVault();
    ref.read(vaultWriteSchedulerProvider).reset();
    ref.read(kdbxRepositoryProvider).closeDatabase();
    ref.read(activeDatabaseProvider.notifier).state = null;
    ref.read(cachedMasterPasswordProvider.notifier).state = null;
    ref.read(vaultSelectedItemTypeIdProvider.notifier).state = null;
    unawaited(SshAgentService.instance.syncKeys());
    unawaited(TrayService.instance.setVaultLocked(true));
    Navigator.of(context).pushReplacementNamed(
      UnlockScreen.routeName,
      arguments: UnlockScreenArgs(
        lockedPath: lockedVaultPath,
        lockedReason: reason,
      ),
    );
  }

  /// Shows a non-dismissible progress modal while [CloudSyncService] finishes
  /// any pending upload for [record]. Triggers a retry when the vault is
  /// marked dirty but idle (e.g. previous session crashed before the upload
  /// completed). Returns once the service reports idle or an error, capped
  /// at 60 seconds to avoid hanging the UI forever.
  Future<void> _runSyncingDialog(DatabaseRecord record) async {
    final path = record.databasePath;
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final completer = Completer<void>();
    late final StreamSubscription<CloudSyncStatus> sub;
    sub = CloudSyncService.instance.statusStream.listen((status) {
      if (status.path != path) return;
      if (!status.isBusy) {
        if (!completer.isCompleted) completer.complete();
      }
    });

    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const _CloudSyncBlockingDialog(),
    );

    try {
      // Kick a fresh upload if we're only dirty (not already in-flight).
      // flush() is a no-op when another upload is already running.
      CloudSyncService.instance.flush(record).ignore();
      await CloudSyncService.instance.awaitPending(path);
      if (!CloudSyncService.instance.statusFor(path).isBusy) {
        if (!completer.isCompleted) completer.complete();
      }
      await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {},
      );
    } finally {
      await sub.cancel();
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      await dialog;
    }
  }

  void _showToast(String message, {bool danger = false}) {
    _toastTimer?.cancel();
    _toastMessage = message;
    _toastIsDanger = danger || _isDangerToast(message);
    _insertOrUpdateToastOverlay();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) {
        return;
      }
      _toastMessage = null;
      _removeToastOverlay();
    });
  }

  Future<void> _openQuickSearch({
    bool requestNativeWindow = true,
    bool standalone = true,
    bool openGenerator = false,
  }) async {
    // Desktop standalone Quick Search runs in an *isolated* borderless native
    // panel backed by a second Flutter engine (Option A). The main window is
    // never transformed. We simply ask native to reveal the panel; native
    // pulls a fresh entry snapshot from us on demand (see
    // `quickSearchRequestSnapshot`). Implemented natively on macOS, Windows
    // and Linux.
    if ((Platform.isMacOS || Platform.isWindows || Platform.isLinux) &&
        standalone) {
      _quickSearchOpenGenerator = openGenerator;
      try {
        await _windowChannel.invokeMethod<void>(
          'showQuickSearchPanel',
          <String, Object?>{'openGenerator': openGenerator},
        );
      } catch (_) {
        // If the panel engine failed to boot, fall back to bringing the
        // main window forward so the hotkey still does *something*.
        if (requestNativeWindow) {
          try {
            await _windowChannel.invokeMethod<void>('bringToFront');
          } catch (_) {}
        }
      }
      return;
    }

    // Non-standalone in-window request: keep painting the overlay inside this
    // window (used e.g. when explicitly requested without the isolated panel).
    _quickSearchOpenGenerator = openGenerator;
    _quickSearchWindowHeight = openGenerator
        ? _kQuickSearchGeneratorHeight
        : _kQuickSearchWindowMinHeight;
    if (requestNativeWindow && (Platform.isWindows || Platform.isLinux)) {
      try {
        await _windowChannel.invokeMethod<void>('showQuickSearchWindow');
      } catch (_) {
        try {
          await _windowChannel.invokeMethod<void>('bringToFront');
        } catch (_) {}
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isQuickSearchOpen = true;
      _isQuickSearchStandalone = standalone;
    });
  }

  /// Serialises the current entry projection + appearance/config into the
  /// JSON snapshot consumed by the isolated Quick Search engine. `KdbxEntry`
  /// is `freezed` + `json_serializable`, so the panel can rebuild the exact
  /// same `_MockEntry` list via `_mockEntryFromKdbx` on the other side.
  String _buildQuickSearchSnapshotJson({bool openGenerator = false}) {
    final kdbxEntries = ref.read(vaultDatabaseEntriesProvider);
    final mapped = _sortEntries(
      kdbxEntries.map(_mockEntryFromKdbx).toList(),
    );
    final selectedUuid = (_entries.isNotEmpty &&
            _selectedIndex >= 0 &&
            _selectedIndex < _entries.length)
        ? _entries[_selectedIndex].uuid
        : null;
    final spotlight =
        ref.read(spotlightShortcutProvider) ?? ShortcutData.defaultSpotlight;

    // Ship entries in the ranked/sorted order via their uuid so the panel can
    // preserve ordering; the KdbxEntry JSON carries everything the overlay
    // renders.
    final orderedUuids = mapped.map((e) => e.uuid).toList();
    final byUuid = <String, KdbxEntry>{
      for (final e in kdbxEntries) e.uuid: e,
    };
    final orderedKdbx = <Map<String, dynamic>>[];
    for (final uuid in orderedUuids) {
      final entry = byUuid[uuid];
      if (entry != null) {
        orderedKdbx.add(entry.toJson());
      }
    }

    return jsonEncode(<String, Object?>{
      'entries': orderedKdbx,
      'initialSelectedUuid': selectedUuid,
      'initialShowGenerator': openGenerator,
      'hideCreditCardNumber': ref.read(vaultHideCreditCardNumberProvider),
      'shortcutDisplay': spotlight.display,
      'fontFamily': currentFontFamily,
      'textSizeDelta': currentTextSizeDelta,
    });
  }

  Future<void> _bringMainWindowToFront() async {
    try {
      await _windowChannel.invokeMethod<void>('bringToFront');
    } catch (_) {}
  }

  Future<void> _handleQuickSearchHeightChanged(double height) async {
    if (!_isQuickSearchStandalone || !Platform.isMacOS) {
      return;
    }
    if ((_quickSearchWindowHeight - height).abs() < 0.5) {
      return;
    }
    _quickSearchWindowHeight = height;
    try {
      await _windowChannel.invokeMethod<void>(
        'setQuickSearchSize',
        <String, double>{
          'height': _quickSearchWindowHeight,
        },
      );
    } catch (_) {}
  }

  Future<void> _closeQuickSearch({bool hideWindow = true}) async {
    final wasStandalone = _isQuickSearchStandalone;
    if (!_isQuickSearchOpen) {
      return;
    }
    setState(() {
      _isQuickSearchOpen = false;
      _isQuickSearchStandalone = false;
    });
    // In-window overlay only exists on Windows/Linux (or non-standalone).
    // On macOS the standalone panel is owned entirely by native, so there is
    // nothing to tear down here.
    if ((Platform.isWindows || Platform.isLinux) && wasStandalone) {
      if (hideWindow) {
        try {
          await _windowChannel.invokeMethod<void>('hideWindow');
        } catch (_) {}
      }
    }
  }

  void _openEntryFromQuickSearch(String uuid) {
    if (_isQuickSearchStandalone) {
      unawaited(_closeQuickSearch(hideWindow: false));
    } else {
      _closeQuickSearch(hideWindow: false);
    }
    _openEntryByUuid(uuid);
  }

  Future<void> _openNewItemFromQuickSearch() async {
    await _closeQuickSearch(hideWindow: false);
    if (!mounted) {
      return;
    }
    _openNewItemModal();
  }

  Future<void> _openEditItemFromQuickSearch(String uuid) async {
    await _closeQuickSearch(hideWindow: false);
    if (!mounted) {
      return;
    }
    final allEntries = _sortEntries(
      ref.read(vaultEntriesProvider).map(_mockEntryFromKdbx).toList(),
    );
    final idx = allEntries.indexWhere((e) => e.uuid == uuid);
    if (idx < 0) {
      return;
    }
    setState(() {
      _editingEntry = allEntries[idx];
      _isEditItemModalOpen = true;
    });
  }

  bool _isDangerToast(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('unable') ||
        normalized.contains('failed') ||
        normalized.contains('error') ||
        normalized.contains('invalid') ||
        normalized.contains('required') ||
        normalized.contains('unavailable') ||
        normalized.contains('empty');
  }

  void _insertOrUpdateToastOverlay() {
    if (!mounted || _toastMessage == null) {
      return;
    }

    if (_toastOverlayEntry != null) {
      _toastOverlayEntry!.markNeedsBuild();
      return;
    }

    _toastOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final message = _toastMessage;
        if (message == null) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          child: SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    );
                  },
                  child: _InAppToast(
                    key: ValueKey(
                        '$message-${_toastIsDanger ? 'danger' : 'normal'}'),
                    message: message,
                    danger: _toastIsDanger,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_toastOverlayEntry!);
  }

  void _removeToastOverlay() {
    _toastOverlayEntry?.remove();
    _toastOverlayEntry = null;
  }

  void _requestDeleteCurrentEntry() {
    if (_entries.isEmpty) {
      return;
    }

    setState(() {
      _pendingDeleteEntry = _entries[_selectedIndex];
      _isDeletingEntry = false;
    });
  }

  void _dismissDeleteDialog() {
    if (_isDeletingEntry) return;
    setState(() {
      _pendingDeleteEntry = null;
      _isDeletingEntry = false;
    });
  }

  void _requestRemovePasskeyCurrentEntry() {
    if (_entries.isEmpty) {
      return;
    }

    setState(() {
      _pendingPasskeyRemovalEntry = _entries[_selectedIndex];
    });
  }

  void _dismissRemovePasskeyDialog() {
    setState(() {
      _pendingPasskeyRemovalEntry = null;
    });
  }

  Future<void> _confirmDeleteEntry() async {
    final entry = _pendingDeleteEntry;
    if (entry == null || _isDeletingEntry) {
      return;
    }

    setState(() {
      _isDeletingEntry = true;
    });
    if (!mounted || _pendingDeleteEntry != entry) return;

    setState(() {
      _entries = List<_MockEntry>.of(_entries)..remove(entry);
      if (_entries.isEmpty) {
        _selectedIndex = 0;
      } else if (_selectedIndex >= _entries.length) {
        _selectedIndex = _entries.length - 1;
      }
      _pendingDeleteEntry = null;
      _isDeletingEntry = false;
    });

    var deleted = true;
    if (entry.uuid.isNotEmpty) {
      deleted = await _deleteEntryFromRepository(entry.uuid);
    }
    if (!mounted || !deleted) return;
    _showToast('${entry.title} moved to Trash');
  }

  void _restoreCurrentEntry() {
    if (_entries.isEmpty) return;
    final entry = _entries[_selectedIndex];
    if (entry.uuid.isEmpty) return;
    _doRestoreEntry(entry);
  }

  void _permanentDeleteCurrentEntry() {
    if (_entries.isEmpty) return;
    final entry = _entries[_selectedIndex];
    if (entry.uuid.isEmpty) return;
    _doPermanentDelete(entry);
  }

  Future<void> _doPermanentDelete(_MockEntry entry) async {
    setState(() {
      _entries = List<_MockEntry>.of(_entries)..remove(entry);
      if (_entries.isEmpty) {
        _selectedIndex = 0;
      } else if (_selectedIndex >= _entries.length) {
        _selectedIndex = _entries.length - 1;
      }
    });
    try {
      await ref.read(kdbxRepositoryProvider).permanentlyDeleteEntry(entry.uuid);
      publishAndScheduleSave(ref, ref.read(kdbxRepositoryProvider));
      if (!mounted) return;
      _showToast('${entry.title} permanently deleted');
    } catch (e) {
      if (mounted) _showToast('Failed to delete item: $e', danger: true);
    }
  }

  Future<void> _doRestoreEntry(_MockEntry entry) async {
    try {
      await ref.read(kdbxRepositoryProvider).restoreEntry(entry.uuid);
      publishAndScheduleSave(ref, ref.read(kdbxRepositoryProvider));
      if (!mounted) return;
      _showToast('${entry.title} restored');
    } catch (e) {
      if (mounted) _showToast('Failed to restore item: $e', danger: true);
    }
  }

  Future<bool> _deleteEntryFromRepository(String uuid) async {
    try {
      await ref.read(kdbxRepositoryProvider).deleteEntry(uuid);
      publishAndScheduleSave(ref, ref.read(kdbxRepositoryProvider));
      if (!mounted) return false;
      return true;
    } catch (e) {
      if (mounted) _showToast('Failed to delete item: $e', danger: true);
      return false;
    }
  }

  Future<bool> _removePasskeyFromEntry(_MockEntry selectedEntry) async {
    if (selectedEntry.uuid.isEmpty) {
      _showToast('Unable to remove passkey');
      return false;
    }

    try {
      final sourceEntry = ref.read(vaultDatabaseEntriesProvider).firstWhere(
            (entry) => entry.uuid == selectedEntry.uuid,
          );
      final remainingFields = sourceEntry.fields
          .where((field) => !_isPasskeyMetadataField(field))
          .toList(growable: false);

      if (remainingFields.length == sourceEntry.fields.length) {
        _showToast('No passkey found to remove');
        return false;
      }

      final repository = ref.read(kdbxRepositoryProvider);
      await repository.updateEntry(
        entryUuid: sourceEntry.uuid,
        fields: remainingFields,
        notes: sourceEntry.notes,
        tags: sourceEntry.tags,
      );
      publishAndScheduleSave(ref, repository);
      _replaceEntries(
        ref.read(vaultEntriesProvider).map(_mockEntryFromKdbx).toList(),
        preferredEntryUuid: sourceEntry.uuid,
      );
      _showToast('Passkey removed');
      return true;
    } catch (_) {
      _showToast('Unable to remove passkey');
      return false;
    }
  }

  Future<void> _confirmRemovePasskeyEntry() async {
    final entry = _pendingPasskeyRemovalEntry;
    if (entry == null) {
      return;
    }

    await _removePasskeyFromEntry(entry);

    if (!mounted) {
      return;
    }

    setState(() {
      _pendingPasskeyRemovalEntry = null;
    });
  }

  bool _isPasskeyMetadataField(EntryField field) {
    return field.key.toLowerCase().contains('kpex_passkey_');
  }

  void _replaceEntries(
    List<_MockEntry> mapped, {
    String? preferredEntryUuid,
  }) {
    final selectedUuid = preferredEntryUuid ??
        ((_entries.isNotEmpty && _selectedIndex < _entries.length)
            ? _entries[_selectedIndex].uuid
            : null);
    final sorted = _sortEntries(mapped);
    final nextIndex = selectedUuid == null
        ? 0
        : sorted.indexWhere((entry) => entry.uuid == selectedUuid);

    setState(() {
      _entries = sorted;
      if (_entries.isEmpty) {
        _selectedIndex = 0;
      } else if (nextIndex >= 0) {
        _selectedIndex = nextIndex;
      } else if (_selectedIndex >= _entries.length) {
        _selectedIndex = _entries.length - 1;
      }
    });
  }

  List<_MockEntry> _sortEntries(List<_MockEntry> entries) {
    final sorted = List<_MockEntry>.of(entries);

    int compareByLastEdited(_MockEntry a, _MockEntry b) {
      final dateCompare = a.lastTouchedAt.compareTo(b.lastTouchedAt);
      if (dateCompare != 0) {
        return dateCompare;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    }

    sorted.sort((a, b) {
      final result = switch (_sortField) {
        _VaultSortField.title =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        _VaultSortField.lastEdited => compareByLastEdited(a, b),
      };

      final withTieBreaker = result == 0 && _sortField == _VaultSortField.title
          ? compareByLastEdited(a, b)
          : result;

      return _sortDirection == _VaultSortDirection.ascending
          ? withTieBreaker
          : -withTieBreaker;
    });

    return sorted;
  }

  void _handleSortChanged(_VaultSortField field) {
    final selectedUuid =
        (_entries.isNotEmpty && _selectedIndex < _entries.length)
            ? _entries[_selectedIndex].uuid
            : null;

    setState(() {
      if (_sortField == field) {
        _sortDirection = _sortDirection == _VaultSortDirection.ascending
            ? _VaultSortDirection.descending
            : _VaultSortDirection.ascending;
      } else {
        _sortField = field;
        _sortDirection = field == _VaultSortField.title
            ? _VaultSortDirection.ascending
            : _VaultSortDirection.descending;
      }
      _entries = _sortEntries(_entries);
      if (_entries.isEmpty) {
        _selectedIndex = 0;
      } else if (selectedUuid != null) {
        final nextIndex =
            _entries.indexWhere((entry) => entry.uuid == selectedUuid);
        _selectedIndex = nextIndex >= 0 ? nextIndex : 0;
      }
    });
  }

  void _openEntryWebsiteFromList(int index) {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    if (entry.website.trim().isEmpty) return;
    final url = Uri.parse(entry.website);
    launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _editEntryFromList(int index) {
    if (index < 0 || index >= _entries.length) return;
    setState(() {
      _selectedIndex = index;
    });
    _openEditItemModal();
  }

  void _duplicateEntryFromList(int index) async {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    if (entry.uuid.isEmpty) {
      _showToast('Cannot duplicate mock entry');
      return;
    }

    try {
      final sourceEntry = ref.read(vaultDatabaseEntriesProvider).firstWhere(
            (e) => e.uuid == entry.uuid,
          );

      final repository = ref.read(kdbxRepositoryProvider);
      final newTitle = '${entry.title} Copy';

      final createdEntry = await repository.createEntry(
        groupUuid: entry.groupUuid,
        fields: sourceEntry.fields,
        notes: sourceEntry.notes,
        tags: sourceEntry.tags,
      );

      // Update the title
      await repository.updateEntry(
        entryUuid: createdEntry.uuid,
        fields: [
          ...sourceEntry.fields.where((f) => f.key.toLowerCase() != 'title'),
          EntryField(key: 'Title', value: newTitle, isProtected: false),
        ],
        notes: sourceEntry.notes,
        tags: sourceEntry.tags,
      );

      publishAndScheduleSave(ref, repository);
      if (!mounted) return;

      _replaceEntries(
        ref.read(vaultEntriesProvider).map(_mockEntryFromKdbx).toList(),
        preferredEntryUuid: createdEntry.uuid,
      );
      _showToast('Entry duplicated as "$newTitle"');
    } catch (e) {
      if (mounted) _showToast('Failed to duplicate entry: $e', danger: true);
    }
  }

  void _copyTotpFromList(int index) {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    if (entry.totpAuthUrl.isEmpty) return;
    final totpCode = _formattedTotpCode(entry, _timeNotifier.value);
    Clipboard.setData(ClipboardData(text: totpCode));
    _showToast('TOTP code copied to clipboard');
  }

  void _deleteEntryFromList(int index) {
    if (index < 0 || index >= _entries.length) return;
    setState(() {
      _selectedIndex = index;
      _pendingDeleteEntry = _entries[index];
      _isDeletingEntry = false;
    });
  }

  Future<void> _refreshVaultEntries() async {
    if (_isRefreshing) {
      return;
    }

    setState(() {
      _isRefreshing = true;
    });

    try {
      final repository = ref.read(kdbxRepositoryProvider);
      ref.read(activeDatabaseProvider.notifier).state =
          repository.currentDatabase;
      ref.invalidate(vaultEntriesProvider);
      final kdbxEntries = ref.read(vaultEntriesProvider);
      if (!mounted) {
        return;
      }
      _replaceEntries(kdbxEntries.map(_mockEntryFromKdbx).toList());
      _showToast('Vault refreshed');
    } catch (_) {
      if (mounted) {
        _showToast('Unable to refresh vault');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _openScanTotp() {
    setState(() => _isScanTotpOpen = true);
  }

  void _dismissScanTotp() {
    setState(() => _isScanTotpOpen = false);
  }

  void _confirmAddTotp(String otpauthUrl) {
    if (_entries.isEmpty) return;
    setState(() {
      final updated =
          _entries[_selectedIndex].copyWith(totpAuthUrl: otpauthUrl);
      _entries = List<_MockEntry>.of(_entries)..[_selectedIndex] = updated;
      _isScanTotpOpen = false;
    });
    _showToast('2FA code added successfully');
  }

  void _openEditItemModal() {
    if (_entries.isEmpty) return;
    setState(() {
      _editingEntry = _entries[_selectedIndex];
      _isEditItemModalOpen = true;
    });
  }

  void _dismissEditItemModal() {
    setState(() {
      _isEditItemModalOpen = false;
      _editingEntry = null;
    });
  }

  void _onItemUpdated(String uuid) {
    final refreshed = ref.read(vaultEntriesProvider);
    _replaceEntries(
      refreshed.map(_mockEntryFromKdbx).toList(),
      preferredEntryUuid: uuid,
    );
  }

  void _openNewItemModal() {
    setState(() {
      _isNewItemModalOpen = true;
    });
  }

  void _openImport() {
    const ImportFlowOrchestrator().startFlow(context, ref);
  }

  void _dismissNewItemModal() {
    setState(() {
      _isNewItemModalOpen = false;
    });
  }

  void _openAddCategoryModal() {
    setState(() {
      _isAddCategoryModalOpen = true;
    });
  }

  void _openEditCategoryModal(
      ({String uuid, String name, String notes, int count}) category) {
    setState(() {
      _editingCategory = category;
      _isEditCategoryModalOpen = true;
    });
  }

  void _dismissEditCategoryModal() {
    setState(() {
      _isEditCategoryModalOpen = false;
      _editingCategory = null;
    });
  }

  Future<void> _handleCategoryUpdated(String groupUuid) async {
    ref.invalidate(vaultSidebarCategoriesProvider);
    ref.invalidate(vaultEntriesProvider);
    setState(() {
      _isEditCategoryModalOpen = false;
      _editingCategory = null;
    });
  }

  void _requestDeleteCategory(
      ({String uuid, String name, String notes, int count}) category) {
    setState(() {
      _pendingDeleteCategory = category;
    });
  }

  void _dismissDeleteCategoryDialog() {
    setState(() {
      _pendingDeleteCategory = null;
    });
  }

  Future<void> _confirmDeleteCategory() async {
    final category = _pendingDeleteCategory;
    if (category == null) return;

    setState(() {
      _pendingDeleteCategory = null;
    });

    try {
      final repository = ref.read(kdbxRepositoryProvider);
      await repository.deleteGroup(category.uuid);
      publishAndScheduleSave(ref, repository);
      final currentGroup = ref.read(vaultSelectedGroupProvider);
      if (currentGroup == category.uuid) {
        ref.read(vaultSelectedGroupProvider.notifier).state = null;
      }
      _replaceEntries(
        ref.read(vaultEntriesProvider).map(_mockEntryFromKdbx).toList(),
      );
      _showToast('${category.name} category deleted');
    } catch (error) {
      _showToast('Unable to delete category: $error', danger: true);
    }
  }

  void _dismissAddCategoryModal() {
    setState(() {
      _isAddCategoryModalOpen = false;
    });
  }

  Future<void> _handleCategoryCreated(String groupUuid) async {
    ref.read(vaultSelectedGroupProvider.notifier).state = groupUuid;
    ref.read(vaultSelectedItemTypeIdProvider.notifier).state = null;
    ref.read(vaultSelectedTagProvider.notifier).state = null;
    ref.invalidate(vaultSidebarCategoriesProvider);
    ref.invalidate(vaultEntriesProvider);
    setState(() {
      _isAddCategoryModalOpen = false;
    });
  }

  void _openSettings(
      {_SettingsSectionId section = _SettingsSectionId.general}) {
    setState(() {
      _settingsInitialSection = section;
      _isSettingsOpen = true;
    });
  }

  void _openSshAgentSettingsFromItem() {
    _openSettings(section: _SettingsSectionId.developer);
  }

  void _dismissSettings() {
    setState(() => _isSettingsOpen = false);
  }

  /// Orchestrates the full backup restore workflow once the Backup settings
  /// pane has confirmed the user's intent and master password. This handler
  /// owns modal management (close settings → progress dialog → unlock
  /// screen), state cleanup, and toast notifications so the settings pane
  /// stays focused on collecting user intent.
  Future<void> _handleBackupRestoreRequest(
    BackupRestoreRequest request,
  ) async {
    final navigator = Navigator.of(context);
    final lockedVaultPath = ref.read(activeDatabaseProvider)?.path;

    setState(() => _isSettingsOpen = false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    // IMPORTANT: do NOT call BookmarkService.stopAll() before the restore.
    // On macOS the live vault is reachable only through its security-scoped
    // bookmark; revoking it now would make the upcoming file overwrite fail
    // with PathAccessException. Bookmarks are released after the swap, just
    // before we navigate to the unlock screen.
    BackupService.instance.cancelForLockedVault();

    bool progressOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => const RestoreProgressDialog(),
      ).whenComplete(() => progressOpen = false),
    );

    Object? failure;
    try {
      // Flush pending background writes before the restore overwrites the
      // live file, so a stale scheduled save can't land after the swap.
      await ref.read(vaultWriteSchedulerProvider).flushNow();
      await BackupService.instance.restoreLocalBackup(
        request.backup,
        targetVaultPath: lockedVaultPath,
      );
    } catch (e, stack) {
      failure = e;
      debugPrint('[Restore] failed: $e\n$stack');
    }

    if (mounted && progressOpen) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted) return;

    ref.read(vaultWriteSchedulerProvider).reset();
    ref.read(kdbxRepositoryProvider).closeDatabase();
    ref.read(activeDatabaseProvider.notifier).state = null;
    ref.read(cachedMasterPasswordProvider.notifier).state = null;
    ref.read(vaultSelectedItemTypeIdProvider.notifier).state = null;
    // Now that the bytes have been written we can release every active
    // security-scoped bookmark; the unlock screen will resolve a fresh one
    // when the user signs in to the restored vault.
    unawaited(BookmarkService.instance.stopAll());
    unawaited(SshAgentService.instance.syncKeys());
    unawaited(TrayService.instance.setVaultLocked(true));

    navigator.pushReplacementNamed(
      UnlockScreen.routeName,
      arguments: UnlockScreenArgs(
        lockedPath: lockedVaultPath,
        lockedReason: VaultLockedReason.manual,
      ),
    );

    if (failure == null) {
      _showToast(
        'Backup restored. Unlock your vault to access the restored data.',
      );
    } else {
      final detail = _formatRestoreError(failure);
      _showToast('Restore failed: $detail', danger: true);
    }
  }

  String _formatRestoreError(Object error) {
    final raw = error.toString();
    if (raw.contains('PathAccessException') ||
        raw.contains('Permission denied')) {
      return 'Insufficient permissions to read or write the vault file.';
    }
    if (raw.contains('not in KDBX format') || raw.contains('bad magic')) {
      return 'The selected file is not a valid KDBX backup.';
    }
    if (raw.contains('FileSystemException')) {
      return 'File system error — verify the backup is on a writable disk and retry.';
    }
    if (raw.contains('truncated') || raw.contains('corrupt')) {
      return 'Backup file is corrupt or incompatible with this app version.';
    }
    if (raw.contains('onto itself')) {
      return 'Cannot restore the live vault onto itself.';
    }
    return raw.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');
  }

  void _clearAppliedSearch() {
    ref.read(vaultSearchDraftProvider.notifier).state = '';
    ref.read(vaultSearchQueryProvider.notifier).state = '';
  }

  void _openEntryByUuid(String uuid) {
    ref.read(vaultSearchDraftProvider.notifier).state = '';
    ref.read(vaultSearchQueryProvider.notifier).state = '';
    final scopedEntries = _sortEntries(
      ref.read(vaultScopedEntriesProvider).map(_mockEntryFromKdbx).toList(),
    );
    final scopedIndex = scopedEntries.indexWhere((entry) => entry.uuid == uuid);
    if (scopedIndex < 0) {
      return;
    }

    setState(() {
      _entries = scopedEntries;
      _selectedIndex = scopedIndex;
    });
  }

  void _focusEntryByUuid(String uuid) {
    final refreshedEntries = ref.read(vaultEntriesProvider);
    _replaceEntries(
      refreshedEntries.map(_mockEntryFromKdbx).toList(),
      preferredEntryUuid: uuid,
    );
  }
}

class _VaultWindow extends StatelessWidget {
  const _VaultWindow({
    required this.titleBarKey,
    required this.width,
    required this.height,
    required this.entries,
    required this.selectedEntry,
    required this.selectedIndex,
    required this.onEntrySelected,
    required this.onOpenNewItemModal,
    required this.onOpenImport,
    required this.onOpenAddCategoryModal,
    required this.onEditCategory,
    required this.onDeleteCategory,
    required this.onOpenEditItem,
    required this.onLockVault,
    required this.onShowToast,
    required this.onRequestDelete,
    required this.onRequestRemovePasskey,
    required this.onRequestRestore,
    required this.onRequestPermanentDelete,
    required this.onOpenSettings,
    required this.onOpenSshAgentSettings,
    required this.onOpenScanTotp,
    required this.onRefreshEntries,
    required this.isRefreshing,
    required this.sortField,
    required this.sortDirection,
    required this.onSortChanged,
    required this.searchQuery,
    required this.onClearSearch,
    required this.onEntryRequested,
    required this.onOpenEntryWebsite,
    required this.onEditEntry,
    required this.onDuplicateEntry,
    required this.onCopyEntryTotp,
    required this.onDeleteEntry,
    required this.isPasswordAuditView,
    required this.passwordAuditReport,
    required this.passwordAuditDuplicatedCount,
    required this.passwordAuditWeakCount,
    required this.passwordAuditStaleCount,
    required this.passwordAuditSelection,
    required this.passwordAuditDuplicateGroups,
    required this.passwordAuditDuplicateGroupSelection,
    required this.onPasswordAuditIssueSelected,
    required this.onPasswordAuditDuplicateGroupSelected,
    required this.onPasswordAuditBack,
  });

  final double width;
  final double height;
  final List<_MockEntry> entries;
  final _MockEntry? selectedEntry;
  final int selectedIndex;
  final ValueChanged<int> onEntrySelected;
  final VoidCallback onOpenNewItemModal;
  final VoidCallback onOpenImport;
  final VoidCallback onOpenAddCategoryModal;
  final void Function(
          ({String uuid, String name, String notes, int count}) category)
      onEditCategory;
  final void Function(
          ({String uuid, String name, String notes, int count}) category)
      onDeleteCategory;
  final VoidCallback onOpenEditItem;
  final VoidCallback onLockVault;
  final ValueChanged<String> onShowToast;
  final VoidCallback onRequestDelete;
  final VoidCallback onRequestRemovePasskey;
  final VoidCallback onRequestRestore;
  final VoidCallback onRequestPermanentDelete;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenSshAgentSettings;
  final VoidCallback onOpenScanTotp;
  final Future<void> Function() onRefreshEntries;
  final bool isRefreshing;
  final _VaultSortField sortField;
  final _VaultSortDirection sortDirection;
  final ValueChanged<_VaultSortField> onSortChanged;
  final String searchQuery;
  final VoidCallback onClearSearch;
  final ValueChanged<String> onEntryRequested;
  final GlobalKey<_VaultTitleBarState> titleBarKey;
  final ValueChanged<int> onOpenEntryWebsite;
  final ValueChanged<int> onEditEntry;
  final ValueChanged<int> onDuplicateEntry;
  final ValueChanged<int> onCopyEntryTotp;
  final ValueChanged<int> onDeleteEntry;
  final bool isPasswordAuditView;
  final List<PasswordAuditEntry> passwordAuditReport;
  final int passwordAuditDuplicatedCount;
  final int passwordAuditWeakCount;
  final int passwordAuditStaleCount;
  final PasswordAuditIssue? passwordAuditSelection;
  final List<DuplicateItemGroup> passwordAuditDuplicateGroups;
  final String? passwordAuditDuplicateGroupSelection;

  final ValueChanged<PasswordAuditIssue> onPasswordAuditIssueSelected;
  final ValueChanged<String> onPasswordAuditDuplicateGroupSelected;
  final VoidCallback onPasswordAuditBack;

  @override
  Widget build(BuildContext context) {
    // Two-column layout with INDEPENDENT top-strip heights.
    //
    //   ┌───────────────────────┬─────────────────────────────────────────┐
    //   │ _VaultGreetingHeader  │ _VaultTitleBar  (~58 px, hugs content)  │
    //   │   (content-sized)     ├─────────────────────────────────────────┤
    //   │                       │ ┌──────────┬──────────────────────────┐ │
    //   ├───────────────────────┤ │ _ListPane│ _DetailPane / _Empty…    │ │
    //   │ _SidebarPane          │ │          │                          │ │
    //   │   (Expanded)          │ └──────────┴──────────────────────────┘ │
    //   └───────────────────────┴─────────────────────────────────────────┘
    //
    // The left column's bottom-border ("divider line") sits flush under
    // the greeting block and is independent of the right column's
    // title-bar height — so the right panel's `Title | Last Edited` row
    // begins flush under the search row, eliminating the previously
    // synced ~46 px gap.
    return Container(
      width: width,
      height: height,
      color: Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // LEFT column ─ greeting header on top + sidebar below.
          SizedBox(
            width: 230,
            child: Column(
              children: <Widget>[
                _VaultGreetingHeader(
                  onSettingsPressed: onOpenSettings,
                ),
                Expanded(
                  child: _SidebarPane(
                    onLockVault: onLockVault,
                    onOpenImport: onOpenImport,
                    onOpenAddCategoryModal: onOpenAddCategoryModal,
                    onEditCategory: onEditCategory,
                    onDeleteCategory: onDeleteCategory,
                  ),
                ),
              ],
            ),
          ),
          // RIGHT column ─ search header on top + content row below.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _VaultTitleBar(
                  key: titleBarKey,
                  onNewItemPressed: onOpenNewItemModal,
                  onImportPressed: onOpenImport,
                  onEntryRequested: onEntryRequested,
                ),
                if (isPasswordAuditView && passwordAuditSelection == null)
                  _PasswordAuditReportPane(
                    report: passwordAuditReport,
                    duplicatedCount: passwordAuditDuplicatedCount,
                    weakCount: passwordAuditWeakCount,
                    staleCount: passwordAuditStaleCount,
                    onIssueSelected: onPasswordAuditIssueSelected,
                  )
                else if (isPasswordAuditView &&
                    passwordAuditSelection == PasswordAuditIssue.duplicated &&
                    passwordAuditDuplicateGroupSelection == null)
                  _PasswordAuditDuplicateGroupsPane(
                    groups: passwordAuditDuplicateGroups,
                    onGroupSelected: onPasswordAuditDuplicateGroupSelected,
                    onBack: onPasswordAuditBack,
                  )
                else
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        _ListPane(
                          entries: _entriesForListPane(),
                          selectedIndex: _safeSelectedIndexForListPane(),
                          onEntrySelected: (clippedIndex) {
                            final clipped = _entriesForListPane();
                            if (clippedIndex < 0 ||
                                clippedIndex >= clipped.length) {
                              return;
                            }
                            final uuid = clipped[clippedIndex].uuid;
                            final fullIndex =
                                entries.indexWhere((e) => e.uuid == uuid);
                            if (fullIndex >= 0) onEntrySelected(fullIndex);
                          },
                          onRefreshEntries: onRefreshEntries,
                          isRefreshing: isRefreshing,
                          sortField: sortField,
                          sortDirection: sortDirection,
                          onSortChanged: onSortChanged,
                          searchQuery: searchQuery,
                          onClearSearch: onClearSearch,
                          onOpenEntryWebsite: (i) =>
                              _forwardClippedIndex(i, onOpenEntryWebsite),
                          onEditEntry: (i) =>
                              _forwardClippedIndex(i, onEditEntry),
                          onDuplicateEntry: (i) =>
                              _forwardClippedIndex(i, onDuplicateEntry),
                          onCopyEntryTotp: (i) =>
                              _forwardClippedIndex(i, onCopyEntryTotp),
                          onDeleteEntry: (i) =>
                              _forwardClippedIndex(i, onDeleteEntry),
                          isPasswordAuditView: isPasswordAuditView,
                          passwordAuditReport: passwordAuditReport,
                          passwordAuditDuplicatedCount:
                              passwordAuditDuplicatedCount,
                          passwordAuditWeakCount: passwordAuditWeakCount,
                          passwordAuditStaleCount: passwordAuditStaleCount,
                          passwordAuditSelection: passwordAuditSelection,
                          passwordAuditDuplicateGroupLabel:
                              _resolveDuplicateGroupLabel(
                            passwordAuditDuplicateGroups,
                            passwordAuditDuplicateGroupSelection,
                          ),
                          onPasswordAuditIssueSelected:
                              onPasswordAuditIssueSelected,
                          onPasswordAuditBack: onPasswordAuditBack,
                        ),
                        if (_resolveSelectedEntry() != null)
                          _DetailPane(
                            entry: _resolveSelectedEntry()!,
                            onShowToast: onShowToast,
                            onRequestDelete: onRequestDelete,
                            onRequestRemovePasskey: onRequestRemovePasskey,
                            onRequestRestore: onRequestRestore,
                            onRequestPermanentDelete: onRequestPermanentDelete,
                            onOpenScanTotp: onOpenScanTotp,
                            onOpenEditItem: onOpenEditItem,
                            onOpenSshAgentSettings: onOpenSshAgentSettings,
                          )
                        else
                          const Expanded(
                            child: _EmptyDetailPane(),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the display label for the currently selected duplicate group,
  /// or null when no group is selected (or when the selection no longer
  /// matches any group, e.g. after a refresh).
  String? _resolveDuplicateGroupLabel(
    List<DuplicateItemGroup> groups,
    String? selectedKey,
  ) {
    if (selectedKey == null) return null;
    for (final group in groups) {
      if (group.key == selectedKey) return group.displayLabel;
    }
    return null;
  }

  /// Defensive filter that ensures the list pane never shows stale
  /// entries leaking from a previous audit scope. When the user has
  /// drilled into a specific duplicate group, the pane must only show
  /// that group's members. The upstream `entries` field comes from a
  /// state-cached `_entries` list which can momentarily lag the
  /// scoped-entries provider during rapid navigation; clipping here
  /// guarantees the visible list always matches the selected group.
  List<_MockEntry> _entriesForListPane() {
    if (!isPasswordAuditView ||
        passwordAuditSelection != PasswordAuditIssue.duplicated ||
        passwordAuditDuplicateGroupSelection == null) {
      return entries;
    }
    DuplicateItemGroup? selectedGroup;
    for (final group in passwordAuditDuplicateGroups) {
      if (group.key == passwordAuditDuplicateGroupSelection) {
        selectedGroup = group;
        break;
      }
    }
    if (selectedGroup == null) {
      return const <_MockEntry>[];
    }
    final allowedUuids =
        selectedGroup.entries.map((entry) => entry.uuid).toSet();
    return entries
        .where((entry) => allowedUuids.contains(entry.uuid))
        .toList(growable: false);
  }

  /// Keeps the selected index inside bounds for the (possibly clipped)
  /// list returned by [_entriesForListPane]. When the upstream selected
  /// index points at an entry that has been filtered out, fall back to
  /// 0 so the detail pane still shows a member of the current group.
  int _safeSelectedIndexForListPane() {
    final clipped = _entriesForListPane();
    if (clipped.isEmpty) return 0;
    if (selectedIndex < 0 || selectedIndex >= clipped.length) return 0;
    return selectedIndex;
  }

  /// Resolves the entry that should be rendered in the detail pane.
  /// When in level-3 of the duplicate-items audit and the upstream
  /// `selectedEntry` doesn't belong to the selected group, return the
  /// first member of the clipped list instead so the user always sees
  /// a member of the group they drilled into.
  _MockEntry? _resolveSelectedEntry() {
    final clipped = _entriesForListPane();
    if (clipped.isEmpty) return null;
    if (selectedEntry != null &&
        clipped.any((entry) => entry.uuid == selectedEntry!.uuid)) {
      return selectedEntry;
    }
    return clipped.first;
  }

  /// Forwards an index emitted by the list pane (which is over the
  /// possibly-clipped entries) back to the underlying full `entries`
  /// list expected by the parent state's index-based callbacks.
  void _forwardClippedIndex(int clippedIndex, ValueChanged<int> onFull) {
    final clipped = _entriesForListPane();
    if (clippedIndex < 0 || clippedIndex >= clipped.length) return;
    final uuid = clipped[clippedIndex].uuid;
    final fullIndex = entries.indexWhere((entry) => entry.uuid == uuid);
    if (fullIndex >= 0) onFull(fullIndex);
  }
}

/// Inherited widget that exposes the 1-second clock ticker to descendants
/// without forcing them to rebuild every tick. Leaf widgets that actually
/// need the current time (e.g. TOTP code / countdown displays) should
/// wrap themselves in a [ValueListenableBuilder] using
/// [_TimeScope.of(context)]; non-subscribing widgets simply ignore the
/// scope and do not rebuild on tick.
class _TimeScope extends InheritedWidget {
  const _TimeScope({
    required this.notifier,
    required super.child,
  });

  final ValueListenable<DateTime> notifier;

  static ValueListenable<DateTime> of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_TimeScope>();
    assert(scope != null, '_TimeScope missing in widget tree');
    return scope!.notifier;
  }

  @override
  bool updateShouldNotify(_TimeScope oldWidget) =>
      notifier != oldWidget.notifier;
}
