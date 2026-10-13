import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/core/services/google_auth/google_auth.dart';
import 'package:path/path.dart' as p;

/// Regression coverage for the "cloud database not connected on startup" bug.
///
/// The unlock screen fires every cloud vault's health probe in parallel
/// (`Future.wait`), so multiple `signInSilently()` calls can land in the same
/// event-loop turn before persisted credentials have finished loading from
/// disk. The old implementation set a `_hydrated = true` flag on the first
/// line of `_hydrateFromDisk()` — *before* awaiting the disk read — so a
/// second concurrent caller would skip hydration and observe
/// `_currentUser == null`, wrongly reporting "Google Drive is not connected".
///
/// These tests drive the real platform [GoogleAuth] implementation through
/// [googleAuthFor] with a mocked `path_provider` so we exercise the actual
/// hydration path, not a fake.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;

  // The persisted-credentials filename is platform-specific; pick the one the
  // running host's implementation reads so the fixture lands where it looks.
  String persistedFileName() {
    if (Platform.isMacOS) return 'macos_google_auth.json';
    if (Platform.isWindows) return 'windows_google_auth.json';
    if (Platform.isLinux) return 'linux_google_auth.json';
    throw UnsupportedError('unsupported test host');
  }

  setUp(() {
    supportDir = Directory.systemTemp.createTempSync('lp-google-auth');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationSupportDirectory') {
        return supportDir.path;
      }
      return null;
    });
  });

  tearDown(() {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (supportDir.existsSync()) {
      supportDir.deleteSync(recursive: true);
    }
  });

  void writePersistedCredentials({required DateTime expiry}) {
    final file = File(p.join(supportDir.path, persistedFileName()));
    file.writeAsStringSync(jsonEncode(<String, dynamic>{
      'email': 'user@example.com',
      'access_token': 'persisted-access-token',
      'refresh_token': 'persisted-refresh-token',
      'expiry': expiry.toIso8601String(),
    }));
  }

  GoogleAuth buildAuth() => googleAuthFor(
        clientId: 'test-client-id',
        clientSecret: null,
        scopes: const <String>['email'],
      );

  test(
    'concurrent signInSilently calls all see hydrated credentials (no race)',
    () async {
      // Token valid well into the future so signInSilently returns the cached
      // creds directly and never attempts a network refresh.
      writePersistedCredentials(
        expiry: DateTime.now().add(const Duration(hours: 1)),
      );

      final auth = buildAuth();

      // Fire many probes in the same turn, mirroring the unlock screen's
      // parallel `Future.wait` over cloud vault records.
      final results = await Future.wait(
        List.generate(8, (_) => auth.signInSilently()),
      );

      for (final creds in results) {
        expect(
          creds,
          isNotNull,
          reason: 'every concurrent caller must observe hydrated credentials',
        );
      }
      expect(auth.isConnected, isTrue);
      expect(auth.currentEmail, 'user@example.com');
    },
  );

  test(
    'first signInSilently hydrates persisted credentials from disk',
    () async {
      writePersistedCredentials(
        expiry: DateTime.now().add(const Duration(hours: 1)),
      );

      final auth = buildAuth();
      expect(auth.isConnected, isFalse, reason: 'cold before first probe');

      final creds = await auth.signInSilently();
      expect(creds, isNotNull);
      expect(auth.isConnected, isTrue);
    },
  );

  test(
    'signInSilently returns null when no credentials are persisted',
    () async {
      final auth = buildAuth();
      final creds = await auth.signInSilently();
      expect(creds, isNull);
      expect(auth.isConnected, isFalse);
    },
  );
}
