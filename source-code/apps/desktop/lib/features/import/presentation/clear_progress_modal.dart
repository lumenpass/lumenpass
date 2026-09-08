import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../application/import_executor.dart';

/// Modal shown while Replace mode is wiping the existing vault items.
///
/// Mirrors the structure of `ImportProgressModal` (header, progress bar,
/// percent readout, log panel, footer) so that the transition between the
/// "cleaning" phase and the "importing" phase feels seamless.
class ClearProgressModal extends StatefulWidget {
  const ClearProgressModal({
    super.key,
    required this.progress,
    required this.onRetry,
    required this.onCancel,
  });

  final ImportProgress progress;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  State<ClearProgressModal> createState() => _ClearProgressModalState();
}

class _ClearProgressModalState extends State<ClearProgressModal> {
  final ScrollController _logScrollController = ScrollController();

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ClearProgressModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the newest log line in view as entries stream in.
    if (widget.progress.logs.length != oldWidget.progress.logs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_logScrollController.hasClients) return;
        _logScrollController.jumpTo(
          _logScrollController.position.maxScrollExtent,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final isFailed = progress.status == ImportProgressStatus.failed;
    final isRunning = progress.status == ImportProgressStatus.running ||
        progress.status == ImportProgressStatus.idle;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x22172033),
              blurRadius: 40,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (isFailed) ...<Widget>[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  TablerIcons.alert_triangle,
                  size: 32,
                  color: Color(0xFFEF4444),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Cleanup Failed',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1D23),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                progress.errorMessage ??
                    'The vault could not be fully cleared. '
                        'Try again before importing.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ] else ...<Widget>[
              const Text(
                'Cleaning Old Items',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1D23),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                progress.total == 0 && progress.current == 0
                    ? 'Preparing...'
                    : 'Removing ${progress.current} of ${progress.total} items',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress.fraction,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFF3F4F6),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFFEF4444),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${progress.percent}%',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              if (isRunning && progress.logs.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Cleanup log',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  height: 132,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: ListView.builder(
                    controller: _logScrollController,
                    padding: EdgeInsets.zero,
                    itemCount: progress.logs.length,
                    itemBuilder: (context, index) {
                      final entry = progress.logs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          entry.message,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            height: 1.4,
                            color: entry.isError
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF6B7280),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),
            if (isFailed)
              Row(
                children: <Widget>[
                  Expanded(
                    child: _FooterButton(
                      label: 'Cancel',
                      backgroundColor: Colors.white,
                      textColor: const Color(0xFF374151),
                      borderColor: const Color(0xFFD1D5DB),
                      onTap: widget.onCancel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FooterButton(
                      label: 'Retry',
                      backgroundColor: const Color(0xFF0A3B48),
                      textColor: Colors.white,
                      onTap: widget.onRetry,
                    ),
                  ),
                ],
              )
            else
              const _SpinnerHint(),
          ],
        ),
      ),
    );
  }
}

class _SpinnerHint extends StatelessWidget {
  const _SpinnerHint();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEF4444)),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Please wait while the vault is cleaned...',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

class _FooterButton extends StatefulWidget {
  const _FooterButton({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    required this.onTap,
    this.borderColor,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  State<_FooterButton> createState() => _FooterButtonState();
}

class _FooterButtonState extends State<_FooterButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onTap != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              color: _hovered && isEnabled
                  ? widget.backgroundColor.withValues(alpha: 0.8)
                  : widget.backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: widget.borderColor != null
                  ? Border.all(color: widget.borderColor!)
                  : null,
            ),
            child: Center(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: widget.textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
