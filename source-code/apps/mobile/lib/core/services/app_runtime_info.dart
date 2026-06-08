import 'dart:developer' as developer;

import 'package:flutter/services.dart';

class AppRuntimeInfo {
  const AppRuntimeInfo({
    required this.bundleIdentifier,
    required this.version,
    required this.buildNumber,
  });

  factory AppRuntimeInfo.fromMap(Map<Object?, Object?> map) {
    return AppRuntimeInfo(
      bundleIdentifier: (map['bundleIdentifier'] as String? ?? '').trim(),
      version: (map['version'] as String? ?? '').trim(),
      buildNumber: (map['buildNumber'] as String? ?? '').trim(),
    );
  }

  final String bundleIdentifier;
  final String version;
  final String buildNumber;

  @override
  String toString() {
    return 'AppRuntimeInfo('
        'bundleIdentifier: $bundleIdentifier, '
        'version: $version, '
        'buildNumber: $buildNumber'
        ')';
  }
}

class AppRuntimeInfoService {
  AppRuntimeInfoService._();

  static const MethodChannel _channel = MethodChannel('app.runtime.info');

  static Future<AppRuntimeInfo?> load() async {
    try {
      final info = await _channel.invokeMapMethod<Object?, Object?>('getInfo');
      if (info == null) return null;
      return AppRuntimeInfo.fromMap(info);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error, stackTrace) {
      developer.log(
        'failed to load runtime app info: ${error.message}',
        name: 'app.runtime_info',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static Future<void> logStartupInfo() async {
    final info = await load();
    if (info == null) {
      developer.log('runtime app info unavailable', name: 'app.runtime_info');
      return;
    }
    developer.log('$info', name: 'app.runtime_info');
  }
}
