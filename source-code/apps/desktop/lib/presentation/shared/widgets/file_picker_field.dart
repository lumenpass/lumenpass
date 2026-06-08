import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

/// Styled row that displays a file path with desktop-friendly picker actions.
class FilePickerField extends StatelessWidget {
  const FilePickerField({
    required this.label,
    required this.hintText,
    required this.onPressed,
    required this.actionLabel,
    this.value,
    this.onClear,
    super.key,
  });

  final String label;
  final String hintText;
  final String actionLabel;
  final String? value;
  final VoidCallback onPressed;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.64),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                const Icon(TablerIcons.folder_open),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value == null || value!.isEmpty ? hintText : value!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: value == null || value!.isEmpty
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (onClear != null) ...<Widget>[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Clear selection',
                    onPressed: onClear,
                    icon: const Icon(TablerIcons.x),
                  ),
                ],
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onPressed,
                  child: Text(actionLabel),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
