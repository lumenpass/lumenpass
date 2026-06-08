import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../../../app/routes.dart';
import '../../home/application/mobile_home_tab_provider.dart';
import '../../home/presentation/home_screen.dart';
import '../../settings/application/general_settings_provider.dart';
import '../../unlock/application/database_registry.dart';
import '../../unlock/presentation/unlock_vault_screen.dart';
import '../../unlock/presentation/vault_picker_screen.dart';

/// After onboarding (and on warm launches into the authenticated area)
/// decides where to send the user based on the registered vaults and their
/// `QuickVaultSelection` preference.
class StartupRouter extends ConsumerStatefulWidget {
  const StartupRouter({super.key});

  @override
  ConsumerState<StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends ConsumerState<StartupRouter> {
  bool _dispatched = false;

  @override
  void initState() {
    super.initState();
    _dispatch();
  }

  Future<void> _dispatch() async {
    final registry = ref.read(databaseRegistryProvider.notifier);
    await registry.ready;
    if (!mounted || _dispatched) return;
    _dispatched = true;

    final navigator = Navigator.of(context);
    final records = ref.read(databaseRegistryProvider);
    if (records.isEmpty) {
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => VaultPickerScreen(onUnlocked: _onUnlocked),
        ),
      );
      return;
    }

    final settings = ref.read(generalSettingsProvider);
    final target = _resolveTarget(records, settings);
    if (target == null) {
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => VaultPickerScreen(onUnlocked: _onUnlocked),
        ),
      );
      return;
    }

    // Land on the vault picker underneath the unlock screen so Back goes to
    // the vault list instead of dumping the user on a blank route.
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => VaultPickerScreen(onUnlocked: _onUnlocked),
      ),
    );
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => UnlockVaultScreen(record: target),
      ),
    );
  }

  void _onUnlocked() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Public entry used by the root route map so we don't double-wrap the
/// [StartupRouter] in extra Navigator transitions.
Route<dynamic> buildStartupRoute(BuildContext _) {
  return MaterialPageRoute<void>(
    builder: (_) => const StartupRouter(),
    settings: const RouteSettings(name: Routes.startup),
  );
}

/// Resolves which registered vault the startup router should attempt to
/// unlock. Returns `null` when no candidate exists and the caller should
/// fall back to the vault picker.
DatabaseRecord? _resolveTarget(
  List<DatabaseRecord> records,
  GeneralSettings settings,
) {
  if (settings.quickVaultSelection == QuickVaultSelection.lastOpened) {
    final lastId = settings.lastOpenedVaultId;
    if (lastId != null) {
      for (final r in records) {
        if (r.id == lastId) return r;
      }
    }
  }
  for (final r in records) {
    if (r.isDefaultStartup) return r;
  }
  return records.isEmpty ? null : records.first;
}

/// Persists the `lastOpenedVaultId` and keeps the active tab in sync with
/// the user's configured default tab. Call this right after a successful
/// `activeDatabaseProvider` assignment.
Future<void> applyPostUnlockPreferences(WidgetRef ref, String vaultId) async {
  final settings = ref.read(generalSettingsProvider);
  // Persist last-opened asynchronously so navigation to Home isn't blocked.
  ref.read(generalSettingsProvider.notifier).recordLastOpenedVault(vaultId);
  ref
      .read(activeHomeTabAfterUnlockProvider.notifier)
      .state = settings.defaultTab;
}

/// Carries the default-tab intent from the unlock flow into the home screen,
/// which applies it on first build and clears it.
final activeHomeTabAfterUnlockProvider =
    StateProvider<MobileHomeTab?>((_) => null);
