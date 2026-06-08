import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../core/services/backup_service.dart';
import '../../../core/services/subscription_gate_service.dart';
import '../../../core/services/webdav_service.dart';
import '../../../presentation/theme/app_theme.dart';

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

/// Modal form that collects WebDAV connection settings (host, port, username,
/// masked password, root path) and connects via [BackupService]. Pops with
/// the connected account label (`String`) on success, or `null` on cancel.
///
/// Reused by both the create- and open-database modals so the field layout,
/// validation, and "Test connection" behaviour stay consistent.
class WebDavConfigDialog extends StatefulWidget {
  const WebDavConfigDialog({super.key, this.initialConfig});

  /// Pre-fills the form when editing/reconnecting an existing configuration.
  final WebDavConfig? initialConfig;

  @override
  State<WebDavConfigDialog> createState() => _WebDavConfigDialogState();
}

class _WebDavConfigDialogState extends State<WebDavConfigDialog> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _rootPathController;

  bool _obscurePassword = true;
  bool _busy = false;
  String? _testMessage;
  bool _testOk = false;

  /// Whether the host/port/credentials have been verified via "Test". The Root
  /// Path field and the Connect button stay locked until this is true so the
  /// user can only target a folder on a server we know is reachable.
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
    // The path is never typed — it is filled only by the Browse picker.
    _rootPathController = TextEditingController(text: cfg?.rootPath ?? '');
    // An existing configuration was already validated when first saved, so let
    // the user keep its path / reconnect without re-testing first.
    _connectionVerified = cfg != null;
  }

  /// True once the user has chosen a path via Browse (or one was pre-filled
  /// from an existing configuration).
  bool get _hasPath => _rootPathController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _rootPathController.dispose();
    super.dispose();
  }

  WebDavConfig _buildConfig() {
    return WebDavConfig(
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? -1,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      rootPath: _rootPathController.text.trim(),
    );
  }

  /// Validates only the connection-identifying fields (host/port/username/
  /// password). Root Path is excluded because it stays locked until the
  /// connection is verified.
  bool _validateConnectionFields() {
    final all = WebDavService.validateConfig(_buildConfig()).errors;
    final connErrors = <String, String>{
      for (final key in const <String>['host', 'port', 'username', 'password'])
        if (all.containsKey(key)) key: all[key]!,
    };
    setState(() => _fieldErrors = connErrors);
    return connErrors.isEmpty;
  }

  bool _validate() {
    final validation = WebDavService.validateConfig(_buildConfig());
    setState(() => _fieldErrors = validation.errors);
    return validation.isValid;
  }

  Future<void> _test() async {
    if (!_validateConnectionFields()) return;
    setState(() {
      _busy = true;
      _testMessage = null;
      _testOk = false;
    });
    try {
      // Verify host/port/credentials against the server root — the Root Path
      // field is still locked at this point, so test against '/'.
      await BackupService.instance.testWebDavConnection(
        _buildConfig().copyWith(rootPath: '/'),
      );
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _connectionVerified = true;
        _testMessage = 'Connection successful. Choose a path with Browse.';
      });
    } on CloudAccessDeniedException catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _connectionVerified = false;
        _testMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _connectionVerified = false;
        _testMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    if (!_connectionVerified) {
      setState(() {
        _testOk = false;
        _testMessage = 'Test the connection before connecting.';
      });
      return;
    }
    if (!_hasPath) {
      setState(() {
        _testOk = false;
        _testMessage = 'Choose a path with Browse before connecting.';
      });
      return;
    }
    if (!_validate()) return;
    setState(() {
      _busy = true;
      _testOk = false;
      _testMessage = 'Verifying the selected path is writable…';
    });
    try {
      final config = _buildConfig();
      // Confirm the chosen path is a real read/write destination before we
      // persist anything: write a probe file, read it back, then delete it.
      await BackupService.instance.verifyWebDavWritable(config);
      await BackupService.instance.connectWebDav(config);
      if (!mounted) return;
      Navigator.of(context)
          .pop(BackupService.instance.currentWebDavAccount ?? 'Connected');
    } on CloudAccessDeniedException catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  /// Opens the GUI folder picker so the user can navigate the server and pick
  /// (or create) the root path. Only available once the connection is verified.
  Future<void> _browseRootPath() async {
    if (!_connectionVerified) return;
    final config = _buildConfig().copyWith(rootPath: '/');
    final selected = await showDialog<String?>(
      context: context,
      builder: (_) => _WebDavFolderPickerDialog(
        config: config,
        initialPath: _rootPathController.text.trim(),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _rootPathController.text = selected;
        _fieldErrors = Map<String, String>.from(_fieldErrors)
          ..remove('rootPath');
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
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildHeader(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _field(
                        label: 'Server Host',
                        controller: _hostController,
                        hint: 'dav.example.com or https://example.com/dav',
                        errorKey: 'host',
                        icon: TablerIcons.server,
                        invalidatesConnection: true,
                      ),
                      const SizedBox(height: 10),
                      _field(
                        label: 'Port',
                        controller: _portController,
                        hint: '443',
                        errorKey: 'port',
                        icon: TablerIcons.plug,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        invalidatesConnection: true,
                      ),
                      const SizedBox(height: 10),
                      _field(
                        label: 'Username',
                        controller: _usernameController,
                        hint: 'Your WebDAV user name',
                        errorKey: 'username',
                        icon: TablerIcons.user,
                        invalidatesConnection: true,
                      ),
                      const SizedBox(height: 10),
                      _field(
                        label: 'Password',
                        controller: _passwordController,
                        hint: 'Your WebDAV password',
                        errorKey: 'password',
                        icon: TablerIcons.lock,
                        obscure: _obscurePassword,
                        invalidatesConnection: true,
                        suffix: IconButton(
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          icon: Icon(
                            _obscurePassword
                                ? TablerIcons.eye
                                : TablerIcons.eye_off,
                            size: 15,
                            color: _kIcon,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Path',
                        style: _uText(
                          12,
                          _connectionVerified ? _kTitle : _kIcon,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: _field(
                              label: null,
                              controller: _rootPathController,
                              hint: _connectionVerified
                                  ? 'Choose a path with Browse'
                                  : '/',
                              errorKey: 'rootPath',
                              icon: TablerIcons.folder,
                              enabled: _connectionVerified,
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _BrowseButton(
                            enabled: _connectionVerified && !_busy,
                            onPressed: _browseRootPath,
                          ),
                        ],
                      ),
                      if (!_connectionVerified) ...<Widget>[
                        const SizedBox(height: 6),
                        Row(
                          children: <Widget>[
                            const Icon(TablerIcons.lock,
                                size: 12, color: _kIcon),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Test the connection to choose a path.',
                                style: _uText(10, _kLabel),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_testMessage != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _buildTestResult(),
                      ],
                      const SizedBox(height: 6),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorderSoft)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF3F8),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                Image.asset('assets/images/webdav.png', width: 16, height: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Connect to WebDAV',
                  style: _uText(14, _kTitle, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Enter your server details and credentials.',
                  style: _uText(11, _kLabel),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _busy ? null : () => Navigator.of(context).pop(),
            child: const Icon(TablerIcons.x, size: 16, color: _kIcon),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required String? label,
    required TextEditingController controller,
    required String hint,
    required String errorKey,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool enabled = true,
    bool invalidatesConnection = false,
    bool readOnly = false,
  }) {
    final error = _fieldErrors[errorKey];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(
            label,
            style: _uText(
              12,
              enabled ? _kTitle : _kIcon,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: controller,
          enabled: enabled,
          readOnly: readOnly,
          obscureText: obscure,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: _uText(13, enabled ? _kTitle : _kIcon),
          onChanged: (_) {
            // Editing a connection-identifying field invalidates a prior test
            // so the user must re-verify before connecting again.
            final resetVerification =
                invalidatesConnection && _connectionVerified;
            if (_fieldErrors.containsKey(errorKey) ||
                _testMessage != null ||
                resetVerification) {
              setState(() {
                _fieldErrors = Map<String, String>.from(_fieldErrors)
                  ..remove(errorKey);
                _testMessage = null;
                _testOk = false;
                if (resetVerification) _connectionVerified = false;
              });
            }
          },
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: _uText(13, _kIcon),
            filled: true,
            fillColor: enabled ? _kCanvas : const Color(0xFFEFF1F5),
            isDense: true,
            prefixIcon: Icon(icon, size: 16, color: _kIcon),
            suffixIcon: suffix,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? const Color(0xFFEF4444) : _kBorderRow,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? const Color(0xFFEF4444) : _kBorderRow,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kBorderRow),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? const Color(0xFFEF4444) : _kBlue,
                width: 1.5,
              ),
            ),
          ),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(error, style: _uText(10, const Color(0xFFEF4444))),
        ],
      ],
    );
  }

  Widget _buildTestResult() {
    // While busy we show a neutral "in progress" style; otherwise green for
    // success and red for an error.
    final bool inProgress = _busy;
    final Color color = inProgress
        ? _kBlue
        : (_testOk ? const Color(0xFF15803D) : const Color(0xFFEF4444));
    final Color bg = inProgress
        ? const Color(0xFFEEF3FF)
        : (_testOk ? const Color(0xFFEFFDF3) : const Color(0xFFFEF2F2));
    final Color border = inProgress
        ? const Color(0xFFB5C3F8)
        : (_testOk ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        children: <Widget>[
          if (inProgress)
            SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(
              _testOk ? TablerIcons.circle_check : TablerIcons.alert_circle,
              size: 14,
              color: color,
            ),
          const SizedBox(width: 8),
          Expanded(child: Text(_testMessage!, style: _uText(11, color))),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kBorderSoft)),
      ),
      child: Row(
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: _busy ? null : _test,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(TablerIcons.plug_connected, size: 15),
            label: const Text('Test'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF374151),
              side: const BorderSide(color: Color(0xFFD1D5DB)),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              minimumSize: const Size(0, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: _uText(12, const Color(0xFF374151),
                  fontWeight: FontWeight.w600),
            ),
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kLabel,
              side: const BorderSide(color: _kBorderSoft),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              minimumSize: const Size(0, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: _uText(12, _kLabel, fontWeight: FontWeight.w600),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: (_busy || !_connectionVerified || !_hasPath)
                ? null
                : _connect,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFB9C6FF),
              disabledForegroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
              minimumSize: const Size(0, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: _uText(12, Colors.white, fontWeight: FontWeight.w600),
            ),
            child: _busy
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

/// Compact "Browse" button shown beside the Root Path field.
class _BrowseButton extends StatelessWidget {
  const _BrowseButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: const Icon(TablerIcons.folder_search, size: 15),
        label: const Text('Browse'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF374151),
          disabledForegroundColor: _kIcon,
          side: BorderSide(
            color: enabled ? const Color(0xFFD1D5DB) : _kBorderRow,
          ),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          minimumSize: const Size(0, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: _uText(12, const Color(0xFF374151),
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// GUI folder picker for WebDAV, mirroring the Google Drive / OneDrive folder
/// pickers. Navigates the server tree (rooted at `/`) using an explicit,
/// not-yet-saved [config]; pops with the chosen server-relative path.
class _WebDavFolderPickerDialog extends StatefulWidget {
  const _WebDavFolderPickerDialog({
    required this.config,
    required this.initialPath,
  });

  final WebDavConfig config;
  final String initialPath;

  @override
  State<_WebDavFolderPickerDialog> createState() =>
      _WebDavFolderPickerDialogState();
}

class _WebDavFolderPickerDialogState extends State<_WebDavFolderPickerDialog> {
  final List<CloudFolder> _breadcrumb = <CloudFolder>[];
  List<CloudFolder>? _folders;
  String? _error;
  bool _loading = true;

  final _newFolderController = TextEditingController();
  bool _showNewFolder = false;
  bool _creatingFolder = false;

  String get _currentPath =>
      _breadcrumb.isEmpty ? '/' : _breadcrumb.last.id;

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
      final folders = await BackupService.instance.browseWebDavFolders(
        widget.config,
        parentId: _breadcrumb.isEmpty ? '/' : _breadcrumb.last.id,
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

  Future<void> _createFolder() async {
    final folderName = _newFolderController.text.trim();
    if (folderName.isEmpty) return;
    setState(() => _creatingFolder = true);
    try {
      final created = await BackupService.instance.createWebDavFolderIn(
        widget.config,
        folderName,
        parentId: _breadcrumb.isEmpty ? '/' : _breadcrumb.last.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop(created.id);
    } catch (e) {
      if (!mounted) return;
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
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
            Image.asset('assets/images/webdav.png', width: 16, height: 16),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              _breadcrumb.isEmpty ? 'Select WebDAV Folder' : _breadcrumb.last.name,
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
    final folders = _folders ?? const <CloudFolder>[];
    if (folders.isEmpty) {
      return Center(
        child: Text('No sub-folders here.', style: _uText(12, _kLabel)),
      );
    }
    return ListView.builder(
      itemCount: folders.length,
      itemBuilder: (_, i) => _WebDavFolderTile(
        folder: folders[i],
        onNavigate: () {
          setState(() => _breadcrumb.add(folders[i]));
          _loadFolders();
        },
      ),
    );
  }

  Widget _buildNewFolderInput() {
    final bool canCreate =
        !_creatingFolder && _newFolderController.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFF),
        border: Border(top: BorderSide(color: _kBorderSoft)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _newFolderController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (canCreate) _createFolder();
              },
              style: _uText(12, _kTitle, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'New folder name',
                hintStyle: _uText(12, _kIcon),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorderRow),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBlue, width: 1.4),
                ),
                prefixIcon:
                    const Icon(TablerIcons.folder_plus, size: 16, color: _kIcon),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 40, minHeight: 38),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: canCreate ? _createFolder : null,
              icon: _creatingFolder
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
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
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                textStyle: _uText(12, Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
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
            onPressed: () => Navigator.of(context).pop(_currentPath),
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

class _WebDavFolderTile extends StatefulWidget {
  const _WebDavFolderTile({required this.folder, required this.onNavigate});

  final CloudFolder folder;
  final VoidCallback onNavigate;

  @override
  State<_WebDavFolderTile> createState() => _WebDavFolderTileState();
}

class _WebDavFolderTileState extends State<_WebDavFolderTile> {
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
              Icon(TablerIcons.folder,
                  size: 15, color: _hovered ? _kBlue : _kIcon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.folder.name,
                  style: _uText(12, _hovered ? _kBlue : _kTitle,
                      fontWeight: FontWeight.w500),
                ),
              ),
              Icon(TablerIcons.chevron_right,
                  size: 14, color: _hovered ? _kBlue : _kIcon),
            ],
          ),
        ),
      ),
    );
  }
}
