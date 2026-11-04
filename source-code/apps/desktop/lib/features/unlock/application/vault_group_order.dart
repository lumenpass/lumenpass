import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/repository/kdbx_repository_provider.dart';

/// Persists the order in which storage-provider groups appear on the unlock
/// screen. Holds `DatabaseRecord.storageType` tokens (`'local'`,
/// `'googleDrive'`, ...) in display order.
class VaultGroupOrderNotifier extends StateNotifier<List<String>> {
  VaultGroupOrderNotifier(this._ref) : super(const <String>[]) {
    unawaited(_load());
  }

  static const String _storageKey = 'lumenpass_vault_group_order_v1';

  final Ref _ref;
  final Completer<void> _readyCompleter = Completer<void>();

  Future<void> get ready => _readyCompleter.future;

  Future<void> _load() async {
    try {
      final storage = _ref.read(localStorageProvider);
      final raw = await storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = raw
            .split(',')
            .map((entry) => entry.trim())
            .where((entry) => entry.isEmpty == false)
            .toList(growable: false);
        if (decoded.isNotEmpty) {
          state = decoded;
        }
      }
    } catch (_) {
      // Fall back to the caller's default ordering.
    } finally {
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.complete();
      }
    }
  }

  /// Applies a new order for the *visible* groups and persists the result.
  ///
  /// [visibleOrder] is the complete new order of the groups currently on
  /// screen. [knownOrder] seeds the stored list on a fresh install so that
  /// providers filtered out by a search keep a sensible position instead of
  /// being dropped.
  ///
  /// Providers that are not currently visible keep their original slots: only
  /// the positions previously occupied by visible groups are rewritten. That
  /// way reordering during a search never reshuffles the hidden groups.
  Future<void> applyVisibleOrder(
    List<String> visibleOrder, {
    required List<String> knownOrder,
  }) async {
    if (visibleOrder.isEmpty) return;

    final base = <String>[
      ...state.where(knownOrder.contains),
      ...knownOrder.where((type) => !state.contains(type)),
    ];

    if (base.isEmpty) {
      // Nothing persisted yet: the visible order simply wins.
      state = List<String>.unmodifiable(visibleOrder);
      await _persist();
      return;
    }

    final visible = visibleOrder.toSet();
    final slots = <int>[
      for (var i = 0; i < base.length; i++)
        if (visible.contains(base[i])) i,
    ];

    final next = List<String>.from(base);
    var cursor = 0;
    for (final slot in slots) {
      if (cursor >= visibleOrder.length) break;
      next[slot] = visibleOrder[cursor++];
    }
    // Visible providers with no existing slot (newly added) go last.
    for (var i = cursor; i < visibleOrder.length; i++) {
      next.add(visibleOrder[i]);
    }

    state = List<String>.unmodifiable(next);
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final storage = _ref.read(localStorageProvider);
      await storage.write(key: _storageKey, value: state.join(','));
    } catch (_) {
      // Reordering is cosmetic; a failed write must not break the UI.
    }
  }
}

final vaultGroupOrderProvider =
    StateNotifierProvider<VaultGroupOrderNotifier, List<String>>(
  (ref) => VaultGroupOrderNotifier(ref),
);
