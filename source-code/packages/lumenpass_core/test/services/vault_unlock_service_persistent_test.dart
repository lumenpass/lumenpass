import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:test/test.dart';

/// In-memory [KeyValueStore] / [SecretStore] fakes so the service can be
/// exercised without any platform plugins.
class _MemStore implements KeyValueStore, SecretStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

void main() {
  const vaultId = 'vault-123';
  const maxAge = Duration(days: 14);

  late _MemStore prefs;
  late _MemStore secrets;
  late VaultUnlockService svc;

  setUp(() {
    prefs = _MemStore();
    secrets = _MemStore();
    // Mirror the mobile wiring where flags live in the secret store.
    svc = VaultUnlockService(
      preferences: prefs,
      secrets: secrets,
      storeFlagsInSecrets: true,
    );
  });

  test('no token by default; no password returned', () async {
    expect(await svc.getLastManualUnlockAt(vaultId), isNull);
    expect(
      await svc.getPersistentUnlockPassword(vaultId, maxAge: maxAge),
      isNull,
    );
  });

  test('recordManualUnlock stores password and returns it within the window',
      () async {
    final now = DateTime.utc(2024, 1, 1, 12);
    await svc.recordManualUnlock(vaultId, 'master-pw', now: now);

    expect(await svc.getLastManualUnlockAt(vaultId), now);

    // 13 days later — still inside the 14-day cap.
    final within = now.add(const Duration(days: 13));
    expect(
      await svc.getPersistentUnlockPassword(vaultId,
          maxAge: maxAge, now: within),
      'master-pw',
    );
  });

  test('expired token (>14d) returns null and purges the stored password',
      () async {
    final now = DateTime.utc(2024, 1, 1, 12);
    await svc.recordManualUnlock(vaultId, 'master-pw', now: now);

    final after = now.add(const Duration(days: 14, seconds: 1));
    expect(
      await svc.getPersistentUnlockPassword(vaultId,
          maxAge: maxAge, now: after),
      isNull,
    );

    // The at-rest password and timestamp are gone after expiry.
    expect(await svc.getLastManualUnlockAt(vaultId), isNull);
    // Even with a fresh "now", nothing is returned until re-armed.
    expect(
      await svc.getPersistentUnlockPassword(vaultId, maxAge: maxAge, now: now),
      isNull,
    );
  });

  test('recordManualUnlock refreshes the timestamp (resets the cap)', () async {
    final t0 = DateTime.utc(2024, 1, 1, 12);
    await svc.recordManualUnlock(vaultId, 'master-pw', now: t0);

    // 10 days later the user manually unlocks again.
    final t1 = t0.add(const Duration(days: 10));
    await svc.recordManualUnlock(vaultId, 'master-pw', now: t1);

    expect(await svc.getLastManualUnlockAt(vaultId), t1);

    // 13 days after the *refresh* (23 days after the original unlock) it is
    // still valid because the clock reset.
    final t2 = t1.add(const Duration(days: 13));
    expect(
      await svc.getPersistentUnlockPassword(vaultId, maxAge: maxAge, now: t2),
      'master-pw',
    );
  });

  test('clearPersistentUnlock purges everything', () async {
    final now = DateTime.utc(2024, 1, 1, 12);
    await svc.recordManualUnlock(vaultId, 'master-pw', now: now);

    await svc.clearPersistentUnlock(vaultId);

    expect(await svc.getLastManualUnlockAt(vaultId), isNull);
    expect(
      await svc.getPersistentUnlockPassword(vaultId, maxAge: maxAge, now: now),
      isNull,
    );
  });

  test('persistent-unlock data is isolated per vault', () async {
    final now = DateTime.utc(2024, 1, 1, 12);
    await svc.recordManualUnlock('vault-a', 'pw-a', now: now);

    expect(await svc.getLastManualUnlockAt('vault-b'), isNull);
    expect(
      await svc.getPersistentUnlockPassword('vault-b',
          maxAge: maxAge, now: now),
      isNull,
    );
    expect(
      await svc.getPersistentUnlockPassword('vault-a',
          maxAge: maxAge, now: now),
      'pw-a',
    );
  });
}
