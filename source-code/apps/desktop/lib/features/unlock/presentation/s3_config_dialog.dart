import 'package:flutter/material.dart';
import 'package:flutter_aws_s3_client/flutter_aws_s3_client.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../core/services/appearance_preferences.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/s3_regions.dart';
import '../../../core/services/s3_service.dart';
import '../../../presentation/theme/app_theme.dart';
import '../../../presentation/theme/drive_clue_tokens.dart';
import '../../../presentation/widgets/drive_clue/dc_flow_page.dart';

// ── Light palette (sidebar-toned, matches the Cloud Services page) ─────────
const Color _kSurface = DcColors.lightSurface;
const Color _kSurfaceMuted = DcColors.lightInset;
const Color _kBorderSoft = DcColors.sidebarLine;
const Color _kBorderRow = DcColors.lightLineStrong;
const Color _kTitle = DcColors.sidebarText;
const Color _kLabel = DcColors.sidebarMuted;
const Color _kIcon = DcColors.sidebarMuted;
const Color _kBlue = DcColors.selection;
const Color _kDanger = DcColors.redOnLight;
const Color _kSuccess = DcColors.tealOnLight;

TextStyle _uText(
  double size,
  Color color, {
  FontWeight fontWeight = FontWeight.w400,
  double? letterSpacing,
  double? height,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: fontWeight,
    fontFamily: currentFontFamily,
    letterSpacing: letterSpacing,
    height: height,
  );
}

/// Page-heading style used by the inner pages: tight tracking, heavy weight.
TextStyle _uHeading(double size, Color color, {double? height}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: FontWeight.w700,
    fontFamily: currentFontFamily,
    letterSpacing: -0.3,
    height: height,
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
    final bool editing = widget.initialConfig != null;
    return Theme(
      data: AppTheme.driveClue(),
      child: DcFlowPage(
        title: editing ? 'Reconnect Amazon S3' : 'Connect to Amazon S3',
        subtitle: editing
            ? 'Update the credentials, region and bucket for this vault'
            : 'Enter your AWS credentials and bucket information',
        icon: TablerIcons.cloud_upload,
        iconBackground: _kBlue,
        onBack: _busy ? null : () => Navigator.of(context).pop(null),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildPageHeading(),
                const SizedBox(height: 16),
                _buildField(
                  label: 'Access Key ID',
                  controller: _accessKeyController,
                  fieldKey: 'accessKey',
                  hint: 'AKIAIOSFODNN7EXAMPLE',
                  enabled: !_busy,
                  onChange: (v) => _onChanged('accessKey', v),
                ),
                const SizedBox(height: 12),
                _buildSecretField(),
                const SizedBox(height: 12),
                _buildRegionDropdown(),
                const SizedBox(height: 12),
                _buildField(
                  label: 'Bucket Name',
                  controller: _bucketController,
                  fieldKey: 'bucketId',
                  hint: 'my-lumenpass-backups',
                  enabled: !_busy,
                  onChange: (v) => _onChanged('bucketId', v),
                ),
                const SizedBox(height: 12),
                // ── Root path – locked until connection is verified ──
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
                      child: TextField(
                        controller: _rootPathController,
                        readOnly: true,
                        enabled: _connectionVerified,
                        style: _uText(
                          13,
                          _connectionVerified ? _kTitle : _kIcon,
                        ),
                        decoration: InputDecoration(
                          hintText: _connectionVerified
                              ? 'Choose a path with Browse'
                              : '/',
                          hintStyle: _uText(13, _kIcon),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          filled: true,
                          fillColor: _kSurfaceMuted,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _kBorderRow),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _kBorderRow),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _kBorderRow),
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
                      const Icon(TablerIcons.lock, size: 12, color: _kIcon),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Path selection unlocked after a successful test.',
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
        footer: _buildFooterRow(),
      ),
    );
  }

  /// Inner-page style heading: branded icon tile, heavy title, muted subtitle.
  Widget _buildPageHeading() {
    final editing = widget.initialConfig != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _kSurfaceMuted,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorderSoft),
          ),
          child: Image.asset('assets/images/aws-s3-icon.png',
              width: 24, height: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                editing ? 'Reconnect Amazon S3' : 'Connect to Amazon S3',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _uHeading(19, _kTitle, height: 1.15),
              ),
              const SizedBox(height: 3),
              Text(
                editing
                    ? 'Update the credentials, region and bucket for this vault.'
                    : 'Enter your AWS credentials and bucket information.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _uText(12, _kLabel, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
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
              Icon(TablerIcons.alert_circle, size: 12, color: _kDanger),
              const SizedBox(width: 4),
              Text(error, style: _uText(11, _kDanger)),
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
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: true,
            fillColor: _kSurfaceMuted,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? _kDanger : _kBorderRow,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? _kDanger : _kBorderRow,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kBorderRow),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? _kDanger : _kBlue,
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
              Icon(TablerIcons.alert_circle, size: 12, color: _kDanger),
              const SizedBox(width: 4),
              Text(error, style: _uText(11, _kDanger)),
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
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: true,
            fillColor: _kSurfaceMuted,
            prefixIcon: const Icon(TablerIcons.lock, size: 16, color: _kIcon),
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
              borderSide: BorderSide(
                color: error != null ? _kDanger : _kBorderRow,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? _kDanger : _kBorderRow,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kBorderRow),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? _kDanger : _kBlue,
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
              Icon(TablerIcons.alert_circle, size: 12, color: _kDanger),
              const SizedBox(width: 4),
              Text(error, style: _uText(11, _kDanger)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: DropdownButtonFormField<String>(
            initialValue: _selectedRegion,
            isExpanded: true,
            isDense: true,
            style: _uText(13, _kTitle),
            icon: const Icon(TablerIcons.chevron_down, size: 16, color: _kIcon),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              filled: true,
              fillColor: _kSurfaceMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: error != null ? _kDanger : _kBorderRow,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: error != null ? _kDanger : _kBorderRow,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: error != null ? _kDanger : _kBlue,
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

  Widget _buildTestResult() {
    final bool inProgress = _busy;
    final Color color = inProgress ? _kBlue : (_testOk ? _kSuccess : _kDanger);
    final Color bg = inProgress
        ? DcColors.lightSelectionFill
        : (_testOk ? DcColors.tealSoft : DcColors.redSoft);
    final Color border = inProgress
        ? DcColors.selectionLine
        : (_testOk ? DcColors.tealLine : DcColors.redLine);
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
              _testOk ? TablerIcons.circle_check : TablerIcons.alert_triangle,
              size: 14,
              color: color,
            ),
          const SizedBox(width: 8),
          Expanded(child: Text(_testMessage!, style: _uText(11, color))),
        ],
      ),
    );
  }

  Widget _buildFooterRow() {
    return Row(
      children: <Widget>[
        Flexible(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _test,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(TablerIcons.plug_connected, size: 15),
            label: Text(
              _testOk ? 'Re-test' : 'Test Connection',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kTitle,
              disabledForegroundColor: _kIcon,
              side: const BorderSide(color: _kBorderRow),
              backgroundColor: _kSurfaceMuted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              minimumSize: const Size(0, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: _uText(12, _kTitle, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Spacer(),
        OutlinedButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(null),
          style: OutlinedButton.styleFrom(
            foregroundColor: _kLabel,
            disabledForegroundColor: _kIcon,
            side: const BorderSide(color: _kBorderRow),
            backgroundColor: _kSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            minimumSize: const Size(0, 38),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: _uText(12, _kLabel, fontWeight: FontWeight.w600),
          ),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed:
              (_connectionVerified && _testOk && !_busy) ? _connect : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kBlue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: DcColors.lightLineStrong,
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
          child: const Text('Connect'),
        ),
      ],
    );
  }
}

/// Compact "Browse" button shown beside the Path field.
class _BrowseButton extends StatelessWidget {
  const _BrowseButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: const Icon(TablerIcons.folder_search, size: 15),
        label: const Text('Browse'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _kTitle,
          disabledForegroundColor: _kIcon,
          side: BorderSide(color: enabled ? _kBorderRow : _kBorderSoft),
          backgroundColor: _kSurfaceMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          minimumSize: const Size(0, 46),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: _uText(12, _kTitle, fontWeight: FontWeight.w600),
        ),
      ),
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
      data: AppTheme.driveClue(),
      child: DcFlowPage(
        title: 'Select S3 Folder',
        subtitle: _currentPrefix.isEmpty ? 'Bucket root' : _currentPrefix,
        icon: TablerIcons.folder,
        onBack: _depth > 0 ? _navigateUp : () => Navigator.of(context).pop(),
        scrollable: false,
        inset: false,
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildFolderHeading(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Text(
                    _error!,
                    style: _uText(12, _kDanger),
                    textAlign: TextAlign.center,
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : _prefixes.isEmpty
                        ? Center(
                            child: Text(
                              _depth == 0
                                  ? 'No folders found in this bucket.'
                                  : 'This folder is empty.',
                              style: _uText(12, _kLabel),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemCount: _prefixes.length,
                            itemBuilder: (context, index) {
                              final p = _prefixes[index];
                              return _S3PrefixTile(
                                label: _displayName(p),
                                onNavigate: () => _navigateTo(p),
                              );
                            },
                          ),
              ),
              _buildNewFolderInput(),
            ],
          ),
        ),
        footer: _buildFooterRow(),
      ),
    );
  }

  /// Inner-page style heading showing where the browse currently points.
  Widget _buildFolderHeading() {
    final current = _currentPrefix.isEmpty ? 'Bucket root' : _currentPrefix;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorderSoft)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _kSurfaceMuted,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorderSoft),
            ),
            child: const Icon(TablerIcons.bucket, size: 19, color: _kBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  current,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _uHeading(16, _kTitle, height: 1.2),
                ),
                const SizedBox(height: 2),
                Text(
                  'Choose the folder to store this vault in.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _uText(11, _kLabel, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewFolderInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        color: _kSurfaceMuted,
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
                fillColor: _kSurface,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: _kBorderRow),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: _kBlue, width: 1.4),
                ),
                prefixIcon: const Icon(TablerIcons.folder_plus,
                    size: 16, color: _kIcon),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 40, minHeight: 38),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: _canCreate ? _createFolder : null,
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
                disabledBackgroundColor: DcColors.lightLineStrong,
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                textStyle:
                    _uText(12, Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterRow() {
    return Row(
      children: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: _kLabel,
            side: const BorderSide(color: _kBorderRow),
            backgroundColor: _kSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: _uText(12, _kLabel, fontWeight: FontWeight.w600),
          ),
          child: const Text('Cancel'),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: () {
            final clean = _currentPrefix.endsWith('/')
                ? _currentPrefix.substring(0, _currentPrefix.length - 1)
                : _currentPrefix;
            Navigator.of(context).pop(clean);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _kBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: _uText(12, Colors.white, fontWeight: FontWeight.w600),
          ),
          child: const Text('Select Path'),
        ),
      ],
    );
  }
}

/// Light row for a bucket prefix inside the picker.
class _S3PrefixTile extends StatefulWidget {
  const _S3PrefixTile({required this.label, required this.onNavigate});

  final String label;
  final VoidCallback onNavigate;

  @override
  State<_S3PrefixTile> createState() => _S3PrefixTileState();
}

class _S3PrefixTileState extends State<_S3PrefixTile> {
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: _hovered ? DcColors.lightSelectionFill : _kSurface,
            border: const Border(bottom: BorderSide(color: _kBorderSoft)),
          ),
          child: Row(
            children: <Widget>[
              Icon(TablerIcons.folder,
                  size: 15, color: _hovered ? _kBlue : _kIcon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: _uText(12, _hovered ? _kBlue : _kTitle,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
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
