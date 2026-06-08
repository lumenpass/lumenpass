import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/services/cloud_database_service.dart';
import '../../../core/services/cloud_vault_cache.dart';
import '../../../core/services/sftp_service.dart';
import '../../../core/services/s3_service.dart';
import '../../../core/services/webdav_service.dart';
import '../application/database_registry.dart';
import 'cloud_browser_page.dart';
import 'sftp_config_page.dart';
import 's3_config_dialog.dart';
import 'webdav_config_page.dart';

// ── Theme constants (aligned with vault_picker_screen) ────────────────────────

const _kInk = Color(0xFF0A3B48);
const _kMuted = Color(0xFF6B858D);
const _kBorder = Color(0xFFE3EAF0);
const _kBg = Color(0xFFF4F9FA);
const _kDanger = Color(0xFFEF4444);

enum _DuplicateStorage { local, googleDrive, dropbox, oneDrive, webDav, sftp, s3 }

/// Full-screen page that duplicates an existing database to a destination of
/// the user's choice — the local Documents directory / SAF-picked folder,
/// Google Drive, or Dropbox. Mirrors the desktop `DuplicateDatabaseModal`
/// but uses a mobile-native layout.
class DuplicateDatabaseModal extends ConsumerStatefulWidget {
  const DuplicateDatabaseModal({
    super.key,
    required this.source,
    required this.defaultNickname,
    required this.onDuplicated,
  });

  /// The record being duplicated.
  final DatabaseRecord source;

  /// Suggested nickname — typically `<origin> Copy`.
  final String defaultNickname;

  /// Invoked with the new `DatabaseRecord` once the duplicate has been
  /// created and registered. Callers typically show a snack bar.
  final Future<void> Function(DatabaseRecord record) onDuplicated;

  @override
  ConsumerState<DuplicateDatabaseModal> createState() =>
      _DuplicateDatabaseModalState();
}

class _DuplicateDatabaseModalState
    extends ConsumerState<DuplicateDatabaseModal> {
  final TextEditingController _nameController = TextEditingController();

  _DuplicateStorage _storage = _DuplicateStorage.local;

  String? _localDirectory;
  bool _isConnectingGoogle = false;
  bool _isConnectingDropbox = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  // Selected remote destination folder. Null means "root" — matches the
  // desktop modal's default.
  String? _googleFolderId;
  String? _googleFolderName;
  String? _dropboxFolderPath;
  String? _dropboxFolderName;

  bool _isConnectingOneDrive = false;
  String? _oneDriveFolderId;
  String? _oneDriveFolderName;

  bool _isConnectingWebDav = false;
  String? _webDavFolderPath;
  String? _webDavFolderName;

  bool _isConnectingSftp = false;
  String? _sftpFolderPath;
  String? _sftpFolderName;

  bool _isConnectingS3 = false;
  String? _s3FolderPath;
  String? _s3FolderName;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.defaultNickname;
    _loadDefaultLocalDirectory();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadDefaultLocalDirectory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      if (!mounted) return;
      setState(() => _localDirectory = dir.path);
    } catch (_) {}
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kInk,
        foregroundColor: Colors.white,
        title: const Text(
          'Duplicate Database',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionLabel('New Database Name'),
                    const SizedBox(height: 8),
                    _buildNameField(),
                    const SizedBox(height: 22),
                    _sectionLabel('Save To'),
                    const SizedBox(height: 10),
                    _buildStorageOption(
                      storage: _DuplicateStorage.local,
                      iconAsset: 'assets/images/dir.png',
                      title: 'Local Storage',
                      subtitle: _localDirectory ?? 'App documents folder',
                      action: _TileAction(
                        label:
                            _localDirectory == null ? 'Browse' : 'Change',
                        onTap: _isSubmitting ? null : _pickLocalDirectory,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildCloudStorageOption(
                      storage: _DuplicateStorage.googleDrive,
                      iconAsset: 'assets/images/google-drive.png',
                      title: 'Google Drive',
                      configured:
                          CloudDatabaseService.isGoogleDriveConfigured,
                      account: ref.watch(cloudGoogleAccountProvider) ??
                          CloudDatabaseService
                              .instance.currentGoogleAccount?.email,
                      folderName: _googleFolderName,
                      isConnecting: _isConnectingGoogle,
                      onConnect: _connectGoogle,
                      onDisconnect: _disconnectGoogle,
                      onPickFolder: _pickGoogleFolder,
                      notConfiguredMessage:
                          'Google Drive is not configured for this build.',
                    ),
                    const SizedBox(height: 8),
                    _buildCloudStorageOption(
                      storage: _DuplicateStorage.dropbox,
                      iconAsset: 'assets/images/dropbox.png',
                      title: 'Dropbox',
                      configured: CloudDatabaseService.isDropboxConfigured,
                      account: ref.watch(cloudDropboxAccountProvider),
                      folderName: _dropboxFolderName,
                      isConnecting: _isConnectingDropbox,
                      onConnect: _connectDropbox,
                      onDisconnect: _disconnectDropbox,
                      onPickFolder: _pickDropboxFolder,
                      notConfiguredMessage:
                          'Dropbox is not configured for this build.',
                    ),
                    const SizedBox(height: 8),
                    _buildCloudStorageOption(
                      storage: _DuplicateStorage.oneDrive,
                      iconAsset: 'assets/images/onedrive.png',
                      title: 'OneDrive',
                      configured: CloudDatabaseService.isOneDriveConfigured,
                      account: ref.watch(cloudOneDriveAccountProvider),
                      folderName: _oneDriveFolderName,
                      isConnecting: _isConnectingOneDrive,
                      onConnect: _connectOneDrive,
                      onDisconnect: _disconnectOneDrive,
                      onPickFolder: _pickOneDriveFolder,
                      notConfiguredMessage:
                          'OneDrive is not configured for this build.',
                    ),
                    const SizedBox(height: 8),
                    _buildCloudStorageOption(
                      storage: _DuplicateStorage.webDav,
                      iconAsset: 'assets/images/webdav.png',
                      title: 'WebDAV',
                      configured: CloudDatabaseService.isWebDavConfigured,
                      account: ref.watch(cloudWebDavAccountProvider),
                      folderName: _webDavFolderName,
                      isConnecting: _isConnectingWebDav,
                      onConnect: _connectWebDav,
                      onDisconnect: _disconnectWebDav,
                      onPickFolder: _pickWebDavFolder,
                      notConfiguredMessage:
                          'WebDAV is always available.',
                    ),
                    const SizedBox(height: 8),
                    _buildCloudStorageOption(
                      storage: _DuplicateStorage.sftp,
                      iconAsset: 'assets/images/sftp.png',
                      title: 'SFTP',
                      configured: CloudDatabaseService.isSftpConfigured,
                      account: ref.watch(cloudSftpAccountProvider),
                      folderName: _sftpFolderName,
                      isConnecting: _isConnectingSftp,
                      onConnect: _connectSftp,
                      onDisconnect: _disconnectSftp,
                      onPickFolder: _pickSftpFolder,
                      notConfiguredMessage:
                          'SFTP is always available.',
                    ),
                    const SizedBox(height: 8),
                    _buildCloudStorageOption(
                      storage: _DuplicateStorage.s3,
                      iconAsset: 'assets/images/aws-s3-icon.png',
                      title: 'Amazon S3',
                      configured: CloudDatabaseService.isS3Configured,
                      account: ref.watch(cloudS3AccountProvider),
                      folderName: _s3FolderName,
                      isConnecting: _isConnectingS3,
                      onConnect: _connectS3,
                      onDisconnect: _disconnectS3,
                      onPickFolder: _pickS3Folder,
                      notConfiguredMessage:
                          'Amazon S3 is always available.',
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
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
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _kInk,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    );
  }

  Widget _buildNameField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: TextField(
        controller: _nameController,
        enabled: !_isSubmitting,
        style: const TextStyle(
          color: _kInk,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        onChanged: (_) {
          if (_errorMessage != null) {
            setState(() => _errorMessage = null);
          }
        },
        decoration: const InputDecoration(
          hintText: 'e.g. My Vault Copy',
          hintStyle: TextStyle(color: _kMuted, fontSize: 14),
          contentPadding:
              EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildStorageOption({
    required _DuplicateStorage storage,
    required String iconAsset,
    required String title,
    required String subtitle,
    _TileAction? action,
    _TileAction? secondaryAction,
    bool disabled = false,
  }) {
    final selected = _storage == storage;
    final opacity = disabled ? 0.45 : 1.0;
    return Opacity(
      opacity: opacity,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: (_isSubmitting || disabled)
              ? null
              : () => setState(() {
                    _storage = storage;
                    _errorMessage = null;
                  }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? _kInk : _kBorder,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _kBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Image.asset(iconAsset, fit: BoxFit.contain),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _kInk,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _kMuted,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                      if (secondaryAction != null) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: secondaryAction.onTap,
                          child: Text(
                            secondaryAction.label,
                            style: const TextStyle(
                              color: _kDanger,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: 8),
                  _buildActionButton(action),
                ],
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: selected ? _kInk : _kMuted.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(_TileAction action) {
    final enabled = action.onTap != null && !_isSubmitting;
    return OutlinedButton(
      onPressed: enabled ? action.onTap : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        foregroundColor: _kInk,
        side: BorderSide(color: _kBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        action.label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildError(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: _kDanger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: _kDanger, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: Colors.black26,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottom),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _isSubmitting ? null : () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kInk,
                  side: const BorderSide(color: _kBorder),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _kInk,
                  disabledBackgroundColor: _kMuted.withValues(alpha: 0.4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Duplicate'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Subtitles / actions for cloud tiles ─────────────────────────────────

  /// Tile specialised for Google Drive / Dropbox. Shows configured state,
  /// account email, and destination folder; exposes `Connect`, `Change`
  /// (folder picker) and `Disconnect` actions — mirroring the desktop modal.
  Widget _buildCloudStorageOption({
    required _DuplicateStorage storage,
    required String iconAsset,
    required String title,
    required bool configured,
    required String? account,
    required String? folderName,
    required bool isConnecting,
    required Future<void> Function() onConnect,
    required Future<void> Function() onDisconnect,
    required Future<void> Function() onPickFolder,
    required String notConfiguredMessage,
  }) {
    if (!configured) {
      return _buildStorageOption(
        storage: storage,
        iconAsset: iconAsset,
        title: title,
        subtitle: notConfiguredMessage,
        disabled: true,
      );
    }

    final connected = account != null && account.isNotEmpty;
    final subtitle = connected
        ? '$account\nFolder: ${folderName ?? '/ (root)'}'
        : 'Connect your ${title.toLowerCase()} account to upload.';

    _TileAction? action;
    if (!connected) {
      action = _TileAction(
        label: isConnecting ? 'Connecting…' : 'Connect',
        onTap: isConnecting || _isSubmitting ? null : onConnect,
      );
    } else {
      // Primary inline action = change folder. Disconnect is a secondary
      // trailing link so the tile doesn't grow too tall on narrow screens.
      action = _TileAction(
        label: 'Change',
        onTap: _isSubmitting ? null : onPickFolder,
      );
    }

    return _buildStorageOption(
      storage: storage,
      iconAsset: iconAsset,
      title: title,
      subtitle: subtitle,
      action: action,
      secondaryAction: connected
          ? _TileAction(
              label: 'Disconnect',
              onTap: _isSubmitting ? null : onDisconnect,
            )
          : null,
    );
  }

  // ── Picker / connection handlers ────────────────────────────────────────

  Future<void> _pickLocalDirectory() async {
    try {
      final picked = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose destination folder',
      );
      if (!mounted || picked == null || picked.isEmpty) return;
      setState(() {
        _localDirectory = picked;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not pick folder: $e');
    }
  }

  Future<void> _connectGoogle() async {
    setState(() => _isConnectingGoogle = true);
    try {
      await CloudDatabaseService.instance.connectGoogle();
      if (!mounted) return;
      final email = ref.read(cloudGoogleAccountProvider) ??
          CloudDatabaseService.instance.currentGoogleAccount?.email;
      if (email != null && email.isNotEmpty) {
        setState(() {
          _storage = _DuplicateStorage.googleDrive;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Google sign-in failed: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    } finally {
      if (mounted) setState(() => _isConnectingGoogle = false);
    }
  }

  Future<void> _disconnectGoogle() async {
    try {
      await CloudDatabaseService.instance.disconnectGoogle();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
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
      await CloudDatabaseService.instance.connectDropbox();
      if (!mounted) return;
      if (ref.read(cloudDropboxAccountProvider) != null) {
        setState(() {
          _storage = _DuplicateStorage.dropbox;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Dropbox connection failed: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    } finally {
      if (mounted) setState(() => _isConnectingDropbox = false);
    }
  }

  Future<void> _disconnectDropbox() async {
    try {
      await CloudDatabaseService.instance.disconnectDropbox();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _dropboxFolderPath = null;
      _dropboxFolderName = null;
      if (_storage == _DuplicateStorage.dropbox) {
        _storage = _DuplicateStorage.local;
      }
    });
  }

  Future<void> _pickGoogleFolder() async {
    // Ensure we have an active Google session before opening the picker.
    // Without this the picker would just show an error screen for "Not
    // signed in to Google Drive" — very confusing after a restart where the
    // `cloudGoogleAccountProvider` was set optimistically by silent sign-in
    // but the underlying `GoogleSignIn.currentUser` handle was cleared.
    if (CloudDatabaseService.instance.currentGoogleAccount == null) {
      try {
        await CloudDatabaseService.instance.connectGoogle();
      } catch (e) {
        if (!mounted) return;
        setState(() => _errorMessage =
            'Google sign-in failed: ${e.toString().replaceFirst('Exception: ', '')}');
        return;
      }
      if (CloudDatabaseService.instance.currentGoogleAccount == null) return;
    }

    if (!mounted) return;
    final selected = await Navigator.of(context).push<CloudSelectedFolder?>(
      MaterialPageRoute<CloudSelectedFolder?>(
        builder: (_) => const CloudBrowserPage(
          cloudType: CloudKind.googleDrive,
          mode: CloudBrowserMode.selectFolder,
        ),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _googleFolderId = selected.id.isEmpty ? null : selected.id;
      _googleFolderName = selected.displayPath;
      _storage = _DuplicateStorage.googleDrive;
      _errorMessage = null;
    });
  }

  Future<void> _pickDropboxFolder() async {
    if (CloudDatabaseService.instance.currentDropboxToken == null) {
      try {
        await CloudDatabaseService.instance.connectDropbox();
      } catch (e) {
        if (!mounted) return;
        setState(() => _errorMessage =
            'Dropbox connection failed: ${e.toString().replaceFirst('Exception: ', '')}');
        return;
      }
      if (CloudDatabaseService.instance.currentDropboxToken == null) return;
    }

    if (!mounted) return;
    final selected = await Navigator.of(context).push<CloudSelectedFolder?>(
      MaterialPageRoute<CloudSelectedFolder?>(
        builder: (_) => const CloudBrowserPage(
          cloudType: CloudKind.dropbox,
          mode: CloudBrowserMode.selectFolder,
        ),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _dropboxFolderPath = selected.id.isEmpty ? null : selected.id;
      _dropboxFolderName = selected.displayPath;
      _storage = _DuplicateStorage.dropbox;
      _errorMessage = null;
    });
  }

  // ── OneDrive handlers ──────────────────────────────────────────────────

  Future<void> _connectOneDrive() async {
    setState(() => _isConnectingOneDrive = true);
    try {
      await CloudDatabaseService.instance.connectOneDrive();
      if (!mounted) return;
      final email = ref.read(cloudOneDriveAccountProvider) ??
          CloudDatabaseService.instance.currentGoogleAccount?.email;
      if (email != null && email.isNotEmpty) {
        setState(() {
          _storage = _DuplicateStorage.oneDrive;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'OneDrive sign-in failed: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    } finally {
      if (mounted) setState(() => _isConnectingOneDrive = false);
    }
  }

  Future<void> _disconnectOneDrive() async {
    try {
      await CloudDatabaseService.instance.disconnectOneDrive();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _oneDriveFolderId = null;
      _oneDriveFolderName = null;
      if (_storage == _DuplicateStorage.oneDrive) {
        _storage = _DuplicateStorage.local;
      }
    });
  }

  Future<void> _pickOneDriveFolder() async {
    if (CloudDatabaseService.instance.currentGoogleAccount == null) {
      try {
        await CloudDatabaseService.instance.connectOneDrive();
      } catch (e) {
        if (!mounted) return;
        setState(() => _errorMessage =
            'OneDrive sign-in failed: ${e.toString().replaceFirst('Exception: ', '')}');
        return;
      }
      if (CloudDatabaseService.instance.currentGoogleAccount == null) return;
    }

    if (!mounted) return;
    final selected = await Navigator.of(context).push<CloudSelectedFolder?>(
      MaterialPageRoute<CloudSelectedFolder?>(
        builder: (_) => const CloudBrowserPage(
          cloudType: CloudKind.oneDrive,
          mode: CloudBrowserMode.selectFolder,
        ),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _oneDriveFolderId = selected.id.isEmpty ? null : selected.id;
      _oneDriveFolderName = selected.displayPath;
      _storage = _DuplicateStorage.oneDrive;
      _errorMessage = null;
    });
  }

  // ── WebDAV handlers ────────────────────────────────────────────────────

  Future<void> _connectWebDav() async {
    setState(() => _isConnectingWebDav = true);
    try {
      final config = await Navigator.of(context).push<WebDavConfig>(
        MaterialPageRoute<WebDavConfig>(
          builder: (_) => WebDavConfigPage(
            initialConfig:
                CloudDatabaseService.instance.currentWebDavConfig,
          ),
        ),
      );
      if (config == null) {
        if (mounted) setState(() => _isConnectingWebDav = false);
        return;
      }
      await CloudDatabaseService.instance.connectWebDav(config);
      if (!mounted) return;
      final account = ref.read(cloudWebDavAccountProvider) ?? config.accountLabel;
      if (account.isNotEmpty) {
        setState(() {
          _storage = _DuplicateStorage.webDav;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'WebDAV connection failed: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    } finally {
      if (mounted) setState(() => _isConnectingWebDav = false);
    }
  }

  Future<void> _disconnectWebDav() async {
    try {
      await CloudDatabaseService.instance.disconnectWebDav();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _webDavFolderPath = null;
      _webDavFolderName = null;
      if (_storage == _DuplicateStorage.webDav) {
        _storage = _DuplicateStorage.local;
      }
    });
  }

  Future<void> _pickWebDavFolder() async {
    if (CloudDatabaseService.instance.currentWebDavConfig == null) {
      if (!mounted) return;
      setState(
          () => _errorMessage = 'WebDAV not configured. Connect first.');
      return;
    }

    if (!mounted) return;
    final selected = await Navigator.of(context).push<CloudSelectedFolder?>(
      MaterialPageRoute<CloudSelectedFolder?>(
        builder: (_) => const CloudBrowserPage(
          cloudType: CloudKind.webdav,
          mode: CloudBrowserMode.selectFolder,
        ),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _webDavFolderPath = selected.id.isEmpty ? null : selected.id;
      _webDavFolderName = selected.displayPath;
      _storage = _DuplicateStorage.webDav;
      _errorMessage = null;
    });
  }

  // ── SFTP handlers ──────────────────────────────────────────────────────

  Future<void> _connectSftp() async {
    setState(() => _isConnectingSftp = true);
    try {
      final config = await Navigator.of(context).push<SftpConfig>(
        MaterialPageRoute<SftpConfig>(
          builder: (_) => SftpConfigPage(
            initialConfig: CloudDatabaseService.instance.currentSftpConfig,
          ),
        ),
      );
      if (config == null) {
        if (mounted) setState(() => _isConnectingSftp = false);
        return;
      }
      await CloudDatabaseService.instance.connectSftp(config);
      if (!mounted) return;
      final account = ref.read(cloudSftpAccountProvider) ?? config.accountLabel;
      if (account.isNotEmpty) {
        setState(() {
          _storage = _DuplicateStorage.sftp;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'SFTP connection failed: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    } finally {
      if (mounted) setState(() => _isConnectingSftp = false);
    }
  }

  Future<void> _disconnectSftp() async {
    try {
      await CloudDatabaseService.instance.disconnectSftp();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _sftpFolderPath = null;
      _sftpFolderName = null;
      if (_storage == _DuplicateStorage.sftp) {
        _storage = _DuplicateStorage.local;
      }
    });
  }

  Future<void> _connectS3() async {
    setState(() => _isConnectingS3 = true);
    try {
      final account = await Navigator.of(context).push<String?>(
        MaterialPageRoute<String?>(
          builder: (_) => const S3ConfigDialog(),
          fullscreenDialog: true,
        ),
      );
      if (account == null) {
        if (mounted) setState(() => _isConnectingS3 = false);
        return;
      }
      if (!mounted) return;
      if (ref.read(cloudS3AccountProvider) != null) {
        setState(() {
          _storage = _DuplicateStorage.s3;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'S3 connection failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isConnectingS3 = false);
    }
  }

  Future<void> _disconnectS3() async {
    try {
      await CloudDatabaseService.instance.disconnectS3();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _s3FolderPath = null;
      _s3FolderName = null;
      if (_storage == _DuplicateStorage.s3) {
        _storage = _DuplicateStorage.local;
      }
    });
  }

  Future<void> _pickS3Folder() async {
    if (!CloudDatabaseService.instance.isS3Connected) {
      if (!mounted) return;
      setState(() => _errorMessage = 'S3 not configured. Connect first.');
      return;
    }

    final selected = await Navigator.of(context).push<CloudSelectedFolder?>(
      MaterialPageRoute<CloudSelectedFolder?>(
        builder: (_) => const CloudBrowserPage(
          cloudType: CloudKind.s3,
          mode: CloudBrowserMode.selectFolder,
        ),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _s3FolderPath = selected.id.isEmpty ? null : selected.id;
      _s3FolderName = selected.displayPath;
      _storage = _DuplicateStorage.s3;
      _errorMessage = null;
    });
  }

  Future<void> _pickSftpFolder() async {
    if (CloudDatabaseService.instance.currentSftpConfig == null) {
      if (!mounted) return;
      setState(() => _errorMessage = 'SFTP not configured. Connect first.');
      return;
    }

    if (!mounted) return;
    final selected = await Navigator.of(context).push<CloudSelectedFolder?>(
      MaterialPageRoute<CloudSelectedFolder?>(
        builder: (_) => const CloudBrowserPage(
          cloudType: CloudKind.sftp,
          mode: CloudBrowserMode.selectFolder,
        ),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _sftpFolderPath = selected.id.isEmpty ? null : selected.id;
      _sftpFolderName = selected.displayPath;
      _storage = _DuplicateStorage.sftp;
      _errorMessage = null;
    });
  }

  // ── Submit ──────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() =>
          _errorMessage = 'Enter a name for the duplicated database.');
      return;
    }

    switch (_storage) {
      case _DuplicateStorage.local:
        if (_localDirectory == null || _localDirectory!.isEmpty) {
          setState(
              () => _errorMessage = 'Choose a destination folder first.');
          return;
        }
        break;
      case _DuplicateStorage.googleDrive:
        if (!CloudDatabaseService.isGoogleDriveConfigured) {
          setState(
              () => _errorMessage = 'Google Drive is not configured.');
          return;
        }
        final email = ref.read(cloudGoogleAccountProvider) ??
            CloudDatabaseService.instance.currentGoogleAccount?.email;
        if (email == null || email.isEmpty) {
          setState(() => _errorMessage = 'Connect Google Drive first.');
          return;
        }
        break;
      case _DuplicateStorage.dropbox:
        if (!CloudDatabaseService.isDropboxConfigured) {
          setState(() => _errorMessage = 'Dropbox is not configured.');
          return;
        }
        if (ref.read(cloudDropboxAccountProvider) == null) {
          setState(() => _errorMessage = 'Connect Dropbox first.');
          return;
        }
        break;
      case _DuplicateStorage.oneDrive:
        if (!CloudDatabaseService.isOneDriveConfigured) {
          setState(() => _errorMessage = 'OneDrive is not configured.');
          return;
        }
        if (ref.read(cloudOneDriveAccountProvider) == null) {
          setState(() => _errorMessage = 'Connect OneDrive first.');
          return;
        }
        break;
      case _DuplicateStorage.webDav:
        if (!CloudDatabaseService.isWebDavConfigured) {
          setState(() => _errorMessage = 'WebDAV is not configured.');
          return;
        }
        if (ref.read(cloudWebDavAccountProvider) == null) {
          setState(() => _errorMessage = 'Connect WebDAV first.');
          return;
        }
        break;
      case _DuplicateStorage.sftp:
        if (!CloudDatabaseService.isSftpConfigured) {
          setState(() => _errorMessage = 'SFTP is not configured.');
          return;
        }
        if (ref.read(cloudSftpAccountProvider) == null) {
          setState(() => _errorMessage = 'Connect SFTP first.');
          return;
        }
        break;
      case _DuplicateStorage.s3:
        if (!CloudDatabaseService.isS3Configured) {
          setState(() => _errorMessage = 'S3 is not configured.');
          return;
        }
        if (ref.read(cloudS3AccountProvider) == null) {
          setState(() => _errorMessage = 'Connect S3 first.');
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
      final bytes = await _readSourceBytes();

      final DatabaseRecord added;
      switch (_storage) {
        case _DuplicateStorage.local:
          added = await _duplicateToLocal(
            safeName: safeName,
            name: name,
            bytes: bytes,
          );
          break;
        case _DuplicateStorage.googleDrive:
          added = await _duplicateToGoogleDrive(
            safeName: safeName,
            name: name,
            bytes: bytes,
          );
          break;
        case _DuplicateStorage.dropbox:
          added = await _duplicateToDropbox(
            safeName: safeName,
            name: name,
            bytes: bytes,
          );
          break;
        case _DuplicateStorage.oneDrive:
          added = await _duplicateToOneDrive(
            safeName: safeName,
            name: name,
            bytes: bytes,
          );
          break;
        case _DuplicateStorage.webDav:
          added = await _duplicateToWebDav(
            safeName: safeName,
            name: name,
            bytes: bytes,
          );
          break;
        case _DuplicateStorage.sftp:
          added = await _duplicateToSftp(
            safeName: safeName,
            name: name,
            bytes: bytes,
          );
          break;
        case _DuplicateStorage.s3:
          added = await _duplicateToS3(
            safeName: safeName,
            name: name,
            bytes: bytes,
          );
          break;
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onDuplicated(added);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<Uint8List> _readSourceBytes() async {
    final file = File(widget.source.databasePath);
    if (await file.exists()) return file.readAsBytes();

    // Source file missing — re-download from cloud when possible.
    final storageType = widget.source.storageType;
    final cloudFileId = widget.source.cloudFileId;
    if (cloudFileId == null || cloudFileId.isEmpty) {
      throw Exception('Source database file could not be found.');
    }
    if (storageType == 'googleDrive') {
      return CloudDatabaseService.instance.downloadGoogleDriveFile(cloudFileId);
    }
    if (storageType == 'dropbox') {
      return CloudDatabaseService.instance.downloadDropboxFile(cloudFileId);
    }
    if (storageType == 'oneDrive') {
      return CloudDatabaseService.instance.downloadOneDriveFile(cloudFileId);
    }
    if (storageType == 'webdav') {
      return CloudDatabaseService.instance.downloadWebDavFile(cloudFileId);
    }
    throw Exception('Source database file could not be found.');
  }

  Future<DatabaseRecord> _duplicateToLocal({
    required String safeName,
    required String name,
    required Uint8List bytes,
  }) async {
    final destination = _nextAvailablePath(_localDirectory!, safeName);
    await Directory(p.dirname(destination)).create(recursive: true);
    await File(destination).writeAsBytes(bytes, flush: true);

    return ref.read(databaseRegistryProvider.notifier).addDatabase(
          nickname: name,
          databasePath: destination,
          storageType: 'local',
        );
  }

  Future<DatabaseRecord> _duplicateToGoogleDrive({
    required String safeName,
    required String name,
    required Uint8List bytes,
  }) async {
    final fileName = '$safeName.kdbx';
    final fileId = await CloudDatabaseService.instance.uploadToGoogleDrive(
      bytes,
      fileName,
      folderId: _googleFolderId,
    );

    final cachePath = await cloudDatabaseCachePath(
      storageType: 'googleDrive',
      cloudFileId: fileId.isNotEmpty ? fileId : fileName,
      cloudFileName: fileName,
    );
    await Directory(p.dirname(cachePath)).create(recursive: true);
    await File(cachePath).writeAsBytes(bytes, flush: true);

    return ref.read(databaseRegistryProvider.notifier).addDatabase(
          nickname: name,
          databasePath: cachePath,
          storageType: 'googleDrive',
          cloudFileId: fileId.isNotEmpty ? fileId : null,
          cloudFileName: fileName,
        );
  }

  Future<DatabaseRecord> _duplicateToDropbox({
    required String safeName,
    required String name,
    required Uint8List bytes,
  }) async {
    final fileName = '$safeName.kdbx';
    // Normalise the selected folder — "/" or "" both mean root; otherwise
    // concatenate with a single separator.
    final folder = (_dropboxFolderPath ?? '').trim();
    final normalisedFolder = folder.isEmpty || folder == '/'
        ? ''
        : (folder.endsWith('/')
            ? folder.substring(0, folder.length - 1)
            : folder);
    final dropboxPath =
        normalisedFolder.isEmpty ? '/$fileName' : '$normalisedFolder/$fileName';
    await CloudDatabaseService.instance.uploadToDropbox(bytes, dropboxPath);

    final cachePath = await cloudDatabaseCachePath(
      storageType: 'dropbox',
      cloudFileId: dropboxPath.toLowerCase(),
      cloudFileName: fileName,
    );
    await Directory(p.dirname(cachePath)).create(recursive: true);
    await File(cachePath).writeAsBytes(bytes, flush: true);

    return ref.read(databaseRegistryProvider.notifier).addDatabase(
          nickname: name,
          databasePath: cachePath,
          storageType: 'dropbox',
          cloudFileId: dropboxPath.toLowerCase(),
          cloudFileName: fileName,
        );
  }

  Future<DatabaseRecord> _duplicateToOneDrive({
    required String safeName,
    required String name,
    required Uint8List bytes,
  }) async {
    final fileName = '$safeName.kdbx';
    final fileId = await CloudDatabaseService.instance.uploadNewFileToOneDrive(
      bytes,
      _oneDriveFolderId ?? 'root',
      fileName,
    );

    final cachePath = await cloudDatabaseCachePath(
      storageType: 'oneDrive',
      cloudFileId: fileId.isNotEmpty ? fileId : fileName,
      cloudFileName: fileName,
    );
    await Directory(p.dirname(cachePath)).create(recursive: true);
    await File(cachePath).writeAsBytes(bytes, flush: true);

    return ref.read(databaseRegistryProvider.notifier).addDatabase(
          nickname: name,
          databasePath: cachePath,
          storageType: 'oneDrive',
          cloudFileId: fileId.isNotEmpty ? fileId : null,
          cloudFileName: fileName,
        );
  }

  Future<DatabaseRecord> _duplicateToWebDav({
    required String safeName,
    required String name,
    required Uint8List bytes,
  }) async {
    final fileName = '$safeName.kdbx';
    final folder = (_webDavFolderPath ?? '').trim();
    final defaultPath =
        CloudDatabaseService.instance.currentWebDavConfig?.rootPath ?? '/';
    final baseFolder = folder.isEmpty || folder == '/' ? defaultPath : folder;
    final remotePath = await CloudDatabaseService.instance.uploadNewFileToWebDav(
      bytes,
      baseFolder,
      fileName,
    );

    final cachePath = await cloudDatabaseCachePath(
      storageType: 'webdav',
      cloudFileId: remotePath,
      cloudFileName: fileName,
    );
    await Directory(p.dirname(cachePath)).create(recursive: true);
    await File(cachePath).writeAsBytes(bytes, flush: true);

    return ref.read(databaseRegistryProvider.notifier).addDatabase(
          nickname: name,
          databasePath: cachePath,
          storageType: 'webdav',
          cloudFileId: remotePath,
          cloudFileName: fileName,
        );
  }

  Future<DatabaseRecord> _duplicateToSftp({
    required String safeName,
    required String name,
    required Uint8List bytes,
  }) async {
    final fileName = '$safeName.kdbx';
    final folder = (_sftpFolderPath ?? '').trim();
    final defaultPath =
        CloudDatabaseService.instance.currentSftpConfig?.rootPath ?? '/';
    final baseFolder = folder.isEmpty || folder == '/' ? defaultPath : folder;
    final remotePath = await CloudDatabaseService.instance.uploadNewFileToSftp(
      bytes,
      baseFolder,
      fileName,
    );

    final cachePath = await cloudDatabaseCachePath(
      storageType: 'sftp',
      cloudFileId: remotePath,
      cloudFileName: fileName,
    );
    await Directory(p.dirname(cachePath)).create(recursive: true);
    await File(cachePath).writeAsBytes(bytes, flush: true);

    return ref.read(databaseRegistryProvider.notifier).addDatabase(
          nickname: name,
          databasePath: cachePath,
          storageType: 'sftp',
          cloudFileId: remotePath,
          cloudFileName: fileName,
        );
  }

  Future<DatabaseRecord> _duplicateToS3({
    required String safeName,
    required String name,
    required Uint8List bytes,
  }) async {
    final fileName = '$safeName.kdbx';
    final folder = (_s3FolderPath ?? '').trim();
    final defaultPath =
        S3Service.instance.currentRootPath ?? '';
    final baseFolder = folder.isEmpty || folder == '/' ? defaultPath : folder;
    final key = await CloudDatabaseService.instance.uploadNewFileToS3(
      bytes,
      baseFolder,
      fileName,
    );

    final cachePath = await cloudDatabaseCachePath(
      storageType: 's3',
      cloudFileId: key,
      cloudFileName: fileName,
    );
    await Directory(p.dirname(cachePath)).create(recursive: true);
    await File(cachePath).writeAsBytes(bytes, flush: true);

    return ref.read(databaseRegistryProvider.notifier).addDatabase(
          nickname: name,
          databasePath: cachePath,
          storageType: 's3',
          cloudFileId: key,
          cloudFileName: fileName,
        );
  }

  String _nextAvailablePath(String directory, String safeName) {
    String candidate = p.join(directory, '$safeName.kdbx');
    int index = 2;
    while (File(candidate).existsSync()) {
      candidate = p.join(directory, '$safeName ($index).kdbx');
      index += 1;
    }
    return candidate;
  }
}

class _TileAction {
  const _TileAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;
}
