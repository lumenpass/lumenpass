import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repository/providers.dart';

/// Storage key for [vaultAutoFetchItemIconProvider]. Persisted through the
/// mobile `LocalStorageService` (SharedPreferences). Name is shared with
/// the desktop preference store so behavior stays consistent per-user on
/// shared devices.
const String vaultAutoFetchItemIconKey = 'vault.autoFetchItemIcon';

/// User toggle: should we fetch website favicons over the network for
/// login entries that don't have a cached icon yet?
///
/// Default mirrors the desktop default of `true` — fetch by default so
/// new vaults still show rich icons without forcing the user into
/// settings first.
final vaultAutoFetchItemIconProvider = StateProvider<bool>((ref) => true);

/// In-session cache: favicon URL → true (loaded OK) | false (failed).
/// A missing key means the URL has not been attempted this session.
///
/// This is the key piece that keeps the behavior identical to desktop:
///   * a URL that already succeeded this session keeps its icon visible
///     even if the user flips the toggle off mid-session;
///   * a URL that failed this session is not retried for every tile
///     rebuild — we wait for the next cold start (when the persisted
///     failure sentinel on the entry short-circuits it for good).
final faviconFetchResultProvider =
    StateProvider<Map<String, bool>>((ref) => {});

/// Hydrates the vault-level preferences from local storage. Called once
/// at app startup; silently no-ops if the key is missing or corrupt so
/// first-launch users get the documented defaults.
Future<void> loadMobileVaultPreferences(ProviderContainer container) async {
  final storage = container.read(localStorageProvider);

  try {
    final iconStr = await storage.read(vaultAutoFetchItemIconKey);
    if (iconStr != null) {
      container.read(vaultAutoFetchItemIconProvider.notifier).state =
          iconStr == 'true';
    }
  } catch (_) {
    // Preferences are best-effort; a corrupt value should not crash
    // app startup — fall back to the in-memory default.
  }
}

/// Convenience: update the auto-fetch toggle and persist the new value.
Future<void> setVaultAutoFetchItemIcon(
  ProviderContainer container,
  bool value,
) async {
  container.read(vaultAutoFetchItemIconProvider.notifier).state = value;
  try {
    await container
        .read(localStorageProvider)
        .write(vaultAutoFetchItemIconKey, value.toString());
  } catch (_) {
    // Non-fatal: the in-memory value is already updated so the UI reacts
    // immediately; the write can be retried on next toggle.
  }
}
