import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/services/backup_service.dart';
import '../../../core/services/bookmark_service.dart';
import '../../../presentation/theme/app_theme.dart';
import '../../cloud/application/cloud_disconnect.dart';
import '../../cloud/application/cloud_service_provider.dart';
import '../application/database_registry.dart';
import 'provider_config_route.dart';
import 'storage_source_list.dart';
import '../../../presentation/theme/drive_clue_tokens.dart';
import '../../../presentation/widgets/drive_clue/dc_flow_page.dart';

const Color _kCanvas = DcColors.sidebar;
const Color _kPaperBright = DcColors.lightSurface;
const Color _kBorderSoft = DcColors.sidebarLine;
const Color _kTitle = DcColors.sidebarText;
const Color _kLabel = DcColors.sidebarMuted;
const Color _kIcon = DcColors.sidebarMuted;
const Color _kBlue = DcColors.selection;
const Color _kInkBorder = DcColors.lightLineStrong;
const Color _kMintSoft = DcColors.lightSelectionFill;
const Color _kYellow = DcColors.lightSelectionFill;

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
    fontFamily: 'Ubuntu Sans',
    letterSpacing: letterSpacing,
  );
}

enum _StorageType { local, googleDrive, dropbox, oneDrive, webDav, sftp, s3 }

enum _CloudType { googleDrive, dropbox, oneDrive, webDav, sftp, s3 }

class OpenExistingDatabaseModal extends ConsumerStatefulWidget {
  const OpenExistingDatabaseModal({super.key, required this.onOpened});

  final Future<void> Function(String dbPath) onOpened;

  @override
  ConsumerState<OpenExistingDatabaseModal> createState() =>
      _OpenExistingDatabaseModalState();
}

class _OpenExistingDatabaseModalState
    extends ConsumerState<OpenExistingDatabaseModal> {
  _StorageType _storage = _StorageType.local;
  _SelectedDatabaseFile? _selectedFile;
  List<_SelectedDatabaseFile> _localFiles = const <_SelectedDatabaseFile>[];
  bool _isOpening = false;
  String? _errorMessage;

  String? _googleAccount;
  bool _isConnectingGoogle = false;

  String? _dropboxAccount;
  bool _isConnectingDropbox = false;

  String? _oneDriveAccount;
  bool _isConnectingOneDrive = false;

  String? _webDavAccount;
  bool _isConnectingWebDav = false;

  String? _sftpAccount;
  bool _isConnectingSftp = false;

  String? _s3Account;
  bool _isConnectingS3 = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreCloudState());
  }

  Future<void> _restoreCloudState() async {
    final googleEmail =
        await BackupService.instance.restoreGoogleSessionEmail();
    if (!mounted) return;
    final dropboxEmail = ref.read(backupDropboxAccountProvider);
    final oneDriveEmail = ref.read(backupOneDriveAccountProvider);
    final webDavAccount = ref.read(backupWebDavAccountProvider);
    final sftpAccount = ref.read(backupSftpAccountProvider);
    final s3Account = ref.read(backupS3AccountProvider);
    if (googleEmail != null ||
        dropboxEmail != null ||
        oneDriveEmail != null ||
        webDavAccount != null ||
        sftpAccount != null ||
        s3Account != null) {
      setState(() {
        _googleAccount = googleEmail;
        _dropboxAccount = dropboxEmail;
        _oneDriveAccount = oneDriveEmail;
        _webDavAccount = webDavAccount;
        _sftpAccount = sftpAccount;
        _s3Account = s3Account;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedFile = _selectedFile;
    final validationMessage =
        selectedFile == null ? null : _selectionError(selectedFile);
    String? combinedValidationMessage = validationMessage;
    for (final localFile in _localFiles) {
      final blocking = _blockingSelectionError(localFile);
      if (blocking != null) {
        combinedValidationMessage = blocking;
        break;
      }
    }

    return Theme(
      data: AppTheme.driveClueLight(),
      child: DcFlowPage(
        title: 'Open Existing Database',
        subtitle: 'Pick a database file from local storage or a cloud provider',
        icon: TablerIcons.folder_open,
        iconBackground: _kBlue,
        onBack: _isOpening ? null : () => Navigator.of(context).pop(),
        inset: false,
        scrollable: false,
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildStorageSection(),
              if (selectedFile != null && _localFiles.isEmpty) ...<Widget>[
                const SizedBox(height: 16),
                _buildSelectedFileCard(selectedFile),
              ],
              if (_localFiles.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                _buildLocalFilesCard(),
              ],
              if (_errorMessage != null ||
                  combinedValidationMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                _buildError(combinedValidationMessage ?? _errorMessage!),
              ],
            ],
          ),
        ),
        footer: _buildFooterRow(
          canSubmit: combinedValidationMessage == null,
        ),
      ),
    );
  }

  Widget _buildStorageSection() {
    final selectedFile = _selectedFile;
    final bool dropboxConfigured = BackupService.isDropboxConfigured;

    StorageSourceEntry cloud({
      required _StorageType type,
      required String asset,
      required Color brand,
      required String title,
      required String? account,
      required bool connecting,
      required VoidCallback? onConnect,
      required VoidCallback onDisconnect,
      required VoidCallback onPickFile,
      String? disabledReason,
    }) {
      final bool connected = account != null;
      final String? fileLabel =
          selectedFile?.storage == type ? selectedFile!.displayPath : null;
      return StorageSourceEntry(
        id: type.name,
        icon: Image.asset(asset, width: 18, height: 18),
        brandColor: brand,
        title: title,
        account: account,
        detail:
            connected ? (fileLabel ?? 'No database selected') : 'Not connected',
        ready: connected,
        selected: connected && _storage == type,
        busy: connecting,
        actionLabel: connected
            ? (fileLabel != null ? 'Change file' : 'Select file')
            : 'Connect',
        onAction: connected ? onPickFile : onConnect,
        onSelect: () => _selectStorage(type),
        onDisconnect: connected ? onDisconnect : null,
        disabledReason: disabledReason,
      );
    }

    final bool localPicked = _localFiles.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 18),
        StorageSourceList(
          entries: <StorageSourceEntry>[
            StorageSourceEntry(
              id: _StorageType.local.name,
              icon: Image.asset('assets/images/dir.png', width: 18, height: 18),
              brandColor: StorageBrandColors.local,
              title: 'This Mac',
              detail: localPicked
                  ? (_localFiles.length == 1
                      ? _shortenPath(_localFiles.first.displayPath)
                      : '${_localFiles.length} databases selected')
                  : 'Choose a database file on this Mac',
              ready: true,
              selected: _storage == _StorageType.local,
              actionLabel: localPicked ? 'Change files' : 'Browse',
              onAction: _pickLocalFile,
              onSelect: () => _selectStorage(_StorageType.local),
            ),
            cloud(
              type: _StorageType.googleDrive,
              asset: 'assets/images/google-drive.png',
              brand: StorageBrandColors.googleDrive,
              title: 'Google Drive',
              account: _googleAccount,
              connecting: _isConnectingGoogle,
              onConnect: _connectGoogle,
              onDisconnect: _disconnectGoogle,
              onPickFile: _pickGoogleDriveFile,
            ),
            cloud(
              type: _StorageType.dropbox,
              asset: 'assets/images/dropbox.png',
              brand: StorageBrandColors.dropbox,
              title: 'Dropbox',
              account: _dropboxAccount,
              connecting: _isConnectingDropbox,
              onConnect: dropboxConfigured ? _connectDropbox : null,
              onDisconnect: _disconnectDropbox,
              onPickFile: _pickDropboxFile,
              disabledReason:
                  dropboxConfigured ? null : 'Not available in this build',
            ),
            cloud(
              type: _StorageType.oneDrive,
              asset: 'assets/images/onedrive.png',
              brand: StorageBrandColors.oneDrive,
              title: 'OneDrive',
              account: _oneDriveAccount,
              connecting: _isConnectingOneDrive,
              onConnect: _connectOneDrive,
              onDisconnect: _disconnectOneDrive,
              onPickFile: _pickOneDriveFile,
            ),
            cloud(
              type: _StorageType.webDav,
              asset: 'assets/images/webdav.png',
              brand: StorageBrandColors.webDav,
              title: 'WebDAV',
              account: _webDavAccount,
              connecting: _isConnectingWebDav,
              onConnect: _connectWebDav,
              onDisconnect: _disconnectWebDav,
              onPickFile: _pickWebDavFile,
            ),
            cloud(
              type: _StorageType.sftp,
              asset: 'assets/images/sftp.png',
              brand: StorageBrandColors.sftp,
              title: 'SFTP',
              account: _sftpAccount,
              connecting: _isConnectingSftp,
              onConnect: _connectSftp,
              onDisconnect: _disconnectSftp,
              onPickFile: _pickSftpFile,
            ),
            cloud(
              type: _StorageType.s3,
              asset: 'assets/images/aws-s3-icon.png',
              brand: StorageBrandColors.s3,
              title: 'Amazon S3',
              account: _s3Account,
              connecting: _isConnectingS3,
              onConnect: _connectS3,
              onDisconnect: _disconnectS3,
              onPickFile: _pickS3File,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectedFileCard(_SelectedDatabaseFile selectedFile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Selected Database',
          style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: _kMintSoft,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _kInkBorder),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _kYellow,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: _kInkBorder),
                ),
                alignment: Alignment.center,
                child: _storageIcon(selectedFile.storage),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      selectedFile.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selectedFile.displayPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _uText(11, _kLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocalFilesCard() {
    final int newCount =
        _localFiles.where((file) => !_isRegistered(file)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              _localFiles.length == 1
                  ? 'Selected Database'
                  : 'Selected Databases (${_localFiles.length})',
              style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
            ),
            if (newCount > 0 && newCount < _localFiles.length) ...<Widget>[
              const SizedBox(width: 8),
              Text(
                '$newCount new',
                style: _uText(11, _kLabel),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _kMintSoft,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _kInkBorder),
          ),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < _localFiles.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: 4),
                _buildLocalFileRow(_localFiles[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocalFileRow(_SelectedDatabaseFile file) {
    final String? warning = _localFileWarning(file);
    final bool unavailable = warning != null;
    final Color contentColor = unavailable ? _kLabel : _kTitle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: unavailable ? DcColors.lightInset : _kPaperBright,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _kInkBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: unavailable ? _kYellow.withValues(alpha: 0.45) : _kYellow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: unavailable
                    ? _kInkBorder.withValues(alpha: 0.5)
                    : _kInkBorder,
              ),
            ),
            alignment: Alignment.center,
            child: Opacity(
              opacity: unavailable ? 0.5 : 1,
              child: _storageIcon(file.storage),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  file.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _uText(
                    12,
                    contentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _shortenPath(file.displayPath),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _uText(
                    11,
                    unavailable
                        ? _kLabel.withValues(alpha: 0.75)
                        : _kLabel,
                  ),
                ),
                if (warning != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      const Icon(
                        TablerIcons.alert_triangle,
                        size: 12,
                        color: DcColors.amberOnLight,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          warning,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _uText(10, DcColors.amberOnLight),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isOpening ? null : () => _removeLocalFile(file),
            child: Icon(
              TablerIcons.x,
              size: 15,
              color: _kLabel,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: DcColors.redSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DcColors.redOnLight),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            TablerIcons.alert_circle,
            size: 14,
            color: DcColors.redOnLight,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: _uText(11, DcColors.redOnLight),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _errorMessage = null),
            child:
                const Icon(TablerIcons.x, size: 13, color: DcColors.redOnLight),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterRow({required bool canSubmit}) {
    final enabled = !_isOpening &&
        (_selectedFile != null || _localFiles.isNotEmpty) &&
        canSubmit;

    return Row(
      children: <Widget>[
        OutlinedButton(
          onPressed: _isOpening ? null : () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: _kTitle,
            side: const BorderSide(color: _kInkBorder),
            backgroundColor: _kPaperBright,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            textStyle: _uText(12, _kLabel, fontWeight: FontWeight.w600),
          ),
          child: const Text('Cancel'),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: enabled ? _submit : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kBlue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _kBorderSoft,
            shadowColor: _kInkBorder,
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
            textStyle: _uText(12, Colors.white, fontWeight: FontWeight.w600),
          ),
          child: _isOpening
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Open Database'),
        ),
      ],
    );
  }

  Future<void> _connectGoogle() async {
    setState(() => _isConnectingGoogle = true);
    try {
      await BackupService.instance.connectGoogle();
      final account = BackupService.instance.currentGoogleAccount;
      if (account != null) {
        setState(() {
          _googleAccount = account.email;
          _storage = _StorageType.googleDrive;
          _localFiles = const <_SelectedDatabaseFile>[];
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
    final confirmed = await confirmCloudDisconnect(context);
    if (!confirmed || !mounted) return;
    setState(() => _isConnectingGoogle = true);
    try {
      await performCloudDisconnect(ref, CloudServiceProvider.googleDrive);
      if (!mounted) return;
      setState(() {
        _googleAccount = null;
        if (_selectedFile?.storage == _StorageType.googleDrive) {
          _selectedFile = null;
        }
        if (_storage == _StorageType.googleDrive) {
          _storage = _StorageType.local;
        }
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Google sign-out failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isConnectingGoogle = false);
      }
    }
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
          _storage = _StorageType.dropbox;
          _localFiles = const <_SelectedDatabaseFile>[];
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
    final confirmed = await confirmCloudDisconnect(context);
    if (!confirmed || !mounted) return;
    setState(() => _isConnectingDropbox = true);
    try {
      await performCloudDisconnect(ref, CloudServiceProvider.dropbox);
      if (!mounted) return;
      setState(() {
        _dropboxAccount = null;
        if (_selectedFile?.storage == _StorageType.dropbox) {
          _selectedFile = null;
        }
        if (_storage == _StorageType.dropbox) {
          _storage = _StorageType.local;
        }
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Dropbox sign-out failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isConnectingDropbox = false);
      }
    }
  }

  Future<void> _connectOneDrive() async {
    setState(() => _isConnectingOneDrive = true);
    try {
      await BackupService.instance.connectOneDrive();
      final token = BackupService.instance.currentOneDriveToken;
      if (token != null && token.isNotEmpty) {
        setState(() {
          _oneDriveAccount =
              ref.read(backupOneDriveAccountProvider) ?? 'Connected';
          _storage = _StorageType.oneDrive;
          _localFiles = const <_SelectedDatabaseFile>[];
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'OneDrive connection failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isConnectingOneDrive = false);
      }
    }
  }

  Future<void> _disconnectOneDrive() async {
    final confirmed = await confirmCloudDisconnect(context);
    if (!confirmed || !mounted) return;
    setState(() => _isConnectingOneDrive = true);
    try {
      await performCloudDisconnect(ref, CloudServiceProvider.oneDrive);
      if (!mounted) return;
      setState(() {
        _oneDriveAccount = null;
        if (_selectedFile?.storage == _StorageType.oneDrive) {
          _selectedFile = null;
        }
        if (_storage == _StorageType.oneDrive) {
          _storage = _StorageType.local;
        }
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'OneDrive sign-out failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isConnectingOneDrive = false);
      }
    }
  }

  Future<void> _connectWebDav() async {
    setState(() => _isConnectingWebDav = true);
    try {
      final account = await pushWebDavConfigPage(
        context,
        initialConfig: BackupService.instance.currentWebDavConfig,
      );
      if (!mounted) return;
      if (account != null) {
        setState(() {
          _webDavAccount = account;
          _storage = _StorageType.webDav;
          _localFiles = const <_SelectedDatabaseFile>[];
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'WebDAV connection failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isConnectingWebDav = false);
      }
    }
  }

  Future<void> _disconnectWebDav() async {
    final confirmed = await confirmCloudDisconnect(context);
    if (!confirmed || !mounted) return;
    setState(() => _isConnectingWebDav = true);
    try {
      await performCloudDisconnect(ref, CloudServiceProvider.webdav);
      if (!mounted) return;
      setState(() {
        _webDavAccount = null;
        if (_selectedFile?.storage == _StorageType.webDav) {
          _selectedFile = null;
        }
        if (_storage == _StorageType.webDav) {
          _storage = _StorageType.local;
        }
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'WebDAV sign-out failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isConnectingWebDav = false);
      }
    }
  }

  Future<void> _connectSftp() async {
    setState(() => _isConnectingSftp = true);
    try {
      final account = await pushSftpConfigPage(
        context,
        initialConfig: BackupService.instance.currentSftpConfig,
      );
      if (!mounted) return;
      if (account != null) {
        setState(() {
          _sftpAccount = account;
          _storage = _StorageType.sftp;
          _localFiles = const <_SelectedDatabaseFile>[];
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'SFTP connection failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isConnectingSftp = false);
      }
    }
  }

  Future<void> _disconnectSftp() async {
    final confirmed = await confirmCloudDisconnect(context);
    if (!confirmed || !mounted) return;
    setState(() => _isConnectingSftp = true);
    try {
      await performCloudDisconnect(ref, CloudServiceProvider.sftp);
      if (!mounted) return;
      setState(() {
        _sftpAccount = null;
        if (_selectedFile?.storage == _StorageType.sftp) {
          _selectedFile = null;
        }
        if (_storage == _StorageType.sftp) {
          _storage = _StorageType.local;
        }
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'SFTP sign-out failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isConnectingSftp = false);
      }
    }
  }

  Future<void> _connectS3() async {
    setState(() => _isConnectingS3 = true);
    try {
      final account = await pushS3ConfigPage(
        context,
        initialConfig: BackupService.instance.currentS3Config,
      );
      if (!mounted) return;
      if (account != null) {
        setState(() {
          _s3Account = account;
          _storage = _StorageType.s3;
          _localFiles = const <_SelectedDatabaseFile>[];
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'S3 connection failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isConnectingS3 = false);
      }
    }
  }

  Future<void> _disconnectS3() async {
    final confirmed = await confirmCloudDisconnect(context);
    if (!confirmed || !mounted) return;
    setState(() => _isConnectingS3 = true);
    try {
      await performCloudDisconnect(ref, CloudServiceProvider.s3);
      if (!mounted) return;
      setState(() {
        _s3Account = null;
        if (_selectedFile?.storage == _StorageType.s3) {
          _selectedFile = null;
        }
        if (_storage == _StorageType.s3) {
          _storage = _StorageType.local;
        }
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'S3 sign-out failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isConnectingS3 = false);
      }
    }
  }

  void _selectStorage(_StorageType storage) {
    setState(() {
      _storage = storage;
      if (_selectedFile?.storage != storage) {
        _selectedFile = null;
      }
      if (storage != _StorageType.local) {
        _localFiles = const <_SelectedDatabaseFile>[];
      }
      _errorMessage = null;
    });
  }

  Future<void> _pickLocalFile() async {
    final pickedFiles = await BookmarkService.instance.pickFilesWithBookmarks();
    if (!mounted || pickedFiles.isEmpty) {
      return;
    }

    final picked = <_SelectedDatabaseFile>[
      for (final file in pickedFiles)
        _SelectedDatabaseFile(
          storage: _StorageType.local,
          sourceId: file.path,
          databasePath: file.path,
          displayName: _fileName(file.path),
          displayPath: file.path,
          bookmark: file.bookmark.isNotEmpty ? file.bookmark : null,
        ),
    ];

    setState(() {
      _localFiles = picked;
      _storage = _StorageType.local;
      _selectedFile = null;
      _errorMessage = null;
    });
  }

  Future<void> _pickGoogleDriveFile() async {
    final result = await showDialog<CloudFile?>(
      context: context,
      builder: (_) => const _CloudDatabasePickerDialog(
        cloudType: _CloudType.googleDrive,
      ),
    );
    if (result == null) {
      return;
    }

    final cachePath = await _cloudCachePath(_StorageType.googleDrive, result);
    _applySelection(
      _SelectedDatabaseFile(
        storage: _StorageType.googleDrive,
        sourceId: result.id,
        databasePath: cachePath,
        displayName: result.name,
        displayPath: result.displayPath,
      ),
    );
  }

  Future<void> _pickDropboxFile() async {
    final result = await showDialog<CloudFile?>(
      context: context,
      builder: (_) => const _CloudDatabasePickerDialog(
        cloudType: _CloudType.dropbox,
      ),
    );
    if (result == null) {
      return;
    }

    final cachePath = await _cloudCachePath(_StorageType.dropbox, result);
    _applySelection(
      _SelectedDatabaseFile(
        storage: _StorageType.dropbox,
        sourceId: result.id,
        databasePath: cachePath,
        displayName: result.name,
        displayPath: result.displayPath,
      ),
    );
  }

  Future<void> _pickOneDriveFile() async {
    final result = await showDialog<CloudFile?>(
      context: context,
      builder: (_) => const _CloudDatabasePickerDialog(
        cloudType: _CloudType.oneDrive,
      ),
    );
    if (result == null) {
      return;
    }

    final cachePath = await _cloudCachePath(_StorageType.oneDrive, result);
    _applySelection(
      _SelectedDatabaseFile(
        storage: _StorageType.oneDrive,
        sourceId: result.id,
        databasePath: cachePath,
        displayName: result.name,
        displayPath: result.displayPath,
      ),
    );
  }

  Future<void> _pickWebDavFile() async {
    final result = await showDialog<CloudFile?>(
      context: context,
      builder: (_) => const _CloudDatabasePickerDialog(
        cloudType: _CloudType.webDav,
      ),
    );
    if (result == null) {
      return;
    }

    final cachePath = await _cloudCachePath(_StorageType.webDav, result);
    _applySelection(
      _SelectedDatabaseFile(
        storage: _StorageType.webDav,
        sourceId: result.id,
        databasePath: cachePath,
        displayName: result.name,
        displayPath: result.displayPath,
      ),
    );
  }

  Future<void> _pickSftpFile() async {
    final result = await showDialog<CloudFile?>(
      context: context,
      builder: (_) => const _CloudDatabasePickerDialog(
        cloudType: _CloudType.sftp,
      ),
    );
    if (result == null) {
      return;
    }

    final cachePath = await _cloudCachePath(_StorageType.sftp, result);
    _applySelection(
      _SelectedDatabaseFile(
        storage: _StorageType.sftp,
        sourceId: result.id,
        databasePath: cachePath,
        displayName: result.name,
        displayPath: result.displayPath,
      ),
    );
  }

  Future<void> _pickS3File() async {
    final result = await showDialog<CloudFile?>(
      context: context,
      builder: (_) => const _CloudDatabasePickerDialog(
        cloudType: _CloudType.s3,
      ),
    );
    if (result == null) {
      return;
    }

    final cachePath = await _cloudCachePath(_StorageType.s3, result);
    _applySelection(
      _SelectedDatabaseFile(
        storage: _StorageType.s3,
        sourceId: result.id,
        databasePath: cachePath,
        displayName: result.name,
        displayPath: result.displayPath,
      ),
    );
  }

  void _applySelection(_SelectedDatabaseFile selectedFile) {
    setState(() {
      _selectedFile = selectedFile;
      _storage = selectedFile.storage;
      _localFiles = const <_SelectedDatabaseFile>[];
      _errorMessage = null;
    });
  }

  void _removeLocalFile(_SelectedDatabaseFile file) {
    setState(() {
      _localFiles = _localFiles.where((f) => !identical(f, file)).toList();
      _errorMessage = null;
    });
  }

  Future<void> _submit() async {
    if (_localFiles.isNotEmpty) {
      await _submitLocalFiles();
      return;
    }

    final selectedFile = _selectedFile;
    if (selectedFile == null) {
      setState(() => _errorMessage = 'Select a database file to continue.');
      return;
    }

    final validationMessage = _selectionError(selectedFile);
    if (validationMessage != null) {
      setState(() => _errorMessage = validationMessage);
      return;
    }

    setState(() {
      _isOpening = true;
      _errorMessage = null;
    });

    try {
      if (selectedFile.storage == _StorageType.googleDrive ||
          selectedFile.storage == _StorageType.dropbox ||
          selectedFile.storage == _StorageType.oneDrive ||
          selectedFile.storage == _StorageType.webDav ||
          selectedFile.storage == _StorageType.sftp ||
          selectedFile.storage == _StorageType.s3) {
        await Directory(p.dirname(selectedFile.databasePath))
            .create(recursive: true);

        final Uint8List bytes;
        if (selectedFile.storage == _StorageType.googleDrive) {
          bytes = await BackupService.instance
              .downloadGoogleDriveFile(selectedFile.sourceId);
        } else if (selectedFile.storage == _StorageType.dropbox) {
          bytes = await BackupService.instance
              .downloadDropboxFile(selectedFile.sourceId);
        } else if (selectedFile.storage == _StorageType.oneDrive) {
          bytes = await BackupService.instance
              .downloadOneDriveFile(selectedFile.sourceId);
        } else if (selectedFile.storage == _StorageType.webDav) {
          bytes = await BackupService.instance
              .downloadWebDavFile(selectedFile.sourceId);
        } else if (selectedFile.storage == _StorageType.sftp) {
          bytes = await BackupService.instance
              .downloadSftpFile(selectedFile.sourceId);
        } else {
          bytes = await BackupService.instance
              .downloadS3File(selectedFile.sourceId);
        }

        await File(selectedFile.databasePath).writeAsBytes(bytes, flush: true);
      }

      await ref.read(databaseRegistryProvider.notifier).addDatabase(
            nickname: selectedFile.nickname,
            databasePath: selectedFile.databasePath,
            bookmark: selectedFile.bookmark,
            storageType: _storageValue(selectedFile.storage),
            cloudFileId: selectedFile.storage != _StorageType.local &&
                    selectedFile.sourceId.isNotEmpty
                ? selectedFile.sourceId
                : null,
            cloudFileName: selectedFile.storage != _StorageType.local
                ? selectedFile.displayName
                : null,
          );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
      await widget.onOpened(selectedFile.databasePath);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isOpening = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _submitLocalFiles() async {
    final files = _localFiles;
    if (files.isEmpty) {
      setState(() => _errorMessage = 'Select a database file to continue.');
      return;
    }

    for (final file in files) {
      final blocking = _blockingSelectionError(file);
      if (blocking != null) {
        setState(() => _errorMessage = blocking);
        return;
      }
    }

    // Vaults that are already registered stay visible but are skipped here;
    // the row itself carries the grayed-out warning.
    final pending =
        files.where((file) => !_isRegistered(file)).toList(growable: false);
    if (pending.isEmpty) {
      setState(() {
        _errorMessage = files.length == 1
            ? 'This database is already in your list.'
            : 'All selected databases are already in your list.';
      });
      return;
    }

    setState(() {
      _isOpening = true;
      _errorMessage = null;
    });

    try {
      final registry = ref.read(databaseRegistryProvider.notifier);
      for (final file in pending) {
        await registry.addDatabase(
          nickname: file.nickname,
          databasePath: file.databasePath,
          bookmark: file.bookmark,
          storageType: _storageValue(file.storage),
        );
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
      await widget.onOpened(pending.first.databasePath);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isOpening = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<String> _cloudCachePath(_StorageType storage, CloudFile file) async {
    final appSupport = await getApplicationSupportDirectory();
    final String storageFolder;
    switch (storage) {
      case _StorageType.googleDrive:
        storageFolder = 'google_drive';
      case _StorageType.dropbox:
        storageFolder = 'dropbox';
      case _StorageType.oneDrive:
        storageFolder = 'onedrive';
      case _StorageType.webDav:
        storageFolder = 'webdav';
      case _StorageType.sftp:
        storageFolder = 'sftp';
      case _StorageType.s3:
        storageFolder = 's3';
      case _StorageType.local:
        storageFolder = 'local';
    }
    final safeBase = _safeBaseName(file.name);
    final ext = _databaseExtension(file.name);
    final hash = sha1
        .convert(utf8.encode('${storage.name}:${file.id}'))
        .toString()
        .substring(0, 12);

    return p.join(
      appSupport.path,
      'cloud_databases',
      storageFolder,
      '${safeBase}_$hash$ext',
    );
  }

  /// Whether [selectedFile] already exists in the database registry.
  bool _isRegistered(_SelectedDatabaseFile selectedFile) {
    final normalizedPath = _normalizePath(selectedFile.databasePath);
    final nickname = selectedFile.nickname.toLowerCase();

    return ref.read(databaseRegistryProvider).any((record) {
      if (_normalizePath(record.databasePath) == normalizedPath) {
        return true;
      }

      if (selectedFile.storage == _StorageType.local) {
        return false;
      }

      return record.storageType == _storageValue(selectedFile.storage) &&
          record.nickname.toLowerCase() == nickname;
    });
  }

  /// Errors that block opening [selectedFile] outright.
  String? _blockingSelectionError(_SelectedDatabaseFile selectedFile) {
    if (!_isSupportedDatabaseFile(selectedFile.displayName)) {
      return 'Please choose a .kdbx or .kdb file.';
    }
    return null;
  }

  /// Non-blocking, row-level warning for a picked file (e.g. duplicates).
  String? _localFileWarning(_SelectedDatabaseFile file) {
    if (_blockingSelectionError(file) != null) {
      return null;
    }
    if (_isRegistered(file)) {
      return 'Already in your list — will be skipped';
    }
    return null;
  }

  String? _selectionError(_SelectedDatabaseFile selectedFile) {
    final blocking = _blockingSelectionError(selectedFile);
    if (blocking != null) {
      return blocking;
    }

    if (_isRegistered(selectedFile)) {
      return 'This database is already in your list.';
    }

    return null;
  }
}

class _SelectedDatabaseFile {
  const _SelectedDatabaseFile({
    required this.storage,
    required this.sourceId,
    required this.databasePath,
    required this.displayName,
    required this.displayPath,
    this.bookmark,
  });

  final _StorageType storage;
  final String sourceId;
  final String databasePath;
  final String displayName;
  final String displayPath;
  final String? bookmark;

  String get nickname => _baseDatabaseName(displayName);
}

class _CloudDatabasePickerDialog extends StatefulWidget {
  const _CloudDatabasePickerDialog({required this.cloudType});

  final _CloudType cloudType;

  @override
  State<_CloudDatabasePickerDialog> createState() =>
      _CloudDatabasePickerDialogState();
}

class _CloudDatabasePickerDialogState
    extends State<_CloudDatabasePickerDialog> {
  final List<CloudFolder> _breadcrumb = <CloudFolder>[];
  List<CloudFolder>? _folders;
  List<CloudFile>? _files;
  String? _error;
  bool _loading = true;

  String get _currentDisplayPath =>
      _breadcrumb.isEmpty ? '/' : _breadcrumb.last.displayPath;

  String _childDisplayPath(String name) {
    final current = _currentDisplayPath;
    return current == '/' ? '/$name' : '$current/$name';
  }

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final Future<List<CloudFolder>> foldersFuture;
      final Future<List<CloudFile>> filesFuture;

      if (widget.cloudType == _CloudType.googleDrive) {
        foldersFuture = BackupService.instance.listGoogleDriveFolders(
          parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
        );
        filesFuture = BackupService.instance.listGoogleDriveFiles(
          parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
        );
      } else if (widget.cloudType == _CloudType.dropbox) {
        foldersFuture = BackupService.instance
            .listDropboxFolders(_breadcrumb.isEmpty ? '' : _breadcrumb.last.id);
        filesFuture = BackupService.instance
            .listDropboxFiles(_breadcrumb.isEmpty ? '' : _breadcrumb.last.id);
      } else if (widget.cloudType == _CloudType.oneDrive) {
        foldersFuture = BackupService.instance.listOneDriveFolders(
            parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id);
        filesFuture = BackupService.instance.listOneDriveFiles(
            parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id);
      } else if (widget.cloudType == _CloudType.webDav) {
        foldersFuture = BackupService.instance.listWebDavFolders(
            parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id);
        filesFuture = BackupService.instance.listWebDavFiles(
            parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id);
      } else if (widget.cloudType == _CloudType.sftp) {
        foldersFuture = BackupService.instance.listSftpFolders(
            parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id);
        filesFuture = BackupService.instance.listSftpFiles(
            parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id);
      } else {
        foldersFuture = BackupService.instance.listS3Folders(
            prefix: _breadcrumb.isEmpty ? '' : _breadcrumb.last.id);
        filesFuture = BackupService.instance.listS3Files(
            prefix: _breadcrumb.isEmpty ? '' : _breadcrumb.last.id);
      }

      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        foldersFuture,
        filesFuture,
      ]);

      final folders = results[0] as List<CloudFolder>;
      final files = (results[1] as List<CloudFile>)
          .where((file) => _isSupportedDatabaseFile(file.name))
          .toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _folders = folders;
        _files = files;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.cloudType == _CloudType.googleDrive
        ? 'Select Google Drive Database'
        : widget.cloudType == _CloudType.dropbox
            ? 'Select Dropbox Database'
            : widget.cloudType == _CloudType.oneDrive
                ? 'Select OneDrive Database'
                : widget.cloudType == _CloudType.webDav
                    ? 'Select WebDAV Database'
                    : widget.cloudType == _CloudType.sftp
                        ? 'Select SFTP Database'
                        : 'Select Amazon S3 Database';

    final String current = _breadcrumb.isEmpty ? 'Root' : _breadcrumb.last.name;
    return Theme(
      data: AppTheme.driveClueLight(),
      child: DcFlowPage(
        title: title,
        subtitle: current,
        icon: TablerIcons.folder_open,
        onBack: _breadcrumb.isEmpty
            ? () => Navigator.of(context).pop()
            : () {
                setState(() => _breadcrumb.removeLast());
                _loadEntries();
              },
        scrollable: false,
        inset: false,
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_breadcrumb.isNotEmpty) _buildBreadcrumb(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                _error!,
                                style: _uText(12, DcColors.redOnLight),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : _buildEntryList(),
              ),
            ],
          ),
        ),
        footer: _buildFooterRow(),
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
                _loadEntries();
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
                  _loadEntries();
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

  Widget _buildEntryList() {
    final folders = _folders ?? const <CloudFolder>[];
    final files = _files ?? const <CloudFile>[];

    if (folders.isEmpty && files.isEmpty) {
      return Center(
        child: Text(
          'No KeePass databases in this location.',
          style: _uText(12, _kLabel),
        ),
      );
    }

    return ListView(
      children: <Widget>[
        for (final folder in folders)
          _FolderListTile(
            folder: folder,
            onNavigate: () {
              setState(() {
                _breadcrumb.add(
                  CloudFolder(
                    id: folder.id,
                    name: folder.name,
                    path: _childDisplayPath(folder.name),
                  ),
                );
              });
              _loadEntries();
            },
          ),
        for (final file in files)
          _DatabaseFileTile(
            file: file,
            onSelect: () {
              Navigator.of(context).pop(
                CloudFile(
                  id: file.id,
                  name: file.name,
                  path: _childDisplayPath(file.name),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildFooterRow() {
    return Row(
      children: <Widget>[
        Text(
          'Select a .kdbx or .kdb file',
          style: _uText(11, _kLabel),
        ),
        const Spacer(),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: DcColors.sidebarText,
            side: const BorderSide(color: DcColors.lightLineStrong),
            backgroundColor: DcColors.sidebar,
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
      ],
    );
  }
}

class _FolderListTile extends StatefulWidget {
  const _FolderListTile({
    required this.folder,
    required this.onNavigate,
  });

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
            color:
                _hovered ? DcColors.lightSelectionFill : DcColors.lightSurface,
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

class _DatabaseFileTile extends StatefulWidget {
  const _DatabaseFileTile({
    required this.file,
    required this.onSelect,
  });

  final CloudFile file;
  final VoidCallback onSelect;

  @override
  State<_DatabaseFileTile> createState() => _DatabaseFileTileState();
}

class _DatabaseFileTileState extends State<_DatabaseFileTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color:
                _hovered ? DcColors.lightSelectionFill : DcColors.lightSurface,
            border: const Border(bottom: BorderSide(color: _kBorderSoft)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _hovered ? _kYellow : _kCanvas,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  TablerIcons.file_database,
                  size: 15,
                  color: _kBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _uText(
                        12,
                        _hovered ? _kBlue : _kTitle,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Choose this database',
                      style: _uText(10, _kLabel),
                    ),
                  ],
                ),
              ),
              Text(
                'Open',
                style: _uText(11, _kBlue, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _storageIcon(_StorageType storage) {
  switch (storage) {
    case _StorageType.googleDrive:
      return Image.asset('assets/images/google-drive.png',
          width: 18, height: 18);
    case _StorageType.dropbox:
      return Image.asset('assets/images/dropbox.png', width: 18, height: 18);
    case _StorageType.oneDrive:
      return Image.asset('assets/images/onedrive.png', width: 18, height: 18);
    case _StorageType.webDav:
      return Image.asset('assets/images/webdav.png', width: 18, height: 18);
    case _StorageType.sftp:
      return Image.asset('assets/images/sftp.png', width: 18, height: 18);
    case _StorageType.s3:
      return Image.asset('assets/images/aws-s3-icon.png',
          width: 18, height: 18);
    case _StorageType.local:
      return Image.asset('assets/images/dir.png', width: 18, height: 18);
  }
}

String _storageValue(_StorageType storage) {
  switch (storage) {
    case _StorageType.googleDrive:
      return 'googleDrive';
    case _StorageType.dropbox:
      return 'dropbox';
    case _StorageType.oneDrive:
      return 'oneDrive';
    case _StorageType.webDav:
      return 'webdav';
    case _StorageType.sftp:
      return 'sftp';
    case _StorageType.s3:
      return 's3';
    case _StorageType.local:
      return 'local';
  }
}

bool _isSupportedDatabaseFile(String name) {
  final extension = p.extension(name).toLowerCase();
  return extension == '.kdbx' || extension == '.kdb';
}

String _databaseExtension(String name) {
  final extension = p.extension(name).toLowerCase();
  return extension.isEmpty ? '.kdbx' : extension;
}

String _safeBaseName(String name) {
  final baseName = p.basenameWithoutExtension(name).trim();
  final sanitized = baseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  return sanitized.isEmpty ? 'database' : sanitized;
}

String _baseDatabaseName(String pathOrName) {
  final name = _fileName(pathOrName);
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

String _fileName(String path) {
  final segments = path.split(RegExp(r'[\/\\]'));
  return segments.isEmpty ? path : segments.last;
}

String _normalizePath(String path) {
  final normalized = p.normalize(path);
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

String _shortenPath(String path) {
  const int maxLen = 52;
  if (path.length <= maxLen) {
    return path;
  }

  final home = Platform.environment['HOME'] ?? '';
  final shortened = home.isNotEmpty ? path.replaceFirst(home, '~') : path;
  if (shortened.length <= maxLen) {
    return shortened;
  }

  final segments = shortened.split(RegExp(r'[/]'));
  if (segments.length > 3) {
    return '${segments.first}/…/${segments[segments.length - 2]}/${segments.last}';
  }

  return '…${shortened.substring(shortened.length - maxLen + 1)}';
}
