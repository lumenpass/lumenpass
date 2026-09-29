import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../core/services/backup_service.dart';

import '../../../presentation/theme/app_theme.dart';

import '../../unlock/presentation/s3_config_dialog.dart';
import '../../unlock/presentation/sftp_config_dialog.dart';
import '../../unlock/presentation/webdav_config_dialog.dart';

import '../application/cloud_disconnect.dart';
import '../application/cloud_service_provider.dart';

// ── Vintage palette (mirrors the database picker) ───────────────────────────
const Color _kCanvas = Color(0xFFF7F4EC);
const Color _kPaperBright = Color(0xFFFFFCF5);
const Color _kBorderSoft = Color(0xFFB8B1A5);
const Color _kBorderHover = Color(0xFF252628);
const Color _kHoverBg = Color(0xFFF4E2A4);
const Color _kTitle = Color(0xFF191A1B);
const Color _kLabel = Color(0xFF626560);
const Color _kIcon = Color(0xFF777A75);
const Color _kActionDark = Color(0xFFFF5B22);
const Color _kPrimaryHover = Color(0xFFE94A13);
const Color _kInkBorder = Color(0xFF252628);
const Color _kPeach = Color(0xFFF4D7C8);
const Color _kYellow = Color(0xFFF4E2A4);
const Color _kMintSoft = Color(0xFFDFF2EC);

const Color _kOkBg = _kMintSoft;
const Color _kOkBorder = Color(0xFF21A98F);
const Color _kOkText = Color(0xFF146C5C);
const Color _kWarnBg = Color(0xFFF9E1D8);
const Color _kWarnBorder = Color(0xFFC9402D);
const Color _kWarnText = Color(0xFF9F2F21);
const Color _kAmberBg = _kYellow;
const Color _kAmberBorder = Color(0xFFC09B28);
const Color _kAmberText = Color(0xFF765E10);
const double _kServiceGridGap = 12;
const double _kServiceCardRadius = 14;
const List<BoxShadow> _kServiceCardShadow = <BoxShadow>[
  BoxShadow(
    color: Color(0x33252628),
    offset: Offset(4, 4),
  ),
];

TextStyle _t(
  double size,
  Color color, {
  FontWeight fontWeight = FontWeight.w400,
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

TextStyle _serif(
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

enum _CloudServicesLayout { grid, list }

/// Per-provider health-check lifecycle used to drive each card's UI.
class _ProviderHealth {
  const _ProviderHealth({this.checking = false, this.result});

  /// True while a credential check is in flight.
  final bool checking;

  /// Resolved credential status, or null if never checked / not connected.
  final CloudCredentialResult? result;

  _ProviderHealth copyWith({bool? checking, CloudCredentialResult? result}) {
    return _ProviderHealth(
      checking: checking ?? this.checking,
      result: result ?? this.result,
    );
  }
}

/// Centralized management screen for every cloud storage connection.
///
/// Surfaces connect / disconnect actions and runs a background credential
/// health check when opened so the user is warned when a stored token has
/// been revoked (e.g. the app was removed from their Google account).
class CloudServicesScreen extends ConsumerStatefulWidget {
  const CloudServicesScreen({super.key});

  static const String routeName = '/cloud-services';

  @override
  ConsumerState<CloudServicesScreen> createState() =>
      _CloudServicesScreenState();
}

class _CloudServicesScreenState extends ConsumerState<CloudServicesScreen> {
  final Map<CloudServiceProvider, _ProviderHealth> _health =
      <CloudServiceProvider, _ProviderHealth>{};

  /// Providers currently running a connect/disconnect action.
  final Set<CloudServiceProvider> _busy = <CloudServiceProvider>{};
  _CloudServicesLayout _layout = _CloudServicesLayout.grid;

  @override
  void initState() {
    super.initState();
    // Verify every already-connected provider concurrently on open.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAll());
  }

  Future<void> _checkAll() async {
    final futures = <Future<void>>[];
    for (final provider in CloudServiceProvider.values) {
      if (provider.isConnected) {
        futures.add(_checkProvider(provider));
      }
    }
    await Future.wait(futures);
  }

  Future<void> _checkProvider(CloudServiceProvider provider) async {
    if (!provider.isConnected) {
      setState(() => _health.remove(provider));
      return;
    }
    setState(() {
      _health[provider] =
          (_health[provider] ?? const _ProviderHealth()).copyWith(
        checking: true,
      );
    });
    try {
      final result = await BackupService.instance
          .verifyCloudCredentialsForStorage(provider.storageType);
      if (!mounted) return;
      setState(() {
        _health[provider] = _ProviderHealth(checking: false, result: result);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _health[provider] = _ProviderHealth(
          checking: false,
          result: CloudCredentialResult(
            CloudCredentialStatus.authExpired,
            providerLabel: provider.label,
            message: 'Could not verify connection: $e',
          ),
        );
      });
    }
  }

  // ── Connect / disconnect ──────────────────────────────────────────────────

  Future<void> _connect(CloudServiceProvider provider) async {
    if (_busy.contains(provider)) return;

    setState(() => _busy.add(provider));
    try {
      switch (provider) {
        case CloudServiceProvider.googleDrive:
          await BackupService.instance.connectGoogle();
          break;
        case CloudServiceProvider.dropbox:
          await BackupService.instance.connectDropbox();
          break;
        case CloudServiceProvider.oneDrive:
          await BackupService.instance.connectOneDrive();
          break;
        case CloudServiceProvider.webdav:
          await showDialog<String?>(
            context: context,
            barrierDismissible: false,
            builder: (_) => WebDavConfigDialog(
              initialConfig: BackupService.instance.currentWebDavConfig,
            ),
          );
          break;
        case CloudServiceProvider.sftp:
          await showDialog<String?>(
            context: context,
            barrierDismissible: false,
            builder: (_) => SftpConfigDialog(
              initialConfig: BackupService.instance.currentSftpConfig,
            ),
          );
          break;
        case CloudServiceProvider.s3:
          await showDialog<String?>(
            context: context,
            barrierDismissible: false,
            builder: (_) => S3ConfigDialog(),
          );
          break;
      }
    } catch (e) {
      if (mounted) _showSnack('${provider.label} connection failed: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(provider));
    }

    // Refresh health for the (possibly) newly connected provider.
    if (mounted) await _checkProvider(provider);
  }

  Future<void> _disconnect(CloudServiceProvider provider) async {
    if (_busy.contains(provider)) return;

    final confirmed = await confirmCloudDisconnect(context);
    if (!confirmed || !mounted) return;

    setState(() => _busy.add(provider));
    try {
      // Stages 1-3: delete the saved token, terminate the provider session,
      // and remove this provider's vault references from the local registry.
      // The cloud files themselves are never touched.
      await performCloudDisconnect(ref, provider);
      if (mounted) setState(() => _health.remove(provider));
    } catch (e) {
      if (mounted) _showSnack('${provider.label} disconnect failed: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(provider));
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: _t(12, Colors.white)),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.light(),
      child: Scaffold(
        backgroundColor: _kCanvas,
        body: _VintageGridSurface(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildHeader(),
                const Divider(height: 1, color: _kBorderSoft),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Connected services',
                              style: _serif(17, _kTitle),
                            ),
                          ),
                          _LayoutToggle(
                            layout: _layout,
                            onChanged: (layout) =>
                                setState(() => _layout = layout),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Manage where LumenPass syncs your vaults. Connections '
                        'are checked automatically when you open this screen.',
                        style: _t(12.5, _kLabel, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      _buildServicesLayout(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServicesLayout() {
    if (_layout == _CloudServicesLayout.list) {
      return Column(
        children: <Widget>[
          for (final provider in CloudServiceProvider.values) ...<Widget>[
            _buildServiceCard(provider, _CloudServicesLayout.list),
            if (provider != CloudServiceProvider.values.last)
              const SizedBox(height: 12),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columnCount = maxWidth >= 1080
            ? 3
            : maxWidth >= 700
                ? 2
                : 1;
        final tileWidth =
            (maxWidth - (_kServiceGridGap * (columnCount - 1))) / columnCount;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: CloudServiceProvider.values.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            crossAxisSpacing: _kServiceGridGap,
            mainAxisSpacing: _kServiceGridGap,
            mainAxisExtent: _gridTileHeight(tileWidth),
          ),
          itemBuilder: (context, index) {
            final provider = CloudServiceProvider.values[index];
            return _buildServiceCard(provider, _CloudServicesLayout.grid);
          },
        );
      },
    );
  }

  double _gridTileHeight(double tileWidth) {
    if (tileWidth < 360) return 196;
    if (tileWidth < 440) return 164;
    if (tileWidth < 560) return 160;
    return 148;
  }

  Widget _buildServiceCard(
    CloudServiceProvider provider,
    _CloudServicesLayout layout,
  ) {
    return _CloudServiceCard(
      provider: provider,
      accountLabel: provider.accountLabel(ref),
      isConnected: provider.isConnected,
      health: _health[provider],
      busy: _busy.contains(provider),
      layout: layout,
      onConnect: () => _connect(provider),
      onDisconnect: () => _disconnect(provider),
      onRecheck: () => _checkProvider(provider),
    );
  }

  Widget _buildHeader() {
    final double topPadding =
        Theme.of(context).platform == TargetPlatform.macOS ? 28 : 14;

    return Container(
      padding: EdgeInsets.fromLTRB(14, topPadding, 20, 13),
      decoration: const BoxDecoration(
        color: _kPaperBright,
        border: Border(bottom: BorderSide(color: _kInkBorder)),
      ),
      child: Row(
        children: <Widget>[
          _BackButton(onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 6),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _kPeach,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kInkBorder),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: _kInkBorder, offset: Offset(2, 2)),
              ],
            ),
            child: const Icon(TablerIcons.cloud, size: 18, color: _kTitle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Cloud Services',
                  style: _serif(18, _kTitle),
                ),
                Text(
                  'Centralized cloud connection management',
                  style: _t(12, _kLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatefulWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _hovered ? _kYellow : _kPaperBright,
              shape: BoxShape.circle,
              border: Border.all(
                color: _kInkBorder,
              ),
            ),
            child: const Icon(TablerIcons.arrow_left, size: 18, color: _kTitle),
          ),
        ),
      ),
    );
  }
}

class _LayoutToggle extends StatelessWidget {
  const _LayoutToggle({
    required this.layout,
    required this.onChanged,
  });

  final _CloudServicesLayout layout;
  final ValueChanged<_CloudServicesLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _kPaperBright,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kInkBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _LayoutToggleButton(
            key: const ValueKey<String>('cloud-services-layout-grid'),
            selected: layout == _CloudServicesLayout.grid,
            icon: TablerIcons.layout_grid,
            tooltip: 'Grid layout',
            onTap: () => onChanged(_CloudServicesLayout.grid),
          ),
          _LayoutToggleButton(
            key: const ValueKey<String>('cloud-services-layout-list'),
            selected: layout == _CloudServicesLayout.list,
            icon: TablerIcons.list_details,
            tooltip: 'List layout',
            onTap: () => onChanged(_CloudServicesLayout.list),
          ),
        ],
      ),
    );
  }
}

class _LayoutToggleButton extends StatelessWidget {
  const _LayoutToggleButton({
    super.key,
    required this.selected,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Semantics(
            button: true,
            selected: selected,
            label: tooltip,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 30,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? _kYellow : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? _kInkBorder : Colors.transparent,
                ),
              ),
              child: Icon(
                icon,
                size: 16,
                color: selected ? _kTitle : _kIcon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloudServiceCard extends StatelessWidget {
  const _CloudServiceCard({
    required this.provider,
    required this.accountLabel,
    required this.isConnected,
    required this.health,
    required this.busy,
    required this.layout,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRecheck,
  });

  final CloudServiceProvider provider;
  final String? accountLabel;
  final bool isConnected;

  final _ProviderHealth? health;
  final bool busy;
  final _CloudServicesLayout layout;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onRecheck;

  bool get _available => provider.isConfigured;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: layout == _CloudServicesLayout.grid
          ? const BoxConstraints(minHeight: 140)
          : null,
      padding: EdgeInsets.all(
        layout == _CloudServicesLayout.grid ? 16 : 14,
      ),
      decoration: BoxDecoration(
        color: _kPaperBright,
        borderRadius: BorderRadius.circular(_kServiceCardRadius),
        border: Border.all(color: _kInkBorder),
        boxShadow: _kServiceCardShadow,
      ),
      child: layout == _CloudServicesLayout.grid
          ? _buildGridContent()
          : _buildListContent(),
    );
  }

  Widget _buildListContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildIcon(),
            const SizedBox(width: 12),
            Expanded(child: _buildTitle()),
            const SizedBox(width: 12),
            _buildActions(),
          ],
        ),
        _buildStatus(),
      ],
    );
  }

  Widget _buildGridContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildIcon(),
            const SizedBox(width: 12),
            Expanded(child: _buildTitle()),
            const SizedBox(width: 12),
            _buildActions(),
          ],
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topLeft,
            child: _buildStatus(),
          ),
        ),
      ],
    );
  }

  Widget _buildIcon() {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _kPeach,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kInkBorder),
      ),
      child: Image.asset(
        provider.assetPath,
        width: 22,
        height: 22,
        errorBuilder: (_, __, ___) =>
            const Icon(TablerIcons.cloud, size: 20, color: _kIcon),
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                provider.label,
                style: _serif(15.5, _kTitle),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          !_available
              ? 'Not available in this build'
              : (accountLabel != null && isConnected
                  ? accountLabel!
                  : provider.description),
          style: _t(12, _kLabel, height: 1.3),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildActions() {
    if (busy) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      );
    }

    if (!_available) {
      return Text(
        'Unavailable',
        style: _t(12, _kIcon, fontWeight: FontWeight.w600),
      );
    }

    if (isConnected) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _SmallButton(
            label: 'Recheck',
            icon: TablerIcons.refresh,
            onTap: onRecheck,
            primary: false,
          ),
          const SizedBox(width: 8),
          _SmallButton(
            label: 'Disconnect',
            icon: TablerIcons.plug_connected_x,
            onTap: onDisconnect,
            primary: false,
            danger: true,
          ),
        ],
      );
    }

    return _SmallButton(
      label: 'Connect',
      icon: TablerIcons.plug_connected,
      onTap: onConnect,
      primary: true,
    );
  }

  Widget _buildStatus() {
    if (!isConnected || !_available) return const SizedBox.shrink();

    final h = health;
    if (h == null || h.checking) {
      return _StatusBanner(
        bg: _kCanvas,
        border: _kBorderSoft,
        fg: _kLabel,
        icon: TablerIcons.loader,
        text: 'Checking connection...',
      );
    }

    final result = h.result;
    if (result == null) return const SizedBox.shrink();

    switch (result.status) {
      case CloudCredentialStatus.valid:
      case CloudCredentialStatus.notApplicable:
        return _StatusBanner(
          bg: _kOkBg,
          border: _kOkBorder,
          fg: _kOkText,
          icon: TablerIcons.circle_check,
          text: accountLabel != null
              ? 'Connected as $accountLabel'
              : 'Connected and healthy',
        );
      case CloudCredentialStatus.networkError:
        return _StatusBanner(
          bg: _kAmberBg,
          border: _kAmberBorder,
          fg: _kAmberText,
          icon: TablerIcons.wifi_off,
          text: result.message ??
              "Couldn't verify the connection. Check your network.",
        );
      case CloudCredentialStatus.notSignedIn:
      case CloudCredentialStatus.authExpired:
        return _StatusBanner(
          bg: _kWarnBg,
          border: _kWarnBorder,
          fg: _kWarnText,
          icon: TablerIcons.alert_triangle,
          text: result.message ??
              'Connection problem. ${provider.label} rejected the stored '
                  'credentials - please reconnect.',
          textSize: 11.5,
          action: onConnect,
          actionLabel: 'Reconnect',
        );
    }
  }
}

class _SmallButton extends StatefulWidget {
  const _SmallButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.primary,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  final bool danger;

  @override
  State<_SmallButton> createState() => _SmallButtonState();
}

class _SmallButtonState extends State<_SmallButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color borderColor;
    if (widget.primary) {
      bg = _hovered ? _kPrimaryHover : _kActionDark;
      fg = Colors.white;
      borderColor = Colors.transparent;
    } else if (widget.danger) {
      bg = _hovered ? _kWarnBg : _kPaperBright;
      fg = _kWarnText;
      borderColor = _kWarnBorder;
    } else {
      bg = _hovered ? _kHoverBg : _kPaperBright;
      fg = _kTitle;
      borderColor = _hovered ? _kBorderHover : _kBorderSoft;
    }

    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Semantics(
            button: true,
            label: widget.label,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 38,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: borderColor),
              ),
              child: Icon(widget.icon, size: 16, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.bg,
    required this.border,
    required this.fg,
    required this.icon,
    required this.text,
    this.textSize = 12.5,
    this.action,
    this.actionLabel,
  });

  final Color bg;
  final Color border;
  final Color fg;
  final IconData icon;
  final String text;
  final double textSize;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: _t(textSize, fg, height: 1.35)),
            ),
            if (action != null && actionLabel != null) ...<Widget>[
              const SizedBox(width: 10),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: action,
                  child: Text(
                    actionLabel!,
                    style: _t(12.5, fg, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VintageGridSurface extends StatelessWidget {
  const _VintageGridSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _VintageGridPainter(),
      child: child,
    );
  }
}

class _VintageGridPainter extends CustomPainter {
  const _VintageGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x10252628)
      ..strokeWidth = 1;
    const spacing = 28.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
