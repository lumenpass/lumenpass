import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

@immutable
class LatestRelease {
  const LatestRelease({
    required this.platform,
    required this.version,
    required this.changeLog,
    required this.downloadUrl,
  });

  final String platform;
  final String version;
  final String changeLog;
  final String downloadUrl;
}

class ReleaseApiException implements Exception {
  const ReleaseApiException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ReleaseApiException($code): $message';
}

/// Thin HTTP client for the public release-metadata endpoint exposed by the
/// LumenPass backend at `<BACKEND_API_URL>/<platform>/release/latest`.
///
/// The endpoint is unauthenticated.
class ReleaseApiClient {
  ReleaseApiClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        _baseUrl = (baseUrl ?? _defaultBaseUrl).trim() {
    if (!kDebugMode && _baseUrl.isNotEmpty && !_baseUrl.startsWith('https://')) {
      throw StateError(
        'BACKEND_API_URL must use HTTPS in production builds. Got: $_baseUrl',
      );
    }
  }

  static const String _defaultBaseUrl =
      String.fromEnvironment('BACKEND_API_URL');

  final http.Client _http;
  final String _baseUrl;

  bool get isConfigured => _baseUrl.isNotEmpty;

  Uri _uri(String path) {
    if (!isConfigured) {
      throw const ReleaseApiException(
        'not_configured',
        'BACKEND_API_URL is not set. Configure it in dart_defines.local.json.',
      );
    }
    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final suffix = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$suffix');
  }

  Future<LatestRelease> fetchLatest({required String platform}) async {
    final encoded = Uri.encodeComponent(platform);
    final url = _uri('/$encoded/release/latest');
    developer.log(
      'GET $url (platform=$platform)',
      name: 'release_api',
    );
    http.Response response;
    try {
      response = await _http
          .get(
            url,
            headers: const <String, String>{
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));
    } on SocketException catch (err) {
      developer.log(
        'GET $url failed: network error: ${err.message}',
        name: 'release_api',
        error: err,
      );
      throw ReleaseApiException('network', 'Network error: ${err.message}');
    } on http.ClientException catch (err) {
      developer.log(
        'GET $url failed: client error: ${err.message}',
        name: 'release_api',
        error: err,
      );
      throw ReleaseApiException('network', err.message);
    } catch (err) {
      developer.log(
        'GET $url failed: $err',
        name: 'release_api',
        error: err,
      );
      throw ReleaseApiException('unknown', err.toString());
    }

    developer.log(
      'GET $url -> ${response.statusCode} (${response.body.length} bytes)',
      name: 'release_api',
    );

    if (response.statusCode == 404) {
      throw const ReleaseApiException(
        'not_found',
        'No release information available for this platform yet.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReleaseApiException(
        'http_${response.statusCode}',
        'Unexpected response (${response.statusCode}).',
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const ReleaseApiException(
        'bad_response',
        'Server returned malformed JSON.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const ReleaseApiException(
        'bad_response',
        'Server returned an unexpected payload.',
      );
    }

    final platformValue = decoded['platform'];
    final versionValue = decoded['version'];
    final changeLogValue = decoded['changeLog'] ?? decoded['change_log'];
    final downloadUrlValue = decoded['downloadUrl'] ?? decoded['download_url'];

    if (platformValue is! String ||
        versionValue is! String ||
        changeLogValue is! String ||
        downloadUrlValue is! String ||
        platformValue.isEmpty ||
        versionValue.isEmpty) {
      throw const ReleaseApiException(
        'bad_response',
        'Server response is missing required fields.',
      );
    }

    return LatestRelease(
      platform: platformValue,
      version: versionValue,
      changeLog: changeLogValue,
      downloadUrl: (downloadUrlValue).trim(),
    );
  }

  void close() => _http.close();
}

/// Compares two LumenPass version strings of the form `1.0.0+1`.
///
/// Returns a negative number if [a] < [b], zero if equal, positive otherwise.
/// Build numbers (after `+`) are compared numerically when both sides expose
/// them. Missing build numbers are treated as `0`.
int compareReleaseVersions(String a, String b) {
  final parsedA = _parseReleaseVersion(a);
  final parsedB = _parseReleaseVersion(b);
  for (var i = 0; i < 3; i++) {
    final diff = parsedA.parts[i] - parsedB.parts[i];
    if (diff != 0) return diff;
  }
  return parsedA.build - parsedB.build;
}

/// Formats a LumenPass version string of the form `1.0.1+1` for display,
/// turning the `+` build separator into a human-readable `Build` label, e.g.
/// `1.0.1+1` becomes `1.0.1 Build 1`. A missing build number is omitted.
String formatReleaseVersion(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final plusIndex = trimmed.indexOf('+');
  if (plusIndex < 0) return trimmed;
  final core = trimmed.substring(0, plusIndex).trim();
  final build = trimmed.substring(plusIndex + 1).trim();
  if (core.isEmpty) return trimmed;
  if (build.isEmpty) return core;
  return '$core Build $build';
}

class _ParsedVersion {
  const _ParsedVersion(this.parts, this.build);
  final List<int> parts;
  final int build;
}

_ParsedVersion _parseReleaseVersion(String raw) {
  final trimmed = raw.trim();
  final plusIndex = trimmed.indexOf('+');
  final core = plusIndex >= 0 ? trimmed.substring(0, plusIndex) : trimmed;
  final buildRaw = plusIndex >= 0 ? trimmed.substring(plusIndex + 1) : '';
  final segments = core.split('.');
  final parts = <int>[0, 0, 0];
  for (var i = 0; i < 3; i++) {
    if (i < segments.length) {
      parts[i] = int.tryParse(segments[i].replaceAll(RegExp(r'[^0-9]'), '')) ??
          0;
    }
  }
  final build =
      int.tryParse(buildRaw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  return _ParsedVersion(parts, build);
}
