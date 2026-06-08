import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../features/vault/application/vault_item_type.dart';
import '../constants/kdbx_field_keys.dart';
import '../models/entry_field.dart';
import '../models/kdbx_entry.dart';
import '../repository/kdbx_repository.dart';
import 'vault_preferences.dart';

/// Result of an unlock attempt initiated by the browser extension.
class BridgeUnlockResult {
  const BridgeUnlockResult({required this.ok, this.error});

  final bool ok;
  final String? error;
}

/// Capabilities surfaced to the extension when the vault is locked.
class BridgeUnlockOptions {
  const BridgeUnlockOptions({
    required this.vaultReady,
    this.vaultName,
    this.hasPin = false,
    this.hasBiometric = false,
    this.biometricAvailable = false,
    this.lastMethod,
  });

  /// True when a database path is known and we can attempt an unlock.
  final bool vaultReady;
  final String? vaultName;
  final bool hasPin;
  final bool hasBiometric;
  final bool biometricAvailable;

  /// "biometric" | "pin" | "none"
  final String? lastMethod;
}

typedef BridgeUnlockOptionsProvider = Future<BridgeUnlockOptions> Function();
typedef BridgeUnlockPassword = Future<BridgeUnlockResult> Function(
    String password);
typedef BridgeUnlockPin = Future<BridgeUnlockResult> Function(String pin);
typedef BridgeUnlockBiometric = Future<BridgeUnlockResult> Function();

/// Local HTTP server that lets the LumenPass browser extension communicate
/// with the desktop app.  Listens on 127.0.0.1:19455 (loopback only).
///
/// No token authentication is required — any extension on this machine may
/// connect.  The vault's locked state acts as the natural gate: when the
/// vault is locked all data endpoints return empty results.
class BrowserExtensionService {
  BrowserExtensionService({
    required KdbxRepository repository,
    String Function()? getDomainSetting,
    List<DisabledAutofillDomain> Function()? getDisabledAutofillDomains,
    Future<void> Function(List<DisabledAutofillDomain> domains)?
        setDisabledAutofillDomains,
    void Function()? onFocusRequest,
    void Function()? onOpenNewItemRequest,
    void Function(String entryUuid)? onOpenEditItemRequest,
    Future<void> Function()? onAfterSave,
    BridgeUnlockOptionsProvider? getUnlockOptions,
    BridgeUnlockPassword? unlockWithPassword,
    BridgeUnlockPin? unlockWithPin,
    BridgeUnlockBiometric? unlockWithBiometric,
  })  : _repository = repository,
        _getDomainSetting = getDomainSetting ?? (() => 'default'),
        _getDisabledAutofillDomains =
            getDisabledAutofillDomains ?? (() => const []),
        _setDisabledAutofillDomains = setDisabledAutofillDomains,
        _onFocusRequest = onFocusRequest,
        _onOpenNewItemRequest = onOpenNewItemRequest,
        _onOpenEditItemRequest = onOpenEditItemRequest,
        _onAfterSave = onAfterSave,
        _getUnlockOptions = getUnlockOptions,
        _unlockWithPassword = unlockWithPassword,
        _unlockWithPin = unlockWithPin,
        _unlockWithBiometric = unlockWithBiometric;

  final String Function() _getDomainSetting;
  final List<DisabledAutofillDomain> Function() _getDisabledAutofillDomains;
  final Future<void> Function(List<DisabledAutofillDomain> domains)?
      _setDisabledAutofillDomains;
  final void Function()? _onFocusRequest;
  final void Function()? _onOpenNewItemRequest;
  final void Function(String entryUuid)? _onOpenEditItemRequest;
  final Future<void> Function()? _onAfterSave;
  final BridgeUnlockOptionsProvider? _getUnlockOptions;
  final BridgeUnlockPassword? _unlockWithPassword;
  final BridgeUnlockPin? _unlockWithPin;
  final BridgeUnlockBiometric? _unlockWithBiometric;

  static const int _port = 19455;
  static const String _host = '127.0.0.1';
  static const String _appVersion = '1.0.0';

  static const String _passkeyCredentialIdField = 'KPEX_PASSKEY_CREDENTIAL_ID';
  // Must match `KdbxFieldKeys.passkeyPrivateKeyPem` so the mobile AutoFill
  // reader and the desktop bridge agree on one custom-field label. Writing
  // under `_PBF` (previous value) left the new entry invisible to the mobile
  // passkey sync path, which looks for `_PEM` exactly.
  static const String _passkeyPrivateKeyField = 'KPEX_PASSKEY_PRIVATE_KEY_PEM';
  static const String _passkeyPrivateKeyLegacyField =
      'KPEX_PASSKEY_PRIVATE_KEY_PBF';
  static const String _passkeyRpIdField = 'KPEX_PASSKEY_RELYING_PARTY';
  static const String _passkeyUsernameField = 'KPEX_PASSKEY_USERNAME';
  static const String _passkeyUserHandleField = 'KPEX_PASSKEY_USER_HANDLE';

  final KdbxRepository _repository;

  HttpServer? _server;
  bool _running = false;

  bool get isRunning => _running;

  void _log(String message) {
    stdout.writeln(
      '[LumenPass Desktop Bridge ${DateTime.now().toIso8601String()}] $message',
    );
  }

  // ─── Lifecycle ──────────────────────────────────────────────────────────────

  /// Start the HTTP server. Retries several times on bind failure (e.g. the
  /// previous process is still releasing the port after a crash/restart).
  Future<void> start() async {
    if (_running) {
      _log('start skipped: server already running');
      return;
    }
    await _startServerWithRetry();
  }

  /// Verify the server is responsive. If it has stopped (e.g. after a system
  /// sleep/wake cycle or unexpected socket error), restart it.
  Future<void> ensureRunning() async {
    if (!_running) {
      _log('ensureRunning: server was not running – restarting');
      await _startServerWithRetry();
      return;
    }
    // Quick health check – if the server object exists but is no longer
    // accepting connections, force a restart.
    try {
      // Sending a test request to our own ping endpoint is the simplest
      // way to verify the loopback listener is still healthy after sleep.
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      try {
        final request = await client.get(_host, _port, '/ping');
        final response = await request.close().timeout(
          const Duration(seconds: 2),
        );
        if (response.statusCode == 200) {
          _log('ensureRunning: health check passed');
          client.close();
          return;
        }
      } finally {
        client.close();
      }
    } catch (_) {
      // Socket error – server is unreachable.
    }
    _log('ensureRunning: health check failed – force-restarting');
    await stop();
    await _startServerWithRetry();
  }

  /// Stop the HTTP server.
  Future<void> stop() async {
    _log('stopping server');
    _cancelRetry();
    await _server?.close(force: true);
    _server = null;
    _running = false;
  }

  // ─── Server ─────────────────────────────────────────────────────────────────

  Timer? _retryTimer;

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  static const int _maxBindRetries = 6;
  static const Duration _bindRetryBaseDelay = Duration(seconds: 2);

  Future<void> _startServerWithRetry() async {
    _cancelRetry();
    for (var attempt = 0; attempt < _maxBindRetries; attempt++) {
      try {
        await _startServer();
        if (_running) return;
      } catch (error) {
        _log('bind attempt ${attempt + 1}/$_maxBindRetries failed: $error');
      }
      if (attempt < _maxBindRetries - 1) {
        final delay = _bindRetryBaseDelay * (1 << attempt); // 2, 4, 8, 16, 32 s
        _log('retrying bind in ${delay.inSeconds}s');
        await Future<void>.delayed(delay);
      }
    }
    _log('all $_maxBindRetries bind attempts failed – server will not start');
    // Schedule one final retry after 60 s as a last resort.
    _retryTimer = Timer(const Duration(seconds: 60), () {
      _retryTimer = null;
      _startServerWithRetry();
    });
  }

  Future<void> _startServer() async {
    try {
      _server = await HttpServer.bind(
        InternetAddress(_host, type: InternetAddressType.IPv4),
        _port,
        shared: true,
      );
      _running = true;
      _log(
        'server listening on $_host:$_port, vaultOpen=${_repository.hasOpenDatabase}',
      );
      _server!.listen(
        _handleRequest,
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (error) {
      _running = false;
      _log('failed to bind server: $error');
      rethrow; // Let the retry loop handle it.
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _setCorsHeaders(request.response);

    // Pre-flight
    if (request.method == 'OPTIONS') {
      request.response
        ..statusCode = 204
        ..close();
      return;
    }

    final path = request.uri.path;
    _log(
      'request ${request.method} $path query=${request.uri.query} vaultOpen=${_repository.hasOpenDatabase}',
    );

    try {
      if (request.method == 'GET' && path == '/ping') {
        await _handlePing(request);
      } else if (request.method == 'POST' && path == '/auth') {
        await _handleAuth(request);
      } else if (request.method == 'GET' && path == '/search') {
        await _handleSearch(request);
      } else if (request.method == 'GET' &&
          path.startsWith('/entry/') &&
          path.length > '/entry/'.length) {
        await _handleGetEntry(request);
      } else if (request.method == 'GET' && path == '/vault-settings') {
        await _handleVaultSettings(request);
      } else if (request.method == 'POST' &&
          path == '/vault-settings/disabled-autofill-domains') {
        await _handleSaveDisabledAutofillDomains(request);
      } else if (request.method == 'GET' && path == '/categories') {
        await _handleCategories(request);
      } else if (request.method == 'POST' && path == '/passkey/create') {
        await _handleCreatePasskey(request);
      } else if (request.method == 'POST' && path == '/entry/create') {
        await _handleCreateEntry(request);
      } else if (request.method == 'POST' && path == '/note/create') {
        await _handleCreateNote(request);
      } else if (request.method == 'POST' && path == '/focus') {
        await _handleFocus(request);
      } else if (request.method == 'POST' && path == '/item/new') {
        await _handleOpenNewItem(request);
      } else if (request.method == 'POST' && path == '/item/edit') {
        await _handleOpenEditItem(request);
      } else if (request.method == 'POST' && path == '/item/delete') {
        await _handleDeleteItem(request);
      } else if (request.method == 'GET' && path == '/unlock/options') {
        await _handleUnlockOptions(request);
      } else if (request.method == 'POST' && path == '/unlock') {
        await _handleUnlockPassword(request);
      } else if (request.method == 'POST' && path == '/unlock/pin') {
        await _handleUnlockPin(request);
      } else if (request.method == 'POST' && path == '/unlock/biometric') {
        await _handleUnlockBiometric(request);
      } else {
        request.response
          ..statusCode = 404
          ..close();
      }
    } catch (error) {
      _log('request failed ${request.method} $path: $error');
      _respondJson(request.response, 500, {'error': 'Internal server error'});
    }
  }

  void _setCorsHeaders(HttpResponse response) {
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type');
  }

  // ─── Endpoint handlers ─────────────────────────────────────────────────────

  Future<void> _handlePing(HttpRequest request) async {
    _log('ping -> vaultOpen=${_repository.hasOpenDatabase}');
    _respondJson(request.response, 200, {
      'status': 'ok',
      'version': _appVersion,
      'vaultOpen': _repository.hasOpenDatabase,
    });
  }

  Future<void> _handleFocus(HttpRequest request) async {
    _log('focus request received');
    _onFocusRequest?.call();
    _respondJson(request.response, 200, {'ok': true});
  }

  Future<void> _handleOpenNewItem(HttpRequest request) async {
    _log('open new item request received');
    _onFocusRequest?.call();
    _onOpenNewItemRequest?.call();
    _respondJson(request.response, 200, {'ok': true});
  }

  Future<void> _handleOpenEditItem(HttpRequest request) async {
    final body = await _readJsonBody(request);
    if (body == null) {
      _respondJson(
          request.response, 400, {'ok': false, 'error': 'Invalid JSON'});
      return;
    }

    final entryUuid = (body['id'] as String? ?? '').trim();
    if (entryUuid.isEmpty) {
      _respondJson(request.response, 400, {
        'ok': false,
        'error': 'Item id is required',
      });
      return;
    }

    final handler = _onOpenEditItemRequest;
    if (handler == null) {
      _respondJson(request.response, 503, {
        'ok': false,
        'error': 'Edit item is not available on this desktop build.',
      });
      return;
    }

    _log('open edit item request received entryUuid=$entryUuid');
    _onFocusRequest?.call();
    handler(entryUuid);
    _respondJson(request.response, 200, {'ok': true});
  }

  Future<void> _handleDeleteItem(HttpRequest request) async {
    if (!_repository.hasOpenDatabase) {
      _respondJson(request.response, 404, {
        'ok': false,
        'error': 'No open database',
      });
      return;
    }

    final body = await _readJsonBody(request);
    if (body == null) {
      _respondJson(
        request.response,
        400,
        {'ok': false, 'error': 'Invalid JSON'},
      );
      return;
    }

    final entryUuid = (body['id'] as String? ?? '').trim();
    if (entryUuid.isEmpty) {
      _respondJson(request.response, 400, {
        'ok': false,
        'error': 'Item id is required',
      });
      return;
    }

    try {
      final entry = await _findEntryByUuid(entryUuid);
      await _repository.deleteEntry(entry.uuid);
      await _repository.saveDatabase();
      unawaited(_onAfterSave?.call());
      _log('delete item request succeeded entryUuid=${entry.uuid}');
      _respondJson(request.response, 200, {
        'ok': true,
        'id': entry.uuid,
      });
    } on StateError {
      _respondJson(request.response, 404, {
        'ok': false,
        'error': 'Entry not found',
      });
    } catch (e) {
      _log('delete item request failed entryUuid=$entryUuid: $e');
      _respondJson(request.response, 500, {
        'ok': false,
        'error': e.toString(),
      });
    }
  }

  // ─── Unlock endpoints ──────────────────────────────────────────────────────

  Future<void> _handleUnlockOptions(HttpRequest request) async {
    if (_repository.hasOpenDatabase) {
      _respondJson(request.response, 200, {
        'locked': false,
        'vaultName': _repository.currentDatabase?.name ?? 'LumenPass',
      });
      return;
    }

    final provider = _getUnlockOptions;
    if (provider == null) {
      _respondJson(request.response, 200, {
        'locked': true,
        'vaultReady': false,
      });
      return;
    }

    try {
      final opts = await provider();
      _respondJson(request.response, 200, {
        'locked': true,
        'vaultReady': opts.vaultReady,
        'vaultName': opts.vaultName,
        'hasPin': opts.hasPin,
        'hasBiometric': opts.hasBiometric,
        'biometricAvailable': opts.biometricAvailable,
        'lastMethod': opts.lastMethod,
      });
    } catch (e) {
      _log('unlock/options failed: $e');
      _respondJson(request.response, 500, {'error': e.toString()});
    }
  }

  Future<Map<String, dynamic>?> _readJsonBody(HttpRequest request) async {
    try {
      final raw = await utf8.decodeStream(request);
      if (raw.isEmpty) return <String, dynamic>{};
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleUnlockPassword(HttpRequest request) async {
    if (_repository.hasOpenDatabase) {
      _respondJson(
          request.response, 200, {'ok': true, 'alreadyUnlocked': true});
      return;
    }
    final handler = _unlockWithPassword;
    if (handler == null) {
      _respondJson(request.response, 503, {
        'ok': false,
        'error': 'Unlock is not available on this desktop build.',
      });
      return;
    }
    final body = await _readJsonBody(request);
    if (body == null) {
      _respondJson(
          request.response, 400, {'ok': false, 'error': 'Invalid JSON'});
      return;
    }
    final password = body['password'] as String? ?? '';
    try {
      final result = await handler(password);
      _log('unlock(password) ok=${result.ok} err=${result.error ?? '-'}');
      _respondJson(request.response, result.ok ? 200 : 401, {
        'ok': result.ok,
        'error': result.error,
      });
    } catch (e) {
      _log('unlock(password) threw: $e');
      _respondJson(request.response, 500, {'ok': false, 'error': e.toString()});
    }
  }

  Future<void> _handleUnlockPin(HttpRequest request) async {
    if (_repository.hasOpenDatabase) {
      _respondJson(
          request.response, 200, {'ok': true, 'alreadyUnlocked': true});
      return;
    }
    final handler = _unlockWithPin;
    if (handler == null) {
      _respondJson(request.response, 503, {
        'ok': false,
        'error': 'PIN unlock is not available on this desktop build.',
      });
      return;
    }
    final body = await _readJsonBody(request);
    if (body == null) {
      _respondJson(
          request.response, 400, {'ok': false, 'error': 'Invalid JSON'});
      return;
    }
    final pin = body['pin'] as String? ?? '';
    if (pin.isEmpty) {
      _respondJson(
          request.response, 400, {'ok': false, 'error': 'PIN is required'});
      return;
    }
    try {
      final result = await handler(pin);
      _log('unlock(pin) ok=${result.ok}');
      _respondJson(request.response, result.ok ? 200 : 401, {
        'ok': result.ok,
        'error': result.error,
      });
    } catch (e) {
      _log('unlock(pin) threw: $e');
      _respondJson(request.response, 500, {'ok': false, 'error': e.toString()});
    }
  }

  Future<void> _handleUnlockBiometric(HttpRequest request) async {
    if (_repository.hasOpenDatabase) {
      _respondJson(
          request.response, 200, {'ok': true, 'alreadyUnlocked': true});
      return;
    }
    final handler = _unlockWithBiometric;
    if (handler == null) {
      _respondJson(request.response, 503, {
        'ok': false,
        'error': Platform.isWindows
            ? 'Windows Hello unlock is not available on this desktop build.'
            : 'Biometric unlock is not available on this desktop build.',
      });
      return;
    }
    // Drain the body so the socket can be reused.
    await _readJsonBody(request);
    _onFocusRequest?.call();
    try {
      final result = await handler();
      _log('unlock(biometric) ok=${result.ok}');
      _respondJson(request.response, result.ok ? 200 : 401, {
        'ok': result.ok,
        'error': result.error,
      });
    } catch (e) {
      _log('unlock(biometric) threw: $e');
      _respondJson(request.response, 500, {'ok': false, 'error': e.toString()});
    }
  }

  /// Legacy auth endpoint kept for compatibility — always succeeds so that
  /// older extension versions that send a token still work seamlessly.
  Future<void> _handleAuth(HttpRequest request) async {
    final vaultName = _repository.currentDatabase?.name ?? 'LumenPass';
    _log(
        'auth -> vaultName=$vaultName vaultOpen=${_repository.hasOpenDatabase}');
    _respondJson(request.response, 200, {
      'success': true,
      'vaultName': vaultName,
    });
  }

  Future<void> _handleVaultSettings(HttpRequest request) async {
    _respondJson(request.response, 200, {
      'domainSetting': _getDomainSetting(),
      'disabledAutofillDomains': pruneDisabledAutofillDomains(
        _getDisabledAutofillDomains(),
      ).map((item) => item.toJson()).toList(),
    });
  }

  Future<void> _handleSaveDisabledAutofillDomains(HttpRequest request) async {
    final setter = _setDisabledAutofillDomains;
    if (setter == null) {
      _respondJson(request.response, 503, {
        'ok': false,
        'error': 'Disabled autofill domains cannot be updated.',
      });
      return;
    }

    final body = await _readJsonBody(request);
    if (body == null) {
      _respondJson(
          request.response, 400, {'ok': false, 'error': 'Invalid JSON'});
      return;
    }

    final rawList = body['disabledAutofillDomains'];
    if (rawList is! List) {
      _respondJson(request.response, 400, {
        'ok': false,
        'error': 'disabledAutofillDomains must be an array.',
      });
      return;
    }

    final domains = pruneDisabledAutofillDomains(
      rawList
          .whereType<Map<String, dynamic>>()
          .map(DisabledAutofillDomain.fromJson)
          .whereType<DisabledAutofillDomain>()
          .toList(),
    );

    await setter(domains);
    _respondJson(request.response, 200, {
      'ok': true,
      'disabledAutofillDomains': domains.map((item) => item.toJson()).toList(),
    });
  }

  Future<void> _handleSearch(HttpRequest request) async {
    if (!_repository.hasOpenDatabase) {
      _log('search short-circuited: no open database');
      _respondJson(request.response, 200, <dynamic>[]);
      return;
    }

    final query = request.uri.queryParameters['query'] ?? '';
    final pageUrl = request.uri.queryParameters['url'] ?? '';
    _log('search start query="$query" pageUrl="$pageUrl"');

    final typeFilter = request.uri.queryParameters['type'] ?? '';

    var entries = await _repository.searchEntries(query: query);
    _log(
        'search repository returned ${entries.length} entries before filtering');

    // When a type filter is provided, return all entries of that kind.
    // Special case: "totp" matches any entry that has an OTP secret (not just
    // standalone TOTP entries without URL/username), mirroring the desktop
    // sidebar's Quick Access → TOTP count.
    if (typeFilter.isNotEmpty) {
      if (typeFilter == 'totp') {
        entries = entries
            .where(
                (e) => e.otpAuthUrl != null && e.otpAuthUrl!.trim().isNotEmpty)
            .toList();
      } else {
        entries = entries.where((e) => _entryKind(e) == typeFilter).toList();
      }
      _log(
          'search type filter "$typeFilter" matched ${entries.length} entries');
    } else if (pageUrl.isNotEmpty) {
      // When a page URL is provided, narrow results to the current domain.
      final pageDomain = _extractDomain(pageUrl);
      if (pageDomain.isNotEmpty) {
        final domainSetting =
            request.uri.queryParameters['domainSetting']?.isNotEmpty == true
                ? request.uri.queryParameters['domainSetting']!
                : _getDomainSetting();
        final domainMatched = entries.where((e) {
          final entryDomain = _extractDomain(e.url ?? '');
          return entryDomain.isNotEmpty &&
              _domainsMatchWithSetting(entryDomain, pageDomain, domainSetting);
        }).toList();
        _log(
          'search domain filter "$domainSetting" matched ${domainMatched.length} entries for $pageDomain',
        );
        entries = domainMatched;
      }
    }

    entries.sort((a, b) {
      final aTouched = _latestTimestamp(a.updatedAt, a.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTouched = _latestTimestamp(b.updatedAt, b.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final byDate = bTouched.compareTo(aTouched);
      if (byDate != 0) {
        return byDate;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    final results = entries.map(_entryToSearchResult).toList();
    _log('search response count=${results.length}');
    _respondJson(request.response, 200, results);
  }

  Future<void> _handleGetEntry(HttpRequest request) async {
    if (!_repository.hasOpenDatabase) {
      _log('getEntry short-circuited: no open database');
      _respondJson(request.response, 404, {'error': 'No open database'});
      return;
    }

    final id = Uri.decodeComponent(
      request.uri.path.substring('/entry/'.length),
    );
    _log('getEntry start id=$id');

    final allEntries = await _repository.searchEntries(query: '');
    final entry = allEntries.where((e) => e.uuid == id).firstOrNull;

    if (entry == null) {
      _log('getEntry not found id=$id');
      _respondJson(request.response, 404, {'error': 'Entry not found'});
      return;
    }

    final totp = await _repository.getTOTP(entry.uuid);
    _log('getEntry success id=$id title="${entry.title}"');
    _respondJson(request.response, 200, _entryToDetail(entry, totp: totp));
  }

  Future<void> _handleCategories(HttpRequest request) async {
    final database = _repository.currentDatabase;
    if (database == null) {
      _respondJson(request.response, 200, <dynamic>[]);
      return;
    }

    final categories = <Map<String, dynamic>>[
      {
        'id': database.rootGroup.uuid,
        'name': 'Uncategorized',
      },
      ..._flattenCategoryGroups(database.rootGroup.groups),
    ];

    _respondJson(request.response, 200, categories);
  }

  Future<void> _handleCreatePasskey(HttpRequest request) async {
    if (!_repository.hasOpenDatabase) {
      _respondJson(request.response, 404, {'error': 'No open database'});
      return;
    }

    final groupUuid = _repository.rootGroupUuid;
    if (groupUuid == null) {
      _respondJson(request.response, 500, {'error': 'No root group'});
      return;
    }

    final bodyStr = await utf8.decodeStream(request);
    Map<String, dynamic> body;
    try {
      body = jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (_) {
      _respondJson(request.response, 400, {'error': 'Invalid JSON'});
      return;
    }

    final title = (body['title'] as String?)?.isNotEmpty == true
        ? body['title'] as String
        : (body['rpId'] as String? ?? 'Passkey');
    final rpId = body['rpId'] as String? ?? '';
    final username = body['username'] as String? ?? '';
    final credentialId = body['credentialId'] as String? ?? '';
    final privateKey = body['privateKey'] as String? ?? '';
    final userHandle = body['userHandle'] as String? ?? '';
    final url = body['url'] as String? ?? '';
    final existingEntryId = body['existingEntryId'] as String? ?? '';

    final fields = <EntryField>[
      EntryField(key: 'Title', value: title, isProtected: false),
      EntryField(key: 'UserName', value: username, isProtected: false),
      EntryField(key: 'URL', value: url, isProtected: false),
      EntryField(
          key: _passkeyCredentialIdField,
          value: credentialId,
          isProtected: false),
      EntryField(
          key: _passkeyPrivateKeyField, value: privateKey, isProtected: true),
      EntryField(key: _passkeyRpIdField, value: rpId, isProtected: false),
      EntryField(
          key: _passkeyUsernameField, value: username, isProtected: false),
      if (userHandle.isNotEmpty)
        EntryField(
            key: _passkeyUserHandleField,
            value: userHandle,
            isProtected: false),
    ];

    try {
      late final KdbxEntry entry;
      late final String mode;
      if (existingEntryId.isNotEmpty) {
        final existingEntry = await _findEntryByUuid(existingEntryId);
        final sanitizedExistingFields = existingEntry.fields
            .where(
              (field) =>
                  field.key.toLowerCase() !=
                  _passkeyPrivateKeyLegacyField.toLowerCase(),
            )
            .toList(growable: false);
        entry = await _repository.updateEntry(
          entryUuid: existingEntry.uuid,
          fields: _mergeEntryFields(sanitizedExistingFields, fields),
          notes: existingEntry.notes,
          tags: existingEntry.tags,
        );
        mode = 'updated';
      } else {
        entry = await _repository.createEntry(
          groupUuid: groupUuid,
          fields: fields,
        );
        mode = 'created';
      }
      await _repository.saveDatabase();
      unawaited(_onAfterSave?.call());
      _respondJson(request.response, 200, {
        'ok': true,
        'id': entry.uuid,
        'mode': mode,
      });
    } catch (e) {
      _respondJson(request.response, 500, {'error': e.toString()});
    }
  }

  Future<void> _handleCreateEntry(HttpRequest request) async {
    if (!_repository.hasOpenDatabase) {
      _respondJson(request.response, 404, {'error': 'No open database'});
      return;
    }

    final groupUuid = _repository.rootGroupUuid;
    if (groupUuid == null) {
      _respondJson(request.response, 500, {'error': 'No root group'});
      return;
    }

    final bodyStr = await utf8.decodeStream(request);
    Map<String, dynamic> body;
    try {
      body = jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (_) {
      _respondJson(request.response, 400, {'error': 'Invalid JSON'});
      return;
    }

    final url = body['url'] as String? ?? '';
    final username = body['username'] as String? ?? '';
    final password = body['password'] as String? ?? '';
    final categoryUuid = body['categoryUuid'] as String?;
    final rawTitle = body['title'] as String? ?? '';
    final title = rawTitle.isNotEmpty
        ? rawTitle
        : (url.isNotEmpty ? _extractDomain(url) : 'New Login');
    final targetGroupUuid = (categoryUuid != null && categoryUuid.isNotEmpty)
        ? categoryUuid
        : groupUuid;

    final existingEntryId = body['existingEntryId'] as String? ?? '';

    final newStandardFields = <EntryField>[
      EntryField(key: 'Title', value: title, isProtected: false),
      EntryField(key: 'UserName', value: username, isProtected: false),
      EntryField(key: 'Password', value: password, isProtected: true),
      EntryField(key: 'URL', value: url, isProtected: false),
    ];

    final extraCustomFields = <EntryField>[];
    if (body['customFields'] is List) {
      final customFields = body['customFields'] as List;
      for (final field in customFields) {
        if (field is Map<String, dynamic>) {
          final label = field['label'] as String? ?? '';
          final fieldValue = field['value'] as String? ?? '';
          final secret = field['secret'] as bool? ?? false;
          if (label.isNotEmpty) {
            extraCustomFields.add(EntryField(
              key: label,
              value: fieldValue,
              isProtected: secret || AppKdbxFieldKeys.isProtectedKey(label),
            ));
          }
        }
      }
    }

    try {
      if (existingEntryId.isNotEmpty) {
        final existing = await _findEntryByUuid(existingEntryId);
        final merged = _mergeEntryFields(existing.fields, newStandardFields);
        final withCustom = extraCustomFields.isEmpty
            ? merged
            : _mergeEntryFields(merged, extraCustomFields);
        final entry = await _repository.updateEntry(
          entryUuid: existing.uuid,
          fields: withCustom,
          notes: existing.notes,
          tags: existing.tags,
        );
        await _repository.saveDatabase();
        unawaited(_onAfterSave?.call());
        _log('updateEntry (extension) success id=${entry.uuid} title="$title"');
        _respondJson(request.response, 200, {
          'ok': true,
          'id': entry.uuid,
          'mode': 'updated',
        });
        return;
      }

      final fields = <EntryField>[...newStandardFields, ...extraCustomFields];

      final entry = await _repository.createEntry(
        groupUuid: targetGroupUuid,
        fields: fields,
      );
      await _repository.saveDatabase();
      unawaited(_onAfterSave?.call());
      _log('createEntry success id=${entry.uuid} title="$title"');
      _respondJson(request.response, 200, {
        'ok': true,
        'id': entry.uuid,
        'mode': 'created',
      });
    } catch (e) {
      _log('createEntry/updateEntry failed: $e');
      _respondJson(request.response, 500, {'error': e.toString()});
    }
  }

  Future<void> _handleCreateNote(HttpRequest request) async {
    if (!_repository.hasOpenDatabase) {
      _respondJson(request.response, 404, {'error': 'No open database'});
      return;
    }

    final groupUuid = _repository.rootGroupUuid;
    if (groupUuid == null) {
      _respondJson(request.response, 500, {'error': 'No root group'});
      return;
    }

    final bodyStr = await utf8.decodeStream(request);
    Map<String, dynamic> body;
    try {
      body = jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (_) {
      _respondJson(request.response, 400, {'error': 'Invalid JSON'});
      return;
    }

    final url = body['url'] as String? ?? '';
    final notes = body['notes'] as String? ?? '';
    final categoryUuid = body['categoryUuid'] as String?;
    final rawTitle = body['title'] as String? ?? '';
    final title = rawTitle.isNotEmpty
        ? rawTitle
        : (url.isNotEmpty ? _extractDomain(url) : 'Quick Note');
    final targetGroupUuid = (categoryUuid != null && categoryUuid.isNotEmpty)
        ? categoryUuid
        : groupUuid;

    final tags = <String>[];
    if (body['tags'] is List) {
      for (final tag in body['tags'] as List) {
        if (tag is String && tag.trim().isNotEmpty) {
          tags.add(tag.trim());
        }
      }
    }

    final standardFields = <EntryField>[
      EntryField(key: 'Title', value: title, isProtected: false),
    ];
    if (url.isNotEmpty) {
      standardFields
          .add(EntryField(key: 'URL', value: url, isProtected: false));
    }

    final extraCustomFields = <EntryField>[];
    if (body['customFields'] is List) {
      final customFields = body['customFields'] as List;
      for (final field in customFields) {
        if (field is Map<String, dynamic>) {
          final label = field['label'] as String? ?? '';
          final fieldValue = field['value'] as String? ?? '';
          final secret = field['secret'] as bool? ?? false;
          if (label.isNotEmpty) {
            extraCustomFields.add(EntryField(
              key: label,
              value: fieldValue,
              isProtected: secret || AppKdbxFieldKeys.isProtectedKey(label),
            ));
          }
        }
      }
    }

    try {
      final fields = <EntryField>[...standardFields, ...extraCustomFields];

      final entry = await _repository.createEntry(
        groupUuid: targetGroupUuid,
        fields: fields,
        notes: notes,
        tags: List<String>.unmodifiable(tags),
      );
      await _repository.saveDatabase();
      unawaited(_onAfterSave?.call());
      _log('createNote success id=${entry.uuid} title="$title"');
      _respondJson(request.response, 200, {
        'ok': true,
        'id': entry.uuid,
        'mode': 'created',
      });
    } catch (e) {
      _log('createNote failed: $e');
      _respondJson(request.response, 500, {'error': e.toString()});
    }
  }

  Future<KdbxEntry> _findEntryByUuid(String entryUuid) async {
    final allEntries = await _repository.searchEntries(query: '');
    return allEntries.where((entry) => entry.uuid == entryUuid).firstOrNull ??
        (throw StateError('Entry not found'));
  }

  List<EntryField> _mergeEntryFields(
    List<EntryField> existingFields,
    List<EntryField> replacementFields,
  ) {
    final merged = <String, EntryField>{
      for (final field in existingFields) field.key.toLowerCase(): field,
    };

    for (final field in replacementFields) {
      merged[field.key.toLowerCase()] = field;
    }

    return merged.values.toList(growable: false);
  }

  List<Map<String, dynamic>> _flattenCategoryGroups(
    List<dynamic> groups, {
    String parentPath = '',
  }) {
    final categories = <Map<String, dynamic>>[];
    for (final group in groups) {
      if (group.isRecycleBin == true) {
        continue;
      }
      final currentPath = parentPath.isEmpty
          ? group.name as String
          : '$parentPath / ${group.name}';
      categories.add({
        'id': group.uuid,
        'name': currentPath,
      });
      categories.addAll(
        _flattenCategoryGroups(
          group.groups as List<dynamic>,
          parentPath: currentPath,
        ),
      );
    }
    return categories;
  }

  // ─── Response helpers ──────────────────────────────────────────────────────

  void _respondJson(HttpResponse response, int status, dynamic body) {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body))
      ..close();
  }

  // ─── Serialization ─────────────────────────────────────────────────────────

  Map<String, dynamic> _entryToSearchResult(KdbxEntry entry) {
    final kind = _entryKind(entry);
    final subtitle = _entrySubtitleForSearch(entry, kind);
    final socialProviderField = entry.fields
        .where((f) => !f.isProtected && f.key == 'lp_social_provider')
        .firstOrNull;

    return {
      'id': entry.uuid,
      'title': entry.title,
      'username': entry.username ?? '',
      'url': entry.url ?? '',
      'hasPasskey': _entryHasPasskey(entry),
      'kind': kind,
      'favicon': _faviconUrl(entry.url ?? ''),
      if (subtitle.isNotEmpty) 'subtitle': subtitle,
      if (socialProviderField != null && socialProviderField.value.isNotEmpty)
        'socialProvider': socialProviderField.value,
    };
  }

  Map<String, dynamic> _entryToDetail(KdbxEntry entry, {String? totp}) {
    final password = entry.fieldByKey(AppKdbxFieldKeys.password)?.value ?? '';
    final standardKeys = {
      AppKdbxFieldKeys.title,
      AppKdbxFieldKeys.userName,
      AppKdbxFieldKeys.password,
      AppKdbxFieldKeys.url,
      AppKdbxFieldKeys.notes,
      AppKdbxFieldKeys.otpAuth,
    };
    return {
      'id': entry.uuid,
      'title': entry.title,
      'username': entry.username ?? '',
      'password': password,
      'url': entry.url ?? '',
      'totp': totp,
      'notes': entry.notes ?? '',
      'tags': entry.tags,
      'customFields': entry.fields
          .where((f) => !standardKeys.contains(f.key))
          .map((f) => {
                'label': f.key,
                'value': f.value,
                'secret': f.isProtected,
              })
          .toList(),
      'createdAt': entry.createdAt?.toIso8601String(),
      'updatedAt': entry.updatedAt?.toIso8601String(),
    };
  }

  // ─── Domain helpers ────────────────────────────────────────────────────────

  String _extractDomain(String url) {
    if (url.isEmpty) return '';
    try {
      final uri = Uri.parse(url.contains('://') ? url : 'https://$url');
      return uri.host.toLowerCase();
    } catch (_) {
      return '';
    }
  }

  static bool _isLocalDomain(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h == '127.0.0.1' || h == '::1') return true;
    if (h.endsWith('.local')) return true;
    if (RegExp(r'^192\.168\.|^10\.|^172\.(1[6-9]|2[0-9]|3[01])\.')
        .hasMatch(h)) {
      return true;
    }
    return false;
  }

  String? _faviconUrl(String url) {
    if (url.isEmpty) return null;
    try {
      final uri = Uri.parse(url.contains('://') ? url : 'https://$url');
      if (uri.host.isEmpty) return null;
      if (_isLocalDomain(uri.host)) return null;
      return 'https://www.google.com/s2/favicons?sz=128&domain=${Uri.encodeComponent(uri.host)}';
    } catch (_) {
      return null;
    }
  }

  bool _domainsMatchWithSetting(String a, String b, String setting) {
    if (setting == 'subdomain') {
      return a == b;
    }
    if (a == b) return true;
    return _rootDomain(a) == _rootDomain(b) && _rootDomain(a).isNotEmpty;
  }

  String _rootDomain(String host) {
    final parts = host.split('.');
    return parts.length >= 2
        ? '${parts[parts.length - 2]}.${parts[parts.length - 1]}'
        : host;
  }

  bool _entryHasPasskey(KdbxEntry entry) {
    return entry.fields.any(
      (field) => field.key.toLowerCase() == _passkeyRpIdField.toLowerCase(),
    );
  }

  String _entrySubtitleForSearch(KdbxEntry entry, String kind) {
    if (kind == 'credit-card') {
      final cardNumber = entry
              .fieldByKey('Card Number')
              ?.value
              .replaceAll(RegExp(r'\D'), '') ??
          '';
      if (cardNumber.length >= 4) {
        return '\u2022\u2022\u2022\u2022 \u2022\u2022\u2022\u2022 \u2022\u2022\u2022\u2022 ${cardNumber.substring(cardNumber.length - 4)}';
      }
    }

    final username = entry.username?.trim() ?? '';
    if (username.isNotEmpty) {
      return _truncateListPreview(_singleLinePreview(username), 56);
    }

    final website = entry.url?.trim() ?? '';
    if (website.isNotEmpty) {
      return _truncateListPreview(
        _singleLinePreview(_compactWebsite(website)),
        56,
      );
    }

    final notePreview = _singleLinePreview(entry.notes ?? '');
    if (notePreview.isNotEmpty) {
      return _truncateListPreview(notePreview, 56);
    }

    const normalizedStandardKeys = <String>{
      'title',
      'username',
      'password',
      'url',
      'otpauth',
      'notes',
    };

    for (final field in entry.fields) {
      final key = field.key.trim();
      final normalizedKey = key.toLowerCase();
      if (normalizedStandardKeys.contains(normalizedKey) ||
          AppKdbxFieldKeys.isAttachmentMetaKey(key) ||
          field.isProtected ||
          AppKdbxFieldKeys.isProtectedKey(key)) {
        continue;
      }

      final value = _singleLinePreview(field.value);
      if (value.isNotEmpty) {
        return _truncateListPreview(value, 56);
      }
    }

    return '';
  }

  DateTime? _latestTimestamp(DateTime? a, DateTime? b) {
    if (a == null) {
      return b;
    }
    if (b == null) {
      return a;
    }
    return a.isAfter(b) ? a : b;
  }

  String _singleLinePreview(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _truncateListPreview(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength - 1)}…';
  }

  String _compactWebsite(String rawUrl) {
    final value = rawUrl.trim();
    if (value.isEmpty) {
      return value;
    }

    try {
      final uri = Uri.parse(value);
      final host = uri.host.trim();
      if (host.isEmpty) {
        return value;
      }
      return host.startsWith('www.') ? host.substring(4) : host;
    } catch (_) {
      return value;
    }
  }

  String _entryKind(KdbxEntry entry) {
    final fields = entry.fields;
    final normalizedKeys =
        fields.map((field) => field.key.toLowerCase()).toList();

    if (_entryHasPasskey(entry)) return 'passkey';
    if ((entry.otpAuthUrl?.trim().isNotEmpty ?? false) &&
        (entry.url ?? '').isEmpty &&
        (entry.username ?? '').isEmpty) {
      return 'totp';
    }
    if (normalizedKeys.any((key) =>
        key.contains('ssh') ||
        key.contains('public key') ||
        key.contains('private key'))) {
      return 'ssh-key';
    }
    if (normalizedKeys.any((key) =>
        key.contains('license') ||
        key.contains('serial') ||
        key.contains('product key') ||
        key.contains('registration'))) {
      return 'software-license';
    }
    if (normalizedKeys.any((key) =>
        key == 'card number' || key == 'cvc' || key == 'expiry date')) {
      return 'credit-card';
    }

    switch (classifyVaultItemType(entry)) {
      case VaultItemType.login:
        return 'login';
      case VaultItemType.secureNote:
        return 'secure-note';
      case VaultItemType.creditCard:
        return 'credit-card';
      case VaultItemType.identity:
        return 'identity';
      case VaultItemType.sshKey:
        return 'ssh-key';
      case VaultItemType.document:
        return 'software-license';
      case VaultItemType.bankAccount:
      case VaultItemType.apiCredential:
      case VaultItemType.server:
      case VaultItemType.wifiPassword:
      case VaultItemType.passport:
        return 'unknown';
    }
  }
}
