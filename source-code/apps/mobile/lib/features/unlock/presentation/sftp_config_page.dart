import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/cloud_database_service.dart';
import '../../../core/services/sftp_service.dart';

const _kInk = Color(0xFF0A3B48);
const _kBg = Color(0xFFF4F9FA);
const _kMuted = Color(0xFF6B858D);
const _kBorder = Color(0xFFE3EAF0);
const _kDanger = Color(0xFFEF4444);
const _kSuccess = Color(0xFF15803D);
const _kSurface = Color(0xFFFFFFFF);
const _kFieldFill = Color(0xFFF8FAFB);
const _kHeroSub = Color(0xFFC6D9DE);
const _kSoftInk = Color(0xFFE8F4F6);

/// Full-screen page that collects SFTP connection settings (host, port,
/// username, authentication method, transfer mode, root path) and connects
/// via [CloudDatabaseService].
class SftpConfigPage extends ConsumerStatefulWidget {
  const SftpConfigPage({super.key, this.initialConfig});

  final SftpConfig? initialConfig;

  @override
  ConsumerState<SftpConfigPage> createState() => _SftpConfigPageState();
}

class _SftpConfigPageState extends ConsumerState<SftpConfigPage> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _passphraseController;
  late final TextEditingController _pathController;

  SftpAuthMethod _authMethod = SftpAuthMethod.password;
  SftpTransferMode _transferMode = SftpTransferMode.active;
  String? _keyFilePath;

  bool _obscurePassword = true;
  bool _obscurePassphrase = true;
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
        TextEditingController(text: cfg != null ? cfg.port.toString() : '22');
    _usernameController = TextEditingController(text: cfg?.username ?? '');
    _passwordController = TextEditingController(text: cfg?.password ?? '');
    _passphraseController = TextEditingController();
    _pathController = TextEditingController(text: cfg?.rootPath ?? '');
    if (cfg != null) {
      _authMethod = cfg.authMethod;
      _transferMode = cfg.transferMode;
      _keyFilePath = cfg.keyFilePath;
      _connectionVerified = true;
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _passphraseController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  bool get _hasPath => _pathController.text.trim().isNotEmpty;

  SftpConfig _buildConfig() {
    return SftpConfig(
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? -1,
      username: _usernameController.text.trim(),
      authMethod: _authMethod,
      password: _authMethod == SftpAuthMethod.password
          ? _passwordController.text
          : '',
      keyFilePath:
          _authMethod == SftpAuthMethod.publicKeyFile ? _keyFilePath : null,
      transferMode: _transferMode,
      rootPath: _pathController.text.trim(),
    );
  }

  bool _validateConnectionFields() {
    final all = SftpService.validateConfig(_buildConfig()).errors;
    final connErrors = <String, String>{
      for (final key in _connectionFieldKeys)
        if (all.containsKey(key)) key: all[key]!,
    };
    setState(() => _fieldErrors = connErrors);
    return connErrors.isEmpty;
  }

  Set<String> get _connectionFieldKeys {
    final keys = <String>{'host', 'port', 'username'};
    if (_authMethod == SftpAuthMethod.password) {
      keys.add('password');
    }
    return keys;
  }

  Future<void> _selectKeyFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        dialogTitle: 'Select Private Key',
      );
      if (result == null || result.files.isEmpty) return;
      final filePath = result.files.single.path;
      if (filePath == null) return;
      setState(() {
        _keyFilePath = filePath;
        _fieldErrors = Map<String, String>.from(_fieldErrors)
          ..remove('keyFilePath');
        _connectionVerified = false;
        _message = null;
        _messageOk = false;
      });
    } catch (_) {}
  }

  Future<void> _test() async {
    if (!_validateConnectionFields()) return;
    setState(() {
      _busy = true;
      _message = null;
      _messageOk = false;
    });
    try {
      await CloudDatabaseService.instance.testSftpConnection(
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
        builder: (_) => _SftpFolderBrowserPage(
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
    final validation = SftpService.validateConfig(_buildConfig());
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
      await CloudDatabaseService.instance.verifySftpWritable(config);
      await CloudDatabaseService.instance.connectSftp(config);
      if (!mounted) return;
      Navigator.of(context).pop(
        ref.read(cloudSftpAccountProvider) ?? config.accountLabel,
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
        centerTitle: true,
        title: const Text(
          'Connect to SFTP',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          children: <Widget>[
            _buildHero(),
            const SizedBox(height: 16),
            _sectionCard(
              title: 'Server',
              icon: Icons.storage_rounded,
              child: Column(
                children: <Widget>[
                  _field(
                    label: 'Host',
                    controller: _hostController,
                    hint: 'sftp.example.com or 192.168.1.1',
                    errorKey: 'host',
                    icon: Icons.dns_rounded,
                    invalidatesConnection: true,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 110,
                        child: _field(
                          label: 'Port',
                          controller: _portController,
                          hint: '22',
                          errorKey: 'port',
                          icon: Icons.power_rounded,
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          invalidatesConnection: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(
                          label: 'Username',
                          controller: _usernameController,
                          hint: 'SFTP username',
                          errorKey: 'username',
                          icon: Icons.person_outline_rounded,
                          invalidatesConnection: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildAuthSection(),
            const SizedBox(height: 14),
            _buildTransferModeSection(),
            const SizedBox(height: 14),
            _sectionCard(
              title: 'Remote folder',
              icon: Icons.folder_outlined,
              child: _buildPathField(),
            ),
            if (_message != null) ...<Widget>[
              const SizedBox(height: 14),
              _buildMessage(),
            ],
            const SizedBox(height: 20),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  // ── Polished building blocks ────────────────────────────────────────────────

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kInk,
        borderRadius: BorderRadius.circular(18),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: _kInk.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: const Icon(Icons.terminal_rounded,
                color: Colors.white, size: 23),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Secure file transfer',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Add your server, authenticate, then pick a vault folder.',
                  style:
                      TextStyle(color: _kHeroSub, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: _kInk.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 17, color: _kInk),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  color: _kInk,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _test,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering_rounded, size: 18),
            label: const Text('Test'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kInk,
              side: BorderSide(color: _kBorder),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed:
                (_busy || !_connectionVerified || !_hasPath) ? null : _connect,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: const Text('Connect'),
            style: FilledButton.styleFrom(
              backgroundColor: _kInk,
              disabledBackgroundColor: _kMuted.withValues(alpha: 0.35),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Auth section ────────────────────────────────────────────────────────────

  Widget _buildAuthSection() {
    final isPassword = _authMethod == SftpAuthMethod.password;
    final isKey = _authMethod == SftpAuthMethod.publicKeyFile;
    return _sectionCard(
      title: 'Authentication',
      icon: Icons.key_rounded,
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _authOption(
                  label: 'Password',
                  icon: Icons.password_rounded,
                  selected: isPassword,
                  onTap: () => _setAuthMethod(SftpAuthMethod.password),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _authOption(
                  label: 'Public key',
                  icon: Icons.vpn_key_rounded,
                  selected: isKey,
                  onTap: () => _setAuthMethod(SftpAuthMethod.publicKeyFile),
                ),
              ),
            ],
          ),
          if (isPassword) ...<Widget>[
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              enableSuggestions: false,
              autocorrect: false,
              style: const TextStyle(color: _kInk, fontSize: 14),
              onChanged: (_) {
                if (_fieldErrors.containsKey('password') ||
                    _connectionVerified) {
                  setState(() {
                    _fieldErrors = Map<String, String>.from(_fieldErrors)
                      ..remove('password');
                    _connectionVerified = false;
                    _message = null;
                    _messageOk = false;
                  });
                }
              },
              decoration: InputDecoration(
                hintText: 'Your SFTP password',
                hintStyle: TextStyle(color: _kMuted.withValues(alpha: 0.8)),
                prefixIcon:
                    Icon(Icons.lock_outline_rounded, size: 20, color: _kMuted),
                suffixIcon: IconButton(
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
                filled: true,
                fillColor: _kFieldFill,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: _fieldErrors.containsKey('password')
                        ? _kDanger
                        : _kBorder,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: _fieldErrors.containsKey('password')
                        ? _kDanger
                        : _kBorder,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color:
                        _fieldErrors.containsKey('password') ? _kDanger : _kInk,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            if (_fieldErrors.containsKey('password')) ...<Widget>[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_fieldErrors['password']!,
                    style: const TextStyle(color: _kDanger, fontSize: 11)),
              ),
            ],
          ],
          if (isKey) ...<Widget>[
            const SizedBox(height: 12),
            _buildKeyFilePicker(),
            const SizedBox(height: 10),
            TextField(
              controller: _passphraseController,
              obscureText: _obscurePassphrase,
              enableSuggestions: false,
              autocorrect: false,
              style: const TextStyle(color: _kInk, fontSize: 14),
              onChanged: (_) {
                if (_connectionVerified) {
                  setState(() {
                    _connectionVerified = false;
                    _message = null;
                    _messageOk = false;
                  });
                }
              },
              decoration: InputDecoration(
                hintText: 'Passphrase (if the key is encrypted)',
                hintStyle: TextStyle(color: _kMuted.withValues(alpha: 0.8)),
                prefixIcon:
                    Icon(Icons.lock_open_rounded, size: 20, color: _kMuted),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassphrase
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                    color: _kMuted,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassphrase = !_obscurePassphrase),
                ),
                filled: true,
                fillColor: _kFieldFill,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: _kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: _kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: _kInk, width: 1.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _setAuthMethod(SftpAuthMethod method) {
    if (_authMethod == method) return;
    setState(() {
      _authMethod = method;
      _connectionVerified = false;
      _message = null;
      _messageOk = false;
    });
  }

  Widget _authOption({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? _kInk.withValues(alpha: 0.06) : _kFieldFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _kInk : _kBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: selected ? _kInk : _kMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? _kInk : _kMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: selected ? _kInk : _kMuted.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyFilePicker() {
    if (_keyFilePath != null && _keyFilePath!.isNotEmpty) {
      final fileName = _keyFilePath!.split(Platform.pathSeparator).last;
      return Row(
        children: <Widget>[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFB7E2C5)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.vpn_key_rounded, size: 16, color: _kSuccess),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName,
                      style: const TextStyle(
                          color: _kSuccess,
                          fontWeight: FontWeight.w600,
                          fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: _kMuted),
            onPressed: () => setState(() {
              _keyFilePath = null;
              _connectionVerified = false;
              _message = null;
              _messageOk = false;
            }),
          ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _selectKeyFile,
        icon: const Icon(Icons.upload_file_rounded, size: 17),
        label: const Text('Choose private key file'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _kInk,
          backgroundColor: _kFieldFill,
          side: BorderSide(color: _kBorder),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildTransferModeSection() {
    return _sectionCard(
      title: 'Transfer mode',
      icon: Icons.swap_horiz_rounded,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _kFieldFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _modeSegment(
                label: 'Active',
                selected: _transferMode == SftpTransferMode.active,
                onTap: () =>
                    setState(() => _transferMode = SftpTransferMode.active),
              ),
            ),
            Expanded(
              child: _modeSegment(
                label: 'Passive',
                selected: _transferMode == SftpTransferMode.passive,
                onTap: () =>
                    setState(() => _transferMode = SftpTransferMode.passive),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeSegment({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? _kInk : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _kMuted,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // ── Generic field builder ───────────────────────────────────────────────────

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
        if (label.isNotEmpty) ...<Widget>[
          Text(label,
              style: TextStyle(
                  color: enabled ? _kInk : _kMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
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
              borderSide:
                  BorderSide(color: error != null ? _kDanger : _kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: error != null ? _kDanger : _kBorder),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: error != null ? _kDanger : _kInk, width: 1.5),
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: _field(
                label: '',
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
              height: 52,
              child: OutlinedButton.icon(
                onPressed: (_connectionVerified && !_busy) ? _browsePath : null,
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text('Browse'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kInk,
                  disabledForegroundColor: _kMuted,
                  backgroundColor:
                      _connectionVerified ? _kSoftInk : _kFieldFill,
                  side: BorderSide(color: _kBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (!_connectionVerified) ...<Widget>[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              const Icon(Icons.lock_outline_rounded, size: 13, color: _kMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Test the connection to choose a path.',
                    style: TextStyle(color: _kMuted, fontSize: 11)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMessage() {
    final inProgress = _busy;
    final color = inProgress ? _kInk : (_messageOk ? _kSuccess : _kDanger);
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
            child:
                Text(_message!, style: TextStyle(color: color, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// Full-screen SFTP folder browser driven by an explicit, not-yet-saved config.
class _SftpFolderBrowserPage extends StatefulWidget {
  const _SftpFolderBrowserPage(
      {required this.config, required this.initialPath});

  final SftpConfig config;
  final String initialPath;

  @override
  State<_SftpFolderBrowserPage> createState() => _SftpFolderBrowserPageState();
}

class _SftpFolderBrowserPageState extends State<_SftpFolderBrowserPage> {
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
      final folders = await CloudDatabaseService.instance.browseSftpFolders(
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
      final created = await CloudDatabaseService.instance.createSftpFolderIn(
        widget.config,
        name,
        parentId: _currentPath,
      );
      if (!mounted) return;
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
              child: Text('Root',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ),
            for (int i = 0; i < _breadcrumb.length; i++) ...<Widget>[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child:
                    Icon(Icons.chevron_right, size: 14, color: Colors.white54),
              ),
              GestureDetector(
                onTap: () {
                  setState(
                      () => _breadcrumb.removeRange(i + 1, _breadcrumb.length));
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
            Text(_error ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kDanger, fontSize: 13)),
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
        title: Text(folder.name,
            style: const TextStyle(
                color: _kInk, fontWeight: FontWeight.w700, fontSize: 14)),
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
