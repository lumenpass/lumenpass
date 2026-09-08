import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/models/database_record.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/bookmark_service.dart';
import '../../../core/services/sftp_service.dart';
import '../../../core/services/webdav_service.dart';
import '../../../presentation/theme/app_theme.dart';
import '../application/database_registry.dart';
import 'sftp_config_dialog.dart';
import 'webdav_config_dialog.dart';

const Color _kCanvas = Color(0xFFF6F8FB);
const Color _kBorderSoft = Color(0xFFE1E7F0);
const Color _kBorderRow = Color(0xFFE6EAF0);
const Color _kTitle = Color(0xFF22314A);
const Color _kLabel = Color(0xFF73839D);
const Color _kIcon = Color(0xFF8A97AC);
const Color _kBlue = Color(0xFF4B6CFF);

TextStyle _uText(
  double size,
  Color color, {
  FontWeight fontWeight = FontWeight.w400,
  double? letterSpacing,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: fontWeight,
    fontFamily: 'Inter',
    letterSpacing: letterSpacing,
  );
}

enum _DuplicateStorage { local, googleDrive, dropbox, oneDrive, webDav, sftp }

enum _CloudType { googleDrive, dropbox, oneDrive, webDav, sftp }

/// Modal that lets the user duplicate an existing database to a destination
/// of their choice — local folder, Google Drive, or Dropbox.
class DuplicateDatabaseModal extends ConsumerStatefulWidget {
  const DuplicateDatabaseModal({
    super.key,
    required this.source,
    required this.sourcePath,
    required this.defaultNickname,
    required this.onDuplicated,
  });

  /// The source database record being duplicated.
  final DatabaseRecord source;

  /// Resolved on-disk path to the source database. For cloud-backed records
  /// this is the local cache path (we re-download bytes from the cloud when
  /// this file is missing).
  final String sourcePath;

  /// Pre-filled suggested nickname / filename (typically `<origin> Copy`).
  final String defaultNickname;

  /// Called with the new database path after the duplicate succeeds.
  final Future<void> Function(String dbPath) onDuplicated;

  @override
  ConsumerState<DuplicateDatabaseModal> createState() =>
      _DuplicateDatabaseModalState();
}

class _DuplicateDatabaseModalState
    extends ConsumerState<DuplicateDatabaseModal> {
  _DuplicateStorage _storage = _DuplicateStorage.local;

  final TextEditingController _nameController = TextEditingController();

  String? _localDirectory;

  String? _googleAccount;
  String? _googleFolderId;
  String? _googleFolderName;
  bool _isConnectingGoogle = false;

  String? _dropboxAccount;
  String? _dropboxFolderPath;
  String? _dropboxFolderName;
  bool _isConnectingDropbox = false;

  String? _oneDriveAccount;
  String? _oneDriveFolderId;
  String? _oneDriveFolderName;
  bool _isConnectingOneDrive = false;

  String? _webDavAccount;
  String? _webDavFolderPath;
  String? _webDavFolderName;
  bool _isConnectingWebDav = false;

  String? _sftpAccount;
  String? _sftpFolderPath;
  String? _sftpFolderName;
  bool _isConnectingSftp = false;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.defaultNickname;
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreCloudState());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _restoreCloudState() {
    final googleEmail = ref.read(backupGoogleAccountProvider);
    final dropboxEmail = ref.read(backupDropboxAccountProvider);
    final oneDriveEmail = ref.read(backupOneDriveAccountProvider);
    final webDavAccount = ref.read(backupWebDavAccountProvider);
    final sftpAccount = ref.read(backupSftpAccountProvider);
    if (googleEmail != null ||
        dropboxEmail != null ||
        oneDriveEmail != null ||
        webDavAccount != null ||
        sftpAccount != null) {
      setState(() {
        _googleAccount = googleEmail;
        _dropboxAccount = dropboxEmail;
        _oneDriveAccount = oneDriveEmail;
        _webDavAccount = webDavAccount;
        _sftpAccount = sftpAccount;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.light(),
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 40),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 40,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildHeader(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const SizedBox(height: 16),
                      _buildNameField(),
                      const SizedBox(height: 16),
                      _buildStorageSection(),
                      if (_errorMessage != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _buildError(_errorMessage!),
                      ],
                    ],
                  ),
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorderSoft)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFF4B6CFF), Color(0xFF7B52FF)],
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(TablerIcons.copy, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Duplicate Database',
                  style: _uText(15, _kTitle, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Create a copy of "${widget.source.nickname}" in a new location.',
                  style: _uText(11, _kLabel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _isSubmitting ? null : () => Navigator.of(context).pop(),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _kCanvas,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: _kBorderSoft),
              ),
              child: const Icon(TablerIcons.x, size: 14, color: _kIcon),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'New Database Name',
          style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _nameController,
          style: _uText(13, _kTitle),
          onChanged: (_) => setState(() => _errorMessage = null),
          decoration: InputDecoration(
            hintText: 'e.g. My Vault Copy',
            hintStyle: _uText(13, _kIcon),
            filled: true,
            fillColor: _kCanvas,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kBorderRow),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kBorderRow),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kBlue, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStorageSection() {
    final bool dropboxConfigured = BackupService.isDropboxConfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Save To',
          style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _StorageRow(
          iconChild:
              Image.asset('assets/images/dir.png', width: 16, height: 16),
          label: _localDirectory != null
              ? _shortenPath(_localDirectory!)
              : 'Local Directory',
          selected: _storage == _DuplicateStorage.local,
          actionLabel: _localDirectory != null ? 'Change' : 'Browse...',
          onAction: _pickLocalDirectory,
          onTap: () => setState(() => _storage = _DuplicateStorage.local),
        ),
        const SizedBox(height: 6),
        _CloudStorageRow(
          iconChild: Image.asset(
            'assets/images/google-drive.png',
            width: 16,
            height: 16,
          ),
          provider: 'Google Drive',
          selected: _storage == _DuplicateStorage.googleDrive,
          account: _googleAccount,
          folderName: _googleFolderName,
          isConnecting: _isConnectingGoogle,
          onConnect: _connectGoogle,
          onDisconnect: _disconnectGoogle,
          onPickFolder: _googleAccount != null ? _pickGoogleFolder : null,
          onSelect: _googleAccount != null
              ? () => setState(() => _storage = _DuplicateStorage.googleDrive)
              : null,
        ),
        const SizedBox(height: 6),
        _CloudStorageRow(
          iconChild:
              Image.asset('assets/images/dropbox.png', width: 16, height: 16),
          provider: 'Dropbox',
          selected: _storage == _DuplicateStorage.dropbox,
          account: _dropboxAccount,
          folderName: _dropboxFolderName,
          isConnecting: _isConnectingDropbox,
          onConnect: dropboxConfigured ? _connectDropbox : null,
          onDisconnect: _disconnectDropbox,
          onPickFolder: _dropboxAccount != null ? _pickDropboxFolder : null,
          onSelect: _dropboxAccount != null
              ? () => setState(() => _storage = _DuplicateStorage.dropbox)
              : null,
        ),
        if (!dropboxConfigured) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'Dropbox is disabled in this build. Configure DROPBOX_APP_KEY via --dart-define to enable it.',
            style: _uText(11, _kLabel),
          ),
        ],
        const SizedBox(height: 6),
        _CloudStorageRow(
          iconChild: Image.asset(
            'assets/images/onedrive.png',
            width: 16,
            height: 16,
          ),
          provider: 'OneDrive',
          selected: _storage == _DuplicateStorage.oneDrive,
          account: _oneDriveAccount,
          folderName: _oneDriveFolderName,
          isConnecting: _isConnectingOneDrive,
          onConnect: _connectOneDrive,
          onDisconnect: _disconnectOneDrive,
          onPickFolder:
              _oneDriveAccount != null ? _pickOneDriveFolder : null,
          onSelect: _oneDriveAccount != null
              ? () => setState(() => _storage = _DuplicateStorage.oneDrive)
              : null,
        ),
        const SizedBox(height: 6),
        _CloudStorageRow(
          iconChild: Image.asset(
            'assets/images/webdav.png',
            width: 16,
            height: 16,
          ),
          provider: 'WebDAV',
          selected: _storage == _DuplicateStorage.webDav,
          account: _webDavAccount,
          folderName: _webDavFolderName,
          isConnecting: _isConnectingWebDav,
          onConnect: _connectWebDav,
          onDisconnect: _disconnectWebDav,
          onPickFolder:
              _webDavAccount != null ? _pickWebDavFolder : null,
          onSelect: _webDavAccount != null
              ? () => setState(() => _storage = _DuplicateStorage.webDav)
              : null,
        ),
        const SizedBox(height: 6),
        _CloudStorageRow(
          iconChild: Image.asset(
            'assets/images/sftp.png',
            width: 16,
            height: 16,
          ),
          provider: 'SFTP',
          selected: _storage == _DuplicateStorage.sftp,
          account: _sftpAccount,
          folderName: _sftpFolderName,
          isConnecting: _isConnectingSftp,
          onConnect: _connectSftp,
          onDisconnect: _disconnectSftp,
          onPickFolder: _sftpAccount != null ? _pickSftpFolder : null,
          onSelect: _sftpAccount != null
              ? () => setState(() => _storage = _DuplicateStorage.sftp)
              : null,
        ),
      ],
    );
  }

  Widget _buildError(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            TablerIcons.alert_circle,
            size: 14,
            color: Color(0xFFEF4444),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: _uText(11, const Color(0xFFEF4444)),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _errorMessage = null),
            child:
                const Icon(TablerIcons.x, size: 13, color: Color(0xFFEF4444)),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kBorderSoft)),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: Row(
        children: <Widget>[
          OutlinedButton(
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kLabel,
              side: const BorderSide(color: _kBorderSoft),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              textStyle: _uText(12, _kLabel, fontWeight: FontWeight.w600),
            ),
            child: const Text('Cancel'),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A3B48),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF6F8991),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: _uText(12, Colors.white, fontWeight: FontWeight.w600),
            ),
            child: _isSubmitting
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Duplicate'),
          ),
        ],
      ),
    );
  }

  // ── Cloud auth + folder pickers ──────────────────────────────────────────

  Future<void> _connectGoogle() async {
    setState(() => _isConnectingGoogle = true);
    try {
      await BackupService.instance.connectGoogle();
      final account = BackupService.instance.currentGoogleAccount;
      if (account != null) {
        setState(() {
          _googleAccount = account.email;
          _storage = _DuplicateStorage.googleDrive;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Google sign-in failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isConnectingGoogle = false);
      }
    }
  }

  Future<void> _disconnectGoogle() async {
    await BackupService.instance.disconnectGoogle();
    setState(() {
      _googleAccount = null;
      _googleFolderId = null;
      _googleFolderName = null;
      if (_storage == _DuplicateStorage.googleDrive) {
        _storage = _DuplicateStorage.local;
      }
    });
  }

  Future<void> _connectDropbox() async {
    setState(() => _isConnectingDropbox = true);
    try {
      await BackupService.instance.connectDropbox();
      final token = BackupService.instance.currentDropboxToken;
      if (token != null && token.isNotEmpty) {
        setState(() {
          _dropboxAccount =
              ref.read(backupDropboxAccountProvider) ?? 'Connected';
          _storage = _DuplicateStorage.dropbox;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Dropbox connection failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isConnectingDropbox = false);
      }
    }
  }

  Future<void> _disconnectDropbox() async {
    await BackupService.instance.disconnectDropbox();
    setState(() {
      _dropboxAccount = null;
      _dropboxFolderPath = null;
      _dropboxFolderName = null;
      if (_storage == _DuplicateStorage.dropbox) {
        _storage = _DuplicateStorage.local;
      }
    });
  }

  // ── OneDrive ────────────────────────────────────────────────────────────

  Future<void> _connectOneDrive() async {
    setState(() => _isConnectingOneDrive = true);
    try {
      await BackupService.instance.connectOneDrive();
      final email = ref.read(backupOneDriveAccountProvider) ?? 'Connected';
      if (mounted) {
        setState(() {
          _oneDriveAccount = email;
          _storage = _DuplicateStorage.oneDrive;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'OneDrive sign-in failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isConnectingOneDrive = false);
    }
  }

  Future<void> _disconnectOneDrive() async {
    await BackupService.instance.disconnectOneDrive();
    setState(() {
      _oneDriveAccount = null;
      _oneDriveFolderId = null;
      _oneDriveFolderName = null;
      if (_storage == _DuplicateStorage.oneDrive) {
        _storage = _DuplicateStorage.local;
      }
    });
  }

  Future<void> _pickOneDriveFolder() async {
    final result = await showDialog<CloudFolder?>(
      context: context,
      builder: (_) => const _CloudFolderPickerDialog(
        cloudType: _CloudType.oneDrive,
      ),
    );
    if (result != null) {
      setState(() {
        _oneDriveFolderId = result.id;
        _oneDriveFolderName = result.displayPath;
      });
    }
  }

  // ── WebDAV ──────────────────────────────────────────────────────────────

  Future<void> _connectWebDav() async {
    setState(() => _isConnectingWebDav = true);
    try {
      final config = await showDialog<WebDavConfig>(
        context: context,
        builder: (_) => WebDavConfigDialog(
          initialConfig: BackupService.instance.currentWebDavConfig,
        ),
      );
      if (config == null) {
        if (mounted) setState(() => _isConnectingWebDav = false);
        return;
      }
      await BackupService.instance.connectWebDav(config);
      if (mounted) {
        final account =
            ref.read(backupWebDavAccountProvider) ?? config.accountLabel;
        setState(() {
          _webDavAccount = account;
          _storage = _DuplicateStorage.webDav;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'WebDAV connection failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isConnectingWebDav = false);
    }
  }

  Future<void> _disconnectWebDav() async {
    await BackupService.instance.disconnectWebDav();
    setState(() {
      _webDavAccount = null;
      _webDavFolderPath = null;
      _webDavFolderName = null;
      if (_storage == _DuplicateStorage.webDav) {
        _storage = _DuplicateStorage.local;
      }
    });
  }

  Future<void> _pickWebDavFolder() async {
    final result = await showDialog<CloudFolder?>(
      context: context,
      builder: (_) => const _CloudFolderPickerDialog(
        cloudType: _CloudType.webDav,
      ),
    );
    if (result != null) {
      setState(() {
        _webDavFolderPath = result.id;
        _webDavFolderName = result.displayPath;
      });
    }
  }

  // ── SFTP ────────────────────────────────────────────────────────────────

  Future<void> _connectSftp() async {
    setState(() => _isConnectingSftp = true);
    try {
      final config = await showDialog<SftpConfig>(
        context: context,
        builder: (_) => SftpConfigDialog(
          initialConfig: BackupService.instance.currentSftpConfig,
        ),
      );
      if (config == null) {
        if (mounted) setState(() => _isConnectingSftp = false);
        return;
      }
      await BackupService.instance.connectSftp(config);
      if (mounted) {
        final account =
            ref.read(backupSftpAccountProvider) ?? config.accountLabel;
        setState(() {
          _sftpAccount = account;
          _storage = _DuplicateStorage.sftp;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'SFTP connection failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isConnectingSftp = false);
    }
  }

  Future<void> _disconnectSftp() async {
    await BackupService.instance.disconnectSftp();
    setState(() {
      _sftpAccount = null;
      _sftpFolderPath = null;
      _sftpFolderName = null;
      if (_storage == _DuplicateStorage.sftp) {
        _storage = _DuplicateStorage.local;
      }
    });
  }

  Future<void> _pickSftpFolder() async {
    final result = await showDialog<CloudFolder?>(
      context: context,
      builder: (_) => const _CloudFolderPickerDialog(
        cloudType: _CloudType.sftp,
      ),
    );
    if (result != null) {
      setState(() {
        _sftpFolderPath = result.id;
        _sftpFolderName = result.displayPath;
      });
    }
  }

  Future<void> _pickLocalDirectory() async {
    final picked = await BookmarkService.instance.pickDirectoryWithBookmark();
    if (picked == null) return;
    setState(() {
      _localDirectory = picked.path;
      _storage = _DuplicateStorage.local;
      _errorMessage = null;
    });
  }

  Future<void> _pickGoogleFolder() async {
    final result = await showDialog<CloudFolder?>(
      context: context,
      builder: (_) => const _CloudFolderPickerDialog(
        cloudType: _CloudType.googleDrive,
      ),
    );
    if (result != null) {
      setState(() {
        _googleFolderId = result.id;
        _googleFolderName = result.displayPath;
      });
    }
  }

  Future<void> _pickDropboxFolder() async {
    final result = await showDialog<CloudFolder?>(
      context: context,
      builder: (_) => const _CloudFolderPickerDialog(
        cloudType: _CloudType.dropbox,
      ),
    );
    if (result != null) {
      setState(() {
        _dropboxFolderPath = result.id;
        _dropboxFolderName = result.displayPath;
      });
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(
          () => _errorMessage = 'Enter a name for the duplicated database.');
      return;
    }

    switch (_storage) {
      case _DuplicateStorage.local:
        if (_localDirectory == null) {
          setState(() =>
              _errorMessage = 'Choose a destination folder — click Browse…');
          return;
        }
        break;
      case _DuplicateStorage.googleDrive:
        if (_googleAccount == null) {
          setState(() => _errorMessage = 'Connect to Google Drive first.');
          return;
        }
        break;
      case _DuplicateStorage.dropbox:
        if (_dropboxAccount == null) {
          setState(() => _errorMessage = 'Connect to Dropbox first.');
          return;
        }
        break;
      case _DuplicateStorage.oneDrive:
        if (_oneDriveAccount == null) {
          setState(() => _errorMessage = 'Connect to OneDrive first.');
          return;
        }
        break;
      case _DuplicateStorage.webDav:
        if (_webDavAccount == null) {
          setState(() => _errorMessage = 'Connect to WebDAV first.');
          return;
        }
        break;
      case _DuplicateStorage.sftp:
        if (_sftpAccount == null) {
          setState(() => _errorMessage = 'Connect to SFTP first.');
          return;
        }
        break;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final sourceBytes = await _readSourceBytes();

      switch (_storage) {
        case _DuplicateStorage.local:
          await _duplicateToLocal(safeName: safeName, bytes: sourceBytes);
          break;
        case _DuplicateStorage.googleDrive:
          await _duplicateToGoogleDrive(
            safeName: safeName,
            name: name,
            bytes: sourceBytes,
          );
          break;
        case _DuplicateStorage.dropbox:
          await _duplicateToDropbox(
            safeName: safeName,
            name: name,
            bytes: sourceBytes,
          );
          break;
        case _DuplicateStorage.oneDrive:
          await _duplicateToOneDrive(
            safeName: safeName,
            name: name,
            bytes: sourceBytes,
          );
          break;
        case _DuplicateStorage.webDav:
          await _duplicateToWebDav(
            safeName: safeName,
            name: name,
            bytes: sourceBytes,
          );
          break;
        case _DuplicateStorage.sftp:
          await _duplicateToSftp(
            safeName: safeName,
            name: name,
            bytes: sourceBytes,
          );
          break;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<Uint8List> _readSourceBytes() async {
    final file = File(widget.sourcePath);
    if (await file.exists()) {
      return file.readAsBytes();
    }

    // Source file missing — for cloud-backed records, re-download fresh bytes
    // using the stored cloud id.
    final storageType = widget.source.storageType;
    final cloudFileId = widget.source.cloudFileId;
    if (cloudFileId == null || cloudFileId.isEmpty) {
      throw Exception('Source database file could not be found on disk.');
    }

    if (storageType == 'googleDrive') {
      return BackupService.instance.downloadGoogleDriveFile(cloudFileId);
    }
    if (storageType == 'dropbox') {
      return BackupService.instance.downloadDropboxFile(cloudFileId);
    }
    if (storageType == 'oneDrive') {
      return BackupService.instance.downloadOneDriveFile(cloudFileId);
    }
    if (storageType == 'webdav') {
      return BackupService.instance.downloadWebDavFile(cloudFileId);
    }
    if (storageType == 'sftp') {
      return BackupService.instance.downloadSftpFile(cloudFileId);
    }
    throw Exception('Source database file could not be found on disk.');
  }

  Future<void> _duplicateToLocal({
    required String safeName,
    required Uint8List bytes,
  }) async {
    final separator = Platform.pathSeparator;
    final outputPath = '$_localDirectory$separator$safeName.kdbx';

    if (await File(outputPath).exists()) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage =
            'A file named "$safeName.kdbx" already exists in that folder.';
      });
      return;
    }

    await File(outputPath).writeAsBytes(bytes, flush: true);

    final fileBookmark =
        await BookmarkService.instance.createBookmarkForPath(outputPath);

    await ref.read(databaseRegistryProvider.notifier).addDatabase(
          nickname: _nameController.text.trim(),
          databasePath: outputPath,
          bookmark: fileBookmark.isNotEmpty ? fileBookmark : null,
          storageType: 'local',
        );

    if (!mounted) return;
    Navigator.of(context).pop();
    await widget.onDuplicated(outputPath);
  }

  Future<void> _duplicateToGoogleDrive({
    required String safeName,
    required String name,
    required Uint8List bytes,
  }) async {
    final cachePath = await _cacheFilePath('google_drive', safeName);
    await File(cachePath).writeAsBytes(bytes, flush: true);

    final driveFileId = await BackupService.instance.uploadBytesToGoogleDrive(
      bytes,
      '$safeName.kdbx',
      folderId: _googleFolderId,
    );

    await ref.read(databaseRegistryProvider.notifier).addDatabase(
          nickname: name,
          databasePath: cachePath,
          storageType: 'googleDrive',
          cloudFileId: driveFileId.isNotEmpty ? driveFileId : null,
          cloudFileName: '$safeName.kdbx',
        );

    if (!mounted) return;
    Navigator.of(context).pop();
    await widget.onDuplicated(cachePath);
  }

  Future<void> _duplicateToDropbox({
    required String safeName,
    required String name,
    required Uint8List bytes,
  }) async {
    final cachePath = await _cacheFilePath('dropbox', safeName);
    await File(cachePath).writeAsBytes(bytes, flush: true);

    final folderPath =
        (_dropboxFolderPath != null && _dropboxFolderPath!.isNotEmpty)
            ? _dropboxFolderPath!
            : '';
    final dropboxFilePath = folderPath.isNotEmpty
        ? '$folderPath/$safeName.kdbx'
        : '/$safeName.kdbx';

    await BackupService.instance.uploadBytesToDropbox(bytes, dropboxFilePath);

    await ref.read(databaseRegistryProvider.notifier).addDatabase(
          nickname: name,
          databasePath: cachePath,
          storageType: 'dropbox',
          cloudFileId: dropboxFilePath.toLowerCase(),
          cloudFileName: '$safeName.kdbx',
        );

    if (!mounted) return;
    Navigator.of(context).pop();
    await widget.onDuplicated(cachePath);
  }

  Future<void> _duplicateToOneDrive({
    required String safeName,
    required String name,
    required Uint8List bytes,
  }) async {
    final cachePath = await _cacheFilePath('onedrive', safeName);
    await File(cachePath).writeAsBytes(bytes, flush: true);

    await BackupService.instance.uploadBytesToOneDrive(
      bytes,
      _oneDriveFolderId ?? 'root',
      '$safeName.kdbx',
    );

    await ref.read(databaseRegistryProvider.notifier).addDatabase(
          nickname: name,
          databasePath: cachePath,
          storageType: 'oneDrive',
          cloudFileId: null,
          cloudFileName: '$safeName.kdbx',
        );

    if (!mounted) return;
    Navigator.of(context).pop();
    await widget.onDuplicated(cachePath);
  }

  Future<void> _duplicateToWebDav({
    required String safeName,
    required String name,
    required Uint8List bytes,
  }) async {
    final cachePath = await _cacheFilePath('webdav', safeName);
    await File(cachePath).writeAsBytes(bytes, flush: true);

    final folderPath = (_webDavFolderPath != null && _webDavFolderPath!.isNotEmpty)
        ? _webDavFolderPath!
        : BackupService.instance.currentWebDavConfig?.rootPath ?? '/';
    final remotePath = await BackupService.instance.uploadNewFileToWebDav(
      bytes,
      folderPath,
      '$safeName.kdbx',
    );

    await ref.read(databaseRegistryProvider.notifier).addDatabase(
          nickname: name,
          databasePath: cachePath,
          storageType: 'webdav',
          cloudFileId: remotePath.isNotEmpty ? remotePath : null,
          cloudFileName: '$safeName.kdbx',
        );

    if (!mounted) return;
    Navigator.of(context).pop();
    await widget.onDuplicated(cachePath);
  }

  Future<void> _duplicateToSftp({
    required String safeName,
    required String name,
    required Uint8List bytes,
  }) async {
    final cachePath = await _cacheFilePath('sftp', safeName);
    await File(cachePath).writeAsBytes(bytes, flush: true);

    final folderPath = (_sftpFolderPath != null && _sftpFolderPath!.isNotEmpty)
        ? _sftpFolderPath!
        : BackupService.instance.currentSftpConfig?.rootPath ?? '/';
    final remotePath = await BackupService.instance.uploadNewFileToSftp(
      bytes,
      folderPath,
      '$safeName.kdbx',
    );

    await ref.read(databaseRegistryProvider.notifier).addDatabase(
          nickname: name,
          databasePath: cachePath,
          storageType: 'sftp',
          cloudFileId: remotePath.isNotEmpty ? remotePath : null,
          cloudFileName: '$safeName.kdbx',
        );

    if (!mounted) return;
    Navigator.of(context).pop();
    await widget.onDuplicated(cachePath);
  }

  Future<String> _cacheFilePath(String storageFolder, String safeName) async {
    final appSupport = await getApplicationSupportDirectory();
    final dir = Directory(
      p.join(appSupport.path, 'cloud_databases', storageFolder),
    );
    await dir.create(recursive: true);

    String candidate = p.join(dir.path, '$safeName.kdbx');
    int index = 2;
    while (await File(candidate).exists()) {
      candidate = p.join(dir.path, '$safeName ($index).kdbx');
      index += 1;
    }
    return candidate;
  }
}

// ── Shared sub-widgets (mirrors create_database_modal layout) ────────────────

class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.iconChild,
    required this.label,
    required this.selected,
    required this.actionLabel,
    required this.onAction,
    required this.onTap,
  });

  final Widget iconChild;
  final String label;
  final bool selected;
  final String actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF3FF) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFFB5C3F8) : _kBorderRow,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFE8F0FE)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(7),
              ),
              child: iconChild,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _uText(
                  12,
                  selected ? _kBlue : _kTitle,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF374151),
                side: const BorderSide(color: Color(0xFFD1D5DB)),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudStorageRow extends StatelessWidget {
  const _CloudStorageRow({
    required this.iconChild,
    required this.provider,
    required this.selected,
    required this.account,
    required this.folderName,
    required this.isConnecting,
    required this.onConnect,
    required this.onDisconnect,
    required this.onPickFolder,
    required this.onSelect,
  });

  final Widget iconChild;
  final String provider;
  final bool selected;
  final String? account;
  final String? folderName;
  final bool isConnecting;
  final VoidCallback? onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback? onPickFolder;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final connected = account != null;
    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF3FF) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFFB5C3F8) : _kBorderRow,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFE8F0FE)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: iconChild,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        provider,
                        style: _uText(
                          12,
                          selected ? _kBlue : _kTitle,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (connected) Text(account!, style: _uText(10, _kLabel)),
                    ],
                  ),
                ),
                if (isConnecting)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                else if (!connected)
                  _FilledButton(label: 'Connect', onPressed: onConnect)
                else
                  _TextDestructiveButton(
                    label: 'Disconnect',
                    onPressed: onDisconnect,
                  ),
              ],
            ),
            if (connected) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(TablerIcons.folder, size: 12, color: _kIcon),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        folderName ?? '/ (root)',
                        style: _uText(11, _kLabel),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onPickFolder ?? () {},
                      child: Text(
                        folderName != null ? 'Change' : 'Select Folder',
                        style: _uText(10, _kBlue, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilledButton extends StatelessWidget {
  const _FilledButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFB9C6FF),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: _uText(11, Colors.white, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

class _TextDestructiveButton extends StatelessWidget {
  const _TextDestructiveButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFEF4444),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: _uText(
          11,
          const Color(0xFFEF4444),
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    );
  }
}

// ── Cloud folder picker (duplicated from create_database_modal) ──────────────

class _CloudFolderPickerDialog extends StatefulWidget {
  const _CloudFolderPickerDialog({required this.cloudType});
  final _CloudType cloudType;

  @override
  State<_CloudFolderPickerDialog> createState() =>
      _CloudFolderPickerDialogState();
}

class _CloudFolderPickerDialogState extends State<_CloudFolderPickerDialog> {
  final List<CloudFolder> _breadcrumb = <CloudFolder>[];
  List<CloudFolder>? _folders;
  String? _error;
  bool _loading = true;

  final _newFolderController = TextEditingController();
  bool _showNewFolder = false;
  bool _creatingFolder = false;

  String get _currentDisplayPath =>
      _breadcrumb.isEmpty ? '/' : _breadcrumb.last.displayPath;

  String _childDisplayPath(String name) {
    final current = _currentDisplayPath;
    return current == '/' ? '/$name' : '$current/$name';
  }

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  @override
  void dispose() {
    _newFolderController.dispose();
    super.dispose();
  }

  Future<void> _loadFolders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<CloudFolder> folders;
      switch (widget.cloudType) {
        case _CloudType.googleDrive:
          folders = await BackupService.instance.listGoogleDriveFolders(
            parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
          );
        case _CloudType.dropbox:
          folders = await BackupService.instance.listDropboxFolders(
            _breadcrumb.isEmpty ? '' : _breadcrumb.last.id,
          );
        case _CloudType.oneDrive:
          folders = await BackupService.instance.listOneDriveFolders(
            parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
          );
        case _CloudType.webDav:
          folders = await BackupService.instance.listWebDavFolders(
            parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
          );
        case _CloudType.sftp:
          folders = await BackupService.instance.listSftpFolders(
            parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
          );
      }
      setState(() {
        _folders = folders;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _createFolder() async {
    final folderName = _newFolderController.text.trim();
    if (folderName.isEmpty) return;
    setState(() => _creatingFolder = true);
    try {
      final CloudFolder created;
      switch (widget.cloudType) {
        case _CloudType.googleDrive:
          final rawCreated = await BackupService.instance
              .createGoogleDriveFolder(
            folderName,
            parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
          );
          created = CloudFolder(
            id: rawCreated.id,
            name: rawCreated.name,
            path: _childDisplayPath(folderName),
          );
        case _CloudType.dropbox:
          final parent = _breadcrumb.isEmpty ? '' : _breadcrumb.last.id;
          final path =
              parent.isEmpty ? '/$folderName' : '$parent/$folderName';
          await BackupService.instance.createDropboxFolder(path);
          created = CloudFolder(
            id: path.toLowerCase().replaceAll(' ', '-'),
            name: folderName,
            path: _childDisplayPath(folderName),
          );
        case _CloudType.oneDrive:
          final rawCreated = await BackupService.instance
              .createOneDriveFolder(
            folderName,
            parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
          );
          created = CloudFolder(
            id: rawCreated.id,
            name: rawCreated.name,
            path: _childDisplayPath(folderName),
          );
        case _CloudType.webDav:
          final rawCreated = await BackupService.instance
              .createWebDavFolder(
            folderName,
            parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
          );
          created = CloudFolder(
            id: rawCreated.id,
            name: rawCreated.name,
            path: rawCreated.path,
          );
        case _CloudType.sftp:
          final rawCreated = await BackupService.instance.createSftpFolder(
            folderName,
            parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
          );
          created = CloudFolder(
            id: rawCreated.id,
            name: rawCreated.name,
            path: rawCreated.path,
          );
      }
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _creatingFolder = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.light(),
      child: Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildHeader(),
              if (_breadcrumb.isNotEmpty) _buildBreadcrumb(),
              SizedBox(
                height: 260,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                _error!,
                                style: _uText(12, const Color(0xFFEF4444)),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : _buildFolderList(),
              ),
              if (_showNewFolder) _buildNewFolderInput(),
              _buildDialogFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final String title;
    final IconData icon;
    switch (widget.cloudType) {
      case _CloudType.googleDrive:
        title = 'Select Google Drive Folder';
        icon = TablerIcons.brand_google_drive;
      case _CloudType.dropbox:
        title = 'Select Dropbox Folder';
        icon = TablerIcons.cloud;
      case _CloudType.oneDrive:
        title = 'Select OneDrive Folder';
        icon = TablerIcons.cloud;
      case _CloudType.webDav:
        title = 'Select WebDAV Folder';
        icon = TablerIcons.server;
      case _CloudType.sftp:
        title = 'Select SFTP Folder';
        icon = TablerIcons.server;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorderSoft)),
      ),
      child: Row(
        children: <Widget>[
          if (_breadcrumb.isNotEmpty)
            GestureDetector(
              onTap: () {
                setState(() => _breadcrumb.removeLast());
                _loadFolders();
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(TablerIcons.arrow_left, size: 14, color: _kBlue),
                    const SizedBox(width: 4),
                    Text(
                      'Back',
                      style: _uText(11, _kBlue, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            )
          else ...<Widget>[
            Icon(icon, size: 16, color: _kBlue),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              _breadcrumb.isEmpty ? title : _breadcrumb.last.name,
              style: _uText(13, _kTitle, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(TablerIcons.x, size: 16, color: _kIcon),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorderSoft)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            GestureDetector(
              onTap: () {
                setState(() => _breadcrumb.clear());
                _loadFolders();
              },
              child: Text('Root', style: _uText(11, _kBlue)),
            ),
            for (int i = 0; i < _breadcrumb.length; i++) ...<Widget>[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(TablerIcons.chevron_right, size: 12, color: _kIcon),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _breadcrumb.removeRange(i + 1, _breadcrumb.length);
                  });
                  _loadFolders();
                },
                child: Text(
                  _breadcrumb[i].name,
                  style: _uText(
                    11,
                    i == _breadcrumb.length - 1 ? _kTitle : _kBlue,
                    fontWeight: i == _breadcrumb.length - 1
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFolderList() {
    final List<CloudFolder> folders = _folders ?? <CloudFolder>[];
    if (folders.isEmpty) {
      return Center(
        child: Text('No folders here.', style: _uText(12, _kLabel)),
      );
    }
    return ListView.builder(
      itemCount: folders.length,
      itemBuilder: (_, i) => _FolderListTile(
        folder: folders[i],
        onNavigate: () {
          setState(() {
            _breadcrumb.add(
              CloudFolder(
                id: folders[i].id,
                name: folders[i].name,
                path: _childDisplayPath(folders[i].name),
              ),
            );
          });
          _loadFolders();
        },
      ),
    );
  }

  Widget _buildNewFolderInput() {
    final canCreateFolder =
        !_creatingFolder && _newFolderController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFF),
        border: Border(top: BorderSide(color: _kBorderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Create a new folder in this location',
            style: _uText(11, _kLabel, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _newFolderController,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (canCreateFolder) {
                      _createFolder();
                    }
                  },
                  style: _uText(12, _kTitle, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: 'New folder name',
                    hintStyle: _uText(12, _kIcon),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kBorderRow),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kBlue, width: 1.4),
                    ),
                    prefixIcon: const Icon(
                      TablerIcons.folder_plus,
                      size: 16,
                      color: _kIcon,
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 38,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: canCreateFolder ? _createFolder : null,
                  icon: _creatingFolder
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(TablerIcons.plus, size: 14),
                  label: Text(_creatingFolder ? 'Creating...' : 'Create'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBlue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFB9C6FF),
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    textStyle:
                        _uText(12, Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDialogFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kBorderSoft)),
      ),
      child: Row(
        children: <Widget>[
          TextButton.icon(
            onPressed: () => setState(() {
              _showNewFolder = !_showNewFolder;
              if (!_showNewFolder) _newFolderController.clear();
            }),
            icon: Icon(
              _showNewFolder ? TablerIcons.x : TablerIcons.folder_plus,
              size: 13,
              color: _kBlue,
            ),
            label: Text(
              _showNewFolder ? 'Cancel' : 'New Folder',
              style: _uText(11, _kBlue, fontWeight: FontWeight.w500),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF374151),
              side: const BorderSide(color: Color(0xFFD1D5DB)),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              final selected = _breadcrumb.isEmpty
                  ? const CloudFolder(id: '', name: '/ (root)', path: '/')
                  : _breadcrumb.last;
              Navigator.of(context).pop(selected);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            child: const Text('Select Path'),
          ),
        ],
      ),
    );
  }
}

class _FolderListTile extends StatefulWidget {
  const _FolderListTile({required this.folder, required this.onNavigate});
  final CloudFolder folder;
  final VoidCallback onNavigate;

  @override
  State<_FolderListTile> createState() => _FolderListTileState();
}

class _FolderListTileState extends State<_FolderListTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onNavigate,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFF5F7FF) : Colors.white,
            border: const Border(bottom: BorderSide(color: _kBorderSoft)),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                TablerIcons.folder,
                size: 15,
                color: _hovered ? _kBlue : _kIcon,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.folder.name,
                  style: _uText(
                    12,
                    _hovered ? _kBlue : _kTitle,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                TablerIcons.chevron_right,
                size: 14,
                color: _hovered ? _kBlue : _kIcon,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Utility ──────────────────────────────────────────────────────────────────

String _shortenPath(String path) {
  const int maxLen = 38;
  final home = Platform.environment['HOME'] ?? '';
  final shortened = home.isNotEmpty ? path.replaceFirst(home, '~') : path;
  if (shortened.length <= maxLen) return shortened;
  return '…${shortened.substring(shortened.length - maxLen + 1)}';
}
