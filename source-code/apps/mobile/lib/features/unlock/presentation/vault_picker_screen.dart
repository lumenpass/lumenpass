import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/services/cloud_database_service.dart';

import '../../../core/ui/app_snack_bar.dart';
import '../../../core/ui/floating_glass_search_bar.dart';
import '../../../l10n/app_localizations.dart';

// TODO: Re-enable when cloud services modal is stable.
// import '../../cloud/presentation/cloud_services_screen.dart' show showCloudServicesModal;
import '../../cloud/application/cloud_disconnect.dart';
import '../../cloud/application/cloud_service_provider.dart';
import '../../onboarding/application/spotlight_walkthrough_provider.dart';
import '../../onboarding/presentation/spotlight_walkthrough.dart';
import '../application/database_connection_health.dart';
import '../application/database_registry.dart';
import 'add_vault_sheet.dart';
import 'cloud_browser_page.dart';
import 'duplicate_database_modal.dart';
import 'unlock_vault_screen.dart';
import 'webdav_config_page.dart';
import 'sftp_config_page.dart';
import 's3_config_dialog.dart';

const _pickerBackground = Color(0xFFF4F9FA);
const _pickerInk = Color(0xFF0A3B48);

const _pickerMuted = Color(0xFF6B858D);
const _pickerCardBorder = Color(0xFFE3EAF0);
const _defaultBadgeBg = Color(0xFFEEF3FF);
const _defaultBadgeFg = Color(0xFF4B6CFF);
const _menuBorder = Color(0xFFE8EEF2);
const _pickerFloatingHeaderTopInset = 10.0;

// ── Screen ────────────────────────────────────────────────────────────────────

class VaultPickerScreen extends ConsumerStatefulWidget {
  const VaultPickerScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  ConsumerState<VaultPickerScreen> createState() => _VaultPickerScreenState();
}

class _VaultPickerScreenState extends ConsumerState<VaultPickerScreen> {
  static const _manualWalkthroughStartIndex = 0;

  final _searchController = TextEditingController();
  final _headerKey = GlobalKey();
  final _searchKey = GlobalKey();
  final _vaultListKey = GlobalKey();
  final _quickAccessKey = GlobalKey();
  final _quickActionsKey = GlobalKey();
  final _fabKey = GlobalKey();
  String _query = '';
  bool _manualWalkthroughActive = false;
  int? _manualWalkthroughIndex;
  final Map<String, DatabaseConnectionHealth> _databaseHealth =
      <String, DatabaseConnectionHealth>{};
  String? _databaseHealthSignature;
  int _databaseHealthGeneration = 0;
  bool _isRefreshingDatabaseHealth = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_syncSearchQuery);
  }

  @override
  void dispose() {
    _searchController.removeListener(_syncSearchQuery);
    _searchController.dispose();
    super.dispose();
  }

  void _syncSearchQuery() {
    _setSearchQuery(_searchController.text);
  }

  void _setSearchQuery(String value) {
    if (_query == value) return;
    setState(() => _query = value);
  }

  List<SpotlightWalkthroughStep> _walkthroughSteps(bool hasVaults) {
    return [
      SpotlightWalkthroughStep(
        key: _headerKey,
        title: 'Your vaults',
        message: 'Manage encrypted vaults stored locally or in the cloud.',
        borderRadius: 18,
      ),
      SpotlightWalkthroughStep(
        key: _searchKey,
        title: 'Search vaults',
        message:
            'Type a vault name, provider, or file name to find it quickly.',
        borderRadius: 18,
      ),
      if (hasVaults)
        SpotlightWalkthroughStep(
          key: _vaultListKey,
          title: 'Manage vaults',
          message:
              'Open a vault or use the menu to duplicate, export, or remove it.',
          borderRadius: 18,
        ),
      SpotlightWalkthroughStep(
        key: _quickAccessKey,
        title: 'Storage options',
        message:
            'Pick Local, Google Drive, or Dropbox before creating or opening.',
        borderRadius: 24,
      ),
      SpotlightWalkthroughStep(
        key: _quickActionsKey,
        title: 'Start here',
        message:
            'Create a new encrypted vault or open an existing database file.',
        borderRadius: 18,
      ),
      SpotlightWalkthroughStep(
        key: _fabKey,
        title: 'Quick add',
        message: 'Tap plus anytime to add another vault from this screen.',
        borderRadius: 999,
      ),
    ];
  }

  void _startManualWalkthrough() {
    if (_manualWalkthroughActive) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _manualWalkthroughActive = true;
      _manualWalkthroughIndex = _manualWalkthroughStartIndex;
    });
  }

  Future<void> _finishWalkthrough({required bool persistCompletion}) async {
    if (persistCompletion) {
      await ref.read(spotlightWalkthroughProvider.notifier).complete();
    }
    if (!mounted || !_manualWalkthroughActive) return;
    setState(() {
      _manualWalkthroughActive = false;
      _manualWalkthroughIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final topInset = MediaQuery.of(context).padding.top;

    final allRecords = ref.watch(databaseRegistryProvider);
    final sorted = _sortedVaults(allRecords);
    _scheduleDatabaseHealthChecks(sorted);
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? sorted
        : sorted.where((r) => _recordMatchesSearch(r, q)).toList();
    final walkthrough = ref.watch(spotlightWalkthroughProvider);
    final steps = _walkthroughSteps(filtered.isNotEmpty);
    final showAutomaticWalkthrough =
        walkthrough.loaded && !walkthrough.completed && steps.isNotEmpty;
    final showWalkthrough =
        steps.isNotEmpty &&
        (_manualWalkthroughActive || showAutomaticWalkthrough);
    final activeWalkthroughIndex = showWalkthrough
        ? (_manualWalkthroughActive
              ? (_manualWalkthroughIndex ?? _manualWalkthroughStartIndex)
              : walkthrough.lastStep.clamp(0, steps.length - 1))
        : null;
    final initialWalkthroughIndex =
        activeWalkthroughIndex ?? _manualWalkthroughStartIndex;
    final revealFloatingToolbarActions =
        activeWalkthroughIndex == 1 ||
        activeWalkthroughIndex == steps.length - 1;
    final headerTop = topInset + _pickerFloatingHeaderTopInset;
    const headerHeight = 64.0;
    final contentTopPadding = headerTop + headerHeight + 16;

    return Scaffold(
      backgroundColor: _pickerBackground,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.only(top: contentTopPadding, bottom: 108),
            children: [
              if (filtered.isEmpty)
                _buildEmptyState(context, allRecords.isEmpty, l)
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 2, bottom: 8),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _DatabaseHealthRefreshButton(
                            isRefreshing: _isRefreshingDatabaseHealth,
                            onRefresh: _refreshAllDatabaseHealth,
                          ),
                        ),
                      ),
                      KeyedSubtree(
                        key: _vaultListKey,
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          clipBehavior: Clip.antiAlias,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: _pickerCardBorder),
                            ),
                            child: Column(
                              children: [
                                ...filtered.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final record = entry.value;
                                  final isLast = index == filtered.length - 1;

                                  final health = _databaseHealth[record.id];
                                  final interactionBlocked =
                                      _isDatabaseInteractionBlocked(
                                        record,
                                        health: health,
                                      );
                                  return _VaultTile(
                                    record: record,

                                    health: health,
                                    interactionBlocked: interactionBlocked,
                                    grouped: true,
                                    showDivider: !isLast,
                                    onTap: interactionBlocked
                                        ? null
                                        : () => _openVault(record),
                                    onDelete: () => _deleteVault(record),
                                    onSetDefault: () => ref
                                        .read(databaseRegistryProvider.notifier)
                                        .setDefaultStartup(record.id),
                                    onDuplicate: () => _duplicateVault(record),
                                    onSaveAs: () => _saveDatabaseAs(record),
                                    onShowHealthDetails:
                                        health != null && health.hasError
                                        ? () =>
                                              _showDatabaseHealthDetails(record)
                                        : null,
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: KeyedSubtree(
                  key: _quickAccessKey,
                  child: _QuickAccessSection(
                    actionsKey: _quickActionsKey,
                    onOpenVault: _openVault,
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 10,
            right: 10,
            top: headerTop,
            child: _buildHeader(context),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: FloatingGlassSearchToolbar(
                searchKey: _searchKey,
                addKey: _fabKey,
                hintText: l.vaultPickerSearchHint,
                controller: _searchController,
                onChanged: _setSearchQuery,
                onAdd: _showAddVaultSheet,
                addSemanticLabel: 'Add vault',
                forceActionButtonsVisible: revealFloatingToolbarActions,
              ),
            ),
          ),
          if (showWalkthrough)
            Positioned.fill(
              child: SpotlightWalkthroughOverlay(
                steps: steps,
                initialIndex: initialWalkthroughIndex,
                onStepChanged: (index) {
                  if (_manualWalkthroughActive) {
                    setState(() => _manualWalkthroughIndex = index);
                    return;
                  }
                  ref
                      .read(spotlightWalkthroughProvider.notifier)
                      .setStep(index);
                },
                onFinish: () => _finishWalkthrough(
                  persistCompletion: showAutomaticWalkthrough,
                ),
                onSkip: () => _finishWalkthrough(
                  persistCompletion: showAutomaticWalkthrough,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      key: _headerKey,
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _pickerCardBorder),
        boxShadow: [
          BoxShadow(
            color: _pickerInk.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: -10,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: _pickerInk, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Vaults',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _pickerInk,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Replay walkthrough',
            onPressed: _startManualWalkthrough,
            icon: const Icon(Icons.help_outline_rounded, color: _pickerMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool noVaults, AppL10n l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
      child: Center(
        child: Column(
          children: [
            Icon(
              noVaults ? Icons.lock_open_outlined : Icons.search_off_rounded,
              size: 56,
              color: _pickerMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              noVaults
                  ? l.vaultPickerEmptyTitle
                  : l.vaultPickerNoResults(_query),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _pickerMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (noVaults)
              Text(
                l.vaultPickerEmptyHint,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: _pickerMuted),
              ),
          ],
        ),
      ),
    );
  }

  void _openVault(DatabaseRecord record) {
    unawaited(_openVaultAfterHealthCheck(record));
  }

  Future<void> _openVaultAfterHealthCheck(DatabaseRecord record) async {
    if (!await _ensureDatabaseHealthAllowsUnlock(record)) return;
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnlockVaultScreen(record: record),
      ),
    );
  }

  void _deleteVault(DatabaseRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove vault?'),
        content: Text(
          'Remove "${record.nickname}" from your list?\n\nThe database file will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(databaseRegistryProvider.notifier)
          .removeDatabase(record.id);
    }
  }

  void _showAddVaultSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddVaultSheet(onAdded: _openVault),
    );
  }

  Future<void> _duplicateVault(DatabaseRecord record) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => DuplicateDatabaseModal(
          source: record,
          defaultNickname: _nextDuplicateNickname(
            record.nickname,
            ref.read(databaseRegistryProvider),
          ),
          onDuplicated: (dup) async {
            if (!mounted) return;
            AppSnackBar.success(context, 'Duplicated as "${dup.nickname}"');
          },
        ),
      ),
    );
  }

  Future<void> _saveDatabaseAs(DatabaseRecord record) async {
    try {
      final source = File(record.databasePath);
      if (!await source.exists()) {
        if (!mounted) return;
        AppSnackBar.error(context, 'Could not find the source database file.');
        return;
      }

      final bytes = await source.readAsBytes();
      final defaultName = _suggestSaveAsFileName(record);

      // On mobile `saveFile` opens the native save/share sheet and lets the
      // user pick an arbitrary location. Bytes are passed directly so the
      // picker can write them without us needing write permission to the
      // chosen folder.
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Database As',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: const ['kdbx', 'kdb'],
        bytes: bytes,
      );

      if (!mounted) return;
      if (destination == null || destination.isEmpty) return;

      // On Android/desktop the picker returns the full path and we still
      // need to write the bytes ourselves; on iOS the picker already wrote
      // the file (or opened Files.app) so this write is a no-op when the
      // path isn't directly writable.
      if (Platform.isAndroid || Platform.isMacOS || Platform.isWindows) {
        try {
          final out = File(destination);
          if (!await out.exists() || await out.length() != bytes.length) {
            await out.writeAsBytes(bytes, flush: true);
          }
        } catch (_) {
          // Ignore — the picker already persisted the bytes for us.
        }
      }

      if (!mounted) return;
      AppSnackBar.success(
        context,
        'Saved a copy to ${p.basename(destination)}',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, 'Could not save database: $e');
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
    final ext = (extension == '.kdbx' || extension == '.kdb')
        ? extension
        : '.kdbx';
    return '$safeBase$ext';
  }

  String _nextDuplicateNickname(
    String nickname,
    List<DatabaseRecord> existingRecords,
  ) {
    final existingNames = existingRecords
        .map((record) => record.nickname)
        .toSet();
    var candidate = '$nickname Copy';
    var index = 2;
    while (existingNames.contains(candidate)) {
      candidate = '$nickname Copy $index';
      index += 1;
    }
    return candidate;
  }

  // ── Database connection health ────────────────────────────────────────────

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

  /// Manually re-checks the connection status of every registered database.
  /// Bound to the refresh button in the list header.
  Future<void> _refreshAllDatabaseHealth() async {
    if (_isRefreshingDatabaseHealth) return;
    await _refreshDatabaseHealth(ref.read(databaseRegistryProvider));
  }

  Future<void> _refreshDatabaseHealth(List<DatabaseRecord> databases) async {
    final generation = ++_databaseHealthGeneration;
    final cloudRecords = databases
        .where(isCloudBackedDatabaseRecord)
        .toList(growable: false);
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
      health = await ref
          .read(databaseConnectionHealthProbeProvider)
          .check(record);
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
      builder: (_) =>
          _DatabaseHealthIssueDialog(record: record, health: health),
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _DatabaseHealthDialogAction.close:
        return;
      case _DatabaseHealthDialogAction.retry:
        final refreshed = await _refreshSingleDatabaseHealth(record);
        if (!mounted) return;
        if (refreshed.isHealthy) {
          AppSnackBar.success(
            context,
            '${record.nickname} is ready to sync again.',
          );
        } else {
          AppSnackBar.error(
            context,
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
          AppSnackBar.success(
            context,
            '${record.nickname} is ready to sync again.',
          );
        } else {
          AppSnackBar.error(
            context,
            refreshed.title ?? 'This vault still needs attention.',
          );
        }
        return;
      case _DatabaseHealthDialogAction.unlinkDatabases:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unlink databases?'),
            content: Text(
              'This will remove all '
              '${providerLabelForStorageType(record.storageType)} '
              'databases from your vault list.\n\nThe database files will '
              'not be deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Unlink all'),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          await ref
              .read(databaseRegistryProvider.notifier)
              .removeByStorageType(record.storageType);
          if (mounted) {
            AppSnackBar.info(
              context,
              'All ${providerLabelForStorageType(record.storageType)} '
              'databases have been removed from the list.',
            );
          }
        }
        return;
    }
  }

  Future<bool> _reconnectCloudProvider(String storageType) async {
    try {
      switch (storageType) {
        case 'googleDrive':
          await CloudDatabaseService.instance.connectGoogle();
          return true;
        case 'dropbox':
          await CloudDatabaseService.instance.connectDropbox();
          return true;
        case 'oneDrive':
          await CloudDatabaseService.instance.connectOneDrive();
          return true;
        default:
          if (mounted) {
            AppSnackBar.info(
              context,
              'Open Settings to reconnect '
              '${providerLabelForStorageType(storageType)}.',
            );
          }
          return false;
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Could not reconnect: $e');
      }
      return false;
    }
  }
}

// ── Database health refresh button ────────────────────────────────────────────

/// Manual refresh control shown above the database list. Re-checks the
/// connection status of every registered database when tapped. While a refresh
/// is in flight the icon spins, turns blue, and the button is disabled.
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
              width: 34,
              height: 34,
              child: Center(
                child: AnimatedRotation(
                  turns: isRefreshing ? 1 : 0,
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeInOut,
                  child: Icon(
                    TablerIcons.refresh,
                    size: 19,
                    color: isRefreshing ? _defaultBadgeFg : _pickerMuted,
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

// ── Quick Access Section ──────────────────────────────────────────────────────

enum _StorageProvider {
  local,
  googleDrive,
  dropbox,
  oneDrive,
  webDav,
  sftp,
  s3,
}

class _QuickAccessSection extends ConsumerStatefulWidget {
  const _QuickAccessSection({
    required this.actionsKey,
    required this.onOpenVault,
  });

  final GlobalKey actionsKey;
  final void Function(DatabaseRecord) onOpenVault;

  @override
  ConsumerState<_QuickAccessSection> createState() =>
      _QuickAccessSectionState();
}

class _QuickAccessSectionState extends ConsumerState<_QuickAccessSection> {
  _StorageProvider _selected = _StorageProvider.local;
  bool _busy = false;

  String? _connectedEmail(_StorageProvider provider) {
    return switch (provider) {
      _StorageProvider.googleDrive => ref.watch(cloudGoogleAccountProvider),
      _StorageProvider.dropbox => ref.watch(cloudDropboxAccountProvider),
      _StorageProvider.oneDrive => ref.watch(cloudOneDriveAccountProvider),
      _StorageProvider.webDav => ref.watch(cloudWebDavAccountProvider),
      _StorageProvider.sftp => ref.watch(cloudSftpAccountProvider),
      _StorageProvider.s3 => ref.watch(cloudS3AccountProvider),
      _StorageProvider.local => null,
    };
  }

  bool _isConfigured(_StorageProvider provider) {
    return switch (provider) {
      _StorageProvider.googleDrive =>
        CloudDatabaseService.isGoogleDriveConfigured,
      _StorageProvider.dropbox => CloudDatabaseService.isDropboxConfigured,
      _StorageProvider.oneDrive => CloudDatabaseService.isOneDriveConfigured,
      _StorageProvider.webDav => CloudDatabaseService.isWebDavConfigured,
      _StorageProvider.sftp => true, // SFTP is always usable
      _StorageProvider.s3 => true, // S3 is always usable
      _StorageProvider.local => true,
    };
  }

  bool _isConnected(_StorageProvider provider) {
    return switch (provider) {
      _StorageProvider.googleDrive =>
        ref.watch(cloudGoogleAccountProvider) != null,
      _StorageProvider.dropbox =>
        ref.watch(cloudDropboxAccountProvider) != null,
      _StorageProvider.oneDrive =>
        ref.watch(cloudOneDriveAccountProvider) != null,
      _StorageProvider.webDav => ref.watch(cloudWebDavAccountProvider) != null,
      _StorageProvider.sftp => ref.watch(cloudSftpAccountProvider) != null,
      _StorageProvider.s3 => ref.watch(cloudS3AccountProvider) != null,
      _StorageProvider.local => true,
    };
  }

  /// Maps the local [_StorageProvider] enum to the canonical [CloudServiceProvider]
  /// used by the shared disconnect flow.
  CloudServiceProvider _toCloudServiceProvider(_StorageProvider provider) {
    return switch (provider) {
      _StorageProvider.googleDrive => CloudServiceProvider.googleDrive,
      _StorageProvider.dropbox => CloudServiceProvider.dropbox,
      _StorageProvider.oneDrive => CloudServiceProvider.oneDrive,
      _StorageProvider.webDav => CloudServiceProvider.webdav,
      _StorageProvider.sftp => CloudServiceProvider.sftp,
      _StorageProvider.s3 => CloudServiceProvider.s3,
      _StorageProvider.local => throw ArgumentError(
        'local storage has no cloud mapping',
      ),
    };
  }

  Future<void> _toggleConnection(_StorageProvider provider) async {
    if (_busy) return;

    // WebDAV and SFTP use a credentials form rather than an OAuth round-trip.
    if (provider == _StorageProvider.webDav && !_isConnected(provider)) {
      await _connectWebDav();
      return;
    }
    if (provider == _StorageProvider.sftp && !_isConnected(provider)) {
      await _connectSftp();
      return;
    }
    if (provider == _StorageProvider.s3 && !_isConnected(provider)) {
      await _connectS3();
      return;
    }

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      if (_isConnected(provider)) {
        final confirmed = await confirmCloudDisconnect(context);
        if (!confirmed || !mounted) return;
        final cloudProvider = _toCloudServiceProvider(provider);
        await performCloudDisconnect(ref, cloudProvider);
      } else {
        if (provider == _StorageProvider.googleDrive) {
          await CloudDatabaseService.instance.connectGoogle();
        } else if (provider == _StorageProvider.dropbox) {
          await CloudDatabaseService.instance.connectDropbox();
        } else if (provider == _StorageProvider.oneDrive) {
          await CloudDatabaseService.instance.connectOneDrive();
        }
      }
    } catch (e) {
      if (messenger.mounted) {
        AppSnackBar.error(
          context,
          'Connection failed: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the WebDAV credentials form. Returns once the user connects or
  /// cancels — `cloudWebDavAccountProvider` reflects the connected state.
  Future<bool> _connectWebDav() async {
    final account = await Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        builder: (_) => WebDavConfigPage(
          initialConfig: CloudDatabaseService.instance.currentWebDavConfig,
        ),
        fullscreenDialog: true,
      ),
    );
    return account != null;
  }

  /// Opens the SFTP credentials form. Returns once the user connects or
  /// cancels — `cloudSftpAccountProvider` reflects the connected state.
  Future<bool> _connectSftp() async {
    final account = await Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        builder: (_) => SftpConfigPage(
          initialConfig: CloudDatabaseService.instance.currentSftpConfig,
        ),
        fullscreenDialog: true,
      ),
    );
    return account != null;
  }

  Future<bool> _connectS3() async {
    final account = await Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        builder: (_) => const S3ConfigDialog(),
        fullscreenDialog: true,
      ),
    );
    return account != null;
  }

  void _createVault() {
    if (_selected == _StorageProvider.local) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CreateDatabasePage(onAdded: widget.onOpenVault),
          fullscreenDialog: true,
        ),
      );
    } else {
      _openCloudBrowserForCreate();
    }
  }

  Future<void> _openCloudBrowserForCreate() async {
    final cloudKind = switch (_selected) {
      _StorageProvider.googleDrive => CloudKind.googleDrive,
      _StorageProvider.dropbox => CloudKind.dropbox,
      _StorageProvider.oneDrive => CloudKind.oneDrive,
      _StorageProvider.webDav => CloudKind.webdav,
      _StorageProvider.sftp => CloudKind.sftp,
      _StorageProvider.s3 => CloudKind.s3,
      _StorageProvider.local => CloudKind.googleDrive,
    };

    if (!_isConnected(_selected)) {
      await _toggleConnection(_selected);
      if (!_isConnected(_selected)) return;
    }

    if (!mounted) return;
    // Step 1 — let the user pick the destination folder on the provider.
    final folder = await Navigator.of(context).push<CloudSelectedFolder?>(
      MaterialPageRoute<CloudSelectedFolder?>(
        builder: (_) => CloudBrowserPage(
          cloudType: cloudKind,
          mode: CloudBrowserMode.selectFolder,
        ),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || folder == null) return;

    // Step 2 — open the create form bound to that cloud folder so the user can
    // set a name/password and finish creating the vault on the provider.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateDatabasePage(
          onAdded: widget.onOpenVault,
          cloudTarget: CloudCreateTarget(
            kind: cloudKind,
            folderId: folder.id,
            folderName: folder.displayPath,
          ),
        ),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _openVault() async {
    if (_selected == _StorageProvider.local) {
      await _pickLocalFile();
    } else {
      await _openCloudBrowserForOpen();
    }
  }

  Future<void> _pickLocalFile() async {
    final registry = ref.read(databaseRegistryProvider.notifier);

    // Default to the same directory used when creating a local database.
    String? initialDirectory;
    try {
      final dir = await getApplicationDocumentsDirectory();
      initialDirectory = dir.path;
    } catch (_) {}

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['kdbx', 'kdb'],
      initialDirectory: initialDirectory,
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;

    final filename = result.files.single.name;
    final nickname = p.basenameWithoutExtension(filename);

    final added = await registry.addDatabase(
      nickname: nickname,
      databasePath: path,
      storageType: 'local',
    );
    widget.onOpenVault(added);
  }

  Future<void> _openCloudBrowserForOpen() async {
    final cloudKind = switch (_selected) {
      _StorageProvider.googleDrive => CloudKind.googleDrive,
      _StorageProvider.dropbox => CloudKind.dropbox,
      _StorageProvider.oneDrive => CloudKind.oneDrive,
      _StorageProvider.webDav => CloudKind.webdav,
      _StorageProvider.sftp => CloudKind.sftp,
      _StorageProvider.s3 => CloudKind.s3,
      _StorageProvider.local => CloudKind.googleDrive,
    };

    if (!_isConnected(_selected)) {
      await _toggleConnection(_selected);
      if (!_isConnected(_selected)) return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CloudBrowserPage(
          cloudType: cloudKind,
          mode: CloudBrowserMode.selectVaultFile,
          onAdded: widget.onOpenVault,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = _isConnected(_selected);
    final configured = _isConfigured(_selected);
    final email = _connectedEmail(_selected);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _pickerCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Quick Access',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: _pickerInk,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                // TODO: Re-enable when cloud services modal is stable.
                // _CloudServicesEntryButton(
                //   onTap: () => showCloudServicesModal(context),
                // ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tabWidth = (constraints.maxWidth - 16) / 3;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _StorageProvider.values.map((prov) {
                    final isActive = prov == _selected;

                    return SizedBox(
                      width: tabWidth,
                      child: _ProviderTab(
                        provider: prov,
                        isActive: isActive,
                        isConfigured: _isConfigured(prov),
                        onTap: () => setState(() => _selected = prov),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          if (_selected != _StorageProvider.local) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ConnectionStatusRow(
                provider: _selected,
                connected: connected,
                configured: configured,
                email: email,
                busy: _busy,
                onToggle: configured
                    ? () => _toggleConnection(_selected)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: KeyedSubtree(
              key: widget.actionsKey,
              child: Row(
                children: [
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.add_rounded,
                      label: 'Create Vault',
                      onTap: (_selected == _StorageProvider.local || connected)
                          ? _createVault
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.folder_open_rounded,
                      label: 'Open Vault',
                      onTap: (_selected == _StorageProvider.local || connected)
                          ? _openVault
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderTab extends StatelessWidget {
  const _ProviderTab({
    required this.provider,
    required this.isActive,
    required this.isConfigured,
    required this.onTap,
  });

  final _StorageProvider provider;
  final bool isActive;
  final bool isConfigured;

  final VoidCallback onTap;

  (String asset, String label) get _providerInfo => switch (provider) {
    _StorageProvider.local => ('assets/images/dir.png', 'Local'),
    _StorageProvider.googleDrive => ('assets/images/google-drive.png', 'Drive'),
    _StorageProvider.dropbox => ('assets/images/dropbox.png', 'Dropbox'),
    _StorageProvider.oneDrive => ('assets/images/onedrive.png', 'OneDrive'),
    _StorageProvider.webDav => ('assets/images/webdav.png', 'WebDAV'),
    _StorageProvider.sftp => ('assets/images/sftp.png', 'SFTP'),
    _StorageProvider.s3 => ('assets/images/aws-s3-icon.png', 'Amazon S3'),
  };

  @override
  Widget build(BuildContext context) {
    final (asset, label) = _providerInfo;
    final dimmed = !isConfigured;
    final opacity = dimmed ? 0.45 : 1.0;

    return Opacity(
      opacity: opacity,
      child: GestureDetector(
        onTap: !isConfigured ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 78,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          decoration: BoxDecoration(
            color: isActive
                ? _pickerInk.withValues(alpha: 0.07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive
                  ? _pickerInk.withValues(alpha: 0.2)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(asset, width: 32, height: 32),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isActive ? _pickerInk : _pickerMuted,
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionStatusRow extends StatelessWidget {
  const _ConnectionStatusRow({
    required this.provider,
    required this.connected,
    required this.configured,
    required this.email,
    required this.busy,
    required this.onToggle,
  });

  final _StorageProvider provider;
  final bool connected;
  final bool configured;
  final String? email;
  final bool busy;
  final VoidCallback? onToggle;

  String get _providerLabel => switch (provider) {
    _StorageProvider.googleDrive => 'Google Drive',
    _StorageProvider.dropbox => 'Dropbox',
    _StorageProvider.oneDrive => 'OneDrive',
    _StorageProvider.webDav => 'WebDAV',
    _StorageProvider.sftp => 'SFTP',
    _StorageProvider.s3 => 'Amazon S3',
    _StorageProvider.local => 'Local',
  };

  @override
  Widget build(BuildContext context) {
    if (!configured) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: Color(0xFFF59E0B),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$_providerLabel is not configured.',
                style: const TextStyle(
                  color: Color(0xFF92400E),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: connected ? const Color(0xFFECFDF5) : const Color(0xFFF4F9FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: connected ? const Color(0xFF6EE7B7) : _pickerCardBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected
                  ? const Color(0xFF10B981)
                  : _pickerMuted.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  connected ? 'Connected' : 'Not connected',
                  style: TextStyle(
                    color: connected ? const Color(0xFF065F46) : _pickerMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (connected && email != null && email!.isNotEmpty)
                  Text(
                    email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF065F46).withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 30,
            child: TextButton(
              onPressed: busy ? null : onToggle,
              style: TextButton.styleFrom(
                backgroundColor: connected ? Colors.white : _pickerInk,
                foregroundColor: connected ? _pickerMuted : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: connected
                      ? BorderSide(color: _pickerCardBorder)
                      : BorderSide.none,
                ),
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: busy
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        valueColor: AlwaysStoppedAnimation(
                          connected ? _pickerMuted : Colors.white,
                        ),
                      ),
                    )
                  : Text(connected ? 'Disconnect' : 'Connect'),
            ),
          ),
        ],
      ),
    );
  }
}

// TODO: Re-enable when cloud services modal is stable.
// class _CloudServicesEntryButton extends StatelessWidget {
//   const _CloudServicesEntryButton({required this.onTap});
//
//   final VoidCallback onTap;
//
//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       onTap: onTap,
//       borderRadius: BorderRadius.circular(9),
//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
//         decoration: BoxDecoration(
//           color: _pickerInk.withValues(alpha: 0.06),
//           borderRadius: BorderRadius.circular(9),
//           border: Border.all(color: _pickerCardBorder),
//         ),
//         child: const Row(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Icon(Icons.cloud_sync_rounded, size: 15, color: _pickerInk),
//             SizedBox(width: 5),
//             Text(
//               'Manage',
//               style: TextStyle(
//                 color: _pickerInk,
//                 fontSize: 12,
//                 fontWeight: FontWeight.w700,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Material(
        color: enabled ? _pickerInk : _pickerInk.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
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

// ── Vault tile ────────────────────────────────────────────────────────────────

class _VaultTile extends StatelessWidget {
  const _VaultTile({
    required this.record,

    this.health,
    this.interactionBlocked = false,
    this.grouped = false,
    this.showDivider = false,
    required this.onTap,
    required this.onDelete,
    required this.onSetDefault,
    required this.onDuplicate,
    required this.onSaveAs,
    this.onShowHealthDetails,
  });

  final DatabaseRecord record;

  final DatabaseConnectionHealth? health;
  final bool interactionBlocked;
  final bool grouped;
  final bool showDivider;
  final VoidCallback? onTap;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;
  final VoidCallback onDuplicate;
  final VoidCallback onSaveAs;
  final VoidCallback? onShowHealthDetails;

  @override
  Widget build(BuildContext context) {
    final radius = grouped ? BorderRadius.zero : BorderRadius.circular(18);
    final isHealthChecking = health != null && health!.isChecking;
    final hasHealthError = health != null && health!.hasError;
    final row = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: InkWell(
                borderRadius: radius,
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    grouped ? 14 : 14,
                    grouped ? 13 : 12,
                    8,
                    grouped ? 13 : 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _DatabaseTypeBadge(
                        storageType: record.storageType,
                        healthBadge: (isHealthChecking || hasHealthError)
                            ? _buildHealthBadge()
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 2,
                              children: [
                                Text(
                                  record.nickname,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: const Color(0xFF0B1F26),
                                        fontWeight: FontWeight.w700,
                                        height: 1.2,
                                      ),
                                ),
                                if (record.isDefaultStartup)
                                  const _DefaultStartupChip(),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _locationLabel(record),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: _pickerMuted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    height: 1.25,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 102,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatVaultCreatedDate(record.addedAt),
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: _pickerMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatVaultCreatedTime(record.addedAt),
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: _pickerMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    height: 1.2,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 10, 8),
              child: _VaultItemMenu(
                isDefault: record.isDefaultStartup,
                onSetDefault: onSetDefault,
                onDuplicate: onDuplicate,
                onSaveAs: onSaveAs,
                onRemove: onDelete,
              ),
            ),
          ],
        ),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(left: 70),
            child: Divider(height: 1, thickness: 1, color: Color(0xFFE8EEF2)),
          ),
      ],
    );

    return Opacity(
      opacity: interactionBlocked ? 0.6 : 1.0,
      child: Dismissible(
        key: ValueKey(record.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444),
            borderRadius: radius,
          ),
          child: const Icon(
            Icons.delete_outline_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        confirmDismiss: (_) async {
          onDelete();
          return false;
        },
        child: grouped
            ? Material(color: Colors.transparent, child: row)
            : Material(
                color: Colors.white,
                borderRadius: radius,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: _pickerCardBorder),
                  ),
                  child: row,
                ),
              ),
      ),
    );
  }

  Widget _buildHealthBadge() {
    final h = health!;
    if (h.isChecking) {
      return Tooltip(
        message: 'Checking vault sync status',
        child: SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: _pickerMuted,
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: onShowHealthDetails,
      child: Tooltip(
        message: 'Sync issue — tap for details',
        child: Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: Color(0xFFDC2626),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.priority_high_rounded,
            size: 10,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _DatabaseTypeBadge extends StatelessWidget {
  const _DatabaseTypeBadge({required this.storageType, this.healthBadge});

  final String storageType;
  final Widget? healthBadge;

  @override
  Widget build(BuildContext context) {
    final (asset, bg) = switch (storageType) {
      'googleDrive' => (
        'assets/images/google-drive.png',
        const Color(0xFFF0F4FF),
      ),
      'dropbox' => ('assets/images/dropbox.png', const Color(0xFFEFF6FF)),
      'oneDrive' => ('assets/images/onedrive.png', const Color(0xFFE8F4FD)),
      'webdav' => ('assets/images/webdav.png', const Color(0xFFEFF3F8)),
      'sftp' => ('assets/images/sftp.png', const Color(0xFFEFF3F8)),
      's3' => ('assets/images/aws-s3-icon.png', const Color(0xFFFFF6E8)),
      _ => ('assets/images/dir.png', const Color(0xFFF3F4F6)),
    };
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Image.asset(asset, width: 22, height: 22),
          ),
          if (healthBadge != null)
            Positioned(right: -4, bottom: -4, child: healthBadge!),
        ],
      ),
    );
  }
}

class _DefaultStartupChip extends StatelessWidget {
  const _DefaultStartupChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _defaultBadgeBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 12, color: _defaultBadgeFg),
          const SizedBox(width: 3),
          Text(
            'Default',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _defaultBadgeFg,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _VaultItemMenu extends StatelessWidget {
  const _VaultItemMenu({
    required this.isDefault,
    required this.onSetDefault,
    required this.onDuplicate,
    required this.onSaveAs,
    required this.onRemove,
  });

  final bool isDefault;
  final VoidCallback onSetDefault;
  final VoidCallback onDuplicate;
  final VoidCallback onSaveAs;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Vault actions',
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      offset: const Offset(0, 40),
      onSelected: (value) {
        switch (value) {
          case 'default':
            onSetDefault();
            break;
          case 'saveAs':
            onSaveAs();
            break;
          case 'duplicate':
            onDuplicate();
            break;
          case 'remove':
            onRemove();
            break;
        }
      },
      itemBuilder: (_) => <PopupMenuEntry<String>>[
        if (!isDefault)
          PopupMenuItem<String>(
            value: 'default',
            child: Row(
              children: [
                Icon(Icons.star_outline_rounded, size: 18, color: _pickerInk),
                const SizedBox(width: 10),
                Text(
                  'Set default',
                  style: TextStyle(
                    color: _pickerInk,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'saveAs',
          child: Row(
            children: [
              Icon(Icons.save_alt_rounded, size: 18, color: _pickerInk),
              const SizedBox(width: 10),
              Text(
                'Save As',
                style: TextStyle(
                  color: _pickerInk,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 18, color: _pickerInk),
              const SizedBox(width: 10),
              Text(
                'Duplicate',
                style: TextStyle(
                  color: _pickerInk,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'remove',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: Color(0xFFEF4444),
              ),
              const SizedBox(width: 10),
              Text(
                'Remove',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _pickerBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _menuBorder),
        ),
        child: const Icon(
          Icons.more_vert_rounded,
          size: 22,
          color: _pickerMuted,
        ),
      ),
    );
  }
}

List<DatabaseRecord> _sortedVaults(List<DatabaseRecord> records) {
  final copy = List<DatabaseRecord>.from(records);
  copy.sort((a, b) {
    if (a.isDefaultStartup != b.isDefaultStartup) {
      return a.isDefaultStartup ? -1 : 1;
    }
    // Sort by last opened (most recent first); never-opened vaults go last.
    final aTime = a.lastOpenedAt;
    final bTime = b.lastOpenedAt;
    if (aTime == null && bTime == null) {
      // Fall through to name tiebreaker.
    } else if (aTime == null) {
      return 1;
    } else if (bTime == null) {
      return -1;
    } else {
      final cmp = bTime.compareTo(aTime);
      if (cmp != 0) return cmp;
    }
    final byName = a.nickname.toLowerCase().compareTo(b.nickname.toLowerCase());
    if (byName != 0) return byName;
    return b.addedAt.compareTo(a.addedAt);
  });
  return copy;
}

bool _recordMatchesSearch(DatabaseRecord record, String q) {
  final terms = <String>[
    record.nickname,
    _storageSearchLabel(record.storageType),
    _visibleFileSearchLabel(record),
  ];

  return terms
      .where((term) => term.trim().isNotEmpty)
      .any((term) => term.toLowerCase().contains(q));
}

String _visibleFileSearchLabel(DatabaseRecord record) {
  final cloudFileName = record.cloudFileName?.trim();
  if (cloudFileName != null && cloudFileName.isNotEmpty) {
    return cloudFileName;
  }

  return p.basename(record.databasePath);
}

String _storageSearchLabel(String storageType) {
  switch (storageType) {
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
      return 'Local';
  }
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

String _shortenPath(String path) {
  const maxLen = 52;
  if (path.length <= maxLen) return path;
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  final shortened = home.isNotEmpty ? path.replaceFirst(home, '~') : path;
  if (shortened.length <= maxLen) return shortened;
  final segs = shortened.split(RegExp(r'[/]'));
  if (segs.length > 3) {
    return '${segs.first}/…/${segs[segs.length - 2]}/${segs.last}';
  }
  return '…${shortened.substring(shortened.length - maxLen + 1)}';
}

String _formatVaultCreatedDate(DateTime value) {
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

String _formatVaultCreatedTime(DateTime value) {
  var hour = value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  final isPm = hour >= 12;
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  final period = isPm ? 'PM' : 'AM';
  return '$h12:$minute $period';
}

// ── Database health dialog ────────────────────────────────────────────────────

enum _DatabaseHealthDialogAction { close, retry, reconnect, unlinkDatabases }

class _DatabaseHealthIssueDialog extends StatelessWidget {
  const _DatabaseHealthIssueDialog({
    required this.record,
    required this.health,
  });

  final DatabaseRecord record;
  final DatabaseConnectionHealth health;

  bool get _canReconnect =>
      isCloudBackedDatabaseRecord(record) &&
      (record.storageType == 'googleDrive' ||
          record.storageType == 'dropbox' ||
          record.storageType == 'oneDrive');

  @override
  Widget build(BuildContext context) {
    final providerLabel =
        health.providerLabel ?? providerLabelForStorageType(record.storageType);

    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFDC2626),
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              health.title ?? 'This vault needs attention',
              style: const TextStyle(
                color: Color(0xFF0B1F26),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${record.nickname}" is linked to $providerLabel.',
              style: const TextStyle(
                color: Color(0xFF0B1F26),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              health.details ?? 'The vault cannot confirm sync health.',
              style: const TextStyle(
                color: Color(0xFF6B858D),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (health.recommendedActions.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Recommended actions',
                style: TextStyle(
                  color: Color(0xFF0B1F26),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (final action in health.recommendedActions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Icon(
                          Icons.circle,
                          size: 5,
                          color: Color(0xFF0A3B48),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          action,
                          style: const TextStyle(
                            color: Color(0xFF6B858D),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 12,
        top: 4,
      ),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_canReconnect)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0A3B48),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.of(
                  context,
                ).pop(_DatabaseHealthDialogAction.reconnect),
                child: Text(
                  'Reconnect $providerLabel',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(_DatabaseHealthDialogAction.close),
                  child: const Text(
                    'Close',
                    style: TextStyle(color: Color(0xFF6B858D)),
                  ),
                ),
                if (_canReconnect)
                  TextButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(_DatabaseHealthDialogAction.unlinkDatabases),
                    child: const Text(
                      'Unlink',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(_DatabaseHealthDialogAction.retry),
                  child: const Text(
                    'Check again',
                    style: TextStyle(
                      color: Color(0xFF0A3B48),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
