import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/vault/infrastructure/ssh_private_key_tools.dart';

void main() {
  test('generated encrypted Ed25519 key validates and derives public key',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('lumenpass_test_ssh_');
    try {
      final keyPath = '${tempDir.path}${Platform.pathSeparator}id_test';
      final generated = await Process.run(
        'ssh-keygen',
        <String>['-t', 'ed25519', '-N', 'sshqa', '-f', keyPath, '-q'],
      );
      expect(generated.exitCode, 0, reason: generated.stderr.toString());
      final privateKey = await File(keyPath).readAsString();

      expect(
        await SshPrivateKeyTools.validatePassphrase(
          privateKey: privateKey,
          passphrase: 'sshqa',
        ),
        isNull,
      );
      expect(
        await SshPrivateKeyTools.validatePassphrase(
          privateKey: privateKey,
          passphrase: 'wrong',
        ),
        'That passphrase does not unlock this private key.',
      );
      expect(
        await SshPrivateKeyTools.derivePublicKey(
          privateKey: privateKey,
          passphrase: 'sshqa',
        ),
        startsWith('ssh-ed25519 '),
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  }, skip: Platform.isWindows);
}
