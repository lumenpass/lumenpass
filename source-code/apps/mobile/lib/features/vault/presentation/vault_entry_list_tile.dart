import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import 'vault_entry_avatar.dart';

/// List row styling shared by the Items tab and home "last used" list.
const Color kVaultListRowBorder = Color(0xFFE3E8F0);
const Color kVaultListRowSelectedBg = Color(0xFFDCE8FF);
const Color kVaultListRowTitle = Color(0xFF2C3B56);
const Color kVaultListRowSubtitle = Color(0xFF6E6E73);
const Color kVaultListRowDate = Color(0xFF74839A);
const double kVaultListRowHeight = 64;
const double kVaultListAttributeRowHeight = 80;

final RegExp _vaultListEmailPattern = RegExp(
  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
  caseSensitive: false,
);

class VaultEntryListTile extends StatelessWidget {
  const VaultEntryListTile({
    super.key,
    required this.entry,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.showBottomBorder = true,
    this.showAttributeLines = false,
  });

  final KdbxEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool showBottomBorder;
  final bool showAttributeLines;

  @override
  Widget build(BuildContext context) {
    final itemType = classifyVaultItemType(entry);
    final subtitle = vaultEntryListSubtitle(entry, itemType);
    final dateLabel = formatVaultEntryListDateLabel(
      now: DateTime.now(),
      updatedAt: entry.updatedAt,
      createdAt: entry.createdAt,
    );
    final passkey = entryHasPasskeyChip(entry);
    final hasTotp = entry.otpAuthUrl != null && entry.otpAuthUrl!.isNotEmpty;
    final website = entry.url?.trim() ?? '';
    final showWebsite = showAttributeLines && website.isNotEmpty;
    final showSubtitleIcon =
        showAttributeLines && _showsAccountInlineIcon(entry, subtitle);
    final rowHeight = showAttributeLines
        ? kVaultListAttributeRowHeight
        : kVaultListRowHeight;
    const subtitleStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: kVaultListRowSubtitle,
    );
    const websiteStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w400,
      color: Color(0xFF8A96A8),
    );

    return RepaintBoundary(
      child: Material(
        color: selected ? kVaultListRowSelectedBg : Colors.white,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            height: rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: showBottomBorder
                      ? kVaultListRowBorder
                      : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              children: [
                VaultEntryAvatar(entry: entry, size: 28, itemType: itemType),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              entry.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: kVaultListRowTitle,
                              ),
                            ),
                          ),
                          if (passkey) ...[
                            const SizedBox(width: 6),
                            Image.asset(
                              'assets/images/passkey_icon.png',
                              width: 18,
                              height: 18,
                            ),
                          ],
                          if (hasTotp) ...[
                            const SizedBox(width: 6),
                            Image.asset(
                              'assets/images/totp_icon.png',
                              width: 18,
                              height: 18,
                            ),
                          ],
                        ],
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        showSubtitleIcon
                            ? _InlineValueLine(
                                icon: TablerIcons.user,
                                text: subtitle,
                                style: subtitleStyle,
                              )
                            : Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: subtitleStyle,
                              ),
                      ],
                      if (showWebsite) ...[
                        SizedBox(height: subtitle.isNotEmpty ? 1 : 2),
                        _InlineValueLine(
                          icon: TablerIcons.link,
                          text: website,
                          style: websiteStyle,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: kVaultListRowDate,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: Color(0xFFB8C0CC),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool _showsAccountInlineIcon(KdbxEntry entry, String subtitle) {
  final value = subtitle.trim();
  if (value.isEmpty) {
    return false;
  }

  final username = entry.username?.trim() ?? '';
  if (username.isNotEmpty &&
      value == truncateListPreview(singleLinePreview(username), 56)) {
    return true;
  }

  return _vaultListEmailPattern.hasMatch(value);
}

class _InlineValueLine extends StatelessWidget {
  const _InlineValueLine({
    required this.icon,
    required this.text,
    required this.style,
  });

  final IconData icon;
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Icon(icon, size: 12, color: style.color),
            ),
          ),
          TextSpan(text: text),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}
