import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/repository/kdbx_repository.dart';
import '../../../core/repository/kdbx_repository_provider.dart';
import '../../../core/repository/vault_write_scheduler_provider.dart';
import '../../vault/application/vault_providers.dart';
import '../application/import_executor.dart';
import '../application/import_state.dart';
import '../domain/import_parsed_item.dart';
import '../infrastructure/import_parser_service.dart';
import 'clear_progress_modal.dart';
import 'import_provider_modal.dart';
import 'import_preview_screen.dart';
import 'import_confirmation_modal.dart';
import 'import_progress_modal.dart';

class ImportFlowOrchestrator {
  const ImportFlowOrchestrator();

  void startFlow(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(importStateProvider.notifier);
    notifier.reset();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _ImportFlowDialog(
          onFlowComplete: () {
            Navigator.of(dialogContext).pop();
            _refreshVault(ref);
          },
        );
      },
    );
  }

  void _refreshVault(WidgetRef ref) {
    // Refresh the cached snapshot from the still-open repository. Do NOT
    // invalidate the repository provider — that disposes the open file and
    // resets the active vault to null. Re-read the live database, recompute
    // the entry list, and nudge the vault screen to rebuild from it.
    final repository = ref.read(kdbxRepositoryProvider);
    ref.read(activeDatabaseProvider.notifier).state =
        repository.currentDatabase;
    ref.invalidate(vaultEntriesProvider);
    ref.read(vaultRefreshTriggerProvider.notifier).state++;
  }
}

class _ImportFlowDialog extends ConsumerStatefulWidget {
  const _ImportFlowDialog({required this.onFlowComplete});

  final VoidCallback onFlowComplete;

  @override
  ConsumerState<_ImportFlowDialog> createState() => _ImportFlowDialogState();
}

class _ImportFlowDialogState extends ConsumerState<_ImportFlowDialog> {
  StreamSubscription<ImportProgress>? _importSubscription;
  StreamSubscription<ImportProgress>? _clearSubscription;
  Future<void>? _completedFinalizeFuture;

  @override
  void dispose() {
    _importSubscription?.cancel();
    _clearSubscription?.cancel();
    super.dispose();
  }

  Future<void> _parseAndPreview() async {
    final importState = ref.read(importStateProvider);

    if (importState.filePath == null) return;

    final notifier = ref.read(importStateProvider.notifier);
    notifier.startParsing();

    try {
      final service = const ImportParserService();
      final items = await service.parseFile(
        importState.filePath!,
        provider: importState.selectedProvider?.type,
      );

      for (final item in items) {
        item.validate();
      }

      if (!mounted) return;
      notifier.setParsedItems(items);
    } catch (error) {
      if (!mounted) return;
      final message =
          error is FormatException ? error.message : error.toString();
      // Surface the error inline within the provider modal (the modal stays on
      // the provider-selection step). A SnackBar here renders behind the
      // dialog and gets hidden.
      notifier.setParseError(message);
    }
  }

  Future<void> _startImport() async {
    final importState = ref.read(importStateProvider);
    final readyItems = importState.parsedItems
        .where((item) => item.isReady)
        .toList(growable: false);

    if (readyItems.isEmpty) return;

    _completedFinalizeFuture = null;

    final repository = ref.read(kdbxRepositoryProvider);
    final rootGroupUuid = repository.rootGroupUuid;
    if (rootGroupUuid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No database open. Please open a vault first.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
      return;
    }

    // Import into the category the user chose in the preview. Falls back to
    // the root group (Uncategorized) when no category was selected.
    final targetGroupUuid = importState.targetGroupUuid ?? rootGroupUuid;

    if (importState.importMode == ImportMode.replace) {
      _startClearing(repository, readyItems, targetGroupUuid);
    } else {
      _startImportItems(repository, readyItems, targetGroupUuid);
    }
  }

  void _startClearing(
    KdbxRepository repository,
    List<ImportParsedItem> readyItems,
    String rootGroupUuid,
  ) {
    ref.read(importStateProvider.notifier).goToClearing();

    final executor = ImportExecutor(repository: repository);
    _clearSubscription?.cancel();
    _clearSubscription = executor.clearAllEntries().listen(
      (progress) {
        if (!mounted) return;
        setState(() {
          _clearProgress = progress;
        });

        if (progress.status == ImportProgressStatus.completed) {
          // Vault is clean — save and proceed to the import phase.
          _saveThenImport(repository, readyItems, rootGroupUuid);
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _clearProgress = ImportProgress(
            status: ImportProgressStatus.failed,
            current: _clearProgress.current,
            total: _clearProgress.total,
            succeeded: _clearProgress.succeeded,
            failed: _clearProgress.failed,
            errorMessage: error.toString(),
            logs: _clearProgress.logs,
          );
        });
      },
    );
  }

  Future<void> _saveThenImport(
    KdbxRepository repository,
    List<ImportParsedItem> readyItems,
    String rootGroupUuid,
  ) async {
    try {
      publishAndScheduleSave(ref, repository);
      await ref.read(vaultWriteSchedulerProvider).flushNow();
    } catch (_) {
      // Save best-effort; proceed to import regardless.
    }
    if (!mounted) return;
    _startImportItems(repository, readyItems, rootGroupUuid);
  }

  void _startImportItems(
    KdbxRepository repository,
    List<ImportParsedItem> readyItems,
    String rootGroupUuid,
  ) {
    ref.read(importStateProvider.notifier).goToProgress();

    final executor = ImportExecutor(repository: repository);
    _importSubscription = executor
        .execute(
      items: readyItems,
      mode: ref.read(importStateProvider).importMode,
      rootGroupUuid: rootGroupUuid,
    )
        .listen(
      (progress) {
        if (!mounted) return;
        setState(() {
          _currentProgress = progress;
        });
        if (progress.status == ImportProgressStatus.completed &&
            _completedFinalizeFuture == null) {
          _completedFinalizeFuture = _finalizeCompletedImport();
        }
      },
      onError: (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $error'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      },
    );
  }

  Future<void> _finalizeCompletedImport() async {
    try {
      final repository = ref.read(kdbxRepositoryProvider);
      publishAndScheduleSave(ref, repository);
      await ref.read(vaultWriteSchedulerProvider).flushNow();
      ref.read(vaultSelectedGroupProvider.notifier).state = kCategoryFilterAll;
      ref.read(vaultSelectedItemTypeIdProvider.notifier).state = null;
      ref.read(vaultSelectedTagProvider.notifier).state = null;
      ref.invalidate(vaultEntriesProvider);
      ref.read(vaultRefreshTriggerProvider.notifier).state++;
    } catch (_) {
      // Keep success modal open even if background refresh/save hits an error.
    }
  }

  /// Cached ready items and root group UUID needed to retry the clear + import
  /// flow when the user taps "Retry" on a failed clearing modal.
  List<ImportParsedItem>? _pendingReadyItems;
  String? _pendingRootGroupUuid;

  ImportProgress _currentProgress = ImportProgress.idle;
  ImportProgress _clearProgress = ImportProgress.idle;

  @override
  Widget build(BuildContext context) {
    final importState = ref.watch(importStateProvider);

    switch (importState.step) {
      case ImportStep.providerSelection:
        return ImportProviderModal(
          onClose: widget.onFlowComplete,
          onNext: _parseAndPreview,
        );
      case ImportStep.preview:
        return ImportPreviewScreen(
          onClose: widget.onFlowComplete,
          onStartImport: () {
            ref.read(importStateProvider.notifier).goToConfirmation();
          },
        );
      case ImportStep.confirmation:
        return ImportConfirmationModal(
          onCancel: () {
            ref.read(importStateProvider.notifier).goBackToPreview();
          },
          onConfirm: () {
            // Cache these for retry scenarios.
            final readyItems = importState.parsedItems
                .where((item) => item.isReady)
                .toList(growable: false);
            _pendingReadyItems = readyItems;
            final repository = ref.read(kdbxRepositoryProvider);
            _pendingRootGroupUuid =
                importState.targetGroupUuid ?? repository.rootGroupUuid;
            _startImport();
          },
        );
      case ImportStep.clearing:
        return ClearProgressModal(
          progress: _clearProgress,
          onRetry: () {
            final repository = ref.read(kdbxRepositoryProvider);
            final items = _pendingReadyItems;
            final rootUuid = _pendingRootGroupUuid;
            if (items != null && rootUuid != null) {
              setState(() {
                _clearProgress = ImportProgress.idle;
              });
              _startClearing(repository, items, rootUuid);
            }
          },
          onCancel: widget.onFlowComplete,
        );
      case ImportStep.progress:
        return ImportProgressModal(
          progress: _currentProgress,
          onDone: () async {
            await _completedFinalizeFuture;
            widget.onFlowComplete();
          },
          onCancelRequested: () async {
            // Stop the stream. The in-flight createEntry finishes, then the
            // generator terminates at its next yield.
            await _importSubscription?.cancel();
            // Persist whatever was imported before cancellation so the
            // partial work isn't lost — essential in Replace mode where the
            // existing data was already cleared — and sync to cloud if the
            // vault is cloud-backed.
            try {
              final repository = ref.read(kdbxRepositoryProvider);
              publishAndScheduleSave(ref, repository);
              await ref.read(vaultWriteSchedulerProvider).flushNow();
            } catch (_) {
              // Closing regardless; the list refresh reads live in-memory state.
            }
            widget.onFlowComplete();
          },
        );
    }
  }
}
