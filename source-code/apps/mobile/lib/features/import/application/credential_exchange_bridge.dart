import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Bridge to the native CXP (Credential Exchange Protocol) handler.
///
/// The native side (AppDelegate) intercepts `NSUserActivity` of type
/// `ASCredentialExchangeActivityType`, calls `ASCredentialImportManager`,
/// and pushes the JSON payload to Dart via this channel.
///
/// This bridge buffers payloads that arrive before a listener has
/// subscribed (cold-launch race) and replays them on first subscription.
class CredentialExchangeBridge {
  CredentialExchangeBridge._();

  static final CredentialExchangeBridge instance =
      CredentialExchangeBridge._();

  static const MethodChannel _channel =
      MethodChannel('lumenpass/credential_exchange');

  // Use `sync: true` so a listener subscribing after `add()` still receives
  // already-buffered events flushed via `_replayBuffered()`.
  final StreamController<String> _importController =
      StreamController<String>.broadcast();

  /// Payloads received before the first listener subscribed.
  /// Flushed once a listener attaches.
  final List<String> _pendingPayloads = <String>[];
  bool _hasListener = false;

  /// Stream of raw JSON payloads from the native CXP handler.
  /// Each emission is a JSON-encoded `ASExportedCredentialData`.
  Stream<String> get onImport {
    return _importController.stream;
  }

  bool _initialized = false;

  /// Call once at app startup to register the method call handler
  /// and check for any pending payload that arrived before Flutter was ready.
  void initialize() {
    if (_initialized) return;
    _initialized = true;

    if (!Platform.isIOS) return;

    _channel.setMethodCallHandler(_handleMethodCall);

    // Check for a payload that arrived before the channel was set up.
    _channel.invokeMethod<String>('getPending').then((pending) {
      if (pending != null && pending.isNotEmpty) {
        developer.log(
          'CXP: received pending payload (${pending.length} chars)',
          name: 'credential_exchange',
        );
        _dispatch(pending);
      }
    }).catchError((Object error) {
      developer.log(
        'CXP: getPending failed: $error',
        name: 'credential_exchange',
      );
    });
  }

  /// Called by the controller once it has subscribed to [onImport].
  /// Flushes any payloads that were buffered before subscription.
  void markListenerReady() {
    // ignore: avoid_print
    print(
      '[CXP-Dart] markListenerReady called, '
      'already=$_hasListener, pendingCount=${_pendingPayloads.length}',
    );
    if (_hasListener) return;
    _hasListener = true;
    if (_pendingPayloads.isNotEmpty) {
      developer.log(
        'CXP: flushing ${_pendingPayloads.length} buffered payload(s) '
        'to first listener',
        name: 'credential_exchange',
      );
      final toFlush = List<String>.from(_pendingPayloads);
      _pendingPayloads.clear();
      for (final payload in toFlush) {
        _importController.add(payload);
      }
    }
  }

  void _dispatch(String payload) {
    // ignore: avoid_print
    print(
      '[CXP-Dart] _dispatch: hasListener=$_hasListener, '
      'controllerHasListener=${_importController.hasListener}',
    );
    if (_hasListener && _importController.hasListener) {
      _importController.add(payload);
    } else {
      // Buffer until a listener attaches. Avoid unbounded growth.
      if (_pendingPayloads.length >= 4) {
        _pendingPayloads.removeAt(0);
      }
      _pendingPayloads.add(payload);
      // ignore: avoid_print
      print(
        '[CXP-Dart] no listener yet, buffered payload '
        '(buffer size: ${_pendingPayloads.length})',
      );
      developer.log(
        'CXP: no listener yet, buffered payload '
        '(buffer size: ${_pendingPayloads.length})',
        name: 'credential_exchange',
      );
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    // ignore: avoid_print
    print('[CXP-Dart] _handleMethodCall: ${call.method}');
    if (call.method == 'onImport') {
      final payload = call.arguments as String?;
      if (payload != null && payload.isNotEmpty) {
        // ignore: avoid_print
        print(
          '[CXP-Dart] received import payload (${payload.length} chars)',
        );
        // ignore: avoid_print
        print(
          '[CXP-Dart] payload preview: '
          '${payload.substring(0, payload.length < 1500 ? payload.length : 1500)}',
        );
        developer.log(
          'CXP: received import payload (${payload.length} chars)',
          name: 'credential_exchange',
        );
        _dispatch(payload);
      }
      return null;
    }
    throw PlatformException(
      code: 'NOT_IMPLEMENTED',
      message: 'Method ${call.method} not implemented',
    );
  }

  void dispose() {
    _importController.close();
  }
}
