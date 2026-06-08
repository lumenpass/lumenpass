import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum NativeBannerStyle { success, error, info }

abstract final class NativeBanner {
  static const MethodChannel _channel = MethodChannel(
    'com.tranit.lumenpass/native_banner',
  );

  static Future<bool> show(
    String message, {
    NativeBannerStyle style = NativeBannerStyle.info,
  }) async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        try {
          final shown = await _channel.invokeMethod<bool>('show', {
            'message': message,
            'style': style.name,
          });
          return shown ?? false;
        } catch (_) {
          return false;
        }
      default:
        return false;
    }
  }

  static Future<bool> success(String message) =>
      show(message, style: NativeBannerStyle.success);

  static Future<bool> error(String message) =>
      show(message, style: NativeBannerStyle.error);

  static Future<bool> info(String message) =>
      show(message, style: NativeBannerStyle.info);
}
