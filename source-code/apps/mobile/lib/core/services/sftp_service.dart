import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ---------------------------------------------------------------------------
// Configuration model
// ---------------------------------------------------------------------------

enum SftpAuthMethod { password, publicKeyFile }

enum SftpTransferMode { active, passive }

/// Immutable connection configuration for an SFTP storage provider.
///
/// [password] is treated as a secret and is never written to logs or
/// `toString()` output. For key authentication, [keyFilePath] points at the
/// local private key file selected by the user.
@immutable
class SftpConfig {
  const SftpConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.authMethod,
    this.password = '',
    this.keyFilePath,
    required this.transferMode,
    required this.rootPath,
  });

  final String host;
  final int port;
  final String username;
  final SftpAuthMethod authMethod;
  final String password;
  final String? keyFilePath;

  /// Product-level option required by the settings UI.
  ///
  /// SFTP itself does not use FTP active/passive data channels, so this value
  /// is persisted for compatibility with the UI requirement but does not alter
  /// the SSH/SFTP protocol behavior.
  final SftpTransferMode transferMode;
  final String rootPath;

  SftpConfig copyWith({
    String? host,
    int? port,
    String? username,
    SftpAuthMethod? authMethod,
    String? password,
    String? keyFilePath,
    SftpTransferMode? transferMode,
    String? rootPath,
  }) {
    return SftpConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      password: password ?? this.password,
      keyFilePath: keyFilePath ?? this.keyFilePath,
      transferMode: transferMode ?? this.transferMode,
      rootPath: rootPath ?? this.rootPath,
    );
  }

  Map<String, dynamic> toJsonWithoutSecret() => <String, dynamic>{
        'host': host,
        'port': port,
        'username': username,
        'authMethod': authMethod.name,
        'keyFilePath': keyFilePath,
        'transferMode': transferMode.name,
        'rootPath': rootPath,
      };

  factory SftpConfig.fromJson(
    Map<String, dynamic> json, {
    required String password,
  }) {
    return SftpConfig(
      host: (json['host'] as String?) ?? '',
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: (json['username'] as String?) ?? '',
      authMethod: _authMethodFromString(json['authMethod'] as String?),
      password: password,
      keyFilePath: json['keyFilePath'] as String?,
      transferMode: _transferModeFromString(json['transferMode'] as String?),
      rootPath: (json['rootPath'] as String?) ?? '/',
    );
  }

  String get accountLabel {
    final h = normalizeHostForDisplay(host);
    return username.isEmpty ? h : '$username@$h';
  }

  @override
  String toString() =>
      'SftpConfig(host: $host, port: $port, username: $username, '
      'authMethod: ${authMethod.name}, keyFilePath: $keyFilePath, '
      'transferMode: ${transferMode.name}, rootPath: $rootPath, '
      'password: ••••••)';

  static String normalizeHostForDisplay(String raw) {
    var value = raw.trim();
    value = value.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '');
    final slash = value.indexOf('/');
    if (slash >= 0) value = value.substring(0, slash);
    return value;
  }

  static SftpAuthMethod _authMethodFromString(String? raw) {
    return switch (raw) {
      'publicKeyFile' => SftpAuthMethod.publicKeyFile,
      _ => SftpAuthMethod.password,
    };
  }

  static SftpTransferMode _transferModeFromString(String? raw) {
    return switch (raw) {
      'active' => SftpTransferMode.active,
      _ => SftpTransferMode.passive,
    };
  }
}

@immutable
class SftpConfigValidation {
  const SftpConfigValidation(this.errors);

  final Map<String, String> errors;

  bool get isValid => errors.isEmpty;

  String? operator [](String field) => errors[field];
}

class SftpFolder {
  const SftpFolder({required this.id, required this.name, this.path});

  final String id;
  final String name;
  final String? path;
}

class SftpFile {
  const SftpFile({
    required this.id,
    required this.name,
    this.path,
    this.size,
    this.lastModified,
  });

  final String id;
  final String name;
  final String? path;
  final int? size;
  final DateTime? lastModified;
}

class SftpService {
  SftpService._();
  static final SftpService instance = SftpService._();

  static const String _logTag = '[SFTP]';
  static const Duration _timeout = Duration(seconds: 20);
  static const String _kInternalKeyFileName = 'sftp_private_key';

  SftpConfig? _config;

  SftpConfig? get config => _config;

  bool get isConnected => _config != null;

  static SftpConfigValidation validateConfig(SftpConfig config) {
    final errors = <String, String>{};

    if (config.host.trim().isEmpty) {
      errors['host'] = 'Server host is required.';
    } else if (SftpConfig.normalizeHostForDisplay(config.host).isEmpty) {
      errors['host'] = 'Enter a valid host.';
    }

    if (config.port < 1 || config.port > 65535) {
      errors['port'] = 'Port must be between 1 and 65535.';
    }

    if (config.username.trim().isEmpty) {
      errors['username'] = 'Username is required.';
    }

    switch (config.authMethod) {
      case SftpAuthMethod.password:
        if (config.password.isEmpty) {
          errors['password'] = 'Password is required.';
        }
      case SftpAuthMethod.publicKeyFile:
        if ((config.keyFilePath ?? '').trim().isEmpty) {
          errors['keyFilePath'] = 'Choose a private key file.';
        }
    }

    if (normalizeRootPath(config.rootPath).isEmpty) {
      errors['rootPath'] = 'Root path is required.';
    }

    return SftpConfigValidation(errors);
  }

  static String normalizeRootPath(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '/';
    value = value.replaceAll('\\', '/');
    value = value.replaceAll(RegExp(r'/+'), '/');
    if (!value.startsWith('/')) value = '/$value';
    if (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  Future<void> connect(SftpConfig config) async {
    final validation = validateConfig(config);
    if (!validation.isValid) {
      throw Exception(
        'Invalid SFTP configuration: ${validation.errors.values.first}',
      );
    }

    var normalized = config.copyWith(
      rootPath: normalizeRootPath(config.rootPath),
    );

    // Copy the private key into internal storage so it survives
    // if the user moves or deletes the original file on disk.
    if (normalized.authMethod == SftpAuthMethod.publicKeyFile &&
        normalized.keyFilePath != null &&
        normalized.keyFilePath!.isNotEmpty) {
      final internalPath =
          await _copyKeyFileToInternal(normalized.keyFilePath!);
      normalized = normalized.copyWith(keyFilePath: internalPath);
    }

    _config = normalized;
    try {
      await testConnection(normalized);
      await _withSftp(
          normalized,
          (sftp) => _ensureDirectory(
                sftp,
                normalized.rootPath,
                normalized,
              ));
      _log(
          'connected to ${normalized.accountLabel} root=${normalized.rootPath}');
    } catch (_) {
      _config = null;
      rethrow;
    }
  }

  void restore(SftpConfig config) {
    _config = config.copyWith(rootPath: normalizeRootPath(config.rootPath));
    _log('config restored for ${_config!.accountLabel}');
  }

  Future<void> disconnect() async {
    await _deleteInternalKeyFile();
    _config = null;
    _log('disconnected');
  }

  Future<void> testConnection([SftpConfig? override]) async {
    final cfg = override ?? _config;
    if (cfg == null) {
      throw Exception('No SFTP configuration to test.');
    }
    final validation = validateConfig(cfg);
    if (!validation.isValid) {
      throw Exception(validation.errors.values.first);
    }

    await _withSftp(cfg, (sftp) async {
      await sftp.stat(normalizeRootPath(cfg.rootPath)).timeout(_timeout);
    });
  }

  Future<List<SftpFolder>> listFolders({String? parentPath}) async {
    final cfg = _requireConfig();
    return _withSftp(cfg, (sftp) async {
      final dir = _absolute(parentPath ?? cfg.rootPath, cfg);
      final entries = await _listChildren(sftp, dir);
      return entries.where((e) => e.attr.isDirectory).map((e) {
        final path = _join(dir, e.filename);
        return SftpFolder(id: path, name: e.filename, path: path);
      }).toList();
    });
  }

  Future<List<SftpFile>> listFiles({
    String? parentPath,
    String? extension,
  }) async {
    final cfg = _requireConfig();
    return _withSftp(cfg, (sftp) async {
      final dir = _absolute(parentPath ?? cfg.rootPath, cfg);
      final entries = await _listChildren(sftp, dir);
      var files = entries.where((e) => !e.attr.isDirectory).map((e) {
        final path = _join(dir, e.filename);
        return SftpFile(
          id: path,
          name: e.filename,
          path: path,
          size: e.attr.size,
          lastModified: _dateFromSftpSeconds(e.attr.modifyTime),
        );
      }).toList();
      if (extension != null) {
        files = files
            .where((f) => f.name.toLowerCase().endsWith(extension))
            .toList();
      }
      return files;
    });
  }

  Future<Uint8List> downloadFile(String remotePath) async {
    final cfg = _requireConfig();
    return _withSftp(cfg, (sftp) async {
      final path = _absolute(remotePath, cfg);
      _log('GET ${_redactPath(path)}');
      final file = await sftp.open(path, mode: SftpFileOpenMode.read);
      try {
        return await file.readBytes();
      } finally {
        await file.close();
      }
    });
  }

  Future<void> uploadBytes(Uint8List bytes, String remotePath) async {
    final cfg = _requireConfig();
    await _withSftp(cfg, (sftp) async {
      final path = _absolute(remotePath, cfg);
      await _ensureDirectory(sftp, p.posix.dirname(path), cfg);
      _log('PUT ${_redactPath(path)} (${bytes.length} bytes)');
      final file = await sftp.open(
        path,
        mode: SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate,
      );
      try {
        await file.writeBytes(bytes);
      } finally {
        await file.close();
      }
    });
  }

  Future<String> uploadNewFile(
    Uint8List bytes,
    String folderPath,
    String fileName,
  ) async {
    final cfg = _requireConfig();
    final dir = _absolute(folderPath, cfg);
    final remotePath = _join(dir, fileName);
    await uploadBytes(bytes, remotePath);
    return remotePath;
  }

  Future<void> deleteFile(String remotePath) async {
    final cfg = _requireConfig();
    await _withSftp(cfg, (sftp) async {
      final path = _absolute(remotePath, cfg);
      _log('DELETE ${_redactPath(path)}');
      try {
        await sftp.remove(path);
      } on SftpStatusError catch (e) {
        if (e.code == SftpStatusCode.noSuchFile) return;
        rethrow;
      }
    });
  }

  Future<DateTime?> getFileModifiedTime(String remotePath) async {
    final cfg = _requireConfig();
    return _withSftp(cfg, (sftp) async {
      try {
        final attrs = await sftp.stat(_absolute(remotePath, cfg));
        return _dateFromSftpSeconds(attrs.modifyTime);
      } catch (_) {
        return null;
      }
    });
  }

  Future<SftpFolder> createFolder(String name, {String? parentPath}) async {
    final cfg = _requireConfig();
    return _withSftp(cfg, (sftp) async {
      final parent = _absolute(parentPath ?? cfg.rootPath, cfg);
      final folderPath = _join(parent, name);
      await _ensureDirectory(sftp, folderPath, cfg);
      return SftpFolder(id: folderPath, name: name, path: folderPath);
    });
  }

  Future<List<SftpFolder>> browseFolders(
    SftpConfig config, {
    String? parentPath,
  }) async {
    final cfg = config.copyWith(rootPath: '/');
    return _withSftp(cfg, (sftp) async {
      final dir = _absolute(parentPath ?? '/', cfg);
      final entries = await _listChildren(sftp, dir);
      return entries.where((e) => e.attr.isDirectory).map((e) {
        final path = _join(dir, e.filename);
        return SftpFolder(id: path, name: e.filename, path: path);
      }).toList();
    });
  }

  Future<SftpFolder> createFolderIn(
    SftpConfig config,
    String name, {
    String? parentPath,
  }) async {
    final cfg = config.copyWith(rootPath: '/');
    return _withSftp(cfg, (sftp) async {
      final parent = _absolute(parentPath ?? '/', cfg);
      final folderPath = _join(parent, name);
      await _ensureDirectory(sftp, folderPath, cfg);
      return SftpFolder(id: folderPath, name: name, path: folderPath);
    });
  }

  Future<void> verifyWritable(SftpConfig config) async {
    final cfg = config.copyWith(rootPath: normalizeRootPath(config.rootPath));

    await _withSftp(cfg, (sftp) async {
      await _ensureDirectory(sftp, cfg.rootPath, cfg);
      final fileName =
          '.lumenpass-write-test-${DateTime.now().millisecondsSinceEpoch}.txt';
      final remotePath = _join(cfg.rootPath, fileName);
      final payload = Uint8List.fromList(utf8.encode(
        'LumenPass SFTP write test ${DateTime.now().toIso8601String()}',
      ));

      final file = await sftp.open(
        remotePath,
        mode: SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate,
      );
      try {
        await file.writeBytes(payload);
      } finally {
        await file.close();
      }

      try {
        final read = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
        try {
          final bytes = await read.readBytes();
          if (bytes.isEmpty) {
            throw Exception('The selected path is not readable.');
          }
        } finally {
          await read.close();
        }
      } finally {
        await _silentDelete(sftp, remotePath);
      }
    });
  }

  Future<void> _silentDelete(SftpClient sftp, String path) async {
    try {
      await sftp.remove(path);
    } catch (_) {}
  }

  SftpConfig _requireConfig() {
    final cfg = _config;
    if (cfg == null) {
      throw Exception('Not connected. Call connect() first.');
    }
    return cfg;
  }

  Future<T> _withSftp<T>(
    SftpConfig cfg,
    Future<T> Function(SftpClient sftp) action,
  ) async {
    final socket = await SSHSocket.connect(
      SftpConfig.normalizeHostForDisplay(cfg.host),
      cfg.port,
      timeout: _timeout,
    );
    final client = await _buildClient(socket, cfg);
    SftpClient? sftp;
    try {
      await client.authenticated.timeout(_timeout);
      sftp = await client.sftp().timeout(_timeout);
      return await action(sftp).timeout(_timeout);
    } on SocketException {
      rethrow;
    } on TimeoutException {
      throw Exception('The SFTP server did not respond in time.');
    } on SftpStatusError catch (e) {
      throw Exception(_messageForStatus(e));
    } catch (e) {
      throw Exception(_messageForError(e));
    } finally {
      sftp?.close();
      client.close();
    }
  }

  Future<SSHClient> _buildClient(SSHSocket socket, SftpConfig cfg) async {
    switch (cfg.authMethod) {
      case SftpAuthMethod.password:
        return SSHClient(
          socket,
          username: cfg.username,
          onPasswordRequest: () => cfg.password,
        );
      case SftpAuthMethod.publicKeyFile:
        final keyText = await _readKeyFile(cfg);
        final identities = SSHKeyPair.fromPem(keyText);
        if (identities.isEmpty) {
          throw Exception(
              'The selected key file does not contain a private key.');
        }
        return SSHClient(
          socket,
          username: cfg.username,
          identities: identities,
        );
    }
  }

  Future<String> _readKeyFile(SftpConfig cfg) async {
    final path = cfg.keyFilePath;
    if (path == null || path.isEmpty) {
      throw Exception('Choose a private key file.');
    }
    try {
      return await File(path).readAsString();
    } catch (e) {
      throw Exception('Could not read the selected private key file: $e');
    }
  }

  Future<List<SftpName>> _listChildren(SftpClient sftp, String dir) async {
    final entries = await sftp.listdir(dir);
    return entries
        .where((e) => e.filename != '.' && e.filename != '..')
        .toList();
  }

  Future<void> _ensureDirectory(
    SftpClient sftp,
    String directoryPath,
    SftpConfig cfg,
  ) async {
    final abs = _absolute(directoryPath, cfg);
    if (abs == '/') return;

    final segments = abs.split('/').where((s) => s.isNotEmpty).toList();
    var current = '';
    for (final segment in segments) {
      current = '$current/$segment';
      try {
        final attrs = await sftp.stat(current);
        if (!attrs.isDirectory) {
          throw Exception('"$current" exists but is not a directory.');
        }
      } on SftpStatusError catch (e) {
        if (e.code != SftpStatusCode.noSuchFile) rethrow;
        try {
          await sftp.mkdir(current);
        } on SftpStatusError catch (createError) {
          if (createError.code == SftpStatusCode.failure) {
            final attrs = await sftp.stat(current);
            if (attrs.isDirectory) continue;
          }
          rethrow;
        }
      }
    }
  }

  String _absolute(String path, SftpConfig cfg) {
    final root = normalizeRootPath(cfg.rootPath);
    var value = path.trim().replaceAll('\\', '/');
    if (value.isEmpty) return root;
    if (value.startsWith('/')) return normalizeRootPath(value);
    final joined = root == '/' ? '/$value' : '$root/$value';
    return normalizeRootPath(joined);
  }

  String _join(String parent, String child) {
    final cleanedParent = normalizeRootPath(parent);
    return normalizeRootPath(p.posix.join(cleanedParent, child));
  }

  DateTime? _dateFromSftpSeconds(int? seconds) {
    if (seconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  String _messageForStatus(SftpStatusError e) {
    return switch (e.code) {
      SftpStatusCode.noSuchFile => 'The selected path does not exist.',
      SftpStatusCode.permissionDenied =>
        'The SFTP server denied access to the selected path.',
      _ => e.message.isNotEmpty ? e.message : e.toString(),
    };
  }

  String _messageForError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    if (text.contains('SSHAuthFailError') ||
        text.contains('Permission denied')) {
      return 'Authentication failed. Check the username and credentials.';
    }
    if (text.contains('Invalid private key') || text.contains('private key')) {
      return 'The selected key file could not be used for SFTP authentication.';
    }
    return text;
  }

  String _redactPath(String path) => path;

  // ── Internal key file management ────────────────────────────────────────

  /// Returns the dedicated directory for stored SFTP private key files.
  /// Creates it automatically if it doesn't exist.
  Future<Directory> _getKeyFilesDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/sftp_keys');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Copies the private key file at [sourcePath] into the app's internal
  /// storage so it survives if the user moves or deletes the original file.
  /// Returns the absolute path of the internal copy.
  Future<String> _copyKeyFileToInternal(String sourcePath) async {
    final dir = await _getKeyFilesDir();
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception(
        'The selected private key file could not be found. '
        'It may have been moved or deleted.',
      );
    }
    final destPath = '${dir.path}/$_kInternalKeyFileName';
    await sourceFile.copy(destPath);
    _log('key file copied to internal storage');
    return destPath;
  }

  /// Deletes the internal copy of the private key file (if any).
  Future<void> _deleteInternalKeyFile() async {
    try {
      final dir = await _getKeyFilesDir();
      final file = File('${dir.path}/$_kInternalKeyFileName');
      if (await file.exists()) {
        await file.delete();
        _log('internal key file deleted');
      }
    } catch (e) {
      _log('failed to delete internal key file: $e');
    }
  }

  void _log(String message) {
    debugPrint('$_logTag ${DateTime.now().toIso8601String()} $message');
  }
}
