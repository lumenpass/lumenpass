import 'dart:io';

/// Runs ssh-keygen on private key material, including keys generated in memory.
class SshPrivateKeyTools {
  const SshPrivateKeyTools._();

  static Future<void> writeTemporaryKey(String path, String privateKey) async {
    await File(path).writeAsString(privateKey);
    if (!Platform.isWindows) {
      final result = await Process.run('chmod', <String>['600', path]);
      if (result.exitCode != 0) {
        throw const FileSystemException('Unable to protect temporary SSH key');
      }
    }
  }

  static Future<String?> validatePassphrase({
    required String privateKey,
    required String passphrase,
    String? sourcePath,
  }) async {
    return _withKeyFile(privateKey, sourcePath, (filePath) async {
      try {
        // ssh-keygen reads a passphrase from the controlling terminal, not
        // stdin. -P supplies it non-interactively for -y.
        final result = await Process.run(
          'ssh-keygen',
          <String>['-y', '-P', passphrase, '-f', filePath],
          runInShell: false,
        );
        if (result.exitCode == 0 &&
            result.stdout.toString().trim().isNotEmpty) {
          return null;
        }
        final error = result.stderr.toString().toLowerCase();
        if (error.contains('incorrect passphrase') ||
            error.contains('bad passphrase') ||
            error.contains('incorrect password')) {
          return 'That passphrase does not unlock this private key.';
        }
        return 'Unable to verify the passphrase for this private key.';
      } on ProcessException {
        return 'ssh-keygen is unavailable, so this passphrase cannot be verified here.';
      } catch (_) {
        return 'Unable to verify the passphrase for this private key.';
      }
    });
  }

  static Future<String?> derivePublicKey({
    required String privateKey,
    String? sourcePath,
    String? passphrase,
  }) async {
    return _withKeyFile(privateKey, sourcePath, (filePath) async {
      try {
        final result = await Process.run(
          'ssh-keygen',
          <String>['-y', '-P', passphrase ?? '', '-f', filePath],
          runInShell: false,
        );
        if (result.exitCode != 0) return null;
        final publicKey = result.stdout.toString().trim();
        return publicKey.isEmpty ? null : publicKey;
      } catch (_) {
        return null;
      }
    });
  }

  static Future<T> _withKeyFile<T>(
    String privateKey,
    String? sourcePath,
    Future<T> Function(String filePath) action,
  ) async {
    final existingPath = sourcePath?.trim() ?? '';
    if (existingPath.isNotEmpty) return action(existingPath);

    final tempDir = await Directory.systemTemp.createTemp('lumenpass_sshkey_');
    final filePath = '${tempDir.path}${Platform.pathSeparator}id_temp';
    try {
      await writeTemporaryKey(filePath, privateKey);
      return await action(filePath);
    } finally {
      await tempDir.delete(recursive: true);
    }
  }
}
