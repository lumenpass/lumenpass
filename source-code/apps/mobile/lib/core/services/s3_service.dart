import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_aws_s3_client/flutter_aws_s3_client.dart';
import 'package:flutter_aws_s3_client/src/client/sig_v4.dart';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// Configuration model
// ---------------------------------------------------------------------------

class S3Config {
  final String accessKey;
  final String secretKey;
  final String region;
  final String bucketId;
  final String? host;
  final String? sessionToken;
  final String rootPath;

  const S3Config({
    required this.accessKey,
    required this.secretKey,
    required this.region,
    required this.bucketId,
    this.host,
    this.sessionToken,
    this.rootPath = '',
  });

  bool get isValid =>
      accessKey.isNotEmpty &&
      secretKey.isNotEmpty &&
      region.isNotEmpty &&
      bucketId.isNotEmpty;

  S3Config copyWith({
    String? accessKey,
    String? secretKey,
    String? region,
    String? bucketId,
    String? host,
    String? sessionToken,
    String? rootPath,
  }) {
    return S3Config(
      accessKey: accessKey ?? this.accessKey,
      secretKey: secretKey ?? this.secretKey,
      region: region ?? this.region,
      bucketId: bucketId ?? this.bucketId,
      host: host ?? this.host,
      sessionToken: sessionToken ?? this.sessionToken,
      rootPath: rootPath ?? this.rootPath,
    );
  }
}

// ---------------------------------------------------------------------------
// Result models
// ---------------------------------------------------------------------------

class S3ObjectInfo {
  final String key;
  final int? size;
  final DateTime? lastModified;
  final String? eTag;
  final String? storageClass;

  const S3ObjectInfo({
    required this.key,
    this.size,
    this.lastModified,
    this.eTag,
    this.storageClass,
  });
}

class S3ListResult {
  final List<S3ObjectInfo> objects;
  final bool isTruncated;
  final String? prefix;

  const S3ListResult({
    required this.objects,
    required this.isTruncated,
    this.prefix,
  });
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class S3Service {
  S3Service._();
  static final S3Service instance = S3Service._();

  AwsS3Client? _client;
  S3Config? _config;

  static const _service = 's3';

  bool get isConfigured => _client != null;

  /// The currently configured bucket name, if any.
  String? get currentBucketId => _config?.bucketId;

  /// The currently configured region, if any.
  String? get currentRegion => _config?.region;

  /// The currently configured root path (prefix), if any.
  String? get currentRootPath => _config?.rootPath;

  // -------------------------------------------------------------------------
  // Configuration
  // -------------------------------------------------------------------------

  void configure(S3Config config) {
    if (!config.isValid) {
      throw ArgumentError(
          'S3Config is invalid: all required fields must be non-empty.');
    }
    _config = config;
    _client = AwsS3Client(
      accessKey: config.accessKey,
      secretKey: config.secretKey,
      region: config.region,
      bucketId: config.bucketId,
      host: config.host,
      sessionToken: config.sessionToken,
    );
    debugPrint(
        '[S3Service] Configured for bucket "${config.bucketId}" in ${config.region}');
  }

  void dispose() {
    _client = null;
    _config = null;
  }

  // -------------------------------------------------------------------------
  // S3 Operations
  // -------------------------------------------------------------------------

  AwsS3Client get _requireClient {
    final client = _client;
    if (client == null) {
      throw StateError('S3Service not configured. Call configure() first.');
    }
    return client;
  }

  S3Config get _requireConfig {
    final config = _config;
    if (config == null) {
      throw StateError('S3Service not configured. Call configure() first.');
    }
    return config;
  }

  /// Downloads an object from S3 into memory as [Uint8List].
  Future<Uint8List> downloadObject(String key) async {
    final client = _requireClient;
    try {
      final response = await client.getObject(key);
      _checkResponseError(response);
      return response.bodyBytes;
    } on S3Exception {
      rethrow;
    } catch (e) {
      throw S3Exception(
        http.Response('Network error: $e', 0),
      );
    }
  }

  /// Downloads an object from S3 and streams it to a local [File].
  /// Uses [buildSignedGetParams] for memory-efficient streaming with ETag support.
  Future<void> downloadObjectToFile(
    String key,
    File destination, {
    String? eTag,
    void Function(int received, int? total)? onProgress,
  }) async {
    final client = _requireClient;
    final signedParams = client.buildSignedGetParams(key: key);

    final request = await HttpClient().getUrl(signedParams.uri);
    for (final header in (signedParams.headers).entries) {
      request.headers.add(header.key, header.value);
    }
    if (eTag != null) {
      request.headers.add(HttpHeaders.ifNoneMatchHeader, eTag);
    }
    final response = await request.close();

    if (response.statusCode != HttpStatus.ok) {
      throw S3Exception(
        http.Response(
          await response.transform(const Utf8Decoder()).join(),
          response.statusCode,
        ),
      );
    }

    final file = destination.openWrite();
    await response.pipe(file);
  }

  /// Lists objects in the bucket, optionally filtered by prefix.
  Future<S3ListResult> listObjects({
    String? prefix,
    String? delimiter,
    int? maxKeys,
  }) async {
    final client = _requireClient;
    try {
      final result = await client.listObjects(
        prefix: prefix,
        delimiter: delimiter,
        maxKeys: maxKeys,
      );

      final objects = result?.contents
              ?.map((c) => S3ObjectInfo(
                    key: c.key ?? '',
                    size: int.tryParse(c.size ?? '0'),
                    lastModified: c.lastModified != null
                        ? DateTime.tryParse(c.lastModified!)
                        : null,
                    eTag: c.eTag,
                    storageClass: c.storageClass,
                  ))
              .toList() ??
          [];

      return S3ListResult(
        objects: objects,
        isTruncated: result?.isTruncated == 'true',
        prefix: result?.prefix,
      );
    } on S3Exception {
      rethrow;
    } catch (e) {
      throw S3Exception(
        http.Response('List error: $e', 0),
      );
    }
  }

  /// Checks if an object exists by issuing a HEAD request.
  Future<bool> objectExists(String key) async {
    final client = _requireClient;
    try {
      final response = await client.headObject(key);
      return response.statusCode == HttpStatus.ok;
    } on S3Exception {
      return false;
    }
  }

  /// Lists common prefixes ("folders") in the bucket at the given prefix path.
  /// Uses delimiter="/" so that only the top-level folder names are returned.
  ///
  /// The vendored AWS client only deserializes `Contents` and discards the
  /// `CommonPrefixes` entries that S3 returns when a delimiter is supplied, so
  /// we issue the signed request ourselves and parse the folder prefixes out
  /// of the raw XML. This is what makes freshly created folders show up.
  Future<List<String>> listPrefixes({
    String prefix = '',
    int? maxKeys,
  }) async {
    final client = _requireClient;
    final normalizedPrefix =
        prefix.isEmpty ? '' : (prefix.endsWith('/') ? prefix : '$prefix/');
    try {
      final params = client.buildSignedGetParams(
        key: '',
        queryParams: {
          'list-type': '2',
          'delimiter': '/',
          if (normalizedPrefix.isNotEmpty) 'prefix': normalizedPrefix,
          if (maxKeys != null) 'max-keys': maxKeys.toString(),
        },
      );
      final response = await http.get(params.uri, headers: params.headers);
      if (response.statusCode == 403) {
        throw NoPermissionsException(response);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw S3Exception(response);
      }

      final Set<String> prefixes = {};

      // Folders surface as <CommonPrefixes><Prefix>foo/</Prefix>…
      final commonPrefixRegExp =
          RegExp(r'<Prefix>([^<]*)</Prefix>', caseSensitive: false);
      final commonPrefixBlocks = RegExp(
        r'<CommonPrefixes>(.*?)</CommonPrefixes>',
        caseSensitive: false,
        dotAll: true,
      );
      for (final block in commonPrefixBlocks.allMatches(response.body)) {
        final match = commonPrefixRegExp.firstMatch(block.group(1) ?? '');
        final value = _unescapeXml(match?.group(1) ?? '');
        if (value.isNotEmpty && value != normalizedPrefix) {
          prefixes.add(value);
        }
      }

      // Fallback: infer folders from object keys in case the endpoint does
      // not honour the delimiter (some S3-compatible providers differ).
      final keyRegExp = RegExp(
        r'<Contents>.*?<Key>([^<]*)</Key>.*?</Contents>',
        caseSensitive: false,
        dotAll: true,
      );
      for (final match in keyRegExp.allMatches(response.body)) {
        final key = _unescapeXml(match.group(1) ?? '');
        if (key.isEmpty || key == normalizedPrefix) continue;
        if (!key.startsWith(normalizedPrefix)) continue;
        final remaining = key.substring(normalizedPrefix.length);
        final slashIdx = remaining.indexOf('/');
        if (slashIdx > 0) {
          prefixes.add(normalizedPrefix + remaining.substring(0, slashIdx + 1));
        }
      }

      return prefixes.toList()..sort();
    } on S3Exception {
      rethrow;
    } catch (e) {
      throw S3Exception(
        http.Response('List prefixes error: $e', 0),
      );
    }
  }

  String _unescapeXml(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }

  /// Verifies write permission by uploading a small test object then deleting
  /// it. Throws on any failure (403, network error, etc.).
  Future<void> verifyWritable(String prefixPath) async {
    final normalizedPrefix = prefixPath.endsWith('/') || prefixPath.isEmpty
        ? prefixPath
        : '$prefixPath/';
    final testKey = '$normalizedPrefix.lumenpass-test-probe';

    final testData = Uint8List.fromList(
        utf8.encode('LumenPass S3 writability probe — safe to delete.'));
    await uploadObject(testKey, testData);
    try {
      await deleteObject(testKey);
    } catch (_) {
      // Best-effort cleanup; write already succeeded which is what matters.
    }
  }

  /// Creates a logical folder at [parentPrefix] by uploading a zero-byte
  /// object whose key ends with '/'. This is the S3 convention for folders.
  Future<void> createPrefix(String parentPrefix, String folderName) async {
    final normalizedParent = parentPrefix.isEmpty
        ? ''
        : (parentPrefix.endsWith('/') ? parentPrefix : '$parentPrefix/');
    final folderKey = '$normalizedParent$folderName/';
    await uploadObject(folderKey, Uint8List(0));
  }

  /// Uploads bytes to S3 using a manually signed PUT request via [SigV4].
  Future<void> uploadObject(
    String key,
    Uint8List data, {
    String? contentType,
  }) async {
    final config = _requireConfig;
    final host = config.host ?? 's3.${config.region}.amazonaws.com';
    final unencodedPath = '${config.bucketId}/$key';
    final uri = Uri.https(host, unencodedPath);

    final datetime = SigV4.generateDatetime();
    final credentialScope =
        SigV4.buildCredentialScope(datetime, config.region, _service);
    // Compute SHA-256 of the raw binary payload — never utf8.decode binary data
    // because KDBX (and other binary files) are not valid UTF-8.
    final payloadHash = sha256.convert(data).toString();

    final signedHeaders = {
      'content-type': contentType ?? 'application/octet-stream',
      'host': host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': datetime,
      if (config.sessionToken != null)
        'x-amz-security-token': config.sessionToken!,
    };

    // Build the canonical request manually — we pass the pre-computed
    // payload hash directly rather than going through buildCanonicalRequest,
    // which would hash it again and break the signature.
    final canonicalHeaders = SigV4.buildCanonicalHeaders(signedHeaders);
    final canonicalSignedHeaders =
        SigV4.buildCanonicalSignedHeaders(signedHeaders);
    final canonicalQueryString = SigV4.buildCanonicalQueryString({});

    final canonicalRequest = [
      'PUT',
      '/$unencodedPath',
      canonicalQueryString,
      canonicalHeaders,
      canonicalSignedHeaders,
      payloadHash,
    ].join('\n');

    final stringToSign = SigV4.buildStringToSign(
      datetime,
      credentialScope,
      SigV4.hashCanonicalRequest(canonicalRequest),
    );
    final signingKey = SigV4.calculateSigningKey(
        config.secretKey, datetime, config.region, _service);
    final signature = SigV4.calculateSignature(signingKey, stringToSign);

    final authorization = SigV4.buildAuthorizationHeader(
        config.accessKey, credentialScope, signedHeaders, signature);

    final putResponse = await http.put(
      uri,
      headers: {
        ...signedHeaders,
        'Authorization': authorization,
        'Content-Length': data.length.toString(),
      },
      body: data,
    );

    if (putResponse.statusCode != 200) {
      if (putResponse.statusCode == 403) {
        throw NoPermissionsException(putResponse);
      }
      throw S3Exception(putResponse);
    }
  }

  /// Returns the [DateTime] the object at [key] was last modified, or `null`
  /// if the object does not exist. Used by the sync layer to decide whether
  /// a download is needed (compare against local file mtime).
  Future<DateTime?> getObjectLastModified(String key) async {
    try {
      final result = await listObjects(prefix: key, maxKeys: 1);
      if (result.objects.isEmpty || result.objects.first.key != key) return null;
      return result.objects.first.lastModified;
    } catch (_) {
      return null;
    }
  }

  /// Deletes an object from S3 using a signed DELETE request.
  Future<void> deleteObject(String key) async {
    final config = _requireConfig;
    final host = config.host ?? 's3.${config.region}.amazonaws.com';
    final unencodedPath = '${config.bucketId}/$key';
    final uri = Uri.https(host, unencodedPath);

    final datetime = SigV4.generateDatetime();
    final credentialScope =
        SigV4.buildCredentialScope(datetime, config.region, _service);
    const emptyBody = '';
    final payloadHash = SigV4.hashCanonicalRequest(emptyBody);

    final signedHeaders = {
      'host': host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': datetime,
      if (config.sessionToken != null)
        'x-amz-security-token': config.sessionToken!,
    };

    final canonicalRequest = SigV4.buildCanonicalRequest(
      'DELETE',
      '/$unencodedPath',
      {},
      signedHeaders,
      emptyBody,
    );

    final stringToSign = SigV4.buildStringToSign(
      datetime,
      credentialScope,
      SigV4.hashCanonicalRequest(canonicalRequest),
    );
    final signingKey = SigV4.calculateSigningKey(
        config.secretKey, datetime, config.region, _service);
    final signature = SigV4.calculateSignature(signingKey, stringToSign);

    final authorization = SigV4.buildAuthorizationHeader(
        config.accessKey, credentialScope, signedHeaders, signature);

    final deleteResponse = await http.delete(
      uri,
      headers: {
        ...signedHeaders,
        'Authorization': authorization,
      },
    );

    if (deleteResponse.statusCode != 204 && deleteResponse.statusCode != 200) {
      if (deleteResponse.statusCode == 403) {
        throw NoPermissionsException(deleteResponse);
      }
      throw S3Exception(deleteResponse);
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  void _checkResponseError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    if (response.statusCode == 403) {
      throw NoPermissionsException(response);
    }
    throw S3Exception(response);
  }
}
