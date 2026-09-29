import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:kdbx/kdbx.dart' as kdbx;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/repository/kdbx_repository_provider.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/bookmark_service.dart';
import '../../../core/services/s3_service.dart';

import '../../../features/unlock/application/database_registry.dart';
import '../../../presentation/theme/app_theme.dart';
import 'sftp_config_dialog.dart';
import 'webdav_config_dialog.dart';
import 's3_config_dialog.dart';

// ── Vintage palette (mirrors unlock_screen) ─────────────────────────────────
const Color _kCanvas = Color(0xFFF7F4EC);
const Color _kPaperBright = Color(0xFFFFFCF5);
const Color _kBorderSoft = Color(0xFFB8B1A5);
const Color _kBorderRow = Color(0xFFCAC3B7);
const Color _kTitle = Color(0xFF191A1B);
const Color _kLabel = Color(0xFF626560);
const Color _kIcon = Color(0xFF777A75);
const Color _kBlue = Color(0xFFFF5B22);
const Color _kInkBorder = Color(0xFF252628);
const Color _kMint = Color(0xFF21A98F);
const Color _kMintSoft = Color(0xFFDFF2EC);
const Color _kPeach = Color(0xFFF4D7C8);
const Color _kYellow = Color(0xFFF4E2A4);

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

TextStyle _serifText(
  double size,
  Color color, {
  FontWeight fontWeight = FontWeight.w700,
  double? height,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: fontWeight,
    fontFamily: 'Ubuntu Sans',
    height: height,
  );
}

InputDecoration _fieldDecoration({
  required String hint,
  required IconData prefixIcon,
  Widget? suffix,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: _uText(13, _kIcon),
    filled: true,
    fillColor: _kCanvas,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
    prefixIcon: Icon(prefixIcon, size: 17, color: _kIcon),
    prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    suffixIcon: suffix,
  );
}

enum _StorageType { local, dropbox, googleDrive, oneDrive, webDav, sftp, s3 }

/// The sequential steps of the create-database wizard.
enum _WizardStep { provider, details }

enum _DbFormat { kdbx4, kdbx31, kdb, psafe3 }

extension _DbFormatLabel on _DbFormat {
  String get title {
    switch (this) {
      case _DbFormat.kdbx4:
      case _DbFormat.kdbx31:
        return 'KeePass 2';
      case _DbFormat.kdb:
        return 'KeePass 1';
      case _DbFormat.psafe3:
        return 'Password Safe';
    }
  }

  String get versionLabel {
    switch (this) {
      case _DbFormat.kdbx4:
        return 'KDBX 4.x';
      case _DbFormat.kdbx31:
        return 'KDBX 3.1';
      case _DbFormat.kdb:
        return 'KDB';
      case _DbFormat.psafe3:
        return '3.x / psafe3';
    }
  }

  String? get badgeLabel {
    switch (this) {
      case _DbFormat.kdbx4:
        return 'Recommended';
      case _DbFormat.kdbx31:
      case _DbFormat.kdb:
        return 'Legacy';
      case _DbFormat.psafe3:
        return null;
    }
  }

  String get menuDescription {
    switch (this) {
      case _DbFormat.kdbx4:
        return 'Modern format for new databases.';
      case _DbFormat.kdbx31:
        return 'Older KeePass 2 format for compatibility.';
      case _DbFormat.kdb:
        return 'Visible for compatibility, not available for new databases.';
      case _DbFormat.psafe3:
        return 'Visible for compatibility, not available for new databases.';
    }
  }

  bool get isSupported => this == _DbFormat.kdbx4 || this == _DbFormat.kdbx31;
}

/// Modal dialog for creating a new KeePass database.
class CreateDatabaseModal extends ConsumerStatefulWidget {
  const CreateDatabaseModal({super.key, required this.onCreated});

  /// Called with the new database file path and nickname after successful creation.
  final Future<void> Function(String dbPath, String nickname) onCreated;

  @override
  ConsumerState<CreateDatabaseModal> createState() =>
      _CreateDatabaseModalState();
}

class _CreateDatabaseModalState extends ConsumerState<CreateDatabaseModal> {
  // ── Wizard navigation ─────────────────────────────────────────────────────
  _WizardStep _step = _WizardStep.provider;
  // Tracks navigation direction so transitions slide the correct way.
  bool _goingForward = true;

  _StorageType _storage = _StorageType.local;
  String? _localDirectory;

  final _nameController = TextEditingController(text: 'My Vault');
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptEmptyPassword = false;
  bool _showAdvanced = false;
  bool _useKeyFile = false;
  String? _keyFilePath;
  _DbFormat _format = _DbFormat.kdbx4;

  bool _isCreating = false;
  String? _errorMessage;

  // ── Cloud state ──────────────────────────────────────────────────────────
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

  String? _s3Account;
  String? _s3FolderPath;
  String? _s3FolderName;
  bool _isConnectingS3 = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreCloudState());
  }

  void _restoreCloudState() {
    final googleEmail = ref.read(backupGoogleAccountProvider);
    final dropboxEmail = ref.read(backupDropboxAccountProvider);
    final oneDriveEmail = ref.read(backupOneDriveAccountProvider);
    final oneDriveFolderId = ref.read(backupOneDriveFolderIdProvider);
    final oneDriveFolderName = ref.read(backupOneDriveFolderNameProvider);
    final webDavAccount = ref.read(backupWebDavAccountProvider);
    final webDavFolderPath = ref.read(backupWebDavFolderPathProvider);
    final webDavFolderName = ref.read(backupWebDavFolderNameProvider);
    final sftpAccount = ref.read(backupSftpAccountProvider);
    final sftpFolderPath = ref.read(backupSftpFolderPathProvider);
    final sftpFolderName = ref.read(backupSftpFolderNameProvider);
    final s3Account = ref.read(backupS3AccountProvider);
    final s3FolderPath = ref.read(backupS3FolderPathProvider);
    final s3FolderName = ref.read(backupS3FolderNameProvider);
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
        _oneDriveFolderId = oneDriveFolderId;
        _oneDriveFolderName = oneDriveFolderName;
        _webDavAccount = webDavAccount;
        _webDavFolderPath = webDavFolderPath;
        _webDavFolderName = webDavFolderName;
        _sftpAccount = sftpAccount;
        _sftpFolderPath = sftpFolderPath;
        _sftpFolderName = sftpFolderName;
        _s3Account = s3Account;
        _s3FolderPath = s3FolderPath;
        _s3FolderName = s3FolderName;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
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
            color: _kCanvas,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kInkBorder, width: 1.5),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x33252628),
                blurRadius: 0,
                offset: Offset(6, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildHeader(),
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final bool incoming =
                        child.key == ValueKey<_WizardStep>(_step);
                    // Incoming step enters from the direction of travel; the
                    // outgoing step leaves the opposite way.
                    final double sign = _goingForward ? 1.0 : -1.0;
                    final Offset beginOffset = incoming
                        ? Offset(sign * 0.06, 0)
                        : Offset(-sign * 0.06, 0);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: beginOffset,
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      alignment: Alignment.topCenter,
                      children: <Widget>[
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },
                  child: _step == _WizardStep.provider
                      ? _buildProviderStep()
                      : _buildDetailsStep(),
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Wizard steps ──────────────────────────────────────────────────────────

  /// Whether the currently selected provider has a valid destination so the
  /// user may advance to the details step. Mirrors the storage checks in
  /// [_submit].
  bool get _providerReady {
    switch (_storage) {
      case _StorageType.local:
        return _localDirectory != null;
      case _StorageType.googleDrive:
        return _googleAccount != null;
      case _StorageType.dropbox:
        return _dropboxAccount != null;
      case _StorageType.oneDrive:
        return _oneDriveAccount != null;
      case _StorageType.webDav:
        return _webDavAccount != null;
      case _StorageType.sftp:
        return _sftpAccount != null;
      case _StorageType.s3:
        return _s3Account != null;
    }
  }

  void _goToDetails() {
    if (!_providerReady || _isCreating) return;
    setState(() {
      _goingForward = true;
      _errorMessage = null;
      _step = _WizardStep.details;
    });
  }

  void _goToProvider() {
    if (_isCreating) return;
    setState(() {
      _goingForward = false;
      _errorMessage = null;
      _step = _WizardStep.provider;
    });
  }

  Widget _buildProviderStep() {
    return SingleChildScrollView(
      key: const ValueKey<_WizardStep>(_WizardStep.provider),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildStorageSection(),
          if (_errorMessage != null) ...<Widget>[
            const SizedBox(height: 16),
            _buildError(),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailsStep() {
    return SingleChildScrollView(
      key: const ValueKey<_WizardStep>(_WizardStep.details),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSelectedDestination(),
          const SizedBox(height: 16),
          if (_errorMessage != null) ...<Widget>[
            _buildError(),
            const SizedBox(height: 16),
          ],
          _buildNameSection(),
          const SizedBox(height: 16),
          _buildPasswordSection(),
          if (_showAdvanced) ...<Widget>[
            const SizedBox(height: 12),
            _buildKeyFileSection(),
            const SizedBox(height: 12),
            _buildFormatSection(),
          ],
        ],
      ),
    );
  }

  /// Read-only summary of the destination chosen in step 1, shown at the top of
  /// the details step so the user keeps context without scrolling back.
  Widget _buildSelectedDestination() {
    final String providerLabel;
    final String detail;
    switch (_storage) {
      case _StorageType.local:
        providerLabel = 'Local Directory';
        detail = _localDirectory != null
            ? _shortenPath(_localDirectory!)
            : 'No folder selected';
        break;
      case _StorageType.googleDrive:
        providerLabel = 'Google Drive';
        detail = _googleFolderName ?? _googleAccount ?? '/ (root)';
        break;
      case _StorageType.dropbox:
        providerLabel = 'Dropbox';
        detail = _dropboxFolderName ?? _dropboxAccount ?? '/ (root)';
        break;
      case _StorageType.oneDrive:
        providerLabel = 'OneDrive';
        detail = _oneDriveFolderName ?? _oneDriveAccount ?? '/ (root)';
        break;
      case _StorageType.webDav:
        providerLabel = 'WebDAV';
        detail = _webDavFolderName ?? _webDavAccount ?? '/ (root)';
        break;
      case _StorageType.sftp:
        providerLabel = 'SFTP';
        detail = _sftpFolderName ?? _sftpAccount ?? '/ (root)';
        break;
      case _StorageType.s3:
        providerLabel = 'Amazon S3';
        detail = _s3FolderName ?? _s3Account ?? '/ (root)';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kMintSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kInkBorder),
      ),
      child: Row(
        children: <Widget>[
          const Icon(TablerIcons.circle_check, size: 16, color: _kMint),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Storing in $providerLabel',
                  style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _uText(11, _kLabel),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _goToProvider,
              child: Text(
                'Change',
                style: _uText(11, _kBlue, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 17, 16, 14),
      decoration: const BoxDecoration(
        color: _kPaperBright,
        border: Border(bottom: BorderSide(color: _kBorderSoft)),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(17),
          topRight: Radius.circular(17),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _kPeach,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kInkBorder),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: _kInkBorder, offset: Offset(2, 2)),
              ],
            ),
            child:
                const Icon(TablerIcons.database_plus, size: 16, color: _kTitle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _step == _WizardStep.provider
                      ? 'Choose a Storage Destination'
                      : 'Create New Database',
                  style: _serifText(17, _kTitle),
                ),
                Text(
                  _step == _WizardStep.provider
                      ? 'Step 1 of 2 · Pick where your vault will live.'
                      : 'Step 2 of 2 · Enter a nickname and configure security options.',
                  style: _uText(11, _kLabel),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildStepDots(),
          const SizedBox(width: 12),
          MouseRegion(
            cursor: _isCreating
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _isCreating ? null : () => Navigator.of(context).pop(),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _kPaperBright,
                  shape: BoxShape.circle,
                  border: Border.all(color: _kInkBorder),
                ),
                child: const Icon(TablerIcons.x, size: 14, color: _kTitle),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Two pill indicators reflecting the active wizard step.
  Widget _buildStepDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _StepDot(active: _step == _WizardStep.provider),
        const SizedBox(width: 5),
        _StepDot(active: _step == _WizardStep.details),
      ],
    );
  }

  // ── Storage destination ──────────────────────────────────────────────────

  Widget _buildStorageSection() {
    final bool dropboxConfigured = BackupService.isDropboxConfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Storage Destination',
          style: _serifText(14, _kTitle),
        ),
        const SizedBox(height: 8),
        _DestinationGrid(
          children: <Widget>[
            _StorageRow(
              iconChild:
                  Image.asset('assets/images/dir.png', width: 18, height: 18),
              label: 'Local Directory',
              detail: _localDirectory != null
                  ? _shortenPath(_localDirectory!)
                  : 'Choose a folder on this Mac',
              selected: _storage == _StorageType.local,
              actionLabel: 'Browse',
              onAction: _pickLocalDirectory,
            ),
            _CloudStorageRow(
              iconChild: Image.asset('assets/images/google-drive.png',
                  width: 18, height: 18),
              provider: 'Google Drive',
              selected: _storage == _StorageType.googleDrive,
              account: _googleAccount,
              folderName: _googleFolderName,
              isConnecting: _isConnectingGoogle,
              onConnect: _connectGoogle,
              onDisconnect: _disconnectGoogle,
              onPickFolder: _googleAccount != null ? _pickGoogleFolder : null,
              onSelect: _googleAccount != null
                  ? () => setState(() => _storage = _StorageType.googleDrive)
                  : null,
            ),
            _CloudStorageRow(
              iconChild: Image.asset('assets/images/dropbox.png',
                  width: 18, height: 18),
              provider: 'Dropbox',
              selected: _storage == _StorageType.dropbox,
              account: _dropboxAccount,
              folderName: _dropboxFolderName,
              isConnecting: _isConnectingDropbox,
              onConnect: dropboxConfigured ? _connectDropbox : null,
              onDisconnect: _disconnectDropbox,
              onPickFolder: _dropboxAccount != null ? _pickDropboxFolder : null,
              onSelect: _dropboxAccount != null
                  ? () => setState(() => _storage = _StorageType.dropbox)
                  : null,
            ),
            _CloudStorageRow(
              iconChild: Image.asset('assets/images/onedrive.png',
                  width: 18, height: 18),
              provider: 'OneDrive',
              selected: _storage == _StorageType.oneDrive,
              account: _oneDriveAccount,
              folderName: _oneDriveFolderName,
              isConnecting: _isConnectingOneDrive,
              onConnect: _connectOneDrive,
              onDisconnect: _disconnectOneDrive,
              onPickFolder:
                  _oneDriveAccount != null ? _pickOneDriveFolder : null,
              onSelect: _oneDriveAccount != null
                  ? () => setState(() => _storage = _StorageType.oneDrive)
                  : null,
            ),
            _CloudStorageRow(
              iconChild: Image.asset('assets/images/webdav.png',
                  width: 18, height: 18),
              provider: 'WebDAV',
              selected: _storage == _StorageType.webDav,
              account: _webDavAccount,
              folderName: _webDavFolderName,
              isConnecting: _isConnectingWebDav,
              onConnect: _connectWebDav,
              onDisconnect: _disconnectWebDav,
              onPickFolder: _webDavAccount != null ? _pickWebDavFolder : null,
              onSelect: _webDavAccount != null
                  ? () => setState(() => _storage = _StorageType.webDav)
                  : null,
            ),
            _CloudStorageRow(
              iconChild:
                  Image.asset('assets/images/sftp.png', width: 18, height: 18),
              provider: 'SFTP',
              selected: _storage == _StorageType.sftp,
              account: _sftpAccount,
              folderName: _sftpFolderName,
              isConnecting: _isConnectingSftp,
              onConnect: _connectSftp,
              onDisconnect: _disconnectSftp,
              onPickFolder: _sftpAccount != null ? _pickSftpFolder : null,
              onSelect: _sftpAccount != null
                  ? () => setState(() => _storage = _StorageType.sftp)
                  : null,
            ),
            _CloudStorageRow(
              iconChild: Image.asset('assets/images/aws-s3-icon.png',
                  width: 18, height: 18),
              provider: 'Amazon S3',
              selected: _storage == _StorageType.s3,
              account: _s3Account,
              folderName: _s3FolderName,
              isConnecting: _isConnectingS3,
              onConnect: _connectS3,
              onDisconnect: _disconnectS3,
              onPickFolder: _s3Account != null ? _pickS3Folder : null,
              onSelect: _s3Account != null
                  ? () => setState(() => _storage = _StorageType.s3)
                  : null,
            ),
          ],
        ),
        if (!dropboxConfigured) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'Dropbox is disabled in this build. Configure DROPBOX_APP_KEY via --dart-define to enable it.',
            style: _uText(11, _kLabel),
          ),
        ],
      ],
    );
  }

  // ── Cloud actions ─────────────────────────────────────────────────────────

  Future<void> _connectGoogle() async {
    setState(() => _isConnectingGoogle = true);
    try {
      await BackupService.instance.connectGoogle();
      final acct = BackupService.instance.currentGoogleAccount;
      if (acct != null) {
        setState(() {
          _googleAccount = acct.email;
          _storage = _StorageType.googleDrive;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Google sign-in failed: $e');
    } finally {
      setState(() => _isConnectingGoogle = false);
    }
  }

  Future<void> _disconnectGoogle() async {
    await BackupService.instance.disconnectGoogle();
    setState(() {
      _googleAccount = null;
      _googleFolderId = null;
      _googleFolderName = null;
      if (_storage == _StorageType.googleDrive) {
        _storage = _StorageType.local;
      }
    });
  }

  Future<void> _connectDropbox() async {
    setState(() => _isConnectingDropbox = true);
    try {
      await BackupService.instance.connectDropbox();
      final token = BackupService.instance.currentDropboxToken;
      if (token != null && token.isNotEmpty) {
        final email = ref.read(backupDropboxAccountProvider) ?? 'Connected';
        setState(() {
          _dropboxAccount = email;
          _storage = _StorageType.dropbox;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Dropbox connection failed: $e');
    } finally {
      setState(() => _isConnectingDropbox = false);
    }
  }

  Future<void> _disconnectDropbox() async {
    await BackupService.instance.disconnectDropbox();
    setState(() {
      _dropboxAccount = null;
      _dropboxFolderPath = null;
      _dropboxFolderName = null;
      if (_storage == _StorageType.dropbox) {
        _storage = _StorageType.local;
      }
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

  Future<void> _connectOneDrive() async {
    setState(() => _isConnectingOneDrive = true);
    try {
      await BackupService.instance.connectOneDrive();
      final email = ref.read(backupOneDriveAccountProvider) ?? 'Connected';
      setState(() {
        _oneDriveAccount = email;
        _storage = _StorageType.oneDrive;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() => _errorMessage = 'OneDrive connection failed: $e');
    } finally {
      setState(() => _isConnectingOneDrive = false);
    }
  }

  Future<void> _disconnectOneDrive() async {
    await BackupService.instance.disconnectOneDrive();
    setState(() {
      _oneDriveAccount = null;
      _oneDriveFolderId = null;
      _oneDriveFolderName = null;
      if (_storage == _StorageType.oneDrive) {
        _storage = _StorageType.local;
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

  Future<void> _connectWebDav() async {
    setState(() => _isConnectingWebDav = true);
    try {
      final account = await showDialog<String?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => WebDavConfigDialog(
          initialConfig: BackupService.instance.currentWebDavConfig,
        ),
      );
      if (account != null) {
        setState(() {
          _webDavAccount = account;
          _webDavFolderPath = ref.read(backupWebDavFolderPathProvider);
          _webDavFolderName = ref.read(backupWebDavFolderNameProvider);
          _storage = _StorageType.webDav;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'WebDAV connection failed: $e');
    } finally {
      setState(() => _isConnectingWebDav = false);
    }
  }

  Future<void> _disconnectWebDav() async {
    await BackupService.instance.disconnectWebDav();
    setState(() {
      _webDavAccount = null;
      _webDavFolderPath = null;
      _webDavFolderName = null;
      if (_storage == _StorageType.webDav) {
        _storage = _StorageType.local;
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

  Future<void> _connectSftp() async {
    setState(() => _isConnectingSftp = true);
    try {
      final account = await showDialog<String?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => SftpConfigDialog(
          initialConfig: BackupService.instance.currentSftpConfig,
        ),
      );
      if (account != null) {
        setState(() {
          _sftpAccount = account;
          _sftpFolderPath = ref.read(backupSftpFolderPathProvider);
          _sftpFolderName = ref.read(backupSftpFolderNameProvider);
          _storage = _StorageType.sftp;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'SFTP connection failed: $e');
    } finally {
      setState(() => _isConnectingSftp = false);
    }
  }

  Future<void> _disconnectSftp() async {
    await BackupService.instance.disconnectSftp();
    setState(() {
      _sftpAccount = null;
      _sftpFolderPath = null;
      _sftpFolderName = null;
      if (_storage == _StorageType.sftp) {
        _storage = _StorageType.local;
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

  Future<void> _connectS3() async {
    setState(() => _isConnectingS3 = true);
    try {
      final account = await showDialog<String?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => S3ConfigDialog(
          initialConfig: BackupService.instance.currentS3Config,
        ),
      );
      if (account != null) {
        setState(() {
          _s3Account = account;
          _s3FolderPath = ref.read(backupS3FolderPathProvider);
          _s3FolderName = ref.read(backupS3FolderNameProvider);
          _storage = _StorageType.s3;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'S3 connection failed: $e');
    } finally {
      setState(() => _isConnectingS3 = false);
    }
  }

  Future<void> _disconnectS3() async {
    await BackupService.instance.disconnectS3();
    setState(() {
      _s3Account = null;
      _s3FolderPath = null;
      _s3FolderName = null;
      if (_storage == _StorageType.s3) {
        _storage = _StorageType.local;
      }
    });
  }

  Future<void> _pickS3Folder() async {
    final result = await showDialog<CloudFolder?>(
      context: context,
      builder: (_) => _CloudFolderPickerDialog(
        cloudType: _CloudType.s3,
        initialFolderId: _s3FolderPath,
      ),
    );
    if (result != null) {
      setState(() {
        _s3FolderPath = result.id;
        _s3FolderName = result.displayPath;
      });
    }
  }

  // ── Database name ────────────────────────────────────────────────────────

  Widget _buildNameSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Database Name',
          style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        _ShadowedInput(
          child: TextField(
            controller: _nameController,
            style: _uText(13, _kTitle),
            onChanged: (_) => setState(() => _errorMessage = null),
            decoration: _fieldDecoration(
              hint: 'e.g. My Vault',
              prefixIcon: TablerIcons.database_edit,
            ),
          ),
        ),
      ],
    );
  }

  // ── Password section ─────────────────────────────────────────────────────

  Widget _buildPasswordSection() {
    final bool passwordDisabled = _acceptEmptyPassword;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Master Password',
          style: _uText(13, _kTitle, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        _LabeledField(
          label: 'Master Password',
          child: _ShadowedInput(
            child: TextField(
              controller: _passwordController,
              enabled: !passwordDisabled,
              obscureText: passwordDisabled ? false : _obscurePassword,
              enableSuggestions: false,
              autocorrect: false,
              style: _uText(13, passwordDisabled ? _kLabel : _kTitle),
              onChanged: (_) => setState(() => _errorMessage = null),
              decoration: _fieldDecoration(
                hint: passwordDisabled
                    ? 'Empty password enabled'
                    : 'New Password',
                prefixIcon: TablerIcons.key,
                suffix: passwordDisabled
                    ? null
                    : IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? TablerIcons.eye
                              : TablerIcons.eye_off,
                          size: 15,
                          color: _kIcon,
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _LabeledField(
          label: 'Confirm',
          child: _ShadowedInput(
            child: TextField(
              controller: _confirmController,
              enabled: !passwordDisabled,
              obscureText: passwordDisabled ? false : _obscureConfirm,
              enableSuggestions: false,
              autocorrect: false,
              style: _uText(13, passwordDisabled ? _kLabel : _kTitle),
              onChanged: (_) => setState(() => _errorMessage = null),
              decoration: _fieldDecoration(
                hint: passwordDisabled
                    ? 'Confirmation not required'
                    : 'Confirm New Password',
                prefixIcon: TablerIcons.lock_check,
                suffix: passwordDisabled
                    ? null
                    : IconButton(
                        onPressed: () => setState(
                          () => _obscureConfirm = !_obscureConfirm,
                        ),
                        icon: Icon(
                          _obscureConfirm
                              ? TablerIcons.eye
                              : TablerIcons.eye_off,
                          size: 15,
                          color: _kIcon,
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _ToggleRow(
          label: 'Accept Empty Password',
          value: _acceptEmptyPassword,
          onChanged: (v) => setState(() {
            _acceptEmptyPassword = v;
            _errorMessage = null;
            if (v) {
              _passwordController.clear();
              _confirmController.clear();
            }
          }),
        ),
        const SizedBox(height: 6),
        _ToggleRow(
          label: 'Show Advanced',
          value: _showAdvanced,
          onChanged: (v) => setState(() => _showAdvanced = v),
        ),
      ],
    );
  }

  // ── Key file section ─────────────────────────────────────────────────────

  Widget _buildKeyFileSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ToggleRow(
          label: 'Use a Key File',
          value: _useKeyFile,
          onChanged: (v) => setState(() {
            _useKeyFile = v;
            if (!v) _keyFilePath = null;
          }),
        ),
        if (_useKeyFile) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              _OutlineButton(
                label: 'Select...',
                onPressed: _pickKeyFile,
              ),
              const SizedBox(width: 8),
              _OutlineButton(
                label: 'Create...',
                onPressed: _createKeyFile,
              ),
            ],
          ),
          if (_keyFilePath != null) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorderRow),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _kPeach,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      TablerIcons.key,
                      size: 16,
                      color: _kBlue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'Selected key file',
                          style: _uText(
                            10,
                            _kLabel,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _fileName(_keyFilePath!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _uText(
                            12,
                            _kTitle,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _keyFilePath = null),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: _kBorderRow),
                      ),
                      child: const Icon(
                        TablerIcons.x,
                        size: 14,
                        color: _kIcon,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  // ── Database format ──────────────────────────────────────────────────────

  Widget _buildFormatSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Database Format',
          style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        _FormatDropdown(
          selected: _format,
          onSelect: (f) => setState(() => _format = f),
        ),
      ],
    );
  }

  // ── Error ────────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(TablerIcons.alert_circle,
              size: 14, color: Color(0xFFEF4444)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_errorMessage!,
                style: _uText(11, const Color(0xFFEF4444))),
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

  // ── Footer ───────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: _kPaperBright,
        border: Border(top: BorderSide(color: _kBorderSoft)),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(17),
          bottomRight: Radius.circular(17),
        ),
      ),
      child: _step == _WizardStep.provider
          ? _buildProviderFooter()
          : _buildDetailsFooter(),
    );
  }

  Widget _buildProviderFooter() {
    final bool canAdvance = _providerReady && !_isCreating;
    return Row(
      children: <Widget>[
        OutlinedButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: _kTitle,
            side: const BorderSide(color: _kInkBorder),
            backgroundColor: _kPaperBright,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            textStyle: _uText(12, _kLabel, fontWeight: FontWeight.w600),
          ),
          child: const Text('Cancel'),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: canAdvance ? _goToDetails : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kBlue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _kBorderSoft,
            shadowColor: _kInkBorder,
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            textStyle: _uText(12, Colors.white, fontWeight: FontWeight.w600),
          ),
          icon: const Text('Next'),
          label: const Icon(TablerIcons.arrow_right, size: 16),
        ),
      ],
    );
  }

  Widget _buildDetailsFooter() {
    return Row(
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: _isCreating ? null : _goToProvider,
          style: OutlinedButton.styleFrom(
            foregroundColor: _kTitle,
            side: const BorderSide(color: _kInkBorder),
            backgroundColor: _kPaperBright,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            textStyle: _uText(12, _kLabel, fontWeight: FontWeight.w600),
          ),
          icon: const Icon(TablerIcons.arrow_left, size: 16),
          label: const Text('Back'),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: _isCreating ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kBlue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _kBorderSoft,
            shadowColor: _kInkBorder,
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            textStyle: _uText(12, Colors.white, fontWeight: FontWeight.w600),
          ),
          child: _isCreating
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Create Database'),
        ),
      ],
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _pickLocalDirectory() async {
    // Use the native picker so the bookmark is created while NSOpenPanel
    // still holds the security scope — guarantees cross-session write access.
    final picked = await BookmarkService.instance.pickDirectoryWithBookmark();
    if (picked != null) {
      setState(() {
        _localDirectory = picked.path;
        _storage = _StorageType.local;
        _errorMessage = null;
      });
    }
  }

  kdbx.KdbxVersion? _kdbxVersion() {
    return _format == _DbFormat.kdbx31 ? kdbx.KdbxVersion.V3_1 : null;
  }

  Future<void> _createKeyFile() async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save New Key File',
        fileName: 'lumenpass.keyx',
        lockParentWindow: true,
      );
      if (path == null) return;
      final creds = kdbx.KeyFileCredentials.random();
      final bytes = creds.toXmlV2();
      await File(path).writeAsBytes(bytes);
      setState(() => _keyFilePath = path);
    } on MissingPluginException {
      setState(() => _errorMessage = 'File picker is unavailable.');
    } catch (e) {
      setState(() => _errorMessage = 'Could not create key file: $e');
    }
  }

  Future<void> _pickKeyFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose Key File',
        lockParentWindow: true,
        type: Platform.isMacOS ? FileType.any : FileType.custom,
        allowedExtensions:
            Platform.isMacOS ? null : <String>['key', 'keyx', 'xml'],
        withData: false,
      );
      final path = result?.files.single.path;
      if (path != null) {
        setState(() => _keyFilePath = path);
      }
    } on MissingPluginException {
      setState(() => _errorMessage = 'File picker is unavailable.');
    } catch (e) {
      setState(() => _errorMessage = 'Could not pick key file: $e');
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Enter a database name.');
      return;
    }

    if (_storage == _StorageType.local && _localDirectory == null) {
      setState(
        () => _errorMessage = 'Choose a save location — click Browse…',
      );
      return;
    }

    if (_storage == _StorageType.googleDrive && _googleAccount == null) {
      setState(() => _errorMessage = 'Connect to Google Drive first.');
      return;
    }

    if (_storage == _StorageType.dropbox && _dropboxAccount == null) {
      setState(() => _errorMessage = 'Connect to Dropbox first.');
      return;
    }

    if (_storage == _StorageType.oneDrive && _oneDriveAccount == null) {
      setState(() => _errorMessage = 'Connect to OneDrive first.');
      return;
    }

    if (_storage == _StorageType.webDav && _webDavAccount == null) {
      setState(() => _errorMessage = 'Connect to WebDAV first.');
      return;
    }

    if (_storage == _StorageType.sftp && _sftpAccount == null) {
      setState(() => _errorMessage = 'Connect to SFTP first.');
      return;
    }

    if (_storage == _StorageType.s3 && _s3Account == null) {
      setState(() => _errorMessage = 'Connect to Amazon S3 first.');
      return;
    }

    if (!_acceptEmptyPassword) {
      if (_passwordController.text.isEmpty) {
        setState(() => _errorMessage = 'Enter a master password.');
        return;
      }
      if (_passwordController.text != _confirmController.text) {
        setState(() => _errorMessage = 'Passwords do not match.');
        return;
      }
    }

    if (!_format.isSupported) {
      setState(
        () =>
            _errorMessage = 'Only KDBX 4.x and KDBX 3.1 formats are supported.',
      );
      return;
    }

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

      final String password =
          _acceptEmptyPassword ? '' : _passwordController.text;

      Uint8List? keyFileBytes;
      if (_useKeyFile && _keyFilePath != null) {
        keyFileBytes = await File(_keyFilePath!).readAsBytes();
      }

      if (_storage == _StorageType.googleDrive ||
          _storage == _StorageType.dropbox ||
          _storage == _StorageType.oneDrive ||
          _storage == _StorageType.webDav ||
          _storage == _StorageType.sftp ||
          _storage == _StorageType.s3) {
        // ── Cloud path: create in app-support cache, then upload ──────────
        final appSupport = await getApplicationSupportDirectory();
        final cacheDir = Directory(p.join(appSupport.path, 'cloud_databases'));
        await cacheDir.create(recursive: true);
        final outputPath = p.join(cacheDir.path, '$safeName.kdbx');

        await ref.read(kdbxRepositoryProvider).createDatabase(
              databasePath: outputPath,
              databaseName: name,
              password: password,
              keyFileBytes: keyFileBytes,
              version: _kdbxVersion(),
            );

        final bytes = await File(outputPath).readAsBytes();

        String? cloudFileId;
        String? cloudFileName;

        if (_storage == _StorageType.googleDrive) {
          final driveFileId =
              await BackupService.instance.uploadBytesToGoogleDrive(
            bytes,
            '$safeName.kdbx',
            folderId: _googleFolderId,
          );
          cloudFileId = driveFileId.isNotEmpty ? driveFileId : null;
          cloudFileName = '$safeName.kdbx';
        } else if (_storage == _StorageType.dropbox) {
          final folderPath =
              (_dropboxFolderPath != null && _dropboxFolderPath!.isNotEmpty)
                  ? _dropboxFolderPath!
                  : '';
          final dropboxFilePath = folderPath.isNotEmpty
              ? '$folderPath/$safeName.kdbx'
              : '/$safeName.kdbx';
          await BackupService.instance
              .uploadBytesToDropbox(bytes, dropboxFilePath);
          cloudFileId = dropboxFilePath.toLowerCase();
          cloudFileName = '$safeName.kdbx';
        } else if (_storage == _StorageType.oneDrive) {
          // OneDrive
          final folderId = _oneDriveFolderId ?? '';
          final itemId = await BackupService.instance.uploadNewFileToOneDrive(
            bytes,
            folderId.isNotEmpty ? folderId : 'root',
            '$safeName.kdbx',
          );
          cloudFileId = itemId.isNotEmpty ? itemId : null;
          cloudFileName = '$safeName.kdbx';
        } else if (_storage == _StorageType.webDav) {
          // WebDAV
          final folderPath = _webDavFolderPath ??
              BackupService.instance.currentWebDavConfig?.rootPath ??
              '/';
          final remotePath = await BackupService.instance.uploadNewFileToWebDav(
            bytes,
            folderPath,
            '$safeName.kdbx',
          );
          cloudFileId = remotePath.isNotEmpty ? remotePath : null;
          cloudFileName = '$safeName.kdbx';
        } else if (_storage == _StorageType.s3) {
          // S3
          final folderPath = _s3FolderPath ??
              BackupService.instance.currentS3Config?.rootPath ??
              '';
          final remotePath = await BackupService.instance.uploadNewFileToS3(
            bytes,
            folderPath,
            '$safeName.kdbx',
          );
          cloudFileId = remotePath;
          cloudFileName = '$safeName.kdbx';
        } else {
          // SFTP
          final folderPath = _sftpFolderPath ??
              BackupService.instance.currentSftpConfig?.rootPath ??
              '/';
          final remotePath = await BackupService.instance.uploadNewFileToSftp(
            bytes,
            folderPath,
            '$safeName.kdbx',
          );
          cloudFileId = remotePath.isNotEmpty ? remotePath : null;
          cloudFileName = '$safeName.kdbx';
        }

        await ref.read(databaseRegistryProvider.notifier).addDatabase(
              nickname: name,
              databasePath: outputPath,
              storageType: switch (_storage) {
                _StorageType.googleDrive => 'googleDrive',
                _StorageType.dropbox => 'dropbox',
                _StorageType.oneDrive => 'oneDrive',
                _StorageType.webDav => 'webdav',
                _StorageType.sftp => 'sftp',
                _StorageType.s3 => 's3',
                _StorageType.local => 'local',
              },
              cloudFileId: cloudFileId,
              cloudFileName: cloudFileName,
            );

        if (!mounted) return;
        Navigator.of(context).pop();
        await widget.onCreated(outputPath, name);
      } else {
        // ── Local path ────────────────────────────────────────────────────
        final separator = Platform.pathSeparator;
        final outputPath = '$_localDirectory$separator$safeName.kdbx';

        // Stop if a vault with the same name already exists at this location,
        // so we never silently overwrite an existing database.
        if (await File(outputPath).exists()) {
          setState(() {
            _isCreating = false;
            _errorMessage =
                'A vault named "$safeName" already exists at this location. '
                'Choose a different name.';
          });
          return;
        }

        await ref.read(kdbxRepositoryProvider).createDatabase(
              databasePath: outputPath,
              databaseName: name,
              password: password,
              keyFileBytes: keyFileBytes,
              version: _kdbxVersion(),
            );

        // Create a security-scoped bookmark for the new file while we still
        // have access through the directory security scope.
        final fileBookmark =
            await BookmarkService.instance.createBookmarkForPath(outputPath);

        // Register in the database list with the file-level bookmark.
        await ref.read(databaseRegistryProvider.notifier).addDatabase(
              nickname: name,
              databasePath: outputPath,
              bookmark: fileBookmark.isNotEmpty ? fileBookmark : null,
            );

        if (!mounted) return;
        Navigator.of(context).pop();
        await widget.onCreated(outputPath, name);
      }
    } catch (e) {
      setState(() {
        _isCreating = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }
}

// ── Reusable sub-widgets ─────────────────────────────────────────────────────

class _ShadowedInput extends StatelessWidget {
  const _ShadowedInput({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1A252628),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x14252628),
            blurRadius: 10,
            spreadRadius: -2,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: const _InputInnerShadowPainter(),
        child: child,
      ),
    );
  }
}

class _InputInnerShadowPainter extends CustomPainter {
  const _InputInnerShadowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final fieldBounds = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    final outside = Path()
      ..addRect(
        Rect.fromLTRB(-12, -12, size.width + 12, size.height + 12),
      );
    final inset = Path()
      ..addRRect(fieldBounds.deflate(0.5).shift(const Offset(0, 0.75)));
    final innerEdge = Path.combine(PathOperation.difference, outside, inset);

    canvas
      ..save()
      ..clipRRect(fieldBounds)
      ..drawPath(
        innerEdge,
        Paint()
          ..color = const Color(0x18252628)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _InputInnerShadowPainter oldDelegate) => false;
}

class _DestinationGrid extends StatelessWidget {
  const _DestinationGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final width = (constraints.maxWidth - gap) / 2;
        final height = (width * 0.50).clamp(148.0, 164.0).toDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final child in children)
              SizedBox(width: width, height: height, child: child),
          ],
        );
      },
    );
  }
}

class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.iconChild,
    required this.label,
    required this.detail,
    required this.selected,
    required this.actionLabel,
    required this.onAction,
  });

  final Widget iconChild;
  final String label;
  final String detail;
  final bool selected;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? _kMintSoft : _kPaperBright,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? _kInkBorder : _kBorderRow,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? _kYellow : _kPeach,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: iconChild,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _uText(13, _kTitle, fontWeight: FontWeight.w700),
                ),
              ),
              if (selected)
                const Icon(TablerIcons.circle_check_filled,
                    size: 18, color: _kMint),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _uText(10.5, _kLabel),
          ),
          const Spacer(),
          Align(
            alignment: Alignment.bottomRight,
            child: OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                foregroundColor: _kTitle,
                side: const BorderSide(color: _kInkBorder),
                backgroundColor: _kPaperBright,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: const Size(88, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: _uText(11, _kTitle, fontWeight: FontWeight.w700),
              ),
              child: Text(actionLabel),
            ),
          ),
        ],
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
    final bool connected = account != null;
    return MouseRegion(
      cursor: onSelect == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? _kMintSoft : _kPaperBright,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _kInkBorder : _kBorderRow,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? _kYellow : _kPeach,
                      borderRadius: BorderRadius.circular(10),
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
                            13,
                            _kTitle,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (connected)
                          Text(
                            account!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _uText(10, _kLabel),
                          ),
                      ],
                    ),
                  ),
                  if (isConnecting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  else if (selected)
                    const Icon(TablerIcons.circle_check_filled,
                        size: 18, color: _kMint),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(connected ? TablerIcons.folder : TablerIcons.cloud,
                      size: 12, color: _kIcon),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      connected ? (folderName ?? '/ (root)') : 'Not connected',
                      style: _uText(10.5, _kLabel),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (!isConnecting)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    if (connected) ...<Widget>[
                      _TextDestructiveButton(
                        label: 'Disconnect',
                        onPressed: onDisconnect,
                      ),
                      const SizedBox(width: 8),
                      _TilePrimaryButton(
                        label: folderName != null ? 'Change' : 'Select folder',
                        onPressed: onPickFolder,
                      ),
                    ] else
                      _TilePrimaryButton(
                        label: 'Connect',
                        onPressed: onConnect,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TilePrimaryButton extends StatelessWidget {
  const _TilePrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _kBorderSoft,
        elevation: 0,
        side: const BorderSide(color: _kInkBorder),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        minimumSize: const Size(104, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: _uText(10.5, Colors.white, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

// ── Cloud folder picker ───────────────────────────────────────────────────────

enum _CloudType { googleDrive, dropbox, oneDrive, webDav, sftp, s3 }

class _CloudFolderPickerDialog extends StatefulWidget {
  const _CloudFolderPickerDialog(
      {required this.cloudType, this.initialFolderId});
  final _CloudType cloudType;
  final String? initialFolderId;

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
    if (widget.initialFolderId != null &&
        widget.initialFolderId!.isNotEmpty &&
        widget.initialFolderId != '/') {
      // Split the path into breadcrumb segments.
      final segments = widget.initialFolderId!
          .split('/')
          .where((s) => s.isNotEmpty)
          .toList();
      var accumulatedPath = '';
      for (int i = 0; i < segments.length; i++) {
        accumulatedPath += '/${segments[i]}';
        _breadcrumb.add(CloudFolder(
          id: widget.cloudType == _CloudType.s3
              ? '${segments.sublist(0, i + 1).join('/')}/'
              : accumulatedPath,
          name: segments[i],
          path: accumulatedPath,
        ));
      }
    }
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
      if (widget.cloudType == _CloudType.googleDrive) {
        folders = await BackupService.instance.listGoogleDriveFolders(
          parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
        );
      } else if (widget.cloudType == _CloudType.dropbox) {
        folders = await BackupService.instance.listDropboxFolders(
          _breadcrumb.isEmpty ? '' : _breadcrumb.last.id,
        );
      } else if (widget.cloudType == _CloudType.oneDrive) {
        folders = await BackupService.instance.listOneDriveFolders(
          parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
        );
      } else if (widget.cloudType == _CloudType.webDav) {
        folders = await BackupService.instance.listWebDavFolders(
          parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
        );
      } else if (widget.cloudType == _CloudType.sftp) {
        folders = await BackupService.instance.listSftpFolders(
          parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
        );
      } else {
        folders = await BackupService.instance.listS3Folders(
          prefix: _breadcrumb.isEmpty ? '' : _breadcrumb.last.id,
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
      if (widget.cloudType == _CloudType.googleDrive) {
        final rawCreated = await BackupService.instance.createGoogleDriveFolder(
          folderName,
          parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
        );
        created = CloudFolder(
          id: rawCreated.id,
          name: rawCreated.name,
          path: _childDisplayPath(folderName),
        );
      } else if (widget.cloudType == _CloudType.dropbox) {
        final parent = _breadcrumb.isEmpty ? '' : _breadcrumb.last.id;
        final path = parent.isEmpty ? '/$folderName' : '$parent/$folderName';
        await BackupService.instance.createDropboxFolder(path);
        created = CloudFolder(
          id: path.toLowerCase().replaceAll(' ', '-'),
          name: folderName,
          path: _childDisplayPath(folderName),
        );
      } else if (widget.cloudType == _CloudType.oneDrive) {
        final rawCreated = await BackupService.instance.createOneDriveFolder(
          folderName,
          parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
        );
        created = CloudFolder(
          id: rawCreated.id,
          name: rawCreated.name,
          path: _childDisplayPath(folderName),
        );
      } else if (widget.cloudType == _CloudType.webDav) {
        final rawCreated = await BackupService.instance.createWebDavFolder(
          folderName,
          parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
        );
        created = CloudFolder(
          id: rawCreated.id,
          name: rawCreated.name,
          path: _childDisplayPath(folderName),
        );
      } else if (widget.cloudType == _CloudType.sftp) {
        final rawCreated = await BackupService.instance.createSftpFolder(
          folderName,
          parentId: _breadcrumb.isEmpty ? null : _breadcrumb.last.id,
        );
        created = CloudFolder(
          id: rawCreated.id,
          name: rawCreated.name,
          path: _childDisplayPath(folderName),
        );
      } else {
        // S3
        final parentPrefix = _breadcrumb.isEmpty ? '' : _breadcrumb.last.id;
        await S3Service.instance.createPrefix(parentPrefix, folderName);
        created = CloudFolder(
          id: parentPrefix.isEmpty
              ? '$folderName/'
              : '${parentPrefix.endsWith('/') ? parentPrefix : '$parentPrefix/'}$folderName/',
          name: folderName,
          path: _childDisplayPath(folderName),
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
    final title = widget.cloudType == _CloudType.googleDrive
        ? 'Select Google Drive Folder'
        : widget.cloudType == _CloudType.dropbox
            ? 'Select Dropbox Folder'
            : widget.cloudType == _CloudType.oneDrive
                ? 'Select OneDrive Folder'
                : widget.cloudType == _CloudType.webDav
                    ? 'Select WebDAV Folder'
                    : widget.cloudType == _CloudType.sftp
                        ? 'Select SFTP Folder'
                        : 'Select Amazon S3 Folder';
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
                    Text('Back',
                        style: _uText(11, _kBlue, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            )
          else ...<Widget>[
            widget.cloudType == _CloudType.webDav
                ? Image.asset('assets/images/webdav.png', width: 16, height: 16)
                : widget.cloudType == _CloudType.sftp
                    ? Image.asset('assets/images/sftp.png',
                        width: 16, height: 16)
                    : widget.cloudType == _CloudType.s3
                        ? Image.asset('assets/images/aws-s3-icon.png',
                            width: 16, height: 16)
                        : Icon(
                            widget.cloudType == _CloudType.googleDrive
                                ? TablerIcons.brand_google_drive
                                : widget.cloudType == _CloudType.oneDrive
                                    ? TablerIcons.brand_onedrive
                                    : TablerIcons.cloud,
                            size: 16,
                            color: _kBlue,
                          ),
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
    final bool canCreateFolder =
        !_creatingFolder && _newFolderController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: const BoxDecoration(
        color: _kCanvas,
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
                    disabledBackgroundColor: _kBorderSoft,
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
                  borderRadius: BorderRadius.circular(8)),
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
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white),
            ),
            child: const Text('Select Path'),
          ),
        ],
      ),
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
                  style: _uText(12, _hovered ? _kBlue : _kTitle,
                      fontWeight: FontWeight.w500),
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

class _StepDot extends StatelessWidget {
  const _StepDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: active ? 18 : 7,
      height: 7,
      decoration: BoxDecoration(
        color: active ? _kBlue : _kYellow,
        border: Border.all(color: _kInkBorder),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Transform.scale(
          scale: 0.75,
          alignment: Alignment.centerLeft,
          child: Switch.adaptive(
            value: value,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 2),
        Text(label, style: _uText(12, _kTitle, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: _uText(12, _kLabel, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _kTitle,
        side: const BorderSide(color: _kInkBorder),
        backgroundColor: _kPaperBright,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
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
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFB93827),
        backgroundColor: const Color(0xFFFFE8DF),
        side: const BorderSide(color: Color(0xFFE36A54)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        minimumSize: const Size(104, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle:
            _uText(10.5, const Color(0xFFB93827), fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

class _FormatDropdown extends StatelessWidget {
  const _FormatDropdown({
    required this.selected,
    required this.onSelect,
  });

  final _DbFormat selected;
  final ValueChanged<_DbFormat> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorderRow),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_DbFormat>(
          value: selected,
          isExpanded: true,
          itemHeight: null,
          menuMaxHeight: 280,
          borderRadius: BorderRadius.circular(12),
          dropdownColor: Colors.white,
          icon: const Icon(
            TablerIcons.chevron_down,
            size: 16,
            color: _kIcon,
          ),
          style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
          selectedItemBuilder: (context) {
            return _DbFormat.values
                .map(
                  (format) => Align(
                    alignment: Alignment.centerLeft,
                    child: _FormatOption(
                      format: format,
                      compact: true,
                    ),
                  ),
                )
                .toList();
          },
          items: _DbFormat.values
              .map(
                (format) => DropdownMenuItem<_DbFormat>(
                  value: format,
                  enabled: format.isSupported,
                  child: _FormatOption(format: format),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              onSelect(value);
            }
          },
        ),
      ),
    );
  }
}

class _FormatOption extends StatelessWidget {
  const _FormatOption({
    required this.format,
    this.compact = false,
  });

  final _DbFormat format;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bool enabled = format.isSupported;
    final Color titleColor =
        enabled ? _kTitle : _kLabel.withValues(alpha: 0.85);
    final Color subtitleColor =
        enabled ? _kLabel : _kLabel.withValues(alpha: 0.75);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${format.title} (${format.versionLabel})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _uText(
                    12,
                    titleColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (format.badgeLabel != null) ...<Widget>[
                const SizedBox(width: 8),
                _FormatBadge(
                  label: format.badgeLabel!,
                  emphasized: enabled && format == _DbFormat.kdbx4,
                  subdued: !enabled,
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            compact
                ? (enabled
                    ? format.menuDescription
                    : 'Unavailable for creation')
                : format.menuDescription,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: _uText(
              compact ? 10 : 11,
              subtitleColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatBadge extends StatelessWidget {
  const _FormatBadge({
    required this.label,
    required this.emphasized,
    required this.subdued,
  });

  final String label;
  final bool emphasized;
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor;
    final Color foregroundColor;

    if (subdued) {
      backgroundColor = _kCanvas;
      foregroundColor = const Color(0xFF8A97AC);
    } else if (emphasized) {
      backgroundColor = _kYellow;
      foregroundColor = _kBlue;
    } else {
      backgroundColor = const Color(0xFFF4F6FA);
      foregroundColor = _kLabel;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: _uText(
          9,
          foregroundColor,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ── Utility ──────────────────────────────────────────────────────────────────

String _fileName(String path) {
  final segs = path.split(RegExp(r'[\/\\]'));
  return segs.isEmpty ? path : segs.last;
}

String _shortenPath(String path) {
  const int maxLen = 38;
  final home = Platform.environment['HOME'] ?? '';
  final shortened = home.isNotEmpty ? path.replaceFirst(home, '~') : path;
  if (shortened.length <= maxLen) return shortened;
  return '…${shortened.substring(shortened.length - maxLen + 1)}';
}
