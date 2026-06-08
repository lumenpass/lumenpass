import 'dart:async';
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
import 'core/services/ssh_agent_service.dart';
import 'core/services/tray_service.dart';
import 'features/account/application/account_providers.dart';
import 'features/cloud/presentation/cloud_services_screen.dart';
import 'features/unlock/presentation/unlock_screen.dart';
import 'features/vault/presentation/vault_screen.dart';
import 'presentation/theme/app_theme.dart';

final _container = ProviderContainer();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
  }
  if (Platform.isMacOS || Platform.isWindows) {
    await TrayService.instance.init(_container);
  }
  await loadAppearancePreferences(_container);
  await loadVaultPreferences(_container);
  await loadGeneralPreferences(_container);
  runApp(UncontrolledProviderScope(
      container: _container, child: const LumenPassApp()));
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
      // Attach cloud sync storage before the extension bridge can persist saves,
      // otherwise [CloudSyncService.isDirty] may read false and skip uploads.
      initCloudSyncService(_container);
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
      BackupService.instance.init(_container);
      // Restore the cached auth session and refresh `/me` in the background.
      // Failures are non-fatal — the controller falls back to the cached
      // profile so the user stays signed-in while offline.
      unawaited(
        _container.read(accountControllerProvider.notifier).hydrate(),
      );
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
