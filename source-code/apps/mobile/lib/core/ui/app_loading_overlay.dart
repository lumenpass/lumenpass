import 'package:flutter/material.dart';

import 'app_snack_bar.dart';

// ---------------------------------------------------------------------------
// Global loading overlay
//
// Pattern for all actions:
//   1. 1s lead-in pause (user sees intent registered)
//   2. Show loading overlay + execute task
//   3. 1s tail pause (result registers visually)
//   4. Dismiss overlay + show toast result
// ---------------------------------------------------------------------------

OverlayEntry? _overlayEntry;

class ActionToastError implements Exception {
  const ActionToastError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Wraps [task] in a global full-screen loading overlay with the sequence:
///   delay → loading overlay → task → delay → toast.
///
/// [successMessage] is shown in a toast on completion.
/// [errorMessage] is shown if [task] throws; the error is NOT re-thrown.
/// Set [leadIn] / [tailPause] to adjust timing (defaults: 1 s each).
Future<void> withGlobalLoading(
  BuildContext context,
  Future<void> Function() task, {
  String loadingMessage = 'Loading…',
  String successMessage = 'Done',
  String? errorMessage,
  Duration leadIn = const Duration(seconds: 1),
  Duration tailPause = const Duration(seconds: 1),
}) async {
  // 1. Lead-in pause
  await Future<void>.delayed(leadIn);

  if (!context.mounted) return;

  // 2. Show overlay
  _showOverlay(context, loadingMessage);

  String? toastMsg;
  bool isError = false;

  try {
    await task();
    toastMsg = successMessage;
  } catch (error) {
    isError = true;
    toastMsg = switch (error) {
      ActionToastError(:final message) => message,
      _ => errorMessage ?? 'Something went wrong',
    };
  }

  // 3. Tail pause (overlay still visible)
  await Future<void>.delayed(tailPause);

  // 4. Dismiss overlay + show toast
  _hideOverlay();
  if (context.mounted) {
    _showToast(context, toastMsg, isError: isError);
  }
}

void _showOverlay(BuildContext context, String message) {
  _overlayEntry?.remove();
  _overlayEntry = null;

  final overlay = Overlay.of(context, rootOverlay: true);
  _overlayEntry = OverlayEntry(
    builder: (_) => _LoadingOverlayWidget(message: message),
  );
  overlay.insert(_overlayEntry!);
}

void _hideOverlay() {
  _overlayEntry?.remove();
  _overlayEntry = null;
}

void _showToast(BuildContext context, String message, {bool isError = false}) {
  if (isError) {
    AppSnackBar.error(context, message);
    return;
  }
  AppSnackBar.success(context, message);
}

class _LoadingOverlayWidget extends StatelessWidget {
  const _LoadingOverlayWidget({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
          decoration: BoxDecoration(
            color: const Color(0xFF1C2330),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A90D9)),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
