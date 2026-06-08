import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/cloud_database_service.dart';
import '../../../core/services/webdav_service.dart';

const _kInk = Color(0xFF0A3B48);
const _kBg = Color(0xFFF4F9FA);
const _kMuted = Color(0xFF6B858D);
const _kBorder = Color(0xFFE3EAF0);
const _kDanger = Color(0xFFEF4444);
const _kSuccess = Color(0xFF15803D);

/// Full-screen page that collects WebDAV connection settings (host, port,
/// username, masked password, path) and connects via [CloudDatabaseService].
///
/// Flow mirrors the desktop dialog:
///   1. Fill host/port/username/password → tap **Test** to verify the server.
///   2. On success the Path field unlocks; tap **Browse** to pick a folder.
///   3. **Connect** runs a background read/write probe on the chosen path,
///      then persists the credentials. Pops with the connected account label.
class WebDavConfigPage extends ConsumerStatefulWidget {
  const WebDavConfigPage({super.key, this.initialConfig});

  /// Pre-fills the form when reconnecting an existing configuration.
  final WebDavConfig? initialConfig;

  @override
  ConsumerState<WebDavConfigPage> createState() => _WebDavConfigPageState();
}

class _WebDavConfigPageState extends ConsumerState<WebDavConfigPage> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _pathController;

  bool _obscurePassword = true;
  bool _busy = false;
  String? _message;
  bool _messageOk = false;
  bool _connectionVerified = false;
  Map<String, String> _fieldErrors = const <String, String>{};

  @override
  void initState() {
    super.initState();
    final cfg = widget.initialConfig;
    _hostController = TextEditingController(text: cfg?.host ?? '');
    _portController =
        TextEditingController(text: cfg != null ? cfg.port.toString() : '443');
    _usernameController = TextEditingController(text: cfg?.username ?? '');
    _passwordController = TextEditingController(text: cfg?.password ?? '');
    _pathController = TextEditingController(text: cfg?.rootPath ?? '');
    _connectionVerified = cfg != null;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  bool get _hasPath => _pathController.text.trim().isNotEmpty;

  WebDavConfig _buildConfig() {
    return WebDavConfig(
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? -1,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      rootPath: _pathController.text.trim(),
    );
  }

  bool _validateConnectionFields() {
    final all = WebDavService.validateConfig(_buildConfig()).errors;
    final connErrors = <String, String>{
      for (final key in const <String>['host', 'port', 'username', 'password'])
        if (all.containsKey(key)) key: all[key]!,
    };
    setState(() => _fieldErrors = connErrors);
    return connErrors.isEmpty;
  }

  Future<void> _test() async {
    if (!_validateConnectionFields()) return;
    setState(() {
      _busy = true;
      _message = null;
      _messageOk = false;
    });
    try {
      await CloudDatabaseService.instance.testWebDavConnection(
        _buildConfig().copyWith(rootPath: '/'),
      );
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
    final config = _buildConfig().copyWith(rootPath: '/');
    final selected = await Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        builder: (_) => _WebDavFolderBrowserPage(
          config: config,
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
    final validation = WebDavService.validateConfig(_buildConfig());
    if (!validation.isValid) {
      setState(() => _fieldErrors = validation.errors);
      return;
    }
    setState(() {
      _busy = true;
      _messageOk = false;
      _message = 'Verifying the selected path is writable…';
    });
    try {
      final config = _buildConfig();
      await CloudDatabaseService.instance.verifyWebDavWritable(config);
      await CloudDatabaseService.instance.connectWebDav(config);
      if (!mounted) return;
      Navigator.of(context).pop(
        ref.read(cloudWebDavAccountProvider) ?? config.accountLabel,
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
          'Connect to WebDAV',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: <Widget>[
            Text(
              'Enter your server details and credentials.',
              style: TextStyle(color: _kMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _field(
              label: 'Server Host',
              controller: _hostController,
              hint: 'dav.example.com or https://example.com/dav',
              errorKey: 'host',
              icon: Icons.dns_rounded,
              invalidatesConnection: true,
            ),
            const SizedBox(height: 14),
            _field(
              label: 'Port',
              controller: _portController,
              hint: '443',
              errorKey: 'port',
              icon: Icons.power_rounded,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              invalidatesConnection: true,
            ),
            const SizedBox(height: 14),
            _field(
              label: 'Username',
              controller: _usernameController,
              hint: 'Your WebDAV user name',
              errorKey: 'username',
              icon: Icons.person_outline_rounded,
              invalidatesConnection: true,
            ),
            const SizedBox(height: 14),
            _field(
              label: 'Password',
              controller: _passwordController,
              hint: 'Your WebDAV password',
              errorKey: 'password',
              icon: Icons.lock_outline_rounded,
              obscure: _obscurePassword,
              invalidatesConnection: true,
              suffix: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: _kMuted,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
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
                onPressed: (_connectionVerified && !_busy) ? _browsePath : null,
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text('Browse'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kInk,
                  disabledForegroundColor: _kMuted,
                  side: BorderSide(color: _kBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (!_connectionVerified) ...<Widget>[
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              const Icon(Icons.lock_outline_rounded, size: 13, color: _kMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Test the connection to choose a path.',
                  style: TextStyle(color: _kMuted, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMessage() {
    final inProgress = _busy;
    final color = inProgress
        ? _kInk
        : (_messageOk ? _kSuccess : _kDanger);
    final bg = inProgress
        ? const Color(0xFFEFF3FF)
        : (_messageOk ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          if (inProgress)
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(
              _messageOk
                  ? Icons.check_circle_outline_rounded
                  : Icons.error_outline_rounded,
              size: 16,
              color: color,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_message!, style: TextStyle(color: color, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// Full-screen folder browser used to pick the WebDAV path, mirroring the
/// shape of [CloudBrowserPage] but driven by an explicit, not-yet-saved config.
class _WebDavFolderBrowserPage extends StatefulWidget {
  const _WebDavFolderBrowserPage({
    required this.config,
    required this.initialPath,
  });

  final WebDavConfig config;
  final String initialPath;

  @override
  State<_WebDavFolderBrowserPage> createState() =>
      _WebDavFolderBrowserPageState();
}

class _WebDavFolderBrowserPageState extends State<_WebDavFolderBrowserPage> {
  final List<CloudFolder> _breadcrumb = <CloudFolder>[];
  List<CloudFolder>? _folders;
  bool _loading = true;
  bool _creating = false;
  String? _error;

  String get _currentPath => _breadcrumb.isEmpty ? '/' : _breadcrumb.last.id;

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
      final folders = await CloudDatabaseService.instance.browseWebDavFolders(
        widget.config,
        parentId: _currentPath,
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
      final created = await CloudDatabaseService.instance.createWebDavFolderIn(
        widget.config,
        name,
        parentId: _currentPath,
      );
      if (!mounted) return;
      // Navigate into the freshly-created folder.
      setState(() {
        _creating = false;
        _breadcrumb.add(created);
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
          _breadcrumb.isEmpty ? 'Select Folder' : _breadcrumb.last.name,
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
                                      color: _kMuted, fontSize: 13, height: 1.4),
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
                child: Icon(Icons.chevron_right, size: 14, color: Colors.white54),
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
                        ? FontWeight.w700
                        : FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
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
        trailing: const Icon(Icons.chevron_right_rounded, color: _kMuted),
        onTap: () => _navigateInto(folder),
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
                onPressed: _loading
                    ? null
                    : () => Navigator.of(context).pop(_currentPath),
                style: FilledButton.styleFrom(
                  backgroundColor: _kInk,
                  disabledBackgroundColor: _kMuted.withValues(alpha: 0.35),
                  foregroundColor: Colors.white,
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
