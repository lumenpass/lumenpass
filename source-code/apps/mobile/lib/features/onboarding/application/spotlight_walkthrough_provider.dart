import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/repository/providers.dart';

@immutable
class SpotlightWalkthroughState {
  const SpotlightWalkthroughState({
    this.completed = false,
    this.lastStep = 0,
    this.loaded = false,
  });

  final bool completed;
  final int lastStep;
  final bool loaded;

  SpotlightWalkthroughState copyWith({
    bool? completed,
    int? lastStep,
    bool? loaded,
  }) {
    return SpotlightWalkthroughState(
      completed: completed ?? this.completed,
      lastStep: lastStep ?? this.lastStep,
      loaded: loaded ?? this.loaded,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'completed': completed,
    'lastStep': lastStep,
  };

  static SpotlightWalkthroughState fromJson(Map<String, dynamic> json) {
    return SpotlightWalkthroughState(
      completed: json['completed'] == true,
      lastStep: json['lastStep'] is int ? json['lastStep'] as int : 0,
      loaded: true,
    );
  }
}

class SpotlightWalkthroughNotifier
    extends StateNotifier<SpotlightWalkthroughState> {
  SpotlightWalkthroughNotifier(this._ref)
    : super(const SpotlightWalkthroughState()) {
    _load();
  }

  static const _storageKey = 'lumenpass_vault_picker_spotlight_v1';

  final Ref _ref;

  Future<void> _load() async {
    try {
      final raw = await _ref.read(localStorageProvider).read(_storageKey);
      if (raw == null || raw.isEmpty) {
        state = state.copyWith(loaded: true);
        return;
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      state = SpotlightWalkthroughState.fromJson(decoded);
    } catch (_) {
      state = state.copyWith(loaded: true);
    }
  }

  Future<void> _persist() async {
    try {
      await _ref
          .read(localStorageProvider)
          .write(_storageKey, jsonEncode(state.toJson()));
    } catch (_) {}
  }

  Future<void> setStep(int step) async {
    if (state.completed || state.lastStep == step) return;
    state = state.copyWith(lastStep: step);
    await _persist();
  }

  Future<void> complete() async {
    if (state.completed) return;
    state = state.copyWith(completed: true);
    await _persist();
  }

  Future<void> reset() async {
    state = const SpotlightWalkthroughState(loaded: true);
    await _persist();
  }
}

final spotlightWalkthroughProvider =
    StateNotifierProvider<
      SpotlightWalkthroughNotifier,
      SpotlightWalkthroughState
    >((ref) => SpotlightWalkthroughNotifier(ref));
