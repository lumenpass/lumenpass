import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../../../core/models/database_record.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/bookmark_service.dart';

import '../../../core/services/vault_unlock_service.dart';
import '../../../presentation/theme/app_theme.dart';

import '../../cloud/application/cloud_disconnect.dart';
import '../../cloud/presentation/cloud_services_screen.dart';
import '../../vault/presentation/vault_screen.dart';
import '../application/database_connection_health.dart';
import '../application/database_registry.dart';
import '../application/unlock_controller.dart';
import 'create_database_modal.dart';
import 'duplicate_database_modal.dart';
import 'open_existing_database_modal.dart';
import 'restore_backups_modal.dart';
import 's3_config_dialog.dart';
import 'sftp_config_dialog.dart';
import 'splash_screen.dart';
import 'unlocking_progress_screen.dart';
import 'webdav_config_dialog.dart';

// ── Shared palette ─────────────────────────────────────────────────────────
const Color _kSidebar = Color(0xFFF2F5FA);
const Color _kCanvas = Color(0xFFF6F8FB);
const Color _kBorderSoft = Color(0xFFE1E7F0);
const Color _kBorderRow = Color(0xFFE6EAF0);
const Color _kBorderHover = Color(0xFFD4DDEA);
const Color _kHoverBg = Color(0xFFEAF0FB);
const Color _kTitle = Color(0xFF22314A);
const Color _kLabel = Color(0xFF73839D);
const Color _kIcon = Color(0xFF8A97AC);
const Color _kBlue = Color(0xFF4B6CFF);
const Color _kActionDark = Color(0xFF0A3B48);
const Color _kPanelTextSoft = Colors.white;

const Color _kUnlockDialogBackground = Color(0xFFE7EBF0);
const Color _kUnlockDialogBorder = Color(0xFFC9D2DE);
const Color _kUnlockCardBackground = Color(0xFFE2E7ED);
const Color _kUnlockCardBorder = Color(0xFFD0D8E2);
const Color _kUnlockFieldBackground = Color(0xFFF7F9FB);
const Color _kUnlockFieldText = Color(0xFF1F2937);
const Color _kUnlockHintText = Color(0xFF6E7783);
const Color _kUnlockFieldFocus = Color(0xFF0F67D6);
const Color _kUnlockAccentSoft = Color(0xFFEAF2FF);
const Color _kUnlockAccentBorder = Color(0xFF8BA9D8);
const Color _kUnlockFooterBackground = Color(0xFFDDE4EC);
const Color _kUnlockFooterBorder = Color(0xFFCCD4DF);
const Color _kUnlockGhostBg = Color(0xFFEBEEF3);
const Color _kUnlockGhostBorder = Color(0xFFC0C9D4);
const Color _kUnlockGhostText = Color(0xFF3E4B60);
const Color _kUnlockPrimaryHover = Color(0xFF0D4A59);
const Color _kUnlockPrimaryDisabled = Color(0xFF7F959D);

TextStyle _uText(
  double size,
  Color color, {
  FontWeight fontWeight = FontWeight.w400,
  double? letterSpacing,
  double? height,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: fontWeight,
    fontFamily: 'Inter',
    letterSpacing: letterSpacing,
    height: height,
  );
}

enum _DatabaseSortField { recent, name, createdAt }

enum UnlockAutoPromptMode {
  none,
  immediate,
  onFocus,
}

enum VaultLockedReason {
  manual,
  timeout,
}

class UnlockScreenArgs {
  const UnlockScreenArgs({
    this.lockedPath,
    this.lockedReason = VaultLockedReason.manual,
  });

  final String? lockedPath;
  final VaultLockedReason lockedReason;
}

/// Vault selection screen — lists registered databases.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  static const String routeName = '/';

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  static const MethodChannel _windowChannel = MethodChannel('lumenpass/window');
  static const double _kWindowHeight = 480.0;
  bool _showSplash = false;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, DatabaseConnectionHealth> _databaseHealth =
      <String, DatabaseConnectionHealth>{};
  String? _selectedDatabaseId;
  _DatabaseSortField _sortField = _DatabaseSortField.recent;
  bool _sortAscending = true;
  bool _isRefreshingDatabaseHealth = false;
  String _databaseHealthSignature = '';
  int _databaseHealthGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
      _windowChannel.invokeMethod<void>(
        'showNativeTitleBar',
        <String, dynamic>{'title': 'LumenPass - Password Manager'},
      );
      _windowChannel.invokeMethod<void>(
        'setSize',
        <String, double>{'width': 820, 'height': _kWindowHeight},
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      final String? lockedPath;
      final VaultLockedReason lockedReason;
      if (args is UnlockScreenArgs) {
        lockedPath = args.lockedPath;
        lockedReason = args.lockedReason;
      } else if (args is String) {
        lockedPath = args;
        lockedReason = VaultLockedReason.manual;
      } else {
        lockedPath = null;
        lockedReason = VaultLockedReason.manual;
      }

      if (lockedPath != null && lockedPath.isNotEmpty) {
        unawaited(_openLockedVault(lockedPath, lockedReason: lockedReason));
      } else {
        // Fresh startup — show the splash for visual flair.
        setState(() => _showSplash = true);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final databases = ref.watch(databaseRegistryProvider);
    _scheduleDatabaseHealthChecks(databases);
    final visibleDatabases = _visibleDatabases(databases);
    final selectedRecord = _selectedRecordFrom(visibleDatabases);

    final selectedHealth =
        selectedRecord == null ? null : _databaseHealth[selectedRecord.id];
    final canUnlockSelected = selectedRecord != null &&
        !_isDatabaseInteractionBlocked(selectedRecord, health: selectedHealth);

    final unlockContent = Theme(
      data: AppTheme.light(),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Left: database list
            Expanded(
              flex: 3,
              child: Container(
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _buildHeader(),
                          const SizedBox(height: 14),
                          _SearchField(
                            controller: _searchController,
                            onChanged: (_) => setState(() {}),
                            onClear: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          ),
                          if (databases.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 12),
                            _DatabaseListHeader(
                              sortField: _sortField,
                              sortAscending: _sortAscending,
                              onSort: _toggleSort,
                              isRefreshing: _isRefreshingDatabaseHealth,
                              onRefresh: _refreshAllDatabaseHealth,
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: databases.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(20),
                              child: const _EmptyDatabaseState(),
                            )
                          : visibleDatabases.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: _EmptySearchState(),
                                )
                              : ListView.separated(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 10, 20, 20),
                                  itemCount: visibleDatabases.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 6),
                                  itemBuilder: (_, index) {
                                    final db = visibleDatabases[index];
                                    final health = _databaseHealth[db.id];

                                    return _DatabaseRow(
                                      record: db,
                                      selected: selectedRecord?.id == db.id,
                                      health: health,
                                      onTap: _isDatabaseInteractionBlocked(
                                        db,
                                        health: health,
                                      )
                                          ? null
                                          : () => _selectDatabase(db),
                                      onDoubleTap:
                                          _isDatabaseInteractionBlocked(
                                        db,
                                        health: health,
                                      )
                                              ? null
                                              : () => _handleOpenDatabase(
                                                    db,
                                                    autoPromptMode:
                                                        UnlockAutoPromptMode
                                                            .immediate,
                                                  ),
                                      onShowHealthDetails: health != null &&
                                              health.hasError
                                          ? () => _showDatabaseHealthDetails(db)
                                          : null,
                                      onSetDefault: () =>
                                          _handleSetDefaultDatabase(db),
                                      onSaveAs: () => _handleSaveDatabaseAs(db),
                                      onDuplicate: () =>
                                          _handleDuplicateDatabase(db),
                                      onRestore: () =>
                                          _handleRestoreDatabase(db),
                                      onRemove: () => _handleRemoveDatabase(db),
                                    );
                                  },
                                ),
                    ),
                    _UnlockFooterBar(
                      selectedRecord: selectedRecord,
                      onExit: _handleExitApp,
                      onUnlock: !canUnlockSelected
                          ? null
                          : () => _handleOpenDatabase(
                                selectedRecord,
                                autoPromptMode: UnlockAutoPromptMode.immediate,
                              ),
                    ),
                  ],
                ),
              ),
            ),
            // Vertical divider
            Container(width: 1, color: _kBorderSoft),
            // Right: greeting header (top) + guide panel (below)
            Expanded(
              flex: 2,
              child: Container(
                color: _kSidebar,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const <Widget>[
                    _UnlockGreetingHeader(),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: _VaultGuidePanel(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (_showSplash) {
      return DesktopSplashScreen(
        onFinished: () {
          setState(() => _showSplash = false);
        },
      );
    }

    return unlockContent;
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorderSoft),
              ),
              child: const Icon(
                TablerIcons.database,
                size: 17,
                color: _kTitle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Your Databases',
                style: _uText(15, _kTitle, fontWeight: FontWeight.w700),
              ),
            ),
            _HeaderIconButton(
              icon: TablerIcons.plus,
              tooltip: 'Create database',
              onTap: _openCreateDatabase,
              primary: true,
            ),
            const SizedBox(width: 8),
            _HeaderIconButton(
              icon: TablerIcons.folder_open,
              tooltip: 'Open existing database',
              onTap: _openExistingDatabase,
              primary: false,
            ),
            const SizedBox(width: 8),
            _HeaderIconButton(
              icon: TablerIcons.cloud,
              tooltip: 'Cloud Services',
              onTap: _openCloudServices,
              primary: false,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Choose a database, then unlock it from the footer.',
          style: _uText(12, _kLabel),
        ),
      ],
    );
  }

  void _scheduleDatabaseHealthChecks(List<DatabaseRecord> databases) {
    final signature = databases
        .where(isCloudBackedDatabaseRecord)
        .map(
          (record) => <String>[
            record.id,
            record.storageType,
            record.cloudFileId ?? '',
            record.databasePath,
          ].join('::'),
        )
        .join('|');
    if (_databaseHealthSignature == signature) {
      return;
    }
    _databaseHealthSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refreshDatabaseHealth(databases));
    });
  }

  bool _isDatabaseInteractionBlocked(
    DatabaseRecord record, {
    DatabaseConnectionHealth? health,
  }) {
    if (!isCloudBackedDatabaseRecord(record)) return false;
    if (health == null) return true;
    return health.blocksUnlock;
  }

  Future<void> _refreshDatabaseHealth(List<DatabaseRecord> databases) async {
    final generation = ++_databaseHealthGeneration;
    final cloudRecords =
        databases.where(isCloudBackedDatabaseRecord).toList(growable: false);
    final nextHealth = <String, DatabaseConnectionHealth>{
      for (final entry in _databaseHealth.entries)
        if (cloudRecords.any((record) => record.id == entry.key))
          entry.key: entry.value,
    };
    for (final record in cloudRecords) {
      nextHealth[record.id] = DatabaseConnectionHealth.checking(
        providerLabel: providerLabelForStorageType(record.storageType),
        checkedAt: DateTime.now(),
      );
    }
    if (mounted) {
      setState(() {
        _isRefreshingDatabaseHealth = true;
        _databaseHealth
          ..clear()
          ..addAll(nextHealth);
      });
    }

    final probe = ref.read(databaseConnectionHealthProbeProvider);
    try {
      await Future.wait(
        cloudRecords.map((record) async {
          DatabaseConnectionHealth health;
          try {
            health = await probe.check(record);
          } catch (error) {
            health = DatabaseConnectionHealth.error(
              code: 'health_probe_failed',
              providerLabel: providerLabelForStorageType(record.storageType),
              title: 'Could not verify this vault',
              details: normalizeDatabaseHealthError(error),
              recommendedActions: <String>[
                'Run Check again.',
                'Reconnect the storage provider if the problem persists.',
              ],
              checkedAt: DateTime.now(),
            );
          }
          if (!mounted || generation != _databaseHealthGeneration) {
            return;
          }
          setState(() {
            _databaseHealth[record.id] = health;
          });
        }),
      );
    } finally {
      if (mounted && generation == _databaseHealthGeneration) {
        setState(() => _isRefreshingDatabaseHealth = false);
      }
    }
  }

  Future<void> _refreshAllDatabaseHealth() async {
    await _refreshDatabaseHealth(ref.read(databaseRegistryProvider));
  }

  Future<DatabaseConnectionHealth> _refreshSingleDatabaseHealth(
    DatabaseRecord record,
  ) async {
    if (!isCloudBackedDatabaseRecord(record)) {
      return DatabaseConnectionHealth.healthy(
        providerLabel: providerLabelForStorageType(record.storageType),
        checkedAt: DateTime.now(),
      );
    }

    if (mounted) {
      setState(() {
        _databaseHealth[record.id] = DatabaseConnectionHealth.checking(
          providerLabel: providerLabelForStorageType(record.storageType),
          checkedAt: DateTime.now(),
        );
      });
    }

    DatabaseConnectionHealth health;
    try {
      health = await ref.read(databaseConnectionHealthProbeProvider).check(
            record,
          );
    } catch (error) {
      health = DatabaseConnectionHealth.error(
        code: 'health_probe_failed',
        providerLabel: providerLabelForStorageType(record.storageType),
        title: 'Could not verify this vault',
        details: normalizeDatabaseHealthError(error),
        recommendedActions: <String>[
          'Run Check again.',
          'Reconnect the storage provider if the problem persists.',
        ],
        checkedAt: DateTime.now(),
      );
    }
    if (mounted) {
      setState(() {
        _databaseHealth[record.id] = health;
      });
    }
    return health;
  }

  Future<bool> _ensureDatabaseHealthAllowsUnlock(DatabaseRecord record) async {
    if (!isCloudBackedDatabaseRecord(record)) {
      return true;
    }

    final current = _databaseHealth[record.id];
    final health = current == null || current.isChecking || current.hasError
        ? await _refreshSingleDatabaseHealth(record)
        : current;
    if (!mounted) return false;
    if (health.isHealthy) return true;

    await _showDatabaseHealthDetails(record);
    final settled = _databaseHealth[record.id];
    return settled != null && settled.isHealthy;
  }

  Future<void> _showDatabaseHealthDetails(DatabaseRecord record) async {
    final health = _databaseHealth[record.id];
    if (health == null || !health.hasError || !mounted) {
      return;
    }

    final action = await showDialog<_DatabaseHealthDialogAction>(
      context: context,
      builder: (_) => _DatabaseHealthIssueDialog(
        record: record,
        health: health,
      ),
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _DatabaseHealthDialogAction.close:
        return;
      case _DatabaseHealthDialogAction.retry:
        final refreshed = await _refreshSingleDatabaseHealth(record);
        if (!mounted) return;
        if (refreshed.isHealthy) {
          _showSuccessSnack('${record.nickname} is ready to sync again.');
        } else {
          _showErrorSnack(
            refreshed.title ?? 'This vault still needs attention.',
          );
        }
        return;
      case _DatabaseHealthDialogAction.reconnect:
        final reconnected = await _reconnectCloudProvider(record.storageType);
        if (!mounted || !reconnected) return;
        final refreshed = await _refreshSingleDatabaseHealth(record);
        if (!mounted) return;
        if (refreshed.isHealthy) {
          _showSuccessSnack('${record.nickname} is ready to sync again.');
        } else {
          _showErrorSnack(
            refreshed.title ?? 'This vault still needs attention.',
          );
        }
        return;
      case _DatabaseHealthDialogAction.unlinkDatabases:
        await _unlinkCloudDatabasesForProvider(record);
        return;
    }
  }

  Future<void> _unlinkCloudDatabasesForProvider(DatabaseRecord record) async {
    final providerLabel = providerLabelForStorageType(record.storageType);
    final confirmed = await confirmUnlinkCloudDatabases(
      context,
      providerLabel: providerLabel,
    );
    if (!confirmed || !mounted) return;

    try {
      final removed = await unlinkCloudDatabasesByStorageType(
        ref,
        record.storageType,
      );
      if (!mounted) return;

      setState(() {
        for (final removedRecord in removed) {
          _databaseHealth.remove(removedRecord.id);
        }
        if (_selectedDatabaseId != null &&
            removed.any((r) => r.id == _selectedDatabaseId)) {
          _selectedDatabaseId = null;
        }
      });

      if (removed.isEmpty) {
        _showSuccessSnack('No $providerLabel vaults were linked in this app.');
      } else {
        _showSuccessSnack(
          removed.length == 1
              ? 'Removed 1 $providerLabel vault from this app.'
              : 'Removed ${removed.length} $providerLabel vaults from this app.',
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnack('Could not unlink $providerLabel vaults: $e');
      }
    }
  }

  List<DatabaseRecord> _visibleDatabases(List<DatabaseRecord> databases) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = databases.where((record) {
      if (query.isEmpty) {
        return true;
      }
      return record.nickname.toLowerCase().contains(query) ||
          record.databasePath.toLowerCase().contains(query) ||
          _locationLabel(record).toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) {
      if (a.isDefaultStartup != b.isDefaultStartup) {
        return a.isDefaultStartup ? -1 : 1;
      }

      int result;
      switch (_sortField) {
        case _DatabaseSortField.recent:
          // Most recently opened first; never-opened vaults sink to the bottom.
          final aTime = a.lastOpenedAt;
          final bTime = b.lastOpenedAt;
          if (aTime == null && bTime == null) {
            result = 0;
          } else if (aTime == null) {
            return 1;
          } else if (bTime == null) {
            return -1;
          } else {
            result = bTime.compareTo(aTime);
          }
          break;
        case _DatabaseSortField.name:
          result = a.nickname.toLowerCase().compareTo(b.nickname.toLowerCase());
          break;
        case _DatabaseSortField.createdAt:
          result = a.addedAt.compareTo(b.addedAt);
          break;
      }

      if (result == 0) {
        result = a.nickname.toLowerCase().compareTo(b.nickname.toLowerCase());
      }

      // The recent sort defines its own descending order above; the ascending
      // toggle only applies to the column-based Name / Created at sorts.
      if (_sortField == _DatabaseSortField.recent) {
        return result;
      }
      return _sortAscending ? result : -result;
    });

    return filtered;
  }

  DatabaseRecord? _selectedRecordFrom(List<DatabaseRecord> databases) {
    if (databases.isEmpty) {
      return null;
    }

    final selectedId = _selectedDatabaseId;
    if (selectedId == null) {
      return null;
    }

    for (final record in databases) {
      if (record.id == selectedId) {
        return record;
      }
    }

    return null;
  }

  void _selectDatabase(DatabaseRecord record) {
    setState(() => _selectedDatabaseId = record.id);
  }

  void _toggleSort(_DatabaseSortField field) {
    setState(() {
      if (field == _DatabaseSortField.recent) {
        // Recent has a fixed "most recent first" order; no direction toggle.
        _sortField = field;
        return;
      }
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = field;
        _sortAscending = field == _DatabaseSortField.name;
      }
    });
  }

  Future<void> _handleOpenDatabase(
    DatabaseRecord record, {
    required UnlockAutoPromptMode autoPromptMode,
  }) async {
    final dbPath = await _resolveDatabasePath(record);
    if (!mounted) return;

    final readyForUnlock = await _ensureDatabaseHealthAllowsUnlock(record);
    if (!mounted || !readyForUnlock) return;

    final controller = ref.read(unlockControllerProvider.notifier);
    await controller.resetForNewVault(dbPath);
    if (!mounted) return;

    final bool? unlocked = await showDialog<bool>(
      // ignore: use_build_context_synchronously
      context: context,
      builder: (_) => _UnlockCredentialsDialog(autoPromptMode: autoPromptMode),
    );

    if (!mounted || unlocked != true) {
      return;
    }

    // Record recency so the unlock screen can sort vaults by last opened.
    unawaited(
      ref.read(databaseRegistryProvider.notifier).setLastOpenedAt(record.id),
    );

    Navigator.of(context).pushReplacementNamed(VaultScreen.routeName);
  }

  Future<String> _resolveDatabasePath(DatabaseRecord record) async {
    // Resolve security-scoped bookmark to regain file access across restarts.
    String dbPath = record.databasePath;
    if (record.bookmark != null && record.bookmark!.isNotEmpty) {
      final resolved = await BookmarkService.instance
          .resolveAndStartAccessing(record.bookmark!);
      if (resolved != null && resolved.isNotEmpty) {
        dbPath = resolved;
      }
    }
    return dbPath;
  }

  Future<bool> _reconnectCloudProvider(String storageType) async {
    try {
      switch (storageType) {
        case 'googleDrive':
          await BackupService.instance.connectGoogle();
          return BackupService.instance.isGoogleConnected;
        case 'dropbox':
          await BackupService.instance.connectDropbox();
          return BackupService.instance.currentDropboxToken != null;
        case 'oneDrive':
          await BackupService.instance.connectOneDrive();
          return BackupService.instance.isOneDriveConnected;
        case 'webdav':
          final account = await showDialog<String?>(
            context: context,
            barrierDismissible: false,
            builder: (_) => WebDavConfigDialog(
              initialConfig: BackupService.instance.currentWebDavConfig,
            ),
          );
          if (!mounted) return false;
          return account != null && BackupService.instance.isWebDavConnected;
        case 'sftp':
          final account = await showDialog<String?>(
            context: context,
            barrierDismissible: false,
            builder: (_) => SftpConfigDialog(
              initialConfig: BackupService.instance.currentSftpConfig,
            ),
          );
          if (!mounted) return false;
          return account != null && BackupService.instance.isSftpConnected;
        case 's3':
          final account = await showDialog<String?>(
            context: context,
            barrierDismissible: false,
            builder: (_) => S3ConfigDialog(),
          );
          if (!mounted) return false;
          return account != null &&
              BackupService.instance.currentS3Account != null;
      }
      return false;
    } catch (e) {
      if (mounted) {
        _showErrorSnack('Reconnect failed: $e');
      }
      return false;
    }
  }

  Future<void> _openLockedVault(
    String lockedPath, {
    required VaultLockedReason lockedReason,
  }) async {
    await ref.read(databaseRegistryProvider.notifier).ready;
    if (!mounted) return;
    final databases = ref.read(databaseRegistryProvider);
    if (databases.isEmpty) return;
    final record = databases.firstWhere(
      (db) => db.databasePath == lockedPath,
      orElse: () => databases.first,
    );
    final autoPromptMode = switch (lockedReason) {
      VaultLockedReason.manual => UnlockAutoPromptMode.none,
      VaultLockedReason.timeout => UnlockAutoPromptMode.onFocus,
    };
    await _handleOpenDatabase(
      record,
      autoPromptMode: autoPromptMode,
    );
  }

  Future<void> _openCreateDatabase() async {
    if (Platform.isMacOS) {
      await _windowChannel.invokeMethod<void>(
        'setSize',
        <String, double>{'width': 820, 'height': 720},
      );
    }

    if (!mounted) return;

    String? createdPath;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CreateDatabaseModal(
        onCreated: (String dbPath, String nickname) async {
          // addDatabase is already called inside the modal; just capture path.
          createdPath = dbPath;
        },
      ),
    );

    if (Platform.isMacOS && mounted) {
      await _windowChannel.invokeMethod<void>(
        'setSize',
        <String, double>{'width': 820, 'height': _kWindowHeight},
      );
    }

    if (createdPath != null && mounted) {
      final createdRecord = _recordForPath(createdPath!);
      if (createdRecord != null) {
        setState(() => _selectedDatabaseId = createdRecord.id);
      }
    }
  }

  Future<void> _openExistingDatabase() async {
    if (Platform.isMacOS) {
      await _windowChannel.invokeMethod<void>(
        'setSize',
        <String, double>{'width': 820, 'height': 620},
      );
    }

    if (!mounted) return;

    String? openedPath;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OpenExistingDatabaseModal(
        onOpened: (String dbPath) async {
          openedPath = dbPath;
        },
      ),
    );

    if (Platform.isMacOS && mounted) {
      await _windowChannel.invokeMethod<void>(
        'setSize',
        <String, double>{'width': 820, 'height': _kWindowHeight},
      );
    }

    if (openedPath != null && mounted) {
      final addedRecord = _recordForPath(openedPath!);
      if (addedRecord != null) {
        setState(() => _selectedDatabaseId = addedRecord.id);
      }
    }
  }

  Future<void> _openCloudServices() async {
    // Give the management screen more vertical room on macOS, then restore
    // the compact unlock-window size when the user returns.
    if (Platform.isMacOS) {
      await _windowChannel.invokeMethod<void>(
        'setSize',
        <String, double>{'width': 820, 'height': 640},
      );
    }

    if (!mounted) return;

    await Navigator.of(context).pushNamed(CloudServicesScreen.routeName);

    if (Platform.isMacOS && mounted) {
      await _windowChannel.invokeMethod<void>(
        'setSize',
        <String, double>{'width': 820, 'height': _kWindowHeight},
      );
    }

    if (!mounted) return;
    _databaseHealthSignature = '';
    await _refreshDatabaseHealth(ref.read(databaseRegistryProvider));
  }

  void _showErrorSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: _uText(12, Colors.white)),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showSuccessSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: _uText(12, Colors.white)),
        backgroundColor: _kActionDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _handleRemoveDatabase(DatabaseRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Remove "${record.nickname}"?',
          style: _uText(15, _kTitle, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This removes the database from LumenPass. The file on disk is not deleted.',
          style: _uText(12, _kLabel),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: _uText(12, _kLabel)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Remove',
              style: _uText(12, const Color(0xFFEF4444),
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(databaseRegistryProvider.notifier).removeDatabase(
            record.id,
          );
      if (mounted && _selectedDatabaseId == record.id) {
        setState(() => _selectedDatabaseId = null);
      }
    }
  }

  Future<void> _handleSetDefaultDatabase(DatabaseRecord record) async {
    await ref
        .read(databaseRegistryProvider.notifier)
        .setDefaultStartupDatabase(record.id);
    if (mounted) {
      setState(() => _selectedDatabaseId = record.id);
    }
  }

  /// Opens the restore-backups modal for a database that is still locked
  /// (or too corrupted to unlock). Backups are listed by vault path, so
  /// recovery works without opening the vault first.
  Future<void> _handleRestoreDatabase(DatabaseRecord record) async {
    if (!kBackupRestoreFeatureEnabled) {
      _showErrorSnack('Backup restore is not available in this build.');
      return;
    }

    try {
      final targetPath = await _resolveDatabasePath(record);
      if (!mounted) return;

      final restored = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RestoreBackupsModal(
          record: record,
          targetVaultPath: targetPath,
        ),
      );

      if (!mounted || restored != true) return;

      setState(() => _selectedDatabaseId = record.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Backup restored. Unlock to access the restored data.',
            style: _uText(12, Colors.white),
          ),
          backgroundColor: _kActionDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      _showErrorSnack('Could not open restore: $e');
    }
  }

  Future<void> _handleSaveDatabaseAs(DatabaseRecord record) async {
    try {
      final sourcePath = await _resolveDatabasePath(record);
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        _showErrorSnack('Could not find the selected database file.');
        return;
      }

      final defaultName = _suggestSaveAsFileName(record);
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Database As',
        fileName: defaultName,
        lockParentWindow: true,
        type: Platform.isMacOS ? FileType.any : FileType.custom,
        allowedExtensions: Platform.isMacOS ? null : <String>['kdbx', 'kdb'],
      );
      if (destination == null || destination.isEmpty) {
        return;
      }

      final normalized = _ensureKdbxExtension(destination);
      if (p.normalize(normalized) == p.normalize(sourcePath)) {
        _showErrorSnack(
          'Pick a different location — the selected path is the source file.',
        );
        return;
      }

      await sourceFile.copy(normalized);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved a copy to ${p.basename(normalized)}',
            style: _uText(12, Colors.white),
          ),
          backgroundColor: _kActionDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } on MissingPluginException {
      _showErrorSnack('File picker is unavailable.');
    } catch (e) {
      _showErrorSnack('Could not save database: $e');
    }
  }

  String _suggestSaveAsFileName(DatabaseRecord record) {
    final source =
        (record.cloudFileName != null && record.cloudFileName!.isNotEmpty)
            ? record.cloudFileName!
            : p.basename(record.databasePath);
    final extension = p.extension(source).toLowerCase();
    final base = p.basenameWithoutExtension(source).trim();
    final safeBase = (base.isEmpty ? record.nickname : base).replaceAll(
      RegExp(r'[\\/:*?"<>|]'),
      '_',
    );
    final ext =
        (extension == '.kdbx' || extension == '.kdb') ? extension : '.kdbx';
    return '$safeBase$ext';
  }

  String _ensureKdbxExtension(String path) {
    final extension = p.extension(path).toLowerCase();
    if (extension == '.kdbx' || extension == '.kdb') {
      return path;
    }
    return '$path.kdbx';
  }

  Future<void> _handleDuplicateDatabase(DatabaseRecord record) async {
    try {
      final sourcePath = await _resolveDatabasePath(record);

      if (!mounted) return;

      if (Platform.isMacOS) {
        await _windowChannel.invokeMethod<void>(
          'setSize',
          <String, double>{'width': 820, 'height': 600},
        );
      }

      String? duplicatePath;

      if (!mounted) return;
      await showDialog<void>(
        // ignore: use_build_context_synchronously
        context: context,
        barrierDismissible: false,
        builder: (_) => DuplicateDatabaseModal(
          source: record,
          sourcePath: sourcePath,
          defaultNickname: _nextDuplicateNickname(
            record.nickname,
            ref.read(databaseRegistryProvider),
          ),
          onDuplicated: (dbPath) async {
            duplicatePath = dbPath;
          },
        ),
      );

      if (Platform.isMacOS && mounted) {
        await _windowChannel.invokeMethod<void>(
          'setSize',
          <String, double>{'width': 820, 'height': _kWindowHeight},
        );
      }

      if (duplicatePath != null && mounted) {
        final duplicatedRecord = _recordForPath(duplicatePath!);
        if (duplicatedRecord != null) {
          setState(() => _selectedDatabaseId = duplicatedRecord.id);
        }
      }
    } catch (e) {
      _showErrorSnack('Could not duplicate database: $e');
    }
  }

  String _nextDuplicateNickname(
    String nickname,
    List<DatabaseRecord> existingRecords,
  ) {
    final existingNames =
        existingRecords.map((record) => record.nickname).toSet();
    String candidate = '$nickname Copy';
    int index = 2;
    while (existingNames.contains(candidate)) {
      candidate = '$nickname Copy $index';
      index += 1;
    }
    return candidate;
  }

  DatabaseRecord? _recordForPath(String databasePath) {
    for (final record in ref.read(databaseRegistryProvider)) {
      if (record.databasePath == databasePath) {
        return record;
      }
    }
    return null;
  }

  Future<void> _handleExitApp() async {
    if (Platform.isMacOS) {
      try {
        await _windowChannel.invokeMethod<void>('quit');
        return;
      } catch (_) {}
    }
    exit(0);
  }
}

// ── Database row ────────────────────────────────────────────────────────────

class _DatabaseRow extends StatefulWidget {
  const _DatabaseRow({
    required this.record,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSetDefault,
    required this.onSaveAs,
    required this.onDuplicate,
    required this.onRestore,
    required this.onRemove,
    this.health,
    this.onShowHealthDetails,
  });

  final DatabaseRecord record;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback onSetDefault;
  final VoidCallback onSaveAs;
  final VoidCallback onDuplicate;
  final VoidCallback onRestore;
  final VoidCallback onRemove;
  final DatabaseConnectionHealth? health;
  final VoidCallback? onShowHealthDetails;

  @override
  State<_DatabaseRow> createState() => _DatabaseRowState();
}

class _DatabaseRowState extends State<_DatabaseRow> {
  bool _hovered = false;

  static const Color _menuSurface = Color(0xFFFFFFFF);
  static const Color _menuText = Color(0xFF243247);
  static const Color _menuBorder = Color(0xFFDDE6F2);

  PopupMenuItem<String> _menuItem({
    required String value,
    required IconData icon,
    required String label,
    required Color iconColor,
    bool isDestructive = false,
    bool showBottomDivider = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          border: showBottomDivider
              ? const Border(
                  bottom: BorderSide(color: Color(0xFFE6ECF4)),
                )
              : null,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: _uText(
                11,
                isDestructive ? const Color(0xFFB42318) : _menuText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildContextMenuEntries() {
    final actions = <({
      String value,
      IconData icon,
      String label,
      Color iconColor,
      bool isDestructive,
    })>[
      if (!widget.record.isDefaultStartup)
        (
          value: 'default',
          icon: TablerIcons.star,
          label: 'Set Default',
          iconColor: const Color(0xFFD97706),
          isDestructive: false,
        ),
      (
        value: 'save_as',
        icon: TablerIcons.device_floppy,
        label: 'Save Database As',
        iconColor: const Color(0xFF0F766E),
        isDestructive: false,
      ),
      (
        value: 'duplicate',
        icon: TablerIcons.copy,
        label: 'Duplicate',
        iconColor: const Color(0xFF4F46E5),
        isDestructive: false,
      ),
      if (kBackupRestoreFeatureEnabled)
        (
          value: 'restore',
          icon: TablerIcons.history,
          label: 'Restore',
          iconColor: const Color(0xFF0F766E),
          isDestructive: false,
        ),
      (
        value: 'remove',
        icon: TablerIcons.trash,
        label: 'Remove',
        iconColor: const Color(0xFFDC2626),
        isDestructive: true,
      ),
    ];

    return <PopupMenuEntry<String>>[
      for (var index = 0; index < actions.length; index++)
        _menuItem(
          value: actions[index].value,
          icon: actions[index].icon,
          label: actions[index].label,
          iconColor: actions[index].iconColor,
          isDestructive: actions[index].isDestructive,
          showBottomDivider: index < actions.length - 1,
        ),
    ];
  }

  Future<String?> _showStyledContextMenu({
    required BuildContext menuContext,
    required RelativeRect position,
  }) {
    return showMenu<String>(
      context: menuContext,
      position: position,
      items: _buildContextMenuEntries(),
      color: _menuSurface,
      surfaceTintColor: _menuSurface,
      shadowColor: const Color(0x22000000),
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _menuBorder),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 2),
      constraints: const BoxConstraints(
        minWidth: 186,
        maxWidth: 240,
      ),
    );
  }

  void _handleMenuSelection(String choice) {
    switch (choice) {
      case 'default':
        widget.onSetDefault();
        break;
      case 'save_as':
        widget.onSaveAs();
        break;
      case 'duplicate':
        widget.onDuplicate();
        break;
      case 'restore':
        widget.onRestore();
        break;
      case 'remove':
        widget.onRemove();
        break;
    }
  }

  Future<void> _showMenuAtPoint(
    BuildContext menuContext,
    Offset globalPosition,
  ) async {
    widget.onTap?.call();
    final overlayContext = Overlay.maybeOf(context)?.context;
    final overlayBox = overlayContext?.findRenderObject();
    if (overlayBox is! RenderBox) {
      return;
    }
    final selection = await _showStyledContextMenu(
      menuContext: menuContext,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlayBox.size,
      ),
    );
    if (!mounted || selection == null) {
      return;
    }
    _handleMenuSelection(selection);
  }

  Future<void> _showMenuAnchoredTo(
    BuildContext menuContext,
    BuildContext anchorContext,
  ) async {
    widget.onTap?.call();
    final overlayContext = Overlay.maybeOf(context)?.context;
    final overlayBox = overlayContext?.findRenderObject();
    final anchorBox = anchorContext.findRenderObject();
    if (overlayBox is! RenderBox || anchorBox is! RenderBox) {
      return;
    }
    final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final bottomRight = anchorBox.localToGlobal(
      anchorBox.size.bottomRight(Offset.zero),
      ancestor: overlayBox,
    );
    final selection = await _showStyledContextMenu(
      menuContext: menuContext,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlayBox.size,
      ),
    );
    if (!mounted || selection == null) {
      return;
    }
    _handleMenuSelection(selection);
  }

  @override
  Widget build(BuildContext context) {
    final health = widget.health;
    final isCloudBacked = isCloudBackedDatabaseRecord(widget.record);
    final isPendingCheck = isCloudBacked && health == null;
    final isChecking = (health?.isChecking ?? false) || isPendingCheck;
    final hasHealthError = health?.hasError ?? false;
    final disabled = isPendingCheck || isChecking || hasHealthError;
    final highlighted = widget.selected || _hovered;
    final titleColor = hasHealthError
        ? const Color(0xFF9F1239)
        : widget.selected
            ? Colors.white
            : isChecking
                ? _kLabel
                : _kTitle;
    final subtitleColor = hasHealthError
        ? const Color(0xFFBE123C)
        : widget.selected
            ? _kPanelTextSoft
            : isChecking
                ? _kIcon
                : _kLabel;
    final backgroundColor = hasHealthError
        ? const Color(0xFFFFFBFB)
        : widget.selected
            ? _kActionDark
            : isChecking
                ? const Color(0xFFFAFBFD)
                : Colors.white;
    final borderColor = hasHealthError
        ? const Color(0xFFF3C2C2)
        : highlighted
            ? (widget.selected ? const Color(0xFF2B6A76) : _kBorderHover)
            : isChecking
                ? _kBorderSoft
                : _kBorderRow;
    final locationText = hasHealthError
        ? health?.title ?? 'This vault needs attention.'
        : isChecking
            ? 'Checking connection status…'
            : _locationLabel(widget.record);
    final indicatorHealth = isPendingCheck
        ? DatabaseConnectionHealth.checking(
            providerLabel:
                providerLabelForStorageType(widget.record.storageType),
            checkedAt: DateTime.now(),
          )
        : health;

    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: const Color(0xFFEAF1FC),
        highlightColor: const Color(0x144D79C7),
        splashColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
      ),
      child: Builder(
        builder: (menuContext) {
          return MouseRegion(
            cursor:
                disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              onDoubleTap: widget.onDoubleTap,
              onSecondaryTapDown: isChecking
                  ? null
                  : (details) {
                      _showMenuAtPoint(menuContext, details.globalPosition);
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: 66,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: borderColor,
                    width: widget.selected ? 1.4 : 1,
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Opacity(
                      opacity: isChecking ? 0.62 : 1,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          _DatabaseBadge(
                              record: widget.record, selected: widget.selected),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Flexible(
                                      child: Text(
                                        widget.record.nickname,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: _uText(
                                          13,
                                          titleColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (widget
                                        .record.isDefaultStartup) ...<Widget>[
                                      const SizedBox(width: 8),
                                      _StatusChip(
                                        icon: TablerIcons.star_filled,
                                        label: 'Default',
                                        backgroundColor: widget.selected
                                            ? const Color(0x1FFFFFFF)
                                            : const Color(0xFFEEF3FF),
                                        foregroundColor: widget.selected
                                            ? Colors.white
                                            : _kBlue,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  locationText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _uText(
                                    11,
                                    subtitleColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 110,
                            child: Text(
                              _formatCreatedAt(widget.record.addedAt),
                              textAlign: TextAlign.left,
                              style: _uText(
                                11,
                                hasHealthError
                                    ? const Color(0xFF9F1239)
                                    : widget.selected
                                        ? Colors.white
                                        : isChecking
                                            ? _kIcon
                                            : _kLabel,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Builder(
                            builder: (anchorContext) => _DatabaseItemMenu(
                              selected: widget.selected,
                              enabled: !isChecking,
                              onTap: isChecking
                                  ? null
                                  : () => _showMenuAnchoredTo(
                                        menuContext,
                                        anchorContext,
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if ((isChecking || hasHealthError) &&
                        indicatorHealth != null)
                      Positioned(
                        right: 2,
                        bottom: 0,
                        child: _DatabaseHealthIndicator(
                          health: indicatorHealth,
                          onTap: widget.onShowHealthDetails,
                          compact: true,
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
  }
}

class _DatabaseBadge extends StatelessWidget {
  const _DatabaseBadge({required this.record, required this.selected});

  final DatabaseRecord record;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final String asset;
    final Color bg;
    switch (record.storageType) {
      case 'googleDrive':
        asset = 'assets/images/google-drive.png';
        bg = const Color(0xFFF0F4FF);
        break;
      case 'dropbox':
        asset = 'assets/images/dropbox.png';
        bg = const Color(0xFFEFF6FF);
        break;
      case 'oneDrive':
        asset = 'assets/images/onedrive.png';
        bg = const Color(0xFFE8F4FD);
        break;
      case 'webdav':
        asset = 'assets/images/webdav.png';
        bg = const Color(0xFFEFF3F8);
        break;
      case 'sftp':
        asset = 'assets/images/sftp.png';
        bg = const Color(0xFFEFF3F8);
        break;
      case 's3':
        asset = 'assets/images/aws-s3-icon.png';
        bg = const Color(0xFFFFF6E8);
        break;
      default:
        asset = 'assets/images/dir.png';
        bg = const Color(0xFFF3F4F6);
        break;
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: selected ? const Color(0x1FFFFFFF) : bg,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Image.asset(asset, width: 18, height: 18),
    );
  }
}

class _DatabaseHealthIndicator extends StatelessWidget {
  const _DatabaseHealthIndicator({
    required this.health,
    this.onTap,
    this.compact = false,
  });

  final DatabaseConnectionHealth health;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (health.isChecking) {
      final spinner = SizedBox(
        width: compact ? 10 : 14,
        height: compact ? 10 : 14,
        child: CircularProgressIndicator(
          strokeWidth: compact ? 1.5 : 2,
          color: compact ? _kIcon : null,
        ),
      );
      if (compact) {
        return Tooltip(
          message: 'Checking vault sync status',
          child: spinner,
        );
      }
      return Tooltip(
        message: 'Checking vault sync status',
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F7FB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorderSoft),
          ),
          alignment: Alignment.center,
          child: spinner,
        ),
      );
    }

    if (compact) {
      return Tooltip(
        message: 'Show sync issue details',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Icon(
              TablerIcons.alert_circle_filled,
              size: 14,
              color: const Color(0xFFDC2626),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: 'Show sync issue details',
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFFFFF1F2),
          foregroundColor: const Color(0xFFDC2626),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFF3C2C2)),
          ),
        ),
        icon: const Icon(TablerIcons.alert_circle_filled, size: 16),
      ),
    );
  }
}

class _UnlockVaultIcon extends StatelessWidget {
  const _UnlockVaultIcon({required this.record});

  final DatabaseRecord? record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    if (r == null) {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF4B6CFF), Color(0xFF7B52FF)],
          ),
        ),
        child: const Icon(TablerIcons.lock, size: 28, color: Colors.white),
      );
    }
    final String asset;
    final Color bg;
    switch (r.storageType) {
      case 'googleDrive':
        asset = 'assets/images/google-drive.png';
        bg = const Color(0xFFF0F4FF);
        break;
      case 'dropbox':
        asset = 'assets/images/dropbox.png';
        bg = const Color(0xFFEFF6FF);
        break;
      case 'oneDrive':
        asset = 'assets/images/onedrive.png';
        bg = const Color(0xFFE8F4FD);
        break;
      case 'webdav':
        asset = 'assets/images/webdav.png';
        bg = const Color(0xFFEFF3F8);
        break;
      case 'sftp':
        asset = 'assets/images/sftp.png';
        bg = const Color(0xFFEFF3F8);
        break;
      case 's3':
        asset = 'assets/images/aws-s3-icon.png';
        bg = const Color(0xFFFFF6E8);
        break;
      default:
        asset = 'assets/images/dir.png';
        bg = const Color(0xFFF3F4F6);
        break;
    }
    return Container(
      width: 60,
      height: 60,
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      alignment: Alignment.center,
      child: Image.asset(asset, width: 32, height: 32),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 10, color: foregroundColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: _uText(10, foregroundColor, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────

class _EmptyDatabaseState extends StatelessWidget {
  const _EmptyDatabaseState();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCanvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final tight =
              constraints.hasBoundedHeight && constraints.maxHeight < 130;
          final padding = EdgeInsets.symmetric(
            vertical: tight ? 8 : 28,
            horizontal: tight ? 14 : 20,
          );
          final box = tight ? 32.0 : 44.0;
          final iconSz = tight ? 18.0 : 20.0;
          return SingleChildScrollView(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: box,
                  height: box,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF3FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    TablerIcons.database_off,
                    size: iconSz,
                    color: _kBlue,
                  ),
                ),
                SizedBox(height: tight ? 6 : 10),
                Text(
                  'No databases yet',
                  style: _uText(
                    tight ? 12 : 13,
                    _kTitle,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: tight ? 2 : 4),
                Text(
                  'Create a new database or open an existing .kdbx file.',
                  style: _uText(tight ? 10 : 11, _kLabel),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCanvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final tight =
              constraints.hasBoundedHeight && constraints.maxHeight < 130;
          final padding = EdgeInsets.symmetric(
            vertical: tight ? 8 : 28,
            horizontal: tight ? 14 : 20,
          );
          return SingleChildScrollView(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  TablerIcons.search_off,
                  size: tight ? 20 : 22,
                  color: _kIcon,
                ),
                SizedBox(height: tight ? 6 : 10),
                Text(
                  'No databases match your search',
                  style: _uText(
                    tight ? 12 : 13,
                    _kTitle,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: tight ? 2 : 4),
                Text(
                  'Try a different name or path keyword.',
                  style: _uText(tight ? 10 : 11, _kLabel),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: _uText(12, _kTitle, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: 'Search databases',
        hintStyle: _uText(12, _kIcon),
        prefixIcon: const Icon(TablerIcons.search, size: 16, color: _kIcon),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: onClear,
                icon: const Icon(TablerIcons.x, size: 14, color: _kIcon),
              ),
        filled: true,
        fillColor: _kCanvas,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorderSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBlue, width: 1.4),
        ),
      ),
    );
  }
}

class _DatabaseListHeader extends StatelessWidget {
  const _DatabaseListHeader({
    required this.sortField,
    required this.sortAscending,
    required this.onSort,
    required this.isRefreshing,
    required this.onRefresh,
  });

  final _DatabaseSortField sortField;
  final bool sortAscending;
  final ValueChanged<_DatabaseSortField> onSort;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8E1EF)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _SortLabel(
              label: 'Name',
              active: sortField == _DatabaseSortField.name,
              ascending: sortAscending,
              onTap: () => onSort(_DatabaseSortField.name),
            ),
          ),
          SizedBox(
            width: 80,
            child: _SortLabel(
              label: 'Recent',
              active: sortField == _DatabaseSortField.recent,
              ascending: false,
              onTap: () => onSort(_DatabaseSortField.recent),
            ),
          ),
          SizedBox(
            width: 118,
            child: _SortLabel(
              label: 'Created at',
              active: sortField == _DatabaseSortField.createdAt,
              ascending: sortAscending,
              onTap: () => onSort(_DatabaseSortField.createdAt),
            ),
          ),
          SizedBox(
            width: 48,
            child: Align(
              alignment: Alignment.centerRight,
              child: _DatabaseHealthRefreshButton(
                isRefreshing: isRefreshing,
                onRefresh: onRefresh,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatabaseHealthRefreshButton extends StatelessWidget {
  const _DatabaseHealthRefreshButton({
    required this.isRefreshing,
    required this.onRefresh,
  });

  final bool isRefreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final tooltip = isRefreshing
        ? 'Checking database connections'
        : 'Refresh database connection status';
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: !isRefreshing,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isRefreshing ? null : () => unawaited(onRefresh()),
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 30,
              height: 30,
              child: Center(
                child: AnimatedRotation(
                  turns: isRefreshing ? 1 : 0,
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeInOut,
                  child: Icon(
                    TablerIcons.refresh,
                    size: 17,
                    color: isRefreshing ? _kBlue : const Color(0xFF7C8CA3),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SortLabel extends StatelessWidget {
  const _SortLabel({
    required this.label,
    required this.active,
    required this.ascending,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _uText(
                11,
                active ? _kBlue : const Color(0xFF667892),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            active
                ? (ascending
                    ? TablerIcons.chevron_up
                    : TablerIcons.chevron_down)
                : TablerIcons.selector,
            size: 13,
            color: active ? _kBlue : const Color(0xFF7C8CA3),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatefulWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.primary,
  });

  final IconData icon;
  final String tooltip;
  // Nullable so callers can disable actions while a vault health check runs.
  // to prevent free-tier users from triggering vault create/open flows.
  final VoidCallback? onTap;
  final bool primary;

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final backgroundColor = disabled
        ? (widget.primary ? const Color(0xFFB7C2CC) : const Color(0xFFF1F4F8))
        : (widget.primary
            ? (_hovered ? const Color(0xFF0D4A59) : _kActionDark)
            : (_hovered ? _kHoverBg : Colors.white));
    final foregroundColor = disabled
        ? const Color(0xFF98A1AE)
        : (widget.primary ? Colors.white : _kTitle);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor:
            disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = !disabled),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.primary
                    ? Colors.transparent
                    : (_hovered ? _kBorderHover : _kBorderSoft),
              ),
              boxShadow: widget.primary && !disabled
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x140A3B48),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Icon(widget.icon, size: 17, color: foregroundColor),
          ),
        ),
      ),
    );
  }
}

// ── Local vault header (right column, top) ──────────────────────────────────

class _UnlockGreetingHeader extends StatelessWidget {
  const _UnlockGreetingHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _kSidebar,
        border: Border(bottom: BorderSide(color: _kBorderSoft)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'LumenPass Vaults',
            style: _uText(13, _kTitle, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Open a local or cloud-backed vault using its own credentials.',
            style: _uText(11, _kLabel, height: 1.35),
          ),
        ],
      ),
    );
  }
}

// ── Guide panel ──────────────────────────────────────────────────────────────

class _VaultGuidePanel extends StatelessWidget {
  const _VaultGuidePanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Getting started',
          style: _uText(15, _kTitle, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Manage your KeePass databases:',
          style: _uText(12, _kLabel),
        ),
        const SizedBox(height: 14),
        _GuideItem(
          icon: TablerIcons.database_plus,
          title: 'Create a new database',
          subtitle: 'Click "Create" to start a fresh vault',
        ),
        const SizedBox(height: 8),
        _GuideItem(
          icon: TablerIcons.folder_open,
          title: 'Open an existing database',
          subtitle: 'Click "Open" to browse local, Google Drive, or Dropbox',
        ),
        const SizedBox(height: 8),
        _GuideItem(
          icon: TablerIcons.lock_open,
          title: 'Unlock a database',
          subtitle: 'Select a database in the list, then click "Unlock"',
        ),
        const SizedBox(height: 14),
        Text(
          'Tips:',
          style: _uText(12, _kLabel, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '• Your files stay on your device — LumenPass never uploads them.',
          style: _uText(11, _kLabel),
        ),
        const SizedBox(height: 2),
        Text(
          '• The default database stays pinned to the top of the list.',
          style: _uText(11, _kLabel),
        ),
        const Spacer(),
        const _GuidePanelFooter(),
      ],
    );
  }
}

class _GuidePanelFooter extends StatelessWidget {
  const _GuidePanelFooter();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '0.1.0';
        final buildNumber = snapshot.data?.buildNumber ?? '0.1.0';
        final year = DateTime.now().year;

        return SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                'Copyright @ $year LumenPass - v$version (build $buildNumber)\nYour Right Privacy Password Manager',
                textAlign: TextAlign.right,
                style: _uText(10, _kLabel),
              ),
              const SizedBox(height: 2),
              SelectableText(
                'staff@lumenpass.app - https://www.lumenpass.app',
                textAlign: TextAlign.right,
                style: _uText(10, _kLabel),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DatabaseItemMenu extends StatelessWidget {
  const _DatabaseItemMenu({
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Database actions',
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? const Color(0x1AFFFFFF) : _kCanvas,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? const Color(0x33FFFFFF) : _kBorderSoft,
                ),
              ),
              child: Icon(
                TablerIcons.dots_vertical,
                size: 16,
                color: selected ? Colors.white : _kIcon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnlockFooterBar extends StatelessWidget {
  const _UnlockFooterBar({
    required this.selectedRecord,
    required this.onExit,
    required this.onUnlock,
  });

  final DatabaseRecord? selectedRecord;
  final VoidCallback onExit;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kBorderSoft)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onExit,
              icon: const Icon(TablerIcons.logout_2, size: 16),
              label: const Text('Exit'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kLabel,
                side: const BorderSide(color: _kBorderSoft),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: _uText(12, _kLabel, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: onUnlock,
              icon: const Icon(TablerIcons.lock_open, size: 16),
              label: const Text('Unlock'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kActionDark,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF9BB0B5),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle:
                    _uText(12, Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideItem extends StatelessWidget {
  const _GuideItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: _kBorderSoft),
          ),
          child: Icon(icon, size: 14, color: _kBlue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: _uText(11, _kLabel)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Unlock credentials dialog (unchanged) ────────────────────────────────────

class _UnlockCredentialsDialog extends ConsumerStatefulWidget {
  const _UnlockCredentialsDialog({
    required this.autoPromptMode,
  });

  final UnlockAutoPromptMode autoPromptMode;

  @override
  ConsumerState<_UnlockCredentialsDialog> createState() =>
      _UnlockCredentialsDialogState();
}

class _UnlockCredentialsDialogState
    extends ConsumerState<_UnlockCredentialsDialog>
    with WidgetsBindingObserver {
  static const MethodChannel _windowChannel = MethodChannel('lumenpass/window');

  late final TextEditingController _passwordController;
  bool _obscurePassword = true;
  bool _showAdvanced = false;
  bool _acceptNoPassword = false;
  String? _toastMessage;
  Timer? _toastTimer;
  bool _navigatedToVault = false;
  bool _biometricEnabled = false;
  bool _pinEnabled = false;
  bool _showPinPad = false;
  List<int> _pinDigits = const [];
  bool _pinError = false;
  bool _autoPromptedLastMethod = false;
  bool _lifecycleResumedOnce = false;
  bool _onFocusPostFrameScheduled = false;

  static const double _kHeightNormal = 520;
  static const double _kHeightAdvanced = 640;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleResumedOnce =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _passwordController = TextEditingController();
    _loadUnlockPreferences();
    if (Platform.isMacOS) {
      _windowChannel.invokeMethod<void>(
        'setSize',
        <String, double>{'width': 820, 'height': _kHeightNormal},
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      _lifecycleResumedOnce = true;
      _maybeAutoPromptFromLastMethod(trigger: 'lifecycle');
    }
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toastMessage = message);
    _toastTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _toastMessage = null);
        ref.read(unlockControllerProvider.notifier).clearError();
      }
    });
  }

  void _dismissToast() {
    _toastTimer?.cancel();
    setState(() => _toastMessage = null);
    ref.read(unlockControllerProvider.notifier).clearError();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _passwordController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isMacOS && !_navigatedToVault) {
      _windowChannel.invokeMethod<void>(
        'setSize',
        <String, double>{'width': 820, 'height': 480},
      );
    }
    super.dispose();
  }

  void _toggleAdvanced(bool v) {
    setState(() => _showAdvanced = v);
    if (Platform.isMacOS) {
      _windowChannel.invokeMethod<void>(
        'setSize',
        <String, double>{
          'width': 820,
          'height': v ? _kHeightAdvanced : _kHeightNormal,
        },
      );
    }
  }

  Future<void> _loadUnlockPreferences() async {
    final vaultPath = ref.read(unlockControllerProvider).databasePath;
    if (vaultPath == null || !mounted) return;
    final svc = ref.read(vaultUnlockServiceProvider);
    final bioOn = await svc.isBiometricEnabled(vaultPath);
    final pinOn = await svc.isPinEnabled(vaultPath);
    final lastMethod = await svc.getLastUnlockMethod(vaultPath);
    if (!mounted) return;
    setState(() {
      _biometricEnabled = bioOn;
      _pinEnabled = pinOn;
    });
    _cachedLastMethod = lastMethod;

    if (widget.autoPromptMode == UnlockAutoPromptMode.immediate) {
      // Prompt right away (startup + explicit unlock click).
      _maybeAutoPromptFromLastMethod(trigger: 'immediate');
    }
  }

  VaultLastUnlockMethod _cachedLastMethod = VaultLastUnlockMethod.none;

  void _maybeAutoPromptFromLastMethod({required String trigger}) {
    if (!mounted) return;
    if (_autoPromptedLastMethod) return;
    if (widget.autoPromptMode == UnlockAutoPromptMode.none) return;
    if (widget.autoPromptMode == UnlockAutoPromptMode.onFocus &&
        !_lifecycleResumedOnce) {
      // Only prompt once the app has resumed (i.e., user focused back).
      return;
    }

    final lastMethod = _cachedLastMethod;
    if (lastMethod == VaultLastUnlockMethod.biometric && _biometricEnabled) {
      _autoPromptedLastMethod = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_tryUnlockWithBiometric());
      });
      return;
    }

    if (lastMethod == VaultLastUnlockMethod.pin && _pinEnabled) {
      _autoPromptedLastMethod = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _showPinPad = true);
      });
    }
  }

  void _hidePinPad() {
    setState(() {
      _showPinPad = false;
      _pinDigits = const [];
      _pinError = false;
    });
  }

  void _addPinDigit(int digit) {
    if (_pinDigits.length >= 6 || _pinError) return;
    final updated = [..._pinDigits, digit];
    setState(() => _pinDigits = updated);
    if (updated.length == 6) {
      _tryUnlockWithPin(updated.map((d) => '$d').join());
    }
  }

  void _removePinDigit() {
    if (_pinDigits.isEmpty) return;
    setState(() => _pinDigits = _pinDigits.sublist(0, _pinDigits.length - 1));
  }

  Future<void> _tryUnlockWithPin(String pin) async {
    await _runUnlockWithProgress(
      task: () async {
        final ok = await ref
            .read(unlockControllerProvider.notifier)
            .unlockWithPin(pin);
        if (!ok) {
          final err = ref.read(unlockControllerProvider).errorMessage;
          throw Exception(err ?? 'Incorrect PIN.');
        }
      },
      onFailure: (_) {
        if (!mounted) return;
        setState(() {
          _pinError = true;
          _pinDigits = const [];
        });
        Future<void>.delayed(const Duration(milliseconds: 700)).then((_) {
          if (mounted) setState(() => _pinError = false);
        });
      },
    );
  }

  Future<void> _tryUnlockWithBiometric() async {
    await _runUnlockWithProgress(
      task: () async {
        final ok = await ref
            .read(unlockControllerProvider.notifier)
            .unlockWithBiometric();
        if (!ok) {
          final err = ref.read(unlockControllerProvider).errorMessage;
          // Biometric may simply be cancelled — surface a message only when
          // the controller reported one, otherwise stay silent.
          throw Exception(err ?? '');
        }
      },
      onFailure: (msg) {
        if (!mounted || msg.isEmpty) return;
        _showToast(msg);
      },
    );
  }

  /// Shared progress-overlay path used by password / PIN / biometric unlock.
  ///
  /// Pushes [UnlockingProgressScreen] over the credentials dialog, runs
  /// [task] there, and on success pops both the progress route and the
  /// dialog (with `true`) so the host screen navigates to the vault.
  Future<void> _runUnlockWithProgress({
    required Future<void> Function() task,
    required void Function(String message) onFailure,
  }) async {
    final dialogContext = context;
    final navigator = Navigator.of(dialogContext);
    final vaultPath = ref.read(unlockControllerProvider).databasePath;
    final vaultName = _vaultDisplayName(vaultPath);

    await navigator.push(
      PageRouteBuilder<void>(
        opaque: true,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) => UnlockingProgressScreen(
          vaultName: vaultName,
          unlockTask: task,
          onSuccess: () {
            if (!navigator.mounted) return;
            navigator.pop();
            if (!mounted) return;
            _navigatedToVault = true;
            Navigator.of(dialogContext).pop(true);
          },
          onFailure: (msg) {
            if (!navigator.mounted) return;
            navigator.pop();
            onFailure(msg);
          },
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // For onFocus mode, make a single post-frame attempt (helps desktop).
    if (widget.autoPromptMode == UnlockAutoPromptMode.onFocus &&
        !_onFocusPostFrameScheduled) {
      _onFocusPostFrameScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeAutoPromptFromLastMethod(trigger: 'postframe');
      });
    }

    ref.listen<UnlockState>(unlockControllerProvider, (previous, next) {
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage) {
        _showToast(next.errorMessage!);
      }
    });

    final state = ref.watch(unlockControllerProvider);
    final controller = ref.read(unlockControllerProvider.notifier);
    final registry = ref.watch(databaseRegistryProvider);
    DatabaseRecord? matchedRecord;
    if (state.databasePath != null) {
      for (final r in registry) {
        if (r.databasePath == state.databasePath) {
          matchedRecord = r;
          break;
        }
      }
    }
    final String vaultName =
        (matchedRecord != null && matchedRecord.nickname.trim().isNotEmpty)
            ? matchedRecord.nickname.trim()
            : _vaultDisplayName(state.databasePath);
    final String vaultSubtitle = matchedRecord != null
        ? _locationLabel(matchedRecord)
        : _vaultDisplayName(state.databasePath);
    final bool hasKeyFile =
        state.keyFilePath != null && state.keyFilePath!.isNotEmpty;

    return Theme(
      data: AppTheme.light(),
      child: Dialog(
        backgroundColor: _kUnlockDialogBackground,
        elevation: 0,
        insetPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: _kUnlockDialogBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        const SizedBox(height: 8),
                        _UnlockVaultIcon(record: matchedRecord),
                        const SizedBox(height: 12),
                        Text(
                          vaultName,
                          style:
                              _uText(24, _kTitle, fontWeight: FontWeight.w800),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          vaultSubtitle,
                          style: _uText(12, _kLabel),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _acceptNoPassword
                                ? _kUnlockAccentSoft
                                : _kUnlockCardBackground,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _acceptNoPassword
                                  ? _kUnlockAccentBorder
                                  : _kUnlockCardBorder,
                            ),
                          ),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      'Accept no password',
                                      style: _uText(
                                        12,
                                        _kTitle,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      'Open vault with key file only',
                                      style: _uText(11, _kLabel),
                                    ),
                                  ],
                                ),
                              ),
                              Transform.scale(
                                scale: 0.75,
                                alignment: Alignment.centerRight,
                                child: Switch.adaptive(
                                  value: _acceptNoPassword,
                                  onChanged: (bool v) {
                                    setState(() {
                                      _acceptNoPassword = v;
                                      if (v) _passwordController.clear();
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            Expanded(
                              child: TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                enabled: !_acceptNoPassword,
                                enableSuggestions: false,
                                autocorrect: false,
                                autofocus: true,
                                textInputAction: TextInputAction.done,
                                onChanged: (_) => controller.clearError(),
                                onSubmitted: (_) => _submit(),
                                style: _uText(13, _kUnlockFieldText),
                                decoration: InputDecoration(
                                  hintText: _acceptNoPassword
                                      ? 'No password required'
                                      : 'Enter Master Password',
                                  hintStyle: _uText(13, _kUnlockHintText),
                                  filled: true,
                                  fillColor: _kUnlockFieldBackground,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 13,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: _kUnlockCardBorder,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: _kUnlockCardBorder,
                                    ),
                                  ),
                                  disabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: _kUnlockDialogBorder,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: _kUnlockFieldFocus,
                                      width: 2,
                                    ),
                                  ),
                                  suffixIcon: _acceptNoPassword
                                      ? null
                                      : IconButton(
                                          onPressed: () => setState(
                                            () => _obscurePassword =
                                                !_obscurePassword,
                                          ),
                                          icon: Icon(
                                            _obscurePassword
                                                ? TablerIcons.eye
                                                : TablerIcons.eye_off,
                                            size: 16,
                                            color: _kUnlockHintText,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            if (_pinEnabled) ...<Widget>[
                              const SizedBox(width: 8),
                              _IconActionButton(
                                icon: TablerIcons.grid_dots,
                                onPressed: state.isLoading
                                    ? null
                                    : () => setState(
                                          () => _showPinPad = true,
                                        ),
                                tooltip: 'PIN entry',
                              ),
                            ],
                            if (_biometricEnabled) ...<Widget>[
                              const SizedBox(width: 6),
                              _IconActionButton(
                                icon: Platform.isWindows
                                    ? TablerIcons.scan_eye
                                    : TablerIcons.fingerprint,
                                onPressed: state.isLoading
                                    ? null
                                    : _tryUnlockWithBiometric,
                                tooltip: Platform.isWindows
                                    ? 'Windows Hello unlock'
                                    : 'Biometric unlock',
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: <Widget>[
                            Text(
                              'Advanced',
                              style: _uText(
                                12,
                                _kLabel,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Transform.scale(
                              scale: 0.75,
                              alignment: Alignment.centerRight,
                              child: Switch.adaptive(
                                value: _showAdvanced,
                                onChanged: _toggleAdvanced,
                              ),
                            ),
                          ],
                        ),
                        if (_showAdvanced) ...<Widget>[
                          const SizedBox(height: 10),
                          _AdvancedFileRow(
                            icon: TablerIcons.key,
                            label: 'Key file',
                            subtitle: hasKeyFile
                                ? _fileName(state.keyFilePath!)
                                : 'Optional — add if your vault requires one',
                            hasValue: hasKeyFile,
                            onChoose: controller.selectKeyFile,
                            onClear:
                                hasKeyFile ? controller.clearKeyFile : null,
                          ),
                          const SizedBox(height: 8),
                          Opacity(
                            opacity: 0.45,
                            child: _AdvancedFileRow(
                              icon: TablerIcons.usb,
                              label: 'Hardware key',
                              subtitle: 'YubiKey and FIDO2 hardware keys',
                              badge: 'Soon',
                              hasValue: false,
                              onChoose: () {},
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: _kUnlockFooterBackground,
                    border:
                        Border(top: BorderSide(color: _kUnlockFooterBorder)),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: state.isLoading
                            ? null
                            : () => Navigator.of(context).pop(false),
                        icon: const Icon(TablerIcons.arrow_left, size: 13),
                        label: const Text('Back'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kUnlockGhostText,
                          backgroundColor: _kUnlockGhostBg,
                          disabledForegroundColor: _kUnlockGhostText.withValues(
                            alpha: 0.5,
                          ),
                          disabledBackgroundColor: _kUnlockGhostBg,
                          side: const BorderSide(color: _kUnlockGhostBorder),
                          minimumSize: const Size(0, 32),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          textStyle: _uText(
                            12,
                            _kUnlockGhostText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: state.isLoading ? null : _submit,
                        icon: state.isLoading
                            ? const SizedBox.square(
                                dimension: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(TablerIcons.lock_open, size: 13),
                        label: const Text('Unlock Vault'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kActionDark,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _kUnlockPrimaryDisabled,
                          elevation: 0,
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: _uText(
                            12,
                            Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ).copyWith(
                          backgroundColor:
                              WidgetStateProperty.resolveWith<Color>(
                            (states) {
                              if (states.contains(WidgetState.disabled)) {
                                return _kUnlockPrimaryDisabled;
                              }
                              if (states.contains(WidgetState.hovered)) {
                                return _kUnlockPrimaryHover;
                              }
                              return _kActionDark;
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_showPinPad)
              Positioned.fill(
                child: _buildPinPad(vaultName),
              ),
            if (state.isLoading)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: const Color(0xCCFFFFFF),
                    child: Center(
                      child: Container(
                        width: 280,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _kBorderSoft),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x180F172A),
                              blurRadius: 24,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: <Color>[
                                    Color(0xFF4B6CFF),
                                    Color(0xFF7B52FF),
                                  ],
                                ),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(14),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.6,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Unlocking your vault…',
                              style: _uText(
                                15,
                                _kTitle,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Decrypting the database and preparing your items.',
                              style: _uText(12, _kLabel),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_toastMessage != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 72,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x28EF4444),
                          blurRadius: 16,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          TablerIcons.alert_circle,
                          color: Colors.white,
                          size: 15,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _toastMessage!,
                            style: _uText(12, Colors.white),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _dismissToast,
                          child: const Icon(
                            TablerIcons.x,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    await _runUnlockWithProgress(
      task: () async {
        final ok =
            await ref.read(unlockControllerProvider.notifier).unlock(password);
        if (!ok) {
          final err = ref.read(unlockControllerProvider).errorMessage;
          throw Exception(err ?? 'Incorrect password.');
        }
      },
      onFailure: (msg) {
        if (!mounted || msg.isEmpty) return;
        _showToast(msg);
      },
    );
  }

  Widget _buildPinPad(String vaultName) {
    return Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  const SizedBox(height: 16),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          Color(0xFF4B6CFF),
                          Color(0xFF7B52FF),
                        ],
                      ),
                    ),
                    child: const Icon(
                      TablerIcons.lock,
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    vaultName,
                    style: _uText(20, _kTitle, fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enter your 6-digit PIN',
                    style: _uText(12, _kLabel),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(6, (i) {
                      final filled = i < _pinDigits.length;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _pinError
                                ? const Color(0xFFEF4444)
                                : filled
                                    ? _kBlue
                                    : Colors.transparent,
                            border: Border.all(
                              color: _pinError
                                  ? const Color(0xFFEF4444)
                                  : filled
                                      ? _kBlue
                                      : _kBorderRow,
                              width: 1.5,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  if (_pinError) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      'Incorrect PIN — try again',
                      style: _uText(11, const Color(0xFFEF4444)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Column(
                      children: <Widget>[
                        for (final row in <List<int>>[
                          <int>[1, 2, 3],
                          <int>[4, 5, 6],
                          <int>[7, 8, 9],
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: row
                                  .map(
                                    (n) => Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                        ),
                                        child: _PinKeyButton(
                                          label: '$n',
                                          onTap: () => _addPinDigit(n),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        Row(
                          children: <Widget>[
                            const Expanded(child: SizedBox.shrink()),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                ),
                                child: _PinKeyButton(
                                  label: '0',
                                  onTap: () => _addPinDigit(0),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                ),
                                child: _PinKeyButton(
                                  icon: TablerIcons.backspace,
                                  onTap: _removePinDigit,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: _kUnlockFooterBackground,
              border: Border(top: BorderSide(color: _kUnlockFooterBorder)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _hidePinPad,
                  icon: const Icon(TablerIcons.arrow_left, size: 13),
                  label: const Text('Use master password'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kUnlockGhostText,
                    backgroundColor: _kUnlockGhostBg,
                    side: const BorderSide(color: _kUnlockGhostBorder),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: _uText(
                      12,
                      _kUnlockGhostText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared helper widgets ────────────────────────────────────────────────────

class _PinKeyButton extends StatefulWidget {
  const _PinKeyButton({this.label, this.icon, required this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  State<_PinKeyButton> createState() => _PinKeyButtonState();
}

class _PinKeyButtonState extends State<_PinKeyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        height: 52,
        decoration: BoxDecoration(
          color: _pressed ? _kHoverBg : _kCanvas,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _pressed ? _kBorderHover : _kBorderRow,
          ),
        ),
        alignment: Alignment.center,
        child: widget.icon != null
            ? Icon(widget.icon, size: 16, color: _kIcon)
            : Text(
                widget.label!,
                style: _uText(18, _kTitle, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  const _IconActionButton({
    required this.icon,
    this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: _kCanvas,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorderRow),
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(
            icon,
            size: 16,
            color: onPressed == null ? const Color(0xFFCDD5E0) : _kIcon,
          ),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            overlayColor: WidgetStateColor.transparent,
          ),
        ),
      ),
    );
  }
}

class _AdvancedFileRow extends StatelessWidget {
  const _AdvancedFileRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.hasValue,
    required this.onChoose,
    this.onClear,
    this.badge,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool hasValue;
  final VoidCallback onChoose;
  final VoidCallback? onClear;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kCanvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorderSoft),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: _kBorderSoft),
            ),
            child: Icon(icon, size: 14, color: _kBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      label,
                      style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
                    ),
                    if (badge != null) ...<Widget>[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _kBorderSoft),
                        ),
                        child: Text(
                          badge!,
                          style: _uText(9, _kIcon, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  subtitle,
                  style: _uText(11, _kLabel),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (hasValue && onClear != null)
            IconButton(
              onPressed: onClear,
              icon: const Icon(TablerIcons.x, size: 14, color: _kIcon),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            )
          else if (badge == null)
            TextButton(
              onPressed: onChoose,
              style: TextButton.styleFrom(
                foregroundColor: _kBlue,
                textStyle: _uText(11, _kBlue, fontWeight: FontWeight.w600),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
              ),
              child: const Text('Choose'),
            ),
        ],
      ),
    );
  }
}

// ── Utility functions ────────────────────────────────────────────────────────

String _vaultDisplayName(String? path) {
  if (path == null || path.isEmpty) return 'Your Vault';
  final String name = _fileName(path);
  final int dot = name.lastIndexOf('.');
  final String base = dot > 0 ? name.substring(0, dot) : name;
  return base.isEmpty ? 'Your Vault' : base;
}

String _fileName(String path) {
  final List<String> segments = path.split(RegExp(r'[\\/]'));
  return segments.isEmpty ? path : segments.last;
}

String _locationLabel(DatabaseRecord record) {
  switch (record.storageType) {
    case 'googleDrive':
      return 'Google Drive';
    case 'dropbox':
      return 'Dropbox';
    case 'oneDrive':
      return 'OneDrive';
    case 'webdav':
      return 'WebDAV';
    case 'sftp':
      return 'SFTP';
    case 's3':
      return 'Amazon S3';
    default:
      return _shortenPath(record.databasePath);
  }
}

String _formatCreatedAt(DateTime value) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months[value.month - 1];
  final day = value.day.toString().padLeft(2, '0');
  return '$month $day, ${value.year}';
}

String _shortenPath(String path) {
  const int maxLen = 52;
  if (path.length <= maxLen) return path;
  final home = Platform.environment['HOME'] ?? '';
  final shortened = home.isNotEmpty ? path.replaceFirst(home, '~') : path;
  if (shortened.length <= maxLen) return shortened;
  final segs = shortened.split(RegExp(r'[/]'));
  if (segs.length > 3) {
    return '${segs.first}/…/${segs[segs.length - 2]}/${segs.last}';
  }
  return '…${shortened.substring(shortened.length - maxLen + 1)}';
}

// ── Vault-health dialog ────────────────────────────────────────────────────

enum _DatabaseHealthDialogAction { close, retry, reconnect, unlinkDatabases }

class _DatabaseHealthIssueDialog extends StatelessWidget {
  const _DatabaseHealthIssueDialog({
    required this.record,
    required this.health,
  });

  final DatabaseRecord record;
  final DatabaseConnectionHealth health;

  bool get _canReconnect => isCloudBackedDatabaseRecord(record);

  @override
  Widget build(BuildContext context) {
    final providerLabel =
        health.providerLabel ?? providerLabelForStorageType(record.storageType);

    return Theme(
      data: AppTheme.light(),
      child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: <Widget>[
            const Icon(
              TablerIcons.alert_triangle,
              color: Color(0xFFDC2626),
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                health.title ?? 'This vault needs attention',
                style: _uText(15, _kTitle, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '"${record.nickname}" is linked to $providerLabel.',
                style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                health.details ?? 'The vault cannot confirm sync health.',
                style: _uText(12, _kLabel, height: 1.4),
              ),
              if (health.recommendedActions.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                Text(
                  'Recommended actions',
                  style: _uText(12, _kTitle, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                for (final action in health.recommendedActions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: _kActionDark,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            action,
                            style: _uText(12, _kLabel, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        actionsPadding:
            const EdgeInsets.only(left: 16, right: 16, bottom: 12, top: 4),
        actions: <Widget>[
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_DatabaseHealthDialogAction.close),
            child: Text('Close', style: _uText(12, _kLabel)),
          ),
          if (_canReconnect)
            TextButton(
              onPressed: () => Navigator.of(context)
                  .pop(_DatabaseHealthDialogAction.unlinkDatabases),
              child: Text(
                'Unlink Databases',
                style: _uText(
                  12,
                  const Color(0xFFEF4444),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_DatabaseHealthDialogAction.retry),
            child: Text(
              'Check again',
              style: _uText(12, _kActionDark, fontWeight: FontWeight.w600),
            ),
          ),
          if (_canReconnect)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _kActionDark,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.of(context)
                  .pop(_DatabaseHealthDialogAction.reconnect),
              child: Text(
                'Reconnect $providerLabel',
                style: _uText(12, Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}
