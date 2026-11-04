import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/database_record.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/bookmark_service.dart';

import '../../../core/services/vault_unlock_service.dart';
import '../../../presentation/theme/app_theme.dart';
import '../../../presentation/theme/drive_clue_tokens.dart';
import '../../../presentation/widgets/drive_clue/drive_clue_widgets.dart';
import '../../../presentation/widgets/lumenpass_wordmark.dart';

import '../../cloud/application/cloud_service_provider.dart';
import '../../cloud/application/cloud_disconnect.dart';
import '../../cloud/presentation/cloud_services_screen.dart';
import '../../vault/presentation/vault_screen.dart';
import '../application/database_connection_health.dart';
import '../application/database_registry.dart';
import '../application/unlock_controller.dart';
import '../application/vault_group_order.dart';
import 'create_database_modal.dart';
import 'duplicate_database_modal.dart';
import 'open_existing_database_modal.dart';
import 'provider_config_route.dart';
import 'restore_backups_modal.dart';
import 'splash_screen.dart';
import 'storage_source_list.dart';
import 'unlocking_progress_screen.dart';

import '../../../presentation/widgets/drive_clue/dc_confirm_dialog.dart';

// ── Shared palette (DriveClue tokens) ──────────────────────────────────────
const Color _kActionDark = DcColors.selection;

// ── Vault list body palette (light, sidebar-toned) ────────────────────────
const Color _kPickerInk = DcColors.sidebarText;
const Color _kPickerPaper = DcColors.lightSurface;
const Color _kPickerPaperBright = DcColors.lightSurface;
const Color _kPickerInset = DcColors.lightInset;
const Color _kPickerLine = DcColors.sidebarLine;
const Color _kPickerLineStrong = DcColors.lightLineStrong;
const Color _kPickerMuted = DcColors.sidebarMuted;
const Color _kPickerFaint = DcColors.faint;
const Color _kPickerOrange = DcColors.selection;
const Color _kPickerOrangeDark = DcColors.selectionHover;

/// Distance of the floating database search field from the bottom edge.
const double _kDatabaseSearchBottomOffset = 74;

// ── Vault grid metrics ────────────────────────────────────────────────────
/// Outer padding of the grouped vault grid.
const double _kVaultGridGutter = 16;

/// Gap between cards, and between grid rows.
const double _kVaultGridGap = 12;

/// Cards never get narrower than this; the column count is derived from it.
const double _kVaultCardMinWidth = 236;

/// Preferred order of storage groups in the vault grid.
const List<String> _storageGroupOrder = <String>[
  'local',
  'googleDrive',
  'dropbox',
  'oneDrive',
  'webdav',
  'sftp',
  's3',
];

// ── Credentials dialog palette (light, sidebar-toned) ─────────────────────
const Color _kCredInk = DcColors.sidebarText;
const Color _kCredMuted = DcColors.sidebarMuted;
const Color _kCredCanvas = DcColors.sidebar;
const Color _kCredSurface = DcColors.lightSurface;
const Color _kCredInset = DcColors.lightInset;
const Color _kCredLine = DcColors.sidebarLine;
const Color _kCredLineStrong = DcColors.lightLineStrong;
const Color _kCredAccentTint = DcColors.lightSelectionFill;
const Color _kCredMint = DcColors.tealOnLight;
const Color _kCredMintSoft = Color(0x1F1F8A7D);
const Color _kCredShadow = DcColors.lightCardShadow;

const Color _kUnlockDialogBackground = _kCredCanvas;
const Color _kUnlockCardBackground = _kCredSurface;
const Color _kUnlockFieldText = _kCredInk;
const Color _kUnlockHintText = _kCredMuted;
const Color _kUnlockAccentSoft = _kCredMintSoft;
const Color _kUnlockAccentBorder = _kCredMint;
const Color _kUnlockFooterBackground = _kCredCanvas;
const Color _kUnlockFooterBorder = _kCredLine;
const Color _kUnlockGhostBg = _kCredSurface;
const Color _kUnlockGhostBorder = _kCredLineStrong;
const Color _kUnlockGhostText = _kCredInk;
const Color _kUnlockPrimaryHover = _kPickerOrangeDark;
const Color _kUnlockPrimaryDisabled = Color(0x733882C2);

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
    fontFamily: 'Ubuntu Sans',
    letterSpacing: letterSpacing,
    height: height,
  );
}

TextStyle _pickerText(
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
    fontFamily: 'Ubuntu Sans',
    letterSpacing: letterSpacing,
    height: height,
  );
}

TextStyle _pickerDisplayText(
  double size,
  Color color, {
  double? height,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: FontWeight.w700,
    fontFamily: 'Ubuntu Sans',
    letterSpacing: -0.45,
    height: height,
  );
}

InputDecoration _unlockFieldDecoration({
  required String hint,
  required IconData prefixIcon,
  Widget? suffix,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: _pickerText(13, _kCredMuted),
    filled: true,
    fillColor: _kCredSurface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: _kCredLineStrong),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: _kCredLineStrong),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: _kCredLine),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: _kPickerOrange, width: 1.5),
    ),
    prefixIcon: Icon(prefixIcon, size: 17, color: _kCredMuted),
    prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    suffixIcon: suffix,
  );
}

enum _DatabaseSortField { recent, name, createdAt }

/// One storage bucket in the vault grid (Local, Google Drive, Dropbox...).
class _DatabaseStorageGroup {
  const _DatabaseStorageGroup({
    required this.storageType,
    required this.title,
    required this.assetPath,
    required this.accent,
    required this.records,
  });

  final String storageType;
  final String title;
  final String assetPath;
  final Color accent;
  final List<DatabaseRecord> records;
}

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
  bool _showSplash = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Map<String, DatabaseConnectionHealth> _databaseHealth =
      <String, DatabaseConnectionHealth>{};
  bool _showDatabaseSearch = false;
  String? _selectedDatabaseId;
  _DatabaseSortField _sortField = _DatabaseSortField.recent;
  bool _sortAscending = true;
  bool _isRefreshingDatabaseHealth = false;
  String _databaseHealthSignature = '';
  int _databaseHealthGeneration = 0;

  /// On-disk size in bytes per `DatabaseRecord.id`, resolved lazily.
  final Map<String, int?> _vaultSizes = <String, int?>{};
  String _vaultSizeSignature = '';

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
      _windowChannel.invokeMethod<void>('hideNativeTitleBar');
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
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final databases = ref.watch(databaseRegistryProvider);
    final groupOrder = ref.watch(vaultGroupOrderProvider);
    _scheduleDatabaseHealthChecks(databases);
    _scheduleVaultSizes(databases);
    final visibleDatabases = _visibleDatabases(databases);
    final visibleGroups = _groupDatabases(
      visibleDatabases,
      preferredOrder: groupOrder,
    );
    final selectedRecord = _selectedRecordFrom(visibleDatabases);

    final unlockContent = Theme(
      data: AppTheme.driveClue(),
      child: Scaffold(
        backgroundColor: _kPickerPaper,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Left: database list
            Expanded(
              flex: 3,
              child: ColoredBox(
                color: _kPickerPaper,
                child: Stack(
                  children: <Widget>[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildHeader(),
                        if (databases.isNotEmpty)
                          _buildVaultToolbar(
                            databaseCount: databases.length,
                            groupCount: visibleGroups.length,
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
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    final columns =
                                        _vaultGridColumnCount(constraints);
                                    return ReorderableListView.builder(
                                      padding: EdgeInsets.only(
                                        bottom: _showDatabaseSearch ? 82 : 16,
                                      ),
                                      // Dragging is driven by the grip handle on
                                      // each group header, not a whole-row grab.
                                      buildDefaultDragHandles: false,
                                      proxyDecorator: _groupDragProxy,
                                      itemCount: visibleGroups.length,
                                      onReorder: (int oldIndex, int newIndex) {
                                        // ReorderableListView reports the index
                                        // BEFORE the dragged row is removed.
                                        final target =
                                            newIndex > oldIndex
                                                ? newIndex - 1
                                                : newIndex;
                                        _moveDatabaseGroup(
                                          visibleGroups: visibleGroups,
                                          fromIndex: oldIndex,
                                          toIndex: target,
                                        );
                                      },
                                      itemBuilder: (_, index) {
                                        final group = visibleGroups[index];
                                        return KeyedSubtree(
                                          key: ValueKey<String>(
                                            'vault-group-${group.storageType}',
                                          ),
                                          child: _DatabaseGroupSection(
                                            group: group,
                                            columns: columns,
                                            isFirst: index == 0,
                                            selectedRecordId: selectedRecord?.id,
                                            healthFor:
                                                (record) => _databaseHealth[
                                                    record.id],
                                            isInteractionBlocked:
                                                (record, health) =>
                                                    _isDatabaseInteractionBlocked(
                                              record,
                                              health: health,
                                            ),
                                            onSelect: _selectDatabase,
                                            onOpen: (record) =>
                                                _handleOpenDatabase(
                                              record,
                                              autoPromptMode:
                                                  UnlockAutoPromptMode.immediate,
                                            ),
                                            onShowHealthDetails:
                                                _showDatabaseHealthDetails,
                                            onSetDefault:
                                                _handleSetDefaultDatabase,
                                            onSaveAs: _handleSaveDatabaseAs,
                                            onDuplicate:
                                                _handleDuplicateDatabase,
                                            onRestore: _handleRestoreDatabase,
                                            onRemove: _handleRemoveDatabase,
                                            sizeFor: (record) =>
                                                _vaultSizes[record.id],
                                            groupIndex: index,
                                            groupCount: visibleGroups.length,
                                            onReorderGroup: (newIndex) =>
                                                _moveDatabaseGroup(
                                              visibleGroups: visibleGroups,
                                              fromIndex: index,
                                              toIndex: newIndex,
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                        ),
                        _VaultStatisticsFooter(databases: databases),
                      ],
                    ),
                    if (_showDatabaseSearch)
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: _kDatabaseSearchBottomOffset,
                        child: _SearchField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: (_) => setState(() {}),
                          onClose: _closeDatabaseSearch,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Vertical divider
            Container(width: 1, color: DcColors.shellDivider),
            // Right: greeting header (top) + guide panel (below)
            Expanded(
              flex: 2,
              child: Container(
                color: DcColors.sidebar,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const <Widget>[
                    _UnlockGreetingHeader(),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(18, 15, 18, 14),
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
    return Container(
      height: Platform.isMacOS ? 42 : DcMetrics.headerHeight,
      padding: EdgeInsets.fromLTRB(
        Platform.isMacOS ? 94 : 16,
        0,
        12,
        0,
      ),
      decoration: const BoxDecoration(
        color: DcColors.background,
        border: Border(bottom: BorderSide(color: DcColors.line)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Your vaults',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: _pickerText(
                17,
                DcColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _HeaderIconButton(
            icon: TablerIcons.search,
            tooltip: 'Search databases',
            onTap: _openDatabaseSearch,
            primary: false,
          ),
          const SizedBox(width: 6),
          _HeaderIconButton(
            icon: TablerIcons.plus,
            tooltip: 'Create database',
            onTap: _openCreateDatabase,
            primary: true,
          ),
          const SizedBox(width: 6),
          _HeaderIconButton(
            icon: TablerIcons.folder_open,
            tooltip: 'Open existing database',
            onTap: _openExistingDatabase,
            primary: false,
          ),
          const SizedBox(width: 6),
          _HeaderIconButton(
            icon: TablerIcons.cloud,
            tooltip: 'Cloud Services',
            onTap: _openCloudServices,
            primary: false,
          ),
        ],
      ),
    );
  }

  /// Compact toolbar under the header: sort controls, group summary and the
  /// connection-status refresh. Replaces the old table header now that vaults
  /// render as a grouped card grid.
  Widget _buildVaultToolbar({
    required int databaseCount,
    required int groupCount,
  }) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: _kVaultGridGutter),
      decoration: const BoxDecoration(
        color: _kPickerInset,
        border: Border(bottom: BorderSide(color: _kPickerLine)),
      ),
      child: Row(
        children: <Widget>[
          // Expanded (not Flexible+Spacer): guarantees the summary yields all
          // remaining width before the sort controls, so the toolbar can never
          // overflow at the 960px minimum window size.
          Expanded(
            child: Text(
              groupCount > 1
                  ? '${databaseCount == 1 ? '1 vault' : '$databaseCount vaults'}  •  $groupCount sources'
                  : (databaseCount == 1 ? '1 vault' : '$databaseCount vaults'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _pickerText(
                11,
                _kPickerMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _SortLabel(
            label: 'Name',
            active: _sortField == _DatabaseSortField.name,
            ascending: _sortAscending,
            onTap: () => _toggleSort(_DatabaseSortField.name),
          ),
          const SizedBox(width: 12),
          _SortLabel(
            label: 'Recent',
            active: _sortField == _DatabaseSortField.recent,
            ascending: false,
            onTap: () => _toggleSort(_DatabaseSortField.recent),
          ),
          const SizedBox(width: 12),
          _SortLabel(
            label: 'Created',
            active: _sortField == _DatabaseSortField.createdAt,
            ascending: _sortAscending,
            onTap: () => _toggleSort(_DatabaseSortField.createdAt),
          ),
          const SizedBox(width: 10),
          _DatabaseHealthRefreshButton(
            isRefreshing: _isRefreshingDatabaseHealth,
            onRefresh: _refreshAllDatabaseHealth,
          ),
        ],
      ),
    );
  }

  void _openDatabaseSearch() {
    if (_showDatabaseSearch) {
      _searchFocusNode.requestFocus();
      return;
    }
    setState(() => _showDatabaseSearch = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeDatabaseSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() => _showDatabaseSearch = false);
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

  /// Resolves on-disk `.kdbx` sizes for the local vaults in [databases].
  ///
  /// Local paths are read directly; cloud vaults report the size of their
  /// downloaded cache copy. Sizing is best-effort: a failure leaves the entry
  /// null and the card simply omits the size.
  void _scheduleVaultSizes(List<DatabaseRecord> databases) {
    final signature = databases.map((record) {
      return '${record.id}::${record.databasePath}';
    }).join('|');
    if (_vaultSizeSignature == signature) {
      return;
    }
    _vaultSizeSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refreshVaultSizes(databases));
    });
  }

  Future<void> _refreshVaultSizes(List<DatabaseRecord> databases) async {
    final next = <String, int?>{};
    for (final record in databases) {
      try {
        final file = File(record.databasePath);
        next[record.id] =
            await file.exists() ? await file.length() : null;
      } catch (_) {
        next[record.id] = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _vaultSizes
        ..clear()
        ..addAll(next);
    });
  }

  bool _isDatabaseInteractionBlocked(
    DatabaseRecord record, {
    DatabaseConnectionHealth? health,
  }) {    if (!isCloudBackedDatabaseRecord(record)) return false;
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

    filtered.sort(_compareDatabases);
    return filtered;
  }

  /// Buckets [databases] by storage provider, preserving the sorted order
  /// from `_visibleDatabases` both across groups and inside each group.
  ///
  /// Group order follows the user's persisted drag order in
  /// [vaultGroupOrderProvider]; providers they have not reordered yet keep the
  /// default [_storageGroupOrder] position.
  List<_DatabaseStorageGroup> _groupDatabases(
    List<DatabaseRecord> databases, {
    required List<String> preferredOrder,
  }) {
    final byStorage = <String, List<DatabaseRecord>>{};
    for (final record in databases) {
      byStorage
          .putIfAbsent(record.storageType, () => <DatabaseRecord>[])
          .add(record);
    }

    // Persisted entries win, then any provider not yet in that list.
    final order = <String>[
      ...preferredOrder.where(byStorage.containsKey),
      ..._storageGroupOrder.where(
        (type) => !preferredOrder.contains(type) && byStorage.containsKey(type),
      ),
      ...byStorage.keys.where(
        (type) =>
            !preferredOrder.contains(type) &&
            !_storageGroupOrder.contains(type),
      ),
    ];

    return <_DatabaseStorageGroup>[
      for (final storageType in order)
        if (byStorage[storageType] case final List<DatabaseRecord> records)
          _DatabaseStorageGroup(
            storageType: storageType,
            title: _storageGroupTitle(storageType),
            assetPath: _storageGroupAsset(storageType),
            accent: _storageGroupAccent(storageType),
            records: records,
          ),
    ];
  }

  /// Lifts the dragged group off the paper while it is being reordered.
  Widget _groupDragProxy(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? built) {
        final double t = Curves.easeOut.transform(animation.value);
        return Material(
          color: Colors.transparent,
          child: Transform.scale(
            scale: 1 + 0.012 * t,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _kPickerPaperBright,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kPickerLineStrong),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.14 * t),
                    blurRadius: 18 * t,
                    offset: Offset(0, 6 * t),
                  ),
                ],
              ),
              child: built,
            ),
          ),
        );
      },
      child: child,
    );
  }

  /// Moves a whole provider group from [fromIndex] to [toIndex] and persists
  /// the new display order.
  void _moveDatabaseGroup({
    required List<_DatabaseStorageGroup> visibleGroups,
    required int fromIndex,
    required int toIndex,
  }) {
    if (fromIndex < 0 || fromIndex >= visibleGroups.length) return;
    final clamped = toIndex.clamp(0, visibleGroups.length - 1);
    if (fromIndex == clamped) return;

    final order = <String>[for (final group in visibleGroups) group.storageType];
    final moved = order.removeAt(fromIndex);
    order.insert(clamped, moved);

    unawaited(
      ref.read(vaultGroupOrderProvider.notifier).applyVisibleOrder(
            order,
            // Seed from the DEFAULT provider order so that providers filtered
            // out by a search keep a stable slot instead of losing their place.
            knownOrder: _storageGroupOrder,
          ),
    );
  }

  /// Column count for the vault card grid at a given content width.
  int _vaultGridColumnCount(BoxConstraints constraints) {    final double available = constraints.maxWidth - _kVaultGridGutter * 2;
    final int fit =
        (available / (_kVaultCardMinWidth + _kVaultGridGap)).floor();
    return fit.clamp(1, 6);
  }

  int _compareDatabases(DatabaseRecord a, DatabaseRecord b) {
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
          final account = await pushWebDavConfigPage(
            context,
            initialConfig: BackupService.instance.currentWebDavConfig,
          );
          if (!mounted) return false;
          return account != null && BackupService.instance.isWebDavConnected;
        case 'sftp':
          final account = await pushSftpConfigPage(
            context,
            initialConfig: BackupService.instance.currentSftpConfig,
          );
          if (!mounted) return false;
          return account != null && BackupService.instance.isSftpConnected;
        case 's3':
          final account = await pushS3ConfigPage(context);
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
    if (!mounted) return;

    String? createdPath;

    // Full-page route inside the fixed shell — the window never resizes.
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CreateDatabaseModal(
          onCreated: (String dbPath, String nickname) async {
            // addDatabase is already called inside the page; just capture path.
            createdPath = dbPath;
          },
        ),
      ),
    );

    if (createdPath != null && mounted) {
      final createdRecord = _recordForPath(createdPath!);
      if (createdRecord != null) {
        setState(() => _selectedDatabaseId = createdRecord.id);
      }
    }
  }

  Future<void> _openExistingDatabase() async {
    if (!mounted) return;

    String? openedPath;

    // Full-page route inside the fixed shell — the window never resizes.
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OpenExistingDatabaseModal(
          onOpened: (String dbPath) async {
            openedPath = dbPath;
          },
        ),
      ),
    );

    if (openedPath != null && mounted) {
      final addedRecord = _recordForPath(openedPath!);
      if (addedRecord != null) {
        setState(() => _selectedDatabaseId = addedRecord.id);
      }
    }
  }

  Future<void> _openCloudServices() async {
    if (!mounted) return;

    await Navigator.of(context).pushNamed(CloudServicesScreen.routeName);

    if (!mounted) return;
    _databaseHealthSignature = '';
    await _refreshDatabaseHealth(ref.read(databaseRegistryProvider));
  }

  void _showErrorSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: _uText(12, Colors.white)),
        backgroundColor: DcColors.red,
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
    final confirmed = await showDcConfirmDialog(
      context,
      barTitle: 'Remove vault',
      heading: 'Remove "${record.nickname}"?',
      message: 'This removes the database from LumenPass. '
          'The file on disk is not deleted.',
      confirmLabel: 'Remove',
      icon: TablerIcons.trash,
      isDestructive: true,
    );

    if (confirmed) {
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

      String? duplicatePath;

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
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
        ),
      );

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
}

// ── Vault grid (grouped by storage provider) ────────────────────────────────

/// A provider section of the vault grid: an identity header plus the
/// responsive card grid for that storage type.
class _DatabaseGroupSection extends StatelessWidget {
  const _DatabaseGroupSection({
    required this.group,
    required this.columns,
    required this.isFirst,
    required this.selectedRecordId,
    required this.healthFor,
    required this.isInteractionBlocked,
    required this.onSelect,
    required this.onOpen,
    required this.onShowHealthDetails,
    required this.onSetDefault,
    required this.onSaveAs,
    required this.onDuplicate,
    required this.onRestore,
    required this.onRemove,
    required this.sizeFor,
    required this.groupIndex,
    required this.groupCount,
    required this.onReorderGroup,
  });

  final _DatabaseStorageGroup group;
  final int columns;
  final bool isFirst;
  final String? selectedRecordId;
  final DatabaseConnectionHealth? Function(DatabaseRecord record) healthFor;
  final bool Function(DatabaseRecord record, DatabaseConnectionHealth? health)
      isInteractionBlocked;
  final ValueChanged<DatabaseRecord> onSelect;
  final ValueChanged<DatabaseRecord> onOpen;
  final ValueChanged<DatabaseRecord> onShowHealthDetails;
  final ValueChanged<DatabaseRecord> onSetDefault;
  final ValueChanged<DatabaseRecord> onSaveAs;
  final ValueChanged<DatabaseRecord> onDuplicate;
  final ValueChanged<DatabaseRecord> onRestore;
  final ValueChanged<DatabaseRecord> onRemove;

  /// On-disk size in bytes for a vault, or null when unknown.
  final int? Function(DatabaseRecord record) sizeFor;

  /// Position among the rendered groups, and how many there are in total.
  /// Drives the move controls on the group header.
  final int groupIndex;
  final int groupCount;

  /// Moves this group to [newIndex] in the display order.
  final ValueChanged<int> onReorderGroup;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _kVaultGridGutter,
        isFirst ? 14 : 20,
        _kVaultGridGutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _DatabaseGroupHeader(
            group: group,
            groupIndex: groupIndex,
            groupCount: groupCount,
            onReorder: onReorderGroup,
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // Distribute leftover pixels so the last card is not short.
              final double cardWidth =
                  (constraints.maxWidth - _kVaultGridGap * (columns - 1)) /
                      columns;
              return Wrap(
                spacing: _kVaultGridGap,
                runSpacing: _kVaultGridGap,
                children: <Widget>[
                  for (final record in group.records)
                    SizedBox(
                      width: cardWidth,
                      child: _VaultCard(
                        record: record,
                        accent: group.accent,
                        selected: selectedRecordId == record.id,
                        health: healthFor(record),
                        fileSize: sizeFor(record),
                        isInteractionBlocked:
                            isInteractionBlocked(record, healthFor(record)),
                        onTap: () => onSelect(record),
                        onDoubleTap: () => onOpen(record),
                        onShowHealthDetails: () => onShowHealthDetails(record),
                        onSetDefault: () => onSetDefault(record),
                        onSaveAs: () => onSaveAs(record),
                        onDuplicate: () => onDuplicate(record),
                        onRestore: () => onRestore(record),
                        onRemove: () => onRemove(record),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Sticky-feeling identity header that introduces a provider's card grid.
///
/// The trailing "Vaults" label is replaced by a **Move** control that lets the
/// user reorder the whole group on the grid.
class _DatabaseGroupHeader extends StatelessWidget {
  const _DatabaseGroupHeader({
    required this.group,
    required this.groupIndex,
    required this.groupCount,
    required this.onReorder,
  });

  final _DatabaseStorageGroup group;
  final int groupIndex;
  final int groupCount;
  final ValueChanged<int> onReorder;

  Future<void> _showMoveMenu(BuildContext anchorContext) async {
    final overlayContext = Overlay.maybeOf(anchorContext)?.context;
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

    final selection = await showMenu<_GroupMoveAction>(
      context: anchorContext,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlayBox.size,
      ),
      color: _kPickerPaperBright,
      surfaceTintColor: _kPickerPaperBright,
      shadowColor: const Color(0x30000000),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _kPickerLineStrong, width: 1.3),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 2),
      constraints: const BoxConstraints(minWidth: 178, maxWidth: 230),
      items: <PopupMenuEntry<_GroupMoveAction>>[
        _moveItem(
          _GroupMoveAction.top,
          TablerIcons.arrow_bar_up,
          'Move to top',
          enabled: groupIndex > 0,
        ),
        _moveItem(
          _GroupMoveAction.up,
          TablerIcons.arrow_up,
          'Move up',
          enabled: groupIndex > 0,
        ),
        _moveItem(
          _GroupMoveAction.down,
          TablerIcons.arrow_down,
          'Move down',
          enabled: groupIndex < groupCount - 1,
        ),
        _moveItem(
          _GroupMoveAction.bottom,
          TablerIcons.arrow_bar_down,
          'Move to bottom',
          enabled: groupIndex < groupCount - 1,
        ),
      ],
    );

    if (selection == null) return;
    switch (selection) {
      case _GroupMoveAction.top:
        onReorder(0);
      case _GroupMoveAction.up:
        onReorder(groupIndex - 1);
      case _GroupMoveAction.down:
        onReorder(groupIndex + 1);
      case _GroupMoveAction.bottom:
        onReorder(groupCount - 1);
    }
  }

  PopupMenuItem<_GroupMoveAction> _moveItem(
    _GroupMoveAction action,
    IconData icon,
    String label, {
    required bool enabled,
  }) {
    return PopupMenuItem<_GroupMoveAction>(
      value: enabled ? action : null,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: <Widget>[
          Icon(
            icon,
            size: 14,
            color: enabled ? _kPickerMuted : _kPickerFaint,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: _uText(
              11,
              enabled ? _kPickerInk : _kPickerFaint,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: group.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
            border: Border.all(color: group.accent.withValues(alpha: 0.35)),
          ),
          alignment: Alignment.center,
          child: Image.asset(group.assetPath, width: 15, height: 15),
        ),
        const SizedBox(width: 9),
        Text(
          group.title.toUpperCase(),
          style: _pickerText(
            DcMetrics.sectionLabelSize,
            _kPickerInk,
            fontWeight: FontWeight.w700,
            letterSpacing: DcMetrics.sectionLabelTracking,
          ),
        ),
        const SizedBox(width: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _kPickerInset,
            borderRadius: BorderRadius.circular(DcMetrics.badgeRadius),
            border: Border.all(color: _kPickerLine),
          ),
          child: Text(
            '${group.records.length}',
            style: _pickerText(
              10,
              _kPickerMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(height: 1, color: _kPickerLine),
        ),
        const SizedBox(width: 10),
        // Only meaningful when there is more than one group to reorder.
        if (groupCount > 1)
          Builder(
            builder: (anchorContext) => _GroupMoveButton(
              accent: group.accent,
              groupIndex: groupIndex,
              onMenuTap: () => _showMoveMenu(anchorContext),
            ),
          ),
      ],
    );
  }
}

/// The trailing "Move" affordance on a group header.
///
/// The grip is a dedicated drag handle: dragging it reorders the group, while
/// clicking it opens an explicit move menu for users who prefer not to drag.
class _GroupMoveButton extends StatefulWidget {
  const _GroupMoveButton({
    required this.accent,
    required this.groupIndex,
    required this.onMenuTap,
  });

  final Color accent;
  final int groupIndex;
  final VoidCallback onMenuTap;

  @override
  State<_GroupMoveButton> createState() => _GroupMoveButtonState();
}

class _GroupMoveButtonState extends State<_GroupMoveButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: _hovered
              ? widget.accent.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
          border: Border.all(
            color: _hovered ? widget.accent : _kPickerLine,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Drag handle only.
            Tooltip(
              message: 'Drag to reorder this group',
              child: ReorderableDragStartListener(
                index: widget.groupIndex,
                child: Icon(
                  TablerIcons.grip_vertical,
                  size: 14,
                  color: _hovered ? widget.accent : _kPickerMuted,
                ),
              ),
            ),
            const SizedBox(width: 3),
            // Click target for the explicit move menu.
            Tooltip(
              message: 'Move this group',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onMenuTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    'Move',
                    style: _pickerText(
                      10,
                      _hovered ? widget.accent : _kPickerMuted,
                      fontWeight: FontWeight.w600,
                    ),
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

enum _GroupMoveAction { top, up, down, bottom }

class _VaultCard extends StatefulWidget {
  const _VaultCard({
    required this.record,
    required this.accent,
    required this.selected,
    required this.isInteractionBlocked,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSetDefault,
    required this.onSaveAs,
    required this.onDuplicate,
    required this.onRestore,
    required this.onRemove,
    this.health,
    this.onShowHealthDetails,
    this.fileSize,
  });

  final DatabaseRecord record;

  /// Brand color of the storage group this card belongs to.
  final Color accent;
  final bool selected;
  final bool isInteractionBlocked;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onSetDefault;
  final VoidCallback onSaveAs;
  final VoidCallback onDuplicate;
  final VoidCallback onRestore;
  final VoidCallback onRemove;
  final DatabaseConnectionHealth? health;
  final VoidCallback? onShowHealthDetails;

  /// On-disk size of the vault in bytes; null while unknown.
  final int? fileSize;

  @override
  State<_VaultCard> createState() => _VaultCardState();
}

class _VaultCardState extends State<_VaultCard> {
  bool _hovered = false;

  static const Color _menuSurface = _kPickerPaperBright;
  static const Color _menuText = _kPickerInk;
  static const Color _menuBorder = _kPickerLineStrong;

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
                  bottom: BorderSide(color: _kPickerLine),
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
                isDestructive ? DcColors.redOnLight : _menuText,
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
          iconColor: DcColors.amberOnLight,
          isDestructive: false,
        ),
      (
        value: 'save_as',
        icon: TablerIcons.device_floppy,
        label: 'Save Database As',
        iconColor: DcColors.tealOnLight,
        isDestructive: false,
      ),
      (
        value: 'duplicate',
        icon: TablerIcons.copy,
        label: 'Duplicate',
        iconColor: DcColors.indigo,
        isDestructive: false,
      ),
      if (kBackupRestoreFeatureEnabled)
        (
          value: 'restore',
          icon: TablerIcons.history,
          label: 'Restore',
          iconColor: DcColors.tealOnLight,
          isDestructive: false,
        ),
      (
        value: 'remove',
        icon: TablerIcons.trash,
        label: 'Remove',
        iconColor: DcColors.redOnLight,
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
      shadowColor: const Color(0x30000000),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _menuBorder, width: 1.3),
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
    widget.onTap();
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
    widget.onTap();
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
    final disabled =
        widget.isInteractionBlocked || isChecking || hasHealthError;
    final selected = widget.selected;
    final titleColor = hasHealthError
        ? DcColors.redOnLight
        : isChecking
            ? _kPickerFaint
            : _kPickerInk;
    final subtitleColor = hasHealthError
        ? DcColors.redOnLight
        : isChecking
            ? _kPickerFaint
            : _kPickerMuted;
    final detailText = hasHealthError
        ? health?.title ?? 'This vault needs attention.'
        : isChecking
            ? 'Checking connection status…'
            : _shortenPath(widget.record.databasePath);
    final indicatorHealth = isPendingCheck
        ? DatabaseConnectionHealth.checking(
            providerLabel:
                providerLabelForStorageType(widget.record.storageType),
            checkedAt: DateTime.now(),
          )
        : health;
    final accent = widget.accent;

    final borderColor = selected
        ? accent
        : _hovered
            ? accent.withValues(alpha: 0.55)
            : _kPickerLineStrong;

    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: DcColors.selectionSoft,
        highlightColor: DcColors.selectionSoft,
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
              onTap: disabled ? null : widget.onTap,
              onDoubleTap: disabled ? null : widget.onDoubleTap,
              onSecondaryTapDown: isChecking
                  ? null
                  : (details) {
                      _showMenuAtPoint(menuContext, details.globalPosition);
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  // Selected cards keep a light tint plus a brand ring instead
                  // of a heavy solid fill, so they read as a card, not a row.
                  color: selected
                      ? accent.withValues(alpha: 0.10)
                      : _kPickerPaperBright,
                  borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
                  border: Border.all(
                    color: borderColor,
                    width: selected ? 1.6 : 1,
                  ),
                  boxShadow: _hovered || selected
                      ? const <BoxShadow>[
                          BoxShadow(
                            color: DcColors.lightCardShadow,
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Opacity(
                                opacity: isChecking ? 0.55 : 1,
                                child: _DatabaseBadge(
                                  record: widget.record,
                                  selected: false,
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      widget.record.nickname,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _pickerText(
                                        13,
                                        titleColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: <Widget>[
                                        if (indicatorHealth != null &&
                                            (isChecking || hasHealthError))
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(right: 5),
                                            child: _DatabaseHealthIndicator(
                                              health: indicatorHealth,
                                              onTap: widget.onShowHealthDetails,
                                              compact: true,
                                            ),
                                          ),
                                        Expanded(
                                          child: Text(
                                            _locationLabel(widget.record),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: _pickerText(
                                              11,
                                              subtitleColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Builder(
                                builder: (anchorContext) => _DatabaseItemMenu(
                                  selected: false,
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
                          const SizedBox(height: 9),
                          Text(
                            detailText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _pickerText(
                              10,
                              hasHealthError
                                  ? DcColors.redOnLight
                                  : _kPickerFaint,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Row(
                            children: <Widget>[
                              if (widget.record.isDefaultStartup)
                                _StatusChip(
                                  icon: TablerIcons.star_filled,
                                  label: 'Default',
                                  backgroundColor: DcColors.amber,
                                  foregroundColor: DcColors.sidebarText,
                                ),
                              const Spacer(),
                              if (widget.fileSize case final int bytes) ...<Widget>[
                                Tooltip(
                                  message:
                                      '${_formatFileSize(bytes)} on disk',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      const Icon(
                                        TablerIcons.database,
                                        size: 10,
                                        color: _kPickerFaint,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        _formatFileSize(bytes),
                                        style: _pickerText(
                                          10,
                                          _kPickerFaint,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 1,
                                  height: 9,
                                  color: _kPickerLine,
                                ),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                _formatCreatedAt(widget.record.addedAt),
                                style: _pickerText(
                                  10,
                                  _kPickerFaint,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: const BorderRadius.only(
                              topRight:
                                  Radius.circular(DcMetrics.panelRadius - 1),
                              bottomLeft: Radius.circular(8),
                            ),
                          ),
                          child: const Icon(
                            TablerIcons.check,
                            size: 11,
                            color: Colors.white,
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
        color: bg,
        borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
        border: Border.all(
          color: selected ? const Color(0x80FFFFFF) : _kPickerLine,
        ),
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
          color: compact ? _kPickerMuted : DcColors.selection,
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
            color: _kPickerInset,
            borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
            border: Border.all(color: _kPickerLine),
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
              color: DcColors.redOnLight,
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
          backgroundColor: const Color(0x1AD64541),
          foregroundColor: DcColors.redOnLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
            side: const BorderSide(color: Color(0x66D64541)),
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
          color: _kCredAccentTint,
          borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
          border: Border.all(color: _kCredLine),
        ),
        child: const Icon(
          TablerIcons.lock,
          size: 27,
          color: DcColors.selection,
        ),
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
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        border: Border.all(color: _kCredLine),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: _kCredShadow, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: Image.asset(asset, width: 31, height: 31),
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
        borderRadius: BorderRadius.circular(DcMetrics.badgeRadius),
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

class _VaultStatisticsFooter extends StatelessWidget {
  const _VaultStatisticsFooter({required this.databases});

  final List<DatabaseRecord> databases;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{
      'local': 0,
      CloudServiceProvider.googleDrive.storageType: 0,
      CloudServiceProvider.dropbox.storageType: 0,
      CloudServiceProvider.s3.storageType: 0,
      CloudServiceProvider.webdav.storageType: 0,
    };
    for (final database in databases) {
      if (counts.containsKey(database.storageType)) {
        counts[database.storageType] = counts[database.storageType]! + 1;
      }
    }

    final metrics = <Widget>[
      _StorageCountMetric(
        storageType: 'local',
        label: 'Local',
        assetPath: 'assets/images/dir.png',
        count: counts['local']!,
      ),
      _StorageCountMetric(
        storageType: CloudServiceProvider.googleDrive.storageType,
        label: CloudServiceProvider.googleDrive.label,
        assetPath: CloudServiceProvider.googleDrive.assetPath,
        count: counts[CloudServiceProvider.googleDrive.storageType]!,
      ),
      _StorageCountMetric(
        storageType: CloudServiceProvider.dropbox.storageType,
        label: CloudServiceProvider.dropbox.label,
        assetPath: CloudServiceProvider.dropbox.assetPath,
        count: counts[CloudServiceProvider.dropbox.storageType]!,
      ),
      _StorageCountMetric(
        storageType: CloudServiceProvider.s3.storageType,
        label: CloudServiceProvider.s3.label,
        assetPath: CloudServiceProvider.s3.assetPath,
        count: counts[CloudServiceProvider.s3.storageType]!,
      ),
      _StorageCountMetric(
        storageType: CloudServiceProvider.webdav.storageType,
        label: CloudServiceProvider.webdav.label,
        assetPath: CloudServiceProvider.webdav.assetPath,
        count: counts[CloudServiceProvider.webdav.storageType]!,
      ),
    ];

    return DcStatusBar(
      leading: <Widget>[
        Semantics(
          label: 'Total vaults: ${databases.length}',
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(TablerIcons.database, size: 13),
              const SizedBox(width: 6),
              Text(
                databases.length == 1
                    ? '1 vault'
                    : '${databases.length} vaults',
                style: _pickerText(
                  11,
                  DcColors.sidebarText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
      trailing: metrics,
    );
  }
}

class _StorageCountMetric extends StatelessWidget {
  const _StorageCountMetric({
    required this.storageType,
    required this.label,
    required this.assetPath,
    required this.count,
  });

  final String storageType;
  final String label;
  final String assetPath;
  final int count;

  @override
  Widget build(BuildContext context) {
    final description = '$label vaults: $count';
    return Tooltip(
      key: ValueKey<String>('supported-platform-$storageType'),
      message: description,
      child: Semantics(
        label: description,
        excludeSemantics: true,
        child: Opacity(
          opacity: count == 0 ? 0.48 : 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Image.asset(
                assetPath,
                width: 14,
                height: 14,
                errorBuilder: (_, __, ___) => Icon(
                  storageType == 'local'
                      ? TablerIcons.folder
                      : TablerIcons.cloud,
                  size: 14,
                  color: DcColors.sidebarMuted,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: _pickerText(
                  11,
                  DcColors.sidebarText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
        color: _kPickerInset,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        border: Border.all(color: _kPickerLine),
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
                  decoration: const BoxDecoration(
                    color: DcColors.lightSelectionFill,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    TablerIcons.database_off,
                    size: iconSz,
                    color: DcColors.selection,
                  ),
                ),
                SizedBox(height: tight ? 6 : 10),
                Text(
                  'No databases yet',
                  style: _pickerDisplayText(
                    tight ? 12 : 13,
                    _kPickerInk,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: tight ? 2 : 4),
                Text(
                  'Create a new database or open an existing .kdbx file.',
                  style: _pickerText(tight ? 10 : 11, _kPickerMuted),
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
        color: _kPickerInset,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        border: Border.all(color: _kPickerLine),
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
                  color: _kPickerMuted,
                ),
                SizedBox(height: tight ? 6 : 10),
                Text(
                  'No databases match your search',
                  style: _pickerDisplayText(
                    tight ? 12 : 13,
                    _kPickerInk,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: tight ? 2 : 4),
                Text(
                  'Try a different name or path keyword.',
                  style: _pickerText(tight ? 10 : 11, _kPickerMuted),
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
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      behavior: HitTestBehavior.opaque,
      onTapOutside: (_) => onClose(),
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x29263340),
                blurRadius: 14,
                spreadRadius: -3,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            style: _pickerText(12, _kPickerInk, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Search databases',
              hintStyle: _pickerText(12, _kPickerMuted),
              prefixIcon:
                  const Icon(TablerIcons.search, size: 16, color: _kPickerInk),
              suffixIcon: IconButton(
                tooltip: 'Close search',
                onPressed: onClose,
                icon: const Icon(
                  TablerIcons.x,
                  size: 14,
                  color: _kPickerInk,
                ),
              ),
              filled: true,
              fillColor: _kPickerPaper,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
                borderSide: const BorderSide(color: _kPickerLineStrong),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
                borderSide:
                    const BorderSide(color: DcColors.selection, width: 1.5),
              ),
            ),
          ),
        ),
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
            borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
            child: SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: AnimatedRotation(
                  turns: isRefreshing ? 1 : 0,
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeInOut,
                  child: Icon(
                    TablerIcons.refresh,
                    size: 14,
                    color: isRefreshing ? DcColors.selection : _kPickerMuted,
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
      // Shrink-wraps: this label is laid out as a non-flex child of a Row,
      // which hands down unbounded width constraints. A Flexible child here
      // would assert and take the whole tree down with it.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: _pickerText(
              10,
              active ? _kPickerInk : _kPickerMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            active
                ? (ascending
                    ? TablerIcons.chevron_up
                    : TablerIcons.chevron_down)
                : TablerIcons.selector,
            size: 12,
            color: active ? _kPickerInk : _kPickerFaint,
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
        ? (widget.primary ? _kUnlockPrimaryDisabled : const Color(0x0DFFFFFF))
        : (widget.primary
            ? (_hovered ? DcColors.selectionHover : DcColors.selection)
            : (_hovered ? const Color(0x2EFFFFFF) : const Color(0x17FFFFFF)));
    final foregroundColor = disabled
        ? DcColors.faint
        : (widget.primary ? Colors.white : DcColors.text);

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
            width: 30,
            height: 26,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
              border: widget.primary
                  ? null
                  : Border.all(
                      color: disabled ? DcColors.line : DcColors.lineStrong,
                    ),
            ),
            child: Icon(widget.icon, size: 14, color: foregroundColor),
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
      height: Platform.isMacOS ? 42 : DcMetrics.headerHeight,
      decoration: const BoxDecoration(
        color: DcColors.sidebar,
        border: Border(bottom: BorderSide(color: DcColors.sidebarLine)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: DcColors.selection,
              borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
            ),
            child: const Icon(
              TablerIcons.lock,
              size: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: LumenPassWordmark(
              fontSize: 18,
              lumenColor: DcColors.sidebarText,
              passColor: DcColors.selection,
              suffix: ' vaults',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
          style: _pickerDisplayText(22, DcColors.sidebarText, height: 1),
        ),
        const SizedBox(height: 5),
        Text(
          'Three ways to begin with a portable KeePass vault.',
          style: _pickerText(11, DcColors.sidebarMuted, height: 1.25),
        ),
        const SizedBox(height: 10),
        const _GuideItem(
          index: '01',
          icon: TablerIcons.database_plus,
          title: 'Create a new database',
          subtitle: 'Click "Create" to start a fresh vault',
          surface: Colors.white,
          accent: Color(0xFFD9A400),
        ),
        const SizedBox(height: 7),
        const _GuideItem(
          index: '02',
          icon: TablerIcons.folder_open,
          title: 'Open an existing database',
          subtitle: 'Click "Open" to browse local, Google Drive, or Dropbox',
          surface: Colors.white,
          accent: DcColors.selection,
        ),
        const SizedBox(height: 7),
        const _GuideItem(
          index: '03',
          icon: TablerIcons.lock_open,
          title: 'Unlock a database',
          subtitle: 'Double-click a database in the list to unlock it',
          surface: Colors.white,
          accent: Color(0xFF2E9E62),
        ),
        const SizedBox(height: 9),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0x14263340),
            borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
          ),
          child: Text(
            'PRIVATE BY DEFAULT  ·  Your files stay under your control. The default vault remains pinned first.',
            style: _pickerText(
              9.5,
              DcColors.sidebarText,
              fontWeight: FontWeight.w600,
              height: 1.3,
              letterSpacing: 0.15,
            ),
          ),
        ),
        const Spacer(),
        const _GuidePanelFooter(),
      ],
    );
  }
}

class _GuidePanelFooter extends StatelessWidget {
  const _GuidePanelFooter();

  static final Uri _githubRepository =
      Uri.parse('https://github.com/lumenpass/lumenpass');

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '© $year LumenPass  ·  v$version ($buildNumber)  ·  LOCAL-FIRST',
                style: _pickerText(
                  8.7,
                  DcColors.sidebarMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.35,
                ),
              ),
              const SizedBox(height: 3),
              Tooltip(
                message: 'Open the LumenPass repository on GitHub',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: InkWell(
                    onTap: () => launchUrl(_githubRepository),
                    borderRadius: BorderRadius.circular(5),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            TablerIcons.brand_github,
                            size: 11,
                            color: DcColors.sidebarMuted,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'github.com/lumenpass/lumenpass  ·  Apache-2.0',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _pickerText(
                                8.7,
                                DcColors.sidebarMuted,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: selected ? const Color(0x33FFFFFF) : _kPickerPaper,
                borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
                border: Border.all(
                  color:
                      selected ? const Color(0x66FFFFFF) : _kPickerLineStrong,
                ),
              ),
              child: Icon(
                TablerIcons.dots_vertical,
                size: 14,
                color: selected ? Colors.white : _kPickerMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideItem extends StatelessWidget {
  const _GuideItem({
    required this.index,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.surface,
    required this.accent,
  });

  final String index;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color surface;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        border: Border.all(color: DcColors.sidebarLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
            ),
            child: Icon(icon, size: 15, color: accent),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _pickerText(
                    11,
                    DcColors.sidebarText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _pickerText(9.5, DcColors.sidebarMuted, height: 1.18),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            index,
            style: _pickerText(
              8.5,
              DcColors.sidebarMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Unlock credentials dialog ────────────────────────────────────────────────

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
  late final TextEditingController _passwordController;
  bool _obscurePassword = true;
  bool _showAdvanced = false;
  bool _acceptNoPassword = false;
  String? _toastMessage;
  Timer? _toastTimer;
  bool _biometricEnabled = false;
  bool _pinEnabled = false;
  bool _showPinPad = false;
  List<int> _pinDigits = const [];
  bool _pinError = false;
  bool _autoPromptedLastMethod = false;
  bool _lifecycleResumedOnce = false;
  bool _onFocusPostFrameScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleResumedOnce =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _passwordController = TextEditingController();
    _loadUnlockPreferences();
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
    super.dispose();
  }

  void _toggleAdvanced(bool v) {
    setState(() => _showAdvanced = v);
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
      data: AppTheme.driveClueLight(),
      child: Material(
        color: _kUnlockDialogBackground,
        child: Stack(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      72,
                      Platform.isMacOS ? 46 : 28,
                      72,
                      22,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            _UnlockVaultIcon(record: matchedRecord),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    'UNLOCK YOUR VAULT',
                                    style: _pickerText(
                                      DcMetrics.sectionLabelSize,
                                      DcColors.selection,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    vaultName,
                                    style: _pickerDisplayText(
                                      27,
                                      _kCredInk,
                                      height: 1.05,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: <Widget>[
                                      const Icon(
                                        TablerIcons.map_pin,
                                        size: 13,
                                        color: _kCredMuted,
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          vaultSubtitle,
                                          style: _pickerText(
                                            11,
                                            _kCredMuted,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _kCredMintSoft,
                                borderRadius: BorderRadius.circular(
                                  DcMetrics.badgeRadius,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const Icon(
                                    TablerIcons.lock,
                                    size: 12,
                                    color: _kCredMint,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'ENCRYPTED',
                                    style: _pickerText(
                                      8.5,
                                      _kCredInk,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.7,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _kUnlockCardBackground,
                            borderRadius:
                                BorderRadius.circular(DcMetrics.panelRadius),
                            border: Border.all(color: _kCredLine),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: _kCredShadow,
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: _kCredAccentTint,
                                      borderRadius: BorderRadius.circular(
                                        DcMetrics.controlRadius,
                                      ),
                                    ),
                                    child: const Icon(
                                      TablerIcons.key,
                                      size: 17,
                                      color: DcColors.selection,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          'Enter your credentials',
                                          style: _pickerText(
                                            13,
                                            _kCredInk,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          'Your master password stays on this device.',
                                          style: _pickerText(
                                            10.5,
                                            _kCredMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Master password',
                                style: _pickerText(
                                  10.5,
                                  _kCredInk,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: <Widget>[
                                  Expanded(
                                    child: _UnlockShadowedInput(
                                      child: TextField(
                                        controller: _passwordController,
                                        obscureText: _obscurePassword,
                                        enabled: !_acceptNoPassword,
                                        enableSuggestions: false,
                                        autocorrect: false,
                                        autofocus: true,
                                        textInputAction: TextInputAction.done,
                                        onChanged: (_) =>
                                            controller.clearError(),
                                        onSubmitted: (_) => _submit(),
                                        style: _pickerText(
                                          12.5,
                                          _kUnlockFieldText,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        decoration: _unlockFieldDecoration(
                                          hint: _acceptNoPassword
                                              ? 'No password required'
                                              : 'Enter master password',
                                          prefixIcon: TablerIcons.lock_password,
                                          suffix: _acceptNoPassword
                                              ? null
                                              : IconButton(
                                                  tooltip: _obscurePassword
                                                      ? 'Show password'
                                                      : 'Hide password',
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
                                    const SizedBox(width: 7),
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
                              const SizedBox(height: 11),
                              Container(
                                padding: const EdgeInsets.fromLTRB(11, 7, 5, 7),
                                decoration: BoxDecoration(
                                  color: _acceptNoPassword
                                      ? _kUnlockAccentSoft
                                      : _kCredInset,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _acceptNoPassword
                                        ? _kUnlockAccentBorder
                                        : _kCredLine,
                                  ),
                                ),
                                child: Row(
                                  children: <Widget>[
                                    Icon(
                                      TablerIcons.key_off,
                                      size: 16,
                                      color: _acceptNoPassword
                                          ? _kCredMint
                                          : _kCredMuted,
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            'Use key file only',
                                            style: _pickerText(
                                              11,
                                              _kCredInk,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            'Accept an empty master password',
                                            style: _pickerText(
                                              9.8,
                                              _kCredMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Transform.scale(
                                      scale: 0.72,
                                      alignment: Alignment.centerRight,
                                      child: Switch.adaptive(
                                        value: _acceptNoPassword,
                                        activeTrackColor: _kCredMint,
                                        activeThumbColor: _kCredSurface,
                                        inactiveTrackColor: _kCredLineStrong,
                                        inactiveThumbColor: _kCredSurface,
                                        onChanged: (bool v) {
                                          setState(() {
                                            _acceptNoPassword = v;
                                            if (v) {
                                              _passwordController.clear();
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.fromLTRB(11, 7, 5, 7),
                                decoration: BoxDecoration(
                                  color: _kCredInset,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _kCredLine),
                                ),
                                child: Row(
                                  children: <Widget>[
                                    const Icon(
                                      TablerIcons.adjustments_horizontal,
                                      size: 16,
                                      color: _kCredMuted,
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            'Advanced options',
                                            style: _pickerText(
                                              11,
                                              _kCredInk,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            'Key files and hardware keys',
                                            style: _pickerText(
                                              9.8,
                                              _kCredMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Transform.scale(
                                      scale: 0.72,
                                      alignment: Alignment.centerRight,
                                      child: Switch.adaptive(
                                        value: _showAdvanced,
                                        activeTrackColor: _kPickerOrange,
                                        activeThumbColor: _kCredSurface,
                                        inactiveTrackColor: _kCredLineStrong,
                                        inactiveThumbColor: _kCredSurface,
                                        onChanged: _toggleAdvanced,
                                      ),
                                    ),
                                  ],
                                ),
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
                                  onClear: hasKeyFile
                                      ? controller.clearKeyFile
                                      : null,
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
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: _kCredCanvas,
                    border: Border(
                      top: BorderSide(color: _kCredLine),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: Row(
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: state.isLoading
                            ? null
                            : () => Navigator.of(context).pop(false),
                        icon: const Icon(TablerIcons.arrow_left, size: 16),
                        label: const Text('Back'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kUnlockGhostText,
                          backgroundColor: _kCredSurface,
                          disabledForegroundColor: _kUnlockGhostText.withValues(
                            alpha: 0.5,
                          ),
                          disabledBackgroundColor: _kUnlockGhostBg,
                          side: const BorderSide(color: _kUnlockGhostBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              DcMetrics.controlRadius,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          textStyle: _pickerText(
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
                            : const Icon(TablerIcons.lock_open, size: 14),
                        label: const Text('Unlock vault'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPickerOrange,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _kUnlockPrimaryDisabled,
                          shadowColor: Colors.transparent,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 9,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              DcMetrics.controlRadius,
                            ),
                          ),
                          textStyle: _pickerText(
                            12,
                            Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ).copyWith(
                          backgroundColor:
                              WidgetStateProperty.resolveWith<Color>((states) {
                            if (states.contains(WidgetState.disabled)) {
                              return _kUnlockPrimaryDisabled;
                            }
                            if (states.contains(WidgetState.hovered)) {
                              return _kUnlockPrimaryHover;
                            }
                            return _kPickerOrange;
                          }),
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
                    color: const Color(0x59263340),
                    child: Center(
                      child: Container(
                        width: 280,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: _kCredSurface,
                          borderRadius:
                              BorderRadius.circular(DcMetrics.panelRadius),
                          border: Border.all(color: _kCredLine),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x29263340),
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
                                borderRadius: BorderRadius.circular(
                                  DcMetrics.panelRadius,
                                ),
                                color: DcColors.selection,
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
                                _kCredInk,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Decrypting the database and preparing your items.',
                              style: _uText(12, _kCredMuted),
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
                      color: DcColors.redOnLight,
                      borderRadius:
                          BorderRadius.circular(DcMetrics.panelRadius),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x40000000),
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
      color: _kCredCanvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(height: Platform.isMacOS ? 46 : 24),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _kCredAccentTint,
                      borderRadius:
                          BorderRadius.circular(DcMetrics.panelRadius),
                    ),
                    child: const Icon(
                      TablerIcons.lock,
                      size: 24,
                      color: DcColors.selection,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    vaultName,
                    style: _pickerDisplayText(25, _kCredInk, height: 1.05),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enter your 6-digit PIN',
                    style: _pickerText(11, _kCredMuted),
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
                                ? DcColors.redOnLight
                                : filled
                                    ? _kPickerOrange
                                    : Colors.transparent,
                            border: Border.all(
                              color: _pinError
                                  ? DcColors.redOnLight
                                  : filled
                                      ? _kPickerOrange
                                      : _kCredLine,
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
                      style: _pickerText(10.5, DcColors.redOnLight),
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

class _UnlockShadowedInput extends StatelessWidget {
  const _UnlockShadowedInput({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: const <BoxShadow>[],
      ),
      child: CustomPaint(
        foregroundPainter: const _UnlockInputInnerShadowPainter(),
        child: child,
      ),
    );
  }
}

class _UnlockInputInnerShadowPainter extends CustomPainter {
  const _UnlockInputInnerShadowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final fieldBounds = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    final outside = Path()
      ..addRect(Rect.fromLTRB(-12, -12, size.width + 12, size.height + 12));
    final inset = Path()
      ..addRRect(fieldBounds.deflate(0.5).shift(const Offset(0, 0.75)));
    final innerEdge = Path.combine(PathOperation.difference, outside, inset);

    canvas
      ..save()
      ..clipRRect(fieldBounds)
      ..drawPath(
        innerEdge,
        Paint()
          ..color = const Color(0x1A263340)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _UnlockInputInnerShadowPainter oldDelegate) =>
      false;
}

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
          color: _pressed ? DcColors.selection : _kCredSurface,
          borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
          border: Border.all(color: _kCredLine),
        ),
        alignment: Alignment.center,
        child: widget.icon != null
            ? Icon(widget.icon, size: 16, color: _kCredMuted)
            : Text(
                widget.label!,
                style: _pickerText(
                  17,
                  _kCredInk,
                  fontWeight: FontWeight.w700,
                ),
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
          color: _kCredSurface,
          borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
          border: Border.all(color: _kCredLineStrong),
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(
            icon,
            size: 16,
            color: onPressed == null
                ? _kCredMuted.withValues(alpha: 0.5)
                : _kCredInk,
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
        color: _kCredInset,
        borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
        border: Border.all(color: _kCredLine),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _kCredAccentTint,
              borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
            ),
            child: Icon(icon, size: 14, color: DcColors.selection),
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
                      style: _pickerText(
                        11,
                        _kCredInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (badge != null) ...<Widget>[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: DcColors.amber,
                          borderRadius:
                              BorderRadius.circular(DcMetrics.badgeRadius),
                        ),
                        child: Text(
                          badge!,
                          style: _pickerText(
                            8.5,
                            DcColors.sidebarText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  subtitle,
                  style: _pickerText(10, _kCredMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (hasValue && onClear != null)
            IconButton(
              onPressed: onClear,
              icon: const Icon(
                TablerIcons.x,
                size: 14,
                color: _kCredMuted,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            )
          else if (badge == null)
            TextButton(
              onPressed: onChoose,
              style: TextButton.styleFrom(
                foregroundColor: _kPickerOrangeDark,
                textStyle: _pickerText(
                  10.5,
                  _kPickerOrangeDark,
                  fontWeight: FontWeight.w700,
                ),
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

/// Display name of a storage group header.
String _storageGroupTitle(String storageType) {
  switch (storageType) {
    case 'local':
      return 'This Mac';
    default:
      return providerLabelForStorageType(storageType);
  }
}

/// Bundled logo for a storage group header and card badges.
String _storageGroupAsset(String storageType) {
  switch (storageType) {
    case 'googleDrive':
      return 'assets/images/google-drive.png';
    case 'dropbox':
      return 'assets/images/dropbox.png';
    case 'oneDrive':
      return 'assets/images/onedrive.png';
    case 'webdav':
      return 'assets/images/webdav.png';
    case 'sftp':
      return 'assets/images/sftp.png';
    case 's3':
      return 'assets/images/aws-s3-icon.png';
    default:
      return 'assets/images/dir.png';
  }
}

/// Brand accent used for the group chip, card edge and selection ring.
Color _storageGroupAccent(String storageType) {
  switch (storageType) {
    case 'googleDrive':
      return StorageBrandColors.googleDrive;
    case 'dropbox':
      return StorageBrandColors.dropbox;
    case 'oneDrive':
      return StorageBrandColors.oneDrive;
    case 'webdav':
      return StorageBrandColors.webDav;
    case 'sftp':
      return StorageBrandColors.sftp;
    case 's3':
      return StorageBrandColors.s3;
    default:
      return StorageBrandColors.local;
  }
}

/// Human-readable file size for vault cards (e.g. `48.2 KB`, `1.24 MB`).
String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final double kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final double mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 2 : 1)} MB';
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

/// Light confirmation surface for a vault whose cloud sync is unhealthy.
///
/// Migrated from a dark [AlertDialog] so it matches the light vault list it is
/// opened from: branded title bar, warning heading, bulleted next steps, then
/// Close / Check again / Unlink / Reconnect.
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

    return DcConfirmDialog(
      barTitle: 'Vault sync issue',
      heading: health.title ?? 'This vault needs attention',
      message: '"${record.nickname}" is linked to $providerLabel.\n\n'
          '${health.details ?? 'The vault cannot confirm sync health.'}',
      icon: TablerIcons.alert_triangle,
      width: 500,
      confirmLabel: 'Reconnect $providerLabel',
      confirmIcon: TablerIcons.refresh,
      // Cancel and the title-bar close both surface as "no action taken".
      onCancel: () =>
          Navigator.of(context).pop(_DatabaseHealthDialogAction.close),
      onConfirm: () =>
          Navigator.of(context).pop(_DatabaseHealthDialogAction.reconnect),
      extraActions: <Widget>[
        if (_canReconnect)
          _HealthDialogActionButton(
            label: 'Unlink Databases',
            color: DcColors.redOnLight,
            onPressed: () => Navigator.of(context)
                .pop(_DatabaseHealthDialogAction.unlinkDatabases),
          ),
        _HealthDialogActionButton(
          label: 'Check again',
          color: DcColors.selection,
          onPressed: () =>
              Navigator.of(context).pop(_DatabaseHealthDialogAction.retry),
        ),
      ],
      body: health.recommendedActions.isEmpty
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Recommended actions',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: DcColors.sidebarText,
                  ),
                ),
                const SizedBox(height: 8),
                for (final action in health.recommendedActions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.only(top: 5, right: 8),
                          decoration: const BoxDecoration(
                            color: DcColors.selection,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            action,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: DcColors.sidebarMuted,
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

/// Ghost footer button used by the vault-health dialog for its secondary
/// actions (Check again / Unlink Databases).
class _HealthDialogActionButton extends StatelessWidget {
  const _HealthDialogActionButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Spacing between footer actions is owned by the dialog's footer Wrap, so
    // this button must not add its own trailing margin.
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
