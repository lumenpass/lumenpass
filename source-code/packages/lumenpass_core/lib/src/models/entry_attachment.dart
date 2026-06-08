import 'dart:typed_data';

/// Attachment payload used when creating or updating vault entries.
class EntryAttachment {
  EntryAttachment({
    required this.fileName,
    this.filePath,
    this.bytes,
    this.isProtected = false,
  }) : assert(
          filePath != null || bytes != null,
          'EntryAttachment requires filePath or bytes.',
        );

  final String fileName;
  final String? filePath;
  final Uint8List? bytes;
  final bool isProtected;
}
