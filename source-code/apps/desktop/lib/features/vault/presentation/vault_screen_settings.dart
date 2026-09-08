part of 'vault_screen.dart';

const Color _settingsOverlayTint = Color(0x99F8FAFC);
const Color _settingsPanelBackground = Colors.white;
const Color _settingsSidebarBackground = Color(0xFFFDFEFF);
const Color _settingsDividerColor = Color(0xFFE6EBF2);
const Color _settingsSelectedBlue = Color(0xFF1976F3);
const Color _settingsTextPrimary = Color(0xFF252B35);
const Color _settingsTextSecondary = Color(0xFF8D9198);
const Color _settingsFieldBorder = Color(0xFFE3E6EB);
const Color _settingsActiveItemBackground = Color(0xFF0A3B48);

enum _SettingsSectionId {
  general,
  appearance,
  security,
  cardSecurity,
  backup,
  developer,
  experiment,

  advanced,
  about,
}

enum _AppearanceTextSizeOption {
  smallerMinus,
  smaller,
  defaultSize,
  larger,
  largerPlus,
}

enum _VaultDomainSetting { defaultMatchDetection, baseDomain, subdomain }

enum _VaultAutoLockTimeout {
  fifteenMinutes,
  thirtyMinutes,
  oneHour,
  fourHours,
  eightHours,
  twentyFourHours,
  never,
}

enum _VaultClipboardClearOption {
  thirtySeconds,
  sixtySeconds,
  ninetySeconds,
  never,
}

enum _BackupRetentionDays {
  threeDays,
  sevenDays,
  twentyOneDays,
  thirtyDays;

  /// The retention window in days that this option represents.
  int get days => switch (this) {
        _BackupRetentionDays.threeDays => 3,
        _BackupRetentionDays.sevenDays => 7,
        _BackupRetentionDays.twentyOneDays => 21,
        _BackupRetentionDays.thirtyDays => 30,
      };

  /// Maps a persisted day count back to the closest dropdown option so the UI
  /// reflects the stored value on launch. Unknown values fall back to 7 days.
  static _BackupRetentionDays fromDays(int days) {
    return _BackupRetentionDays.values.firstWhere(
      (option) => option.days == days,
      orElse: () => _BackupRetentionDays.sevenDays,
    );
  }
}

class _SettingsSectionItem {
  const _SettingsSectionItem({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.imageAsset,
  });

  final _SettingsSectionId id;
  final String label;
  final String subtitle;
  final String imageAsset;
}

String _settingsCategoryAsset(int imageId) {
  return 'assets/images/categories/$imageId.png';
}

final List<_SettingsSectionItem> _primarySettingsSections =
    <_SettingsSectionItem>[
  _SettingsSectionItem(
    id: _SettingsSectionId.general,
    label: 'General',
    subtitle: 'The common application settings',
    imageAsset: _settingsCategoryAsset(8),
  ),
  _SettingsSectionItem(
    id: _SettingsSectionId.appearance,
    label: 'Appearance',
    subtitle: 'Visual preferences and interface behavior',
    imageAsset: _settingsCategoryAsset(44),
  ),
  _SettingsSectionItem(
    id: _SettingsSectionId.security,
    label: 'Vault',
    subtitle: 'Unlock, autofill, clipboard, and vault behavior',
    imageAsset: _settingsCategoryAsset(58),
  ),
  _SettingsSectionItem(
    id: _SettingsSectionId.cardSecurity,
    label: 'Security',
    subtitle: 'Protect sensitive data shown in item views',
    imageAsset: _settingsCategoryAsset(58),
  ),
  _SettingsSectionItem(
    id: _SettingsSectionId.backup,
    label: 'Backup',
    subtitle: 'Automatic backups and restore controls',
    imageAsset: _settingsCategoryAsset(64),
  ),
  _SettingsSectionItem(
    id: _SettingsSectionId.developer,
    label: 'SSH Agent',
    subtitle: 'Manage SSH key access for terminals and apps',
    imageAsset: _settingsCategoryAsset(239),
  ),
  _SettingsSectionItem(
    id: _SettingsSectionId.experiment,
    label: 'Experiment',
    subtitle: 'Safe tools for vault data maintenance',
    imageAsset: _settingsCategoryAsset(224),
  ),
];

final List<_SettingsSectionItem> _secondarySettingsSections =
    <_SettingsSectionItem>[
  _SettingsSectionItem(
    id: _SettingsSectionId.advanced,
    label: 'Help',
    subtitle: 'Quick contact form and support options',
    imageAsset: _settingsCategoryAsset(228),
  ),
  _SettingsSectionItem(
    id: _SettingsSectionId.about,
    label: 'About',
    subtitle: 'App version, credits, and release information',
    imageAsset: _settingsCategoryAsset(237),
  ),
];

class _AppearanceFontOption {
  const _AppearanceFontOption({
    required this.label,
    required this.family,
    required this.caption,
  });

  final String label;
  final String family;
  final String caption;
}

const List<_AppearanceFontOption> _appearanceFontOptions =
    <_AppearanceFontOption>[
  _AppearanceFontOption(
    label: 'Inter',
    family: 'Inter',
    caption: 'Current default',
  ),
  _AppearanceFontOption(
    label: 'SF Pro Text',
    family: 'SF Pro Text',
    caption: 'Crisp on macOS',
  ),
  _AppearanceFontOption(
    label: 'Segoe UI',
    family: 'Segoe UI',
    caption: 'Comfortable on Windows',
  ),
  _AppearanceFontOption(
    label: 'Roboto',
    family: 'Roboto',
    caption: 'Material-inspired',
  ),
];

/// Payload bubbled up from the Backup settings pane when the user has
/// explicitly confirmed they want to restore [backup]. Restore is a
/// file-replacement operation, so no password / keyfile is needed at this
/// stage — the existing unlock screen handles credentials uniformly after
/// the restored bytes are on disk.
class BackupRestoreRequest {
  const BackupRestoreRequest({required this.backup});

  final LocalBackupInfo backup;
}

typedef BackupRestoreRequestHandler = Future<void> Function(
  BackupRestoreRequest request,
);

class _SettingsOverlay extends StatefulWidget {
  const _SettingsOverlay({
    required this.onClose,
    this.onRequestRestore,
    this.initialSection = _SettingsSectionId.general,
  });

  final VoidCallback onClose;
  final BackupRestoreRequestHandler? onRequestRestore;
  final _SettingsSectionId initialSection;

  @override
  State<_SettingsOverlay> createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends State<_SettingsOverlay> {
  late _SettingsSectionId _selectedSection;

  @override
  void initState() {
    super.initState();
    _selectedSection = widget.initialSection;
  }

  @override
  void didUpdateWidget(covariant _SettingsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      setState(() => _selectedSection = widget.initialSection);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onClose,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            color: _settingsOverlayTint,
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {},
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final modalWidth = math.min(860.0, constraints.maxWidth - 40);
                  final modalHeight =
                      math.min(620.0, constraints.maxHeight - 40);

                  final sectionItem = <_SettingsSectionItem>[
                    ..._primarySettingsSections,
                    ..._secondarySettingsSections,
                  ].firstWhere((item) => item.id == _selectedSection);

                  return Container(
                    width: modalWidth,
                    height: modalHeight,
                    decoration: BoxDecoration(
                      color: _settingsPanelBackground,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _settingsDividerColor),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x160F172A),
                          blurRadius: 36,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      children: <Widget>[
                        _SettingsContentHeader(
                          section: sectionItem,
                          onClose: widget.onClose,
                        ),
                        Expanded(
                          child: Row(
                            children: <Widget>[
                              SizedBox(
                                width: 250,
                                child: _SettingsSidebar(
                                  selectedSection: _selectedSection,
                                  onSectionSelected:
                                      (_SettingsSectionId sectionId) {
                                    setState(
                                        () => _selectedSection = sectionId);
                                  },
                                ),
                              ),
                              const VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: _settingsDividerColor,
                              ),
                              Expanded(
                                child: _SettingsContentPane(
                                  section: _selectedSection,
                                  onRequestRestore: widget.onRequestRestore,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({
    required this.selectedSection,
    required this.onSectionSelected,
  });

  final _SettingsSectionId selectedSection;
  final ValueChanged<_SettingsSectionId> onSectionSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _settingsSidebarBackground,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(14),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final section in _primarySettingsSections) ...<Widget>[
                      _SettingsSidebarItem(
                        section: section,
                        selected: selectedSection == section.id,
                        onTap: () => onSectionSelected(section.id),
                      ),
                      const SizedBox(height: 2),
                    ],
                    const SizedBox(height: 6),
                    const Divider(
                      thickness: 1,
                      color: _settingsDividerColor,
                      height: 1,
                    ),
                    const SizedBox(height: 8),
                    for (final section
                        in _secondarySettingsSections) ...<Widget>[
                      _SettingsSidebarItem(
                        section: section,
                        selected: selectedSection == section.id,
                        onTap: () => onSectionSelected(section.id),
                      ),
                      const SizedBox(height: 2),
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

class _SettingsSidebarItem extends StatelessWidget {
  const _SettingsSidebarItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final _SettingsSectionItem section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color:
                selected ? _settingsActiveItemBackground : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Image.asset(
                    section.imageAsset,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  section.label,
                  style: _text(
                    14,
                    selected ? Colors.white : _settingsTextPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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

class _SettingsContentPane extends StatelessWidget {
  const _SettingsContentPane({
    required this.section,
    this.onRequestRestore,
  });

  final _SettingsSectionId section;
  final BackupRestoreRequestHandler? onRequestRestore;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (section == _SettingsSectionId.general) {
      content = const _GeneralSettingsContent();
    } else if (section == _SettingsSectionId.appearance) {
      content = const _AppearanceSettingsContent();
    } else if (section == _SettingsSectionId.security) {
      content = const _VaultSettingsContent();
    } else if (section == _SettingsSectionId.cardSecurity) {
      content = const _CardSecuritySettingsContent();
    } else if (section == _SettingsSectionId.backup) {
      content = _BackupSettingsContent(onRequestRestore: onRequestRestore);
    } else if (section == _SettingsSectionId.developer) {
      content = const _SshAgentSettingsContent();
    } else if (section == _SettingsSectionId.experiment) {
      content = const _ExperimentSettingsContent();
    } else if (section == _SettingsSectionId.advanced) {
      content = const _HelpSettingsContent();
    } else if (section == _SettingsSectionId.about) {
      content = const _AboutSettingsContent();
    } else {
      content = _SettingsPlaceholderContent(section: section);
    }

    return ColoredBox(
      color: Colors.white,
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 18, 24, 24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _SettingsContentHeader extends StatelessWidget {
  const _SettingsContentHeader({
    required this.section,
    required this.onClose,
  });

  final _SettingsSectionItem section;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 18, 8),
      decoration: const BoxDecoration(
        color: _settingsActiveItemBackground,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              text: TextSpan(
                children: <TextSpan>[
                  TextSpan(
                    text: section.label,
                    style: _text(
                      14,
                      Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: '  ·  ${section.subtitle}',
                    style: _text(
                      12,
                      Colors.white.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  TablerIcons.x,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneralSettingsContent extends ConsumerStatefulWidget {
  const _GeneralSettingsContent();

  @override
  ConsumerState<_GeneralSettingsContent> createState() =>
      _GeneralSettingsContentState();
}

class _GeneralSettingsContentState
    extends ConsumerState<_GeneralSettingsContent> {
  Future<void> _onHideDockChanged(bool value) async {
    ref.read(hideDockIconProvider.notifier).state = value;
    final storage = ref.read(localStorageProvider);
    final container = ProviderScope.containerOf(context);
    await storage.write(key: generalHideDockIconKey, value: value.toString());
    if (!mounted) return;
    await applyMacOSDockVisibilityPreference(container);
  }

  Future<void> _onAutostartChanged(bool value) async {
    ref.read(autostartWithSystemProvider.notifier).state = value;
    final storage = ref.read(localStorageProvider);
    final container = ProviderScope.containerOf(context);
    await storage.write(
      key: generalAutostartWithSystemKey,
      value: value.toString(),
    );
    if (!mounted) return;
    await applyMacOSAutostartPreference(container);

    // Start-minimized is a child behavior of autostart; if autostart is
    // turned off, disabling it here keeps the UI and native state honest.
    if (!value && ref.read(startMinimizedProvider)) {
      await _onStartMinimizedChanged(false);
    }
  }

  Future<void> _onStartMinimizedChanged(bool value) async {
    ref.read(startMinimizedProvider.notifier).state = value;
    final storage = ref.read(localStorageProvider);
    final container = ProviderScope.containerOf(context);
    await storage.write(
      key: generalStartMinimizedKey,
      value: value.toString(),
    );
    if (!mounted) return;
    await applyMacOSStartMinimizedPreference(container);
  }

  @override
  Widget build(BuildContext context) {
    final hideOnDock = ref.watch(hideDockIconProvider);
    final autostart = ref.watch(autostartWithSystemProvider);
    final startMinimized = ref.watch(startMinimizedProvider);
    return Column(
      key: const ValueKey<String>('general-settings'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (Platform.isMacOS) ...[
          _SettingsToggleRow(
            label: 'Hide LumenPass on the dock',
            value: hideOnDock,
            onChanged: _onHideDockChanged,
          ),
          const SizedBox(height: 4),
        ],
        _SettingsToggleRow(
          label: 'Autostart with system',
          value: autostart,
          onChanged: _onAutostartChanged,
        ),
        const SizedBox(height: 4),
        _SettingsToggleRow(
          label: 'Start minimized',
          value: autostart && startMinimized,
          enabled: autostart,
          onChanged: _onStartMinimizedChanged,
        ),
        const SizedBox(height: 18),
        const _SettingsPaneHeading(label: 'Application Shortcuts'),
        const SizedBox(height: 10),
        _SettingsShortcutCaptureRow(
          label: 'Open spotlight search',
          initialValue: ShortcutData.defaultSpotlight.display,
          shortcutId: ShortcutId.spotlight,
        ),
        const SizedBox(height: 8),
        _SettingsShortcutCaptureRow(
          label: 'Lock Current Vault',
          initialValue: ShortcutData.defaultLockVault.display,
          shortcutId: ShortcutId.lockVault,
        ),
      ],
    );
  }
}

class _AppearanceSettingsContent extends ConsumerStatefulWidget {
  const _AppearanceSettingsContent();

  @override
  ConsumerState<_AppearanceSettingsContent> createState() =>
      _AppearanceSettingsContentState();
}

class _AppearanceSettingsContentState
    extends ConsumerState<_AppearanceSettingsContent> {
  late _AppearanceTextSizeOption _textSize;
  late _AppearanceFontOption _font;
  String _dockIconAsset = dockIconDefaultAsset;

  @override
  void initState() {
    super.initState();
    _textSize = _textSizeFromDelta(ref.read(appearanceTextSizeDeltaProvider));
    _font = _fontOptionFromFamily(ref.read(appearanceFontFamilyProvider));
    _loadDockIconPreference();
  }

  _AppearanceTextSizeOption _textSizeFromDelta(int delta) {
    switch (delta) {
      case -2:
        return _AppearanceTextSizeOption.smallerMinus;
      case -1:
        return _AppearanceTextSizeOption.smaller;
      case 1:
        return _AppearanceTextSizeOption.larger;
      case 2:
        return _AppearanceTextSizeOption.largerPlus;
      default:
        return _AppearanceTextSizeOption.defaultSize;
    }
  }

  int _deltaFromTextSize(_AppearanceTextSizeOption option) {
    switch (option) {
      case _AppearanceTextSizeOption.smallerMinus:
        return -2;
      case _AppearanceTextSizeOption.smaller:
        return -1;
      case _AppearanceTextSizeOption.defaultSize:
        return 0;
      case _AppearanceTextSizeOption.larger:
        return 1;
      case _AppearanceTextSizeOption.largerPlus:
        return 2;
    }
  }

  _AppearanceFontOption _fontOptionFromFamily(String family) {
    return _appearanceFontOptions.firstWhere(
      (f) => f.family == family,
      orElse: () => _appearanceFontOptions.first,
    );
  }

  Future<void> _loadDockIconPreference() async {
    final storage = ref.read(localStorageProvider);
    final savedAsset = await storage.read(key: dockIconPreferenceKey);
    final resolvedAsset =
        dockIconOptions.any((option) => option.assetPath == savedAsset)
            ? savedAsset!
            : dockIconDefaultAsset;
    if (!mounted) {
      return;
    }
    setState(() => _dockIconAsset = resolvedAsset);
  }

  Future<void> _selectDockIcon(String assetPath) async {
    if (_dockIconAsset == assetPath) {
      return;
    }
    setState(() => _dockIconAsset = assetPath);
    final storage = ref.read(localStorageProvider);
    await storage.write(key: dockIconPreferenceKey, value: assetPath);
  }

  Future<void> _selectTextSize(_AppearanceTextSizeOption option) async {
    if (_textSize == option) return;
    setState(() => _textSize = option);
    final delta = _deltaFromTextSize(option);
    ref.read(appearanceTextSizeDeltaProvider.notifier).state = delta;
    final storage = ref.read(localStorageProvider);
    await storage.write(
      key: appearanceTextSizeDeltaKey,
      value: delta.toString(),
    );
  }

  Future<void> _selectFont(_AppearanceFontOption option) async {
    if (_font == option) return;
    setState(() => _font = option);
    ref.read(appearanceFontFamilyProvider.notifier).state = option.family;
    final storage = ref.read(localStorageProvider);
    await storage.write(
      key: appearanceFontFamilyKey,
      value: option.family,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('appearance-settings'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SettingsPaneHeading(label: 'Display & Reading'),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Choose the look and reading comfort level that feels best for your vault workspace.',
            style: _text(
              12,
              _settingsTextSecondary,
              fontWeight: FontWeight.w400,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _settingsDividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SettingsSectionBlock(
                title: 'Text size',
                subtitle:
                    'Fine-tune the interface scale for denser layouts or easier reading.',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _AppearanceTextSizeOption.values
                      .map(
                        (option) => _SettingsChoiceChip(
                          label: _appearanceTextSizeLabel(option),
                          selected: _textSize == option,
                          onTap: () => _selectTextSize(option),
                        ),
                      )
                      .toList(),
                ),
              ),
              const Divider(height: 28, color: _settingsDividerColor),
              _SettingsSectionBlock(
                title: 'Font',
                subtitle:
                    'Pick from the available interface fonts. We can bundle more custom fonts later if you want.',
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _appearanceFontOptions
                      .map(
                        (option) => _AppearanceFontCard(
                          option: option,
                          selected: _font == option,
                          onTap: () => _selectFont(option),
                        ),
                      )
                      .toList(),
                ),
              ),
              const Divider(height: 28, color: _settingsDividerColor),
              _SettingsSectionBlock(
                title: 'Dock Icons',
                subtitle: 'Choose a menu bar lock icon.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: dockIconOptions
                          .map(
                            (option) => _DockIconCard(
                              option: option,
                              selected: _dockIconAsset == option.assetPath,
                              onTap: () => _selectDockIcon(option.assetPath),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'The icon will be updated in next app restart',
                      style: _text(
                        11,
                        _settingsTextSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VaultSettingsContent extends ConsumerStatefulWidget {
  const _VaultSettingsContent();

  @override
  ConsumerState<_VaultSettingsContent> createState() =>
      _VaultSettingsContentState();
}

class _VaultSettingsContentState extends ConsumerState<_VaultSettingsContent> {
  bool _biometricUnlockEnabled = false;
  bool _pinCodeUnlockEnabled = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _domainSetting =
        _domainSettingFromString(ref.read(vaultDomainSettingProvider));
    _autoLockTimeout =
        _minutesToAutoLockTimeout(ref.read(vaultAutoLockMinutesProvider));
    _clipboardClearOption =
        _secondsToClipboardClear(ref.read(vaultClipboardClearSecondsProvider));
    _autoFetchItemIcon = ref.read(vaultAutoFetchItemIconProvider);
    _disabledAutofillDomains = pruneDisabledAutofillDomains(
      ref.read(vaultDisabledAutofillDomainsProvider),
    );
    _loadPreferences();
  }

  _VaultDomainSetting _domainSetting =
      _VaultDomainSetting.defaultMatchDetection;
  _VaultAutoLockTimeout _autoLockTimeout = _VaultAutoLockTimeout.thirtyMinutes;
  _VaultClipboardClearOption _clipboardClearOption =
      _VaultClipboardClearOption.sixtySeconds;
  bool _autoFetchItemIcon = true;
  List<DisabledAutofillDomain> _disabledAutofillDomains = const [];

  Future<void> _loadPreferences() async {
    final vaultPath = ref.read(activeDatabaseProvider)?.path;
    if (vaultPath == null || !mounted) return;
    final svc = ref.read(vaultUnlockServiceProvider);
    final bio = ref.read(biometricAuthServiceProvider);
    final bioEnabled = await svc.isBiometricEnabled(vaultPath);
    final pinEnabled = await svc.isPinEnabled(vaultPath);
    final bioAvailable = await bio.isAvailable();
    if (!mounted) return;
    setState(() {
      _biometricUnlockEnabled = bioEnabled;
      _pinCodeUnlockEnabled = pinEnabled;
      _biometricAvailable = bioAvailable;
    });
  }

  String _domainSettingToString(_VaultDomainSetting setting) {
    switch (setting) {
      case _VaultDomainSetting.defaultMatchDetection:
        return 'default';
      case _VaultDomainSetting.baseDomain:
        return 'baseDomain';
      case _VaultDomainSetting.subdomain:
        return 'subdomain';
    }
  }

  _VaultDomainSetting _domainSettingFromString(String value) {
    switch (value) {
      case 'baseDomain':
        return _VaultDomainSetting.baseDomain;
      case 'subdomain':
        return _VaultDomainSetting.subdomain;
      default:
        return _VaultDomainSetting.defaultMatchDetection;
    }
  }

  Future<void> _selectDomainSetting(_VaultDomainSetting setting) async {
    if (_domainSetting == setting) return;
    setState(() => _domainSetting = setting);
    final stringValue = _domainSettingToString(setting);
    ref.read(vaultDomainSettingProvider.notifier).state = stringValue;
    final storage = ref.read(localStorageProvider);
    await storage.write(key: vaultDomainSettingKey, value: stringValue);
  }

  Future<void> _removeDisabledAutofillDomain(String domain) async {
    final normalized = normalizeDisabledAutofillDomain(domain);
    final next = pruneDisabledAutofillDomains(
      _disabledAutofillDomains
          .where((item) => item.domain != normalized)
          .toList(),
    );
    setState(() => _disabledAutofillDomains = next);
    ref.read(vaultDisabledAutofillDomainsProvider.notifier).state = next;
    final storage = ref.read(localStorageProvider);
    await storage.write(
      key: vaultDisabledAutofillDomainsKey,
      value: encodeDisabledAutofillDomains(next),
    );
  }

  String _disabledAutofillDomainExpiryLabel(DisabledAutofillDomain item) {
    final expiresAt = item.expiresAt;
    if (expiresAt == null) return 'Permanent';
    final dt = DateTime.fromMillisecondsSinceEpoch(expiresAt).toLocal();
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return 'Until ${dt.month}/${dt.day} $hour:$minute';
  }

  int? _autoLockTimeoutToMinutes(_VaultAutoLockTimeout t) {
    switch (t) {
      case _VaultAutoLockTimeout.fifteenMinutes:
        return 15;
      case _VaultAutoLockTimeout.thirtyMinutes:
        return 30;
      case _VaultAutoLockTimeout.oneHour:
        return 60;
      case _VaultAutoLockTimeout.fourHours:
        return 240;
      case _VaultAutoLockTimeout.eightHours:
        return 480;
      case _VaultAutoLockTimeout.twentyFourHours:
        return 1440;
      case _VaultAutoLockTimeout.never:
        return null;
    }
  }

  _VaultAutoLockTimeout _minutesToAutoLockTimeout(int? minutes) {
    switch (minutes) {
      case 15:
        return _VaultAutoLockTimeout.fifteenMinutes;
      case 30:
        return _VaultAutoLockTimeout.thirtyMinutes;
      case 60:
        return _VaultAutoLockTimeout.oneHour;
      case 240:
        return _VaultAutoLockTimeout.fourHours;
      case 480:
        return _VaultAutoLockTimeout.eightHours;
      case 1440:
        return _VaultAutoLockTimeout.twentyFourHours;
      default:
        return _VaultAutoLockTimeout.never;
    }
  }

  int? _clipboardClearToSeconds(_VaultClipboardClearOption o) {
    switch (o) {
      case _VaultClipboardClearOption.thirtySeconds:
        return 30;
      case _VaultClipboardClearOption.sixtySeconds:
        return 60;
      case _VaultClipboardClearOption.ninetySeconds:
        return 90;
      case _VaultClipboardClearOption.never:
        return null;
    }
  }

  _VaultClipboardClearOption _secondsToClipboardClear(int? seconds) {
    switch (seconds) {
      case 30:
        return _VaultClipboardClearOption.thirtySeconds;
      case 60:
        return _VaultClipboardClearOption.sixtySeconds;
      case 90:
        return _VaultClipboardClearOption.ninetySeconds;
      default:
        return _VaultClipboardClearOption.never;
    }
  }

  Future<void> _selectAutoLockTimeout(_VaultAutoLockTimeout timeout) async {
    if (_autoLockTimeout == timeout) return;
    setState(() => _autoLockTimeout = timeout);
    final minutes = _autoLockTimeoutToMinutes(timeout);
    ref.read(vaultAutoLockMinutesProvider.notifier).state = minutes;
    final storage = ref.read(localStorageProvider);
    await storage.write(
      key: vaultAutoLockMinutesKey,
      value: minutes == null ? 'never' : minutes.toString(),
    );
  }

  Future<void> _selectClipboardClear(_VaultClipboardClearOption option) async {
    if (_clipboardClearOption == option) return;
    setState(() => _clipboardClearOption = option);
    final seconds = _clipboardClearToSeconds(option);
    ref.read(vaultClipboardClearSecondsProvider.notifier).state = seconds;
    final storage = ref.read(localStorageProvider);
    await storage.write(
      key: vaultClipboardClearSecondsKey,
      value: seconds == null ? 'never' : seconds.toString(),
    );
  }

  Future<void> _selectAutoFetchItemIcon(bool value) async {
    setState(() => _autoFetchItemIcon = value);
    ref.read(vaultAutoFetchItemIconProvider.notifier).state = value;
    final storage = ref.read(localStorageProvider);
    await storage.write(
        key: vaultAutoFetchItemIconKey, value: value.toString());
  }

  Future<String?> _getOrAskPassword() async {
    final cached = ref.read(cachedMasterPasswordProvider);
    if (cached != null && cached.isNotEmpty) return cached;
    return showDialog<String>(
      context: context,
      builder: (_) => const _PasswordConfirmDialog(),
    );
  }

  Future<void> _enableBiometric() async {
    if (!_biometricAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Platform.isWindows
                ? 'Windows Hello is not available on this device.'
                : 'Biometric authentication is not available on this device.',
          ),
        ),
      );
      return;
    }
    final password = await _getOrAskPassword();
    if (password == null || password.isEmpty || !mounted) return;
    final vaultPath = ref.read(activeDatabaseProvider)?.path;
    if (vaultPath == null) return;
    final svc = ref.read(vaultUnlockServiceProvider);
    await svc.saveBiometricPassword(vaultPath, password);
    await svc.setBiometricEnabled(vaultPath, true);
    if (!mounted) return;
    setState(() => _biometricUnlockEnabled = true);
  }

  Future<void> _disableBiometric() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DisableUnlockMethodDialog(
        method: Platform.isWindows ? 'Windows Hello' : 'Biometric',
        description: Platform.isWindows
            ? 'Windows Hello unlock will be removed from this vault. You can re-enable it at any time.'
            : 'Biometric unlock will be removed from this vault. You can re-enable it at any time.',
      ),
    );
    if (confirmed != true || !mounted) return;
    final vaultPath = ref.read(activeDatabaseProvider)?.path;
    if (vaultPath == null) return;
    await ref.read(vaultUnlockServiceProvider).clearBiometricData(vaultPath);
    if (!mounted) return;
    setState(() => _biometricUnlockEnabled = false);
  }

  Future<void> _enablePin() async {
    final password = await _getOrAskPassword();
    if (password == null || password.isEmpty || !mounted) return;
    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PinSetupDialog(),
    );
    if (pin == null || !mounted) return;
    final vaultPath = ref.read(activeDatabaseProvider)?.path;
    if (vaultPath == null) return;
    final svc = ref.read(vaultUnlockServiceProvider);
    await svc.setupPin(vaultPath, pin, password);
    await svc.setPinEnabled(vaultPath, true);
    if (!mounted) return;
    setState(() => _pinCodeUnlockEnabled = true);
  }

  Future<void> _disablePin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DisableUnlockMethodDialog(
        method: 'PIN code',
        description:
            'PIN code unlock will be removed from this vault. You can re-enable it at any time.',
      ),
    );
    if (confirmed != true || !mounted) return;
    final vaultPath = ref.read(activeDatabaseProvider)?.path;
    if (vaultPath == null) return;
    await ref.read(vaultUnlockServiceProvider).clearPinData(vaultPath);
    if (!mounted) return;
    setState(() => _pinCodeUnlockEnabled = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('vault-settings'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _SettingsPaneHeading(label: 'Vault Access & Behavior'),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Control how the vault unlocks, matches websites, clears sensitive data, and fills item details.',
            style: _text(
              12,
              _settingsTextSecondary,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Column(
          children: <Widget>[
            _SettingsSurfaceSection(
              child: _SettingsSectionBlock(
                title: 'Unlock vault with',
                subtitle:
                    'Turn on any unlock methods you want to make available on this device.',
                child: Column(
                  children: <Widget>[
                    if (!Platform.isLinux) ...<Widget>[
                      _SettingsInlineToggleCard(
                        title:
                            Platform.isWindows ? 'Windows Hello' : 'Biometric',
                        description: Platform.isWindows
                            ? 'Use Windows Hello for faster access with built-in hardware protection.'
                            : 'Use Face ID, Touch ID, or the device biometric prompt for faster access with built-in hardware protection.',
                        value: _biometricUnlockEnabled,
                        showActiveBadge: _biometricUnlockEnabled,
                        onChanged: (value) =>
                            value ? _enableBiometric() : _disableBiometric(),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _SettingsInlineToggleCard(
                      title: 'PIN code',
                      description: Platform.isWindows
                          ? 'Allow a short device PIN as an alternative unlock method when Windows Hello is unavailable or not preferred.'
                          : 'Allow a short device PIN as an alternative unlock method when biometric hardware is unavailable or not preferred.',
                      value: _pinCodeUnlockEnabled,
                      showActiveBadge: _pinCodeUnlockEnabled,
                      onChanged: (value) =>
                          value ? _enablePin() : _disablePin(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SettingsSurfaceSection(
              child: _SettingsSectionBlock(
                title: 'Autofill',
                subtitle:
                    'Tune when the vault offers credentials and how domain matching should behave.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Domain setting',
                      style: _text(
                        12,
                        _settingsTextPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose how strictly LumenPass decides that a saved item matches the current website.',
                      style: _text(
                        11,
                        _settingsTextSecondary,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ..._VaultDomainSetting.values.map(
                      (setting) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SettingsRadioCard(
                          label: _vaultDomainSettingLabel(setting),
                          description: _vaultDomainSettingDescription(setting),
                          selected: _domainSetting == setting,
                          onTap: () => _selectDomainSetting(setting),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SettingsSurfaceSection(
              child: _SettingsSectionBlock(
                title: 'Disabled domains',
                subtitle:
                    'Sites disabled from the browser extension appear here. Remove a domain to allow autofill again.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (_disabledAutofillDomains.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _settingsDividerColor),
                        ),
                        child: Text(
                          'No disabled domains',
                          style: _text(
                            12,
                            _settingsTextSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    else
                      Column(
                        children: _disabledAutofillDomains
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _settingsDividerColor,
                                    ),
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              item.domain,
                                              style: _text(
                                                12,
                                                _settingsTextPrimary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _disabledAutofillDomainExpiryLabel(
                                                item,
                                              ),
                                              style: _text(
                                                11,
                                                _settingsTextSecondary,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            _removeDisabledAutofillDomain(
                                          item.domain,
                                        ),
                                        style: TextButton.styleFrom(
                                          foregroundColor:
                                              const Color(0xFFB42318),
                                          textStyle: _text(
                                            11,
                                            const Color(0xFFB42318),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        child: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SettingsSurfaceSection(
              child: _SettingsSectionBlock(
                title: 'Auto lock vault',
                subtitle:
                    'Define how long the vault can stay open before it locks itself again.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _VaultAutoLockTimeout.values
                          .map(
                            (timeout) => _SettingsChoiceChip(
                              label: _vaultAutoLockTimeoutLabel(timeout),
                              selected: _autoLockTimeout == timeout,
                              onTap: () => _selectAutoLockTimeout(timeout),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _vaultAutoLockTimeoutDescription(_autoLockTimeout),
                      style: _text(
                        11,
                        _settingsTextSecondary,
                        fontWeight: FontWeight.w400,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SettingsSurfaceSection(
              child: _SettingsSectionBlock(
                title: 'Clipboard',
                subtitle:
                    'Choose how quickly copied passwords and secrets are cleared from the clipboard.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _VaultClipboardClearOption.values
                          .map(
                            (option) => _SettingsChoiceChip(
                              label: _vaultClipboardClearLabel(option),
                              selected: _clipboardClearOption == option,
                              onTap: () => _selectClipboardClear(option),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _vaultClipboardClearDescription(
                        _clipboardClearOption,
                      ),
                      style: _text(
                        11,
                        _settingsTextSecondary,
                        fontWeight: FontWeight.w400,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SettingsSurfaceSection(
              child: _SettingsSectionBlock(
                title: 'Items',
                subtitle:
                    'Control extra item enhancements that can make saved entries feel richer and easier to scan.',
                child: _SettingsInlineToggleCard(
                  title: 'Auto fetch item icon',
                  description:
                      'Fetches the website favicon automatically so saved items show a recognizable icon without manual setup.',
                  value: _autoFetchItemIcon,
                  onChanged: _selectAutoFetchItemIcon,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CardSecuritySettingsContent extends ConsumerWidget {
  const _CardSecuritySettingsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideCardNumber = ref.watch(vaultHideCreditCardNumberProvider);
    return Column(
      key: const ValueKey<String>('card-security-settings'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _SettingsPaneHeading(label: 'Security'),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Control how sensitive item data is displayed across the app.',
            style: _text(
              12,
              _settingsTextSecondary,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SettingsSurfaceSection(
          child: _SettingsSectionBlock(
            title: 'Credit cards',
            subtitle:
                'Hide most of a saved card number when viewing item details. Editing an item always shows the full number.',
            child: _SettingsInlineToggleCard(
              title: 'Hide full credit card number',
              description:
                  'Shows only the first 4 and last 3 digits when viewing items. The middle digits are masked.',
              value: hideCardNumber,
              onChanged: (value) => _setHideCardNumber(ref, value),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _setHideCardNumber(WidgetRef ref, bool value) async {
    ref.read(vaultHideCreditCardNumberProvider.notifier).state = value;
    final storage = ref.read(localStorageProvider);
    await storage.write(
      key: vaultHideCreditCardNumberKey,
      value: value.toString(),
    );
  }
}

class _BackupSettingsContent extends ConsumerStatefulWidget {
  const _BackupSettingsContent({this.onRequestRestore});

  final BackupRestoreRequestHandler? onRequestRestore;

  @override
  ConsumerState<_BackupSettingsContent> createState() =>
      _BackupSettingsContentState();
}

class _BackupSettingsContentState
    extends ConsumerState<_BackupSettingsContent> {
  _BackupRetentionDays _retentionDays = _BackupRetentionDays.sevenDays;
  ProviderSubscription<BackupStatus>? _backupStatusSub;

  @override
  void initState() {
    super.initState();
    _backupStatusSub = ref.listenManual<BackupStatus>(
      backupStatusProvider,
      (prev, next) {
        if (prev == next) return;
        if (!mounted) return;

        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) return;

        switch (next) {
          case BackupStatus.running:
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Creating backup…'),
                duration: Duration(seconds: 2),
              ),
            );
          case BackupStatus.done:
            messenger.showSnackBar(
              const SnackBar(
                content: Text('✓ Backup complete'),
                duration: Duration(seconds: 3),
              ),
            );
          case BackupStatus.error:
            messenger.showSnackBar(
              SnackBar(
                content: const Text('Backup failed'),
                backgroundColor: Colors.red.shade600,
                duration: const Duration(seconds: 4),
              ),
            );
          case BackupStatus.idle:
            break;
        }
      },
    );
  }

  @override
  void dispose() {
    _backupStatusSub?.close();
    _backupStatusSub = null;
    super.dispose();
  }

  Future<void> _openBackupFolder() async {
    try {
      await BackupService.instance.openLocalBackupFolder();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open backup folder: $e')),
      );
    }
  }

  Future<void> _showRestoreModal() async {
    final activeDb = ref.read(activeDatabaseProvider);
    if (activeDb == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open a vault before restoring a backup so the app knows what to overwrite.',
          ),
        ),
      );
      return;
    }
    // Find the matching DatabaseRecord for the active vault.
    final registry = ref.read(databaseRegistryProvider);
    final record = registry.firstWhere(
      (r) => r.databasePath == activeDb.path,
      orElse: () => DatabaseRecord(
        id: '',
        nickname: '',
        databasePath: activeDb.path,
        addedAt: DateTime.now(),
      ),
    );

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RestoreBackupsModal(
        record: record,
        targetVaultPath: activeDb.path,
      ),
    );
    if (!mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(backupEnabledProvider);
    final status = ref.watch(backupStatusProvider);
    final lastTimestamp = ref.watch(backupLastTimestampProvider);
    final nextTimestamp = ref.watch(backupNextTimestampProvider);

    // Keep the dropdown in sync with the persisted retention window so it
    // reflects the stored value on launch and after external changes.
    _retentionDays =
        _BackupRetentionDays.fromDays(ref.watch(backupRetentionDaysProvider));

    return Column(
      key: const ValueKey<String>('backup-settings'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SettingsPaneHeading(label: 'Backup & Restore'),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Protect the current vault with scheduled backups and recover from a previous snapshot when needed.',
            style: _text(
              12,
              _settingsTextSecondary,
              fontWeight: FontWeight.w400,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 20),
        _SettingsSurfaceSection(
          child: _SettingsSectionBlock(
            title: 'Backup',
            subtitle:
                'Control whether the app automatically saves backup copies of the current vault.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SettingsInlineToggleCard(
                  title: 'Enable backup',
                  description:
                      'Automatically back up the unlocked vault at 00:00, 04:00, 08:00, 12:00, 16:00, and 20:00 local time.',
                  value: enabled,
                  showActiveBadge: enabled,
                  onChanged: (value) =>
                      BackupService.instance.setEnabled(value),
                ),
                if (enabled) ...<Widget>[
                  const SizedBox(height: 12),
                  _BackupStatusRow(
                    status: status,
                    lastTimestamp: lastTimestamp,
                    nextTimestamp: nextTimestamp,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Delete backup after',
                    style: _text(
                      13,
                      _settingsTextPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Automatically remove older backup copies after the selected retention period.',
                    style: _text(
                      11,
                      _settingsTextSecondary,
                      fontWeight: FontWeight.w400,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingsDropdownField<_BackupRetentionDays>(
                    value: _retentionDays,
                    items: _BackupRetentionDays.values,
                    itemLabelBuilder: _backupRetentionDaysLabel,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _retentionDays = value);
                      BackupService.instance.setRetentionDays(value.days);
                    },
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: _openBackupFolder,
                          icon: const Icon(Icons.folder_open_rounded, size: 18),
                          label: const Text('Open Folder'),
                        ),
                        ElevatedButton.icon(
                          onPressed: status == BackupStatus.running
                              ? null
                              : () => BackupService.instance.runBackup(),
                          icon: status == BackupStatus.running
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Icon(Icons.backup_rounded, size: 18),
                          label: Text(
                            status == BackupStatus.running
                                ? 'Creating backup…'
                                : 'Create Backup Now',
                            style: _text(
                              12,
                              Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _settingsSelectedBlue,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                _settingsSelectedBlue.withValues(alpha: 0.5),
                            disabledForegroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SettingsSurfaceSection(
          child: _SettingsSectionBlock(
            title: 'Restore',
            subtitle:
                'Bring back a previous backup snapshot if the current vault needs to be recovered.',
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _showRestoreModal,
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: const Text('Restore from Backup'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Modal showing real-time progress for the active restore operation. The
/// modal listens to [backupRestoreProgressProvider] so it stays in sync with
/// the BackupService progress reporter.
class RestoreProgressDialog extends ConsumerWidget {
  const RestoreProgressDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(backupRestoreProgressProvider);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: _settingsPanelBackground,
        surfaceTintColor: Colors.transparent,
        title: const Text('Restoring vault'),
        titleTextStyle: _text(
          18,
          _settingsTextPrimary,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: _text(
          13,
          _settingsTextSecondary,
          fontWeight: FontWeight.w500,
          height: 1.45,
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LinearProgressIndicator(value: progress?.value),
              const SizedBox(height: 6),
              Text(
                progress == null
                    ? 'Starting…'
                    : '${(progress.value * 100).toStringAsFixed(0)}%',
                style: _text(11, _settingsTextSecondary),
              ),
              const SizedBox(height: 12),
              Text(
                progress?.message ?? 'Preparing restore…',
                style: _text(13, _settingsTextPrimary,
                    fontWeight: FontWeight.w700),
              ),
              if (progress != null && progress.logs.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _settingsSidebarBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _settingsDividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: progress.logs
                        .skip(progress.logs.length > 6
                            ? progress.logs.length - 6
                            : 0)
                        .map((log) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: Text(
                                '• $log',
                                style: _text(11, _settingsTextSecondary),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BackupStatusRow extends StatelessWidget {
  const _BackupStatusRow({
    required this.status,
    required this.lastTimestamp,
    required this.nextTimestamp,
  });

  final BackupStatus status;
  final DateTime? lastTimestamp;
  final DateTime? nextTimestamp;

  @override
  Widget build(BuildContext context) {
    if (status == BackupStatus.idle && lastTimestamp == null) {
      return const SizedBox.shrink();
    }

    final Widget leading;
    final String text;
    final Color textColor;

    switch (status) {
      case BackupStatus.running:
        leading = const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(_settingsSelectedBlue),
          ),
        );
        text = 'Backing up…';
        textColor = _settingsTextSecondary;
      case BackupStatus.error:
        leading = const Icon(
          TablerIcons.alert_circle,
          size: 15,
          color: Color(0xFFE53E3E),
        );
        text = 'Backup failed';
        textColor = const Color(0xFFE53E3E);
      case BackupStatus.done:
      case BackupStatus.idle:
        leading = const Icon(
          TablerIcons.circle_check,
          size: 15,
          color: Color(0xFF159A0B),
        );
        text = lastTimestamp != null
            ? 'Last backup: ${_formatTs(lastTimestamp!)}'
            : 'No backup yet';
        textColor = _settingsTextSecondary;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _settingsDividerColor),
      ),
      child: Row(
        children: <Widget>[
          leading,
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              nextTimestamp != null
                  ? '$text • Next backup at ${_formatClock(nextTimestamp!)}'
                  : text,
              style: _text(
                11,
                textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTs(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatClock(DateTime ts) {
    final hour = ts.hour.toString().padLeft(2, '0');
    final minute = ts.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _ExperimentSettingsContent extends ConsumerStatefulWidget {
  const _ExperimentSettingsContent();

  @override
  ConsumerState<_ExperimentSettingsContent> createState() =>
      _ExperimentSettingsContentState();
}

class _ExperimentSettingsContentState
    extends ConsumerState<_ExperimentSettingsContent> {
  DateTime _selectedDate = DateTime.now();
  bool _useCurrentDate = true;
  bool _cancelRequested = false;

  String get _formattedSelectedDate {
    final value = _selectedDate;
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(1971),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = picked;
      _useCurrentDate = false;
    });
  }

  Future<void> _processCreatedDateFix() async {
    final now = DateTime.now();
    if (_useCurrentDate) {
      _selectedDate = now;
    }
    final repository = ref.read(kdbxRepositoryProvider);
    final items = await repository.entriesWithInvalidCreatedAt(
      now: now,
    );
    if (!mounted) return;

    if (items.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _settingsPanelBackground,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: _text(
            18,
            _settingsTextPrimary,
            fontWeight: FontWeight.w700,
          ),
          contentTextStyle: _text(
            13,
            _settingsTextPrimary,
            fontWeight: FontWeight.w500,
            height: 1.45,
          ),
          title: const Text('No items found'),
          content: const Text(
            'No vault items have a future or invalid created date.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _settingsPanelBackground,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: _text(
          18,
          _settingsTextPrimary,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: _text(
          13,
          _settingsTextPrimary,
          fontWeight: FontWeight.w500,
          height: 1.45,
        ),
        title: const Text('Fix item created dates?'),
        content: Text(
          'Found ${items.length} items with future or invalid created dates. Their created date will be changed to $_formattedSelectedDate.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _settingsSelectedBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _cancelRequested = false;
    var current = 0;
    var cancelled = false;
    Object? migrationError;
    void Function(void Function())? updateDialog;
    final dialogReady = Completer<void>();

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          updateDialog = setDialogState;
          if (!dialogReady.isCompleted) {
            dialogReady.complete();
          }
          final progress = items.isEmpty ? 0.0 : current / items.length;
          return AlertDialog(
            backgroundColor: _settingsPanelBackground,
            surfaceTintColor: Colors.transparent,
            titleTextStyle: _text(
              18,
              _settingsTextPrimary,
              fontWeight: FontWeight.w700,
            ),
            contentTextStyle: _text(
              13,
              _settingsTextPrimary,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
            title: const Text('Processing migration'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Found ${items.length} items need to be processed.'),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
                  const SizedBox(height: 10),
                  Text('$current/${items.length} processed'),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () async {
                  final cancel = await showDialog<bool>(
                    context: dialogContext,
                    builder: (context) => AlertDialog(
                      backgroundColor: _settingsPanelBackground,
                      surfaceTintColor: Colors.transparent,
                      titleTextStyle: _text(
                        18,
                        _settingsTextPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      contentTextStyle: _text(
                        13,
                        _settingsTextPrimary,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                      ),
                      title: const Text('Cancel migration?'),
                      content: const Text(
                        'The migration is currently processing. Are you sure you want to cancel it?',
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('No'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Yes, cancel'),
                        ),
                      ],
                    ),
                  );
                  if (cancel == true) {
                    _cancelRequested = true;
                  }
                },
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    ));

    await dialogReady.future;

    final replacementDate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final processed = <KdbxEntry>[];

    try {
      for (final item in items) {
        if (_cancelRequested) {
          cancelled = true;
          break;
        }
        await repository.setEntryCreatedAt(
          entryUuid: item.uuid,
          createdAt: replacementDate,
        );
        processed.add(item);
        current += 1;
        updateDialog?.call(() {});
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      if (cancelled) {
        for (final item in processed) {
          final createdAt = item.createdAt;
          if (createdAt == null) continue;
          await repository.setEntryCreatedAt(
            entryUuid: item.uuid,
            createdAt: createdAt,
          );
        }
      } else {
        _clearMockEntryCache();
        publishAndScheduleSave(ref, ref.read(kdbxRepositoryProvider));
        unawaited(SshAgentService.instance.syncKeys());
      }
    } catch (error) {
      migrationError = error;
      for (final item in processed) {
        final createdAt = item.createdAt;
        if (createdAt == null) continue;
        await repository.setEntryCreatedAt(
          entryUuid: item.uuid,
          createdAt: createdAt,
        );
      }
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _settingsPanelBackground,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: _text(
          18,
          _settingsTextPrimary,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: _text(
          13,
          _settingsTextPrimary,
          fontWeight: FontWeight.w500,
          height: 1.45,
        ),
        title: Text(
          migrationError != null
              ? 'Migration failed'
              : (cancelled ? 'Migration cancelled' : 'Migration complete'),
        ),
        content: Text(
          migrationError != null
              ? 'Migration stopped after processing $current/${items.length} items. Changes were rolled back. Error: $migrationError'
              : (cancelled
                  ? 'Migration cancelled after processing $current/${items.length} items. Changes were not saved.'
                  : 'Updated $current/${items.length} items. Vault data has been reloaded.'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _dateOptionButton({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    final foregroundColor =
        selected ? Colors.white : _settingsActiveItemBackground;
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor:
            selected ? _settingsActiveItemBackground : Colors.white,
        foregroundColor: foregroundColor,
        elevation: selected ? 2 : 0,
        shadowColor: _settingsActiveItemBackground.withValues(alpha: 0.18),
        side: BorderSide(
          color: selected
              ? _settingsActiveItemBackground
              : const Color(0xFF334155),
          width: selected ? 2 : 1.4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: _text(13, foregroundColor, fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('experiment-settings'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _SettingsPaneHeading(label: 'Experiment'),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(
            'Experimental tools for repairing imported vault data. Review each action carefully before running it.',
            style: _text(
              12,
              _settingsTextSecondary,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SettingsSurfaceSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Fix items with invalid created dates',
                style: _text(
                  14,
                  _settingsTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Imported vault items may have incorrect created dates, such as dates in the future, 1970, or year zero. This tool migrates affected items to the date you choose.',
                style: _text(
                  12,
                  _settingsTextSecondary,
                  fontWeight: FontWeight.w400,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  _dateOptionButton(
                    selected: _useCurrentDate,
                    icon: TablerIcons.clock,
                    label: 'Now',
                    onPressed: () => setState(() {
                      _selectedDate = DateTime.now();
                      _useCurrentDate = true;
                    }),
                  ),
                  const SizedBox(width: 12),
                  _dateOptionButton(
                    selected: !_useCurrentDate,
                    icon: TablerIcons.calendar,
                    label: _formattedSelectedDate,
                    onPressed: _pickDate,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _processCreatedDateFix,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _settingsSelectedBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                child: const Text('Process'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void _showSshAgentLearnMoreDialog(BuildContext context) {
  showGeneralDialog<void>(
    context: context,
    barrierLabel: 'SSH Agent details',
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (BuildContext ctx, Animation<double> anim,
        Animation<double> secondary) {
      return const _SshAgentLearnMoreDialog();
    },
    transitionBuilder: (BuildContext ctx, Animation<double> anim,
        Animation<double> secondary, Widget child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _SshAgentSettingsContent extends ConsumerWidget {
  const _SshAgentSettingsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(sshAgentEnabledProvider);
    final socketPath = ref.watch(sshAgentSocketPathProvider);
    final configStatus = ref.watch(sshAgentConfigStatusProvider);

    return Column(
      key: const ValueKey<String>('ssh-agent-settings'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _SettingsPaneHeading(label: 'SSH Agent'),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Use the built-in SSH agent so terminals and developer tools can request SSH key access from LumenPass without exporting private keys.',
            style: _text(
              12,
              _settingsTextSecondary,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SettingsSurfaceSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    'SSH Agent',
                    style: _text(
                      14,
                      _settingsTextPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: enabled
                          ? const Color(0xFF159A0B)
                          : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      enabled ? 'Running' : 'Off',
                      style: _text(
                        10,
                        enabled ? Colors.white : _settingsTextPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'The SSH Agent allows terminals and connected developer tools to use SSH keys stored in LumenPass, while keeping the private keys protected inside the app.',
                style: _text(
                  12,
                  _settingsTextSecondary,
                  fontWeight: FontWeight.w400,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              _SettingsInlineToggleCard(
                title: 'Use the SSH Agent',
                description:
                    'Turn this on to let approved apps ask LumenPass to sign SSH requests with your saved keys.',
                value: enabled,
                showActiveBadge: enabled,
                onChanged: (value) =>
                    SshAgentService.instance.setEnabled(value),
              ),
              if (enabled && socketPath.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                _SshAgentConfigStatusRow(status: configStatus),
                const SizedBox(height: 12),
                _SshAgentSocketHint(socketPath: socketPath),
              ],
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => _showSshAgentLearnMoreDialog(context),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: _settingsSelectedBlue,
                  textStyle: _text(
                    12,
                    _settingsSelectedBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Learn More'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SshAgentConfigStatusRow extends StatelessWidget {
  const _SshAgentConfigStatusRow({required this.status});

  final SshAgentConfigStatus status;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String text, Color color) = switch (status) {
      SshAgentConfigStatus.configured => (
          TablerIcons.circle_check,
          'SSH config: configured',
          const Color(0xFF159A0B)
        ),
      SshAgentConfigStatus.needsAttention => (
          TablerIcons.alert_circle,
          'SSH config: needs attention',
          const Color(0xFFE53E3E)
        ),
      SshAgentConfigStatus.unknown => (
          TablerIcons.info_circle,
          'SSH config: checking…',
          _settingsTextSecondary
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _settingsDividerColor),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Text(
            text,
            style: _text(11, color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SshAgentSocketHint extends StatefulWidget {
  const _SshAgentSocketHint({required this.socketPath});

  final String socketPath;

  @override
  State<_SshAgentSocketHint> createState() => _SshAgentSocketHintState();
}

class _SshAgentSocketHintState extends State<_SshAgentSocketHint> {
  bool _copied = false;
  Timer? _copyTimer;

  @override
  void dispose() {
    _copyTimer?.cancel();
    super.dispose();
  }

  void _handleCopy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _copied = true);
    _copyTimer?.cancel();
    _copyTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final configSnippet = [
      '# BEGIN LUMENPASS SSH AGENT',
      'Host *',
      '  IdentityAgent "${widget.socketPath}"',
      '# END LUMENPASS SSH AGENT',
    ].join('\n');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                TablerIcons.terminal_2,
                size: 13,
                color: Color(0xFF0369A1),
              ),
              const SizedBox(width: 6),
              Text(
                'SSH config is set up automatically',
                style: _text(11, const Color(0xFF0369A1),
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'LumenPass writes an IdentityAgent entry to ~/.ssh/config so SSH works without setting SSH_AUTH_SOCK.',
            style: _text(
              11,
              const Color(0xFF0C4A6E),
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _handleCopy(configSnippet),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      configSnippet,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Color(0xFF0C4A6E),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _copied ? TablerIcons.check : TablerIcons.copy,
                    size: 13,
                    color: _copied
                        ? const Color(0xFF059669)
                        : const Color(0xFF0369A1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SshAgentLearnMoreDialog extends StatelessWidget {
  const _SshAgentLearnMoreDialog();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = math.min(560.0, size.width - 48.0);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: dialogWidth,
          constraints: BoxConstraints(maxHeight: size.height - 80),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildHeader(context),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const <Widget>[
                      _SshAgentLearnMorePoint(
                        icon: TablerIcons.key,
                        title: 'Keeps private keys inside LumenPass',
                        body:
                            'SSH clients ask the agent to sign an authentication challenge. LumenPass returns only the signature, so the private key is not exported to your terminal, Git client, or IDE.',
                      ),
                      SizedBox(height: 16),
                      _SshAgentLearnMorePoint(
                        icon: TablerIcons.shield_lock,
                        title: 'Asks before signing',
                        body:
                            'When an app requests a signature, LumenPass shows the requesting app and key name so you can approve or deny the request before anything is signed.',
                      ),
                      SizedBox(height: 16),
                      _SshAgentLearnMorePoint(
                        icon: TablerIcons.terminal_2,
                        title: 'Connects to SSH automatically',
                        body:
                            'On macOS and Linux, LumenPass manages a small IdentityAgent block in ~/.ssh/config. On Windows, OpenSSH connects through the standard SSH agent named pipe.',
                      ),
                      SizedBox(height: 18),
                      _SshAgentLearnMoreNote(),
                    ],
                  ),
                ),
              ),
              const Divider(
                height: 1,
                thickness: 0.5,
                color: _settingsDividerColor,
              ),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F9FF),
        border: Border(
          bottom: BorderSide(color: Color(0xFFBAE6FD), width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            alignment: Alignment.center,
            child: const Icon(
              TablerIcons.terminal_2,
              size: 20,
              color: Color(0xFF0369A1),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'About SSH Agent',
                  style: _text(
                    18,
                    _settingsTextPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Use saved SSH keys from LumenPass without exposing private key material to command-line tools.',
                  style: _text(
                    12,
                    const Color(0xFF0C4A6E),
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            button: true,
            label: 'Close SSH Agent details',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBAE6FD)),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    TablerIcons.x,
                    size: 16,
                    color: _settingsTextSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: _settingsActiveItemBackground,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: _text(13, Colors.white, fontWeight: FontWeight.w700),
            ),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _SshAgentLearnMorePoint extends StatelessWidget {
  const _SshAgentLearnMorePoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 17,
            color: const Color(0xFF0369A1),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: _text(
                  13,
                  _settingsTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: _text(
                  12,
                  _settingsTextSecondary,
                  fontWeight: FontWeight.w400,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SshAgentLearnMoreNote extends StatelessWidget {
  const _SshAgentLearnMoreNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _settingsDividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            TablerIcons.info_circle,
            size: 16,
            color: _settingsSelectedBlue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Turning the SSH Agent off stops the local agent and removes LumenPass from the managed SSH config block. Keys saved elsewhere can keep using your normal OpenSSH setup.',
              style: _text(
                12,
                _settingsTextPrimary,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpSettingsContent extends StatefulWidget {
  const _HelpSettingsContent();

  @override
  State<_HelpSettingsContent> createState() => _HelpSettingsContentState();
}

class _HelpSettingsContentState extends State<_HelpSettingsContent> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _captchaController = TextEditingController();

  late int _captchaLeft;
  late int _captchaRight;
  late bool _captchaIsAddition;

  final SupportApiClient _supportApi = SupportApiClient();
  bool _isSubmitting = false;
  String? _formError;
  String? _successMessage;
  Map<String, String> _fieldErrors = const <String, String>{};

  static final RegExp _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void initState() {
    super.initState();
    _generateCaptcha();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _captchaController.dispose();
    _supportApi.close();
    super.dispose();
  }

  void _generateCaptcha() {
    final random = math.Random();
    _captchaIsAddition = random.nextBool();
    final first = random.nextInt(8) + 2;
    final second = random.nextInt(8) + 1;
    if (_captchaIsAddition) {
      _captchaLeft = first;
      _captchaRight = second;
    } else {
      _captchaLeft = math.max(first, second);
      _captchaRight = math.min(first, second);
    }
  }

  Map<String, String> _validateLocally() {
    final errors = <String, String>{};
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final subject = _subjectController.text.trim();
    final body = _bodyController.text.trim();
    final captchaAnswer = _captchaController.text.trim();

    if (name.isEmpty) errors['name'] = 'Please enter your name.';
    if (email.isEmpty) {
      errors['email'] = 'Please enter your email address.';
    } else if (!_emailRegex.hasMatch(email)) {
      errors['email'] = 'Please enter a valid email address.';
    }
    if (subject.isEmpty) errors['subject'] = 'Please enter a subject.';
    if (body.isEmpty) errors['message'] = 'Please describe how we can help.';

    final expected = _captchaIsAddition
        ? _captchaLeft + _captchaRight
        : _captchaLeft - _captchaRight;
    final parsedAnswer = int.tryParse(captchaAnswer);
    if (parsedAnswer == null || parsedAnswer != expected) {
      errors['captcha'] = 'Captcha answer is incorrect.';
    }
    return errors;
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;
    final localErrors = _validateLocally();
    if (localErrors.isNotEmpty) {
      setState(() {
        _fieldErrors = localErrors;
        _formError = localErrors.values.first;
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _formError = null;
      _successMessage = null;
      _fieldErrors = const <String, String>{};
    });

    final captchaOperator = _captchaIsAddition ? '+' : '-';
    final captchaQuestion = '$_captchaLeft $captchaOperator $_captchaRight = ?';

    try {
      final result = await _supportApi.submitContactTicket(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        subject: _subjectController.text.trim(),
        message: _bodyController.text.trim(),
        priority: 'medium',
        source: 'desktop',
        category: 'help_contact_form',
        captchaQuestion: captchaQuestion,
        captchaAnswer: int.tryParse(_captchaController.text.trim()) ??
            _captchaController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _successMessage =
            'Thanks! We received your request (#${result.shortId.isNotEmpty ? result.shortId : result.ticketId}). Our team will reply soon.';
        _formError = null;
        _nameController.clear();
        _emailController.clear();
        _subjectController.clear();
        _bodyController.clear();
        _captchaController.clear();
        _generateCaptcha();
      });
    } on SupportApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _formError = err.message;
        _fieldErrors = err.fieldErrors ?? const <String, String>{};
        _successMessage = null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _formError = 'Unexpected error sending your request. Please try again.';
        _successMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final captchaOperator = _captchaIsAddition ? '+' : '-';

    return Column(
      key: const ValueKey<String>('help-settings'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _SettingsPaneHeading(label: 'Help'),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Send a quick support request when you need help with setup, recovery, or product questions.',
            style: _text(
              12,
              _settingsTextSecondary,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SettingsSurfaceSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SettingsSectionBlock(
                title: 'Quick contact',
                subtitle:
                    'Share a few details so the support request is easier to review and reply to.',
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _SettingsTextField(
                            controller: _nameController,
                            label: 'Name',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SettingsTextField(
                            controller: _emailController,
                            label: 'Email',
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SettingsTextField(
                      controller: _subjectController,
                      label: 'Subject',
                    ),
                    const SizedBox(height: 12),
                    _SettingsTextField(
                      controller: _bodyController,
                      label: 'Body',
                      maxLines: 5,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Captcha',
                                style: _text(
                                  12,
                                  _settingsTextPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Solve the calculation and enter the answer.',
                                style: _text(
                                  11,
                                  _settingsTextSecondary,
                                  fontWeight: FontWeight.w400,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F6FA),
                                  borderRadius: BorderRadius.circular(14),
                                  border:
                                      Border.all(color: _settingsDividerColor),
                                ),
                                child: Text(
                                  '$_captchaLeft $captchaOperator $_captchaRight = ?',
                                  style: _text(
                                    14,
                                    _settingsTextPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SettingsTextField(
                            controller: _captchaController,
                            label: 'Answer',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    if (_fieldErrors.isNotEmpty ||
                        _formError != null ||
                        _successMessage != null) ...<Widget>[
                      const SizedBox(height: 12),
                      if (_successMessage != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F4EA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF9FCDB1)),
                          ),
                          child: Text(
                            _successMessage!,
                            style: _text(
                              12,
                              const Color(0xFF1B5E20),
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                            ),
                          ),
                        ),
                      if (_formError != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDECEA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE3A8A2)),
                          ),
                          child: Text(
                            _formError!,
                            style: _text(
                              12,
                              const Color(0xFF8B1A10),
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _isSubmitting ? null : _handleSubmit,
                        style: FilledButton.styleFrom(
                          backgroundColor: _settingsActiveItemBackground,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Send',
                                style: _text(
                                  12,
                                  Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AboutSettingsContent extends StatefulWidget {
  const _AboutSettingsContent();

  @override
  State<_AboutSettingsContent> createState() => _AboutSettingsContentState();
}

class _AboutSettingsContentState extends State<_AboutSettingsContent> {
  final ReleaseApiClient _releaseApi = ReleaseApiClient();

  bool _checking = false;
  _UpdateCheckResult? _result;

  @override
  void dispose() {
    _releaseApi.close();
    super.dispose();
  }

  String? _platformKey() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return null;
  }

  Future<void> _checkForUpdate() async {
    if (_checking) return;
    final platformKey = _platformKey();
    if (platformKey == null) {
      setState(() {
        _result = const _UpdateCheckResult.failure(
          'Update checks are only available on macOS and Windows.',
        );
      });
      return;
    }

    setState(() {
      _checking = true;
      _result = null;
    });

    try {
      final info = await PackageInfo.fromPlatform();
      final localCombined = info.buildNumber.isNotEmpty
          ? '${info.version}+${info.buildNumber}'
          : info.version;

      final latest = await _releaseApi.fetchLatest(platform: platformKey);

      if (!mounted) return;

      final cmp = compareReleaseVersions(latest.version, localCombined);
      if (cmp > 0) {
        setState(() {
          _result = _UpdateCheckResult.updateAvailable(
            currentVersion: localCombined,
            latestVersion: latest.version,
            changeLog: latest.changeLog,
            downloadUrl: latest.downloadUrl,
          );
        });
      } else {
        setState(() {
          _result = _UpdateCheckResult.upToDate(
            currentVersion: localCombined,
            latestVersion: latest.version,
          );
        });
      }
    } on ReleaseApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _result = _UpdateCheckResult.failure(_describeReleaseError(err));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _result = const _UpdateCheckResult.failure(
          'Check failed. Please try again later.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }

  String _describeReleaseError(ReleaseApiException err) {
    switch (err.code) {
      case 'not_configured':
        return 'Update server is not configured for this build.';
      case 'network':
        return 'Could not reach the update server. Check your connection and try again.';
      case 'not_found':
        return 'No release information is available yet for this platform.';
      case 'bad_response':
        return 'Update check failed: invalid response from server.';
      default:
        return 'Update check failed. Please try again later.';
    }
  }

  Future<void> _openDownload(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openSourceCode() => _openDownload(
        'https://github.com/lumenpass/lumenpass',
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('about-settings'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _SettingsPaneHeading(label: 'About'),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Learn what LumenPass is, what it supports today, and the release details for the current desktop app.',
            style: _text(
              12,
              _settingsTextSecondary,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SettingsSurfaceSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3F7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.info_outline_rounded,
                      size: 22,
                      color: _settingsActiveItemBackground,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'LumenPass',
                          style: _text(
                            15,
                            _settingsTextPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Secure vault manager for passwords, passkeys, notes, and SSH keys.',
                          style: _text(
                            11,
                            _settingsTextSecondary,
                            fontWeight: FontWeight.w400,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  final version = snapshot.data?.version ?? '—';
                  final buildNumber = snapshot.data?.buildNumber ?? '—';
                  return Row(
                    children: <Widget>[
                      Expanded(
                        child: _SettingsInfoCard(
                          label: 'Version',
                          value: version,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SettingsInfoCard(
                          label: 'Build',
                          value: buildNumber,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _AboutCheckForUpdateBlock(
                checking: _checking,
                result: _result,
                onCheck: _checkForUpdate,
                onDownload: _openDownload,
              ),
              const SizedBox(height: 20),
              _SettingsSectionBlock(
                title: 'Open source',
                subtitle:
                    'LumenPass source code is available under the Mozilla Public License 2.0.',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _openSourceCode,
                    icon: const Icon(Icons.code_rounded, size: 16),
                    label: const Text('View source code & license'),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _SettingsSectionBlock(
                title: 'What the app does',
                subtitle:
                    'LumenPass helps you store and organize sensitive credentials in one place while keeping day-to-day access fast and practical.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _SettingsBulletLine(
                      text:
                          'Manage passwords, passkeys, secure notes, cards, and identities.',
                    ),
                    const SizedBox(height: 8),
                    _SettingsBulletLine(
                      text:
                          'Support autofill workflows, backup schedules, and clipboard protection.',
                    ),
                    const SizedBox(height: 8),
                    _SettingsBulletLine(
                      text:
                          'Provide SSH agent access so saved keys can be used without exporting private material.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UpdateCheckResult {
  const _UpdateCheckResult._({
    required this.kind,
    this.currentVersion,
    this.latestVersion,
    this.changeLog,
    this.downloadUrl,
    this.errorMessage,
  });

  const _UpdateCheckResult.upToDate({
    required String currentVersion,
    required String latestVersion,
  }) : this._(
          kind: _UpdateCheckKind.upToDate,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
        );

  const _UpdateCheckResult.updateAvailable({
    required String currentVersion,
    required String latestVersion,
    required String changeLog,
    required String downloadUrl,
  }) : this._(
          kind: _UpdateCheckKind.updateAvailable,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          changeLog: changeLog,
          downloadUrl: downloadUrl,
        );

  const _UpdateCheckResult.failure(String message)
      : this._(
          kind: _UpdateCheckKind.failure,
          errorMessage: message,
        );

  final _UpdateCheckKind kind;
  final String? currentVersion;
  final String? latestVersion;
  final String? changeLog;
  final String? downloadUrl;
  final String? errorMessage;
}

enum _UpdateCheckKind { upToDate, updateAvailable, failure }

String _formatReleaseVersion(String? raw) {
  if (raw == null) return '—';
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '—';
  final plusIndex = trimmed.indexOf('+');
  if (plusIndex < 0) return 'Version $trimmed';
  final core = trimmed.substring(0, plusIndex).trim();
  final build = trimmed.substring(plusIndex + 1).trim();
  if (core.isEmpty) return 'Version $trimmed';
  if (build.isEmpty) return 'Version $core';
  return 'Version $core Build $build';
}

class _AboutCheckForUpdateBlock extends StatelessWidget {
  const _AboutCheckForUpdateBlock({
    required this.checking,
    required this.result,
    required this.onCheck,
    required this.onDownload,
  });

  final bool checking;
  final _UpdateCheckResult? result;
  final VoidCallback onCheck;
  final ValueChanged<String> onDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _settingsDividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Software updates',
                      style: _text(
                        13,
                        _settingsTextPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Check whether a newer version of LumenPass is available for your platform.',
                      style: _text(
                        11,
                        _settingsTextSecondary,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: checking ? null : onCheck,
                icon: checking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.system_update_alt_rounded, size: 16),
                label: Text(
                  checking ? 'Checking…' : 'Check for updates',
                  style: _text(
                    12,
                    Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _settingsSelectedBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      _settingsSelectedBlue.withValues(alpha: 0.5),
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          if (result != null) ...<Widget>[
            const SizedBox(height: 14),
            _UpdateCheckResultPanel(
              result: result!,
              onDownload: onDownload,
            ),
          ],
        ],
      ),
    );
  }
}

class _UpdateCheckResultPanel extends StatelessWidget {
  const _UpdateCheckResultPanel({
    required this.result,
    required this.onDownload,
  });

  final _UpdateCheckResult result;
  final ValueChanged<String> onDownload;

  @override
  Widget build(BuildContext context) {
    switch (result.kind) {
      case _UpdateCheckKind.upToDate:
        return _UpdateStatusBanner(
          icon: Icons.check_circle_rounded,
          accent: const Color(0xFF1F8F4F),
          background: const Color(0xFFEAF7EE),
          title: 'You are up to date',
          subtitle:
              'You are running ${_formatReleaseVersion(result.currentVersion)}. Latest available: ${_formatReleaseVersion(result.latestVersion)}.',
        );
      case _UpdateCheckKind.failure:
        return _UpdateStatusBanner(
          icon: Icons.error_outline_rounded,
          accent: const Color(0xFFB54708),
          background: const Color(0xFFFFF4E5),
          title: 'Check failed',
          subtitle: result.errorMessage ??
              'We could not verify the latest release right now.',
        );
      case _UpdateCheckKind.updateAvailable:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF7EE),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFB7E2C2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.rocket_launch_rounded,
                    size: 18,
                    color: Color(0xFF1F8F4F),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'A new version is available',
                          style: _text(
                            13,
                            _settingsTextPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'You have ${_formatReleaseVersion(result.currentVersion)} · Latest is ${_formatReleaseVersion(result.latestVersion)}',
                          style: _text(
                            11,
                            _settingsTextSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFC9E9D2)),
                ),
                child: SelectableText(
                  (result.changeLog ?? '').trim().isEmpty
                      ? 'No release notes provided.'
                      : result.changeLog!.trim(),
                  style: _text(
                    11,
                    _settingsTextPrimary,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: () => onDownload(result.downloadUrl ?? ''),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: Text(
                    'Download',
                    style: _text(
                      12,
                      Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F8F4F),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _UpdateStatusBanner extends StatelessWidget {
  const _UpdateStatusBanner({
    required this.icon,
    required this.accent,
    required this.background,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color accent;
  final Color background;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: _text(
                    12,
                    _settingsTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: _text(
                    11,
                    _settingsTextSecondary,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
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

class _SettingsPlaceholderContent extends StatelessWidget {
  const _SettingsPlaceholderContent({required this.section});

  final _SettingsSectionId section;

  @override
  Widget build(BuildContext context) {
    final sectionItem = <_SettingsSectionItem>[
      ..._primarySettingsSections,
      ..._secondarySettingsSections,
    ].firstWhere((item) => item.id == section);

    return Column(
      key: ValueKey<_SettingsSectionId>(section),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F6FA),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(5),
          child: Image.asset(sectionItem.imageAsset),
        ),
        const SizedBox(height: 12),
        Text(
          sectionItem.label,
          style: _text(
            16,
            _settingsTextPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            'This section is scaffolded so we can match the rest of the settings modal now and refine each panel with your next round of adjustments.',
            style: _text(
              12,
              _settingsTextSecondary,
              fontWeight: FontWeight.w400,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsSectionBlock extends StatelessWidget {
  const _SettingsSectionBlock({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          style: _text(
            14,
            _settingsTextPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: _text(
            11,
            _settingsTextSecondary,
            fontWeight: FontWeight.w400,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _SettingsSurfaceSection extends StatelessWidget {
  const _SettingsSurfaceSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _settingsDividerColor),
      ),
      child: child,
    );
  }
}

class _SettingsInfoCard extends StatelessWidget {
  const _SettingsInfoCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _settingsDividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: _text(
              10,
              _settingsTextSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: _text(
              13,
              _settingsTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsDropdownField<T> extends StatelessWidget {
  const _SettingsDropdownField({
    required this.value,
    required this.items,
    required this.itemLabelBuilder,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T value) itemLabelBuilder;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _settingsDividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: _settingsSelectedBlue,
            width: 1.4,
          ),
        ),
      ),
      icon: const Icon(
        TablerIcons.chevron_down,
        size: 16,
        color: _settingsTextSecondary,
      ),
      borderRadius: BorderRadius.circular(14),
      dropdownColor: Colors.white,
      style: _text(
        12,
        _settingsTextPrimary,
        fontWeight: FontWeight.w600,
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<T>(
              value: item,
              child: Text(itemLabelBuilder(item)),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _SettingsTextField extends StatelessWidget {
  const _SettingsTextField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: _text(
        12,
        _settingsTextPrimary,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: _text(
          11,
          _settingsTextSecondary,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: maxLines > 1 ? 14 : 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _settingsDividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: _settingsSelectedBlue,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

class _SettingsBulletLine extends StatelessWidget {
  const _SettingsBulletLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 8),
          decoration: const BoxDecoration(
            color: _settingsActiveItemBackground,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: _text(
              11,
              _settingsTextSecondary,
              fontWeight: FontWeight.w400,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsChoiceChip extends StatelessWidget {
  const _SettingsChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? _settingsActiveItemBackground
                : const Color(0xFFF3F6FA),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? _settingsActiveItemBackground
                  : _settingsDividerColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: _text(
                  11,
                  selected ? Colors.white : _settingsTextPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppearanceFontCard extends StatelessWidget {
  const _AppearanceFontCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _AppearanceFontOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 140,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF3F7) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? _settingsActiveItemBackground
                  : _settingsDividerColor,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Aa',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _settingsTextPrimary,
                  fontFamily: option.family,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                option.label,
                style: _text(
                  12,
                  _settingsTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                option.caption,
                style: _text(
                  10,
                  _settingsTextSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockIconCard extends StatelessWidget {
  const _DockIconCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final DockIconOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 56,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  selected ? _settingsActiveItemBackground : Colors.transparent,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Image.asset(option.assetPath, fit: BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsRadioCard extends StatelessWidget {
  const _SettingsRadioCard({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF3F7) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? _settingsActiveItemBackground
                  : _settingsDividerColor,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? _settingsActiveItemBackground
                        : const Color(0xFFAFB8C6),
                    width: selected ? 5.5 : 1.6,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: _text(
                        12,
                        _settingsTextPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: _text(
                        11,
                        _settingsTextSecondary,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
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

class _SettingsInlineToggleCard extends StatelessWidget {
  const _SettingsInlineToggleCard({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.showActiveBadge = false,
  });

  final String title;
  final String description;
  final bool value;
  // A null callback renders the switch in its disabled state.
  final ValueChanged<bool>? onChanged;
  final bool showActiveBadge;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _settingsDividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        title,
                        style: _text(
                          12,
                          _settingsTextPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (showActiveBadge) ...<Widget>[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7F6ED),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Active',
                          style: _text(
                            9,
                            const Color(0xFF0F7B3A),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: _text(
                    11,
                    _settingsTextSecondary,
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Transform.scale(
            scale: 0.78,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: _settingsSelectedBlue,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFFD9DEE7),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final labelColor = enabled
        ? _settingsTextPrimary
        : _settingsTextPrimary.withValues(alpha: 0.45);
    return Opacity(
      opacity: enabled ? 1.0 : 0.8,
      child: SizedBox(
        height: 40,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: _text(13, labelColor, fontWeight: FontWeight.w500),
              ),
            ),
            Transform.scale(
              scale: 0.78,
              child: Switch.adaptive(
                value: value,
                onChanged: enabled ? onChanged : null,
                activeThumbColor: Colors.white,
                activeTrackColor: _settingsSelectedBlue,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFFD9DEE7),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsShortcutCaptureRow extends ConsumerStatefulWidget {
  const _SettingsShortcutCaptureRow({
    required this.label,
    this.initialValue,
    this.shortcutId,
  });

  final String label;
  final String? initialValue;
  final ShortcutId? shortcutId;

  @override
  ConsumerState<_SettingsShortcutCaptureRow> createState() =>
      _SettingsShortcutCaptureRowState();
}

class _SettingsShortcutCaptureRowState
    extends ConsumerState<_SettingsShortcutCaptureRow> {
  late final FocusNode _focusNode;
  String? _value;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
    final id = widget.shortcutId;
    if (id != null) {
      final current = ref.read(
        id == ShortcutId.spotlight
            ? spotlightShortcutProvider
            : lockVaultShortcutProvider,
      );
      _value = current?.display ?? widget.initialValue;
    } else {
      _value = widget.initialValue;
    }
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      node.unfocus();
      return KeyEventResult.handled;
    }

    if (_isModifierKey(event.logicalKey)) {
      return KeyEventResult.handled;
    }

    final pressedKeys = HardwareKeyboard.instance.logicalKeysPressed;
    final hasModifier = pressedKeys.any(_isModifierKey);

    if (!hasModifier &&
        (event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.delete)) {
      setState(() => _value = null);
      _updateProvider(null);
      return KeyEventResult.handled;
    }

    final ctrl = pressedKeys.contains(LogicalKeyboardKey.controlLeft) ||
        pressedKeys.contains(LogicalKeyboardKey.controlRight);
    final shift = pressedKeys.contains(LogicalKeyboardKey.shiftLeft) ||
        pressedKeys.contains(LogicalKeyboardKey.shiftRight);
    final alt = pressedKeys.contains(LogicalKeyboardKey.altLeft) ||
        pressedKeys.contains(LogicalKeyboardKey.altRight);
    final meta = pressedKeys.contains(LogicalKeyboardKey.metaLeft) ||
        pressedKeys.contains(LogicalKeyboardKey.metaRight);

    final shortcut = _formatShortcut(
      event.logicalKey,
      includeMeta: meta,
      includeShift: shift,
      includeAlt: alt,
      includeControl: ctrl,
    );

    final data = ShortcutData.fromKeyEvent(
      event,
      shortcut,
      ctrl: ctrl,
      shift: shift,
      alt: alt,
      meta: meta,
    );

    setState(() => _value = shortcut);
    if (data != null) {
      _updateProvider(data);
    }
    node.unfocus();
    return KeyEventResult.handled;
  }

  void _updateProvider(ShortcutData? data) {
    final id = widget.shortcutId;
    if (id == null) return;
    ref
        .read(
          id == ShortcutId.spotlight
              ? spotlightShortcutProvider.notifier
              : lockVaultShortcutProvider.notifier,
        )
        .state = data;
    unawaited(ShortcutService.instance.save(id.storageKey, data));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 240,
          child: Text(
            widget.label,
            style: _text(
              13,
              _settingsTextPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Focus(
            focusNode: _focusNode,
            onKeyEvent: _handleKeyEvent,
            child: GestureDetector(
              onTap: () => _focusNode.requestFocus(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _focusNode.hasFocus
                        ? _settingsSelectedBlue
                        : _settingsFieldBorder,
                    width: _focusNode.hasFocus ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _value ?? 'Enter shortcut',
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          13,
                          _value == null
                              ? const Color(0xFF9CA1A8)
                              : _settingsTextPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() => _value = null);
                        _focusNode.unfocus();
                        _updateProvider(null);
                      },
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Color(0xFF969696),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsPaneHeading extends StatelessWidget {
  const _SettingsPaneHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: _text(
        14,
        _settingsTextPrimary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

bool _isModifierKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight;
}

String _formatShortcut(
  LogicalKeyboardKey key, {
  required bool includeMeta,
  required bool includeShift,
  required bool includeAlt,
  required bool includeControl,
}) {
  return formatShortcutForPlatform(
    ctrl: includeControl,
    alt: includeAlt,
    shift: includeShift,
    meta: includeMeta,
    keyLabel: _displayLabelForKey(key),
  );
}

String _displayLabelForKey(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.space) {
    return 'Space';
  }
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    return 'Return';
  }
  if (key == LogicalKeyboardKey.tab) {
    return 'Tab';
  }
  if (key == LogicalKeyboardKey.escape) {
    return 'Esc';
  }
  if (key == LogicalKeyboardKey.backspace) {
    return Platform.isWindows ? 'Backspace' : '⌫';
  }
  if (key == LogicalKeyboardKey.delete) {
    return 'Del';
  }
  if (key == LogicalKeyboardKey.backslash) {
    return '\\';
  }

  final label = key.keyLabel.trim();
  if (label.isNotEmpty) {
    return label.length == 1 ? label.toUpperCase() : _capitalize(label);
  }

  final debugName = key.debugName ?? '';
  if (debugName.startsWith('Digit') && debugName.length == 6) {
    return debugName.substring(5);
  }
  if (debugName.startsWith('Key') && debugName.length == 4) {
    return debugName.substring(3);
  }
  return _capitalize(debugName.replaceAll(' ', ''));
}

String _capitalize(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toUpperCase() + value.substring(1);
}

String _appearanceTextSizeLabel(_AppearanceTextSizeOption option) {
  switch (option) {
    case _AppearanceTextSizeOption.smallerMinus:
      return 'Smaller -';
    case _AppearanceTextSizeOption.smaller:
      return 'Smaller';
    case _AppearanceTextSizeOption.defaultSize:
      return 'Default';
    case _AppearanceTextSizeOption.larger:
      return 'Larger';
    case _AppearanceTextSizeOption.largerPlus:
      return 'Larger +';
  }
}

String _vaultDomainSettingLabel(_VaultDomainSetting setting) {
  switch (setting) {
    case _VaultDomainSetting.defaultMatchDetection:
      return 'Default';
    case _VaultDomainSetting.baseDomain:
      return 'Base domain';
    case _VaultDomainSetting.subdomain:
      return 'Subdomain';
  }
}

String _vaultDomainSettingDescription(_VaultDomainSetting setting) {
  switch (setting) {
    case _VaultDomainSetting.defaultMatchDetection:
      return 'Uses the standard match detection logic to decide when an item belongs to the current site.';
    case _VaultDomainSetting.baseDomain:
      return 'Matches across the main registered domain, such as sharing one login between app.example.com and billing.example.com.';
    case _VaultDomainSetting.subdomain:
      return 'Requires an exact subdomain match, which is stricter and helpful when different subdomains use different accounts.';
  }
}

String _vaultAutoLockTimeoutLabel(_VaultAutoLockTimeout timeout) {
  switch (timeout) {
    case _VaultAutoLockTimeout.fifteenMinutes:
      return '15 mins';
    case _VaultAutoLockTimeout.thirtyMinutes:
      return '30 mins';
    case _VaultAutoLockTimeout.oneHour:
      return '1 hour';
    case _VaultAutoLockTimeout.fourHours:
      return '4 hours';
    case _VaultAutoLockTimeout.eightHours:
      return '8 hours';
    case _VaultAutoLockTimeout.twentyFourHours:
      return '24 hours';
    case _VaultAutoLockTimeout.never:
      return 'Never';
  }
}

String _vaultAutoLockTimeoutDescription(_VaultAutoLockTimeout timeout) {
  switch (timeout) {
    case _VaultAutoLockTimeout.fifteenMinutes:
      return 'Locks quickly after short inactivity to reduce exposure on shared or public devices.';
    case _VaultAutoLockTimeout.thirtyMinutes:
      return 'A balanced default that keeps the vault convenient without staying open too long.';
    case _VaultAutoLockTimeout.oneHour:
      return 'Useful for longer work sessions while still re-locking during extended idle time.';
    case _VaultAutoLockTimeout.fourHours:
      return 'Keeps the vault unlocked through a substantial work block with less frequent reauthentication.';
    case _VaultAutoLockTimeout.eightHours:
      return 'Fits a full workday when the device itself is already protected and closely supervised.';
    case _VaultAutoLockTimeout.twentyFourHours:
      return 'Leaves the vault available across the day and night, which is best reserved for trusted personal machines.';
    case _VaultAutoLockTimeout.never:
      return 'Disables idle re-locking, which is the least secure option and should only be used on tightly controlled devices.';
  }
}

String _vaultClipboardClearLabel(_VaultClipboardClearOption option) {
  switch (option) {
    case _VaultClipboardClearOption.thirtySeconds:
      return '30s';
    case _VaultClipboardClearOption.sixtySeconds:
      return '60s';
    case _VaultClipboardClearOption.ninetySeconds:
      return '90s';
    case _VaultClipboardClearOption.never:
      return 'Never';
  }
}

String _vaultClipboardClearDescription(_VaultClipboardClearOption option) {
  switch (option) {
    case _VaultClipboardClearOption.thirtySeconds:
      return 'Clears copied secrets quickly to minimize the chance they stay available to other apps.';
    case _VaultClipboardClearOption.sixtySeconds:
      return 'Provides a bit more time to paste while still automatically removing sensitive content soon after.';
    case _VaultClipboardClearOption.ninetySeconds:
      return 'Allows a longer grace period when users often copy across several windows before pasting.';
    case _VaultClipboardClearOption.never:
      return 'Leaves copied values in the clipboard until they are replaced manually, which is convenient but less secure.';
  }
}

String _backupRetentionDaysLabel(_BackupRetentionDays retention) {
  switch (retention) {
    case _BackupRetentionDays.threeDays:
      return '3 days';
    case _BackupRetentionDays.sevenDays:
      return '7 days';
    case _BackupRetentionDays.twentyOneDays:
      return '21 days';
    case _BackupRetentionDays.thirtyDays:
      return '30 days';
  }
}

// ── PIN / biometric setup dialogs ────────────────────────────────────────────

class _PasswordConfirmDialog extends StatefulWidget {
  const _PasswordConfirmDialog();

  @override
  State<_PasswordConfirmDialog> createState() => _PasswordConfirmDialogState();
}

class _PasswordConfirmDialogState extends State<_PasswordConfirmDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final password = _controller.text.trim();
    if (password.isEmpty) return;
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF3FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      TablerIcons.lock,
                      size: 18,
                      color: Color(0xFF4B6CFF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Confirm master password',
                          style: _text(
                            15,
                            _settingsTextPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Required to set up this unlock method',
                          style: _text(11, _settingsTextSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                obscureText: _obscure,
                autofocus: true,
                style: _text(13, _settingsTextPrimary),
                decoration: InputDecoration(
                  hintText: 'Enter your master password',
                  hintStyle: _text(13, _settingsTextSecondary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _settingsDividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _settingsDividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Color(0xFF4B6CFF),
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? TablerIcons.eye : TablerIcons.eye_off,
                      size: 16,
                      color: _settingsTextSecondary,
                    ),
                  ),
                ),
                onSubmitted: (_) => _confirm(),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: _text(
                        13,
                        _settingsTextSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimaryButtonColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('Confirm'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog();

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  List<int> _digits = const [];
  List<int>? _firstEntry;
  bool _mismatch = false;

  bool get _isConfirmStep => _firstEntry != null;

  void _addDigit(int d) {
    if (_digits.length >= 6 || _mismatch) return;
    final updated = <int>[..._digits, d];
    setState(() => _digits = updated);
    if (updated.length == 6) _onSixDigits(updated);
  }

  void _removeDigit() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.sublist(0, _digits.length - 1));
  }

  void _onSixDigits(List<int> digits) {
    if (_firstEntry == null) {
      setState(() {
        _firstEntry = List<int>.unmodifiable(digits);
        _digits = const [];
      });
    } else {
      if (_listEq(digits, _firstEntry!)) {
        Navigator.of(context).pop(digits.map((d) => '$d').join());
      } else {
        setState(() {
          _mismatch = true;
          _digits = const [];
        });
        Future<void>.delayed(const Duration(milliseconds: 700), () {
          if (mounted) {
            setState(() {
              _mismatch = false;
              _firstEntry = null;
            });
          }
        });
      }
    }
  }

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 8),
              child: Column(
                children: <Widget>[
                  Text(
                    _isConfirmStep ? 'Confirm your PIN' : 'Create your PIN',
                    style: _text(
                      17,
                      _settingsTextPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isConfirmStep
                        ? 'Re-enter your 6-digit PIN to confirm'
                        : 'Choose a 6-digit PIN for quick unlock',
                    style: _text(12, _settingsTextSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(6, (i) {
                      final filled = i < _digits.length;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _mismatch
                                ? const Color(0xFFEF4444)
                                : filled
                                    ? const Color(0xFF4B6CFF)
                                    : Colors.transparent,
                            border: Border.all(
                              color: _mismatch
                                  ? const Color(0xFFEF4444)
                                  : filled
                                      ? const Color(0xFF4B6CFF)
                                      : _settingsDividerColor,
                              width: 1.5,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  if (_mismatch) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      'PINs do not match \u2014 try again',
                      style: _text(11, const Color(0xFFEF4444)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  for (final row in <List<int>>[
                    <int>[1, 2, 3],
                    <int>[4, 5, 6],
                    <int>[7, 8, 9],
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: row
                            .map(
                              (n) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  child: _SetupPinKey(
                                    label: '$n',
                                    onTap: () => _addDigit(n),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  Row(
                    children: <Widget>[
                      const Expanded(child: SizedBox.shrink()),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: _SetupPinKey(
                            label: '0',
                            onTap: () => _addDigit(0),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: _SetupPinKey(
                            icon: TablerIcons.backspace,
                            onTap: _removeDigit,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            const Divider(height: 1, color: _settingsDividerColor),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: _text(
                        13,
                        _settingsTextSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Disable unlock method confirmation dialog ────────────────────────────────

class _DisableUnlockMethodDialog extends StatelessWidget {
  const _DisableUnlockMethodDialog({
    required this.method,
    required this.description,
  });

  final String method;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      TablerIcons.shield_off,
                      size: 18,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Disable $method',
                          style: _text(
                            15,
                            _settingsTextPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'This unlock method will be turned off',
                          style: _text(11, _settingsTextSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                description,
                style: _text(
                  12,
                  _settingsTextSecondary,
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      'Cancel',
                      style: _text(
                        13,
                        _settingsTextSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    child: Text('Disable $method'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupPinKey extends StatefulWidget {
  const _SetupPinKey({this.label, this.icon, required this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  State<_SetupPinKey> createState() => _SetupPinKeyState();
}

class _SetupPinKeyState extends State<_SetupPinKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        height: 52,
        decoration: BoxDecoration(
          color: _pressed ? const Color(0xFFEEF3FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _pressed ? const Color(0xFF4B6CFF) : _settingsDividerColor,
          ),
        ),
        alignment: Alignment.center,
        child: widget.icon != null
            ? Icon(widget.icon, size: 16, color: _settingsTextSecondary)
            : Text(
                widget.label!,
                style: _text(
                  18,
                  _settingsTextPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
