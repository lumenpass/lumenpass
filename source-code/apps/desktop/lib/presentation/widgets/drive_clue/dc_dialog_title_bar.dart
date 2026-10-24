import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../theme/drive_clue_tokens.dart';
import '../lumenpass_wordmark.dart';

/// Branded, compact title bar shared by desktop dialogs.
class DcDialogTitleBar extends StatelessWidget {
  const DcDialogTitleBar({
    super.key,
    required this.title,
    this.onClose,
    this.onBack,
  });

  final String title;
  final VoidCallback? onClose;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DcMetrics.headerHeight,
      width: double.infinity,
      padding: const EdgeInsets.only(left: 18, right: 12),
      decoration: const BoxDecoration(color: DcColors.background),
      child: Row(
        children: <Widget>[
          if (onBack != null) ...<Widget>[
            IconButton(
              tooltip: 'Back to item types',
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              padding: EdgeInsets.zero,
              onPressed: onBack,
              icon: const Icon(TablerIcons.arrow_left,
                  size: 16, color: DcColors.text),
            ),
            const SizedBox(width: 8),
          ],
          const LumenPassWordmark(
            fontSize: 15,
            lumenColor: DcColors.text,
            passColor: DcColors.cyan,
          ),
          const SizedBox(width: 8),
          const Text('-', style: TextStyle(color: DcColors.muted)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DcColors.text,
              ),
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: 'Close dialog',
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              padding: EdgeInsets.zero,
              onPressed: onClose,
              icon: const Icon(TablerIcons.x, size: 16, color: DcColors.text),
            ),
        ],
      ),
    );
  }
}
