import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/core/services/s3_service.dart';

void main() {
  S3Config validConfig() {
    return S3Config(
      accessKey: 'AKIAIOSFODNN7EXAMPLE',
      secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      region: 'us-east-1',
      bucketId: 'my-test-bucket',
    );
  }

  group('S3Config validation', () {
    test('accepts a valid config', () {
      final config = validConfig();
      expect(config.isValid, isTrue);
    });

    test('rejects config with empty access key', () {
      final config = validConfig();
      final invalid = S3Config(
        accessKey: '',
        secretKey: config.secretKey,
        region: config.region,
        bucketId: config.bucketId,
      );
      expect(invalid.isValid, isFalse);
    });

    test('rejects config with empty secret key', () {
      final config = validConfig();
      final invalid = S3Config(
        accessKey: config.accessKey,
        secretKey: '',
        region: config.region,
        bucketId: config.bucketId,
      );
      expect(invalid.isValid, isFalse);
    });

    test('rejects config with empty region', () {
      final config = validConfig();
      final invalid = S3Config(
        accessKey: config.accessKey,
        secretKey: config.secretKey,
        region: '',
        bucketId: config.bucketId,
      );
      expect(invalid.isValid, isFalse);
    });

    test('rejects config with empty bucket', () {
      final config = validConfig();
      final invalid = S3Config(
        accessKey: config.accessKey,
        secretKey: config.secretKey,
        region: config.region,
        bucketId: '',
      );
      expect(invalid.isValid, isFalse);
    });

    test('rejects config with all empty fields', () {
      const invalid = S3Config(
        accessKey: '',
        secretKey: '',
        region: '',
        bucketId: '',
      );
      expect(invalid.isValid, isFalse);
    });

    test('accepts config with optional fields', () {
      final config = S3Config(
        accessKey: 'AKIAIOSFODNN7EXAMPLE',
        secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        region: 'eu-central-1',
        bucketId: 'my-bucket',
        host: 's3.eu-central-1.amazonaws.com',
        sessionToken: 'session-token-value',
      );
      expect(config.isValid, isTrue);
      expect(config.host, 's3.eu-central-1.amazonaws.com');
      expect(config.sessionToken, 'session-token-value');
    });

    test('accepts config with null optional fields', () {
      final config = validConfig();
      expect(config.host, isNull);
      expect(config.sessionToken, isNull);
    });
  });

  group('S3Service lifecycle', () {
    tearDown(() {
      S3Service.instance.dispose();
    });

    test('is not configured by default', () {
      expect(S3Service.instance.isConfigured, isFalse);
    });

    test('is configured after calling configure() with valid config', () {
      S3Service.instance.configure(validConfig());
      expect(S3Service.instance.isConfigured, isTrue);
      expect(S3Service.instance.currentBucketId, 'my-test-bucket');
      expect(S3Service.instance.currentRegion, 'us-east-1');
    });

    test('is not configured after calling dispose()', () {
      S3Service.instance.configure(validConfig());
      expect(S3Service.instance.isConfigured, isTrue);
      S3Service.instance.dispose();
      expect(S3Service.instance.isConfigured, isFalse);
      expect(S3Service.instance.currentBucketId, isNull);
      expect(S3Service.instance.currentRegion, isNull);
    });

    test('configure() throws ArgumentError for invalid config', () {
      expect(
        () => S3Service.instance.configure(
          S3Config(
            accessKey: '',
            secretKey: 'secret',
            region: 'us-east-1',
            bucketId: 'bucket',
          ),
        ),
        throwsArgumentError,
      );
    });

    test('reconfigure changes the client', () {
      S3Service.instance.configure(validConfig());
      expect(S3Service.instance.currentBucketId, 'my-test-bucket');

      S3Service.instance.configure(
        S3Config(
          accessKey: 'DIFFERENTKEY',
          secretKey: 'differentSecret',
          region: 'eu-west-1',
          bucketId: 'other-bucket',
        ),
      );
      expect(S3Service.instance.currentBucketId, 'other-bucket');
      expect(S3Service.instance.currentRegion, 'eu-west-1');
    });
  });

  group('S3Service unconfigured error handling', () {
    setUp(() {
      // Ensure clean state before each test.
      S3Service.instance.dispose();
    });

    test('downloadObject throws StateError when not configured', () {
      expect(
        () => S3Service.instance.downloadObject('test-key'),
        throwsA(isA<StateError>()),
      );
    });

    test('listObjects throws StateError when not configured', () {
      expect(
        () => S3Service.instance.listObjects(),
        throwsA(isA<StateError>()),
      );
    });

    test('objectExists throws StateError when not configured', () {
      expect(
        () => S3Service.instance.objectExists('test-key'),
        throwsA(isA<StateError>()),
      );
    });

    test('uploadObject throws StateError when not configured', () {
      expect(
        () => S3Service.instance.uploadObject('test-key', Uint8List(0)),
        throwsA(isA<StateError>()),
      );
    });

    test('deleteObject throws StateError when not configured', () {
      expect(
        () => S3Service.instance.deleteObject('test-key'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('S3ObjectInfo model', () {
    test('creates model with all fields', () {
      final info = S3ObjectInfo(
        key: 'vaults/my-vault.kdbx',
        size: 1024,
        lastModified: DateTime(2026, 6, 1),
        eTag: '"abc123def456"',
        storageClass: 'STANDARD',
      );
      expect(info.key, 'vaults/my-vault.kdbx');
      expect(info.size, 1024);
      expect(info.lastModified, DateTime(2026, 6, 1));
      expect(info.eTag, '"abc123def456"');
      expect(info.storageClass, 'STANDARD');
    });

    test('creates model with minimal fields', () {
      final info = S3ObjectInfo(key: 'test.txt');
      expect(info.key, 'test.txt');
      expect(info.size, isNull);
      expect(info.lastModified, isNull);
      expect(info.eTag, isNull);
      expect(info.storageClass, isNull);
    });
  });

  group('S3ListResult model', () {
    test('creates model with objects', () {
      final result = S3ListResult(
        objects: [
          S3ObjectInfo(key: 'file1.txt', size: 100),
          S3ObjectInfo(key: 'file2.txt', size: 200),
        ],
        isTruncated: false,
        prefix: 'vaults/',
      );
      expect(result.objects.length, 2);
      expect(result.isTruncated, isFalse);
      expect(result.prefix, 'vaults/');
    });

    test('creates model with truncated result', () {
      final result = S3ListResult(
        objects: [S3ObjectInfo(key: 'file1.txt')],
        isTruncated: true,
      );
      expect(result.isTruncated, isTrue);
      expect(result.prefix, isNull);
    });

    test('creates model with empty objects', () {
      final result = S3ListResult(
        objects: [],
        isTruncated: false,
      );
      expect(result.objects, isEmpty);
    });
  });
}
