import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
      if (info != null) {
        return AppRuntimeInfo.fromMap(info);
      }
    } on MissingPluginException {
      // Platform did not register the channel — fall back below.
    } on PlatformException catch (error, stackTrace) {
      developer.log(
        'failed to load runtime app info: ${error.message}',
        name: 'app.runtime_info',
        stackTrace: stackTrace,
      );
    }

    // Cross-platform fallback so the version check works even when the
    // native method channel is unavailable on a platform.
    try {
      final pkg = await PackageInfo.fromPlatform();
      return AppRuntimeInfo(
        bundleIdentifier: pkg.packageName,
        version: pkg.version,
        buildNumber: pkg.buildNumber,
      );
    } catch (error, stackTrace) {
      developer.log(
        'failed to load package info: $error',
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
