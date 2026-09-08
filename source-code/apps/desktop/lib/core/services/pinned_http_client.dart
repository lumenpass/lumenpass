import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

// -----------------------------------------------------------------------------
// SHA-1 certificate pinning for LumenPass cloud-service endpoints.
//
// Pinning prevents MITM attacks even when a trusted CA is compromised.
// Because dart:io's X509Certificate does not expose the raw public key,
// we pin the SHA-1 hash of the DER-encoded certificate rather than the
// SubjectPublicKeyInfo (SPKI). This is still effective — an attacker cannot
// produce a certificate with the same hash without the private key.
//
// ## How pinning works here
//
//  1. A custom SecurityContext (with no trusted roots) is used for pinned
//     hosts. This forces the TLS layer to invoke badCertificateCallback for
//     *every* connection to those hosts.
//  2. The callback validates certificate expiry and computes the SHA-1 hash
//     of the DER-encoded certificate bytes.
//  3. The hash is compared against the pinned set for the host.
//  4. Non-pinned hosts use the standard platform / OS trust store unchanged.
//
// ## Populating pin hashes
//
// To obtain the SHA-1 pin for an endpoint:
//
//   echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null \
//     | openssl x509 -outform der \
//     | openssl dgst -sha1 -binary \
//     | openssl enc -base64
//
// Add the resulting base64 string to the relevant host set below.
//
// ## Maintenance
//
// Certificate renewal produces a new SHA-1 hash. Most providers rotate
// certificates every 90 days. Keep both old and new hashes during rotation.
// -----------------------------------------------------------------------------

/// SHA-1 certificate pin hashes for LumenPass cloud-service endpoints.
///
/// Each entry maps a hostname to the set of valid SHA-1 hashes of the
/// DER-encoded certificate. When this map has no hosts with non-empty pin
/// sets, pinning is inactive and all traffic uses standard platform validation.
const _kPinnedHashes = <String, Set<String>>{
  // Dropbox API
  'api.dropboxapi.com': <String>{
    // TODO(pinning): populate with actual SHA-1 hash
  },
  'content.dropboxapi.com': <String>{
    // TODO(pinning): populate with actual SHA-1 hash
  },

  // Microsoft Graph / OneDrive
  'graph.microsoft.com': <String>{
    // TODO(pinning): populate with actual SHA-1 hash
  },
  'login.microsoftonline.com': <String>{
    // TODO(pinning): populate with actual SHA-1 hash
  },

  // Google APIs (Google Drive)
  'www.googleapis.com': <String>{
    // TODO(pinning): populate with actual SHA-1 hash
  },
  'accounts.google.com': <String>{
    // TODO(pinning): populate with actual SHA-1 hash
  },

  // AWS S3 regional endpoints
  's3.amazonaws.com': <String>{
    // TODO(pinning): populate with actual SHA-1 hash
  },
};

bool get isCertificatePinningActive {
  return _kPinnedHashes.values.any((s) => s.isNotEmpty);
}

class PinningHttpOverrides extends HttpOverrides {
  HttpClient? _pinnedClient;
  HttpClient? _defaultClient;

  HttpClient get _pinned {
    _pinnedClient ??= _buildPinnedClient();
    return _pinnedClient!;
  }

  HttpClient get _default {
    _defaultClient ??= HttpClient();
    return _defaultClient!;
  }

  HttpClient _buildPinnedClient() {
    final ctx = SecurityContext(withTrustedRoots: false);
    final client = HttpClient(context: ctx);
    client.badCertificateCallback = _validatePinnedCert;
    debugPrint(
      '[CertPin] Pinning enabled for ${_kPinnedHashes.keys.length} host(s).',
    );
    return client;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    if (!isCertificatePinningActive) {
      if (kDebugMode) {
        debugPrint(
          '[CertPin] No pin hashes configured — pinning inactive. '
          'Standard platform validation in use.',
        );
      }
      return super.createHttpClient(context);
    }

    return _RoutingHttpClient._(this);
  }

  bool _isPinnedHost(String host) {
    final pins = _kPinnedHashes[host];
    if (pins != null && pins.isNotEmpty) return true;
    if (host.endsWith('.s3.amazonaws.com') ||
        host.endsWith('.s3.us-gov.amazonaws.com')) {
      final s3pins = _kPinnedHashes['s3.amazonaws.com'];
      return s3pins != null && s3pins.isNotEmpty;
    }
    return false;
  }

  bool _validatePinnedCert(X509Certificate cert, String host, int port) {
    final now = DateTime.now().toUtc();
    if (now.isBefore(cert.startValidity) || now.isAfter(cert.endValidity)) {
      debugPrint('[CertPin] REJECTED $host — outside validity window.');
      return false;
    }

    final certHash = base64.encode(cert.sha1);
    final pins = _kPinnedHashes[host] ??
        _kPinnedHashes['s3.amazonaws.com'] ??
        <String>{};

    final isPinned = pins.contains(certHash);
    if (!isPinned) {
      debugPrint(
        '[CertPin] REJECTED $host — SHA-1 $certHash not in pinned set. '
        'This may indicate a MITM attack or a routine certificate renewal.',
      );
    }
    return isPinned;
  }
}

// -----------------------------------------------------------------------------
// Routing HttpClient
// -----------------------------------------------------------------------------

class _RoutingHttpClient implements HttpClient {
  _RoutingHttpClient._(this._overrides);

  final PinningHttpOverrides _overrides;

  HttpClient _clientFor(String host) =>
      _overrides._isPinnedHost(host) ? _overrides._pinned : _overrides._default;

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) {
    return _clientFor(host).open(method, host, port, path);
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    return _clientFor(url.host).openUrl(method, url);
  }

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _clientFor(host).get(host, port, path);

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      _clientFor(url.host).getUrl(url);

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _clientFor(host).post(host, port, path);

  @override
  Future<HttpClientRequest> postUrl(Uri url) =>
      _clientFor(url.host).postUrl(url);

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _clientFor(host).put(host, port, path);

  @override
  Future<HttpClientRequest> putUrl(Uri url) =>
      _clientFor(url.host).putUrl(url);

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _clientFor(host).delete(host, port, path);

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) =>
      _clientFor(url.host).deleteUrl(url);

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _clientFor(host).head(host, port, path);

  @override
  Future<HttpClientRequest> headUrl(Uri url) =>
      _clientFor(url.host).headUrl(url);

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _clientFor(host).patch(host, port, path);

  @override
  Future<HttpClientRequest> patchUrl(Uri url) =>
      _clientFor(url.host).patchUrl(url);

  // -- Property delegation ---------------------------------------------------

  @override
  bool get autoUncompress => _overrides._default.autoUncompress;
  @override
  set autoUncompress(bool value) {
    _overrides._default.autoUncompress = value;
    _overrides._pinnedClient?.autoUncompress = value;
  }

  @override
  Duration? get connectionTimeout => _overrides._default.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) {
    _overrides._default.connectionTimeout = value;
    _overrides._pinnedClient?.connectionTimeout = value;
  }

  @override
  Duration get idleTimeout => _overrides._default.idleTimeout;
  @override
  set idleTimeout(Duration value) {
    _overrides._default.idleTimeout = value;
    _overrides._pinnedClient?.idleTimeout = value;
  }

  @override
  int? get maxConnectionsPerHost =>
      _overrides._default.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) {
    _overrides._default.maxConnectionsPerHost = value;
    _overrides._pinnedClient?.maxConnectionsPerHost = value;
  }

  @override
  set findProxy(String Function(Uri url)? f) {
    _overrides._default.findProxy = f;
    _overrides._pinnedClient?.findProxy = f;
  }

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) {
    _overrides._default.authenticate = f;
    _overrides._pinnedClient?.authenticate = f;
  }

  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
        f,
  ) {
    _overrides._default.authenticateProxy = f;
    _overrides._pinnedClient?.authenticateProxy = f;
  }

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) {
    // Intentionally a no-op: the routing client owns certificate validation.
  }

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) {
    _overrides._default.addCredentials(url, realm, credentials);
  }

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) {
    _overrides._default.addProxyCredentials(host, port, realm, credentials);
  }

  @override
  set userAgent(String? value) {
    _overrides._default.userAgent = value;
  }

  @override
  String? get userAgent => _overrides._default.userAgent;

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )? f,
  ) {
    _overrides._default.connectionFactory = f;
    _overrides._pinnedClient?.connectionFactory = f;
  }

  @override
  set keyLog(Function(String line)? callback) {
    _overrides._default.keyLog = callback;
    _overrides._pinnedClient?.keyLog = callback;
  }

  @override
  void close({bool force = false}) {
    _overrides._default.close(force: force);
    _overrides._pinnedClient?.close(force: force);
  }
}
