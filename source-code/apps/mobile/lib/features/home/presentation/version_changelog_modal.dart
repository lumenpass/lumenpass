import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/release_api_client.dart';
import '../../../core/ui/app_snack_bar.dart';

const _kInk = Color(0xFF0A3B48);
const _kInkStrong = Color(0xFF0B1F26);
const _kBody = Color(0xFF243047);
const _kMuted = Color(0xFF6B858D);
const _kBorder = Color(0xFFE3EAF0);
const _kSurface = Color(0xFFF4F9FA);

const _iosStoreUrl = String.fromEnvironment('IOS_STORE_URL');
const _androidStoreUrl = String.fromEnvironment('ANDROID_STORE_URL');

/// Central information modal that surfaces the full change log for a newly
/// detected release. Opened when the user taps the "new version" toast.
Future<void> showVersionChangeLogModal(
  BuildContext context,
  LatestRelease release,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Version details',
    builder: (ctx) => _VersionChangeLogDialog(release: release),
  );
}

class _VersionChangeLogDialog extends StatelessWidget {
  const _VersionChangeLogDialog({required this.release});

  final LatestRelease release;

  @override
  Widget build(BuildContext context) {
    final changeLog = release.changeLog.trim();
    final storeUrl = _platformStoreUrl();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 38),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _kSurface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.rocket_launch_rounded,
                          color: _kInk,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'New version available',
                              style: TextStyle(
                                color: _kInkStrong,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'v${formatReleaseVersion(release.version)}',
                              style: const TextStyle(
                                color: _kMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: _CloseButton(onTap: () => Navigator.of(context).pop()),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              "What's new",
              style: TextStyle(
                color: _kInkStrong,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 320),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kBorder),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    changeLog.isEmpty
                        ? 'No release notes provided.'
                        : changeLog,
                    style: const TextStyle(
                      color: _kBody,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            if (storeUrl.isNotEmpty) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openStore(context, storeUrl),
                  style: FilledButton.styleFrom(
                    backgroundColor: _kInk,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Open in Store'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _platformStoreUrl() {
    if (Platform.isIOS) return _iosStoreUrl.trim();
    if (Platform.isAndroid) return _androidStoreUrl.trim();
    return '';
  }

  Future<void> _openStore(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (context.mounted) {
        AppSnackBar.error(context, 'Unable to open the store right now.');
      }
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        AppSnackBar.error(context, 'Unable to open the store right now.');
      }
    } catch (_) {
      if (context.mounted) {
        AppSnackBar.error(context, 'Unable to open the store right now.');
      }
    }
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            color: _kSurface,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.close_rounded, color: _kMuted, size: 18),
        ),
      ),
    );
  }
}
