/// Base exception used to surface user-friendly failures from the domain layer.
sealed class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VaultAccessException extends AppException {
  const VaultAccessException(super.message);
}

class VaultStateException extends AppException {
  const VaultStateException(super.message);
}

