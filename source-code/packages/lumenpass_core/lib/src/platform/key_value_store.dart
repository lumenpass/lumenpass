/// Simple async key-value store (non-secret).
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
  Future<void> delete(String key);
}

