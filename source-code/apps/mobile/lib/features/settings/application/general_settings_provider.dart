import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/repository/providers.dart';
import '../../home/application/mobile_home_tab_provider.dart';

enum AppLanguage { english }

extension AppLanguageX on AppLanguage {
  String get code {
    switch (this) {
      case AppLanguage.english:
        return 'en';
    }
  }

  static AppLanguage fromCode(String? code) {
    switch (code) {
      default:
        return AppLanguage.english;
    }
  }
}

enum QuickVaultSelection { defaultVault, lastOpened }

extension QuickVaultSelectionX on QuickVaultSelection {
  String get storageKey => switch (this) {
        QuickVaultSelection.defaultVault => 'defaultVault',
        QuickVaultSelection.lastOpened => 'lastOpened',
      };

  static QuickVaultSelection fromStorage(String? value) {
    switch (value) {
      case 'lastOpened':
        return QuickVaultSelection.lastOpened;
      default:
        return QuickVaultSelection.defaultVault;
    }
  }
}

@immutable
class GeneralSettings {
  const GeneralSettings({
    this.language = AppLanguage.english,
    this.defaultTab = MobileHomeTab.home,
    this.quickVaultSelection = QuickVaultSelection.defaultVault,
    this.lastOpenedVaultId,
  });

  final AppLanguage language;
  final MobileHomeTab defaultTab;
  final QuickVaultSelection quickVaultSelection;
  final String? lastOpenedVaultId;

  GeneralSettings copyWith({
    AppLanguage? language,
    MobileHomeTab? defaultTab,
    QuickVaultSelection? quickVaultSelection,
    String? lastOpenedVaultId,
    bool clearLastOpened = false,
  }) {
    return GeneralSettings(
      language: language ?? this.language,
      defaultTab: defaultTab ?? this.defaultTab,
      quickVaultSelection: quickVaultSelection ?? this.quickVaultSelection,
      lastOpenedVaultId:
          clearLastOpened ? null : (lastOpenedVaultId ?? this.lastOpenedVaultId),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'language': language.code,
        'defaultTab': defaultTab.name,
        'quickVaultSelection': quickVaultSelection.storageKey,
        if (lastOpenedVaultId != null) 'lastOpenedVaultId': lastOpenedVaultId,
      };

  static GeneralSettings fromJson(Map<String, dynamic> json) {
    final tabName = json['defaultTab'] as String?;
    final tab = MobileHomeTab.values.firstWhere(
      (t) => t.name == tabName,
      orElse: () => MobileHomeTab.home,
    );
    return GeneralSettings(
      language: AppLanguageX.fromCode(json['language'] as String?),
      defaultTab: tab,
      quickVaultSelection: QuickVaultSelectionX.fromStorage(
        json['quickVaultSelection'] as String?,
      ),
      lastOpenedVaultId: json['lastOpenedVaultId'] as String?,
    );
  }
}

class GeneralSettingsNotifier extends StateNotifier<GeneralSettings> {
  GeneralSettingsNotifier(this._ref) : super(const GeneralSettings()) {
    _load();
  }

  static const _kStorageKey = 'lumenpass_general_settings_v1';

  final Ref _ref;

  Future<void> _load() async {
    try {
      final raw = await _ref.read(localStorageProvider).read(_kStorageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      state = GeneralSettings.fromJson(decoded);
    } catch (_) {
      // Ignore corrupt prefs; fall back to defaults.
    }
  }

  Future<void> _persist() async {
    try {
      await _ref
          .read(localStorageProvider)
          .write(_kStorageKey, jsonEncode(state.toJson()));
    } catch (_) {}
  }

  Future<void> setLanguage(AppLanguage value) async {
    state = state.copyWith(language: value);
    await _persist();
  }

  Future<void> setDefaultTab(MobileHomeTab value) async {
    state = state.copyWith(defaultTab: value);
    await _persist();
  }

  Future<void> setQuickVaultSelection(QuickVaultSelection value) async {
    state = state.copyWith(quickVaultSelection: value);
    await _persist();
  }

  Future<void> recordLastOpenedVault(String vaultId) async {
    if (state.lastOpenedVaultId == vaultId) return;
    state = state.copyWith(lastOpenedVaultId: vaultId);
    await _persist();
  }
}

final generalSettingsProvider =
    StateNotifierProvider<GeneralSettingsNotifier, GeneralSettings>(
      (ref) => GeneralSettingsNotifier(ref),
    );
