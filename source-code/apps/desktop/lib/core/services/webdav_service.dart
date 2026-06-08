import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Configuration model
// ---------------------------------------------------------------------------

/// Immutable connection configuration for a WebDAV storage provider.
///
/// Mirrors the secret-handling conventions used by the OAuth-based providers
/// (OneDrive / Dropbox): the [password] is treated as a sensitive field and is
/// never written to logs or `toString()` output.
@immutable
class WebDavConfig {
  const WebDavConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.rootPath,
  });

  /// WebDAV server hostname or base URL (e.g. `dav.example.com` or
  /// `https://example.com/remote.php/dav/files/me`).
  final String host;

  /// Server port (1–65535).
  final int port;

  /// Authentication user name.
  final String username;

  /// Authentication password — treated as a secret.
  final String password;

  /// Base directory on the server used as the storage root (e.g. `/lumenpass`).
  final String rootPath;

  WebDavConfig copyWith({
    String? host,
    int? port,
    String? username,
    String? password,
    String? rootPath,
  }) {
    return WebDavConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      rootPath: rootPath ?? this.rootPath,
    );
  }

  /// Serialises the non-secret fields. The [password] is intentionally
  /// excluded so callers persist it separately in the secret store.
  Map<String, dynamic> toJsonWithoutSecret() => <String, dynamic>{
        'host': host,
        'port': port,
        'username': username,
        'rootPath': rootPath,
      };

  /// Rebuilds a config from the persisted non-secret JSON plus the secret
  /// [password] loaded from the secure store.
  factory WebDavConfig.fromJson(
    Map<String, dynamic> json, {
    required String password,
  }) {
    return WebDavConfig(
      host: (json['host'] as String?) ?? '',
      port: (json['port'] as num?)?.toInt() ?? 0,
      username: (json['username'] as String?) ?? '',
      password: password,
      rootPath: (json['rootPath'] as String?) ?? '/',
    );
  }

  /// Display label for the connected account, e.g. `me@dav.example.com`.
  String get accountLabel {
    final h = WebDavConfig.normalizeHostForDisplay(host);
    return username.isEmpty ? h : '$username@$h';
  }

  @override
  String toString() =>
      'WebDavConfig(host: $host, port: $port, username: $username, '
      'rootPath: $rootPath, password: ••••••)';

  /// Strips scheme/path so a raw host can be shown compactly in the UI.
  static String normalizeHostForDisplay(String raw) {
    var value = raw.trim();
    value = value.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '');
    final slash = value.indexOf('/');
    if (slash >= 0) value = value.substring(0, slash);
    return value;
  }
}

/// Result of validating a [WebDavConfig]. Field-level errors are keyed by the
/// field name so a form can render them inline; [isValid] is the overall gate.
@immutable
class WebDavConfigValidation {
  const WebDavConfigValidation(this.errors);

  /// Map of field name (`host`, `port`, `username`, `password`, `rootPath`) to
  /// a human-readable error message. Empty when the config is valid.
  final Map<String, String> errors;

  bool get isValid => errors.isEmpty;

  String? operator [](String field) => errors[field];
}

// ---------------------------------------------------------------------------
// Listing models (mirror OneDriveFolder / OneDriveFile)
// ---------------------------------------------------------------------------

class WebDavFolder {
  const WebDavFolder({required this.id, required this.name, this.path});

  /// For WebDAV the "id" is the absolute server-relative collection path.
  final String id;
  final String name;
  final String? path;
}

class WebDavFile {
  const WebDavFile({
    required this.id,
    required this.name,
    this.path,
    this.size,
    this.lastModified,
  });

  /// For WebDAV the "id" is the absolute server-relative resource path.
  final String id;
  final String name;
  final String? path;
  final int? size;
  final DateTime? lastModified;
}

// ---------------------------------------------------------------------------
// WebDavService
// ---------------------------------------------------------------------------

/// Low-level WebDAV client. Singleton so it can be shared by [BackupService]
/// and `CloudSyncService` exactly like [OneDriveService].
///
/// Authentication uses HTTP Basic over the configured base URL. All remote
/// paths are resolved relative to [WebDavConfig.rootPath].
class WebDavService {
  WebDavService._();
  static final WebDavService instance = WebDavService._();

  static const String _logTag = '[WebDAV]';
  static const Duration _timeout = Duration(seconds: 20);

  WebDavConfig? _config;
  http.Client _client = http.Client();

  /// The active configuration, or `null` when disconnected.
  WebDavConfig? get config => _config;

  bool get isConnected => _config != null;

  /// Override the HTTP client (tests only).
  @visibleForTesting
  set debugClient(http.Client client) => _client = client;

  // ── Validation ─────────────────────────────────────────────────────────────

  /// Validates a [WebDavConfig], returning field-keyed errors.
  ///
  /// Rules:
  ///  * `host` — required, non-empty (scheme/path tolerated).
  ///  * `port` — required, integer in 1–65535.
  ///  * `username` — required, non-empty.
  ///  * `password` — required, non-empty.
  ///  * `rootPath` — normalised; must resolve to a non-empty path.
  static WebDavConfigValidation validateConfig(WebDavConfig config) {
    final errors = <String, String>{};

    if (config.host.trim().isEmpty) {
      errors['host'] = 'Server host is required.';
    } else if (WebDavConfig.normalizeHostForDisplay(config.host).isEmpty) {
      errors['host'] = 'Enter a valid host or URL.';
    }

    if (config.port < 1 || config.port > 65535) {
      errors['port'] = 'Port must be between 1 and 65535.';
    }

    if (config.username.trim().isEmpty) {
      errors['username'] = 'Username is required.';
    }

    if (config.password.isEmpty) {
      errors['password'] = 'Password is required.';
    }

    final normalizedRoot = normalizeRootPath(config.rootPath);
    if (normalizedRoot.isEmpty) {
      errors['rootPath'] = 'Root path is required.';
    }

    return WebDavConfigValidation(errors);
  }

  /// Normalises a user-entered root path to a leading-slash, no-trailing-slash
  /// absolute form. `''` / `'/'` collapse to `'/'`.
  static String normalizeRootPath(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '/';
    // Collapse backslashes and duplicate separators.
    value = value.replaceAll('\\', '/');
    value = value.replaceAll(RegExp(r'/+'), '/');
    if (!value.startsWith('/')) value = '/$value';
    if (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  // ── Connection ───────────────────────────────────────────────────────────────

  /// Stores [config] in memory after validating it and verifying the server is
  /// reachable with the given credentials and that [WebDavConfig.rootPath] is
  /// accessible (creating it when missing). Throws on any failure.
  Future<void> connect(WebDavConfig config) async {
    final validation = validateConfig(config);
    if (!validation.isValid) {
      throw Exception(
        'Invalid WebDAV configuration: ${validation.errors.values.first}',
      );
    }

    final normalized = config.copyWith(rootPath: normalizeRootPath(config.rootPath));
    _config = normalized;
    try {
      await testConnection(normalized);
      // Ensure the storage root exists so subsequent uploads succeed.
      await _ensureCollection(normalized.rootPath, normalized);
      _log('connected to ${normalized.accountLabel} root=${normalized.rootPath}');
    } catch (e) {
      _config = null;
      rethrow;
    }
  }

  /// Restores a previously persisted configuration without hitting the network.
  void restore(WebDavConfig config) {
    _config = config.copyWith(rootPath: normalizeRootPath(config.rootPath));
    _log('config restored for ${_config!.accountLabel}');
  }

  void disconnect() {
    _config = null;
    _log('disconnected');
  }

  /// Verifies host, port, credentials and root-path accessibility for
  /// [override] (or the active config). Throws a descriptive [Exception] on
  /// failure; resolves normally when the server is reachable and authorised.
  Future<void> testConnection([WebDavConfig? override]) async {
    final cfg = override ?? _config;
    if (cfg == null) {
      throw Exception('No WebDAV configuration to test.');
    }
    final validation = validateConfig(cfg);
    if (!validation.isValid) {
      throw Exception(validation.errors.values.first);
    }

    final uri = _resolve(cfg.rootPath, cfg);
    final response = await _request(
      'PROPFIND',
      uri,
      cfg,
      headers: <String, String>{'Depth': '0'},
    );

    final status = response.statusCode;
    if (status == 401 || status == 403) {
      throw Exception(
        'Authentication failed (HTTP $status). Check the username and password.',
      );
    }
    // 207 = Multi-Status (success). 404 means the root is missing but the
    // server/credentials are valid — connect() creates it afterwards.
    if (status == 207 || status == 200 || status == 404) {
      return;
    }
    if (status == 405 || status == 501) {
      throw Exception(
        'The server does not appear to support WebDAV (HTTP $status).',
      );
    }
    throw Exception('Unexpected server response (HTTP $status).');
  }

  // ── Listing ──────────────────────────────────────────────────────────────────

  /// Lists collections (folders) directly under [parentPath] (defaults to the
  /// configured root). Paths are server-relative and absolute.
  Future<List<WebDavFolder>> listFolders({String? parentPath}) async {
    final cfg = _requireConfig();
    final dir = _absolute(parentPath ?? cfg.rootPath, cfg);
    final entries = await _propfindChildren(dir, cfg);
    return entries
        .where((e) => e.isCollection)
        .map((e) => WebDavFolder(id: e.path, name: e.name, path: e.path))
        .toList();
  }

  /// Lists files under [parentPath] (defaults to root), optionally filtered by
  /// a filename [extension] such as `.kdbx`.
  Future<List<WebDavFile>> listFiles({
    String? parentPath,
    String? extension,
  }) async {
    final cfg = _requireConfig();
    final dir = _absolute(parentPath ?? cfg.rootPath, cfg);
    final entries = await _propfindChildren(dir, cfg);
    var files = entries
        .where((e) => !e.isCollection)
        .map((e) => WebDavFile(
              id: e.path,
              name: e.name,
              path: e.path,
              size: e.size,
              lastModified: e.lastModified,
            ))
        .toList();
    if (extension != null) {
      files = files.where((f) => f.name.toLowerCase().endsWith(extension)).toList();
    }
    return files;
  }

  // ── File operations ──────────────────────────────────────────────────────────

  /// Downloads the resource at server-relative [remotePath].
  Future<Uint8List> downloadFile(String remotePath) async {
    final cfg = _requireConfig();
    final uri = _resolve(remotePath, cfg);
    _log('GET ${_redactPath(remotePath)}');
    final response = await _request('GET', uri, cfg);
    if (response.statusCode != 200) {
      throw Exception(
        'Download failed (HTTP ${response.statusCode}) for ${_redactPath(remotePath)}',
      );
    }
    return Uint8List.fromList(response.bodyBytes);
  }

  /// Uploads [bytes] to server-relative [remotePath], overwriting any existing
  /// resource. Parent collections are created as needed.
  Future<void> uploadBytes(Uint8List bytes, String remotePath) async {
    final cfg = _requireConfig();
    await _ensureCollection(p.url.dirname(_absolute(remotePath, cfg)), cfg);
    final uri = _resolve(remotePath, cfg);
    _log('PUT ${_redactPath(remotePath)} (${bytes.length} bytes)');
    final response = await _request(
      'PUT',
      uri,
      cfg,
      headers: <String, String>{'Content-Type': 'application/octet-stream'},
      body: bytes,
    );
    final status = response.statusCode;
    if (status != 200 && status != 201 && status != 204) {
      throw Exception(
        'Upload failed (HTTP $status) for ${_redactPath(remotePath)}',
      );
    }
  }

  /// Uploads a new file named [fileName] into [folderPath], returning the
  /// server-relative path of the created resource (used as the cloudFileId).
  Future<String> uploadNewFile(
    Uint8List bytes,
    String folderPath,
    String fileName,
  ) async {
    final cfg = _requireConfig();
    final dir = _absolute(folderPath, cfg);
    final remotePath = p.url.join(dir, fileName);
    await uploadBytes(bytes, remotePath);
    return remotePath;
  }

  /// Deletes the resource (or collection) at [remotePath].
  Future<void> deleteFile(String remotePath) async {
    final cfg = _requireConfig();
    final uri = _resolve(remotePath, cfg);
    _log('DELETE ${_redactPath(remotePath)}');
    final response = await _request('DELETE', uri, cfg);
    final status = response.statusCode;
    if (status != 200 && status != 204 && status != 404) {
      throw Exception(
        'Delete failed (HTTP $status) for ${_redactPath(remotePath)}',
      );
    }
  }

  /// Returns the last-modified time of [remotePath], or `null` when unknown.
  Future<DateTime?> getFileModifiedTime(String remotePath) async {
    final cfg = _requireConfig();
    final uri = _resolve(remotePath, cfg);
    final response = await _request(
      'PROPFIND',
      uri,
      cfg,
      headers: <String, String>{'Depth': '0'},
    );
    if (response.statusCode != 207 && response.statusCode != 200) {
      return null;
    }
    final entries = _parseMultiStatus(response.body, _basePathFor(cfg));
    if (entries.isEmpty) return null;
    return entries.first.lastModified;
  }

  /// Creates a collection named [name] inside [parentPath], returning a
  /// [WebDavFolder] whose id is the new collection's server-relative path.
  Future<WebDavFolder> createFolder(String name, {String? parentPath}) async {
    final cfg = _requireConfig();
    final parent = _absolute(parentPath ?? cfg.rootPath, cfg);
    final folderPath = p.url.join(parent, name);
    await _ensureCollection(folderPath, cfg);
    return WebDavFolder(id: folderPath, name: name, path: folderPath);
  }

  // ── Browsing with an explicit (possibly-unsaved) config ──────────────────────
  //
  // These power the GUI folder picker after the user has run "Test" but before
  // the configuration is saved/connected. They operate against the whole server
  // (root `/`) so the user can navigate freely, and never mutate the singleton
  // [config] state.

  /// Lists collections under [parentPath] (server root when null) using the
  /// supplied [config] directly. The config's own root path is ignored so the
  /// entire server is browsable.
  Future<List<WebDavFolder>> browseFolders(
    WebDavConfig config, {
    String? parentPath,
  }) async {
    final cfg = config.copyWith(rootPath: '/');
    final dir = _absolute(parentPath ?? '/', cfg);
    final entries = await _propfindChildren(dir, cfg);
    return entries
        .where((e) => e.isCollection)
        .map((e) => WebDavFolder(id: e.path, name: e.name, path: e.path))
        .toList();
  }

  /// Creates a collection named [name] under [parentPath] using [config]
  /// directly. Returns the new collection's server-relative path.
  Future<WebDavFolder> createFolderIn(
    WebDavConfig config,
    String name, {
    String? parentPath,
  }) async {
    final cfg = config.copyWith(rootPath: '/');
    final parent = _absolute(parentPath ?? '/', cfg);
    final folderPath = p.url.join(parent, name);
    await _ensureCollection(folderPath, cfg);
    return WebDavFolder(id: folderPath, name: name, path: folderPath);
  }

  /// Confirms the configured [WebDavConfig.rootPath] is both readable and
  /// writable for the supplied [config] by writing a small probe file, reading
  /// it back, then deleting it. Always attempts to clean up the probe file,
  /// even on failure. Throws a descriptive [Exception] when the path is not a
  /// usable read/write destination.
  Future<void> verifyWritable(WebDavConfig config) async {
    final cfg = config.copyWith(rootPath: normalizeRootPath(config.rootPath));

    // Make sure the target collection exists before probing it.
    await _ensureCollection(cfg.rootPath, cfg);

    final fileName =
        '.lumenpass-write-test-${DateTime.now().millisecondsSinceEpoch}.txt';
    final remotePath = p.url.join(cfg.rootPath, fileName);
    final uri = _resolve(remotePath, cfg);
    final payload = utf8.encode(
      'LumenPass WebDAV write test ${DateTime.now().toIso8601String()}',
    );

    // 1. Write the probe file.
    final put = await _request(
      'PUT',
      uri,
      cfg,
      headers: <String, String>{'Content-Type': 'text/plain'},
      body: payload,
    );
    final putStatus = put.statusCode;
    if (putStatus == 401 || putStatus == 403) {
      throw Exception(
        'The selected path is not writable with these credentials '
        '(HTTP $putStatus).',
      );
    }
    if (putStatus == 404 || putStatus == 409) {
      throw Exception(
        'The selected path does not accept new files (HTTP $putStatus).',
      );
    }
    if (putStatus != 200 && putStatus != 201 && putStatus != 204) {
      throw Exception(
        'Could not write to the selected path (HTTP $putStatus).',
      );
    }

    // 2. Read the probe file back to confirm the path is also readable.
    try {
      final get = await _request('GET', uri, cfg);
      if (get.statusCode != 200) {
        throw Exception(
          'The selected path is not readable (HTTP ${get.statusCode}).',
        );
      }
    } finally {
      // 3. Silently remove the probe file regardless of the read outcome.
      await _silentDelete(uri, cfg);
    }
  }

  Future<void> _silentDelete(Uri uri, WebDavConfig cfg) async {
    try {
      await _request('DELETE', uri, cfg);
    } catch (_) {
      // Best-effort cleanup — ignore failures so a transient delete error
      // doesn't block an otherwise-successful write check.
    }
  }

  // ── Internal helpers ─────────────────────────────────────────────────────────

  WebDavConfig _requireConfig() {
    final cfg = _config;
    if (cfg == null) {
      throw Exception('Not connected. Call connect() first.');
    }
    return cfg;
  }

  /// Resolves a [path] (which may be absolute server-relative or relative to
  /// the configured root) to an absolute server-relative path.
  String _absolute(String path, WebDavConfig cfg) {
    final root = normalizeRootPath(cfg.rootPath);
    var value = path.trim().replaceAll('\\', '/');
    if (value.isEmpty) return root;
    if (value.startsWith('/')) {
      // Already absolute on the server.
      value = value.replaceAll(RegExp(r'/+'), '/');
      if (value.length > 1 && value.endsWith('/')) {
        value = value.substring(0, value.length - 1);
      }
      return value;
    }
    final joined = root == '/' ? '/$value' : '$root/$value';
    return joined.replaceAll(RegExp(r'/+'), '/');
  }

  /// Builds the absolute request [Uri] for a server-relative [path].
  Uri _resolve(String path, WebDavConfig cfg) {
    final base = _baseUri(cfg);
    final abs = _absolute(path, cfg);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    // Encode each segment so spaces / unicode resolve correctly.
    final encoded = abs
        .split('/')
        .map((s) => s.isEmpty ? s : Uri.encodeComponent(s))
        .join('/');
    return base.replace(path: '$basePath$encoded');
  }

  /// The server origin (scheme + host + port), honouring a scheme/path baked
  /// into [WebDavConfig.host].
  Uri _baseUri(WebDavConfig cfg) {
    var raw = cfg.host.trim();
    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(raw);
    if (!hasScheme) {
      // Default to https unless a plaintext port is clearly requested.
      final scheme = cfg.port == 80 ? 'http' : 'https';
      raw = '$scheme://$raw';
    }
    final parsed = Uri.parse(raw);
    return parsed.replace(port: cfg.port, path: parsed.path);
  }

  /// The server-relative base path baked into [WebDavConfig.host] (e.g.
  /// `/remote.php/dav/files/me`), used to strip prefixes from PROPFIND hrefs.
  String _basePathFor(WebDavConfig cfg) {
    final path = _baseUri(cfg).path;
    if (path.isEmpty || path == '/') return '';
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }

  String _authHeader(WebDavConfig cfg) {
    final token = base64.encode(utf8.encode('${cfg.username}:${cfg.password}'));
    return 'Basic $token';
  }

  Future<http.Response> _request(
    String method,
    Uri uri,
    WebDavConfig cfg, {
    Map<String, String>? headers,
    List<int>? body,
  }) async {
    final request = http.Request(method, uri);
    request.headers['Authorization'] = _authHeader(cfg);
    request.headers['Accept'] = '*/*';
    if (headers != null) request.headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      return http.Response.fromStream(streamed);
    } on TimeoutException {
      throw Exception('The WebDAV server did not respond in time.');
    }
  }

  /// Issues `MKCOL` for [collectionPath] and every missing ancestor under the
  /// configured root. Existing collections (405) are treated as success.
  Future<void> _ensureCollection(String collectionPath, WebDavConfig cfg) async {
    final abs = _absolute(collectionPath, cfg);
    final root = normalizeRootPath(cfg.rootPath);
    // Build the list of ancestor paths from root → target.
    final segments = abs
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    var current = '';
    for (final segment in segments) {
      current = '$current/$segment';
      // Skip ancestors above the root we don't own.
      if (root != '/' && !'$current/'.startsWith('$root/') && current != root) {
        continue;
      }
      await _mkcol(current, cfg);
    }
  }

  Future<void> _mkcol(String path, WebDavConfig cfg) async {
    final uri = _resolve(path, cfg);
    final response = await _request('MKCOL', uri, cfg);
    final status = response.statusCode;
    // 201 created, 405 already exists, 301 redirect to existing collection.
    if (status == 201 || status == 405 || status == 301) return;
    if (status == 401 || status == 403) {
      throw Exception('Not authorised to create folder (HTTP $status).');
    }
    if (status == 409) {
      // Parent missing — surfaced to caller; _ensureCollection builds parents
      // first so this should not normally happen.
      throw Exception('Cannot create folder, parent missing (HTTP 409).');
    }
    // Some servers return 200 for an existing collection.
    if (status == 200) return;
    throw Exception('Failed to create folder (HTTP $status).');
  }

  Future<List<_WebDavEntry>> _propfindChildren(
    String dirPath,
    WebDavConfig cfg,
  ) async {
    final uri = _resolve(dirPath, cfg);
    final response = await _request(
      'PROPFIND',
      uri,
      cfg,
      headers: <String, String>{'Depth': '1'},
    );
    final status = response.statusCode;
    if (status == 404) return const <_WebDavEntry>[];
    if (status != 207 && status != 200) {
      throw Exception('Failed to list "$dirPath" (HTTP $status).');
    }
    final self = _absolute(dirPath, cfg);
    return _parseMultiStatus(response.body, _basePathFor(cfg))
        .where((e) => e.path != self)
        .toList();
  }

  /// Minimal, dependency-free parser for a WebDAV `multistatus` XML body.
  ///
  /// Extracts each `<response>`'s href, resourcetype (collection?), content
  /// length and last-modified. [basePath] is stripped from hrefs so the
  /// returned paths are root-relative on the server.
  List<_WebDavEntry> _parseMultiStatus(String xml, String basePath) {
    final entries = <_WebDavEntry>[];
    final responseRe = RegExp(
      r'<(?:\w+:)?response\b[^>]*>([\s\S]*?)</(?:\w+:)?response>',
      caseSensitive: false,
    );
    for (final match in responseRe.allMatches(xml)) {
      final block = match.group(1) ?? '';
      final href = _firstTag(block, 'href');
      if (href == null || href.isEmpty) continue;

      var path = href;
      // Hrefs may be absolute URLs or server-relative paths.
      final parsed = Uri.tryParse(href);
      if (parsed != null && parsed.hasScheme) {
        path = parsed.path;
      }
      path = Uri.decodeFull(path);
      if (basePath.isNotEmpty && path.startsWith(basePath)) {
        path = path.substring(basePath.length);
      }
      if (path.isEmpty) path = '/';
      final isCollection =
          RegExp(r'<(?:\w+:)?collection\b', caseSensitive: false).hasMatch(block);
      if (path.length > 1 && path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }

      final name = path == '/'
          ? '/'
          : Uri.decodeComponent(path.split('/').where((s) => s.isNotEmpty).last);

      final lengthStr = _firstTag(block, 'getcontentlength');
      final modifiedStr = _firstTag(block, 'getlastmodified');

      entries.add(_WebDavEntry(
        path: path,
        name: name,
        isCollection: isCollection,
        size: lengthStr != null ? int.tryParse(lengthStr.trim()) : null,
        lastModified: _parseHttpDate(modifiedStr),
      ));
    }
    return entries;
  }

  String? _firstTag(String block, String localName) {
    final re = RegExp(
      '<(?:\\w+:)?$localName\\b[^>]*>([\\s\\S]*?)</(?:\\w+:)?$localName>',
      caseSensitive: false,
    );
    final m = re.firstMatch(block);
    return m?.group(1);
  }

  DateTime? _parseHttpDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return HttpDate.parse(raw.trim()).toUtc();
    } catch (_) {
      return DateTime.tryParse(raw.trim());
    }
  }

  String _redactPath(String path) => path;

  void _log(String message) {
    debugPrint('$_logTag ${DateTime.now().toIso8601String()} $message');
  }
}

/// Parsed entry from a PROPFIND multistatus response.
class _WebDavEntry {
  const _WebDavEntry({
    required this.path,
    required this.name,
    required this.isCollection,
    this.size,
    this.lastModified,
  });

  final String path;
  final String name;
  final bool isCollection;
  final int? size;
  final DateTime? lastModified;
}