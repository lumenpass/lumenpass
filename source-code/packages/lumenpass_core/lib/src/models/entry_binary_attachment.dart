import 'dart:typed_data';

/// Binary attachment stored inside a KDBX entry.
class EntryBinaryAttachment {
  const EntryBinaryAttachment({
    required this.name,
    required this.size,
    required this.isImage,
    required this.bytes,
  });

  final String name;
  final int size;
  final bool isImage;
  final Uint8List bytes;
}

