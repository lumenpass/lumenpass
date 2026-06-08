import 'dart:math';

/// Generates strong passwords with caller-controlled character groups.
class PasswordGeneratorService {
  const PasswordGeneratorService();

  static const String _lowercase = 'abcdefghijkmnopqrstuvwxyz';
  static const String _uppercase = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const String _numbers = '23456789';
  static const String _symbols = '!@#\$%^&*()-_=+[]{};:,.?';

  String generate({
    int length = 20,
    bool includeUppercase = true,
    bool includeLowercase = true,
    bool includeNumbers = true,
    bool includeSymbols = true,
  }) {
    if (length < 8) {
      throw ArgumentError.value(
        length,
        'length',
        'Passwords shorter than 8 characters are not allowed.',
      );
    }

    final enabledPools = <String>[
      if (includeLowercase) _lowercase,
      if (includeUppercase) _uppercase,
      if (includeNumbers) _numbers,
      if (includeSymbols) _symbols,
    ];

    if (enabledPools.isEmpty) {
      throw ArgumentError('At least one character set must be enabled.');
    }

    final random = Random.secure();
    final combined = enabledPools.join();
    final buffer = <String>[
      for (final pool in enabledPools) pool[random.nextInt(pool.length)],
    ];

    while (buffer.length < length) {
      buffer.add(combined[random.nextInt(combined.length)]);
    }

    buffer.shuffle(random);
    return buffer.join();
  }
}

