import 'dart:io';

import 'package:kdbx/kdbx.dart' as native;
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:test/test.dart';

void main() {
  group('KdbxRepositoryImpl', () {
    late Directory tempDir;
    late KdbxRepositoryImpl repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lumenpass_core_test_');
      repository = KdbxRepositoryImpl(
        format: native.KdbxFormat(),
        totpService: const TOTPService(),
      );
      await repository.createDatabase(
        databasePath: '${tempDir.path}/test.kdbx',
        databaseName: 'Test Vault',
        password: 'correct horse battery staple',
      );
    });

    tearDown(() async {
      repository.closeDatabase();
      await tempDir.delete(recursive: true);
    });

    test('favicon cache writes do not change usage timestamps', () async {
      final entry = await repository.createEntry(
        groupUuid: repository.rootGroupUuid!,
        fields: const <EntryField>[
          EntryField(key: AppKdbxFieldKeys.title, value: 'Example'),
          EntryField(key: AppKdbxFieldKeys.url, value: 'https://example.com'),
        ],
      );
      final originalUpdatedAt = entry.updatedAt;
      final originalLastUsedAt = entry.lastUsedAt;

      // KDBX timestamps can be second-granular. Wait long enough that a
      // normal metadata bump would be observable.
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      await repository.setEntryFaviconCache(
        entryUuid: entry.uuid,
        payload: 'base64-png',
      );

      final refreshed = (await repository.searchEntries())
          .singleWhere((candidate) => candidate.uuid == entry.uuid);
      // Automatic favicon caching must not masquerade as a user edit
      // (updatedAt) or a user access (lastUsedAt).
      expect(refreshed.updatedAt, originalUpdatedAt);
      expect(refreshed.lastUsedAt, originalLastUsedAt);
      expect(refreshed.faviconPngBase64, 'base64-png');
    });

    test('created-date repair preserves valid last modification time',
        () async {
      final entry = await repository.createEntry(
        groupUuid: repository.rootGroupUuid!,
        fields: const <EntryField>[
          EntryField(key: AppKdbxFieldKeys.title, value: 'Imported Item'),
        ],
      );
      final originalUpdatedAt = entry.updatedAt;

      await Future<void>.delayed(const Duration(milliseconds: 1200));

      await repository.setEntryCreatedAt(
        entryUuid: entry.uuid,
        createdAt: DateTime.utc(2024, 10, 8),
      );

      final refreshed = (await repository.searchEntries())
          .singleWhere((candidate) => candidate.uuid == entry.uuid);
      expect(refreshed.createdAt, DateTime.utc(2024, 10, 8));
      expect(refreshed.updatedAt, originalUpdatedAt);
    });
  });
}
