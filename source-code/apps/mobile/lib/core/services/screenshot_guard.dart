import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Applies or removes screenshot blocking for the current app window.
///
/// On Android this uses [FLAG_SECURE] to prevent screenshots and screen
/// recording. On iOS there is no equivalent system API available to Flutter —
/// the flag is silently ignored on iOS.
Future<void> applyScreenshotBlocking({required bool block}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    const channel = MethodChannel('com.tranit.lumenpass/screenshot');
    await channel.invokeMethod('setFlagSecure', {'block': block});
  } catch (_) {}
}
