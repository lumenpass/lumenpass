import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../../../core/repository/providers.dart';
import '../../../core/repository/vault_write_scheduler_provider.dart';
import '../../../core/services/vault_auto_sync_controller.dart';
import '../../home/application/home_vault_providers.dart';
import 'vault_entries_providers.dart';

enum VaultItemsSortField { title, lastEdited }

enum VaultItemsSortDirection { ascending, descending }

final vaultItemsSortFieldProvider = StateProvider<VaultItemsSortField>(
  (ref) => VaultItemsSortField.lastEdited,
);

final vaultItemsSortDirectionProvider = StateProvider<VaultItemsSortDirection>(
  (ref) => VaultItemsSortDirection.descending,
);

final vaultItemsSelectedEntryUuidProvider = StateProvider<String?>(
  (ref) => null,
);

final vaultItemsIsRefreshingProvider = StateProvider<bool>((ref) => false);

final vaultItemsIsDeletingProvider = StateProvider<bool>((ref) => false);

final vaultItemsSortedEntriesProvider = Provider<List<KdbxEntry>>((ref) {
  final entries = List<KdbxEntry>.from(
    ref.watch(vaultSearchFilteredEntriesProvider),
  );
  final field = ref.watch(vaultItemsSortFieldProvider);
  final dir = ref.watch(vaultItemsSortDirectionProvider);

  int compareByLastEdited(KdbxEntry a, KdbxEntry b) {
    // Ascending order: Last Used (primary), then Last Updated (secondary).
    // The outer sort negates this for the default `descending` direction, so
    // the list shows most-recently-used first.
    final byUsed = effectiveLastUsedAt(a).compareTo(effectiveLastUsedAt(b));
    if (byUsed != 0) {
      return byUsed;
    }
    final byUpdated = effectiveLastUpdatedAt(
      a,
    ).compareTo(effectiveLastUpdatedAt(b));
    if (byUpdated != 0) {
      return byUpdated;
    }
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  entries.sort((a, b) {
    final result = switch (field) {
      VaultItemsSortField.title => a.title.toLowerCase().compareTo(
        b.title.toLowerCase(),
      ),
      VaultItemsSortField.lastEdited => compareByLastEdited(a, b),
    };

    final withTieBreaker = result == 0 && field == VaultItemsSortField.title
        ? compareByLastEdited(a, b)
        : result;

    final signed = dir == VaultItemsSortDirection.ascending
        ? withTieBreaker
        : -withTieBreaker;
    return signed;
  });

  return entries;
});

/// Minimum time the refreshing flag stays `true` so the UI spinner is
/// visible even when the underlying invalidation is near-instant.
const _kMinRefreshVisibleDuration = Duration(milliseconds: 650);

/// Publishes the already-mutated in-memory database to the UI immediately
/// and schedules persistence in the background via [VaultWriteScheduler].
///
/// Use after any repository mutation (create/update/delete/touch). The UI
/// reflects the change instantly; the expensive encrypt-and-write runs off
/// the interaction path. Set [immediate] to `false` for low-priority writes
/// (last-used timestamps, favicon caching) so they coalesce into one save.
KdbxDatabase publishAndScheduleSave(
  WidgetRef ref,
  KdbxRepository repository, {
  bool immediate = true,
}) {
  final database = repository.currentDatabase;
  if (database == null) {
    throw const VaultStateException('No open vault to publish.');
  }
  publishVaultSnapshot(ref, database);
  final scheduler = ref.read(vaultWriteSchedulerProvider);
  if (immediate) {
    scheduler.markDirtyImmediate();
  } else {
    scheduler.markDirtyDebounced();
  }
  return database;
}

void publishVaultSnapshot(WidgetRef ref, KdbxDatabase database) {
  ref.read(activeDatabaseProvider.notifier).state = database;
  for (final p in _vaultDerivedProviders) {
    ref.invalidate(p);
  }
}

/// Same fan-out as [publishVaultSnapshot] but for callers that only have a
/// Riverpod [Ref] (e.g. a [StateNotifier] holding `Ref _ref`). Republishes
/// `activeDatabaseProvider` and invalidates every derived entries provider
/// so the home screen and items list rebuild with the freshly mutated data.
void publishVaultSnapshotFromRef(Ref ref, KdbxDatabase database) {
  ref.read(activeDatabaseProvider.notifier).state = database;
  for (final p in _vaultDerivedProviders) {
    ref.invalidate(p);
  }
}

/// Every provider that depends on the active database snapshot. Centralised
/// so the two `publishVaultSnapshot*` entry points stay in sync.
final List<ProviderOrFamily> _vaultDerivedProviders = <ProviderOrFamily>[
  vaultVisibleEntriesProvider,
  vaultCategoryScopedEntriesProvider,
  vaultTypeScopedEntriesProvider,
  vaultSearchFilteredEntriesProvider,
  vaultItemsSortedEntriesProvider,
  vaultAllTagsProvider,
  vaultSidebarCategoriesProvider,
  vaultItemTypeCountsProvider,
  homeRecentEntriesProvider,
  homeRecentCreatedEntriesProvider,
  homeQuickAccessCountsProvider,
  homePopularTagsProvider,
];

Future<void> refreshVaultSnapshot(
  WidgetRef ref, {
  Duration reloadDelay = Duration.zero,
}) async {
  if (ref.read(vaultItemsIsRefreshingProvider)) {
    return;
  }
  ref.read(vaultItemsIsRefreshingProvider.notifier).state = true;
  final started = DateTime.now();
  try {
    if (reloadDelay > Duration.zero) {
      await Future<void>.delayed(reloadDelay);
    }
    await ref.read(vaultAutoSyncControllerProvider.notifier).sync();
    final repo = ref.read(kdbxRepositoryProvider);
    final database = repo.currentDatabase;
    if (database != null) {
      publishVaultSnapshot(ref, database);
    }
  } finally {
    final elapsed = DateTime.now().difference(started);
    final remaining = _kMinRefreshVisibleDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    ref.read(vaultItemsIsRefreshingProvider.notifier).state = false;
  }
}
