import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../core/services/backup_service.dart';
import '../../../core/services/bookmark_service.dart';
import '../../../core/services/sftp_service.dart';
import '../../../core/services/subscription_gate_service.dart';
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

class SftpConfigDialog extends StatefulWidget {
  const SftpConfigDialog({super.key, this.initialConfig});

  final SftpConfig? initialConfig;

  @override
  State<SftpConfigDialog> createState() => _SftpConfigDialogState();
}

class _SftpConfigDialogState extends State<SftpConfigDialog> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _rootPathController;

  SftpAuthMethod _authMethod = SftpAuthMethod.password;
  SftpTransferMode _transferMode = SftpTransferMode.passive;
  String? _keyFilePath;
  String? _keyFileBookmark;

  bool _obscurePassword = true;
  bool _busy = false;
  String? _testMessage;
  bool _testOk = false;
  bool _connectionVerified = false;
  Map<String, String> _fieldErrors = const <String, String>{};

  @override
  void initState() {
    super.initState();
    final cfg = widget.initialConfig;
    _hostController = TextEditingController(text: cfg?.host ?? '');
    _portController =
        TextEditingController(text: cfg != null ? cfg.port.toString() : '22');
    _usernameController = TextEditingController(text: cfg?.username ?? '');
    _passwordController = TextEditingController(text: cfg?.password ?? '');
    _rootPathController = TextEditingController(text: cfg?.rootPath ?? '');
    _authMethod = cfg?.authMethod ?? SftpAuthMethod.password;
    _transferMode = cfg?.transferMode ?? SftpTransferMode.passive;
    _keyFilePath = cfg?.keyFilePath;
    _keyFileBookmark = cfg?.keyFileBookmark;
    _connectionVerified = cfg != null;
  }

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

  SftpConfig _buildConfig() {
    return SftpConfig(
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? -1,
      username: _usernameController.text.trim(),
      authMethod: _authMethod,
      password: _passwordController.text,
      keyFilePath: _keyFilePath,
      keyFileBookmark: _keyFileBookmark,
      transferMode: _transferMode,
      rootPath: _rootPathController.text.trim(),
    );
  }

  bool _validateConnectionFields() {
    final all = SftpService.validateConfig(_buildConfig()).errors;
    final keys = <String>[
      'host',
      'port',
      'username',
      if (_authMethod == SftpAuthMethod.password) 'password',
      if (_authMethod == SftpAuthMethod.publicKeyFile) 'keyFilePath',
    ];
    final connErrors = <String, String>{
      for (final key in keys)
        if (all.containsKey(key)) key: all[key]!,
    };
    setState(() => _fieldErrors = connErrors);
    return connErrors.isEmpty;
  }

  bool _validate() {
    final validation = SftpService.validateConfig(_buildConfig());
    setState(() => _fieldErrors = validation.errors);
    return validation.isValid;
  }

  void _invalidateConnection() {
    if (!_connectionVerified && _testMessage == null) return;
    setState(() {
      _connectionVerified = false;
      _testOk = false;
      _testMessage = null;
    });
  }

  Future<void> _pickKeyFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose SFTP private key',
      lockParentWindow: true,
      type: FileType.any,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    final bookmark = await BookmarkService.instance.createBookmarkForPath(path);
    if (!mounted) return;
    setState(() {
      _keyFilePath = path;
      _keyFileBookmark = bookmark.isNotEmpty ? bookmark : null;
      _fieldErrors = Map<String, String>.from(_fieldErrors)
        ..remove('keyFilePath');
    });
    _invalidateConnection();
  }

  Future<void> _test() async {
    if (!_validateConnectionFields()) return;
    setState(() {
      _busy = true;
      _testMessage = null;
      _testOk = false;
    });
    try {
      await BackupService.instance.testSftpConnection(
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
      _testMessage = 'Verifying the selected path is writable...';
    });
    try {
      final config = _buildConfig();
      await BackupService.instance.verifySftpWritable(config);
      await BackupService.instance.connectSftp(config);
      if (!mounted) return;
      Navigator.of(context)
          .pop(BackupService.instance.currentSftpAccount ?? 'Connected');
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

  Future<void> _browseRootPath() async {
    if (!_connectionVerified) return;
    final config = _buildConfig().copyWith(rootPath: '/');
    final selected = await showDialog<String?>(
      context: context,
      builder: (_) => _SftpFolderPickerDialog(
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
          width: 440,
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
                        label: 'Host',
                        controller: _hostController,
                        hint: 'sftp.example.com',
                        errorKey: 'host',
                        icon: TablerIcons.server,
                        invalidatesConnection: true,
                      ),
                      const SizedBox(height: 10),
                      _field(
                        label: 'Port',
                        controller: _portController,
                        hint: '22',
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
                        hint: 'Your SFTP user name',
                        errorKey: 'username',
                        icon: TablerIcons.user,
                        invalidatesConnection: true,
                      ),
                      const SizedBox(height: 12),
                      _buildAuthMethod(),
                      const SizedBox(height: 10),
                      if (_authMethod == SftpAuthMethod.password)
                        _field(
                          label: 'Password',
                          controller: _passwordController,
                          hint: 'Your SFTP password',
                          errorKey: 'password',
                          icon: TablerIcons.lock,
                          obscure: _obscurePassword,
                          invalidatesConnection: true,
                          suffix: IconButton(
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
                        )
                      else
                        _buildKeyFilePicker(),
                      const SizedBox(height: 12),
                      _buildTransferMode(),
                      const SizedBox(height: 12),
                      Text(
                        'Root path',
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
                            const Icon(
                              TablerIcons.lock,
                              size: 12,
                              color: _kIcon,
                            ),
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
            child: Image.asset('assets/images/sftp.png', width: 16, height: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Connect to SFTP',
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

  Widget _buildAuthMethod() {
    return _SegmentedSetting<SftpAuthMethod>(
      label: 'Authentication',
      value: _authMethod,
      options: const <_SegmentOption<SftpAuthMethod>>[
        _SegmentOption(SftpAuthMethod.password, 'Password'),
        _SegmentOption(SftpAuthMethod.publicKeyFile, 'Public key file'),
      ],
      onChanged: (value) {
        setState(() {
          _authMethod = value;
          _fieldErrors = Map<String, String>.from(_fieldErrors)
            ..remove('password')
            ..remove('keyFilePath');
        });
        _invalidateConnection();
      },
    );
  }

  Widget _buildTransferMode() {
    return _SegmentedSetting<SftpTransferMode>(
      label: 'Transfer mode',
      value: _transferMode,
      options: const <_SegmentOption<SftpTransferMode>>[
        _SegmentOption(SftpTransferMode.passive, 'Passive'),
        _SegmentOption(SftpTransferMode.active, 'Active'),
      ],
      onChanged: (value) => setState(() => _transferMode = value),
    );
  }

  Widget _buildKeyFilePicker() {
    final error = _fieldErrors['keyFilePath'];
    final path = _keyFilePath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Public key file',
          style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _kCanvas,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: error != null ? const Color(0xFFEF4444) : _kBorderRow,
            ),
          ),
          child: Row(
            children: <Widget>[
              const Icon(TablerIcons.key, size: 16, color: _kIcon),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  path == null || path.isEmpty
                      ? 'Choose a private key file'
                      : path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _uText(13, path == null ? _kIcon : _kTitle),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickKeyFile,
                icon: const Icon(TablerIcons.file_search, size: 14),
                label: const Text('Choose'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF374151),
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: _uText(
                    12,
                    const Color(0xFF374151),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(error, style: _uText(10, const Color(0xFFEF4444))),
        ],
      ],
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
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: _uText(
                12,
                const Color(0xFF374151),
                fontWeight: FontWeight.w600,
              ),
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
              padding: const EdgeInsets.symmetric(horizontal: 16),
              minimumSize: const Size(0, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: _uText(12, _kLabel, fontWeight: FontWeight.w600),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed:
                (_busy || !_connectionVerified || !_hasPath) ? null : _connect,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFB9C6FF),
              disabledForegroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18),
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

class _SegmentOption<T> {
  const _SegmentOption(this.value, this.label);

  final T value;
  final String label;
}

class _SegmentedSetting<T> extends StatelessWidget {
  const _SegmentedSetting({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<_SegmentOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: _uText(12, _kTitle, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: _kCanvas,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorderRow),
          ),
          child: Row(
            children: <Widget>[
              for (final option in options)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(option.value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: option.value == value ? Colors.white : _kCanvas,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: option.value == value
                            ? const <BoxShadow>[
                                BoxShadow(
                                  color: Color(0x14000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        option.label,
                        style: _uText(
                          12,
                          option.value == value ? _kTitle : _kLabel,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

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
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(0, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: _uText(
            12,
            const Color(0xFF374151),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SftpFolderPickerDialog extends StatefulWidget {
  const _SftpFolderPickerDialog({
    required this.config,
    required this.initialPath,
  });

  final SftpConfig config;
  final String initialPath;

  @override
  State<_SftpFolderPickerDialog> createState() =>
      _SftpFolderPickerDialogState();
}

class _SftpFolderPickerDialogState extends State<_SftpFolderPickerDialog> {
  final List<CloudFolder> _breadcrumb = <CloudFolder>[];
  List<CloudFolder>? _folders;
  String? _error;
  bool _loading = true;

  final _newFolderController = TextEditingController();
  bool _showNewFolder = false;
  bool _creatingFolder = false;

  String get _currentPath => _breadcrumb.isEmpty ? '/' : _breadcrumb.last.id;

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
      final folders = await BackupService.instance.browseSftpFolders(
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
      final created = await BackupService.instance.createSftpFolderIn(
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
              _buildPickerFooter(),
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
                    Text(
                      'Back',
                      style: _uText(11, _kBlue, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            )
          else ...<Widget>[
            Image.asset('assets/images/sftp.png', width: 16, height: 16),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              _breadcrumb.isEmpty
                  ? 'Select SFTP Folder'
                  : _breadcrumb.last.name,
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
      itemBuilder: (_, i) => _SftpFolderTile(
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
      padding: const EdgeInsets.all(12),
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
                prefixIcon: const Icon(
                  TablerIcons.folder_plus,
                  size: 16,
                  color: _kIcon,
                ),
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
                textStyle: _uText(
                  12,
                  Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickerFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
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
                borderRadius: BorderRadius.circular(8),
              ),
              minimumSize: const Size(0, 36),
            ),
            child: const Text('Select Path'),
          ),
        ],
      ),
    );
  }
}

class _SftpFolderTile extends StatefulWidget {
  const _SftpFolderTile({required this.folder, required this.onNavigate});

  final CloudFolder folder;
  final VoidCallback onNavigate;

  @override
  State<_SftpFolderTile> createState() => _SftpFolderTileState();
}

class _SftpFolderTileState extends State<_SftpFolderTile> {
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
                  style: _uText(12, _kTitle, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(TablerIcons.chevron_right, size: 14, color: _kIcon),
            ],
          ),
        ),
      ),
    );
  }
}
