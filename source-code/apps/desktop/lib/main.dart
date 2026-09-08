import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/services/appearance_preferences.dart';
import 'core/services/general_preferences.dart';
import 'core/services/vault_preferences.dart';
import 'core/services/browser_extension_provider.dart';
import 'core/services/browser_extension_service.dart';
import 'core/services/backup_service.dart';
import 'core/services/cloud_sync_service.dart';
import 'core/services/pinned_http_client.dart';
import 'core/services/removed_account_data_cleanup.dart';
import 'core/services/ssh_agent_service.dart';
import 'core/services/tray_service.dart';
import 'core/repository/kdbx_repository_provider.dart';

import 'features/cloud/presentation/cloud_services_screen.dart';
import 'features/unlock/presentation/unlock_screen.dart';
import 'features/vault/presentation/vault_screen.dart';
import 'presentation/theme/app_theme.dart';

final _container = ProviderContainer();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // On Linux the GTK embedder cannot launch a custom Dart entrypoint, so the
  // isolated Quick Search engine runs this same `main()` with a sentinel
  // argument instead (see QuickSearchPanel in linux/runner/). Detect it as
  // early as possible and delegate to the dedicated entrypoint before any of
  // the main-app services (tray, cloud sync, backup) boot.
  if (args.contains('--quick-search-panel')) {
    return quickSearchMain();
  }
  HttpOverrides.global = PinningHttpOverrides();
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
  }
  await cleanupRemovedDesktopAccountData(
    _container.read(localStorageProvider),
  );
  if (Platform.isMacOS || Platform.isWindows) {
    await TrayService.instance.init(_container);
  }
  await loadAppearancePreferences(_container);
  await loadVaultPreferences(_container);
  await loadGeneralPreferences(_container);
  initCloudSyncService(_container);
  await BackupService.instance.init(_container);
  runApp(UncontrolledProviderScope(
      container: _container, child: const LumenPassApp()));
}

/// Entry point for the **isolated Quick Search window** (Option A).
///
/// This runs in a *second* Flutter engine hosted by a borderless native
/// panel (see `QuickSearchPanel` in `macos/Runner/MainFlutterWindow.swift`).
/// It has its own Dart isolate and therefore no access to the main app's
/// decrypted vault — the entry list is pushed in as JSON over the
/// `lumenpass/quick_search` method channel and rebuilt locally. See
/// [QuickSearchWindow] for the full contract.
///
/// Kept intentionally minimal: no tray, no cloud sync, no backup service —
/// just the search UI.
@pragma('vm:entry-point')
Future<void> quickSearchMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = PinningHttpOverrides();
  runApp(const QuickSearchWindow());
}

/// Root application shell with the shared Riverpod scope and theme.
class LumenPassApp extends ConsumerStatefulWidget {
  const LumenPassApp({super.key});

  @override
  ConsumerState<LumenPassApp> createState() => _LumenPassAppState();
}

class _LumenPassAppState extends ConsumerState<LumenPassApp>
    with WidgetsBindingObserver {
  BrowserExtensionService? _extensionService;
  DateTime _lastResumeCheck = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = ref.read(browserExtensionServiceProvider);
      _extensionService = svc;
      svc.start();
      if (Platform.isMacOS) {
        SshAgentService.instance.init(_container);
        applyMacOSDockVisibilityPreference(_container);
      }
      if (Platform.isWindows) {
        SshAgentService.instance.init(_container);
      }
      if (Platform.isLinux) {
        SshAgentService.instance.init(_container);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // After system sleep/wake or extended idle, the loopback HTTP server
    // may have become unreachable. Verify it and restart if needed.
    // Debounce to 10 s so rapid focus shifts don't spam health checks.
    final now = DateTime.now();
    if (now.difference(_lastResumeCheck).inSeconds < 10) return;
    _lastResumeCheck = now;
    _extensionService?.ensureRunning();
  }

  @override
  Widget build(BuildContext context) {
    final sizeDelta = ref.watch(appearanceTextSizeDeltaProvider);
    final fontFamily = ref.watch(appearanceFontFamilyProvider);
    currentTextSizeDelta = sizeDelta;
    currentFontFamily = fontFamily;
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'LumenPass - Password Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(fontFamily: fontFamily, sizeDelta: sizeDelta),
      darkTheme: AppTheme.dark(fontFamily: fontFamily, sizeDelta: sizeDelta),
      themeMode: ThemeMode.dark,
      initialRoute: UnlockScreen.routeName,
      routes: <String, WidgetBuilder>{
        UnlockScreen.routeName: (_) => const UnlockScreen(),
        VaultScreen.routeName: (_) => const VaultScreen(),
        CloudServicesScreen.routeName: (_) => const CloudServicesScreen(),
      },
    );
  }
}
