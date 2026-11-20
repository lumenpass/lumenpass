import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../presentation/theme/app_theme.dart';
import '../../../presentation/theme/drive_clue_tokens.dart';
import '../../../presentation/widgets/lumenpass_wordmark.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Detached Settings window (second Flutter engine)
/// ─────────────────────────────────────────────────────────────────────────
///
/// This widget is the *entire* UI hosted by the standalone native Settings
/// window (see `settingsMain()` in `main.dart`, `SettingsWindowController`
/// in `macos/Runner/SettingsWindow.swift`, and `SettingsWindow` in
/// `windows/runner/settings_window.cpp` / `linux/runner/settings_window.cc`).
///
/// Like [QuickSearchWindow] it runs in its own Dart isolate with its own
/// Riverpod container, so it holds **no** vault data. Everything it shows
/// arrives as a JSON snapshot over `lumenpass/settings_host`, and every change
/// is sent back as an intent that the main engine applies against the real
/// providers. That keeps the main window's state authoritative.
///
/// Because this is a preference-only surface, it needs none of the vault-
/// bound settings panes. Sections that require the decrypted database
/// (master password, backup restore, biometrics, PIN) are intentionally absent
/// — they are handed back to the main window instead.
class SettingsWindow extends StatefulWidget {
  const SettingsWindow({super.key});

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  static const MethodChannel _channel =
      MethodChannel('lumenpass/settings_host');

  /// How often the window re-pulls the snapshot so live values (SSH Agent
  /// socket path and config status) stay current while the pane is open.
  static const Duration _pollInterval = Duration(seconds: 2);

  _SettingsSnapshot _settings = const _SettingsSnapshot();
  Timer? _pollTimer;

  /// Deep-link requests from the native host (e.g. "manage SSH agent" opens
  /// the Advanced pane).
  final ValueNotifier<String?> _sectionRequest = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleHostCall);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _channel.invokeMethod<void>('ready');
      _requestSettings();
    });
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (mounted) unawaited(_requestSettings());
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _sectionRequest.dispose();
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleHostCall(MethodCall call) async {
    switch (call.method) {
      case 'setSnapshot':
        final raw = call.arguments;
        if (raw is String) _applySnapshot(raw);
        return null;
      case 'setSection':
        final raw = call.arguments;
        if (raw is String) _sectionRequest.value = raw;
        return null;
      default:
        return null;
    }
  }

  Future<void> _requestSettings() async {
    try {
      final raw = await _channel.invokeMethod<String>('requestSettings');
      if (raw != null) _applySnapshot(raw);
    } on PlatformException {
      // Host not ready yet; the pushed snapshot will arrive via setSnapshot.
    } on MissingPluginException {
      // Running outside a native host (e.g. widget test / wrong entrypoint).
    }
  }

  void _applySnapshot(String raw) {
    if (!mounted) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final next = _SettingsSnapshot.fromJson(json);
      // Avoid rebuilding the whole tree every poll tick when nothing moved.
      if (next == _settings) return;
      setState(() => _settings = next);
    } catch (_) {
      // Ignore malformed payloads rather than blanking the window.
    }
  }

  /// Fire-and-forget: the host applies the change and echoes a fresh snapshot.
  Future<void> _write(String key, Object? value) async {
    try {
      final raw = await _channel.invokeMethod<String>(
        'applySetting',
        <String, Object?>{'key': key, 'value': value},
      );
      if (raw != null) _applySnapshot(raw);
    } on PlatformException {
      // Keep the optimistic local state; the next snapshot reconciles.
    } on MissingPluginException {
      // No native host attached.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // Mirror the main window's typography so the detached window previews
      // text-size and font changes live instead of only on next launch.
      //
      // The body is the light DriveClue surface used by the main window; the
      // 46 px title bar keeps the dark chrome and paints its own dark tokens,
      // so the shell reads as "dark window bar over a light page".
      theme: AppTheme.driveClueLight(
        fontFamily: _settings.fontFamily,
        sizeDelta: _settings.textSizeDelta,
      ),
      darkTheme: AppTheme.driveClueLight(
        fontFamily: _settings.fontFamily,
        sizeDelta: _settings.textSizeDelta,
      ),
      themeMode: ThemeMode.light,
      home: _SettingsShell(
        settings: _settings,
        onWrite: _write,
        sectionRequest: _sectionRequest,
      ),
    );
  }
}

/// Result of one host snapshot.
class _SettingsSnapshot {
  const _SettingsSnapshot({
    this.hideDockIcon = false,
    this.autostartWithSystem = false,
    this.startMinimized = false,
    this.textSizeDelta = 0,
    this.fontFamily = 'Ubuntu Sans',
    this.hideCreditCardNumber = true,
    this.autoLockMinutes = 30,
    this.clipboardClearSeconds = 60,
    this.domainSetting = 'default',
    this.autoFetchItemIcon = true,
    this.sshAgentEnabled = false,
    this.sshAgentSocketPath = '',
    this.sshAgentConfigStatus = 'unknown',
  });

  factory _SettingsSnapshot.fromJson(Map<String, dynamic> json) {
    return _SettingsSnapshot(
      hideDockIcon: json['hideDockIcon'] as bool? ?? false,
      autostartWithSystem: json['autostartWithSystem'] as bool? ?? false,
      startMinimized: json['startMinimized'] as bool? ?? false,
      textSizeDelta: (json['textSizeDelta'] as num?)?.toInt() ?? 0,
      fontFamily: json['fontFamily'] as String? ?? 'Ubuntu Sans',
      hideCreditCardNumber: json['hideCreditCardNumber'] as bool? ?? true,
      autoLockMinutes: (json['autoLockMinutes'] as num?)?.toInt(),
      clipboardClearSeconds: (json['clipboardClearSeconds'] as num?)?.toInt(),
      domainSetting: json['domainSetting'] as String? ?? 'default',
      autoFetchItemIcon: json['autoFetchItemIcon'] as bool? ?? true,
      sshAgentEnabled: json['sshAgentEnabled'] as bool? ?? false,
      sshAgentSocketPath: json['sshAgentSocketPath'] as String? ?? '',
      sshAgentConfigStatus:
          json['sshAgentConfigStatus'] as String? ?? 'unknown',
    );
  }

  final bool hideDockIcon;
  final bool autostartWithSystem;
  final bool startMinimized;
  final int textSizeDelta;
  final String fontFamily;
  final bool hideCreditCardNumber;
  final int? autoLockMinutes;
  final int? clipboardClearSeconds;
  final String domainSetting;
  final bool autoFetchItemIcon;
  final bool sshAgentEnabled;
  final String sshAgentSocketPath;
  final String sshAgentConfigStatus;

  @override
  bool operator ==(Object other) {
    return other is _SettingsSnapshot &&
        other.hideDockIcon == hideDockIcon &&
        other.autostartWithSystem == autostartWithSystem &&
        other.startMinimized == startMinimized &&
        other.textSizeDelta == textSizeDelta &&
        other.fontFamily == fontFamily &&
        other.hideCreditCardNumber == hideCreditCardNumber &&
        other.autoLockMinutes == autoLockMinutes &&
        other.clipboardClearSeconds == clipboardClearSeconds &&
        other.domainSetting == domainSetting &&
        other.autoFetchItemIcon == autoFetchItemIcon &&
        other.sshAgentEnabled == sshAgentEnabled &&
        other.sshAgentSocketPath == sshAgentSocketPath &&
        other.sshAgentConfigStatus == sshAgentConfigStatus;
  }

  @override
  int get hashCode => Object.hash(
        hideDockIcon,
        autostartWithSystem,
        startMinimized,
        textSizeDelta,
        fontFamily,
        hideCreditCardNumber,
        autoLockMinutes,
        clipboardClearSeconds,
        domainSetting,
        autoFetchItemIcon,
        sshAgentEnabled,
        sshAgentSocketPath,
        sshAgentConfigStatus,
      );
}

class _SettingsShell extends StatefulWidget {
  const _SettingsShell({
    required this.settings,
    required this.onWrite,
    required this.sectionRequest,
  });

  final _SettingsSnapshot settings;
  final Future<void> Function(String key, Object? value) onWrite;
  final ValueNotifier<String?> sectionRequest;

  @override
  State<_SettingsShell> createState() => _SettingsShellState();
}

class _SettingsShellState extends State<_SettingsShell> {
  int _selected = 0;

  static const List<_SettingsSection> _sections = <_SettingsSection>[
    _SettingsSection('General', Icons.settings_outlined, 'general'),
    _SettingsSection('Appearance', Icons.palette_outlined, 'appearance'),
    _SettingsSection('Security', Icons.shield_outlined, 'security'),
    _SettingsSection('Advanced', Icons.terminal_outlined, 'advanced'),
    _SettingsSection('About', Icons.info_outline, 'about'),
  ];

  @override
  void initState() {
    super.initState();
    widget.sectionRequest.addListener(_handleSectionRequest);
    // A deep link can arrive before the first frame.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _handleSectionRequest());
  }

  @override
  void didUpdateWidget(covariant _SettingsShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sectionRequest != widget.sectionRequest) {
      oldWidget.sectionRequest.removeListener(_handleSectionRequest);
      widget.sectionRequest.addListener(_handleSectionRequest);
    }
  }

  @override
  void dispose() {
    widget.sectionRequest.removeListener(_handleSectionRequest);
    super.dispose();
  }

  void _handleSectionRequest() {
    final requested = widget.sectionRequest.value;
    if (requested == null || !mounted) return;
    final index = _sections.indexWhere((s) => s.id == requested);
    widget.sectionRequest.value = null;
    if (index < 0 || index == _selected) return;
    setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    // A `Material` ancestor is required for Material widgets (Switch, ink).
    // The window root has no Scaffold, so provide it here.
    //
    // Shell mirrors the main window: a light sidebar down the full height
    // (it also sits under the native traffic lights), then a right column
    // made of the dark 46 px title bar and the light settings content.
    return Material(
      color: DcColors.sidebar,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Sidebar(
            sections: _sections,
            selected: _selected,
            onSelected: (index) => setState(() => _selected = index),
          ),
          const SizedBox(
            width: 1,
            child: ColoredBox(color: DcColors.lightLineStrong),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DcSettingsTitleBar(section: _sections[_selected].label),
                Expanded(
                  child: _ContentPane(
                    child: switch (_selected) {
                      0 => _GeneralPane(
                          settings: widget.settings,
                          onWrite: widget.onWrite,
                        ),
                      1 => _AppearancePane(
                          settings: widget.settings,
                          onWrite: widget.onWrite,
                        ),
                      2 => _SecurityPane(
                          settings: widget.settings,
                          onWrite: widget.onWrite,
                        ),
                      3 => _AdvancedPane(
                          settings: widget.settings,
                          onWrite: widget.onWrite,
                        ),
                      _ => const _AboutPane(),
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dark window title bar: the LumenPass wordmark followed by the active
/// section name (`LumenPass: General`).
class DcSettingsTitleBar extends StatelessWidget {
  const DcSettingsTitleBar({super.key, required this.section});

  final String section;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DcMetrics.headerHeight,
      decoration: const BoxDecoration(
        color: DcColors.background,
        border: Border(bottom: BorderSide(color: DcColors.line)),
      ),
      padding: const EdgeInsets.only(left: 18, right: 14),
      child: Row(
        children: <Widget>[
          const LumenPassWordmark(
            fontSize: 15,
            lumenColor: DcColors.text,
            passColor: DcColors.cyan,
          ),
          const Text(
            ':',
            style: TextStyle(fontSize: 15, color: DcColors.muted),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              section,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DcColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection {
  const _SettingsSection(this.label, this.icon, this.id);

  final String label;
  final IconData icon;

  /// Name shared with the native host and the main window's
  /// `_SettingsSectionId` values.
  final String id;
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.sections,
    required this.selected,
    required this.onSelected,
  });

  final List<_SettingsSection> sections;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      color: DcColors.sidebar,
      // The sidebar runs the full height under the native traffic lights (the
      // window is `fullSizeContentView`). The header sits on the same row as
      // the traffic lights, the nav follows immediately, and the footer is
      // pinned to the bottom behind a full-bleed hairline.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _SidebarHeader(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var i = 0; i < sections.length; i++)
                  _SidebarRow(
                    section: sections[i],
                    selected: i == selected,
                    onTap: () => onSelected(i),
                  ),
              ],
            ),
          ),
          const Spacer(),
          const Divider(
              height: 1, thickness: 1, color: DcColors.lightLineStrong),
          const _SidebarFooter(),
        ],
      ),
    );
  }
}

/// Brand block above the nav. On macOS the wordmark sits on the same row as
/// the native traffic lights (to their right), and the supporting line starts
/// flush with the nav rows below it so the column keeps one left edge.
class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader();

  /// Horizontal room needed by the macOS traffic lights: they sit 20 pt from
  /// the window edge as three 12 pt buttons with 8 pt gaps, ending at 72 pt.
  /// 80 keeps a comfortable gap after the green button.
  static const double _kTrafficLightGutter = 80;

  /// Side padding shared with the nav rows below.
  static const double _kSidePadding = 10;

  @override
  Widget build(BuildContext context) {
    final bool isMac = Platform.isMacOS;
    // The gutter is measured from the window edge, the padding from inside.
    final double gutter = isMac ? _kTrafficLightGutter - _kSidePadding : 0;
    return Padding(
      // Vertically centred on the native buttons when they are present.
      padding: EdgeInsets.fromLTRB(
        _kSidePadding,
        isMac ? 11 : 13,
        _kSidePadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (gutter > 0) SizedBox(width: gutter),
              const Expanded(
                child: LumenPassWordmark(
                  fontSize: 13,
                  lumenColor: DcColors.sidebarText,
                  passColor: DcColors.selection,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Changes apply right away.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: DcColors.sidebarMuted),
          ),
        ],
      ),
    );
  }
}

/// Pinned bottom block: keeps the column from looking top-heavy and puts the
/// build/licensing details where people look for them. The divider above it is
/// drawn by [_Sidebar] so it spans the full sidebar width.
class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? '—';
              final build = snapshot.data?.buildNumber ?? '—';
              return Text(
                'v$version ($build)',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: DcColors.sidebarMuted,
                ),
              );
            },
          ),
          const SizedBox(height: 3),
          const Text(
            'Free forever · Apache-2.0',
            style: TextStyle(fontSize: 10, color: DcColors.sidebarMuted),
          ),
        ],
      ),
    );
  }
}

class _SidebarRow extends StatefulWidget {
  const _SidebarRow({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final _SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<_SidebarRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: DcMetrics.sidebarRowHeight,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? DcColors.selection
                : _hovered
                    ? DcColors.sidebarHover
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                widget.section.icon,
                size: 15,
                color: selected ? Colors.white : DcColors.sidebarMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.section.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? Colors.white : DcColors.sidebarText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContentPane extends StatelessWidget {
  /// The pane heading is intentionally absent: the section name is rendered in
  /// the window's dark title bar, matching the main window's title-bar style.
  const _ContentPane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DcColors.sidebar,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
        // Do NOT wrap this in `Align`: inside a vertical scroll view the
        // height constraint is unbounded, and `Align` would try to take
        // infinite height, overflowing the enclosing Row.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: child,
        ),
      ),
    );
  }
}

// ── Panes ─────────────────────────────────────────────────────────────────

class _GeneralPane extends StatelessWidget {
  const _GeneralPane({required this.settings, required this.onWrite});

  final _SettingsSnapshot settings;
  final Future<void> Function(String key, Object? value) onWrite;

  @override
  Widget build(BuildContext context) {
    return Column(
      // Inside a scroll view the incoming height is unbounded; a `max` Column
      // would expand to infinity and overflow the enclosing Row with a red
      // error screen. Every pane must shrink-wrap.
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _PaneIntro(
          'Control how LumenPass runs alongside the rest of your system.',
        ),
        _SettingsCard(
          children: <Widget>[
            // Dock/menu-bar behaviour only exists on macOS; Windows and Linux
            // always keep the tray icon.
            if (Platform.isMacOS)
              _SettingsToggle(
                title: 'Keep LumenPass in the menu bar',
                subtitle: 'Allows Quick Search and the SSH agent to work '
                    'while the main window is closed.',
                value: settings.hideDockIcon,
                onChanged: (value) => onWrite('hideDockIcon', value),
              ),
            _SettingsToggle(
              title: 'Start at login',
              subtitle: 'Launch LumenPass automatically when you sign in.',
              value: settings.autostartWithSystem,
              onChanged: (value) => onWrite('autostartWithSystem', value),
            ),
            _SettingsToggle(
              title: 'Start minimized',
              subtitle: 'When launched at login, keep the main window hidden '
                  'until you open it.',
              value: settings.startMinimized,
              onChanged: (value) => onWrite('startMinimized', value),
              showDivider: false,
            ),
          ],
        ),
      ],
    );
  }
}

class _AppearancePane extends StatelessWidget {
  const _AppearancePane({required this.settings, required this.onWrite});

  final _SettingsSnapshot settings;
  final Future<void> Function(String key, Object? value) onWrite;

  static const List<String> _fonts = <String>[
    'Ubuntu Sans',
    'Inter',
    'SF Pro Text',
    'Segoe UI',
    'Roboto',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _PaneIntro(
          'Adjust how text renders across both windows.',
        ),
        const _GroupLabel('Text size'),
        Row(
          children: <Widget>[
            for (var delta = -2; delta <= 2; delta++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Chip(
                  label: delta == 0
                      ? 'Default'
                      : (delta > 0 ? '+$delta' : '$delta'),
                  selected: settings.textSizeDelta == delta,
                  onTap: () => onWrite('textSizeDelta', delta),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        const _GroupLabel('Font'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final font in _fonts)
              _Chip(
                label: font,
                selected: settings.fontFamily == font,
                onTap: () => onWrite('fontFamily', font),
              ),
          ],
        ),
      ],
    );
  }
}

class _SecurityPane extends StatelessWidget {
  const _SecurityPane({required this.settings, required this.onWrite});

  final _SettingsSnapshot settings;
  final Future<void> Function(String key, Object? value) onWrite;

  static const List<(String, int?)> _autoLockOptions = <(String, int?)>[
    ('15 min', 15),
    ('30 min', 30),
    ('1 hour', 60),
    ('4 hours', 240),
    ('8 hours', 480),
    ('24 hours', 1440),
    ('Never', null),
  ];

  static const List<(String, int?)> _clipboardOptions = <(String, int?)>[
    ('30 sec', 30),
    ('60 sec', 60),
    ('90 sec', 90),
    ('Never', null),
  ];

  static const List<(String, String)> _domainOptions = <(String, String)>[
    ('Default matching', 'default'),
    ('Base domain', 'baseDomain'),
    ('Subdomain', 'subdomain'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _PaneIntro(
          'Protect sensitive data and control how long unlocked state lasts.',
        ),
        const _GroupLabel('Sensitive data'),
        _SettingsCard(
          children: <Widget>[
            _SettingsToggle(
              title: 'Hide full credit card number',
              subtitle: 'Shows only the first 4 and last 3 digits in item '
                  'details. The encrypted value is unchanged.',
              value: settings.hideCreditCardNumber,
              onChanged: (value) => onWrite('hideCreditCardNumber', value),
              showDivider: false,
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _GroupLabel('Auto-lock'),
        _ChipGroup<int?>(
          options: _autoLockOptions,
          selected: settings.autoLockMinutes,
          onSelected: (value) => onWrite('autoLockMinutes', value),
        ),
        const SizedBox(height: 22),
        const _GroupLabel('Clear clipboard after'),
        _ChipGroup<int?>(
          options: _clipboardOptions,
          selected: settings.clipboardClearSeconds,
          onSelected: (value) => onWrite('clipboardClearSeconds', value),
        ),
        const SizedBox(height: 22),
        const _GroupLabel('Website matching'),
        _ChipGroup<String>(
          options: _domainOptions,
          selected: settings.domainSetting,
          onSelected: (value) => onWrite('domainSetting', value),
        ),
        const SizedBox(height: 22),
        const _GroupLabel('Icons'),
        _SettingsCard(
          children: <Widget>[
            _SettingsToggle(
              title: 'Fetch item icons',
              subtitle: 'Look up site icons so saved logins are easier to '
                  'recognise at a glance.',
              value: settings.autoFetchItemIcon,
              onChanged: (value) => onWrite('autoFetchItemIcon', value),
              showDivider: false,
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _HintPanel(
          icon: Icons.lock_outline,
          title: 'Kept in the main window',
          body: 'Biometric unlock, PIN codes, and backup restore need the '
              'decrypted vault, so they stay in the main window.',
        ),
      ],
    );
  }
}

class _AdvancedPane extends StatelessWidget {
  const _AdvancedPane({required this.settings, required this.onWrite});

  final _SettingsSnapshot settings;
  final Future<void> Function(String key, Object? value) onWrite;

  @override
  Widget build(BuildContext context) {
    final enabled = settings.sshAgentEnabled;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _PaneIntro(
          'Use the built-in SSH agent so terminals and developer tools can '
          'request SSH key access from LumenPass without exporting private '
          'keys.',
        ),
        _SettingsCard(
          children: <Widget>[
            _SettingsToggle(
              title: 'Use the SSH Agent',
              subtitle: 'Turn this on to let approved apps ask LumenPass to '
                  'sign SSH requests with your saved keys.',
              value: enabled,
              onChanged: (value) => onWrite('sshAgentEnabled', value),
              showDivider: enabled,
              trailingBadge: enabled ? 'Running' : 'Off',
            ),
            if (enabled) _SshAgentDetails(settings: settings),
          ],
        ),
        const SizedBox(height: 22),
        const _HintPanel(
          icon: Icons.storage_outlined,
          title: 'Kept in the main window',
          body: 'Backup scheduling and vault maintenance tools need the '
              'decrypted vault, so they stay in the main window.',
        ),
      ],
    );
  }
}

/// Live SSH Agent details: config status plus the socket path to copy.
class _SshAgentDetails extends StatefulWidget {
  const _SshAgentDetails({required this.settings});

  final _SettingsSnapshot settings;

  @override
  State<_SshAgentDetails> createState() => _SshAgentDetailsState();
}

class _SshAgentDetailsState extends State<_SshAgentDetails> {
  bool _copied = false;
  Timer? _copyTimer;

  @override
  void dispose() {
    _copyTimer?.cancel();
    super.dispose();
  }

  Future<void> _copySocketPath() async {
    final path = widget.settings.sshAgentSocketPath;
    if (path.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    setState(() => _copied = true);
    _copyTimer?.cancel();
    _copyTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String text, Color color) =
        switch (widget.settings.sshAgentConfigStatus) {
      'configured' => (
          Icons.check_circle_outline,
          'SSH config: configured',
          DcColors.tealOnLight,
        ),
      'needsAttention' => (
          Icons.error_outline,
          'SSH config: needs attention',
          DcColors.redOnLight,
        ),
      _ => (
          Icons.info_outline,
          'SSH config: checking…',
          DcColors.sidebarMuted,
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.settings.sshAgentSocketPath.isNotEmpty)
          _SocketPathWell(
            path: widget.settings.sshAgentSocketPath,
            copied: _copied,
            onCopy: _copySocketPath,
          ),
      ],
    );
  }
}

class _SocketPathWell extends StatelessWidget {
  const _SocketPathWell({
    required this.path,
    required this.copied,
    required this.onCopy,
  });

  final String path;
  final bool copied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: DcColors.lightInset,
        borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
        border: Border.all(color: DcColors.sidebarLine),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SelectableText(
              path,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.4,
                fontFamily: 'Menlo',
                color: DcColors.sidebarMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onCopy,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 26),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              foregroundColor: DcColors.selection,
            ),
            child: Text(
              copied ? 'Copied' : 'Copy',
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutPane extends StatelessWidget {
  const _AboutPane();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _AboutHero(),
        const SizedBox(height: 20),
        const _GroupLabel('Release'),
        _SettingsCard(
          children: <Widget>[
            _AboutFactRow(
              label: 'Author',
              value: _kAuthor,
            ),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.data?.version ?? '—';
                final build = snapshot.data?.buildNumber ?? '—';
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _AboutFactRow(label: 'Version', value: version),
                    _AboutFactRow(
                      label: 'Build',
                      value: build,
                      showDivider: false,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _GroupLabel('Links'),
        _SettingsCard(
          children: <Widget>[
            _AboutLinkRow(
              icon: Icons.code_rounded,
              title: 'GitHub repository',
              subtitle: 'github.com/lumenpass/lumenpass',
              url: _kRepositoryUrl,
            ),
            _AboutLinkRow(
              icon: Icons.verified_user_outlined,
              title: 'License',
              subtitle: 'Apache License 2.0',
              url: _kLicenseUrl,
            ),
            _AboutLinkRow(
              icon: Icons.public_rounded,
              title: 'Website',
              subtitle: 'lumenpass.app',
              url: _kWebsiteUrl,
              showDivider: false,
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _GroupLabel('License agreement'),
        const _LicenseSummary(),
        const SizedBox(height: 20),
        const _GroupLabel('Platform'),
        const _PlatformSection(),
      ],
    );
  }
}

const String _kAuthor = 'TranTech Studio';
const String _kRepositoryUrl = 'https://github.com/lumenpass/lumenpass';
const String _kLicenseUrl = 'https://www.apache.org/licenses/LICENSE-2.0';
const String _kWebsiteUrl = 'https://www.lumenpass.app';
const String _kDownloadsUrl = 'https://www.lumenpass.app/downloads';

/// Name, one-line description and the "free forever" promise.
class _AboutHero extends StatelessWidget {
  const _AboutHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: DcColors.lightSurface,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        border: Border.all(color: DcColors.sidebarLine),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: DcColors.lightSelectionFill,
                  borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.shield_outlined,
                  size: 22,
                  color: DcColors.selection,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    LumenPassWordmark(
                      fontSize: 17,
                      lumenColor: DcColors.sidebarText,
                      passColor: DcColors.selection,
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Password manager',
                      style: TextStyle(
                        fontSize: 12,
                        color: DcColors.sidebarMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Secure vault for logins, passkeys, cards, secure notes, identities '
            'and SSH keys. Your data stays encrypted in a local KDBX file that '
            'only you can open.',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: DcColors.sidebarMuted,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: DcColors.tealOnLight.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: DcColors.tealOnLight.withValues(alpha: 0.35),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.favorite_border,
                      size: 12,
                      color: DcColors.tealOnLight,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Free forever',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: DcColors.tealOnLight,
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                'No account required · no subscription',
                style: TextStyle(
                  fontSize: 10.5,
                  color: DcColors.sidebarMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Label/value row used by the release card.
class _AboutFactRow extends StatelessWidget {
  const _AboutFactRow({
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: DcColors.sidebarLine)),
            )
          : null,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: DcColors.sidebarMuted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: DcColors.sidebarText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Clickable row that opens an external URL.
class _AboutLinkRow extends StatelessWidget {
  const _AboutLinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String url;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: DcColors.sidebarLine)),
            )
          : null,
      child: _AboutLinkButton(
        onPressed: () => _openExternal(url),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 16, color: DcColors.sidebarMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: DcColors.sidebarText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: DcColors.sidebarMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.open_in_new,
                size: 14,
                color: DcColors.selection,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ink response wrapper that keeps the row padding outside the ripple.
class _AboutLinkButton extends StatelessWidget {
  const _AboutLinkButton({required this.onPressed, required this.child});

  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
      child: child,
    );
  }
}

/// Plain-language summary of the Apache-2.0 terms.
class _LicenseSummary extends StatelessWidget {
  const _LicenseSummary();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 15),
      decoration: BoxDecoration(
        color: DcColors.lightInset,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        border: Border.all(color: DcColors.sidebarLine),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.verified_user_outlined,
                size: 15,
                color: DcColors.selection,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Apache License 2.0',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: DcColors.sidebarText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'LumenPass is free to use for personal and commercial work, with '
            'no subscription, feature gates or item limits. The source code is '
            'public: you may read, modify and redistribute it, including in '
            'closed-source products, as long as the license and copyright '
            'notices are kept and changed files are marked.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: DcColors.sidebarMuted,
            ),
          ),
          const SizedBox(height: 9),
          GestureDetector(
            onTap: () => _openExternal(_kLicenseUrl),
            child: const Text(
              'Read the full license',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: DcColors.selection,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Current build target plus download hints for the other platforms.
class _PlatformSection extends StatelessWidget {
  const _PlatformSection();

  @override
  Widget build(BuildContext context) {
    final current = _currentPlatform();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SettingsCard(
          children: <Widget>[
            _AboutFactRow(
              label: 'Running on',
              value: current,
              showDivider: false,
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'LumenPass also runs on the platforms below. Browser extensions '
          'share the same encrypted vault with the desktop app.',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.5,
            color: DcColors.sidebarMuted,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final option in _kOtherPlatforms)
              _PlatformChip(
                icon: option.$1,
                label: option.$2,
                current: option.$2 == current,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _openExternal(_kDownloadsUrl),
            icon: const Icon(Icons.download_rounded, size: 15),
            label: const Text('Get LumenPass for your platform'),
            style: OutlinedButton.styleFrom(
              foregroundColor: DcColors.sidebarText,
              backgroundColor: DcColors.lightSurface,
              side: const BorderSide(color: DcColors.lightLineStrong),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _currentPlatform() {
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }

  static const List<(IconData, String)> _kOtherPlatforms = <(IconData, String)>[
    (Icons.laptop_mac_rounded, 'macOS'),
    (Icons.desktop_windows_rounded, 'Windows'),
    (Icons.computer_rounded, 'Linux'),
    (Icons.extension_rounded, 'Browser extension'),
  ];
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({
    required this.icon,
    required this.label,
    required this.current,
  });

  final IconData icon;
  final String label;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final Color background =
        current ? DcColors.lightSelectionFill : DcColors.lightSurface;
    final Color border =
        current ? DcColors.selection : DcColors.lightLineStrong;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: 14,
            color: current ? DcColors.selection : DcColors.sidebarMuted,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: current ? FontWeight.w700 : FontWeight.w500,
              color: current ? DcColors.selection : DcColors.sidebarText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens [url] in the system browser, ignoring malformed input.
Future<void> _openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // No handler available: the link simply does nothing.
  }
}

// ── Shared building blocks ────────────────────────────────────────────────

class _PaneIntro extends StatelessWidget {
  const _PaneIntro(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          height: 1.45,
          color: DcColors.sidebarMuted,
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: DcMetrics.sectionLabelSize,
          letterSpacing: DcMetrics.sectionLabelTracking,
          fontWeight: FontWeight.w700,
          color: DcColors.sidebarMuted,
        ),
      ),
    );
  }
}

/// Rows grouped in one bordered well, separated by hairlines.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DcColors.lightSurface,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        border: Border.all(color: DcColors.sidebarLine),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _SettingsToggle extends StatelessWidget {
  const _SettingsToggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.showDivider = true,
    this.trailingBadge,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;
  final String? trailingBadge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: showDivider
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: DcColors.sidebarLine)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              // The content pane scrolls, so the axis is unbounded: a `max`
              // Column would try to occupy infinite height and blow the Row
              // up (red error screen). Shrink-wrap instead.
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: DcColors.sidebarText,
                        ),
                      ),
                    ),
                    if (trailingBadge != null) ...<Widget>[
                      const SizedBox(width: 8),
                      _StatusPill(
                        label: trailingBadge!,
                        active: value,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: DcColors.sidebarMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch.adaptive(
            value: value,
            activeTrackColor: DcColors.selection,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active ? DcColors.tealOnLight : DcColors.lightInset,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: active ? Colors.white : DcColors.sidebarMuted,
        ),
      ),
    );
  }
}

/// Single-select chip row for an option list.
class _ChipGroup<T> extends StatelessWidget {
  const _ChipGroup({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(String, T)> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final option in options)
          _Chip(
            label: option.$1,
            selected: option.$2 == selected,
            onTap: () => onSelected(option.$2),
          ),
      ],
    );
  }
}

class _Chip extends StatefulWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? DcColors.selection
                : _hovered
                    ? DcColors.lightSelectionFill
                    : DcColors.lightSurface,
            borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
            border: Border.all(
              color: selected ? DcColors.selection : DcColors.lightLineStrong,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? Colors.white : DcColors.sidebarText,
            ),
          ),
        ),
      ),
    );
  }
}

/// Informational panel pointing the user back to the main window.
class _HintPanel extends StatelessWidget {
  const _HintPanel({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: DcColors.lightInset,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        border: Border.all(color: DcColors.sidebarLine),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 15, color: DcColors.tealOnLight),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: DcColors.sidebarText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: DcColors.sidebarMuted,
            ),
          ),
        ],
      ),
    );
  }
}
