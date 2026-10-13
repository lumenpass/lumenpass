import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/core/services/vault_auto_lock_service.dart';

void main() {
  group('vault auto-lock helpers', () {
    test('computes deadline from unlock time and setting', () {
      final unlockedAt = DateTime(2026, 5, 10, 20, 0, 0);

      expect(
        computeVaultAutoLockDeadline(
          unlockedAt: unlockedAt,
          autoLockMinutes: 30,
        ),
        DateTime(2026, 5, 10, 20, 30, 0),
      );
    });

    test('recalculates remaining time immediately when setting changes', () {
      final unlockedAt = DateTime(2026, 5, 10, 20, 0, 0);
      final now = DateTime(2026, 5, 10, 20, 10, 0);

      expect(
        computeVaultAutoLockRemaining(
          now: now,
          unlockedAt: unlockedAt,
          autoLockMinutes: 30,
        ),
        const Duration(minutes: 20),
      );

      expect(
        computeVaultAutoLockRemaining(
          now: now,
          unlockedAt: unlockedAt,
          autoLockMinutes: 15,
        ),
        const Duration(minutes: 5),
      );
    });

    test('clamps expired countdown to zero', () {
      final unlockedAt = DateTime(2026, 5, 10, 20, 0, 0);
      final now = DateTime(2026, 5, 10, 20, 31, 0);

      expect(
        computeVaultAutoLockRemaining(
          now: now,
          unlockedAt: unlockedAt,
          autoLockMinutes: 30,
        ),
        Duration.zero,
      );
    });

    test('returns null when auto-lock is disabled', () {
      expect(
        computeVaultAutoLockDeadline(
          unlockedAt: DateTime(2026, 5, 10, 20, 0, 0),
          autoLockMinutes: null,
        ),
        isNull,
      );

      expect(
        computeVaultAutoLockRemaining(
          now: DateTime(2026, 5, 10, 20, 10, 0),
          unlockedAt: DateTime(2026, 5, 10, 20, 0, 0),
          autoLockMinutes: null,
        ),
        isNull,
      );
    });

    test('formats zero-padded countdown label', () {
      expect(
        formatVaultAutoLockCountdown(
          const Duration(hours: 1, minutes: 30, seconds: 21),
        ),
        'Autolock in 01h:30m:21s',
      );

      expect(
        formatVaultAutoLockCountdown(const Duration(seconds: 9)),
        'Autolock in 00h:00m:09s',
      );
    });
  });
}
