import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/core/services/webdav_service.dart';

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
      final result = WebDavService.validateConfig(config(host: '   '));
      expect(result.isValid, isFalse);
      expect(result['host'], isNotNull);
    });

    test('rejects ports outside 1–65535', () {
      expect(WebDavService.validateConfig(config(port: 0))['port'], isNotNull);
      expect(
        WebDavService.validateConfig(config(port: 70000))['port'],
        isNotNull,
      );
      expect(WebDavService.validateConfig(config(port: 1)).isValid, isTrue);
      expect(WebDavService.validateConfig(config(port: 65535)).isValid, isTrue);
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

    test('flags an empty root path', () {
      final result = WebDavService.validateConfig(config(rootPath: '   '));
      // normalizeRootPath collapses blank to '/', which is valid.
      expect(result.isValid, isTrue);
    });
  });

  group('WebDavService.normalizeRootPath', () {
    test('adds a leading slash and trims a trailing one', () {
      expect(WebDavService.normalizeRootPath('lumenpass/'), '/lumenpass');
      expect(WebDavService.normalizeRootPath('/lumenpass/'), '/lumenpass');
      expect(WebDavService.normalizeRootPath('lumenpass'), '/lumenpass');
    });

    test('collapses duplicate and back separators', () {
      expect(WebDavService.normalizeRootPath('//a\\\\b//c'), '/a/b/c');
    });

    test('collapses blank input to root', () {
      expect(WebDavService.normalizeRootPath(''), '/');
      expect(WebDavService.normalizeRootPath('   '), '/');
      expect(WebDavService.normalizeRootPath('/'), '/');
    });
  });

  group('WebDavConfig secret handling', () {
    test('toString masks the password', () {
      expect(config(password: 'topsecret').toString(), isNot(contains('topsecret')));
    });

    test('toJsonWithoutSecret omits the password', () {
      final json = config(password: 'topsecret').toJsonWithoutSecret();
      expect(json.containsKey('password'), isFalse);
      expect(json['host'], 'dav.example.com');
      expect(json['port'], 443);
    });

    test('fromJson restores the secret separately', () {
      final original = config(password: 'topsecret');
      final restored = WebDavConfig.fromJson(
        original.toJsonWithoutSecret(),
        password: 'topsecret',
      );
      expect(restored.host, original.host);
      expect(restored.port, original.port);
      expect(restored.username, original.username);
      expect(restored.rootPath, original.rootPath);
      expect(restored.password, 'topsecret');
    });
  });

  group('WebDavConfig.accountLabel', () {
    test('renders user@host, stripping scheme and path', () {
      expect(
        config(host: 'https://example.com/remote.php/dav', username: 'me')
            .accountLabel,
        'me@example.com',
      );
    });
  });
}
