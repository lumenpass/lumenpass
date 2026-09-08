import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../../features/unlock/application/database_registry.dart';
import '../services/ssh_agent_service.dart' show navigatorKey;
import 'database_save_sync.dart';
import 'kdbx_repository_provider.dart';

/// App-wide scheduler that persists vault mutations in the background.
///
/// Mutations are applied to the in-memory KDBX file by [KdbxRepository] and
/// reported here; the actual encrypt-and-write runs off the user interaction
/// path so clicks, edits and list scrolling never block on disk I/O or the
/// Argon2 KDF. Hard synchronization points (vault lock, app backgrounded,
/// import finalize, browser-extension writes) call [VaultWriteScheduler.flushNow].
final vaultWriteSchedulerProvider = Provider<VaultWriteScheduler>((ref) {
  final scheduler = VaultWriteScheduler(
    saveAndSync: () async {
      final repository = ref.read(kdbxRepositoryProvider);
      final registry = ref.read(databaseRegistryProvider);
      return saveAndSyncDatabase(repository, registry);
    },
    onSaveError: (error, stackTrace) {
      debugPrint('[VaultWrite] background save failed: $error');
      debugPrint(stackTrace.toString());
      final context = navigatorKey.currentContext;
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save vault changes. Will retry.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    },
  );
  ref.onDispose(scheduler.dispose);
  return scheduler;
});
