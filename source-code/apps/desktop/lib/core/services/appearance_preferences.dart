import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/repository/kdbx_repository_provider.dart';

const String appearanceTextSizeDeltaKey = 'appearance.textSizeDelta';
const String appearanceFontFamilyKey = 'appearance.fontFamily';

const int appearanceTextSizeDeltaDefault = 0;
const String appearanceFontFamilyDefault = 'Inter';

/// Live globals read by _text() helper in vault_screen_theme.dart.
/// Updated by LumenPassApp every build cycle before descendent builds run.
int currentTextSizeDelta = appearanceTextSizeDeltaDefault;
String currentFontFamily = appearanceFontFamilyDefault;

final appearanceTextSizeDeltaProvider = StateProvider<int>(
  (ref) => appearanceTextSizeDeltaDefault,
);

final appearanceFontFamilyProvider = StateProvider<String>(
  (ref) => appearanceFontFamilyDefault,
);

Future<void> loadAppearancePreferences(ProviderContainer container) async {
  final storage = container.read(localStorageProvider);

  final deltaStr = await storage.read(key: appearanceTextSizeDeltaKey);
  if (deltaStr != null) {
    final delta = int.tryParse(deltaStr);
    if (delta != null && delta >= -2 && delta <= 2) {
      container.read(appearanceTextSizeDeltaProvider.notifier).state = delta;
      currentTextSizeDelta = delta;
    }
  }

  final fontFamily = await storage.read(key: appearanceFontFamilyKey);
  if (fontFamily != null && fontFamily.isNotEmpty) {
    container.read(appearanceFontFamilyProvider.notifier).state = fontFamily;
    currentFontFamily = fontFamily;
  }
}
