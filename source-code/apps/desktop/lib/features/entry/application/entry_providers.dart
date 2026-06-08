import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/kdbx_entry.dart';
import '../../../core/repository/kdbx_repository_provider.dart';

final totpTickProvider = StreamProvider<DateTime>((ref) async* {
  while (true) {
    yield DateTime.now();
    await Future<void>.delayed(const Duration(seconds: 1));
  }
});

final selectedEntryProvider = Provider.family<KdbxEntry?, String>((ref, entryUuid) {
  final database = ref.watch(activeDatabaseProvider);
  if (database == null) {
    return null;
  }

  for (final entry in database.entries) {
    if (entry.uuid == entryUuid) {
      return entry;
    }
  }

  return null;
});

class TOTPViewState {
  const TOTPViewState({
    required this.code,
    required this.secondsRemaining,
  });

  final String code;
  final int secondsRemaining;
}

final entryTotpProvider =
    Provider.family<TOTPViewState?, String>((ref, entryUuid) {
      final entry = ref.watch(selectedEntryProvider(entryUuid));
      final tick = ref.watch(totpTickProvider).valueOrNull;
      if (entry?.otpAuthUrl == null || tick == null) {
        return null;
      }

      final service = ref.watch(totpServiceProvider);
      final code = service.generateCode(entry!.otpAuthUrl, timestamp: tick);
      if (code == null) {
        return null;
      }

      return TOTPViewState(
        code: code,
        secondsRemaining: service.secondsRemaining(
          entry.otpAuthUrl,
          timestamp: tick,
        ),
      );
    });
