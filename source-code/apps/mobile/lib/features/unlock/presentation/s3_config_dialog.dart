import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/cloud_database_service.dart';
import '../../../core/services/s3_regions.dart';
import '../../../core/services/s3_service.dart';

const _kInk = Color(0xFF0A3B48);
const _kBg = Color(0xFFF4F9FA);
const _kMuted = Color(0xFF6B858D);
const _kBorder = Color(0xFFE3EAF0);
const _kDanger = Color(0xFFEF4444);
const _kSuccess = Color(0xFF15803D);

/// Full-screen page that collects AWS S3 credentials and bucket information.
///
/// Flow mirrors the WebDAV / SFTP config pages:
///   1. Fill access key / secret key / region / bucket → tap **Test**.
///   2. On success the Path field unlocks; tap **Browse** to pick a prefix.
///   3. **Connect** runs a writability probe on the chosen path, then persists
///      the credentials. Pops with the connected account label.
class S3ConfigDialog extends ConsumerStatefulWidget {
  const S3ConfigDialog({super.key, this.initialConfig});

  /// Pre-fills the form when reconnecting an existing configuration.
  final S3Config? initialConfig;

  @override
  ConsumerState<S3ConfigDialog> createState() => _S3ConfigDialogState();
}

class _S3ConfigDialogState extends ConsumerState<S3ConfigDialog> {
  late final TextEditingController _accessKeyController;
  late final TextEditingController _secretKeyController;
  late final TextEditingController _bucketController;
  late final TextEditingController _pathController;

  String? _selectedRegion;
  bool _obscureSecret = true;
  bool _busy = false;
  String? _message;
  bool _messageOk = false;
  bool _connectionVerified = false;
  Map<String, String> _fieldErrors = const <String, String>{};

  @override
  void initState() {
    super.initState();
    final cfg = widget.initialConfig;
    _accessKeyController = TextEditingController(text: cfg?.accessKey ?? '');
    _secretKeyController = TextEditingController(text: cfg?.secretKey ?? '');
    _bucketController = TextEditingController(text: cfg?.bucketId ?? '');
    _pathController = TextEditingController(text: cfg?.rootPath ?? '');
    _selectedRegion = cfg?.region;
    _connectionVerified = cfg != null && cfg.isValid;
  }

  @override
  void dispose() {
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _bucketController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  bool get _hasPath => _pathController.text.trim().isNotEmpty;

  S3Config _buildConfig() {
    return S3Config(
      accessKey: _accessKeyController.text.trim(),
      secretKey: _secretKeyController.text.trim(),
      region: _selectedRegion ?? '',
      bucketId: _bucketController.text.trim(),
      rootPath: _pathController.text.trim(),
    );
  }

  void _invalidateConnection() {
    if (_connectionVerified) {
      setState(() => _connectionVerified = false);
    }
    setState(() {
      _message = null;
      _messageOk = false;
    });
  }

  bool _validateConnectionFields() {
    final errors = <String, String>{};
    if (_accessKeyController.text.trim().isEmpty) {
      errors['accessKey'] = 'Access Key ID is required.';
    }
    if (_secretKeyController.text.trim().isEmpty) {
      errors['secretKey'] = 'Secret Access Key is required.';
    }
    if (_selectedRegion == null || _selectedRegion!.isEmpty) {
      errors['region'] = 'Please select a region.';
    }
    if (_bucketController.text.trim().isEmpty) {
      errors['bucket'] = 'Bucket name is required.';
    }
    setState(() => _fieldErrors = errors);
    return errors.isEmpty;
  }

  Future<void> _test() async {
    if (!_validateConnectionFields()) return;
    setState(() {
      _busy = true;
      _message = null;
      _messageOk = false;
    });
    try {
      S3Service.instance.configure(_buildConfig());
      await S3Service.instance.listObjects(maxKeys: 1);
      if (!mounted) return;
      setState(() {
        _messageOk = true;
        _connectionVerified = true;
        _message = 'Connection successful. Choose a path with Browse.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messageOk = false;
        _connectionVerified = false;
        _message = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _browsePath() async {
    if (!_connectionVerified) return;
    final selected = await Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        builder: (_) => _S3PrefixBrowserPage(
          initialPath: _pathController.text.trim(),
        ),
        fullscreenDialog: true,
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _pathController.text = selected;
        _fieldErrors = Map<String, String>.from(_fieldErrors)
          ..remove('rootPath');
      });
    }
  }

  Future<void> _connect() async {
    if (!_connectionVerified) {
      setState(() {
        _messageOk = false;
        _message = 'Test the connection before connecting.';
      });
      return;
    }
    if (!_hasPath) {
      setState(() {
        _messageOk = false;
        _message = 'Choose a path with Browse before connecting.';
      });
      return;
    }
    final config = _buildConfig();
    if (!config.isValid) {
      setState(() => _fieldErrors = const {
            'accessKey': 'Fill in all required fields.',
          });
      return;
    }
    setState(() {
      _busy = true;
      _messageOk = false;
      _message = 'Verifying the selected path is writable…';
    });
    try {
      await S3Service.instance.verifyWritable(config.rootPath);
      await CloudDatabaseService.instance.connectS3(config);
      if (!mounted) return;
      Navigator.of(context).pop(
        ref.read(cloudS3AccountProvider) ??
            's3://${config.bucketId}${config.rootPath.isNotEmpty ? '/${config.rootPath}' : ''}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messageOk = false;
        _message = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kInk,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Connect to Amazon S3',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: <Widget>[
            Text(
              'Enter your AWS credentials and bucket information.',
              style: TextStyle(color: _kMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _field(
              label: 'Access Key ID',
              controller: _accessKeyController,
              hint: 'AKIAIOSFODNN7EXAMPLE',
              errorKey: 'accessKey',
              icon: Icons.vpn_key_rounded,
              invalidatesConnection: true,
            ),
            const SizedBox(height: 14),
            _field(
              label: 'Secret Access Key',
              controller: _secretKeyController,
              hint: 'Your AWS secret key',
              errorKey: 'secretKey',
              icon: Icons.lock_outline_rounded,
              obscure: _obscureSecret,
              invalidatesConnection: true,
              suffix: IconButton(
                icon: Icon(
                  _obscureSecret
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: _kMuted,
                ),
                onPressed: () =>
                    setState(() => _obscureSecret = !_obscureSecret),
              ),
            ),
            const SizedBox(height: 14),
            _buildRegionField(),
            const SizedBox(height: 14),
            _field(
              label: 'Bucket Name',
              controller: _bucketController,
              hint: 'my-lumenpass-backups',
              errorKey: 'bucket',
              icon: Icons.storage_rounded,
              invalidatesConnection: true,
            ),
            const SizedBox(height: 14),
            _buildPathField(),
            if (_message != null) ...<Widget>[
              const SizedBox(height: 16),
              _buildMessage(),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _busy ? null : _test,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering_rounded, size: 18),
              label: const Text('Test Connection'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kInk,
                side: BorderSide(color: _kBorder),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: (_busy || !_connectionVerified || !_hasPath)
                  ? null
                  : _connect,
              style: FilledButton.styleFrom(
                backgroundColor: _kInk,
                disabledBackgroundColor: _kMuted.withValues(alpha: 0.35),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegionField() {
    final error = _fieldErrors['region'];
    final hasSelection = _selectedRegion != null &&
        kAwsRegions.any((r) => r.code == _selectedRegion);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'AWS Region',
          style: TextStyle(
            color: _kInk,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          isExpanded: true,
          menuMaxHeight: 320,
          decoration: InputDecoration(
            hintText: 'Select a region',
            hintStyle: TextStyle(color: _kMuted.withValues(alpha: 0.8)),
            prefixIcon:
                const Icon(Icons.public_rounded, size: 20, color: _kMuted),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: error != null ? _kDanger : _kBorder,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: error != null ? _kDanger : _kBorder,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: error != null ? _kDanger : _kInk,
                width: 1.5,
              ),
            ),
          ),
          value: hasSelection ? _selectedRegion : null,
          items: kAwsRegions
              .map((r) => DropdownMenuItem<String>(
                    value: r.code,
                    child: Text(
                      '${r.label} (${r.code})',
                      style: const TextStyle(color: _kInk, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedRegion = value;
              if (_fieldErrors.containsKey('region')) {
                _fieldErrors = Map<String, String>.from(_fieldErrors)
                  ..remove('region');
              }
            });
            _invalidateConnection();
          },
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(error, style: const TextStyle(color: _kDanger, fontSize: 11)),
        ],
      ],
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    required String errorKey,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool enabled = true,
    bool readOnly = false,
    bool invalidatesConnection = false,
  }) {
    final error = _fieldErrors[errorKey];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: enabled ? _kInk : _kMuted,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          readOnly: readOnly,
          obscureText: obscure,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: const TextStyle(color: _kInk, fontSize: 14),
          onChanged: (_) {
            final resetVerification =
                invalidatesConnection && _connectionVerified;
            if (_fieldErrors.containsKey(errorKey) ||
                _message != null ||
                resetVerification) {
              setState(() {
                _fieldErrors = Map<String, String>.from(_fieldErrors)
                  ..remove(errorKey);
                _message = null;
                _messageOk = false;
                if (resetVerification) _connectionVerified = false;
              });
            }
          },
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: _kMuted.withValues(alpha: 0.8)),
            prefixIcon: Icon(icon, size: 20, color: _kMuted),
            suffixIcon: suffix,
            filled: true,
            fillColor: enabled ? Colors.white : const Color(0xFFEFF1F4),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: error != null ? _kDanger : _kBorder,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: error != null ? _kDanger : _kBorder,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: error != null ? _kDanger : _kInk,
                width: 1.5,
              ),
            ),
          ),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(error, style: const TextStyle(color: _kDanger, fontSize: 11)),
        ],
      ],
    );
  }

  Widget _buildPathField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: _field(
                label: 'Path',
                controller: _pathController,
                hint: _connectionVerified ? 'Choose a path with Browse' : '/',
                errorKey: 'rootPath',
                icon: Icons.folder_outlined,
                enabled: _connectionVerified,
                readOnly: true,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _connectionVerified ? _browsePath : null,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Browse'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kInk,
                  disabledForegroundColor: _kMuted.withValues(alpha: 0.5),
                  side: BorderSide(
                    color: _connectionVerified
                        ? _kBorder
                        : _kBorder.withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMessage() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          _messageOk ? Icons.check_circle_outline : Icons.error_outline,
          color: _messageOk ? _kSuccess : _kDanger,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _message!,
            style: TextStyle(
              color: _messageOk ? _kSuccess : _kDanger,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

// ── S3 Prefix Browser ─────────────────────────────────────────────────────────

/// Full-screen page that lets the user browse S3 prefixes ("folders") and
/// select one, or create a new folder. Pops with the selected prefix string.
/// Mirrors the [_WebDavFolderBrowserPage] pattern.
class _S3PrefixBrowserPage extends StatefulWidget {
  const _S3PrefixBrowserPage({required this.initialPath});

  final String initialPath;

  @override
  State<_S3PrefixBrowserPage> createState() => _S3PrefixBrowserPageState();
}

class _S3PrefixBrowserPageState extends State<_S3PrefixBrowserPage> {
  final List<CloudFolder> _breadcrumb = <CloudFolder>[];
  List<CloudFolder>? _folders;
  bool _loading = true;
  bool _creating = false;
  String? _error;

  String get _currentPath =>
      _breadcrumb.isEmpty ? '' : _breadcrumb.last.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final folders = await CloudDatabaseService.instance.listS3Folders(
        parentId: _currentPath.isEmpty ? null : _currentPath,
      );
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _navigateInto(CloudFolder folder) {
    setState(() => _breadcrumb.add(folder));
    _load();
  }

  void _navigateUp() {
    setState(() => _breadcrumb.removeLast());
    _load();
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    setState(() => _creating = true);
    try {
      await S3Service.instance.createPrefix(_currentPath, name);
      if (!mounted) return;
      setState(() {
        _creating = false;
        _breadcrumb.add(CloudFolder(
          id: _currentPath.isEmpty ? '$name/' : '$_currentPath$name/',
          name: name,
          path: _currentPath.isEmpty ? '$name/' : '$_currentPath$name/',
        ));
      });
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final folders = _folders ?? const <CloudFolder>[];
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kInk,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: _breadcrumb.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _loading ? null : _navigateUp,
              ),
        title: Text(
          _breadcrumb.isEmpty ? 'Select S3 Path' : _breadcrumb.last.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'New folder',
            onPressed: (_loading || _creating) ? null : _createFolder,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildBreadcrumb(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildError()
                      : folders.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No subfolders here.\n'
                                  'Use "Select This Folder" to choose this level.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: _kMuted,
                                      fontSize: 13,
                                      height: 1.4),
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 12, 14, 14),
                              itemCount: folders.length,
                              itemBuilder: (_, i) => _folderTile(folders[i]),
                            ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumb() {
    return Container(
      width: double.infinity,
      color: _kInk,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            GestureDetector(
              onTap: () {
                setState(() => _breadcrumb.clear());
                _load();
              },
              child: Text(
                'Root',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            for (int i = 0; i < _breadcrumb.length; i++) ...<Widget>[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.chevron_right,
                    size: 14, color: Colors.white54),
              ),
              GestureDetector(
                onTap: () {
                  setState(() =>
                      _breadcrumb.removeRange(i + 1, _breadcrumb.length));
                  _load();
                },
                child: Text(
                  _breadcrumb[i].name,
                  style: TextStyle(
                    color: i == _breadcrumb.length - 1
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.82),
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

  Widget _folderTile(CloudFolder folder) {
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
          folder.name,
          style: const TextStyle(
            color: _kInk,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        trailing:
            const Icon(Icons.chevron_right_rounded, color: _kMuted),
        onTap: () => _navigateInto(folder),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, color: _kDanger, size: 30),
            const SizedBox(height: 10),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kDanger, fontSize: 13),
            ),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black26,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
        child: Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
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
                onPressed: () =>
                    Navigator.of(context).pop(_currentPath),
                style: FilledButton.styleFrom(
                  backgroundColor: _kInk,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Select This Folder'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
