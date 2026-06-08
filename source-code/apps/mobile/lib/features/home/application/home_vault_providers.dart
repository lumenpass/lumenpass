import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:path/path.dart' as p;

import '../../../core/repository/providers.dart';
import '../../unlock/application/database_registry.dart';
import '../../vault/application/vault_entries_providers.dart';

/// Recent items for the home list: newest first, capped at 7, respecting search.
final homeRecentEntriesProvider = Provider<List<KdbxEntry>>((ref) {
  final entries = ref.watch(vaultSearchFilteredEntriesProvider).toList();
  entries.sort((a, b) {
    final ta = latestEntryTimestamp(a.updatedAt, a.createdAt) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final tb = latestEntryTimestamp(b.updatedAt, b.createdAt) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return tb.compareTo(ta);
  });
  return entries.take(7).toList(growable: false);
});

final homeQuickAccessCountsProvider =
    Provider<({int all, int totp, int secureNotes, int ssh})>((ref) {
  final entries = ref.watch(vaultVisibleEntriesProvider);
  var totp = 0;
  var secureNotes = 0;
  var ssh = 0;
  for (final entry in entries) {
    if (entry.otpAuthUrl != null && entry.otpAuthUrl!.trim().isNotEmpty) {
      totp++;
    }
    final type = classifyVaultItemType(entry);
    if (type == VaultItemType.secureNote) {
      secureNotes++;
    }
    if (type == VaultItemType.sshKey) {
      ssh++;
    }
  }
  return (
    all: entries.length,
    totp: totp,
    secureNotes: secureNotes,
    ssh: ssh,
  );
});

final homePopularTagsProvider = Provider<List<String>>((ref) {
  final entries = ref.watch(vaultVisibleEntriesProvider);
  final counts = <String, int>{};
  for (final entry in entries) {
    for (final raw in entry.tags) {
      final tag = raw.trim();
      if (tag.isEmpty) {
        continue;
      }
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
  }
  final ranked = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) {
        return byCount;
      }
      return a.key.toLowerCase().compareTo(b.key.toLowerCase());
    });
  return ranked.take(12).map((e) => e.key).toList(growable: false);
});

/// The [DatabaseRecord] for the currently open vault, or null.
final homeVaultRecordProvider = Provider<DatabaseRecord?>((ref) {
  final db = ref.watch(activeDatabaseProvider);
  if (db == null) return null;
  final currentPath = p.normalize(db.path);
  final registry = ref.watch(databaseRegistryProvider);
  for (final r in registry) {
    if (p.normalize(r.databasePath) == currentPath) return r;
  }
  return null;
});

String _sanitizeVaultDisplayName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.replaceFirst(RegExp(r'_[a-f0-9]{12}$', caseSensitive: false), '');
}

final homeVaultStorageTypeProvider = Provider<String>((ref) {
  final record = ref.watch(homeVaultRecordProvider);
  if (record != null) return record.storageType;

  final db = ref.watch(activeDatabaseProvider);
  if (db == null) return 'local';
  final normalizedPath = p.normalize(db.path).toLowerCase();
  if (normalizedPath.contains('/cloud_databases/google_drive/')) {
    return 'googleDrive';
  }
  if (normalizedPath.contains('/cloud_databases/dropbox/')) {
    return 'dropbox';
  }
  if (normalizedPath.contains('/cloud_databases/onedrive/')) {
    return 'oneDrive';
  }
  if (normalizedPath.contains('/cloud_databases/webdav/')) {
    return 'webdav';
  }
  return 'local';
});

final homeVaultTitleProvider = Provider<String>((ref) {
  final db = ref.watch(activeDatabaseProvider);
  if (db == null) return 'Vault';

  // Registry nickname is most reliable — it's set by the user or derived from
  // the original cloud filename, never a hash-suffixed cache path.
  final record = ref.watch(homeVaultRecordProvider);
  if (record != null) {
    final nick = _sanitizeVaultDisplayName(record.nickname);
    if (nick.isNotEmpty) return nick;

    // For cloud vaults the original filename is a reliable fallback.
    final cloud = _sanitizeVaultDisplayName(record.cloudFileName ?? '');
    if (cloud.isNotEmpty) return p.basenameWithoutExtension(cloud);
  }

  // Fall back to KeePass-internal database name.
  final metaName = _sanitizeVaultDisplayName(db.name);
  if (metaName.isNotEmpty) return metaName;

  final fileName = p.basename(db.path);
  if (fileName.isNotEmpty && fileName != '.' && fileName != '/') {
    return _sanitizeVaultDisplayName(p.basenameWithoutExtension(fileName));
  }
  return 'Vault';
});
