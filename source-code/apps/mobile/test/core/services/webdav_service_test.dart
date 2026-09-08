import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/webdav_service.dart';

void main() {
  WebDavConfig config({
    String host = 'dav.example.com',
    int port = 443,
    String username = 'me',
    String password = 'secret',
    String rootPath = '/lumenpass',
  }) {
    return WebDavConfig(
      host: host,
      port: port,
      username: username,
      password: password,
      rootPath: rootPath,
    );
  }

  group('WebDavConfig validation', () {
    test('accepts a fully-specified valid config', () {
      final result = WebDavService.validateConfig(config());
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('requires a non-empty host', () {
      expect(
        WebDavService.validateConfig(config(host: '   '))['host'],
        isNotNull,
      );
    });

    test('rejects ports outside 1–65535', () {
      expect(WebDavService.validateConfig(config(port: 0))['port'], isNotNull);
      expect(
        WebDavService.validateConfig(config(port: 70000))['port'],
        isNotNull,
      );
      expect(WebDavService.validateConfig(config(port: 1)).isValid, isTrue);
    });

    test('requires username and password', () {
      expect(
        WebDavService.validateConfig(config(username: ''))['username'],
        isNotNull,
      );
      expect(
        WebDavService.validateConfig(config(password: ''))['password'],
        isNotNull,
      );
    });
  });

  group('WebDavService.normalizeRootPath', () {
    test('adds a leading slash and trims a trailing one', () {
      expect(WebDavService.normalizeRootPath('lumenpass/'), '/lumenpass');
      expect(WebDavService.normalizeRootPath('/lumenpass/'), '/lumenpass');
    });

    test('collapses blank input to root', () {
      expect(WebDavService.normalizeRootPath(''), '/');
      expect(WebDavService.normalizeRootPath('   '), '/');
    });
  });

  group('WebDavConfig secret handling', () {
    test('toString masks the password', () {
      expect(
        config(password: 'topsecret').toString(),
        isNot(contains('topsecret')),
      );
    });

    test('accountLabel renders user@host, stripping scheme and path', () {
      expect(
        config(host: 'https://example.com/remote.php/dav', username: 'me')
            .accountLabel,
        'me@example.com',
      );
    });
  });
}
