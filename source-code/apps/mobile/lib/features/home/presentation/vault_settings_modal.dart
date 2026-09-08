import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../autofill/application/autofill_bridge.dart';
import '../../autofill/application/autofill_providers.dart';
import '../../home/application/home_vault_providers.dart';
import '../../home/application/mobile_home_tab_provider.dart';
import '../../settings/application/general_settings_provider.dart';
import '../../settings/application/vault_security_provider.dart';
import '../../../core/repository/providers.dart';
import '../../../core/services/app_runtime_info.dart';
import '../../../core/services/biometric_auth_service.dart';

import '../../../core/ui/app_snack_bar.dart';
import '../../../l10n/app_localizations.dart';

void showVaultSettingsModal(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _VaultSettingsSheet(),
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// Palette (shared across settings screens)
// ──────────────────────────────────────────────────────────────────────────────

const Color _kBackground = Color(0xFFF2F4F6);
const Color _kCard = Colors.white;
const Color _kDivider = Color(0xFFE3EAF0);
const Color _kLabel = Color(0xFF0A3B48);
const Color _kSecondaryLabel = Color(0xFF6B7A83);
const Color _kChevron = Color(0xFFB5C4CB);
const Color _kBlue = Color(0xFF007AFF);
const Color _kFooterNote = Color(0xFF6B7A83);

// ──────────────────────────────────────────────────────────────────────────────
// Section identifiers + data
// ──────────────────────────────────────────────────────────────────────────────

enum _SettingsSectionId {
  general,
  security,
  backup,
  autofill,
  advanced,
  about,
  rate,
}

class _SettingsItem {
  const _SettingsItem({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    this.isExternal = false,
  });

  final _SettingsSectionId id;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final bool isExternal;
}

class _SettingsSection {
  const _SettingsSection({required this.title, required this.items});
  final String title;
  final List<_SettingsItem> items;
}

List<_SettingsSection> _settingsSections(AppL10n l) => [
  _SettingsSection(
    title: l.settingsSectionPersonalization,
    items: [
      _SettingsItem(
        id: _SettingsSectionId.general,
        label: l.settingsGeneralLabel,
        subtitle: l.settingsGeneralSubtitle,
        icon: Icons.tune_rounded,
        iconColor: const Color(0xFF14B8A6),
      ),
    ],
  ),
  _SettingsSection(
    title: l.settingsSectionSecurity,
    items: [
      _SettingsItem(
        id: _SettingsSectionId.security,
        label: l.settingsSecurityLabel,
        subtitle: l.settingsSecuritySubtitle,
        icon: Icons.shield_outlined,
        iconColor: const Color(0xFF0EA5E9),
      ),
      _SettingsItem(
        id: _SettingsSectionId.autofill,
        label: l.settingsAutofillLabel,
        subtitle: l.settingsAutofillSubtitle,
        icon: Icons.bolt_outlined,
        iconColor: const Color(0xFF3B82F6),
      ),
    ],
  ),
  _SettingsSection(
    title: l.settingsSectionSyncBackup,
    items: [
      _SettingsItem(
        id: _SettingsSectionId.backup,
        label: l.settingsBackupLabel,
        subtitle: l.settingsBackupSubtitle,
        icon: Icons.cloud_sync_outlined,
        iconColor: const Color(0xFF10B981),
      ),
    ],
  ),
  _SettingsSection(
    title: l.settingsSectionAboutFeedback,
    items: [
      _SettingsItem(
        id: _SettingsSectionId.about,
        label: l.settingsAboutLabel,
        subtitle: l.settingsAboutSubtitle,
        icon: Icons.info_outline_rounded,
        iconColor: const Color(0xFF06B6D4),
      ),
      _SettingsItem(
        id: _SettingsSectionId.rate,
        label: l.settingsRateLabel,
        subtitle: l.settingsRateSubtitle,
        icon: Icons.star_outline_rounded,
        iconColor: const Color(0xFFF59E0B),
        isExternal: true,
      ),
    ],
  ),
];

// ──────────────────────────────────────────────────────────────────────────────
// Sheet
// ──────────────────────────────────────────────────────────────────────────────

class _VaultSettingsSheet extends StatelessWidget {
  const _VaultSettingsSheet();

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final sections = _settingsSections(l);
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: _kBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────────────
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D1D6),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(
                            l.settingsTitle,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: _kLabel,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEEEF0),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  l.commonDone,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: _kLabel,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, thickness: 0.5, color: _kDivider),
                  ],
                ),
              ),

              // ── Scrollable list ──────────────────────────────────────────
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  children: [
                    for (var i = 0; i < sections.length; i++) ...[
                      _SectionHeader(sections[i].title),
                      _SettingsGroup(items: sections[i].items),
                      if (i < sections.length - 1) const SizedBox(height: 18),
                    ],
                    const SizedBox(height: 24),
                    const _FooterNote(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Group (card with multiple rows)
// ──────────────────────────────────────────────────────────────────────────────

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.items});

  final List<_SettingsItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isLast = index == items.length - 1;
          return _SettingsRow(item: item, isLast: isLast);
        }),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Row
// ──────────────────────────────────────────────────────────────────────────────

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.item, required this.isLast});

  final _SettingsItem item;
  final bool isLast;

  void _handleTap(BuildContext context) {
    if (item.id == _SettingsSectionId.rate) {
      _openAppStoreReview(context);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _SettingsDetailScreen(section: item.id),
      ),
    );
  }

  Future<void> _openAppStoreReview(BuildContext context) async {
    // Public App Store listing ID.
    // Android package id mirrors applicationId in android/app/build.gradle.kts.
    const iosAppId = '6762245861';
    const androidPackage = 'com.tranit.lumenpass.android';

    final candidates = <Uri>[
      if (Platform.isIOS) ...[
        Uri.parse(
          'itms-apps://itunes.apple.com/app/id$iosAppId?action=write-review',
        ),
        Uri.parse('https://apps.apple.com/app/id$iosAppId?action=write-review'),
      ] else if (Platform.isAndroid) ...[
        Uri.parse('market://details?id=$androidPackage'),
        Uri.parse(
          'https://play.google.com/store/apps/details?id=$androidPackage',
        ),
      ] else
        Uri.parse('https://www.lumenpass.app'),
    ];

    for (final uri in candidates) {
      try {
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (opened) return;
      } catch (_) {
        // Fall through to the next candidate.
      }
    }

    if (context.mounted) {
      AppSnackBar.error(context, 'Unable to open the App Store right now.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => _handleTap(context),
          borderRadius: isLast
              ? const BorderRadius.vertical(bottom: Radius.circular(14))
              : BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _SettingsListIcon(
                    icon: item.icon,
                    color: item.iconColor,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _kLabel,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _kSecondaryLabel,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(
                    item.isExternal
                        ? Icons.open_in_new_rounded
                        : Icons.chevron_right_rounded,
                    size: 18,
                    color: _kChevron,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          const Padding(
            padding: EdgeInsets.only(left: 52),
            child: Divider(height: 1, thickness: 0.5, color: _kDivider),
          ),
      ],
    );
  }
}

class _SettingsListIcon extends StatelessWidget {
  const _SettingsListIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.24),
            color.withValues(alpha: 0.12),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 0.8),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Footer note
// ──────────────────────────────────────────────────────────────────────────────

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        'If you find LumenPass useful and have a couple of minutes, please leave us a review. It makes a huge difference to us. Thank you in advance.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: _kFooterNote, height: 1.5),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Detail screen (sub-setting pages)
// ──────────────────────────────────────────────────────────────────────────────

class _SettingsDetailScreen extends ConsumerStatefulWidget {
  const _SettingsDetailScreen({required this.section});

  final _SettingsSectionId section;

  @override
  ConsumerState<_SettingsDetailScreen> createState() =>
      _SettingsDetailScreenState();
}

class _SettingsDetailScreenState extends ConsumerState<_SettingsDetailScreen> {
  // Dummy state – replaced with real providers once guide lands.
  final Map<String, bool> _toggles = <String, bool>{};
  final Map<String, String> _values = <String, String>{};

  AppRuntimeInfo? _runtimeInfo;

  @override
  void initState() {
    super.initState();
    if (widget.section == _SettingsSectionId.about) {
      _loadRuntimeInfo();
    }
  }

  Future<void> _loadRuntimeInfo() async {
    final info = await AppRuntimeInfoService.load();
    if (!mounted) return;
    setState(() => _runtimeInfo = info);
  }

  bool _toggleValue(String key, {bool fallback = false}) =>
      _toggles[key] ?? fallback;

  void _setToggle(String key, bool value) =>
      setState(() => _toggles[key] = value);

  String _pickValue(String key, String fallback) => _values[key] ?? fallback;

  Future<void> _pickFromList({
    required String key,
    required String title,
    required List<String> options,
    required String current,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _OptionPickerSheet(title: title, options: options, current: current),
    );
    if (selected != null) {
      setState(() => _values[key] = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _titleFor(widget.section);
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, color: _kBlue, size: 28),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: _kLabel,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0.5),
          child: Divider(height: 0.5, thickness: 0.5, color: _kDivider),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: _buildSectionContent(),
      ),
    );
  }

  String _titleFor(_SettingsSectionId id) {
    final l = AppL10n.of(context);
    switch (id) {
      case _SettingsSectionId.general:
        return l.generalTitle;
      case _SettingsSectionId.security:
        return l.settingsSecurityLabel;
      case _SettingsSectionId.backup:
        return l.settingsBackupLabel;
      case _SettingsSectionId.autofill:
        return l.settingsAutofillLabel;
      case _SettingsSectionId.advanced:
        return 'Advanced';
      case _SettingsSectionId.about:
        return l.settingsAboutLabel;
      case _SettingsSectionId.rate:
        return l.settingsRateLabel;
    }
  }

  List<Widget> _buildSectionContent() {
    switch (widget.section) {
      case _SettingsSectionId.general:
        return _generalContent();
      case _SettingsSectionId.security:
        return _securityContent();
      case _SettingsSectionId.backup:
        return _backupContent();
      case _SettingsSectionId.autofill:
        return _autoFillContent();
      case _SettingsSectionId.advanced:
        return _advancedContent();
      case _SettingsSectionId.about:
        return _aboutContent();
      case _SettingsSectionId.rate:
        return const <Widget>[];
    }
  }

  // ── Dummy content per section ─────────────────────────────────────────────

  List<Widget> _generalContent() {
    final l = AppL10n.of(context);
    final settings = ref.watch(generalSettingsProvider);
    final notifier = ref.read(generalSettingsProvider.notifier);

    final languageLabel = switch (settings.language) {
      AppLanguage.english => l.languageEnglish,
    };
    final defaultTabLabel = _defaultTabLabel(l, settings.defaultTab);
    final quickVaultLabel = switch (settings.quickVaultSelection) {
      QuickVaultSelection.defaultVault => l.quickVaultDefault,
      QuickVaultSelection.lastOpened => l.quickVaultLastOpened,
    };

    return [
      _SectionHeader(l.generalPreferences),
      _DetailGroup(
        children: [
          _ValueRow(
            icon: Icons.language_rounded,
            iconColor: const Color(0xFF0EA5E9),
            title: l.generalLanguage,
            value: languageLabel,
            onTap: () async {
              final selected = await showModalBottomSheet<AppLanguage>(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (_) => _EnumPickerSheet<AppLanguage>(
                  title: l.generalLanguage,
                  current: settings.language,
                  options: AppLanguage.values,
                  labelFor: (value) => switch (value) {
                    AppLanguage.english => l.languageEnglish,
                  },
                ),
              );
              if (selected != null && selected != settings.language) {
                await notifier.setLanguage(selected);
                if (mounted) {
                  AppSnackBar.success(
                    context,
                    '${l.generalLanguage}: ${switch (selected) {
                      AppLanguage.english => l.languageEnglish,
                    }}',
                  );
                }
              }
            },
          ),
          _ValueRow(
            icon: Icons.tab_rounded,
            iconColor: const Color(0xFF14B8A6),
            title: l.generalDefaultTab,
            value: defaultTabLabel,
            onTap: () async {
              final selected = await showModalBottomSheet<MobileHomeTab>(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (_) => _EnumPickerSheet<MobileHomeTab>(
                  title: l.generalDefaultTab,
                  current: settings.defaultTab,
                  options: const [
                    MobileHomeTab.home,
                    MobileHomeTab.items,
                    MobileHomeTab.totp,
                  ],
                  labelFor: (value) => _defaultTabLabel(l, value),
                ),
              );
              if (selected != null && selected != settings.defaultTab) {
                await notifier.setDefaultTab(selected);
                if (mounted) {
                  AppSnackBar.success(
                    context,
                    '${l.generalDefaultTab}: ${_defaultTabLabel(l, selected)}',
                  );
                }
              }
            },
          ),
          _ValueRow(
            icon: Icons.history_rounded,
            iconColor: const Color(0xFFF59E0B),
            title: l.generalQuickVaultSelection,
            value: quickVaultLabel,
            onTap: () async {
              final selected = await showModalBottomSheet<QuickVaultSelection>(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (_) => _EnumPickerSheet<QuickVaultSelection>(
                  title: l.generalQuickVaultSelection,
                  current: settings.quickVaultSelection,
                  options: QuickVaultSelection.values,
                  labelFor: (value) => switch (value) {
                    QuickVaultSelection.defaultVault => l.quickVaultDefault,
                    QuickVaultSelection.lastOpened => l.quickVaultLastOpened,
                  },
                ),
              );
              if (selected != null &&
                  selected != settings.quickVaultSelection) {
                await notifier.setQuickVaultSelection(selected);
                if (mounted) {
                  AppSnackBar.success(
                    context,
                    '${l.generalQuickVaultSelection}: ${switch (selected) {
                      QuickVaultSelection.defaultVault => l.quickVaultDefault,
                      QuickVaultSelection.lastOpened => l.quickVaultLastOpened,
                    }}',
                  );
                }
              }
            },
          ),
        ],
      ),
      const SizedBox(height: 12),
      _FooterHint(l.generalFooter),
    ];
  }

  String _defaultTabLabel(AppL10n l, MobileHomeTab tab) => switch (tab) {
    MobileHomeTab.home => l.defaultTabHome,
    MobileHomeTab.items => l.defaultTabItems,
    MobileHomeTab.totp => l.defaultTabTotp,
    MobileHomeTab.profile => l.defaultTabProfile,
  };

  List<Widget> _securityContent() {
    // Unlock data is keyed by the vault's stable record id (not its file path,
    // which is unstable across iOS updates). The legacy path->id migration has
    // already run during unlock before this screen is reachable.
    final vaultId = ref.watch(homeVaultRecordProvider.select((r) => r?.id));
    final svc = ref.read(vaultUnlockServiceProvider);
    final bio = ref.read(biometricAuthServiceProvider);
    final security = ref.watch(vaultSecuritySettingsProvider);
    final secNotifier = ref.read(vaultSecuritySettingsProvider.notifier);

    return [
      const _SectionHeader('UNLOCK'),
      _DetailGroup(
        children: [
          _BiometricToggleRow(vaultPath: vaultId, svc: svc, bio: bio),
          _AsyncToggleRow(
            icon: Icons.pin_rounded,
            iconColor: const Color(0xFF5856D6),
            title: 'PIN unlock',

            getValue: () => vaultId == null
                ? Future.value(false)
                : svc.isPinEnabled(vaultId),
            onChanged: (enabled) async {
              if (vaultId == null) return;
              if (enabled) {
                var password = ref.read(cachedMasterPasswordProvider) ?? '';
                if (password.isEmpty) {
                  if (!mounted) return;
                  password =
                      await showModalBottomSheet<String>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _PasswordConfirmSheet(),
                      ) ??
                      '';
                }
                if (password.isEmpty) return;
                if (!mounted) return;
                final pin = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const _PinSetupSheet(),
                );
                if (pin == null || pin.isEmpty) return;
                await svc.setupPin(vaultId, pin, password);
                await svc.setPinEnabled(vaultId, true);
                if (mounted) {
                  AppSnackBar.success(context, 'PIN unlock enabled');
                }
              } else {
                final confirmed = await _confirmDisableUnlock(
                  context,
                  method: 'PIN code',
                  description:
                      'PIN unlock will be removed. You can re-enable it at any time.',
                );
                if (confirmed != true) return;
                await svc.clearPinData(vaultId);
                if (mounted) {
                  AppSnackBar.info(context, 'PIN unlock disabled');
                }
              }
            },
          ),
          _ValueRow(
            icon: Icons.lock_clock_rounded,
            iconColor: const Color(0xFF007AFF),
            title: 'Auto-lock',
            value: security.autoLock.label,
            onTap: () async {
              final selected = await showModalBottomSheet<AutoLockTimeout>(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (_) => _EnumPickerSheet<AutoLockTimeout>(
                  title: 'Auto-lock after',
                  current: security.autoLock,
                  options: AutoLockTimeout.values,
                  labelFor: (v) => v.label,
                ),
              );
              if (selected != null && selected != security.autoLock) {
                await secNotifier.setAutoLock(selected);
                if (mounted) {
                  AppSnackBar.success(context, 'Auto-lock: ${selected.label}');
                }
              }
            },
          ),
        ],
      ),

      const SizedBox(height: 16),
      const _SectionHeader('PRIVACY'),
      _DetailGroup(
        children: [
          _ToggleRow(
            icon: Icons.credit_card_rounded,
            iconColor: const Color(0xFF5856D6),
            title: 'Hide full credit card number',
            subtitle: 'Show only the first 4 and last 3 digits when viewing',
            value: security.hideCreditCardNumber,
            onChanged: (v) => secNotifier.setHideCreditCardNumber(v),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const _SectionHeader('CLIPBOARD'),
      _DetailGroup(
        children: [
          _ValueRow(
            icon: Icons.content_paste_off_rounded,
            iconColor: const Color(0xFFFF9500),
            title: 'Clear clipboard',
            value: security.clipboardClear.label,
            onTap: () async {
              final selected =
                  await showModalBottomSheet<ClipboardClearTimeout>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _EnumPickerSheet<ClipboardClearTimeout>(
                      title: 'Clear clipboard after',
                      current: security.clipboardClear,
                      options: ClipboardClearTimeout.values,
                      labelFor: (v) => v.label,
                    ),
                  );
              if (selected != null && selected != security.clipboardClear) {
                await secNotifier.setClipboardClear(selected);
                if (mounted) {
                  AppSnackBar.success(context, 'Clipboard: ${selected.label}');
                }
              }
            },
          ),
        ],
      ),
    ];
  }

  List<Widget> _backupContent() {
    final backupLocation = _pickValue('backupLocation', 'Local Folder');

    return [
      const _SectionHeader('AUTO BACKUP'),
      _DetailGroup(
        children: [
          _ToggleRow(
            icon: Icons.cloud_upload_rounded,
            iconColor: const Color(0xFF007AFF),
            title: 'Auto backup',
            value: _toggleValue('autoBackup', fallback: true),
            onChanged: (v) => _setToggle('autoBackup', v),
          ),
          const _InfoRow(
            icon: Icons.schedule_rounded,
            iconColor: Color(0xFF5856D6),
            title: 'Frequency',
            value: 'Every 4 hours',
          ),
          _ValueRow(
            icon: Icons.hourglass_bottom_rounded,
            iconColor: const Color(0xFFFF9500),
            title: 'Delete backup after',
            value: _pickValue('backupDeleteAfter', '7 days'),
            onTap: () => _pickFromList(
              key: 'backupDeleteAfter',
              title: 'Delete backup after',
              options: const ['3 days', '7 days', '21 days', '30 days'],
              current: _pickValue('backupDeleteAfter', '7 days'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const _SectionHeader('BACKUP LOCATION'),
      _DetailGroup(
        children: [
          _ValueRow(
            icon: Icons.storage_rounded,
            iconColor: const Color(0xFF34C759),
            title: 'Location',
            value: backupLocation,
            onTap: () => _pickFromList(
              key: 'backupLocation',
              title: 'Backup location',
              options: const ['Local Folder', 'Google Drive', 'Dropbox'],
              current: backupLocation,
            ),
          ),
          if (backupLocation == 'Local Folder')
            _ValueRow(
              icon: Icons.folder_open_rounded,
              iconColor: const Color(0xFF007AFF),
              title: 'Backup path',
              value: _pickValue('backupPath', 'Application Support/backups'),
              onTap: () => _showDummy('Choose backup path'),
            ),
          if (backupLocation == 'Google Drive')
            _ValueRow(
              icon: Icons.folder_special_rounded,
              iconColor: const Color(0xFF007AFF),
              title: 'Drive folder',
              value: _pickValue('backupDriveFolder', 'Drive root'),
              onTap: () => _showDummy('Choose Google Drive folder'),
            ),
          if (backupLocation == 'Dropbox')
            _ValueRow(
              icon: Icons.folder_special_rounded,
              iconColor: const Color(0xFF007AFF),
              title: 'Dropbox folder',
              value: _pickValue('backupDropboxFolder', '/Apps/LumenPass'),
              onTap: () => _showDummy('Choose Dropbox folder'),
            ),
        ],
      ),
      const SizedBox(height: 16),
      const _SectionHeader('STATUS'),
      _DetailGroup(
        children: const [
          _InfoRow(
            icon: Icons.history_rounded,
            iconColor: Color(0xFF34C759),
            title: 'Last backup',
            value: 'Today, 09:42',
          ),
          _InfoRow(
            icon: Icons.sd_storage_rounded,
            iconColor: Color(0xFF8E8E93),
            title: 'Backup size',
            value: '2.4 MB',
          ),
        ],
      ),
      const SizedBox(height: 16),
      _DetailGroup(
        children: [
          _ChevronRow(
            icon: Icons.backup_rounded,
            iconColor: const Color(0xFF007AFF),
            title: 'Back up now',
            onTap: () => _showDummy('Backing up…'),
          ),
          _ChevronRow(
            icon: Icons.restore_rounded,
            iconColor: const Color(0xFF5856D6),
            title: 'Restore from backup',
            onTap: () => _showDummy('Restore from backup'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _autoFillContent() {
    final prefs = ref.watch(autoFillPreferencesProvider);
    final prefsNotifier = ref.read(autoFillPreferencesProvider.notifier);
    final statusAsync = ref.watch(autoFillServiceStatusProvider);
    final bridge = ref.read(autoFillBridgeProvider);
    final systemAutoFillEnabled =
        statusAsync.valueOrNull == AutoFillServiceStatus.enabled;

    final (
      statusLabel,
      statusColor,
      statusIcon,
      statusSubtitle,
    ) = switch (statusAsync) {
      AsyncData(value: AutoFillServiceStatus.enabled) => (
        'Enabled in system settings',
        const Color(0xFF34C759),
        Icons.check_circle_rounded,
        'LumenPass is ready to fill your saved logins across the system.',
      ),
      AsyncData(value: AutoFillServiceStatus.disabled) => (
        'Not enabled yet',
        const Color(0xFFFF9500),
        Icons.error_outline_rounded,
        'Turn LumenPass on in the system AutoFill settings to use it '
            'in Safari and other apps.',
      ),
      AsyncData(value: AutoFillServiceStatus.notSupported) => (
        'Not supported on this device',
        const Color(0xFF8E8E93),
        Icons.block_rounded,
        'System AutoFill is unavailable on this device.',
      ),
      AsyncError() => (
        'Status unavailable',
        const Color(0xFF8E8E93),
        Icons.help_outline_rounded,
        'Could not query system AutoFill status. Pull to refresh.',
      ),
      _ => (
        'Checking…',
        const Color(0xFF8E8E93),
        Icons.autorenew_rounded,
        'Querying system AutoFill status.',
      ),
    };

    Future<void> refreshStatus() async {
      ref.invalidate(autoFillServiceStatusProvider);
      await ref.read(autoFillServiceStatusProvider.future);
    }

    return [
      const _SectionHeader('STATUS'),
      _DetailGroup(
        children: [
          _ValueRow(
            icon: statusIcon,
            iconColor: statusColor,
            title: 'System AutoFill',
            value: statusLabel,
            onTap: refreshStatus,
          ),
          _ChevronRow(
            icon: Icons.ios_share_rounded,
            iconColor: _kBlue,
            title: 'Open system AutoFill settings',
            onTap: () async {
              final opened = await bridge.openSystemSettings();
              if (!mounted) return;
              if (!opened) {
                AppSnackBar.error(context, 'Unable to open system settings.');
                return;
              }
              // Give the user time to toggle LumenPass then refresh on return.
              Future<void>.delayed(const Duration(seconds: 1), refreshStatus);
            },
          ),
        ],
      ),
      const SizedBox(height: 6),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          statusSubtitle,
          style: const TextStyle(
            fontSize: 12,
            color: _kFooterNote,
            height: 1.4,
          ),
        ),
      ),
      if (Platform.isAndroid && systemAutoFillEnabled) ...[
        const SizedBox(height: 16),
        const _SectionHeader('CHROME BROWSER'),
        _ChromeAutofillSection(bridge: bridge),
      ],
      const SizedBox(height: 16),
      const _SectionHeader('MATCHING'),
      _DisabledSection(
        enabled: systemAutoFillEnabled,
        child: _DetailGroup(
          children: [
            _ValueRow(
              icon: Icons.link_rounded,
              iconColor: const Color(0xFF34C759),
              title: 'URL match detection',
              value: prefs.matchMode,
              onTap: () async {
                final selected = await showModalBottomSheet<String>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _OptionPickerSheet(
                    title: 'Match detection',
                    options: const [
                      'Base domain',
                      'Domain',
                      'Host',
                      'Exact',
                      'Regex',
                    ],
                    current: prefs.matchMode,
                  ),
                );
                if (selected != null) {
                  await prefsNotifier.setMatchMode(selected);
                }
              },
            ),
            _ToggleRow(
              icon: Icons.check_circle_outline_rounded,
              iconColor: const Color(0xFF34C759),
              title: 'Ask before filling',
              value: prefs.askBeforeFilling,
              onChanged: (v) => prefsNotifier.setAskBeforeFilling(v),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const _FooterHint(
        'AutoFill lets you sign in to apps and websites using items saved in '
        'LumenPass. Credentials are encrypted and shared only with the '
        'LumenPass AutoFill extension.',
      ),
    ];
  }

  List<Widget> _advancedContent() {
    return [
      const _SectionHeader('DATA'),
      _DetailGroup(
        children: [
          _ChevronRow(
            icon: Icons.file_download_outlined,
            iconColor: const Color(0xFF007AFF),
            title: 'Export data',
            onTap: () => _showDummy('Export vault'),
          ),
          _ChevronRow(
            icon: Icons.file_upload_outlined,
            iconColor: const Color(0xFF5856D6),
            title: 'Import data',
            onTap: () => _showDummy('Import vault'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const _SectionHeader('DEVELOPER'),
      _DetailGroup(
        children: [
          _ToggleRow(
            icon: Icons.terminal_rounded,
            iconColor: const Color(0xFF8E8E93),
            title: 'Developer mode',
            value: _toggleValue('devMode', fallback: false),
            onChanged: (v) => _setToggle('devMode', v),
          ),
          _ChevronRow(
            icon: Icons.bug_report_outlined,
            iconColor: const Color(0xFFFF9500),
            title: 'View diagnostic logs',
            onTap: () => _showDummy('Diagnostic logs'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _DetailGroup(
        children: [
          _ChevronRow(
            icon: Icons.restart_alt_rounded,
            iconColor: const Color(0xFFFF3B30),
            title: 'Reset all settings',
            titleColor: const Color(0xFFFF3B30),
            showChevron: false,
            onTap: () => _showDummy('Settings reset'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const _FooterHint(
        'Advanced options are intended for power users. Use with caution.',
      ),
    ];
  }

  List<Widget> _aboutContent() {
    final version = _runtimeInfo?.version.isNotEmpty == true
        ? _runtimeInfo!.version
        : '—';
    final build = _runtimeInfo?.buildNumber.isNotEmpty == true
        ? _runtimeInfo!.buildNumber
        : '—';
    return [
      const SizedBox(height: 8),
      const _AboutHeader(),
      const SizedBox(height: 20),
      _DetailGroup(
        children: [
          _InfoRow(
            icon: Icons.tag_rounded,
            iconColor: const Color(0xFF8E8E93),
            title: 'Version',
            value: version,
          ),
          _InfoRow(
            icon: Icons.build_rounded,
            iconColor: const Color(0xFF8E8E93),
            title: 'Build',
            value: build,
          ),
        ],
      ),
      const SizedBox(height: 16),
      _DetailGroup(
        children: [
          _ChevronRow(
            icon: Icons.privacy_tip_outlined,
            iconColor: const Color(0xFF007AFF),
            title: 'Privacy policy',
            onTap: () => _openExternalUrl('https://www.lumenpass.app/policy'),
          ),
          _ChevronRow(
            icon: Icons.description_outlined,
            iconColor: const Color(0xFF5856D6),
            title: 'Terms of service',
            onTap: () => _openExternalUrl('https://www.lumenpass.app/terms'),
          ),
          _ChevronRow(
            icon: Icons.code_rounded,
            iconColor: const Color(0xFFFF9500),
            title: 'Source code & MPL-2.0 license',
            subtitle: 'github.com/lumenpass/lumenpass',
            isExternal: true,
            onTap: () =>
                _openExternalUrl('https://github.com/lumenpass/lumenpass'),
          ),
          _ChevronRow(
            icon: Icons.language_rounded,
            iconColor: const Color(0xFF34C759),
            title: 'Website',
            subtitle: 'https://www.lumenpass.app',
            isExternal: true,
            onTap: () => _openExternalUrl('https://www.lumenpass.app'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Your vault is encrypted on your device. '
          'Only you hold the keys — not us, not anyone else.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: _kSecondaryLabel, height: 1.45),
        ),
      ),
    ];
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        AppSnackBar.error(context, 'Unable to open $url');
      }
    } catch (_) {
      if (mounted) {
        AppSnackBar.error(context, 'Unable to open $url');
      }
    }
  }

  void _showDummy(String label) {
    AppSnackBar.info(context, '$label (coming soon)');
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Chrome AutoFill setup section (Android only)
// ──────────────────────────────────────────────────────────────────────────────

class _ChromeAutofillSection extends ConsumerWidget {
  const _ChromeAutofillSection({required this.bridge});
  final AutoFillBridge bridge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chromeAsync = ref.watch(chromeThirdPartyModeProvider);

    final (
      statusLabel,
      statusColor,
      statusIcon,
      needsSetup,
    ) = switch (chromeAsync) {
      AsyncData(value: ChromeThirdPartyMode.enabled) => (
        'Enabled',
        const Color(0xFF34C759),
        Icons.check_circle_rounded,
        false,
      ),
      AsyncData(value: ChromeThirdPartyMode.disabled) => (
        'Not enabled',
        const Color(0xFFFF9500),
        Icons.warning_amber_rounded,
        true,
      ),
      _ => (
        'Unknown',
        const Color(0xFF8E8E93),
        Icons.help_outline_rounded,
        false,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailGroup(
          children: [
            _ValueRow(
              icon: statusIcon,
              iconColor: statusColor,
              title: 'Chrome autofill integration',
              value: statusLabel,
              onTap: () {
                ref.invalidate(chromeThirdPartyModeProvider);
              },
            ),
            _ChevronRow(
              icon: Icons.open_in_new_rounded,
              iconColor: _kBlue,
              title: 'Open Chrome autofill settings',
              onTap: () async {
                final ok = await bridge.openChromeAutofillSettings(
                  package_: 'com.android.chrome',
                );
                if (!context.mounted) return;
                if (!ok) {
                  AppSnackBar.error(
                    context,
                    'Chrome is not installed or does not support this setting yet.',
                  );
                  return;
                }
                Future<void>.delayed(const Duration(seconds: 1), () {
                  ref.invalidate(chromeThirdPartyModeProvider);
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (needsSetup)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Chrome 135+ requires an extra step: open Chrome → '
              'Settings → Autofill Services → "Autofill using another '
              'service" and select LumenPass.',
              style: TextStyle(fontSize: 12, color: _kFooterNote, height: 1.4),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Chrome is configured to use LumenPass for autofill.',
              style: TextStyle(fontSize: 12, color: _kFooterNote, height: 1.4),
            ),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Detail UI primitives
// ──────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: _kSecondaryLabel,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _DetailGroup extends StatelessWidget {
  const _DetailGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: List.generate(children.length, (i) {
          final isLast = i == children.length - 1;
          return Column(
            children: [
              children[i],
              if (!isLast)
                const Padding(
                  padding: EdgeInsets.only(left: 54),
                  child: Divider(height: 1, thickness: 0.5, color: _kDivider),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _DisabledSection extends StatelessWidget {
  const _DisabledSection({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !enabled,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        opacity: enabled ? 1 : 0.46,
        child: child,
      ),
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.24),
            color.withValues(alpha: 0.12),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.32), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, size: 18, color: color.withValues(alpha: 0.96)),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          _LeadingIcon(icon: icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, color: _kLabel),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _kSecondaryLabel,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: const Color(0xFF34C759),
            inactiveTrackColor: const Color(0xFFD1D7DD),
          ),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _LeadingIcon(icon: icon, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 16, color: _kLabel),
              ),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 15, color: _kSecondaryLabel),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 20, color: _kChevron),
          ],
        ),
      ),
    );
  }
}

class _ChevronRow extends StatelessWidget {
  const _ChevronRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.titleColor = _kLabel,
    this.showChevron = true,
    this.isExternal = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color titleColor;
  final bool showChevron;
  final bool isExternal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _LeadingIcon(icon: icon, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 16, color: titleColor),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _kSecondaryLabel,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showChevron)
              Icon(
                isExternal
                    ? Icons.open_in_new_rounded
                    : Icons.chevron_right_rounded,
                size: isExternal ? 18 : 20,
                color: _kChevron,
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _LeadingIcon(icon: icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, color: _kLabel),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 15, color: _kSecondaryLabel),
          ),
        ],
      ),
    );
  }
}

class _FooterHint extends StatelessWidget {
  const _FooterHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: _kFooterNote, height: 1.4),
      ),
    );
  }
}

class _AboutHeader extends StatelessWidget {
  const _AboutHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.asset(
            'assets/images/lumenpass-dark.png',
            width: 96,
            height: 96,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'LumenPass',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: _kLabel,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Your Right Privacy Password Manager',
          style: TextStyle(fontSize: 13, color: _kSecondaryLabel),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Option picker sheet (for value rows)
// ──────────────────────────────────────────────────────────────────────────────

Future<bool?> _confirmDisableUnlock(
  BuildContext context, {
  required String method,
  required String description,
}) => showDialog<bool>(
  context: context,
  builder: (ctx) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 22),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Disable $method unlock?',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _kLabel,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(fontSize: 14, color: _kSecondaryLabel),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kLabel,
                    side: const BorderSide(color: _kDivider),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Disable'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  ),
);

// ── Biometric toggle row (checks availability on mount) ───────────────────

class _BiometricToggleRow extends ConsumerStatefulWidget {
  const _BiometricToggleRow({
    required this.vaultPath,
    required this.svc,
    required this.bio,
  });

  final String? vaultPath;
  final VaultUnlockService svc;
  final BiometricAuthService bio;

  @override
  ConsumerState<_BiometricToggleRow> createState() =>
      _BiometricToggleRowState();
}

class _BiometricToggleRowState extends ConsumerState<_BiometricToggleRow> {
  bool _available = true;
  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final available = await widget.bio.isAvailable();
    final enabled = widget.vaultPath == null
        ? false
        : await widget.svc.isBiometricEnabled(widget.vaultPath!);
    if (mounted) {
      setState(() {
        _available = available;
        _enabled = enabled;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(bool enable) async {
    final vaultPath = widget.vaultPath;
    if (vaultPath == null) return;

    if (enable) {
      var password = ref.read(cachedMasterPasswordProvider) ?? '';
      if (password.isEmpty) {
        if (!mounted) return;
        password =
            await showModalBottomSheet<String>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const _PasswordConfirmSheet(),
            ) ??
            '';
      }
      if (password.isEmpty) return;
      final authenticated = await widget.bio.authenticate(
        reason: 'Confirm your identity to enable biometric unlock',
      );
      if (!authenticated || !mounted) return;
      await widget.svc.saveBiometricPassword(vaultPath, password);
      await widget.svc.setBiometricEnabled(vaultPath, true);
      if (mounted) {
        setState(() => _enabled = true);
        AppSnackBar.success(context, 'Biometric unlock enabled');
      }
    } else {
      final confirmed = await _confirmDisableUnlock(
        context,
        method: 'Biometric',
        description:
            'Biometric unlock will be removed. You can re-enable it at any time.',
      );
      if (confirmed != true || !mounted) return;
      await widget.svc.clearBiometricData(vaultPath);
      if (mounted) {
        setState(() => _enabled = false);
        AppSnackBar.info(context, 'Biometric unlock disabled');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canToggle = _available;
    final subtitle = !_available ? 'Not available on this device' : null;
    return Opacity(
      opacity: canToggle ? 1.0 : 0.45,
      child: _ToggleRow(
        icon: Icons.fingerprint_rounded,
        iconColor: const Color(0xFF34C759),
        title: 'Biometric unlock',
        subtitle: subtitle,
        value: _enabled,
        onChanged: (_loading || !canToggle) ? null : _toggle,
      ),
    );
  }
}

// ── Async toggle row (loads initial state from a Future) ───────────────────

class _AsyncToggleRow extends StatefulWidget {
  const _AsyncToggleRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.getValue,
    this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;

  final Future<bool> Function() getValue;
  final Future<void> Function(bool)? onChanged;

  @override
  State<_AsyncToggleRow> createState() => _AsyncToggleRowState();
}

class _AsyncToggleRowState extends State<_AsyncToggleRow> {
  bool _value = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final v = await widget.getValue();
    if (mounted) {
      setState(() {
        _value = v;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _loading || widget.onChanged == null;
    return Opacity(
      opacity: disabled && !_loading ? 0.45 : 1.0,
      child: _ToggleRow(
        icon: widget.icon,
        iconColor: widget.iconColor,
        title: widget.title,
        value: _value,
        onChanged: disabled
            ? null
            : (v) async {
                final prev = _value;
                setState(() => _value = v);
                try {
                  await widget.onChanged!(v);
                  final actual = await widget.getValue();
                  if (mounted) setState(() => _value = actual);
                } catch (_) {
                  if (mounted) setState(() => _value = prev);
                }
              },
      ),
    );
  }
}

// ── Password confirm sheet (for quick-unlock users setting up PIN/biometric) ─

class _PasswordConfirmSheet extends StatefulWidget {
  const _PasswordConfirmSheet();

  @override
  State<_PasswordConfirmSheet> createState() => _PasswordConfirmSheetState();
}

class _PasswordConfirmSheetState extends State<_PasswordConfirmSheet> {
  final _ctrl = TextEditingController();
  bool _obscure = true;
  final bool _submitting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final pw = _ctrl.text.trim();
    if (pw.isEmpty) return;
    Navigator.of(context).pop(pw);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: _kBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D1D6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Confirm your password',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: _kLabel,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enter your master password to enable this unlock method.',
                style: TextStyle(fontSize: 14, color: _kSecondaryLabel),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ctrl,
                obscureText: _obscure,
                autofocus: true,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Master password',
                  filled: true,
                  fillColor: _kCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: _kSecondaryLabel,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0A3B48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Confirm'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: _kSecondaryLabel),
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

// ── PIN setup bottom sheet ─────────────────────────────────────────────────

class _PinSetupSheet extends StatefulWidget {
  const _PinSetupSheet();

  @override
  State<_PinSetupSheet> createState() => _PinSetupSheetState();
}

class _PinSetupSheetState extends State<_PinSetupSheet> {
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
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: _kBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D1D6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _isConfirmStep ? 'Confirm your PIN' : 'Create your PIN',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _kLabel,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isConfirmStep
                  ? 'Re-enter your 6-digit PIN to confirm'
                  : 'Choose a 6-digit PIN for quick unlock',
              style: const TextStyle(fontSize: 13, color: _kSecondaryLabel),
            ),
            const SizedBox(height: 28),
            // Dot indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(6, (i) {
                final filled = i < _digits.length;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _mismatch
                          ? const Color(0xFFEF4444)
                          : filled
                          ? _kBlue
                          : Colors.transparent,
                      border: Border.all(
                        color: _mismatch
                            ? const Color(0xFFEF4444)
                            : filled
                            ? _kBlue
                            : _kDivider,
                        width: 1.5,
                      ),
                    ),
                  ),
                );
              }),
            ),
            if (_mismatch) ...[
              const SizedBox(height: 8),
              const Text(
                'PINs do not match — try again',
                style: TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
              ),
            ],
            const SizedBox(height: 24),
            // Numpad
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  for (final row in <List<int>>[
                    [1, 2, 3],
                    [4, 5, 6],
                    [7, 8, 9],
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: row
                            .map(
                              (n) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: _PinKey(
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
                    children: [
                      const Expanded(child: SizedBox()),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: _PinKey(label: '0', onTap: () => _addDigit(0)),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: _PinKey(
                            icon: TablerIcons.backspace,
                            onTap: _removeDigit,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: _kSecondaryLabel),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinKey extends StatelessWidget {
  const _PinKey({this.label, this.icon, required this.onTap});
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 58,
          child: Center(
            child: icon != null
                ? Icon(icon, size: 22, color: _kLabel)
                : Text(
                    label!,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: _kLabel,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

class _OptionPickerSheet extends StatelessWidget {
  const _OptionPickerSheet({
    required this.title,
    required this.options,
    required this.current,
  });

  final String title;
  final List<String> options;
  final String current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: _kBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D1D6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: _kLabel,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Container(
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: List.generate(options.length, (i) {
                    final option = options[i];
                    final selected = option == current;
                    final isLast = i == options.length - 1;
                    return Column(
                      children: [
                        InkWell(
                          onTap: () => Navigator.of(context).pop(option),
                          borderRadius: isLast
                              ? const BorderRadius.vertical(
                                  bottom: Radius.circular(14),
                                )
                              : BorderRadius.zero,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    option,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: _kLabel,
                                    ),
                                  ),
                                ),
                                if (selected)
                                  const Icon(
                                    Icons.check_rounded,
                                    size: 20,
                                    color: _kBlue,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (!isLast)
                          const Padding(
                            padding: EdgeInsets.only(left: 16),
                            child: Divider(
                              height: 1,
                              thickness: 0.5,
                              color: _kDivider,
                            ),
                          ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnumPickerSheet<T> extends StatelessWidget {
  const _EnumPickerSheet({
    required this.title,
    required this.options,
    required this.current,
    required this.labelFor,
  });

  final String title;
  final List<T> options;
  final T current;
  final String Function(T value) labelFor;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: _kBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D1D6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: _kLabel,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Container(
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: List.generate(options.length, (i) {
                    final option = options[i];
                    final selected = option == current;
                    final isLast = i == options.length - 1;
                    return Column(
                      children: [
                        InkWell(
                          onTap: () => Navigator.of(context).pop(option),
                          borderRadius: isLast
                              ? const BorderRadius.vertical(
                                  bottom: Radius.circular(14),
                                )
                              : BorderRadius.zero,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    labelFor(option),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: _kLabel,
                                    ),
                                  ),
                                ),
                                if (selected)
                                  const Icon(
                                    Icons.check_rounded,
                                    size: 20,
                                    color: _kBlue,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (!isLast)
                          const Padding(
                            padding: EdgeInsets.only(left: 16),
                            child: Divider(
                              height: 1,
                              thickness: 0.5,
                              color: _kDivider,
                            ),
                          ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
