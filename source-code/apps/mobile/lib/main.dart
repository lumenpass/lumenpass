import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app/app_theme.dart';
import 'app/routes.dart';
import 'core/services/app_runtime_info.dart';
import 'core/services/cloud_database_service.dart';
import 'core/services/cloud_sync_service.dart';
import 'core/repository/providers.dart';
import 'core/services/pinned_http_client.dart';
import 'core/services/removed_account_data_cleanup.dart';

import 'core/services/screenshot_guard.dart';
import 'core/services/vault_auto_sync_controller.dart';
import 'core/services/vault_preferences.dart';
import 'core/ui/root_navigator.dart';
import 'features/autofill/application/autofill_providers.dart';

import 'features/home/presentation/home_screen.dart';
import 'features/import/application/credential_exchange_bridge.dart';
import 'features/import/application/credential_exchange_controller.dart';
import 'features/import/presentation/cxp_import_sheet.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/onboarding/presentation/splash_screen.dart';
import 'features/settings/application/vault_security_provider.dart';
import 'features/startup/presentation/startup_router.dart';
import 'features/unlock/presentation/unlock_vault_screen.dart';
import 'features/unlock/presentation/vault_picker_screen.dart';
import 'l10n/app_localizations.dart';

final _container = ProviderContainer();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = PinningHttpOverrides();
  await cleanupRemovedMobileAccountData(
    secureStorage: _container.read(secureStorageProvider),
    localStorage: _container.read(localStorageProvider),
  );
  await LiquidGlassWidgets.initialize();
  unawaited(AppRuntimeInfoService.logStartupInfo());
  CredentialExchangeBridge.instance.initialize();
  // Restore previously-connected Google Drive / Dropbox sessions in the
  // background so the Duplicate / Add Vault flows show "connected" state
  // immediately, without forcing the user to OAuth again on every cold start.
  unawaited(CloudDatabaseService.instance.init(_container));
  initCloudSyncService(_container);
  // Hydrate vault-level preferences (favicon auto-fetch toggle, …) so the
  // first vault screen sees the user's saved choice instead of the
  // in-memory default. Fire-and-forget — the loader is resilient and the
  // UI falls back to the default while the value is in flight.
  // ignore: discarded_futures
  loadMobileVaultPreferences(_container);
  runApp(
    LiquidGlassWidgets.wrap(
      adaptiveQuality: true,
      child: UncontrolledProviderScope(
        container: _container,
        child: const MobileApp(),
      ),
    ),
  );
}

class MobileApp extends ConsumerStatefulWidget {
  const MobileApp({super.key});

  @override
  ConsumerState<MobileApp> createState() => _MobileAppState();
}

class _MobileAppState extends ConsumerState<MobileApp> {
  final GlobalKey<NavigatorState> _navigatorKey = rootNavigatorKey;
  bool _cxpSheetOpen = false;

  @override
  Widget build(BuildContext context) {
    ref.watch(autoFillSyncControllerProvider);
    ref.watch(vaultAutoSyncControllerProvider);

    // Apply/remove screenshot blocking when the setting changes.
    ref.listen(
      vaultSecuritySettingsProvider.select((s) => s.blockScreenshots),
      (_, block) => applyScreenshotBlocking(block: block),
    );

    // Eagerly read the CXP controller so it subscribes to the bridge as
    // early as possible — otherwise payloads delivered via `onImport`
    // during cold launch can race past the StateNotifier construction.
    // `read` is safe inside `build` because the controller is a singleton.
    ref.read(cxpImportControllerProvider);

    // When a CXP payload arrives, surface the import sheet. Triggered by
    // a change in `payloadVersion` — that counter bumps for every new
    // payload regardless of whether the status field changed, which
    // matters when the user dismisses one preview and 1Password sends
    // another with the same shape.
    ref.listen<CxpImportState>(cxpImportControllerProvider, (prev, next) {
      final isPresentable =
          next.status == CxpImportStatus.received ||
          next.status == CxpImportStatus.lockedNoVault;
      final isNewPayload =
          isPresentable && (prev?.payloadVersion ?? 0) != next.payloadVersion;
      if (isNewPayload && !_cxpSheetOpen) {
        final navigator = _navigatorKey.currentState;
        if (navigator == null) return;
        _cxpSheetOpen = true;
        showCxpImportSheet(navigator.context).whenComplete(() {
          _cxpSheetOpen = false;
        });
      }
    });

    // If the user unlocks the vault while a CXP payload is waiting in the
    // `lockedNoVault` state, promote it to `received` so the preview can
    // appear automatically the next time the user is on a top-level screen.
    ref.listen(activeDatabaseProvider, (prev, next) {
      if (prev == null && next != null) {
        ref.read(cxpImportControllerProvider.notifier).retryAfterUnlock();
      }
    });

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'LumenPass',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      builder: (context, child) {
        // App-wide keyboard dismissal: a single tap on any empty area unfocuses
        // the active field, so every TextField in the app can be dismissed with
        // the standard tap-outside gesture without wrapping each screen. Taps on
        // buttons/fields win the gesture arena, so this only fires on blank space.
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child,
        );
      },
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      navigatorObservers: [unlockRouteObserver],
      routes: {
        Routes.splash: (context) => SplashScreen(
          onGetStarted: () =>
              Navigator.of(context).pushReplacementNamed(Routes.startup),
        ),
        Routes.onboarding: (context) => OnboardingScreen(
          onFinish: () {
            Navigator.of(context).pushReplacementNamed(Routes.startup);
          },
        ),
        Routes.startup: (context) => const StartupRouter(),
        Routes.vaults: (context) => VaultPickerScreen(
          onUnlocked: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
              (route) => false,
            );
          },
        ),
        Routes.home: (context) => const HomeScreen(),
      },
    );
  }
}
