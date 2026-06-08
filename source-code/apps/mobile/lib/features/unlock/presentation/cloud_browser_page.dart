import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/cloud_database_service.dart';
import '../../../core/services/cloud_vault_cache.dart';
import '../application/database_registry.dart';

/// Which cloud provider to browse.
enum CloudKind { googleDrive, dropbox, oneDrive, webdav, sftp, s3 }

/// Whether the browser selects an existing vault file, or only a destination
/// folder path.
enum CloudBrowserMode { selectVaultFile, selectFolder }

/// Folder selection result. `id` is Drive folderId or Dropbox path; empty means
/// root.
class CloudSelectedFolder {
  const CloudSelectedFolder({required this.id, required this.displayPath});
  final String id;
  final String displayPath;
}

const _kInk = Color(0xFF0A3B48);
const _kBg = Color(0xFFF4F9FA);
const _kMuted = Color(0xFF6B858D);
const _kBorder = Color(0xFFE3EAF0);
const _kDanger = Color(0xFFEF4444);

/// Full-screen page for browsing Google Drive or Dropbox.
///
/// - When [mode] is [CloudBrowserMode.selectVaultFile], the user selects a
///   `.kdbx` file which is downloaded + registered, then [onAdded] is called.
/// - When [mode] is [CloudBrowserMode.selectFolder], the user navigates folders
///   and returns the currently-selected folder via `Navigator.pop`.
class CloudBrowserPage extends ConsumerStatefulWidget {
  const CloudBrowserPage({
    super.key,
    required this.cloudType,
    required this.mode,
    this.onAdded,
  });

  final CloudKind cloudType;
  final CloudBrowserMode mode;

  /// Required for [CloudBrowserMode.selectVaultFile].
  final void Function(DatabaseRecord)? onAdded;

  @override
  ConsumerState<CloudBrowserPage> createState() => _CloudBrowserPageState();
}

class _CloudBrowserPageState extends ConsumerState<CloudBrowserPage> {
  final List<CloudFolder> _breadcrumb = [];
  final _searchCtrl = TextEditingController();
  List<CloudFolder>? _folders;
  List<CloudFile>? _files;
  bool _loading = true;
  bool _importing = false;
  String? _error;
  String _query = '';

  CloudFile? _selectedVault;

  String get _title => switch (widget.cloudType) {
        CloudKind.googleDrive => 'Google Drive',
        CloudKind.dropbox => 'Dropbox',
        CloudKind.oneDrive => 'OneDrive',
        CloudKind.webdav => 'WebDAV',
        CloudKind.sftp => 'SFTP',
        CloudKind.s3 => 'Amazon S3',
      };

  String get _currentPath => _breadcrumb.isEmpty ? '' : _breadcrumb.last.id;

  String get _brandAsset => switch (widget.cloudType) {
        CloudKind.googleDrive => 'assets/images/google-drive.png',
        CloudKind.dropbox => 'assets/images/dropbox.png',
        CloudKind.oneDrive => 'assets/images/onedrive.png',
        CloudKind.webdav => 'assets/images/webdav.png',
        CloudKind.sftp => 'assets/images/sftp.png',
        CloudKind.s3 => 'assets/images/aws-s3-icon.png',
      };

  bool get _folderMode => widget.mode == CloudBrowserMode.selectFolder;

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
      if (widget.cloudType == CloudKind.googleDrive) {
        futures = [
          CloudDatabaseService.instance.listGoogleDriveFolders(
            parentId: _breadcrumb.isEmpty ? null : _currentPath,
          ),
          if (_folderMode)
            Future.value(const <CloudFile>[])
          else
            CloudDatabaseService.instance.listGoogleDriveFiles(
              parentId: _breadcrumb.isEmpty ? null : _currentPath,
            ),
        ];
      } else if (widget.cloudType == CloudKind.oneDrive) {
        futures = [
          CloudDatabaseService.instance.listOneDriveFolders(
            parentId: _breadcrumb.isEmpty ? null : _currentPath,
          ),
          if (_folderMode)
            Future.value(const <CloudFile>[])
          else
            CloudDatabaseService.instance.listOneDriveFiles(
              parentId: _breadcrumb.isEmpty ? null : _currentPath,
            ),
        ];
      } else if (widget.cloudType == CloudKind.webdav) {
        futures = [
          CloudDatabaseService.instance.listWebDavFolders(
            parentId: _breadcrumb.isEmpty ? null : _currentPath,
          ),
          if (_folderMode)
            Future.value(const <CloudFile>[])
          else
            CloudDatabaseService.instance.listWebDavFiles(
              parentId: _breadcrumb.isEmpty ? null : _currentPath,
            ),
        ];
      } else if (widget.cloudType == CloudKind.sftp) {
        futures = [
          CloudDatabaseService.instance.listSftpFolders(
            parentId: _breadcrumb.isEmpty ? null : _currentPath,
          ),
          if (_folderMode)
            Future.value(const <CloudFile>[])
          else
            CloudDatabaseService.instance.listSftpFiles(
              parentId: _breadcrumb.isEmpty ? null : _currentPath,
            ),
        ];
      } else if (widget.cloudType == CloudKind.s3) {
        futures = [
          CloudDatabaseService.instance.listS3Folders(
            parentId: _breadcrumb.isEmpty ? null : _currentPath,
          ),
          if (_folderMode)
            Future.value(const <CloudFile>[])
          else
            CloudDatabaseService.instance.listS3Files(
              parentId: _breadcrumb.isEmpty ? null : _currentPath,
            ),
        ];
      } else {
        futures = [
          CloudDatabaseService.instance.listDropboxFolders(_currentPath),
          if (_folderMode)
            Future.value(const <CloudFile>[])
          else
            CloudDatabaseService.instance.listDropboxFiles(_currentPath),
        ];
      }

      final results = await Future.wait(futures);
      final folders = results[0] as List<CloudFolder>;
      final allFiles = results[1] as List<CloudFile>;
      final dbFiles = allFiles.where(_isSupportedFile).toList();

      if (!mounted) return;
      setState(() {
        _folders = folders;
        _files = dbFiles;
        _loading = false;
        _selectedVault = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
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
    final onAdded = widget.onAdded;
    if (onAdded == null) return;

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
      final Uint8List bytes;
      final String storageType;
      switch (widget.cloudType) {
        case CloudKind.googleDrive:
          bytes = await CloudDatabaseService.instance.downloadGoogleDriveFile(
            selectedFile.id,
          );
          storageType = 'googleDrive';
        case CloudKind.dropbox:
          bytes = await CloudDatabaseService.instance.downloadDropboxFile(
            selectedFile.id,
          );
          storageType = 'dropbox';
        case CloudKind.oneDrive:
          bytes = await CloudDatabaseService.instance.downloadOneDriveFile(
            selectedFile.id,
          );
          storageType = 'oneDrive';
        case CloudKind.webdav:
          bytes = await CloudDatabaseService.instance.downloadWebDavFile(
            selectedFile.id,
          );
          storageType = 'webdav';
        case CloudKind.sftp:
          bytes = await CloudDatabaseService.instance.downloadSftpFile(
            selectedFile.id,
          );
          storageType = 'sftp';
        case CloudKind.s3:
          bytes = await CloudDatabaseService.instance.downloadS3File(
            selectedFile.id,
          );
          storageType = 's3';
      }
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
      onAdded(added);
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

    final canSelect = _folderMode
        ? !_loading && !_importing
        : _selectedVault != null && !_loading && !_importing;

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
            canSelect: canSelect,
            cancelEnabled: !_importing,
            onCancel: () => Navigator.of(context).pop(),
            onSelect: _folderMode ? _selectCurrentFolder : _importSelectedVault,
            selectLabel: _folderMode ? 'Select Path' : 'Select Vault',
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
    if (_folderMode) return const <CloudFile>[];
    final files = _files ?? const <CloudFile>[];
    if (_query.trim().isEmpty) return files;
    final q = _query.trim().toLowerCase();
    return files.where((f) => f.name.toLowerCase().contains(q)).toList();
  }

  void _selectCurrentFolder() {
    final selected = _breadcrumb.isEmpty
        ? const CloudSelectedFolder(id: '', displayPath: '/ (root)')
        : CloudSelectedFolder(
            id: _breadcrumb.last.id,
            displayPath: _breadcrumb.last.displayPath,
          );
    Navigator.of(context).pop(selected);
  }

  Widget _buildTopPanel(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final accountEmail = switch (widget.cloudType) {
      CloudKind.googleDrive =>
        ref.watch(cloudGoogleAccountProvider) ??
            CloudDatabaseService.instance.currentGoogleAccount?.email,
      CloudKind.dropbox => ref.watch(cloudDropboxAccountProvider),
      CloudKind.oneDrive => ref.watch(cloudOneDriveAccountProvider),
      CloudKind.webdav => ref.watch(cloudWebDavAccountProvider),
      CloudKind.sftp => ref.watch(cloudSftpAccountProvider),
      CloudKind.s3 => ref.watch(cloudS3AccountProvider),
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
                if (_folderMode) return;
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
                setState(() => _breadcrumb.removeRange(i + 1, _breadcrumb.length));
                _loadEntries();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: _kDanger, size: 30),
            const SizedBox(height: 10),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kDanger, fontSize: 13),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _loadEntries,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<CloudFolder> folders, List<CloudFile> files) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      children: [
        if (folders.isNotEmpty) ...[
          Text(
            'FOLDERS',
            style: TextStyle(
              color: _kMuted.withValues(alpha: 0.9),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          ...folders.map(
            (f) => _FolderRow(
              name: f.name,
              onTap: () => _navigateInto(f),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (!_folderMode && files.isNotEmpty) ...[
          Text(
            'VAULT FILES',
            style: TextStyle(
              color: _kMuted.withValues(alpha: 0.9),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          ...files.map((f) {
            final selected = _selectedVault?.id == f.id;
            return _FileRow(
              name: f.name,
              selected: selected,
              onTap: () => _onVaultRowTap(f),
            );
          }),
        ],
        if (folders.isEmpty && (_folderMode || files.isEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Center(
              child: Text(
                _folderMode
                    ? 'No subfolders here.\nUse "Select Path" to choose this level.'
                    : 'No supported vaults found here.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kMuted, fontSize: 13, height: 1.4),
              ),
            ),
          ),
      ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: filled ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.16),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 20),
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
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search',
        prefixIcon: const Icon(Icons.search, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _kBorder),
        ),
      ),
    );
  }
}

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({
    required this.breadcrumb,
    required this.onTapRoot,
    required this.onTapAt,
  });

  final List<CloudFolder> breadcrumb;
  final VoidCallback onTapRoot;
  final ValueChanged<int> onTapAt;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          GestureDetector(
            onTap: onTapRoot,
            child: Text(
              'Root',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          for (int i = 0; i < breadcrumb.length; i++) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.chevron_right, size: 14, color: Colors.white54),
            ),
            GestureDetector(
              onTap: () => onTapAt(i),
              child: Text(
                breadcrumb[i].name,
                style: TextStyle(
                  color: i == breadcrumb.length - 1
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.82),
                  fontWeight:
                      i == breadcrumb.length - 1 ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.name, required this.onTap});
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _kBg,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.folder_rounded, color: _kInk),
        ),
        title: Text(
          name,
          style: const TextStyle(
            color: _kInk,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: _kMuted),
        onTap: onTap,
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? _kInk : _kBorder, width: selected ? 2 : 1),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _kBg,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.lock_outline_rounded, color: _kInk),
        ),
        title: Text(
          name,
          style: const TextStyle(
            color: _kInk,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        trailing: Icon(
          selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
          color: selected ? _kInk : _kMuted,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _CloudBrowserFooter extends StatelessWidget {
  const _CloudBrowserFooter({
    required this.canSelect,
    required this.cancelEnabled,
    required this.onCancel,
    required this.onSelect,
    required this.selectLabel,
  });

  final bool canSelect;
  final bool cancelEnabled;
  final VoidCallback onCancel;
  final VoidCallback onSelect;
  final String selectLabel;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black26,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: cancelEnabled ? onCancel : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kInk,
                  side: BorderSide(color: _kBorder),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: canSelect ? onSelect : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _kInk,
                  disabledBackgroundColor: _kMuted.withValues(alpha: 0.35),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(selectLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

