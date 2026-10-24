import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../core/services/backup_service.dart';

import '../../../presentation/theme/app_theme.dart';

import '../../unlock/presentation/s3_config_dialog.dart';
import '../../unlock/presentation/sftp_config_dialog.dart';
import '../../unlock/presentation/storage_source_list.dart';
import '../../unlock/presentation/webdav_config_dialog.dart';

import '../application/cloud_disconnect.dart';
import '../application/cloud_service_provider.dart';
import '../../../presentation/theme/drive_clue_tokens.dart';

// ── Light palette (sidebar-toned, matches the database picker) ─────────────
const Color _kCanvas = DcColors.sidebar;
const Color _kPaperBright = DcColors.lightSurface;
const Color _kBorderSoft = DcColors.sidebarLine;
const Color _kBorderHover = DcColors.lightLineStrong;
const Color _kHoverBg = DcColors.lightSelectionFill;
const Color _kTitle = DcColors.sidebarText;
const Color _kLabel = DcColors.sidebarMuted;
const Color _kIcon = DcColors.sidebarMuted;
const Color _kActionDark = DcColors.selection;
const Color _kInkBorder = DcColors.lightLineStrong;
const Color _kYellow = DcColors.lightSelectionFill;
const Color _kMintSoft = DcColors.tealSoft;

const Color _kOkBg = _kMintSoft;
const Color _kOkBorder = DcColors.tealLine;
const Color _kOkText = DcColors.tealOnLight;
const Color _kWarnBg = DcColors.redSoft;
const Color _kWarnBorder = DcColors.redLine;
const Color _kWarnText = DcColors.redOnLight;
const Color _kAmberBg = DcColors.amberSoft;
const Color _kAmberBorder = DcColors.amberLine;
const Color _kAmberText = DcColors.amberOnLight;

// ── Dark header palette (matches the vault title bar) ─────────────────────────
const Color _kHeaderBg = DcColors.background;
const Color _kHeaderLine = DcColors.shellDivider;
const Color _kHeaderTitle = DcColors.text;
const Color _kHeaderLabel = DcColors.muted;
const Color _kHeaderControl = DcColors.panel;
const Color _kHeaderControlHover = DcColors.panelRaised;
const Color _kHeaderControlLine = DcColors.lineStrong;
const double _kServiceGridGap = 12;
const double _kServiceCardRadius = 7;
const List<BoxShadow> _kServiceCardShadow = <BoxShadow>[
  BoxShadow(
    color: DcColors.lightCardShadow,
    blurRadius: 6,
    offset: Offset(0, 2),
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
  const _ProviderHealth({
    this.checking = false,
    this.result,
    this.checkedAt,
  });

  /// True while a credential check is in flight.
  final bool checking;

  /// Resolved credential status, or null if never checked / not connected.
  final CloudCredentialResult? result;

  /// When the last credential check finished.
  final DateTime? checkedAt;

  _ProviderHealth copyWith({bool? checking, CloudCredentialResult? result}) {
    return _ProviderHealth(
      checking: checking ?? this.checking,
      result: result ?? this.result,
      checkedAt: checkedAt,
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
        _health[provider] = _ProviderHealth(
          checking: false,
          result: result,
          checkedAt: DateTime.now(),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _health[provider] = _ProviderHealth(
          checking: false,
          checkedAt: DateTime.now(),
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
        backgroundColor: DcColors.redOnLight,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  _ServiceState _stateOf(CloudServiceProvider provider) {
    if (!provider.isConfigured) return _ServiceState.unavailable;
    if (!provider.isConnected) return _ServiceState.available;
    final h = _health[provider];
    if (h == null || h.checking || h.result == null) {
      return _ServiceState.checking;
    }
    switch (h.result!.status) {
      case CloudCredentialStatus.valid:
      case CloudCredentialStatus.notApplicable:
        return _ServiceState.healthy;
      case CloudCredentialStatus.networkError:
        return _ServiceState.offline;
      case CloudCredentialStatus.notSignedIn:
      case CloudCredentialStatus.authExpired:
        return _ServiceState.authProblem;
    }
  }

  @override
  Widget build(BuildContext context) {
    final attention = <CloudServiceProvider>[];
    final connected = <CloudServiceProvider>[];
    final available = <CloudServiceProvider>[];
    for (final provider in CloudServiceProvider.values) {
      switch (_stateOf(provider)) {
        case _ServiceState.authProblem:
        case _ServiceState.offline:
          attention.add(provider);
          break;
        case _ServiceState.healthy:
        case _ServiceState.checking:
          connected.add(provider);
          break;
        case _ServiceState.available:
        case _ServiceState.unavailable:
          available.add(provider);
          break;
      }
    }
    final bool anyChecking = _health.values.any((h) => h.checking);

    return Theme(
      data: AppTheme.driveClueLight(),
      child: Scaffold(
        backgroundColor: _kCanvas,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildHeader(),
              const Divider(height: 1, color: _kHeaderLine),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                  children: <Widget>[
                    _SummaryStrip(
                      connected: connected.length,
                      attention: attention.length,
                      available: available.length,
                      checking: anyChecking,
                      layout: _layout,
                      onLayoutChanged: (layout) =>
                          setState(() => _layout = layout),
                      onRecheckAll: connected.isEmpty && attention.isEmpty
                          ? null
                          : _checkAll,
                    ),
                    if (attention.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 22),
                      _SectionLabel(
                        label: 'Needs attention',
                        count: attention.length,
                        color: _kWarnText,
                      ),
                      const SizedBox(height: 8),
                      for (final provider in attention) ...<Widget>[
                        _AttentionCard(
                          provider: provider,
                          accountLabel: provider.accountLabel(ref),
                          state: _stateOf(provider),
                          message: _health[provider]?.result?.message,
                          busy: _busy.contains(provider),
                          onReconnect: () => _connect(provider),
                          onRecheck: () => _checkProvider(provider),
                          onDisconnect: () => _disconnect(provider),
                        ),
                        if (provider != attention.last)
                          const SizedBox(height: _kServiceGridGap),
                      ],
                    ],
                    if (connected.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 22),
                      _SectionLabel(
                        label: 'Connected',
                        count: connected.length,
                        color: _kOkText,
                      ),
                      const SizedBox(height: 8),
                      _ServiceGrid(
                        layout: _layout,
                        tileHeight: 92,
                        children: <Widget>[
                          for (final provider in connected)
                            _ConnectedCard(
                              provider: provider,
                              accountLabel: provider.accountLabel(ref),
                              checking:
                                  _stateOf(provider) == _ServiceState.checking,
                              checkedAt: _health[provider]?.checkedAt,
                              busy: _busy.contains(provider),
                              onRecheck: () => _checkProvider(provider),
                              onDisconnect: () => _disconnect(provider),
                            ),
                        ],
                      ),
                    ],
                    if (available.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 22),
                      _SectionLabel(
                        label: 'Available to connect',
                        count: available.length,
                        color: _kLabel,
                      ),
                      const SizedBox(height: 8),
                      _ServiceGrid(
                        layout: _layout,
                        tileHeight: 72,
                        children: <Widget>[
                          for (final provider in available)
                            _AvailableTile(
                              provider: provider,
                              enabled: provider.isConfigured,
                              busy: _busy.contains(provider),
                              onConnect: () => _connect(provider),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final double topPadding =
        Theme.of(context).platform == TargetPlatform.macOS ? 28 : 14;

    return Container(
      padding: EdgeInsets.fromLTRB(14, topPadding, 20, 13),
      decoration: const BoxDecoration(
        color: _kHeaderBg,
        border: Border(bottom: BorderSide(color: _kHeaderLine)),
      ),
      child: Row(
        children: <Widget>[
          _BackButton(onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 6),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _kActionDark,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(TablerIcons.cloud, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Cloud Services',
                  style: _serif(18, _kHeaderTitle),
                ),
                Text(
                  'Manage where LumenPass syncs your vaults',
                  style: _t(12, _kHeaderLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolved display state of one provider.
enum _ServiceState {
  healthy,
  checking,
  offline,
  authProblem,
  available,
  unavailable,
}

Color _brandColor(CloudServiceProvider provider) {
  switch (provider) {
    case CloudServiceProvider.googleDrive:
      return StorageBrandColors.googleDrive;
    case CloudServiceProvider.dropbox:
      return StorageBrandColors.dropbox;
    case CloudServiceProvider.oneDrive:
      return StorageBrandColors.oneDrive;
    case CloudServiceProvider.webdav:
      return StorageBrandColors.webDav;
    case CloudServiceProvider.sftp:
      return StorageBrandColors.sftp;
    case CloudServiceProvider.s3:
      return StorageBrandColors.s3;
  }
}

String _formatTime(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

// ── Summary strip ────────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.connected,
    required this.attention,
    required this.available,
    required this.checking,
    required this.layout,
    required this.onLayoutChanged,
    required this.onRecheckAll,
  });

  final int connected;
  final int attention;
  final int available;
  final bool checking;
  final _CloudServicesLayout layout;
  final ValueChanged<_CloudServicesLayout> onLayoutChanged;
  final VoidCallback? onRecheckAll;

  @override
  Widget build(BuildContext context) {
    final String headline;
    if (checking) {
      headline = 'Checking your connections…';
    } else if (attention > 0) {
      headline = attention == 1
          ? '1 connection needs your attention'
          : '$attention connections need your attention';
    } else if (connected > 0) {
      headline = 'All connections are healthy';
    } else {
      headline = 'No cloud services connected yet';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: _kPaperBright,
        borderRadius: BorderRadius.circular(_kServiceCardRadius),
        border: Border.all(color: _kBorderSoft),
        boxShadow: _kServiceCardShadow,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(headline, style: _serif(15, _kTitle)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    _CountChip(
                      count: connected,
                      label: 'connected',
                      fg: _kOkText,
                      bg: _kOkBg,
                      border: _kOkBorder,
                    ),
                    _CountChip(
                      count: attention,
                      label: 'need attention',
                      fg: attention > 0 ? _kWarnText : _kLabel,
                      bg: attention > 0 ? _kWarnBg : _kCanvas,
                      border: attention > 0 ? _kWarnBorder : _kBorderSoft,
                    ),
                    _CountChip(
                      count: available,
                      label: 'not connected',
                      fg: _kLabel,
                      bg: _kCanvas,
                      border: _kBorderSoft,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (onRecheckAll != null) ...<Widget>[
            _IconButton(
              tooltip: 'Recheck all connections',
              icon: TablerIcons.refresh,
              onTap: checking ? null : onRecheckAll,
            ),
            const SizedBox(width: 8),
          ],
          _LayoutToggle(layout: layout, onChanged: onLayoutChanged),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.count,
    required this.label,
    required this.fg,
    required this.bg,
    required this.border,
  });

  final int count;
  final String label;
  final Color fg;
  final Color bg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '$count ',
              style: _t(11.5, fg, fontWeight: FontWeight.w800),
            ),
            TextSpan(text: label, style: _t(11.5, fg)),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Ubuntu Sans',
              fontSize: DcMetrics.sectionLabelSize,
              fontWeight: FontWeight.w700,
              letterSpacing: DcMetrics.sectionLabelTracking,
              color: _kLabel,
            ),
          ),
          const SizedBox(width: 6),
          Text('$count', style: _t(11, _kIcon, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Lays tiles out as a responsive grid, or a single column in list mode.
class _ServiceGrid extends StatelessWidget {
  const _ServiceGrid({
    required this.layout,
    required this.tileHeight,
    required this.children,
  });

  final _CloudServicesLayout layout;
  final double tileHeight;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final int columns = layout == _CloudServicesLayout.list
            ? 1
            : (maxWidth >= 1080 ? 3 : (maxWidth >= 640 ? 2 : 1));
        final tileWidth =
            (maxWidth - _kServiceGridGap * (columns - 1)) / columns;
        return Wrap(
          spacing: _kServiceGridGap,
          runSpacing: _kServiceGridGap,
          children: <Widget>[
            for (final child in children)
              SizedBox(width: tileWidth, height: tileHeight, child: child),
          ],
        );
      },
    );
  }
}

// ── Cards ────────────────────────────────────────────────────────────────────

class _ProviderLogo extends StatelessWidget {
  const _ProviderLogo({
    required this.provider,
    this.size = 40,
    this.muted = false,
  });

  final CloudServiceProvider provider;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final brand = _brandColor(provider);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: brand.withValues(alpha: muted ? 0.06 : 0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: brand.withValues(alpha: muted ? 0.12 : 0.28)),
      ),
      child: Opacity(
        opacity: muted ? 0.55 : 1,
        child: Image.asset(
          provider.assetPath,
          width: size * 0.52,
          height: size * 0.52,
          errorBuilder: (_, __, ___) =>
              const Icon(TablerIcons.cloud, size: 18, color: _kIcon),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.fg,
    required this.bg,
    required this.border,
    this.icon,
  });

  final String label;
  final Color fg;
  final Color bg;
  final Color border;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: _t(10.5, fg, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.provider,
    required this.accountLabel,
    required this.state,
    required this.message,
    required this.busy,
    required this.onReconnect,
    required this.onRecheck,
    required this.onDisconnect,
  });

  final CloudServiceProvider provider;
  final String? accountLabel;
  final _ServiceState state;
  final String? message;
  final bool busy;
  final VoidCallback onReconnect;
  final VoidCallback onRecheck;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final bool auth = state == _ServiceState.authProblem;
    final Color accent = auth ? _kWarnText : _kAmberText;
    final Color soft = auth ? _kWarnBg : _kAmberBg;
    final Color line = auth ? _kWarnBorder : _kAmberBorder;
    final String text = message ??
        (auth
            ? '${provider.label} rejected the stored credentials. '
                'Reconnect to keep your vaults syncing.'
            : "Couldn't reach ${provider.label}. Check your network.");

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _kPaperBright,
        borderRadius: BorderRadius.circular(_kServiceCardRadius),
        border: Border.all(color: line),
        boxShadow: _kServiceCardShadow,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(width: 4, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                child: Row(
                  children: <Widget>[
                    _ProviderLogo(provider: provider),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  provider.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _serif(15, _kTitle),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusPill(
                                label: auth ? 'Sign-in expired' : 'Offline',
                                icon: auth
                                    ? TablerIcons.alert_triangle
                                    : TablerIcons.wifi_off,
                                fg: accent,
                                bg: soft,
                                border: line,
                              ),
                            ],
                          ),
                          if (accountLabel != null) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              accountLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _t(11.5, _kLabel),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _t(12, accent, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (busy)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    else ...<Widget>[
                      _PillButton(
                        label: auth ? 'Reconnect' : 'Try again',
                        icon: auth
                            ? TablerIcons.plug_connected
                            : TablerIcons.refresh,
                        onTap: auth ? onReconnect : onRecheck,
                        color: accent,
                      ),
                      const SizedBox(width: 4),
                      _CardMenu(
                        onRecheck: auth ? onRecheck : null,
                        onDisconnect: onDisconnect,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectedCard extends StatefulWidget {
  const _ConnectedCard({
    required this.provider,
    required this.accountLabel,
    required this.checking,
    required this.checkedAt,
    required this.busy,
    required this.onRecheck,
    required this.onDisconnect,
  });

  final CloudServiceProvider provider;
  final String? accountLabel;
  final bool checking;
  final DateTime? checkedAt;
  final bool busy;
  final VoidCallback onRecheck;
  final VoidCallback onDisconnect;

  @override
  State<_ConnectedCard> createState() => _ConnectedCardState();
}

class _ConnectedCardState extends State<_ConnectedCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final String footnote = w.checking
        ? 'Verifying credentials…'
        : (w.checkedAt != null
            ? 'Checked at ${_formatTime(w.checkedAt!)}'
            : 'Not checked yet');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: _kPaperBright,
          borderRadius: BorderRadius.circular(_kServiceCardRadius),
          border: Border.all(color: _hovered ? _kBorderHover : _kBorderSoft),
          boxShadow: _kServiceCardShadow,
        ),
        child: Row(
          children: <Widget>[
            _ProviderLogo(provider: w.provider),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          w.provider.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _serif(14.5, _kTitle),
                        ),
                      ),
                      const SizedBox(width: 8),
                      w.checking
                          ? const _StatusPill(
                              label: 'Checking',
                              fg: _kLabel,
                              bg: _kCanvas,
                              border: _kBorderSoft,
                            )
                          : const _StatusPill(
                              label: 'Healthy',
                              icon: TablerIcons.check,
                              fg: _kOkText,
                              bg: _kOkBg,
                              border: _kOkBorder,
                            ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    w.accountLabel ?? w.provider.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(11.5, _kTitle),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    footnote,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(10.5, _kLabel),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (w.busy)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              _CardMenu(
                onRecheck: w.checking ? null : w.onRecheck,
                onDisconnect: w.onDisconnect,
              ),
          ],
        ),
      ),
    );
  }
}

class _AvailableTile extends StatefulWidget {
  const _AvailableTile({
    required this.provider,
    required this.enabled,
    required this.busy,
    required this.onConnect,
  });

  final CloudServiceProvider provider;
  final bool enabled;
  final bool busy;
  final VoidCallback onConnect;

  @override
  State<_AvailableTile> createState() => _AvailableTileState();
}

class _AvailableTileState extends State<_AvailableTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final bool interactive = w.enabled && !w.busy;
    final bool hot = interactive && _hovered;

    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: interactive ? w.onConnect : null,
        child: CustomPaint(
          foregroundPainter: _DashedBorderPainter(
            color: hot ? _kActionDark : _kInkBorder,
            radius: _kServiceCardRadius,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: hot
                  ? _kHoverBg
                  : _kPaperBright.withValues(alpha: w.enabled ? 0.55 : 0.3),
              borderRadius: BorderRadius.circular(_kServiceCardRadius),
            ),
            child: Row(
              children: <Widget>[
                _ProviderLogo(
                  provider: w.provider,
                  size: 36,
                  muted: !hot,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        w.provider.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(
                          13.5,
                          w.enabled ? _kTitle : _kLabel,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        w.enabled
                            ? w.provider.description
                            : 'Not available in this build',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(11, _kLabel),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (w.busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (w.enabled)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(TablerIcons.plus,
                          size: 13, color: _kActionDark),
                      const SizedBox(width: 4),
                      Text(
                        'Connect',
                        style:
                            _t(12, _kActionDark, fontWeight: FontWeight.w700),
                      ),
                    ],
                  )
                else
                  Text(
                    'Unavailable',
                    style: _t(11.5, _kIcon, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(0.5);
    final path = Path()..addRRect(rrect);
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dash),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

// ── Controls ─────────────────────────────────────────────────────────────────

class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.onRecheck, required this.onDisconnect});

  final VoidCallback? onRecheck;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: PopupMenuButton<String>(
        tooltip: 'More actions',
        padding: EdgeInsets.zero,
        color: _kPaperBright,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kServiceCardRadius),
          side: const BorderSide(color: _kBorderSoft),
        ),
        icon: const Icon(TablerIcons.dots_vertical, size: 16, color: _kIcon),
        onSelected: (value) {
          if (value == 'recheck') onRecheck?.call();
          if (value == 'disconnect') onDisconnect();
        },
        itemBuilder: (_) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'recheck',
            enabled: onRecheck != null,
            height: 34,
            child: Row(
              children: <Widget>[
                const Icon(TablerIcons.refresh, size: 14, color: _kTitle),
                const SizedBox(width: 8),
                Text('Recheck connection', style: _t(12, _kTitle)),
              ],
            ),
          ),
          const PopupMenuDivider(height: 6),
          PopupMenuItem<String>(
            value: 'disconnect',
            height: 34,
            child: Row(
              children: <Widget>[
                const Icon(TablerIcons.plug_connected_x,
                    size: 14, color: _kWarnText),
                const SizedBox(width: 8),
                Text(
                  'Disconnect',
                  style: _t(12, _kWarnText, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatefulWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? Color.lerp(widget.color, Colors.black, 0.12)
                : widget.color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(widget.icon, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: _t(12, Colors.white, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
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
              color: _hovered ? _kHeaderControlHover : _kHeaderControl,
              shape: BoxShape.circle,
              border: Border.all(color: _kHeaderControlLine),
            ),
            child: const Icon(
              TablerIcons.arrow_left,
              size: 18,
              color: _kHeaderTitle,
            ),
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
        borderRadius: BorderRadius.circular(7),
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
                borderRadius: BorderRadius.circular(7),
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

class _IconButton extends StatefulWidget {
  const _IconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
    final bool hot = enabled && _hovered;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Semantics(
            button: true,
            enabled: enabled,
            label: widget.tooltip,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hot ? _kHoverBg : _kPaperBright,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: hot ? _kBorderHover : _kInkBorder),
              ),
              child: Icon(
                widget.icon,
                size: 16,
                color: enabled ? _kTitle : _kInkBorder,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
