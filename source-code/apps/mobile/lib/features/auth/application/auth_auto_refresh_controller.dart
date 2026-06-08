import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';

class AuthAutoRefreshController with WidgetsBindingObserver {
  AuthAutoRefreshController({
    required Ref ref,
    required AuthState initialAuthState,
    Duration interval = const Duration(minutes: 1),
    DateTime Function()? clock,
    bool observeLifecycle = true,
  })  : _ref = ref,
        _interval = interval,
        _clock = clock ?? DateTime.now,
        _observeLifecycle = observeLifecycle {
    if (_observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
    }
    onAuthStateChanged(initialAuthState);
  }

  static const Duration _resumeDebounce = Duration(seconds: 3);

  final Ref _ref;
  final Duration _interval;
  final DateTime Function() _clock;
  final bool _observeLifecycle;

  Timer? _timer;
  bool _foreground = true;
  DateTime? _lastRefreshTriggerAt;

  bool _shouldRun(AuthState authState) =>
      authState.isHydrated && authState.isAuthenticated;

  void onAuthStateChanged(AuthState authState) {
    if (!_shouldRun(authState)) {
      _stopTimer();
      return;
    }
    if (_foreground) {
      _restartTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        _restartTimer();
        final authState = _ref.read(authControllerProvider);
        if (_shouldRun(authState)) {
          final now = _clock();
          final sinceLast = _lastRefreshTriggerAt == null
              ? null
              : now.difference(_lastRefreshTriggerAt!);
          if (sinceLast == null || sinceLast >= _resumeDebounce) {
            unawaited(_refreshProfile(force: false, reason: 'resume'));
          }
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _foreground = false;
        _stopTimer();
        break;
    }
  }

  void _restartTimer() {
    final authState = _ref.read(authControllerProvider);
    if (!_foreground || !_shouldRun(authState)) return;
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) {
      unawaited(_refreshProfile(force: false, reason: 'interval'));
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _refreshProfile({
    required bool force,
    required String reason,
  }) async {
    final authState = _ref.read(authControllerProvider);
    if (!_foreground || !_shouldRun(authState)) return;

    _lastRefreshTriggerAt = _clock();
    if (kDebugMode) {
      debugPrint('[AuthAutoRefresh] trigger=$reason force=$force');
    }

    await _ref
        .read(authControllerProvider.notifier)
        .refreshProfile(force: force, showLoading: false);
  }

  void dispose() {
    if (_observeLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _stopTimer();
  }
}

final authAutoRefreshControllerProvider = Provider<AuthAutoRefreshController>((
  ref,
) {
  final controller = AuthAutoRefreshController(
    ref: ref,
    initialAuthState: ref.read(authControllerProvider),
  );
  ref.listen<AuthState>(authControllerProvider, (_, next) {
    controller.onAuthStateChanged(next);
  });
  ref.onDispose(controller.dispose);
  return controller;
});
