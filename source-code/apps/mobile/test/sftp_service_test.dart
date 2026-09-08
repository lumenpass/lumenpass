import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/sftp_service.dart';

void main() {
  SftpConfig config({
    String host = 'sftp.example.com',
    int port = 22,
    String username = 'me',
    SftpAuthMethod authMethod = SftpAuthMethod.password,
    String password = 'secret',
    String? keyFilePath,
    SftpTransferMode transferMode = SftpTransferMode.passive,
    String rootPath = '/lumenpass',
  }) {
    return SftpConfig(
      host: host,
      port: port,
      username: username,
      authMethod: authMethod,
      password: password,
      keyFilePath: keyFilePath,
      transferMode: transferMode,
      rootPath: rootPath,
    );
  }

  group('SftpConfig validation', () {
    test('accepts password auth config', () {
      final result = SftpService.validateConfig(config());
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('accepts public key auth config', () {
      final result = SftpService.validateConfig(
        config(
          authMethod: SftpAuthMethod.publicKeyFile,
          password: '',
          keyFilePath: '/Users/me/.ssh/id_ed25519',
        ),
      );
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('requires host, port, and username', () {
      expect(SftpService.validateConfig(config(host: ''))['host'], isNotNull);
      expect(SftpService.validateConfig(config(port: 0))['port'], isNotNull);
      expect(
          SftpService.validateConfig(config(port: 70000))['port'], isNotNull);
      expect(
        SftpService.validateConfig(config(username: ''))['username'],
        isNotNull,
      );
    });

    test('requires password for password auth', () {
      expect(
        SftpService.validateConfig(config(password: ''))['password'],
        isNotNull,
      );
    });

    test('requires key file for key auth', () {
      expect(
        SftpService.validateConfig(
          config(authMethod: SftpAuthMethod.publicKeyFile, password: ''),
        )['keyFilePath'],
        isNotNull,
      );
    });
  });

  group('SftpService.normalizeRootPath', () {
    test('adds a leading slash and trims a trailing one', () {
      expect(SftpService.normalizeRootPath('lumenpass/'), '/lumenpass');
      expect(SftpService.normalizeRootPath('/lumenpass/'), '/lumenpass');
      expect(SftpService.normalizeRootPath('lumenpass'), '/lumenpass');
    });

    test('collapses duplicate and back separators', () {
      expect(SftpService.normalizeRootPath('//a\\\\b//c'), '/a/b/c');
    });

    test('collapses blank input to root', () {
      expect(SftpService.normalizeRootPath(''), '/');
      expect(SftpService.normalizeRootPath('   '), '/');
      expect(SftpService.normalizeRootPath('/'), '/');
    });
  });

  group('SftpConfig secret handling', () {
    test('toString masks the password', () {
      expect(
        config(password: 'topsecret').toString(),
        isNot(contains('topsecret')),
      );
    });

    test('toJsonWithoutSecret omits the password', () {
      final json = config(password: 'topsecret').toJsonWithoutSecret();
      expect(json.containsKey('password'), isFalse);
      expect(json['host'], 'sftp.example.com');
      expect(json['port'], 22);
    });

    test('fromJson restores the secret separately', () {
      final original = config(password: 'topsecret');
      final restored = SftpConfig.fromJson(
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

  group('SftpConfig.accountLabel', () {
    test('renders user@host, stripping scheme and path', () {
      expect(
        config(host: 'sftp://example.com/home/me', username: 'me').accountLabel,
        'me@example.com',
      );
    });
  });
}
