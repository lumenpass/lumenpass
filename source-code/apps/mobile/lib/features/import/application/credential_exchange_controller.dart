import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/repository/providers.dart';
import '../../../core/repository/vault_write_scheduler_provider.dart';
import '../../vault/application/vault_items_list_providers.dart';
import '../domain/import_parsed_item.dart';
import '../infrastructure/cxf_parser.dart';
import 'credential_exchange_bridge.dart';

enum CxpImportStatus {
  idle,
  received,
  lockedNoVault,
  executing,
  completed,
  failed,
}

class CxpImportState {
  const CxpImportState({
    this.status = CxpImportStatus.idle,
    this.exporterName,
    this.items = const [],
    this.selectedIndexes = const <int>{},
    this.current = 0,
    this.total = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.errorMessage,
    this.payloadVersion = 0,
  });

  final CxpImportStatus status;
  final String? exporterName;
  final List<ImportParsedItem> items;

  /// Indexes into [items] that the user has chosen to import.
  /// All items are selected by default when a payload arrives.
  final Set<int> selectedIndexes;

  final int current;
  final int total;
  final int succeeded;
  final int failed;
  final String? errorMessage;

  /// Monotonically increasing counter incremented every time a new CXP
  /// payload arrives. Lets UI listeners detect a fresh payload even when
  /// the status field has the same value as before (e.g. a second
  /// `received` after the first was dismissed without `dismiss()`).
  final int payloadVersion;

  double get fraction => total > 0 ? current / total : 0;
  int get selectedCount => selectedIndexes.length;

  CxpImportState copyWith({
    CxpImportStatus? status,
    String? exporterName,
    List<ImportParsedItem>? items,
    Set<int>? selectedIndexes,
    int? current,
    int? total,
    int? succeeded,
    int? failed,
    String? errorMessage,
    int? payloadVersion,
  }) {
    return CxpImportState(
      status: status ?? this.status,
      exporterName: exporterName ?? this.exporterName,
      items: items ?? this.items,
      selectedIndexes: selectedIndexes ?? this.selectedIndexes,
      current: current ?? this.current,
      total: total ?? this.total,
      succeeded: succeeded ?? this.succeeded,
      failed: failed ?? this.failed,
      errorMessage: errorMessage ?? this.errorMessage,
      payloadVersion: payloadVersion ?? this.payloadVersion,
    );
  }
}

class CxpImportController extends StateNotifier<CxpImportState> {
  CxpImportController(this._ref) : super(const CxpImportState()) {
    _subscription = CredentialExchangeBridge.instance.onImport.listen(
      _onPayloadReceived,
    );
    // Tell the bridge we have a listener now — it will flush any payloads
    // that arrived (and were buffered) before the controller existed.
    CredentialExchangeBridge.instance.markListenerReady();
  }

  final Ref _ref;
  StreamSubscription<String>? _subscription;
  static const _parser = CxfParser();
  int _payloadCounter = 0;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onPayloadReceived(String jsonPayload) {
    // ignore: avoid_print
    print('[CXP-Dart] _onPayloadReceived: ${jsonPayload.length} chars');
    try {
      final result = _parser.parse(jsonPayload);
      // ignore: avoid_print
      print(
        '[CXP-Dart] parsed ${result.items.length} items, '
        'exporter=${result.exporterName}',
      );
      if (result.items.isEmpty) {
        developer.log(
          'CXP: payload contained no importable items',
          name: 'cxp_import',
        );
        return;
      }

      // Check whether a vault is unlocked and ready.
      final repository = _ref.read(kdbxRepositoryProvider);
      final isVaultOpen = repository.hasOpenDatabase;

      _payloadCounter++;
      developer.log(
        'CXP: dispatching payload #$_payloadCounter '
        '(${result.items.length} items, vaultOpen=$isVaultOpen)',
        name: 'cxp_import',
      );

      state = CxpImportState(
        status: isVaultOpen
            ? CxpImportStatus.received
            : CxpImportStatus.lockedNoVault,
        exporterName: result.exporterName,
        items: result.items,
        selectedIndexes: <int>{
          for (var i = 0; i < result.items.length; i++) i,
        },
        total: result.items.length,
        payloadVersion: _payloadCounter,
      );
    } catch (e) {
      developer.log('CXP: parse error: $e', name: 'cxp_import');
      _payloadCounter++;
      state = CxpImportState(
        status: CxpImportStatus.failed,
        errorMessage: 'Failed to parse credentials: $e',
        payloadVersion: _payloadCounter,
      );
    }
  }

  /// Re-check vault state and promote from [lockedNoVault] → [received]
  /// if the vault has since been unlocked. Bumps [payloadVersion] so the
  /// UI listener re-fires and presents the preview sheet.
  void retryAfterUnlock() {
    if (state.status != CxpImportStatus.lockedNoVault) return;
    final repository = _ref.read(kdbxRepositoryProvider);
    if (repository.hasOpenDatabase) {
      _payloadCounter++;
      state = state.copyWith(
        status: CxpImportStatus.received,
        payloadVersion: _payloadCounter,
      );
    }
  }

  /// Flip the selection state of a single item by index.
  void toggleItem(int index) {
    if (index < 0 || index >= state.items.length) return;
    final next = Set<int>.from(state.selectedIndexes);
    if (next.contains(index)) {
      next.remove(index);
    } else {
      next.add(index);
    }
    state = state.copyWith(selectedIndexes: next);
  }

  /// Select every parsed item.
  void selectAll() {
    state = state.copyWith(
      selectedIndexes: <int>{
        for (var i = 0; i < state.items.length; i++) i,
      },
    );
  }

  /// Clear the selection.
  void deselectAll() {
    state = state.copyWith(selectedIndexes: const <int>{});
  }

  Future<void> executeImport() async {
    if (state.status != CxpImportStatus.received) return;
    if (state.selectedIndexes.isEmpty) return;

    final repository = _ref.read(kdbxRepositoryProvider);
    if (!repository.hasOpenDatabase) {
      state = state.copyWith(
        status: CxpImportStatus.failed,
        errorMessage: 'No vault is open. Unlock your vault first.',
      );
      return;
    }

    final rootGroupUuid = repository.rootGroupUuid;
    if (rootGroupUuid == null) {
      state = state.copyWith(
        status: CxpImportStatus.failed,
        errorMessage: 'Could not determine vault root group.',
      );
      return;
    }

    // Filter to the user's selection while preserving insertion order.
    final selectedIndexesSorted = state.selectedIndexes.toList()..sort();
    final items = [
      for (final idx in selectedIndexesSorted) state.items[idx],
    ];

    state = state.copyWith(
      status: CxpImportStatus.executing,
      current: 0,
      total: items.length,
      succeeded: 0,
      failed: 0,
    );

    var succeeded = 0;
    var failed = 0;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      try {
        final entryFields = item.toEntryFields();
        await repository.createEntry(
          groupUuid: rootGroupUuid,
          fields: entryFields,
          notes: item.notes,
          tags: item.tags,
        );
        succeeded++;
      } catch (e) {
        failed++;
        developer.log(
          'CXP: failed to import "${item.title}": $e',
          name: 'cxp_import',
        );
      }

      state = state.copyWith(
        current: i + 1,
        succeeded: succeeded,
        failed: failed,
      );

      // Yield to the event loop for UI updates.
      if ((i + 1) % 10 == 0 || i == items.length - 1) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    // Publish the snapshot immediately so the home screen and items list show
    // the imported entries, then flush the background writer so persistence
    // is guaranteed before the import reports completion.
    try {
      final database = repository.currentDatabase;
      if (database != null) {
        publishVaultSnapshotFromRef(_ref, database);
      }
      final scheduler = _ref.read(vaultWriteSchedulerProvider);
      scheduler.markDirtyImmediate();
      await scheduler.flushNow();
    } catch (e) {
      developer.log('CXP: save failed: $e', name: 'cxp_import');
    }

    state = state.copyWith(
      status: CxpImportStatus.completed,
      current: items.length,
      succeeded: succeeded,
      failed: failed,
    );
  }

  void dismiss() {
    state = const CxpImportState();
  }
}

final cxpImportControllerProvider =
    StateNotifierProvider<CxpImportController, CxpImportState>(
  (ref) => CxpImportController(ref),
);
