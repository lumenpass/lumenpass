/// Simple async key-value store for secrets (passwords/PINs/etc).
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
  Future<void> delete(String key);
}

