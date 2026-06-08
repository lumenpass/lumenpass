import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../../../core/repository/providers.dart';
import '../../../core/services/vault_auto_sync_controller.dart';
import '../../home/application/home_vault_providers.dart';
import 'vault_entries_providers.dart';

enum VaultItemsSortField { title, lastEdited }

enum VaultItemsSortDirection { ascending, descending }

final vaultItemsSortFieldProvider =
    StateProvider<VaultItemsSortField>((ref) => VaultItemsSortField.lastEdited);

final vaultItemsSortDirectionProvider =
    StateProvider<VaultItemsSortDirection>(
  (ref) => VaultItemsSortDirection.descending,
);

final vaultItemsSelectedEntryUuidProvider = StateProvider<String?>((ref) => null);

final vaultItemsIsRefreshingProvider = StateProvider<bool>((ref) => false);

final vaultItemsIsDeletingProvider = StateProvider<bool>((ref) => false);

final vaultItemsSortedEntriesProvider = Provider<List<KdbxEntry>>((ref) {
  final entries =
      List<KdbxEntry>.from(ref.watch(vaultSearchFilteredEntriesProvider));
  final field = ref.watch(vaultItemsSortFieldProvider);
  final dir = ref.watch(vaultItemsSortDirectionProvider);

  int compareByLastEdited(KdbxEntry a, KdbxEntry b) {
    final ta = latestEntryTimestamp(a.updatedAt, a.createdAt) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final tb = latestEntryTimestamp(b.updatedAt, b.createdAt) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final c = ta.compareTo(tb);
    if (c != 0) {
      return c;
    }
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  entries.sort((a, b) {
    final result = switch (field) {
      VaultItemsSortField.title =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      VaultItemsSortField.lastEdited => compareByLastEdited(a, b),
    };

    final withTieBreaker =
        result == 0 && field == VaultItemsSortField.title
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
    ref.read(activeDatabaseProvider.notifier).state = repo.currentDatabase;
    ref.invalidate(vaultVisibleEntriesProvider);
    ref.invalidate(homeRecentEntriesProvider);
  } finally {
    final elapsed = DateTime.now().difference(started);
    final remaining = _kMinRefreshVisibleDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    ref.read(vaultItemsIsRefreshingProvider.notifier).state = false;
  }
}
