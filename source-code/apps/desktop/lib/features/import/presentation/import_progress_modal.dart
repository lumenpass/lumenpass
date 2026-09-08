import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../application/import_executor.dart';

class ImportProgressModal extends StatefulWidget {
  const ImportProgressModal({
    required this.progress,
    required this.onDone,
    required this.onCancelRequested,
  });

  final ImportProgress progress;
  final VoidCallback onDone;
  final VoidCallback onCancelRequested;

  @override
  State<ImportProgressModal> createState() => _ImportProgressModalState();
}

class _ImportProgressModalState extends State<ImportProgressModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _successController;
  late final Animation<double> _successScale;
  final ScrollController _logScrollController = ScrollController();

  bool _wasCompleted = false;

  @override
  void initState() {
    super.initState();
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _successScale = CurvedAnimation(
      parent: _successController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _successController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ImportProgressModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isComplete =
        widget.progress.status == ImportProgressStatus.completed;
    if (isComplete && !_wasCompleted) {
      _wasCompleted = true;
      _successController.forward();
    }
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
    final isComplete = progress.status == ImportProgressStatus.completed;
    final isRunning = progress.status == ImportProgressStatus.running;

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
            if (isComplete) ...<Widget>[
              ScaleTransition(
                scale: _successScale,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    TablerIcons.circle_check,
                    size: 36,
                    color: Color(0xFF22C55E),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Import Complete',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1D23),
                ),
              ),
              const SizedBox(height: 8),
              _buildCompletionStats(progress),
            ] else ...<Widget>[
              const Text(
                'Importing Items',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1D23),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isRunning
                    ? 'Processing ${progress.current} of ${progress.total} items'
                    : 'Preparing...',
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
                    Color(0xFF0A3B48),
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
                    'Import log',
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
              if (isRunning) ...<Widget>[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _MiniStat(
                      label: 'Succeeded',
                      count: progress.succeeded,
                      color: const Color(0xFF22C55E),
                    ),
                    const SizedBox(width: 16),
                    _MiniStat(
                      label: 'Failed',
                      count: progress.failed,
                      color: progress.failed > 0
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF9CA3AF),
                    ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 24),
            if (isComplete)
              _FooterButton(
                label: 'Close',
                backgroundColor: const Color(0xFF0A3B48),
                textColor: Colors.white,
                onTap: widget.onDone,
              )
            else
              _FooterButton(
                label: 'Cancel',
                backgroundColor: Colors.white,
                textColor: const Color(0xFF374151),
                borderColor: const Color(0xFFD1D5DB),
                onTap: () async {
                  final shouldCancel = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      title: const Text('Cancel Import?',
                          style: TextStyle(color: Color(0xFF1F2937))),
                      content: const Text(
                          'Are you sure you want to cancel the import process? Some items may have already been imported.',
                          style: TextStyle(color: Color(0xFF4B5563))),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('No, continue',
                              style: TextStyle(color: Color(0xFF4B5563))),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Yes, cancel',
                              style: TextStyle(color: Color(0xFFDC2626))),
                        ),
                      ],
                    ),
                  );
                  if (shouldCancel == true) {
                    widget.onCancelRequested();
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionStats(ImportProgress progress) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          progress.failed > 0
              ? 'Processed ${progress.total} items with some errors.'
              : 'All ${progress.total} items imported successfully.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: _ReportStat(
                label: 'Total',
                count: progress.total,
                color: const Color(0xFF374151),
                icon: TablerIcons.list_details,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ReportStat(
                label: 'Imported',
                count: progress.succeeded,
                color: const Color(0xFF22C55E),
                icon: TablerIcons.circle_check,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ReportStat(
                label: 'Failed',
                count: progress.failed,
                color: progress.failed > 0
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF9CA3AF),
                icon: TablerIcons.circle_x,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReportStat extends StatelessWidget {
  const _ReportStat({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  final String label;
  final int count;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
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
    );
  }
}
