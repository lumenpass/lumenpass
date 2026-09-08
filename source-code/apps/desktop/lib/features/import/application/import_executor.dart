import 'dart:async';

import '../domain/import_parsed_item.dart';
import '../../../core/repository/kdbx_repository.dart';

enum ImportMode { append, replace }

enum ImportProgressStatus { idle, running, completed, cancelled, failed }

/// A single line in the live import log shown under the progress bar.
class ImportLogEntry {
  const ImportLogEntry(this.message, {this.isError = false});

  final String message;
  final bool isError;
}

class ImportProgress {
  const ImportProgress({
    required this.status,
    required this.current,
    required this.total,
    this.succeeded = 0,
    this.failed = 0,
    this.errorMessage,
    this.currentLog,
    this.logs = const <ImportLogEntry>[],
  });

  final ImportProgressStatus status;
  final int current;
  final int total;
  final int succeeded;
  final int failed;
  final String? errorMessage;
  final String? currentLog;
  final List<ImportLogEntry> logs;

  double get fraction => total > 0 ? current / total : 0;
  int get percent => total > 0 ? (fraction * 100).round() : 0;

  static const ImportProgress idle = ImportProgress(
    status: ImportProgressStatus.idle,
    current: 0,
    total: 0,
  );
}

class ImportExecutor {
  ImportExecutor({required this.repository});

  final KdbxRepository repository;

  /// Permanently removes every entry from the vault, emitting a progress
  /// stream so a "Cleaning old items" modal can mirror the import progress
  /// UX. Used by Replace mode before [execute].
  ///
  /// The clear runs in repeated passes over the live database so that any
  /// entries the kdbx layer relocates (e.g. into the recycle bin) on the
  /// first delete are picked up and permanently removed on the next pass.
  /// The stream finishes with [ImportProgressStatus.completed] only when the
  /// database has zero remaining entries.
  Stream<ImportProgress> clearAllEntries() async* {
    final logs = <ImportLogEntry>[
      const ImportLogEntry('Counting existing items...'),
    ];

    // Initial count drives the progress bar. We don't know yet how many
    // recycle-bin sweeps will be needed, but the visible-entry count is what
    // the user can see in the vault list, so it's the most honest total.
    final initialEntries = await repository.searchEntries();
    final total = initialEntries.length;

    yield ImportProgress(
      status: ImportProgressStatus.running,
      current: 0,
      total: total,
      currentLog: total == 0
          ? 'Vault is already empty.'
          : 'Preparing to remove $total items...',
      logs: List<ImportLogEntry>.unmodifiable(logs),
    );

    // Give the UI a frame to render the modal before we start deleting.
    await Future<void>.delayed(const Duration(milliseconds: 16));

    if (total == 0) {
      logs.add(const ImportLogEntry('Nothing to clean.'));
      yield ImportProgress(
        status: ImportProgressStatus.completed,
        current: 0,
        total: 0,
        succeeded: 0,
        failed: 0,
        logs: List<ImportLogEntry>.unmodifiable(logs),
      );
      return;
    }

    var deleted = 0;
    var failed = 0;
    final emitEvery = total <= 120 ? 1 : (total / 120).ceil();

    // Repeated passes guarantee we drain the live database, including any
    // entries the kdbx library moved into the recycle bin instead of
    // permanently deleting on the first call. We cap the pass count so a
    // pathological repository can't loop forever.
    const maxPasses = 5;
    for (var pass = 0; pass < maxPasses; pass++) {
      final remaining = await repository.searchEntries();
      if (remaining.isEmpty) break;

      for (final entry in remaining) {
        final title = entry.title.isNotEmpty ? entry.title : 'Untitled';
        try {
          await repository.permanentlyDeleteEntry(entry.uuid);
          deleted++;
          logs.add(ImportLogEntry('Removed: $title'));
        } catch (error) {
          failed++;
          logs.add(ImportLogEntry('Failed: $title — $error', isError: true));
        }

        final cappedCurrent = deleted > total ? total : deleted;
        if (cappedCurrent == total || deleted % emitEvery == 0) {
          yield ImportProgress(
            status: ImportProgressStatus.running,
            current: cappedCurrent,
            total: total,
            succeeded: deleted,
            failed: failed,
            currentLog: logs.last.message,
            logs: List<ImportLogEntry>.unmodifiable(logs),
          );
          await Future<void>.delayed(Duration.zero);
        }
      }
    }

    // Final verification: the vault must be empty before we hand off to the
    // import phase, otherwise the user will end up with the duplicates the
    // Replace mode is meant to prevent.
    final leftover = await repository.searchEntries();
    if (leftover.isNotEmpty) {
      logs.add(ImportLogEntry(
        '${leftover.length} item(s) could not be removed.',
        isError: true,
      ));
      yield ImportProgress(
        status: ImportProgressStatus.failed,
        current: deleted,
        total: total,
        succeeded: deleted,
        failed: failed + leftover.length,
        errorMessage:
            '${leftover.length} item(s) remained after clearing the vault.',
        logs: List<ImportLogEntry>.unmodifiable(logs),
      );
      return;
    }

    logs.add(ImportLogEntry(
      'Cleanup finished: $deleted item(s) permanently removed'
      '${failed > 0 ? ', $failed failed' : ''}.',
    ));

    yield ImportProgress(
      status: ImportProgressStatus.completed,
      current: total,
      total: total,
      succeeded: deleted,
      failed: failed,
      logs: List<ImportLogEntry>.unmodifiable(logs),
    );
  }

  Stream<ImportProgress> execute({
    required List<ImportParsedItem> items,
    required ImportMode mode,
    required String rootGroupUuid,
  }) async* {
    final logs = <ImportLogEntry>[
      const ImportLogEntry('Preparing import...'),
    ];
    final total = items.length;

    yield ImportProgress(
      status: ImportProgressStatus.running,
      current: 0,
      total: total,
      currentLog: 'Preparing import...',
      logs: List<ImportLogEntry>.unmodifiable(logs),
    );

    // Entry creation is an in-memory (synchronous) operation, so without
    // handing control back to the event loop the whole loop would drain in a
    // single turn and the UI would jump straight to "completed". Yield to the
    // event loop here so the progress dialog paints before work starts, then
    // again on every emit below so the bar animates as items are processed.
    await Future<void>.delayed(const Duration(milliseconds: 16));

    var succeeded = 0;
    var failed = 0;

    // Cap the number of UI updates so we don't rebuild on all 2000+ items,
    // while still emitting enough frames for a smooth progress animation.
    final emitEvery = total <= 120 ? 1 : (total / 120).ceil();

    for (var i = 0; i < total; i++) {
      final item = items[i];
      final title = item.title.isNotEmpty ? item.title : 'Untitled';

      try {
        final entryFields = item.toEntryFields();
        await repository.createEntry(
          groupUuid: rootGroupUuid,
          fields: entryFields,
          notes: item.notes,
          tags: item.tags,
        );

        succeeded++;
        logs.add(ImportLogEntry('Imported: $title'));
      } catch (error) {
        failed++;
        logs.add(ImportLogEntry('Failed: $title — $error', isError: true));
      }

      final isLast = i == total - 1;
      if (isLast || (i + 1) % emitEvery == 0) {
        yield ImportProgress(
          status: ImportProgressStatus.running,
          current: i + 1,
          total: total,
          succeeded: succeeded,
          failed: failed,
          currentLog: logs.last.message,
          logs: List<ImportLogEntry>.unmodifiable(logs),
        );
        // Return control to the event loop so Flutter can render this frame.
        await Future<void>.delayed(Duration.zero);
      }
    }

    logs.add(ImportLogEntry(
      'Import finished: $succeeded imported, $failed failed.',
    ));

    yield ImportProgress(
      status: ImportProgressStatus.completed,
      current: total,
      total: total,
      succeeded: succeeded,
      failed: failed,
      logs: List<ImportLogEntry>.unmodifiable(logs),
    );
  }
}
