import 'package:flutter/material.dart' hide Icon;

enum ImportProviderType { onePassword, bitwarden, protonPass, nordPass, roboForm, enpass, applePasswords, chrome, dashlane }

class ImportProviderDefinition {
  const ImportProviderDefinition({
    required this.type,
    required this.displayName,
    required this.description,
    required this.acceptedExtensions,
    required this.assetPath,
    required this.primaryColor,
  });

  final ImportProviderType type;
  final String displayName;
  final String description;
  final List<String> acceptedExtensions;
  final String assetPath;
  final Color primaryColor;

  static const ImportProviderDefinition onePassword = ImportProviderDefinition(
    type: ImportProviderType.onePassword,
    displayName: '1Password',
    description: 'Import logins, secure notes, and credentials',
    acceptedExtensions: <String>['.csv', '.1pux'],
    assetPath: 'assets/images/importers/1password.png',
    primaryColor: Color(0xFF0A60C4),
  );

  static const ImportProviderDefinition bitwarden = ImportProviderDefinition(
    type: ImportProviderType.bitwarden,
    displayName: 'Bitwarden',
    description: 'Import logins, cards, identities, notes, and SSH keys',
    acceptedExtensions: <String>['.json', '.csv'],
    assetPath: 'assets/images/importers/bitwarden.png',
    primaryColor: Color(0xFF175DDC),
  );

  static const ImportProviderDefinition protonPass = ImportProviderDefinition(
    type: ImportProviderType.protonPass,
    displayName: 'Proton Pass',
    description: 'Import logins, cards, identities, notes, and SSH keys',
    acceptedExtensions: <String>['.csv'],
    assetPath: 'assets/images/importers/proton_pass.png',
    primaryColor: Color(0xFF6D4AFF),
  );

  static const ImportProviderDefinition nordPass = ImportProviderDefinition(
    type: ImportProviderType.nordPass,
    displayName: 'NordPass',
    description: 'Import logins, cards, identities, and notes',
    acceptedExtensions: <String>['.csv'],
    assetPath: 'assets/images/importers/nordpass.png',
    primaryColor: Color(0xFF2E5BFF),
  );

  static const ImportProviderDefinition roboForm = ImportProviderDefinition(
    type: ImportProviderType.roboForm,
    displayName: 'RoboForm',
    description: 'Import logins, notes, and one-time passwords',
    acceptedExtensions: <String>['.csv'],
    assetPath: 'assets/images/importers/roboform.png',
    primaryColor: Color(0xFF2D7DD2),
  );

  static const ImportProviderDefinition enpass = ImportProviderDefinition(
    type: ImportProviderType.enpass,
    displayName: 'Enpass',
    description: 'Import logins, notes, and custom fields',
    acceptedExtensions: <String>['.json', '.csv', '.txt'],
    assetPath: 'assets/images/importers/enpass.png',
    primaryColor: Color(0xFF007AFF),
  );

  static const ImportProviderDefinition applePasswords =
      ImportProviderDefinition(
    type: ImportProviderType.applePasswords,
    displayName: 'Apple Passwords',
    description: 'Import logins and one-time codes from Apple Passwords',
    acceptedExtensions: <String>['.csv'],
    assetPath: 'assets/images/importers/apple_passwords.png',
    primaryColor: Color(0xFF1D1D1F),
  );

  static const ImportProviderDefinition chrome = ImportProviderDefinition(
    type: ImportProviderType.chrome,
    displayName: 'Google Chrome',
    description: 'Import saved passwords exported from Chrome',
    acceptedExtensions: <String>['.csv'],
    assetPath: 'assets/images/importers/chrome.png',
    primaryColor: Color(0xFF4285F4),
  );

  static const ImportProviderDefinition dashlane = ImportProviderDefinition(
    type: ImportProviderType.dashlane,
    displayName: 'Dashlane',
    description: 'Import logins, secure notes, IDs, payments, and identities',
    acceptedExtensions: <String>['.zip', '.csv'],
    assetPath: 'assets/images/importers/dashlane.png',
    primaryColor: Color(0xFF0E806A),
  );

  static const List<ImportProviderDefinition> all = <ImportProviderDefinition>[
    onePassword,
    bitwarden,
    protonPass,
    nordPass,
    roboForm,
    enpass,
    applePasswords,
    chrome,
    dashlane,
  ];
}

class ImportProviderSelection {
  const ImportProviderSelection({
    required this.provider,
    required this.filePath,
    required this.fileName,
  });

  final ImportProviderDefinition provider;
  final String filePath;
  final String fileName;

  String get fileExtension {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return '';
    return fileName.substring(dot).toLowerCase();
  }
}
