import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ui/app_snack_bar.dart';
import '../application/autofill_bridge.dart';
import '../application/autofill_providers.dart';

/// Persisted forever. When `true`, the "Turn On AutoFill" nudge is muted
/// across every subsequent unlock. User can undo from the AutoFill settings
/// section if we expose a switch there in the future.
const String kPrefAutoFillReminderOptedOut = 'autofill.reminder.opted_out';

/// Checks the AutoFill service status and — if the provider is installed
/// but not yet enabled — surfaces the "Turn On AutoFill" sheet. No-op if:
///   • the platform doesn't support AutoFill (web/desktop),
///   • the user already enabled the provider,
///   • the user previously tapped "Don't Use AutoFill".
///
/// Safe to call from any post-unlock entry point; it handles its own
/// preference + status guards.
Future<void> maybeShowAutoFillReminder(
  BuildContext context,
  WidgetRef ref,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kPrefAutoFillReminderOptedOut) == true) return;
  } catch (_) {
    // If we can't read prefs, fall through — showing the sheet is safer
    // than silently dropping the nudge.
  }

  AutoFillServiceStatus status;
  try {
    // Force a fresh read so a recent toggle in Settings isn't missed.
    ref.invalidate(autoFillServiceStatusProvider);
    status = await ref.read(autoFillServiceStatusProvider.future);
  } catch (_) {
    return;
  }
  if (status != AutoFillServiceStatus.disabled) return;

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x99000000),
    builder: (_) => const AutoFillReminderSheet(),
  );
}

/// "Turn On AutoFill" coaching sheet shown right after unlock when the OS
/// AutoFill provider hasn't been enabled yet. Offers three outcomes:
///
/// * `AutoFill Settings` — deep-links into iOS Settings so the user can
///   flip the provider on, using the same bridge that powers the Settings
///   screen CTA. The success sheet in `main.dart` picks it up on return.
/// * `Setup Later` — dismisses without persisting anything, so the sheet
///   reappears on the next unlock.
/// * `Don't Use AutoFill` — persists an opt-out flag so we never nag again.
class AutoFillReminderSheet extends ConsumerStatefulWidget {
  const AutoFillReminderSheet({super.key});

  @override
  ConsumerState<AutoFillReminderSheet> createState() =>
      _AutoFillReminderSheetState();
}

class _AutoFillReminderSheetState extends ConsumerState<AutoFillReminderSheet> {
  // Brand palette — mirrors the home shell and Settings screens.
  static const _kInk = Color(0xFF0A3B48);
  static const _kText = Color(0xFF163640);
  static const _kMuted = Color(0xFF6B858D);
  static const _kDanger = Color(0xFFD97706);
  static const _kDangerSoft = Color(0xFFFDECCF);

  bool _isOpening = false;
  bool _isOptingOut = false;

  Future<void> _openSettings() async {
    if (_isOpening) return;
    setState(() => _isOpening = true);
    final bridge = ref.read(autoFillBridgeProvider);
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Close the sheet up-front so the user isn't returning to a stacked
    // modal when the success sheet auto-surfaces from `main.dart`'s
    // resume listener. The native hand-off is fired right after.
    Navigator.of(context).pop();
    final opened = await bridge.openSystemSettings();
    if (!opened) {
      if (messenger != null && overlay != null) {
        AppSnackBar.showOnOverlay(
          overlay,
          'Unable to open system AutoFill settings.',
          variant: SnackBarVariant.error,
        );
      }
    }
  }

  Future<void> _dontUse() async {
    if (_isOptingOut) return;
    setState(() => _isOptingOut = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kPrefAutoFillReminderOptedOut, true);
    } catch (_) {
      // Best effort — if persistence fails the user will just see this
      // sheet again on the next unlock.
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(22, 8, 22, 20 + safeBottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row: keep the drag handle perfectly centered while the
            // "Setup Later" button sits in the top-right with iOS-like inset.
            SizedBox(
              height: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 2,
                    child: _SetupLaterButton(
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Center(child: _AutoFillReminderHero()),
            const SizedBox(height: 18),
            const Text(
              'Turn On AutoFill',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _kText,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Let LumenPass fill your passwords and passkeys in Safari "
              'and every other app — fast, secure, and always at your fingertips.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                height: 1.45,
                color: _kInk.withValues(alpha: 0.68),
              ),
            ),
            const SizedBox(height: 18),
            _StepsCard(),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isOpening ? null : _openSettings,
                icon: _isOpening
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.arrow_outward_rounded, size: 18),
                label: Text(
                  _isOpening ? 'Opening…' : 'AutoFill Settings',
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kInk,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _isOptingOut ? null : _dontUse,
              style: TextButton.styleFrom(
                foregroundColor: _kDanger,
                backgroundColor: _kDangerSoft,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isOptingOut
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _kDanger,
                      ),
                    )
                  : const Text(
                      "Don't Use AutoFill",
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            const Text(
              '*Not recommended — you will have to type passwords manually.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _kMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupLaterButton extends StatelessWidget {
  const _SetupLaterButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE3EAF0), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120A2F3D),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Text(
            'Setup Later',
            style: TextStyle(
              color: Color(0xFF4A5A63),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  const _StepsCard();

  static const _kInk = Color(0xFF0A3B48);
  static const _kText = Color(0xFF163640);
  static const _kMuted = Color(0xFF6B858D);
  static const _kBorder = Color(0xFFE3EAF0);
  static const _kSoft = Color(0xFFF4F9FA);

  @override
  Widget build(BuildContext context) {
    const steps = <String>[
      'Tap "AutoFill Settings" below.',
      'Toggle AutoFill on.',
      'Choose LumenPass as the provider.',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _kSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded, size: 15, color: _kInk),
              const SizedBox(width: 6),
              Text(
                'Step by step',
                style: TextStyle(
                  color: _kInk,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < steps.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: _kBorder),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: _kInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    steps[i],
                    style: const TextStyle(
                      color: _kText,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            if (i < steps.length - 1) const SizedBox(height: 8),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              children: const [
                Icon(Icons.info_outline_rounded, size: 14, color: _kMuted),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "These instructions stay here until you're done.",
                    style: TextStyle(
                      color: _kMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
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

class _AutoFillReminderHero extends StatelessWidget {
  const _AutoFillReminderHero();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Soft halo to lift the icon off the sheet background.
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFDCEEF2).withValues(alpha: 0.55),
            ),
          ),
          // App icon disc.
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/images/lumenpass-dark.png',
              fit: BoxFit.cover,
            ),
          ),
        ],
      ),
    );
  }
}
