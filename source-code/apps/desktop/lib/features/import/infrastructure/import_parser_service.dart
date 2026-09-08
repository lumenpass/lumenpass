import 'dart:io';

import '../domain/import_parsed_item.dart';
import '../domain/import_provider.dart';
import 'apple_passwords_parser.dart';
import 'bitwarden_parser.dart';
import 'chrome_parser.dart';
import 'csv_parser.dart';
import 'dashlane_parser.dart';
import 'enpass_parser.dart';
import 'nordpass_parser.dart';
import 'one_pux_parser.dart';
import 'proton_pass_parser.dart';
import 'roboform_parser.dart';

class ImportParserService {
  const ImportParserService();

  /// Parses [filePath] into normalized import items.
  ///
  /// When [provider] is supplied the file is routed to that provider's
  /// dedicated parser (and validated against the formats it accepts). When it
  /// is omitted the file is routed purely by extension, preserving the legacy
  /// generic behavior.
  Future<List<ImportParsedItem>> parseFile(
    String filePath, {
    ImportProviderType? provider,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FormatException('File not found: $filePath');
    }

    final extension = _fileExtension(filePath);

    if (provider == ImportProviderType.bitwarden) {
      if (extension != '.json' && extension != '.csv') {
        throw FormatException(
            'Invalid file type "$extension". Bitwarden exports must be a '
            '.json or .csv file.');
      }
      return const BitwardenParser().parseFile(filePath);
    }

    if (provider == ImportProviderType.protonPass) {
      if (extension != '.csv') {
        throw FormatException(
            'Invalid file type "$extension". Proton Pass exports must be a '
            '.csv file.');
      }
      return const ProtonPassParser().parseFile(filePath);
    }

    if (provider == ImportProviderType.nordPass) {
      if (extension != '.csv') {
        throw FormatException(
            'Invalid file type "$extension". NordPass exports must be a '
            '.csv file.');
      }
      return const NordPassParser().parseFile(filePath);
    }

    if (provider == ImportProviderType.roboForm) {
      if (extension != '.csv') {
        throw FormatException(
            'Invalid file type "$extension". RoboForm exports must be a '
            '.csv file.');
      }
      return const RoboFormParser().parseFile(filePath);
    }

    if (provider == ImportProviderType.enpass) {
      if (extension != '.json' &&
          extension != '.csv' &&
          extension != '.txt') {
        throw FormatException(
            'Invalid file type "$extension". Enpass exports must be a '
            '.json, .csv, or .txt file.');
      }
      return const EnpassParser().parseFile(filePath);
    }

    if (provider == ImportProviderType.applePasswords) {
      if (extension != '.csv') {
        throw FormatException(
            'Invalid file type "$extension". Apple Passwords exports must be '
            'a .csv file.');
      }
      return const ApplePasswordsParser().parseFile(filePath);
    }

    if (provider == ImportProviderType.chrome) {
      if (extension != '.csv') {
        throw FormatException(
            'Invalid file type "$extension". Chrome password exports must be '
            'a .csv file.');
      }
      return const ChromeParser().parseFile(filePath);
    }

    if (provider == ImportProviderType.dashlane) {
      if (extension != '.zip' && extension != '.csv') {
        throw FormatException(
            'Invalid file type "$extension". Dashlane exports must be a '
            '.zip archive or a .csv file.');
      }
      return const DashlaneParser().parseFile(filePath);
    }

    switch (extension) {
      case '.csv':
        return _parseCsv(filePath);
      case '.1pux':
        return _parseOnePux(filePath);
      default:
        throw FormatException(
            'Unsupported file format: $extension. Supported formats: .csv, .1pux');
    }
  }

  Future<List<ImportParsedItem>> _parseCsv(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    return const CsvParser().parse(content);
  }

  Future<List<ImportParsedItem>> _parseOnePux(String filePath) async {
    return const OnePuxParser().parse(filePath);
  }

  String _fileExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '';
    return path.substring(dot).toLowerCase();
  }
}
