import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite-backed key-value store for local app settings and preferences.
/// Replaces flutter_secure_storage for non-sensitive data (file paths, flags).
class LocalStorageService {
  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'lumenpass_prefs.db');
    _db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE prefs (key TEXT PRIMARY KEY, value TEXT)',
          );
        },
      ),
    );
    return _db!;
  }

  Future<String?> read({required String key}) async {
    final db = await _database;
    final rows = await db.query(
      'prefs',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> write({required String key, String? value}) async {
    if (value == null) {
      await delete(key: key);
      return;
    }
    final db = await _database;
    await db.insert(
      'prefs',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete({required String key}) async {
    final db = await _database;
    await db.delete('prefs', where: 'key = ?', whereArgs: [key]);
  }
}
