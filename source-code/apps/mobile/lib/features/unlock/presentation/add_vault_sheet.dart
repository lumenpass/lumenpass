import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kdbx/kdbx.dart' as kdbx;
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/repository/providers.dart';
import '../../../core/repository/vault_write_scheduler_provider.dart';
import '../../../core/services/cloud_database_service.dart';
import '../../../core/services/cloud_vault_cache.dart';

import '../../../core/ui/app_snack_bar.dart';
import '../application/database_registry.dart';
import 'cloud_browser_page.dart';
import 'webdav_config_page.dart';
import 'sftp_config_page.dart';
import 's3_config_dialog.dart';

// ── Enums ─────────────────────────────────────────────────────────────────────

enum _CloudType { googleDrive, dropbox, oneDrive, webDav, sftp, s3 }

// ── Theme constants ───────────────────────────────────────────────────────────

const _kInk = Color(0xFF0A3B48);
const _kMuted = Color(0xFF6B858D);
const _kBorder = Color(0xFFE3EAF0);
const _kBg = Color(0xFFF4F9FA);

// ── Add Vault Sheet (entry point) ─────────────────────────────────────────────

/// Main bottom sheet shown when the user taps "+".
/// Header: drag handle and close; options: Create New, Open Local, Drive, Dropbox.
class AddVaultSheet extends ConsumerStatefulWidget {
  const AddVaultSheet({super.key, required this.onAdded});

  final void Function(DatabaseRecord) onAdded;

  @override
  ConsumerState<AddVaultSheet> createState() => _AddVaultSheetState();
}

class _AddVaultSheetState extends ConsumerState<AddVaultSheet> {
  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Color(0x290A2F3D),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: Color(0xFFE1EAF0))),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCE6EC),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.only(right: 54),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE5EFF3),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.storage_rounded,
                                color: _kInk,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Add vault',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: const Color(0xFF163640),
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 16,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x180F172A),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(
                        side: BorderSide(color: Color(0xFFD7E2E8)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        customBorder: const CircleBorder(),
                        child: const SizedBox(
                          width: 38,
                          height: 38,
                          child: Icon(
                            Icons.close_rounded,
                            color: Color(0xFF5E7180),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: Material(
              color: Colors.white,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(0, 10, 0, bottomPad + 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _OptionTile(
                      icon: Icons.storage_rounded,
                      iconBg: const Color(0xFFDCEEF2),
                      iconColor: _kInk,
                      title: 'Create New Database',
                      subtitle: 'Set up a fresh encrypted vault',
                      showDivider: true,
                      onTap: _openCreatePage,
                    ),
                    _OptionTile(
                      icon: Icons.folder_open_rounded,
                      iconBg: const Color(0xFFF0F4FA),
                      iconColor: const Color(0xFF4A6670),
                      title: 'Open Local File',
                      subtitle: 'Pick a .kdbx file from device storage',
                      showDivider: true,
                      onTap: _pickLocalFile,
                    ),
                    _OptionTile(
                      iconAsset: 'assets/images/google-drive.png',
                      iconBg: const Color(0xFFF0F4FF),
                      title: 'Google Drive',
                      subtitle: 'Browse and open from your Drive',
                      showDivider: true,
                      onTap: CloudDatabaseService.isGoogleDriveConfigured
                          ? () => _openCloudBrowser(_CloudType.googleDrive)
                          : null,
                    ),
                    if (!CloudDatabaseService.isGoogleDriveConfigured)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: Text(
                          'Google Drive needs GOOGLE_CLIENT_ID via --dart-define '
                          'and ios/Flutter/GoogleClient.xcconfig on iOS '
                          '(see GoogleClient.xcconfig.example).',
                          style: TextStyle(color: _kMuted, fontSize: 11),
                        ),
                      ),
                    _OptionTile(
                      iconAsset: 'assets/images/dropbox.png',
                      iconBg: const Color(0xFFEFF6FF),
                      title: 'Dropbox',
                      subtitle: 'Browse and open from your Dropbox',
                      showDivider: true,
                      onTap: CloudDatabaseService.isDropboxConfigured
                          ? () => _openCloudBrowser(_CloudType.dropbox)
                          : null,
                    ),
                    if (!CloudDatabaseService.isDropboxConfigured)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: Text(
                          'Dropbox requires DROPBOX_APP_KEY via --dart-define.',
                          style: TextStyle(color: _kMuted, fontSize: 11),
                        ),
                      ),
                    _OptionTile(
                      iconAsset: 'assets/images/onedrive.png',
                      iconBg: const Color(0xFFE8F4FD),
                      title: 'OneDrive',
                      subtitle: 'Browse and open from your OneDrive',
                      showDivider: true,
                      onTap: CloudDatabaseService.isOneDriveConfigured
                          ? () => _openCloudBrowser(_CloudType.oneDrive)
                          : null,
                    ),

                    if (!CloudDatabaseService.isOneDriveConfigured)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: Text(
                          'OneDrive requires ONEDRIVE_CLIENT_ID via --dart-define.',
                          style: TextStyle(color: _kMuted, fontSize: 11),
                        ),
                      ),
                    _OptionTile(
                      iconAsset: 'assets/images/webdav.png',
                      iconBg: const Color(0xFFEFF3F8),
                      title: 'WebDAV',
                      subtitle: 'Connect a WebDAV server (Nextcloud, Koofr...)',
                      showDivider: true,
                      onTap: () => _openCloudBrowser(_CloudType.webDav),
                    ),

                    _OptionTile(
                      iconAsset: 'assets/images/sftp.png',
                      iconBg: const Color(0xFFEEF2F6),
                      title: 'SFTP',
                      subtitle: 'Connect via SSH/SFTP (secure file transfer)',
                      showDivider: true,
                      onTap: () => _openCloudBrowser(_CloudType.sftp),
                    ),

                    _OptionTile(
                      iconAsset: 'assets/images/aws-s3-icon.png',
                      iconBg: const Color(0xFFF6F8FB),
                      title: 'Amazon S3',
                      subtitle: 'Connect any AWS S3 bucket',
                      onTap: () => _openCloudBrowser(_CloudType.s3),
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openCreatePage() {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => CreateDatabasePage(onAdded: widget.onAdded),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _pickLocalFile() async {
    final registry = ref.read(databaseRegistryProvider.notifier);
    final navigator = Navigator.of(context);
    navigator.pop();

    // Default to the same directory used when creating a local database, so
    // users see their existing vaults without having to navigate the Files app.
    String? initialDirectory;
    try {
      final dir = await getApplicationDocumentsDirectory();
      initialDirectory = dir.path;
    } catch (_) {}

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['kdbx', 'kdb'],
      initialDirectory: initialDirectory,
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;

    final filename = result.files.single.name;
    final nickname = p.basenameWithoutExtension(filename);

    final added = await registry.addDatabase(
      nickname: nickname,
      databasePath: path,
      storageType: 'local',
    );
    widget.onAdded(added);
  }

  Future<void> _openCloudBrowser(_CloudType cloudType) async {
    final messenger = ScaffoldMessenger.of(context);

    if (cloudType == _CloudType.googleDrive) {
      final account = CloudDatabaseService.instance.currentGoogleAccount;
      if (account == null) {
        try {
          await CloudDatabaseService.instance.connectGoogle();
        } catch (e) {
          if (messenger.mounted) {
            AppSnackBar.error(
              context,
              'Google sign-in failed: ${e.toString().replaceFirst('Exception: ', '')}',
            );
          }
          return;
        }

        if (CloudDatabaseService.instance.currentGoogleAccount == null) return;
      }
    } else if (cloudType == _CloudType.oneDrive) {
      if (!CloudDatabaseService.instance.isOneDriveConnected) {
        try {
          await CloudDatabaseService.instance.connectOneDrive();
        } catch (e) {
          if (messenger.mounted) {
            AppSnackBar.error(
              context,
              'OneDrive connection failed: ${e.toString().replaceFirst('Exception: ', '')}',
            );
          }
          return;
        }

        if (!CloudDatabaseService.instance.isOneDriveConnected) return;
      }
    } else if (cloudType == _CloudType.webDav) {
      if (!CloudDatabaseService.instance.isWebDavConnected) {
        final account = await Navigator.of(context).push<String?>(
          MaterialPageRoute<String?>(
            builder: (_) => WebDavConfigPage(
              initialConfig: CloudDatabaseService.instance.currentWebDavConfig,
            ),
            fullscreenDialog: true,
          ),
        );
        if (account == null ||
            !CloudDatabaseService.instance.isWebDavConnected) {
          return;
        }
      }
    } else if (cloudType == _CloudType.sftp) {
      if (!CloudDatabaseService.instance.isSftpConnected) {
        final account = await Navigator.of(context).push<String?>(
          MaterialPageRoute<String?>(
            builder: (_) => SftpConfigPage(
              initialConfig: CloudDatabaseService.instance.currentSftpConfig,
            ),
            fullscreenDialog: true,
          ),
        );
        if (account == null || !CloudDatabaseService.instance.isSftpConnected) {
          return;
        }
      }
    } else if (cloudType == _CloudType.s3) {
      if (!CloudDatabaseService.instance.isS3Connected) {
        final account = await Navigator.of(context).push<String?>(
          MaterialPageRoute<String?>(
            builder: (_) => const S3ConfigDialog(),
            fullscreenDialog: true,
          ),
        );
        if (account == null || !CloudDatabaseService.instance.isS3Connected) {
          return;
        }
      }
    } else {
      final token = CloudDatabaseService.instance.currentDropboxToken;
      if (token == null || token.isEmpty) {
        try {
          await CloudDatabaseService.instance.connectDropbox();
        } catch (e) {
          if (messenger.mounted) {
            AppSnackBar.error(
              context,
              'Dropbox connection failed: ${e.toString().replaceFirst('Exception: ', '')}',
            );
          }
          return;
        }

        final connectedToken =
            CloudDatabaseService.instance.currentDropboxToken;
        if (connectedToken == null || connectedToken.isEmpty) return;
      }
    }

    if (!mounted) return;
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => CloudBrowserPage(
          cloudType: switch (cloudType) {
            _CloudType.googleDrive => CloudKind.googleDrive,
            _CloudType.dropbox => CloudKind.dropbox,
            _CloudType.oneDrive => CloudKind.oneDrive,
            _CloudType.webDav => CloudKind.webdav,
            _CloudType.sftp => CloudKind.sftp,
            _CloudType.s3 => CloudKind.s3,
          },
          mode: CloudBrowserMode.selectVaultFile,
          onAdded: widget.onAdded,
        ),
        fullscreenDialog: true,
      ),
    );
  }
}

// ── Create Database Page ───────────────────────────────────────────────────────

/// Destination for a vault that is being created directly on a cloud provider.
///
/// When supplied to [CreateDatabasePage], the new `.kdbx` is generated, uploaded
/// to [kind] inside [folderId], cached locally and registered as a cloud vault —
/// instead of being written to a user-picked local directory.
class CloudCreateTarget {
  const CloudCreateTarget({
    required this.kind,
    required this.folderId,
    required this.folderName,
  });

  /// Which cloud provider the vault will live on.
  final CloudKind kind;

  /// Drive folderId / OneDrive folderId / Dropbox folder path. Empty == root.
  final String folderId;

  /// Human-friendly destination path used for display (e.g. `/Apps`).
  final String folderName;
}

/// Full-screen page for creating a new KeePass database.
///
/// Pass [cloudTarget] to create the vault on a cloud provider; leave it null to
/// create a local vault stored in a user-picked directory.
class CreateDatabasePage extends ConsumerStatefulWidget {
  const CreateDatabasePage({
    super.key,
    required this.onAdded,
    this.cloudTarget,
  });

  final void Function(DatabaseRecord) onAdded;

  /// When non-null the vault is created on the given cloud provider/folder.
  final CloudCreateTarget? cloudTarget;

  @override
  ConsumerState<CreateDatabasePage> createState() => _CreateDatabasePageState();
}

enum _DbFormat { kdbx4, kdbx31 }

extension _DbFormatLabel on _DbFormat {
  String get title {
    switch (this) {
      case _DbFormat.kdbx4:
        return 'KeePass 2 (KDBX 4.x)';
      case _DbFormat.kdbx31:
        return 'KeePass 2 (KDBX 3.1)';
    }
  }

  String get subtitle {
    switch (this) {
      case _DbFormat.kdbx4:
        return 'Modern format for new databases';
      case _DbFormat.kdbx31:
        return 'Older format for compatibility';
    }
  }
}

class _CreateDatabasePageState extends ConsumerState<CreateDatabasePage> {
  final _nameCtrl = TextEditingController(text: 'My Vault');
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscurePw = true;
  bool _obscureConfirm = true;
  bool _acceptEmpty = false;
  bool _showAdvanced = false;
  bool _useKeyFile = false;
  bool _isCreating = false;
  String? _storageDirectoryPath;
  String? _keyFilePath;
  _DbFormat _format = _DbFormat.kdbx4;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_onFormChanged);
    _passwordCtrl.addListener(_onFormChanged);
    _confirmCtrl.addListener(_onFormChanged);
    _loadDefaultStorageDirectory();
  }

  Future<void> _loadDefaultStorageDirectory() async {
    if (_isCloud) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      if (!mounted) return;
      setState(() => _storageDirectoryPath = dir.path);
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onFormChanged);
    _passwordCtrl.removeListener(_onFormChanged);
    _confirmCtrl.removeListener(_onFormChanged);
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _onFormChanged() {
    if (!mounted) return;
    setState(() => _error = null);
  }

  Future<void> _pickStorageDirectory() async {
    final selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose where to store your database',
    );
    if (!mounted || selectedDirectory == null || selectedDirectory.isEmpty) {
      return;
    }

    final writableDirectory = await _localWritableDirectoryPath();
    if (!mounted) return;
    setState(() {
      _storageDirectoryPath = writableDirectory;
      _error = selectedDirectory == writableDirectory
          ? null
          : 'On iOS, new local databases must be created in the app documents folder. '
                'Use Open Local File to add an existing vault from Files.';
    });
  }

  Future<String> _localWritableDirectoryPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<void> _pickKeyFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose Key File',
        type: FileType.custom,
        allowedExtensions: const ['key', 'keyx', 'xml'],
        withData: false,
      );
      final selectedPath = result?.files.single.path;
      if (!mounted || selectedPath == null || selectedPath.isEmpty) return;
      setState(() {
        _keyFilePath = selectedPath;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not pick key file: $e');
    }
  }

  Future<void> _createKeyFile() async {
    try {
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save New Key File',
        fileName: 'lumenpass.keyx',
      );
      if (!mounted || outputPath == null || outputPath.isEmpty) return;

      final creds = kdbx.KeyFileCredentials.random();
      final bytes = creds.toXmlV2();
      await File(outputPath).writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      setState(() {
        _useKeyFile = true;
        _keyFilePath = outputPath;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not create key file: $e');
    }
  }

  kdbx.KdbxVersion? _kdbxVersion() {
    return _format == _DbFormat.kdbx31 ? kdbx.KdbxVersion.V3_1 : null;
  }

  bool get _isCloud => widget.cloudTarget != null;

  List<String> get _validationIssues {
    final issues = <String>[];
    final name = _nameCtrl.text.trim();
    final storageDirectoryPath = _storageDirectoryPath?.trim() ?? '';
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;
    final hasKeyFile = _keyFilePath != null && _keyFilePath!.trim().isNotEmpty;

    if (name.isEmpty) {
      issues.add('Enter a database name.');
    }

    // Cloud vaults use the folder chosen in the previous step, so there is no
    // local storage directory to validate.
    if (!_isCloud && storageDirectoryPath.isEmpty) {
      issues.add('Choose a storage location.');
    }

    if (_acceptEmpty) {
      if (!_useKeyFile) {
        issues.add(
          _showAdvanced
              ? 'Turn on Use a Key File when Accept Empty Password is enabled.'
              : 'Turn on Show Advanced, then enable Use a Key File when Accept Empty Password is enabled.',
        );
      }
    } else {
      if (password.isEmpty) {
        issues.add('Enter a master password.');
      }

      if (confirm.isEmpty) {
        issues.add('Confirm the master password.');
      }

      if (password.isNotEmpty && confirm.isNotEmpty && password != confirm) {
        issues.add('Master password and confirmation must match.');
      }
    }

    if (_useKeyFile && !hasKeyFile) {
      issues.add('Select an existing key file or create a new one.');
    }

    return issues;
  }

  bool get _canSubmit => !_isCreating && _validationIssues.isEmpty;

  Future<void> _showSubmitHelp() async {
    final issues = _validationIssues;
    final title = issues.isEmpty
        ? 'Ready to Create'
        : 'Why Create Database Is Disabled';
    final intro = issues.isEmpty
        ? 'The form is fully validated and ready to submit.'
        : 'Complete the items below to enable Create Database:';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(intro, style: const TextStyle(fontSize: 14, color: _kInk)),
              const SizedBox(height: 12),
              if (issues.isEmpty)
                const _ValidationHintRow(
                  icon: Icons.check_circle_rounded,
                  iconColor: Color(0xFF16A34A),
                  message:
                      'Database name, password rules, storage location, and key file requirements are all satisfied.',
                )
              else
                for (final issue in issues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ValidationHintRow(
                      icon: Icons.remove_circle_outline_rounded,
                      iconColor: const Color(0xFFD97706),
                      message: issue,
                    ),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _canSubmit;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kInk,
        foregroundColor: Colors.white,
        title: Text(
          _isCloud ? 'Create Cloud Database' : 'Create New Database',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                _ErrorBanner(
                  message: _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
                const SizedBox(height: 16),
              ],
              _SectionLabel(label: 'Database Name'),
              const SizedBox(height: 8),
              _TextField(
                controller: _nameCtrl,
                hint: 'e.g. Personal, Work',
                enabled: !_isCreating,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _onFormChanged(),
              ),
              const SizedBox(height: 20),
              if (!_acceptEmpty) ...[
                _SectionLabel(label: 'Master Password'),
                const SizedBox(height: 8),
                _TextField(
                  controller: _passwordCtrl,
                  hint: 'Enter master password',
                  obscure: _obscurePw,
                  enabled: !_isCreating,
                  textInputAction: TextInputAction.next,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePw
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                      color: _kMuted,
                    ),
                    onPressed: () => setState(() => _obscurePw = !_obscurePw),
                  ),
                  onChanged: (_) => _onFormChanged(),
                ),
                const SizedBox(height: 12),
                _TextField(
                  controller: _confirmCtrl,
                  hint: 'Confirm master password',
                  obscure: _obscureConfirm,
                  enabled: !_isCreating,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  suffix: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                      color: _kMuted,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  onChanged: (_) => _onFormChanged(),
                ),
                const SizedBox(height: 20),
              ],
              _SectionLabel(label: 'Storage Location'),
              const SizedBox(height: 8),
              if (_isCloud)
                _CloudDestinationTile(target: widget.cloudTarget!)
              else
                _StorageDirectoryPicker(
                  path: _storageDirectoryPath,
                  enabled: !_isCreating,
                  onTap: _pickStorageDirectory,
                ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: _acceptEmpty,
                onChanged: _isCreating
                    ? null
                    : (value) => setState(() {
                        _acceptEmpty = value;
                        _error = null;
                        if (value) {
                          _passwordCtrl.clear();
                          _confirmCtrl.clear();
                        }
                      }),
                activeThumbColor: _kInk,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Accept Empty Password',
                  style: TextStyle(fontSize: 16, color: _kInk),
                ),
              ),
              SwitchListTile.adaptive(
                value: _showAdvanced,
                onChanged: _isCreating
                    ? null
                    : (value) => setState(() {
                        _showAdvanced = value;
                        _error = null;
                      }),
                activeThumbColor: _kInk,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Show Advanced',
                  style: TextStyle(fontSize: 16, color: _kInk),
                ),
              ),
              if (_showAdvanced) ...[
                SwitchListTile.adaptive(
                  value: _useKeyFile,
                  onChanged: _isCreating
                      ? null
                      : (value) => setState(() {
                          _useKeyFile = value;
                          _error = null;
                          if (!value) {
                            _keyFilePath = null;
                          }
                        }),
                  activeThumbColor: _kInk,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Use a Key File',
                    style: TextStyle(fontSize: 16, color: _kInk),
                  ),
                ),
                if (_useKeyFile) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          onPressed: _isCreating ? null : _pickKeyFile,
                          label: 'Select Key File',
                          icon: Icons.folder_open_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionButton(
                          onPressed: _isCreating ? null : _createKeyFile,
                          label: 'Create Key File',
                          icon: Icons.add_rounded,
                        ),
                      ),
                    ],
                  ),
                  if (_keyFilePath != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.key_rounded, size: 18, color: _kInk),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              p.basename(_keyFilePath!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _kInk,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _isCreating
                                ? null
                                : () => setState(() => _keyFilePath = null),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            color: _kMuted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                _SectionLabel(label: 'Database Format'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBorder),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<_DbFormat>(
                      value: _format,
                      isExpanded: true,
                      onChanged: _isCreating
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _format = value);
                              }
                            },
                      items: _DbFormat.values
                          .map(
                            (format) => DropdownMenuItem<_DbFormat>(
                              value: format,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    format.title,
                                    style: const TextStyle(
                                      color: _kInk,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    format.subtitle,
                                    style: const TextStyle(
                                      color: _kMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: canSubmit ? _create : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kInk,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _kMuted,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isCreating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Create Database',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _showSubmitHelp,
                  icon: const Icon(
                    Icons.help_outline_rounded,
                    size: 16,
                    color: _kMuted,
                  ),
                  label: const Text(
                    "Why I can't submit?",
                    style: TextStyle(
                      color: _kMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: _kMuted,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create() async {
    final issues = _validationIssues;
    if (issues.isNotEmpty) {
      setState(() => _error = issues.first);
      return;
    }

    final name = _nameCtrl.text.trim();
    final password = _passwordCtrl.text;

    setState(() {
      _isCreating = true;
      _error = null;
    });

    try {
      Uint8List? keyFileBytes;
      if (_useKeyFile && _keyFilePath != null) {
        keyFileBytes = await File(_keyFilePath!).readAsBytes();
      }

      final added = _isCloud
          ? await _createCloudDatabase(
              name: name,
              password: password,
              keyFileBytes: keyFileBytes,
            )
          : await _createLocalDatabase(
              name: name,
              password: password,
              keyFileBytes: keyFileBytes,
            );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onAdded(added);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCreating = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<DatabaseRecord> _createLocalDatabase({
    required String name,
    required String password,
    required Uint8List? keyFileBytes,
  }) async {
    final storageDirectoryPath = await _localWritableDirectoryPath();
    if (_storageDirectoryPath != storageDirectoryPath) {
      setState(() => _storageDirectoryPath = storageDirectoryPath);
    }

    final safeFilename = '${_safeName(name)}.kdbx';
    final dbPath = p.join(storageDirectoryPath, safeFilename);

    final repo = ref.read(kdbxRepositoryProvider);
    await repo.createDatabase(
      databasePath: dbPath,
      databaseName: name,
      password: _acceptEmpty ? '' : password,
      keyFileBytes: keyFileBytes,
      version: _kdbxVersion(),
    );

    return ref
        .read(databaseRegistryProvider.notifier)
        .addDatabase(
          nickname: name,
          databasePath: dbPath,
          storageType: 'local',
        );
  }

  /// Builds the `.kdbx` locally, uploads it to the chosen cloud folder, caches
  /// the bytes and registers the vault with cloud metadata. Mirrors the import
  /// path in [cloud_browser_page] and the desktop create-database modal.
  Future<DatabaseRecord> _createCloudDatabase({
    required String name,
    required String password,
    required Uint8List? keyFileBytes,
  }) async {
    final target = widget.cloudTarget!;
    final safeName = _safeName(name);
    final fileName = '$safeName.kdbx';

    // 1. Create the database bytes in a temporary file.
    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(
      tempDir.path,
      'lumenpass_create_${DateTime.now().microsecondsSinceEpoch}_$fileName',
    );
    final repo = ref.read(kdbxRepositoryProvider);
    await repo.createDatabase(
      databasePath: tempPath,
      databaseName: name,
      password: _acceptEmpty ? '' : password,
      keyFileBytes: keyFileBytes,
      version: _kdbxVersion(),
    );
    ref.read(vaultWriteSchedulerProvider).reset();
    repo.closeDatabase();

    final bytes = await File(tempPath).readAsBytes();

    // 2. Upload to the selected cloud folder.
    final String storageType;
    String? cloudFileId;
    switch (target.kind) {
      case CloudKind.googleDrive:
        storageType = 'googleDrive';
        final driveFileId = await CloudDatabaseService.instance
            .uploadToGoogleDrive(
              bytes,
              fileName,
              folderId: target.folderId.isEmpty ? null : target.folderId,
            );
        cloudFileId = driveFileId.isNotEmpty ? driveFileId : fileName;
      case CloudKind.dropbox:
        storageType = 'dropbox';
        final folder = target.folderId.trim();
        final normalisedFolder = folder.isEmpty || folder == '/'
            ? ''
            : (folder.endsWith('/')
                  ? folder.substring(0, folder.length - 1)
                  : folder);
        final dropboxPath = normalisedFolder.isEmpty
            ? '/$fileName'
            : '$normalisedFolder/$fileName';
        await CloudDatabaseService.instance.uploadToDropbox(bytes, dropboxPath);
        cloudFileId = dropboxPath.toLowerCase();
      case CloudKind.oneDrive:
        storageType = 'oneDrive';
        final itemId = await CloudDatabaseService.instance
            .uploadNewFileToOneDrive(
              bytes,
              target.folderId.isEmpty ? 'root' : target.folderId,
              fileName,
            );
        cloudFileId = itemId.isNotEmpty ? itemId : fileName;
      case CloudKind.webdav:
        storageType = 'webdav';
        final remotePath = await CloudDatabaseService.instance
            .uploadNewFileToWebDav(bytes, target.folderId, fileName);
        cloudFileId = remotePath.isNotEmpty ? remotePath : fileName;
      case CloudKind.sftp:
        storageType = 'sftp';
        final sftpPath = await CloudDatabaseService.instance
            .uploadNewFileToSftp(bytes, target.folderId, fileName);
        cloudFileId = sftpPath.isNotEmpty ? sftpPath : fileName;
      case CloudKind.s3:
        storageType = 's3';
        final s3Key = await CloudDatabaseService.instance.uploadNewFileToS3(
          bytes,
          target.folderId,
          fileName,
        );
        cloudFileId = s3Key.isNotEmpty ? s3Key : fileName;
    }

    // 3. Cache the bytes at the stable cloud path so the vault opens offline.
    final cachePath = await cloudDatabaseCachePath(
      storageType: storageType,
      cloudFileId: cloudFileId,
      cloudFileName: fileName,
    );
    await Directory(p.dirname(cachePath)).create(recursive: true);
    await File(cachePath).writeAsBytes(bytes, flush: true);

    // Best-effort cleanup of the temporary build file.
    try {
      await File(tempPath).delete();
    } catch (_) {}

    // 4. Register the cloud vault.
    return ref
        .read(databaseRegistryProvider.notifier)
        .addDatabase(
          nickname: name,
          databasePath: cachePath,
          storageType: storageType,
          cloudFileId: cloudFileId,
          cloudFileName: fileName,
        );
  }

  String _safeName(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

class _ValidationHintRow extends StatelessWidget {
  const _ValidationHintRow({
    required this.icon,
    required this.iconColor,
    required this.message,
  });

  final IconData icon;
  final Color iconColor;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: _kInk, fontSize: 13, height: 1.35),
          ),
        ),
      ],
    );
  }
}

// ── Cloud Browser Page ────────────────────────────────────────────────────────

/// Full-screen page for browsing Google Drive or Dropbox to select a .kdbx file.
class _CloudBrowserPage extends ConsumerStatefulWidget {
  const _CloudBrowserPage({required this.cloudType, required this.onAdded});

  final _CloudType cloudType;
  final void Function(DatabaseRecord) onAdded;

  @override
  ConsumerState<_CloudBrowserPage> createState() => _CloudBrowserPageState();
}

class _CloudBrowserPageState extends ConsumerState<_CloudBrowserPage> {
  final List<CloudFolder> _breadcrumb = [];
  final _searchCtrl = TextEditingController();
  List<CloudFolder>? _folders;
  List<CloudFile>? _files;
  bool _loading = true;
  bool _importing = false;
  String? _error;
  String _query = '';

  /// Selected .kdbx in the current (filtered) list; cleared when folder reloads.
  CloudFile? _selectedVault;

  String get _title =>
      widget.cloudType == _CloudType.googleDrive ? 'Google Drive' : 'Dropbox';

  String get _currentPath => _breadcrumb.isEmpty ? '' : _breadcrumb.last.id;

  String get _brandAsset => widget.cloudType == _CloudType.googleDrive
      ? 'assets/images/google-drive.png'
      : 'assets/images/dropbox.png';

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final List<Future<dynamic>> futures;
      if (widget.cloudType == _CloudType.googleDrive) {
        futures = [
          CloudDatabaseService.instance.listGoogleDriveFolders(
            parentId: _breadcrumb.isEmpty ? null : _currentPath,
          ),
          CloudDatabaseService.instance.listGoogleDriveFiles(
            parentId: _breadcrumb.isEmpty ? null : _currentPath,
          ),
        ];
      } else {
        futures = [
          CloudDatabaseService.instance.listDropboxFolders(_currentPath),
          CloudDatabaseService.instance.listDropboxFiles(_currentPath),
        ];
      }

      final results = await Future.wait(futures);
      final folders = results[0] as List<CloudFolder>;
      final allFiles = results[1] as List<CloudFile>;
      final dbFiles = allFiles.where(_isSupportedFile).toList();

      if (mounted) {
        setState(() {
          _folders = folders;
          _files = dbFiles;
          _loading = false;
          _selectedVault = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  static bool _isSupportedFile(CloudFile f) {
    final ext = p.extension(f.name).toLowerCase();
    return ext == '.kdbx' || ext == '.kdb';
  }

  void _navigateInto(CloudFolder folder) {
    final displayPath = _breadcrumb.isEmpty
        ? '/${folder.name}'
        : '${_breadcrumb.last.displayPath}/${folder.name}';
    setState(
      () => _breadcrumb.add(
        CloudFolder(id: folder.id, name: folder.name, path: displayPath),
      ),
    );
    _loadEntries();
  }

  void _navigateUp() {
    setState(() => _breadcrumb.removeLast());
    _loadEntries();
  }

  void _navigateToRoot() {
    setState(() => _breadcrumb.clear());
    _loadEntries();
  }

  void _onVaultRowTap(CloudFile file) {
    setState(() {
      _selectedVault = _selectedVault?.id == file.id ? null : file;
    });
  }

  Future<void> _importSelectedVault() async {
    final file = _selectedVault;
    if (file == null) return;

    final displayPath = _breadcrumb.isEmpty
        ? '/${file.name}'
        : '${_breadcrumb.last.displayPath}/${file.name}';
    final selectedFile = CloudFile(
      id: file.id,
      name: file.name,
      path: displayPath,
    );

    setState(() {
      _importing = true;
      _error = null;
    });

    try {
      final Uint8List bytes = widget.cloudType == _CloudType.googleDrive
          ? await CloudDatabaseService.instance.downloadGoogleDriveFile(
              selectedFile.id,
            )
          : await CloudDatabaseService.instance.downloadDropboxFile(
              selectedFile.id,
            );

      final storageType = widget.cloudType == _CloudType.googleDrive
          ? 'googleDrive'
          : 'dropbox';
      final cachePath = await cloudDatabaseCachePath(
        storageType: storageType,
        cloudFileId: selectedFile.id,
        cloudFileName: selectedFile.name,
      );
      await Directory(p.dirname(cachePath)).create(recursive: true);
      await File(cachePath).writeAsBytes(bytes, flush: true);

      final nickname = p.basenameWithoutExtension(selectedFile.name);
      final registry = ref.read(databaseRegistryProvider.notifier);

      final added = await registry.addDatabase(
        nickname: nickname,
        databasePath: cachePath,
        storageType: storageType,
        cloudFileId: selectedFile.id,
        cloudFileName: selectedFile.name,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onAdded(added);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final folders = _visibleFolders;
    final files = _visibleFiles;

    return Scaffold(
      backgroundColor: _kInk,
      body: Column(
        children: [
          _buildTopPanel(context),
          Expanded(
            child: ColoredBox(
              color: _kBg,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null)
                    _buildErrorState()
                  else
                    _buildList(folders, files),
                  if (_importing)
                    ColoredBox(
                      color: Colors.white.withValues(alpha: 0.72),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
          _CloudBrowserFooter(
            canSelect: _selectedVault != null && !_loading && !_importing,
            cancelEnabled: !_importing,
            onCancel: () => Navigator.of(context).pop(),
            onSelectVault: _importSelectedVault,
          ),
        ],
      ),
    );
  }

  List<CloudFolder> get _visibleFolders {
    final folders = _folders ?? const <CloudFolder>[];
    if (_query.trim().isEmpty) return folders;
    final q = _query.trim().toLowerCase();
    return folders.where((f) => f.name.toLowerCase().contains(q)).toList();
  }

  List<CloudFile> get _visibleFiles {
    final files = _files ?? const <CloudFile>[];
    if (_query.trim().isEmpty) return files;
    final q = _query.trim().toLowerCase();
    return files.where((f) => f.name.toLowerCase().contains(q)).toList();
  }

  Widget _buildTopPanel(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final accountEmail = switch (widget.cloudType) {
      _CloudType.googleDrive =>
        ref.watch(cloudGoogleAccountProvider) ??
            CloudDatabaseService.instance.currentGoogleAccount?.email,
      _CloudType.dropbox => ref.watch(cloudDropboxAccountProvider),
      _CloudType.oneDrive => ref.watch(cloudOneDriveAccountProvider),
      _CloudType.webDav => ref.watch(cloudWebDavAccountProvider),
      _CloudType.sftp => ref.watch(cloudSftpAccountProvider),
      _CloudType.s3 => ref.watch(cloudS3AccountProvider),
    };
    final accountLine = accountEmail != null && accountEmail.isNotEmpty
        ? accountEmail
        : 'Signed in';

    return Container(
      color: _kInk,
      padding: EdgeInsets.fromLTRB(8, topInset + 4, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (_breadcrumb.isNotEmpty) ...[
                _HeaderActionButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: _navigateUp,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: Image.asset(_brandAsset, fit: BoxFit.contain),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                ),
                          ),
                          Text(
                            accountLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 12,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _HeaderActionButton(
                icon: Icons.refresh_rounded,
                onTap: _loading || _importing ? null : _loadEntries,
                filled: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _CloudSearchBar(
            controller: _searchCtrl,
            onChanged: (value) {
              setState(() {
                _query = value;
                final visible = _visibleFiles;
                if (_selectedVault != null &&
                    !visible.any((f) => f.id == _selectedVault!.id)) {
                  _selectedVault = null;
                }
              });
            },
          ),
          if (_breadcrumb.isNotEmpty) ...[
            const SizedBox(height: 8),
            _BreadcrumbBar(
              breadcrumb: _breadcrumb,
              onTapRoot: _navigateToRoot,
              onTapAt: (i) {
                setState(
                  () => _breadcrumb.removeRange(i + 1, _breadcrumb.length),
                );
                _loadEntries();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    final message = _errorMessageForDisplay(_error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size: 34,
                  color: Color(0xFFEF4444),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Unable to load this folder',
                style: TextStyle(
                  color: Color(0xFF0B1F26),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF6B858D),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _loadEntries, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }

  String _errorMessageForDisplay(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return 'Unknown error. Please try again.';
    if (text.contains('DOBJC_initializeApi') ||
        text.contains('objective_c.framework/objective_c')) {
      return 'Google Drive could not load iOS native libraries (stripped symbols). '
          'Rebuild the app with Runner → Build Settings → Strip Style set to '
          'Non-Global Symbols, then run flutter clean and build again. '
          'See: docs.flutter.dev/platform-integration/ios/c-interop';
    }
    return text;
  }

  Widget _buildList(List<CloudFolder> folders, List<CloudFile> files) {
    final hasResults = folders.isNotEmpty || files.isNotEmpty;

    return RefreshIndicator(
      onRefresh: _loadEntries,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          if (!hasResults)
            _EmptyFolderState(hasQuery: _query.trim().isNotEmpty)
          else ...[
            if (folders.isNotEmpty) ...[
              const _CompactListSectionHeader('Folders'),
              for (final folder in folders) ...[
                _FolderTile(folder: folder, onTap: () => _navigateInto(folder)),
                const SizedBox(height: 8),
              ],
            ],
            if (files.isNotEmpty) ...[
              if (folders.isNotEmpty) const SizedBox(height: 8),
              for (final file in files) ...[
                _VaultFileTile(
                  file: file,
                  selected: _selectedVault?.id == file.id,
                  onTap: () => _onVaultRowTap(file),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

class _CloudBrowserFooter extends StatelessWidget {
  const _CloudBrowserFooter({
    required this.canSelect,
    required this.cancelEnabled,
    required this.onCancel,
    required this.onSelectVault,
  });

  final bool canSelect;
  final bool cancelEnabled;
  final VoidCallback onCancel;
  final VoidCallback onSelectVault;

  @override
  Widget build(BuildContext context) {
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
                onPressed: cancelEnabled ? onCancel : null,
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
                onPressed: canSelect ? onSelectVault : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _kInk,
                  disabledBackgroundColor: const Color(
                    0xFF6B858D,
                  ).withValues(alpha: 0.35),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Select Vault'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Breadcrumb Bar ─────────────────────────────────────────────────────────────

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({
    required this.breadcrumb,
    required this.onTapRoot,
    required this.onTapAt,
  });

  final List<CloudFolder> breadcrumb;
  final VoidCallback onTapRoot;
  final void Function(int) onTapAt;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _BreadcrumbChip(label: 'Root', onTap: onTapRoot, active: false),
          for (int i = 0; i < breadcrumb.length; i++) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: Color(0xFF7AACB5),
              ),
            ),
            _BreadcrumbChip(
              label: breadcrumb[i].name,
              onTap: () => onTapAt(i),
              active: i == breadcrumb.length - 1,
            ),
          ],
        ],
      ),
    );
  }
}

class _BreadcrumbChip extends StatelessWidget {
  const _BreadcrumbChip({
    required this.label,
    required this.onTap,
    required this.active,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFFD2E8ED),
            fontSize: 11,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: filled
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: filled ? 0.12 : 0.22),
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _CloudSearchBar extends StatelessWidget {
  const _CloudSearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 18, color: Color(0xFF6E8A93)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                color: Color(0xFF0A3B48),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(
                  color: Color(0xFF6E8A93),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                onChanged('');
              },
              child: const Icon(
                Icons.close_rounded,
                size: 18,
                color: Color(0xFF6E8A93),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompactListSectionHeader extends StatelessWidget {
  const _CompactListSectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: Color(0xFF6B858D),
        ),
      ),
    );
  }
}

class _VaultFileTile extends StatelessWidget {
  const _VaultFileTile({
    required this.file,
    required this.selected,
    required this.onTap,
  });

  final CloudFile file;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFEEF6F8) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _kInk : const Color(0xFFDDE7EC),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFD0E8EE)
                      : const Color(0xFFDCEEF2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.lock_outline_rounded, color: _kInk, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF0B1F26),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: selected ? _kInk : _kMuted.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.folder, required this.onTap});

  final CloudFolder folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4D6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.folder_rounded,
                  color: Color(0xFFE9A100),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0B1F26),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF7A9098)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyFolderState extends StatelessWidget {
  const _EmptyFolderState({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _kBorder),
            ),
            child: Icon(
              hasQuery ? Icons.search_off_rounded : Icons.folder_open_rounded,
              size: 34,
              color: _kMuted.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            hasQuery ? 'No matches in this folder' : 'No vault files here yet',
            style: const TextStyle(
              color: Color(0xFF0B1F26),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasQuery
                ? 'Try a different search term or clear the filter.'
                : 'Browse another folder to find a .kdbx vault.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _kMuted, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// ── Shared small widgets ───────────────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    this.icon,
    this.iconAsset,
    required this.iconBg,
    this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showDivider = false,
  }) : assert(icon != null || iconAsset != null, 'Provide icon or iconAsset'),
       assert(icon == null || iconColor != null);

  final IconData? icon;

  /// Brand image (e.g. Google Drive, Dropbox); takes precedence over [icon].
  final String? iconAsset;
  final Color iconBg;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.45 : 1.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: iconAsset != null
                        ? Image.asset(iconAsset!, width: 24, height: 24)
                        : Icon(icon!, color: iconColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: _kInk,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(color: _kMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: _kMuted),
                ],
              ),
            ),
          ),
          if (showDivider)
            const Padding(
              padding: EdgeInsets.only(left: 78, right: 20),
              child: Divider(height: 1, thickness: 1, color: Color(0xFFE8EEF2)),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: _kInk,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.enabled = true,
    this.suffix,
    this.onChanged,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final bool enabled;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        enabled: enabled,
        onChanged: onChanged,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        style: const TextStyle(
          color: _kInk,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _kMuted, fontSize: 14),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: InputBorder.none,
          suffixIcon: suffix,
        ),
      ),
    );
  }
}

class _CloudDestinationTile extends StatelessWidget {
  const _CloudDestinationTile({required this.target});

  final CloudCreateTarget target;

  (String asset, String label) get _info => switch (target.kind) {
    CloudKind.googleDrive => ('assets/images/google-drive.png', 'Google Drive'),
    CloudKind.dropbox => ('assets/images/dropbox.png', 'Dropbox'),
    CloudKind.oneDrive => ('assets/images/onedrive.png', 'OneDrive'),
    CloudKind.webdav => ('assets/images/webdav.png', 'WebDAV'),
    CloudKind.sftp => ('assets/images/sftp.png', 'SFTP'),
    CloudKind.s3 => ('assets/images/aws-s3-icon.png', 'Amazon S3'),
  };

  @override
  Widget build(BuildContext context) {
    final (asset, label) = _info;
    final folder = target.folderName.isEmpty ? '/ (root)' : target.folderName;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _kBg,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(7),
            child: Image.asset(asset, fit: BoxFit.contain),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _kInk,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Folder: $folder',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kMuted,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageDirectoryPicker extends StatelessWidget {
  const _StorageDirectoryPicker({
    required this.path,
    required this.enabled,
    required this.onTap,
  });

  final String? path;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPath = path != null && path!.isNotEmpty;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder_open_rounded, size: 18, color: _kMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasPath ? path! : 'Choose destination folder',
                  maxLines: hasPath ? 4 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasPath ? _kInk : _kMuted,
                    fontSize: hasPath ? 12 : 14,
                    fontWeight: FontWeight.w500,
                    height: hasPath ? 1.25 : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: _kMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.onPressed,
    required this.label,
    this.icon,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorder),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 18,
                  color: onPressed == null ? _kMuted : _kInk,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: onPressed == null ? _kMuted : _kInk,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Color(0xFFEF4444)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(
              Icons.close_rounded,
              size: 14,
              color: Color(0xFFEF4444),
            ),
          ),
        ],
      ),
    );
  }
}
