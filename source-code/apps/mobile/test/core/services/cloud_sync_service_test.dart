import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/services/cloud_sync_service.dart';

void main() {
  group('shouldDownloadRemoteVaultCopy', () {
    final syncedRemote = DateTime.utc(2026, 6, 11, 5, 0, 0);

    test('downloads when local cache is missing', () {
      expect(
        shouldDownloadRemoteVaultCopy(
          localModified: null,
          remoteModified: syncedRemote,
          lastSyncedRemoteModified: syncedRemote,
        ),
        isTrue,
      );
    });

    test('downloads when remote is newer than local mtime', () {
      expect(
        shouldDownloadRemoteVaultCopy(
          localModified: DateTime.utc(2026, 6, 11, 4, 59, 0),
          remoteModified: syncedRemote,
          lastSyncedRemoteModified: syncedRemote,
        ),
        isTrue,
      );
    });

    test(
      'downloads when remote revision changed despite newer local mtime',
      () {
        expect(
          shouldDownloadRemoteVaultCopy(
            localModified: DateTime.utc(2026, 6, 11, 5, 10, 0),
            remoteModified: syncedRemote,
            lastSyncedRemoteModified: DateTime.utc(2026, 6, 11, 4, 45, 0),
          ),
          isTrue,
        );
      },
    );

    test('skips when remote revision matches the last synced copy', () {
      expect(
        shouldDownloadRemoteVaultCopy(
          localModified: DateTime.utc(2026, 6, 11, 5, 10, 0),
          remoteModified: syncedRemote,
          lastSyncedRemoteModified: syncedRemote,
        ),
        isFalse,
      );
    });

    test('self-heals older installs without a remembered remote revision', () {
      expect(
        shouldDownloadRemoteVaultCopy(
          localModified: DateTime.utc(2026, 6, 11, 5, 10, 0),
          remoteModified: syncedRemote,
          lastSyncedRemoteModified: null,
        ),
        isTrue,
      );
    });
  });
}
