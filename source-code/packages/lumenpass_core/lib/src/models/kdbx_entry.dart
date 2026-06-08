import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kdbx/kdbx.dart' as native;

import '../constants/kdbx_field_keys.dart';
import 'entry_field.dart';

part 'kdbx_entry.freezed.dart';
part 'kdbx_entry.g.dart';

/// Immutable projection of a KeePass entry for the presentation layer.
@freezed
class KdbxEntry with _$KdbxEntry {
  const factory KdbxEntry({
    required String uuid,
    required String groupUuid,
    required String title,
    String? username,
    String? url,
    String? notes,
    String? otpAuthUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    @Default(<String>[]) List<String> tags,
    @Default(<EntryField>[]) List<EntryField> fields,

    /// Base64-encoded PNG bytes cached in a hidden custom field on the
    /// entry. `null` ⇒ not attempted yet. [AppKdbxFieldKeys.faviconFailedSentinel]
    /// ⇒ we tried and the host has no usable favicon; skip future fetches.
    /// Any other value ⇒ a usable base64 PNG payload ready for
    /// `Image.memory` display with no network hop.
    String? faviconPngBase64,
  }) = _KdbxEntry;

  const KdbxEntry._();

  factory KdbxEntry.fromJson(Map<String, dynamic> json) =>
      _$KdbxEntryFromJson(json);

  factory KdbxEntry.fromNative(native.KdbxEntry source) {
    final title =
        source.getString(native.KdbxKeyCommon.TITLE)?.getText() ?? 'Untitled';
    final username =
        source.getString(native.KdbxKeyCommon.USER_NAME)?.getText();
    final url = source.getString(native.KdbxKeyCommon.URL)?.getText();
    final notes =
        source.getString(native.KdbxKey(AppKdbxFieldKeys.notes))?.getText();
    final otpAuthUrl = source.getString(native.KdbxKeyCommon.OTP)?.getText() ??
        source.getString(native.KdbxKey('otp'))?.getText();
    final faviconPngBase64 = source
        .getString(native.KdbxKey(AppKdbxFieldKeys.faviconPngBase64))
        ?.getText();
    final rawTags = source.tags.get() ?? '';
    final tags = rawTags
        .split(';')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);

    return KdbxEntry(
      uuid: source.uuid.toString(),
      groupUuid: source.parent?.uuid.toString() ?? '',
      title: title,
      username: username,
      url: url,
      notes: notes,
      otpAuthUrl: otpAuthUrl,
      createdAt: source.times.creationTime.get(),
      updatedAt: source.times.lastModificationTime.get(),
      tags: tags,
      fields: source.stringEntries
          .where((entry) =>
              entry.key.key != AppKdbxFieldKeys.notes &&
              !AppKdbxFieldKeys.isInternalMetaKey(entry.key.key))
          .map(EntryField.fromNative)
          .toList(growable: false),
      faviconPngBase64: faviconPngBase64,
    );
  }

  /// Whether the entry has a cached favicon PNG ready for offline display.
  bool get hasCachedFaviconImage =>
      faviconPngBase64 != null &&
      faviconPngBase64!.isNotEmpty &&
      faviconPngBase64 != AppKdbxFieldKeys.faviconFailedSentinel;

  /// Whether a previous favicon fetch was recorded as failed, meaning we
  /// should not re-fetch for this entry.
  bool get faviconFetchPreviouslyFailed =>
      faviconPngBase64 == AppKdbxFieldKeys.faviconFailedSentinel;

  EntryField? fieldByKey(String key) {
    for (final field in fields) {
      if (field.key.toLowerCase() == key.toLowerCase()) {
        return field;
      }
    }
    return null;
  }
}

