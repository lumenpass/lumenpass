import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'autofill_credential.dart';

/// Result of querying the OS about our AutoFill provider.
enum AutoFillServiceStatus {
  /// Platform doesn't support AutoFill via a provider (e.g. web, desktop).
  notSupported,

  /// AutoFill is supported but our provider isn't enabled by the user
  /// in the system settings yet.
  disabled,

  /// Our provider is enabled in system settings.
  enabled,

  /// The native side couldn't determine the status (treated as unknown).
  unknown,
}

/// Thin wrapper around a platform method channel that drives the native
/// AutoFill providers. The native side is responsible for:
///
/// * Securely caching the credentials in a location visible to the OS
///   AutoFill subsystem (App Group shared container on iOS, app-private
///   encrypted cache on Android).
/// * Telling the OS which credentials are available (`ASCredentialIdentityStore`
///   on iOS; Android wires up from the service at fill time).
/// * Reporting back provider status / opening the relevant settings panel.
class AutoFillBridge {
  AutoFillBridge._();

  static final AutoFillBridge instance = AutoFillBridge._();

  static const MethodChannel _channel = MethodChannel('lumenpass/autofill');

  /// Returns true when the host platform ships a supported AutoFill API.
  bool get isPlatformSupported => Platform.isIOS || Platform.isAndroid;

  /// Reports whether the LumenPass AutoFill provider is currently turned on
  /// in the system settings (Settings → Passwords → AutoFill on iOS,
  /// Settings → System → Languages & input → Autofill service on Android).
  Future<AutoFillServiceStatus> getStatus() async {
    if (!isPlatformSupported) return AutoFillServiceStatus.notSupported;
    try {
      final raw = await _channel.invokeMethod<String>('getStatus');
      switch (raw) {
        case 'enabled':
          return AutoFillServiceStatus.enabled;
        case 'disabled':
          return AutoFillServiceStatus.disabled;
        case 'notSupported':
          return AutoFillServiceStatus.notSupported;
      }
      return AutoFillServiceStatus.unknown;
    } on PlatformException {
      return AutoFillServiceStatus.unknown;
    } on MissingPluginException {
      return AutoFillServiceStatus.unknown;
    }
  }

  /// Pushes the latest snapshot of eligible credentials down to the native
  /// side so the OS AutoFill subsystem can offer suggestions. Entries that
  /// aren't logins, or that don't carry a username + password, are filtered
  /// out by the caller before invoking this method.
  Future<void> syncCredentials(List<AutoFillCredential> credentials) async {
    if (!isPlatformSupported) return;
    try {
      await _channel.invokeMethod<void>('syncCredentials', <String, Object?>{
        'credentials': credentials.map((c) => c.toJson()).toList(),
      });
      developer.log(
        'Synced ${credentials.length} credentials to native AutoFill store',
        name: 'autofill',
      );
    } on PlatformException catch (error, stack) {
      // Don't break the vault on sync failure, but surface it for devs.
      developer.log(
        'AutoFill sync failed: ${error.code} ${error.message}',
        name: 'autofill',
        error: error,
        stackTrace: stack,
      );
    } on MissingPluginException {
      // native side not yet wired up (e.g. running on desktop tests).
    }
  }

  /// Clears all cached AutoFill credentials. Called when the vault locks or
  /// the user signs out.
  Future<void> clearCredentials() async {
    if (!isPlatformSupported) return;
    try {
      await _channel.invokeMethod<void>('clearCredentials');
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }

  /// Deep-links the user into the system AutoFill settings so they can
  /// toggle LumenPass on.
  Future<bool> openSystemSettings() async {
    if (!isPlatformSupported) return false;
    try {
      return (await _channel.invokeMethod<bool>('openSystemSettings')) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<ChromeThirdPartyMode> getChromeThirdPartyMode({
    String package_ = 'com.android.chrome',
  }) async {
    if (!Platform.isAndroid) return ChromeThirdPartyMode.unknown;
    try {
      final raw = await _channel.invokeMethod<String>(
        'getChromeThirdPartyMode',
        <String, Object?>{'package': package_},
      );
      switch (raw) {
        case 'enabled':
          return ChromeThirdPartyMode.enabled;
        case 'disabled':
          return ChromeThirdPartyMode.disabled;
      }
      return ChromeThirdPartyMode.unknown;
    } on PlatformException {
      return ChromeThirdPartyMode.unknown;
    } on MissingPluginException {
      return ChromeThirdPartyMode.unknown;
    }
  }

  Future<bool> openChromeAutofillSettings({String? package_}) async {
    if (!Platform.isAndroid) return false;
    try {
      final arguments = <String, Object?>{};
      if (package_ != null) arguments['package'] = package_;
      return (await _channel.invokeMethod<bool>(
            'openChromeAutofillSettings',
            arguments,
          )) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

enum ChromeThirdPartyMode { enabled, disabled, unknown }
