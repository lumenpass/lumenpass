import 'package:flutter/material.dart';
import 'package:flutter_aws_s3_client/flutter_aws_s3_client.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../core/services/backup_service.dart';
import '../../../core/services/s3_regions.dart';
import '../../../core/services/s3_service.dart';
import '../../../presentation/theme/app_theme.dart';

const Color _kCanvas = Color(0xFFF6F8FB);
const Color _kBorderSoft = Color(0xFFE1E7F0);
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

/// Modal form that collects AWS S3 credentials and region/bucket settings.
/// After a successful connection test the user can browse and select a path
/// prefix within the bucket. On Connect a writability probe is run before
/// the dialog closes. Pops with the account label (`String`) on success,
/// or `null` on cancel.
class S3ConfigDialog extends StatefulWidget {
  const S3ConfigDialog({super.key, this.initialConfig});

  /// Pre-fills the form when reconnecting an existing configuration.
  final S3Config? initialConfig;

  @override
  State<S3ConfigDialog> createState() => _S3ConfigDialogState();
}

class _S3ConfigDialogState extends State<S3ConfigDialog> {
  late final TextEditingController _accessKeyController;
  late final TextEditingController _secretKeyController;
  late final TextEditingController _bucketController;
  late final TextEditingController _rootPathController;

  String _selectedRegion = 'us-east-1';

  bool _obscureSecret = true;
  bool _busy = false;
  bool _testOk = false;
  bool _connectionVerified = false;
  String? _testMessage;
  Map<String, String> _fieldErrors = const <String, String>{};

  /// True once the user has chosen a path via Browse (or one was pre-filled
  /// from an existing configuration).
  bool get _hasPath => _rootPathController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final cfg = widget.initialConfig;
    _accessKeyController = TextEditingController(text: cfg?.accessKey ?? '');
    _secretKeyController = TextEditingController(text: cfg?.secretKey ?? '');
    _selectedRegion = cfg?.region ?? 'us-east-1';
    _bucketController = TextEditingController(text: cfg?.bucketId ?? '');
    _rootPathController = TextEditingController(text: cfg?.rootPath ?? '');
    _connectionVerified = cfg != null && cfg.isValid;
  }

  @override
  void dispose() {
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _bucketController.dispose();
    _rootPathController.dispose();
    super.dispose();
  }

  S3Config _buildConfig() {
    return S3Config(
      accessKey: _accessKeyController.text.trim(),
      secretKey: _secretKeyController.text.trim(),
      region: _selectedRegion,
      bucketId: _bucketController.text.trim(),
      rootPath: _rootPathController.text.trim(),
    );
  }

  bool _validate() {
    final config = _buildConfig();
    if (!config.isValid) {
      final errors = <String, String>{};
      if (config.accessKey.isEmpty) {
        errors['accessKey'] = 'Access key is required';
      }
      if (config.secretKey.isEmpty) {
        errors['secretKey'] = 'Secret key is required';
      }
      if (config.region.isEmpty) errors['region'] = 'Region is required';
      if (config.bucketId.isEmpty) {
        errors['bucketId'] = 'Bucket name is required';
      }
      setState(() => _fieldErrors = errors);
      return false;
    }
    setState(() => _fieldErrors = {});
    return true;
  }

  void _toggleSecretVisibility() {
    setState(() => _obscureSecret = !_obscureSecret);
  }

  Future<void> _test() async {
    if (!_validate()) return;
    setState(() {
      _busy = true;
      _testMessage = null;
      _testOk = false;
    });
    try {
      final config = _buildConfig();
      S3Service.instance.configure(config);
      await S3Service.instance.listObjects(maxKeys: 1);
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _connectionVerified = true;
        _testMessage =
            'Connection successful — bucket "${config.bucketId}" is accessible. Choose a path with Browse.';
      });
    } on NoPermissionsException {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _connectionVerified = false;
        _testMessage =
            'Access denied (HTTP 403). Check your credentials and bucket permissions.';
      });
    } on S3Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _connectionVerified = false;
        _testMessage =
            'S3 error (${e.response.statusCode}): ${e.response.body}';
      });
    } catch (e) {
      if (!mounted) return;
      S3Service.instance.dispose();
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
    if (!_connectionVerified || !_testOk) {
      setState(() {
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
      // Confirm the chosen prefix is writable: upload a probe, then delete it.
      await S3Service.instance.verifyWritable(config.rootPath);
      await BackupService.instance.connectS3(config);
      if (!mounted) return;
      Navigator.of(context)
          .pop(BackupService.instance.currentS3Account ?? 'Connected');
    } on NoPermissionsException {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage =
            'Write denied (HTTP 403). Check bucket write permissions.';
        _busy = false;
      });
    } on S3Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage =
            'S3 error (${e.response.statusCode}): ${e.response.body}';
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

  /// Opens the S3 prefix picker so the user can navigate bucket prefixes and
  /// pick (or create) a parent folder. Only available after connection is
  /// verified.
  Future<void> _browseRootPath() async {
    if (!_connectionVerified) return;
    final selected = await showDialog<String?>(
      context: context,
      builder: (_) => _S3PrefixPickerDialog(
        prefix: _rootPathController.text.trim(),
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

  void _onChanged(String field, String value) {
    setState(() {
      _connectionVerified = false;
      _testOk = false;
      _testMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.light(),
      child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titlePadding: EdgeInsets.zero,
        contentPadding: EdgeInsets.zero,
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        title: Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset('assets/images/aws-s3-icon.png',
                      width: 24, height: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Connect to Amazon S3',
                      style: _uText(16, _kTitle, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: Icon(TablerIcons.x, size: 18, color: _kIcon),
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Enter your AWS credentials and bucket information.',
                style: _uText(12, _kLabel, letterSpacing: 0.02),
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildField(
                  label: 'Access Key ID',
                  controller: _accessKeyController,
                  fieldKey: 'accessKey',
                  hint: 'AKIAIOSFODNN7EXAMPLE',
                  enabled: !_busy,
                  onChange: (v) => _onChanged('accessKey', v),
                ),
                const SizedBox(height: 14),
                _buildSecretField(),
                const SizedBox(height: 14),
                _buildRegionDropdown(),
                const SizedBox(height: 14),
                _buildField(
                  label: 'Bucket Name',
                  controller: _bucketController,
                  fieldKey: 'bucketId',
                  hint: 'my-lumenpass-backups',
                  enabled: !_busy,
                  onChange: (v) => _onChanged('bucketId', v),
                ),
                const SizedBox(height: 14),
                // ── Root path – locked until connection is verified ─────
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
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _rootPathController,
                        readOnly: true,
                        enabled: _connectionVerified,
                        style:
                            _uText(13, _connectionVerified ? _kTitle : _kIcon),
                        decoration: InputDecoration(
                          hintText: _connectionVerified
                              ? 'Choose a path with Browse'
                              : '/',
                          hintStyle: _uText(13, _kIcon),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          filled: true,
                          fillColor: _kCanvas,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: _kBorderSoft, width: 1),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: _kBorderSoft, width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: _kBlue, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 40,
                      child: FilledButton.icon(
                        icon: Icon(TablerIcons.folder_open,
                            size: 14,
                            color: _connectionVerified && !_busy
                                ? _kBlue
                                : _kIcon),
                        label: Text('Browse',
                            style: _uText(
                              12,
                              _connectionVerified && !_busy ? _kBlue : _kIcon,
                              fontWeight: FontWeight.w600,
                            )),
                        onPressed: (_connectionVerified && !_busy)
                            ? _browseRootPath
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          side: BorderSide(
                              color: _connectionVerified && !_busy
                                  ? _kBlue
                                  : _kBorderSoft,
                              width: 1),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 0),
                        ),
                      ),
                    ),
                  ],
                ),
                if (!_connectionVerified) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(TablerIcons.lock, size: 11, color: _kIcon),
                      const SizedBox(width: 4),
                      Text(
                        'Path selection unlocked after a successful test.',
                        style: _uText(11, _kIcon),
                      ),
                    ],
                  ),
                ],
                if (_testMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _testOk
                          ? const Color(0xFFE7F6EC)
                          : const Color(0xFFFDECEC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _testOk
                            ? const Color(0xFFB7E2C5)
                            : const Color(0xFFF3C2C2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _testOk
                              ? TablerIcons.circle_check
                              : TablerIcons.alert_triangle,
                          size: 14,
                          color: _testOk
                              ? const Color(0xFF1B7A3D)
                              : const Color(0xFFC0392B),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _testMessage!,
                            style: _uText(
                              12,
                              _testOk
                                  ? const Color(0xFF1B7A3D)
                                  : const Color(0xFFC0392B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(null),
            style: TextButton.styleFrom(
              foregroundColor: _kLabel,
              textStyle: _uText(13, _kLabel),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kCanvas,
              foregroundColor: _kBlue,
              side: const BorderSide(color: _kBorderSoft, width: 1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: _busy ? null : _test,
            child: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                : Text(
                    _testOk ? 'Re-test' : 'Test Connection',
                    style: _uText(12, _kBlue, fontWeight: FontWeight.w600),
                  ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _connectionVerified && _testOk
                  ? _kBlue
                  : const Color(0xFFCBD5E1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed:
                (_connectionVerified && _testOk && !_busy) ? _connect : null,
            child: Text(
              'Connect',
              style: _uText(12, Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String fieldKey,
    required String hint,
    required bool enabled,
    required Function(String) onChange,
  }) {
    final error = _fieldErrors[fieldKey];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
            ),
            if (error != null) ...[
              const SizedBox(width: 8),
              Icon(TablerIcons.alert_circle,
                  size: 12, color: const Color(0xFFC0392B)),
              const SizedBox(width: 4),
              Text(error, style: _uText(11, const Color(0xFFC0392B))),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          onChanged: onChange,
          style: _uText(13, _kTitle),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: _uText(13, _kIcon),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: _kCanvas,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kBorderSoft, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? const Color(0xFFC0392B) : _kBorderSoft,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? const Color(0xFFC0392B) : _kBlue,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSecretField() {
    final error = _fieldErrors['secretKey'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Secret Access Key',
              style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
            ),
            if (error != null) ...[
              const SizedBox(width: 8),
              Icon(TablerIcons.alert_circle,
                  size: 12, color: const Color(0xFFC0392B)),
              const SizedBox(width: 4),
              Text(error, style: _uText(11, const Color(0xFFC0392B))),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _secretKeyController,
          enabled: !_busy,
          obscureText: _obscureSecret,
          onChanged: (v) => _onChanged('secretKey', v),
          style: _uText(13, _kTitle),
          decoration: InputDecoration(
            hintText: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
            hintStyle: _uText(13, _kIcon),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: _kCanvas,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureSecret ? TablerIcons.eye_off : TablerIcons.eye,
                size: 16,
                color: _kIcon,
              ),
              onPressed: _toggleSecretVisibility,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kBorderSoft, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? const Color(0xFFC0392B) : _kBorderSoft,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? const Color(0xFFC0392B) : _kBlue,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRegionDropdown() {
    final error = _fieldErrors['region'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'AWS Region',
              style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
            ),
            if (error != null) ...[
              const SizedBox(width: 8),
              Icon(TablerIcons.alert_circle,
                  size: 12, color: const Color(0xFFC0392B)),
              const SizedBox(width: 4),
              Text(error, style: _uText(11, const Color(0xFFC0392B))),
            ],
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: DropdownButtonFormField<String>(
            value: _selectedRegion,
            isExpanded: true,
            isDense: true,
            style: _uText(13, _kTitle),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: _kCanvas,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBorderSoft, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: error != null ? const Color(0xFFC0392B) : _kBorderSoft,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: error != null ? const Color(0xFFC0392B) : _kBlue,
                  width: 1.5,
                ),
              ),
            ),
            items: kAwsRegions.map((r) {
              return DropdownMenuItem<String>(
                value: r.code,
                child: Text(
                  '${r.label} (${r.code})',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedRegion = value;
                      _connectionVerified = false;
                      _testOk = false;
                      _testMessage = null;
                    });
                  },
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// S3 Prefix Picker dialog
// ═══════════════════════════════════════════════════════════════════════════

class _S3PrefixPickerDialog extends StatefulWidget {
  const _S3PrefixPickerDialog({this.prefix = ''});

  final String prefix;

  @override
  State<_S3PrefixPickerDialog> createState() => _S3PrefixPickerDialogState();
}

class _S3PrefixPickerDialogState extends State<_S3PrefixPickerDialog> {
  String _currentPrefix = '';
  List<String> _prefixes = [];
  bool _loading = true;
  bool _creatingFolder = false;
  String? _error;
  int _depth = 0;
  late final TextEditingController _newFolderController;

  @override
  void initState() {
    super.initState();
    _newFolderController = TextEditingController();
    _currentPrefix = widget.prefix;
    _depth = widget.prefix.isEmpty
        ? 0
        : widget.prefix.split('/').where((s) => s.isNotEmpty).length;
    _load();
  }

  @override
  void dispose() {
    _newFolderController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefixes =
          await S3Service.instance.listPrefixes(prefix: _currentPrefix);
      if (!mounted) return;
      setState(() {
        _prefixes = prefixes;
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
    setState(() {
      _creatingFolder = true;
      _error = null;
    });
    try {
      await S3Service.instance.createPrefix(_currentPrefix, folderName);
      _newFolderController.clear();
      if (!mounted) return;
      setState(() => _creatingFolder = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _creatingFolder = false;
      });
    }
  }

  void _navigateTo(String prefix) {
    setState(() {
      _currentPrefix = prefix;
      _depth++;
    });
    _load();
  }

  void _navigateUp() {
    if (_depth == 0) return;
    final segments =
        _currentPrefix.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return;
    segments.removeLast();
    setState(() {
      _currentPrefix = segments.isEmpty ? '' : '${segments.join('/')}/';
      _depth = segments.length;
    });
    _load();
  }

  String _displayName(String fullPrefix) {
    final base = _currentPrefix.isEmpty ? '' : _currentPrefix;
    var name = fullPrefix.substring(base.length);
    if (name.endsWith('/')) name = name.substring(0, name.length - 1);
    return name;
  }

  bool get _canCreate =>
      !_creatingFolder && _newFolderController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.light(),
      child: Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: 420,
          height: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                decoration: const BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: _kBorderSoft, width: 1)),
                ),
                child: Row(
                  children: [
                    Icon(TablerIcons.bucket, size: 18, color: _kBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentPrefix.isEmpty ? 'Bucket root' : _currentPrefix,
                        style: _uText(13, _kTitle, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_depth > 0)
                      IconButton(
                        tooltip: 'Up',
                        icon:
                            Icon(TablerIcons.arrow_up, size: 18, color: _kIcon),
                        onPressed: _navigateUp,
                      ),
                    IconButton(
                      tooltip: 'New folder',
                      icon: Icon(TablerIcons.folder_plus,
                          size: 18, color: _kIcon),
                      onPressed: () =>
                          setState(() => _newFolderController.clear()),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: Icon(TablerIcons.x, size: 18, color: _kIcon),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Current path + Select button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(
                  children: [
                    Icon(TablerIcons.folder_check, size: 16, color: _kBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentPrefix.isEmpty
                            ? '/ (bucket root)'
                            : _currentPrefix,
                        style: _uText(12, _kLabel),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 32,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _kBlue,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 0),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () {
                          final clean = _currentPrefix.endsWith('/')
                              ? _currentPrefix.substring(
                                  0, _currentPrefix.length - 1)
                              : _currentPrefix;
                          Navigator.of(context).pop(clean);
                        },
                        child: Text('Select',
                            style: _uText(11, Colors.white,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: _kBorderSoft),
              // Error
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(_error!,
                      style: _uText(12, const Color(0xFFC0392B)),
                      textAlign: TextAlign.center),
                ),
              // Folder list (fills the center)
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 1.5))
                    : _prefixes.isEmpty
                        ? Center(
                            child: Text(
                              _depth == 0
                                  ? 'No folders found in this bucket.'
                                  : 'This folder is empty.',
                              style: _uText(12, _kIcon),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _prefixes.length,
                            itemBuilder: (context, index) {
                              final p = _prefixes[index];
                              return ListTile(
                                dense: true,
                                leading: Icon(TablerIcons.folder,
                                    size: 18, color: _kIcon),
                                title: Text(_displayName(p),
                                    style: _uText(13, _kTitle)),
                                onTap: () => _navigateTo(p),
                                trailing: Icon(TablerIcons.chevron_right,
                                    size: 16, color: _kIcon),
                              );
                            },
                          ),
              ),
              // New-folder inline input (pinned to the bottom)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFF),
                  border: Border(top: BorderSide(color: _kBorderSoft)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newFolderController,
                        enabled: !_creatingFolder,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) {
                          if (_canCreate) _createFolder();
                        },
                        style: _uText(12, _kTitle, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: 'New folder name',
                          hintStyle: _uText(12, _kIcon),
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _kBorderSoft),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: _kBlue, width: 1.4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 40,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              _canCreate ? _kBlue : const Color(0xFFCBD5E1),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 0),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _canCreate ? _createFolder : null,
                        child: _creatingFolder
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5, color: Colors.white),
                              )
                            : Text('Create',
                                style: _uText(12, Colors.white,
                                    fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
