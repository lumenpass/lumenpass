import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:argon2_ffi_base/argon2_ffi_base.dart';
import 'package:pointycastle/export.dart' as pc;

/// Argon2 implementation for the `kdbx` package that runs the pure-Dart
/// PointyCastle KDF on a background isolate.
///
/// The kdbx package's default [PointyCastleArgon2] executes `argon2Async`
/// synchronously on the calling isolate (`Future.value(argon2(args))`).
/// KDBX4 databases derive their master key with Argon2 on **every** save and
/// open, so with typical KeePass KDF parameters that blocks the UI isolate
/// for hundreds of milliseconds to seconds. This class computes the identical
/// hash (same generator, same parameters) but off-loads the work via
/// [Isolate.run], keeping the UI responsive.
///
/// Pass an instance to `KdbxFormat(IsolateArgon2())`.
class IsolateArgon2 extends Argon2 {
  const IsolateArgon2();

  @override
  bool get isFfi => false;

  @override
  bool get isImplemented => true;

  @override
  Uint8List argon2(Argon2Arguments args) => _deriveKey(args);

  @override
  Future<Uint8List> argon2Async(Argon2Arguments args) {
    return Isolate.run(() => _deriveKey(args));
  }

  static Uint8List _deriveKey(Argon2Arguments args) {
    final kdf = pc.Argon2BytesGenerator();
    kdf.init(
      pc.Argon2Parameters(
        args.type,
        args.salt,
        desiredKeyLength: args.length,
        iterations: args.iterations,
        memory: args.memory,
        lanes: args.parallelism,
        version: args.version,
      ),
    );
    return kdf.process(args.key);
  }
}
