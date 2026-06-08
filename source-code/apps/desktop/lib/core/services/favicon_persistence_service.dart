import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:lumenpass_core/lumenpass_core.dart';

import '../repository/database_save_sync.dart';
import '../repository/kdbx_repository_provider.dart';
import '../../features/unlock/application/database_registry.dart';

/// Fetches website favicons on demand, stores the PNG bytes in a hidden
/// custom field on the owning entry, and coalesces the resulting
/// database saves.
///
/// The `_FaviconTile` widget calls [enqueue] after a successful
/// `Image.network` load (or on a definitive failure) to persist the
/// outcome. Results are written as:
///   * a base64-encoded PNG payload for successful fetches, or
///   * [AppKdbxFieldKeys.faviconFailedSentinel] for failures, so future
///     renders skip the network entirely.
///
/// Saves are debounced across the entry set so a wave of favicon loads
/// after vault unlock coalesces into a single save + cloud sync round
/// rather than one per entry.
class FaviconPersistenceService {
  FaviconPersistenceService({
    required this.ref,
    this.saveDebounce = const Duration(milliseconds: 750),
    this.fetchTimeout = const Duration(seconds: 6),
    this.maxBytes = 32 * 1024,
  });

  final Ref ref;
  final Duration saveDebounce;
  final Duration fetchTimeout;

  /// Favicons larger than this are considered too big to embed and are
  /// marked as failed to avoid bloating the encrypted database.
  final int maxBytes;

  final Set<String> _inFlight = <String>{};
  Timer? _saveTimer;
  bool _dirty = false;

  /// Request that the favicon bytes for [faviconUrl] be downloaded and
  /// persisted onto the entry identified by [entryUuid].
  ///
  /// Safe to call repeatedly; duplicate requests for an entry currently
  /// being processed are ignored.
  void enqueue({
    required String entryUuid,
    required String faviconUrl,
  }) {
    if (entryUuid.isEmpty || faviconUrl.isEmpty) return;
    if (!_inFlight.add(entryUuid)) return;
    unawaited(_process(entryUuid: entryUuid, faviconUrl: faviconUrl));
  }

  /// Record that the favicon URL for [entryUuid] definitively does not
  /// exist / cannot be loaded, so we never try again for this entry.
  void recordFailure({required String entryUuid}) {
    if (entryUuid.isEmpty) return;
    if (!_inFlight.add(entryUuid)) return;
    unawaited(
      _writeToEntry(
        entryUuid: entryUuid,
        payload: AppKdbxFieldKeys.faviconFailedSentinel,
      ),
    );
  }

  Future<void> _process({
    required String entryUuid,
    required String faviconUrl,
  }) async {
    try {
      final bytes = await _downloadBytes(faviconUrl);
      if (bytes == null || bytes.isEmpty || bytes.length > maxBytes) {
        await _writeToEntry(
          entryUuid: entryUuid,
          payload: AppKdbxFieldKeys.faviconFailedSentinel,
        );
        return;
      }
      await _writeToEntry(
        entryUuid: entryUuid,
        payload: base64Encode(bytes),
      );
    } catch (error, stack) {
      debugPrint('[FaviconPersist] fetch failed for $faviconUrl: $error');
      debugPrint(stack.toString());
      await _writeToEntry(
        entryUuid: entryUuid,
        payload: AppKdbxFieldKeys.faviconFailedSentinel,
      );
    }
  }

  Future<Uint8List?> _downloadBytes(String url) async {
    final resp =
        await http.get(Uri.parse(url)).timeout(fetchTimeout);
    if (resp.statusCode != 200) return null;
    return resp.bodyBytes;
  }

  Future<void> _writeToEntry({
    required String entryUuid,
    required String payload,
  }) async {
    try {
      final repo = ref.read(kdbxRepositoryProvider);
      if (!repo.hasOpenDatabase) return;
      await repo.setEntryFaviconCache(
        entryUuid: entryUuid,
        payload: payload,
      );
      _dirty = true;
      _scheduleSave();
    } finally {
      _inFlight.remove(entryUuid);
    }
  }

  /// Coalesces saves from a burst of favicon loads into one.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDebounce, _flushSave);
  }

  Future<void> _flushSave() async {
    if (!_dirty) return;
    _dirty = false;
    final repo = ref.read(kdbxRepositoryProvider);
    if (!repo.hasOpenDatabase) return;
    final registry = ref.read(databaseRegistryProvider);
    try {
      await saveAndSyncDatabase(repo, registry);
    } catch (error) {
      debugPrint('[FaviconPersist] save failed: $error');
      // Flag dirty again so the next fetch re-triggers a save.
      _dirty = true;
    }
  }
}

final faviconPersistenceServiceProvider =
    Provider<FaviconPersistenceService>((ref) {
  final service = FaviconPersistenceService(ref: ref);
  ref.onDispose(() {
    service._saveTimer?.cancel();
  });
  return service;
});
