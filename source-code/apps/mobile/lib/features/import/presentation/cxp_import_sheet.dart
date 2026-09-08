import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/credential_exchange_controller.dart';
import '../domain/import_parsed_item.dart';

const _kInk = Color(0xFF0A3B48);
const _kMuted = Color(0xFF6B858D);
const _kFaint = Color(0xFFAAB7BD);
const _kAccent = Color(0xFF0A67FF);
const _kSurface = Color(0xFFF4F7F9);
const _kDivider = Color(0xFFE3EAF0);

Future<void> showCxpImportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => const _CxpImportSheetContent(),
  );
}

class _CxpImportSheetContent extends ConsumerWidget {
  const _CxpImportSheetContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cxpImportControllerProvider);
    final mq = MediaQuery.of(context);

    // The preview view needs near-full-screen height so users can actually
    // scan dozens of items; the status views (executing/completed/failed)
    // size to their content.
    final isPreview = state.status == CxpImportStatus.received;
    final maxHeight = mq.size.height * (isPreview ? 0.92 : 0.55);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: _buildContent(context, ref, state),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    CxpImportState state,
  ) {
    switch (state.status) {
      case CxpImportStatus.idle:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        });
        return const SizedBox.shrink();

      case CxpImportStatus.received:
        return _ReceivedView(state: state);

      case CxpImportStatus.lockedNoVault:
        return _CompactView(child: _LockedView(state: state));

      case CxpImportStatus.executing:
        return _CompactView(child: _ExecutingView(state: state));

      case CxpImportStatus.completed:
        return _CompactView(child: _CompletedView(state: state));

      case CxpImportStatus.failed:
        return _CompactView(child: _FailedView(state: state));
    }
  }
}

/// Wrap status views in the same padded container the sheet used previously,
/// so the executing / completed / failed states keep their compact look.
class _CompactView extends StatelessWidget {
  const _CompactView({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DragHandle(),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFFD0D5DD),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// ─── Received (preview + per-item selection) ───────────────────────────

class _ReceivedView extends ConsumerWidget {
  const _ReceivedView({required this.state});
  final CxpImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(cxpImportControllerProvider.notifier);
    final allSelected = state.selectedCount == state.items.length;
    final noneSelected = state.selectedCount == 0;

    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        const SizedBox(height: 10),
        _DragHandle(),
        const SizedBox(height: 14),

        // Header — source app + count.
        _PreviewHeader(state: state),

        // Toolbar — select all / clear + selected count.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
          child: Row(
            children: [
              Text(
                '${state.selectedCount} of ${state.items.length} selected',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _kInk,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: allSelected
                    ? controller.deselectAll
                    : controller.selectAll,
                style: TextButton.styleFrom(
                  foregroundColor: _kAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  allSelected ? 'Clear all' : 'Select all',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1, color: _kDivider),

        // Scrollable list of parsed items.
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: state.items.length,
            itemBuilder: (context, i) {
              final item = state.items[i];
              final selected = state.selectedIndexes.contains(i);
              return _ItemRow(
                item: item,
                selected: selected,
                onTap: () => controller.toggleItem(i),
              );
            },
          ),
        ),

        // Footer — Cancel + Start Import buttons.
        _PreviewFooter(
          selectedCount: state.selectedCount,
          enabled: !noneSelected,
          onCancel: () {
            controller.dismiss();
            Navigator.of(context).pop();
          },
          onImport: controller.executeImport,
        ),
      ],
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.state});
  final CxpImportState state;

  @override
  Widget build(BuildContext context) {
    final exporter = state.exporterName ?? 'Another app';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.swap_horiz_rounded,
              color: _kAccent,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Import Credentials',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: _kInk,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'From $exporter · ${state.items.length} item'
                  '${state.items.length == 1 ? "" : "s"}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _kMuted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ImportParsedItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Build the second line: username · host. Fall back to URL or notes
    // snippet so the row is never blank.
    final subtitle = _buildSubtitle();
    final hasOtp =
        item.otpAuthUrl != null && item.otpAuthUrl!.trim().isNotEmpty;
    final hasPasskey = item.customFields.any(
      (f) => f.name.startsWith('KPEX_PASSKEY_'),
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Item glyph
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials(item.title),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _kInk,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _kInk,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (hasPasskey) ...[
                        const SizedBox(width: 6),
                        _Badge(label: 'Passkey', color: _kAccent),
                      ],
                      if (hasOtp) ...[
                        const SizedBox(width: 6),
                        _Badge(label: 'TOTP', color: Color(0xFF22C55E)),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: _kMuted,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Checkbox
            _SelectionCheck(selected: selected),
          ],
        ),
      ),
    );
  }

  String? _buildSubtitle() {
    final username = item.username?.trim();
    final url = item.url?.trim();
    final host = _extractHost(url);

    if (username != null && username.isNotEmpty && host != null) {
      return '$username · $host';
    }
    if (username != null && username.isNotEmpty) return username;
    if (host != null) return host;
    if (url != null && url.isNotEmpty) return url;

    final notes = item.notes?.trim();
    if (notes != null && notes.isNotEmpty) {
      return notes.length > 60 ? '${notes.substring(0, 57)}…' : notes;
    }
    return null;
  }

  static String _initials(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'[\s._-]+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return trimmed[0].toUpperCase();
  }

  static String? _extractHost(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    try {
      final uri = Uri.parse(url.trim());
      final host = uri.host;
      if (host.isNotEmpty) {
        return host.startsWith('www.') ? host.substring(4) : host;
      }
    } catch (_) {}
    return null;
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _SelectionCheck extends StatelessWidget {
  const _SelectionCheck({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? _kAccent : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? _kAccent : _kFaint,
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
          : null,
    );
  }
}

class _PreviewFooter extends StatelessWidget {
  const _PreviewFooter({
    required this.selectedCount,
    required this.enabled,
    required this.onCancel,
    required this.onImport,
  });

  final int selectedCount;
  final bool enabled;
  final VoidCallback onCancel;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kDivider, width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kMuted,
                  side: const BorderSide(color: _kDivider),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: enabled ? onImport : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _kAccent,
                  disabledBackgroundColor:
                      _kAccent.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  selectedCount == 0
                      ? 'Select items'
                      : 'Start Import ($selectedCount)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Locked / No Vault ─────────────────────────────────────────────────

class _LockedView extends ConsumerWidget {
  const _LockedView({required this.state});
  final CxpImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exporter = state.exporterName ?? '1Password';
    final controller = ref.read(cxpImportControllerProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.lock_outline_rounded,
            size: 28,
            color: Color(0xFFF59E0B),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Vault is Locked',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _kInk,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$exporter wants to transfer ${state.items.length} '
          'credential${state.items.length == 1 ? "" : "s"} to LumenPass.\n\n'
          'Please unlock your vault first, then come back here '
          'to continue the import.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14.5,
            color: _kMuted,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: () {
              // Re-check vault state — user may have unlocked while sheet
              // was showing. If still locked, dismiss so they can unlock.
              controller.retryAfterUnlock();
              final updated = ref.read(cxpImportControllerProvider);
              if (updated.status == CxpImportStatus.lockedNoVault) {
                // Still locked — dismiss the sheet so the user can
                // navigate to the unlock screen. The payload stays
                // in-memory; main.dart's listener will re-show the sheet
                // once `retryAfterUnlock()` succeeds.
                Navigator.of(context).pop();
              }
              // If promoted to `received`, the sheet rebuilds automatically
              // into the preview list — no extra action needed.
            },
            style: FilledButton.styleFrom(
              backgroundColor: _kAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Unlock Vault',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: () {
              controller.dismiss();
              Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: _kMuted,
              side: const BorderSide(color: _kDivider),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Executing ─────────────────────────────────────────────────────────

class _ExecutingView extends StatelessWidget {
  const _ExecutingView({required this.state});
  final CxpImportState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            value: state.fraction > 0 ? state.fraction : null,
            strokeWidth: 3,
            color: _kAccent,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Importing credentials...',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: _kInk,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${state.current} of ${state.total}',
          style: const TextStyle(fontSize: 14, color: _kMuted),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: state.fraction,
            minHeight: 6,
            backgroundColor: _kDivider,
            color: _kAccent,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Completed ─────────────────────────────────────────────────────────

class _CompletedView extends ConsumerWidget {
  const _CompletedView({required this.state});
  final CxpImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.check_circle_rounded,
          size: 48,
          color: Color(0xFF22C55E),
        ),
        const SizedBox(height: 16),
        const Text(
          'Import Complete',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _kInk,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${state.succeeded} credential${state.succeeded == 1 ? "" : "s"} '
          'imported successfully'
          '${state.failed > 0 ? ", ${state.failed} failed" : ""}.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: _kMuted, height: 1.4),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: () {
              ref.read(cxpImportControllerProvider.notifier).dismiss();
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: _kAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Done',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Failed ────────────────────────────────────────────────────────────

class _FailedView extends ConsumerWidget {
  const _FailedView({required this.state});
  final CxpImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 48,
          color: Color(0xFFEF4444),
        ),
        const SizedBox(height: 16),
        const Text(
          'Import Failed',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _kInk,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          state.errorMessage ?? 'An unknown error occurred.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: _kMuted, height: 1.4),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: () {
              ref.read(cxpImportControllerProvider.notifier).dismiss();
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: _kAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Dismiss',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}
