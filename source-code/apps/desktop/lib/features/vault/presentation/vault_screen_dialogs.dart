part of 'vault_screen.dart';

class _NewVersionBanner extends StatelessWidget {
  const _NewVersionBanner({
    required this.version,
    required this.onDownload,
    required this.onDismiss,
  });

  final String version;
  final VoidCallback onDownload;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final formatted = _formatBannerVersion(version);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB870),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                const Icon(
                  TablerIcons.rocket,
                  size: 18,
                  color: Color(0xFF0F172A),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: _text(
                        11,
                        const Color(0xFF0F172A),
                        fontWeight: FontWeight.w400,
                      ).copyWith(decoration: TextDecoration.none),
                      children: <InlineSpan>[
                        const TextSpan(text: 'New version released '),
                        TextSpan(
                          text: formatted,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _NewVersionBannerCta(onPressed: onDownload),
                const SizedBox(width: 4),
                _NewVersionBannerDismiss(onPressed: onDismiss),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatBannerVersion(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final plusIndex = trimmed.indexOf('+');
    if (plusIndex < 0) return 'v$trimmed';
    final core = trimmed.substring(0, plusIndex).trim();
    final build = trimmed.substring(plusIndex + 1).trim();
    if (core.isEmpty) return 'v$trimmed';
    if (build.isEmpty) return 'v$core';
    return 'v$core Build $build';
  }
}

class _NewVersionBannerCta extends StatelessWidget {
  const _NewVersionBannerCta({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(
        TablerIcons.download,
        size: 14,
        color: Color(0xFF0F172A),
      ),
      label: Text(
        'Download new version',
        style: _text(
          11,
          const Color(0xFF0F172A),
          fontWeight: FontWeight.w700,
        ),
      ),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF0F172A),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        backgroundColor: const Color(0xFF0F172A).withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

class _NewVersionBannerDismiss extends StatelessWidget {
  const _NewVersionBannerDismiss({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Dismiss',
      splashRadius: 16,
      iconSize: 16,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(),
      icon: const Icon(
        TablerIcons.x,
        color: Color(0xFF0F172A),
      ),
    );
  }
}

class _InAppToast extends StatelessWidget {
  const _InAppToast({
    required this.message,
    this.danger = false,
    super.key,
  });

  final String message;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFDC2626) : const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(12),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: danger ? const Color(0x33DC2626) : const Color(0x1F0F172A),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            danger ? TablerIcons.alert_circle : TablerIcons.copy_check,
            size: 15,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style:
                  _text(12, Colors.white, fontWeight: FontWeight.w600).copyWith(
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoveAttributeConfirmationOverlay extends StatelessWidget {
  const _RemoveAttributeConfirmationOverlay({
    required this.onCancel,
    required this.onConfirm,
  });

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCancel,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            color: const Color(0x99F8FAFC),
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE5EAF2)),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x140F172A),
                      blurRadius: 30,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Remove this attribute?',
                      style: _text(
                        18,
                        const Color(0xFF202939),
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Are you sure you want to remove this attribute? This action cannot be undone.',
                      style: _text(
                        14,
                        const Color(0xFF4B5565),
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onConfirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kDangerButtonColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Remove Attribute',
                          style: _text(
                            14,
                            Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: onCancel,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          side: const BorderSide(color: Color(0xFFD6DCE6)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: _text(
                            14,
                            const Color(0xFF3E4A5E),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteConfirmationOverlay extends StatelessWidget {
  const _DeleteConfirmationOverlay({
    required this.entryTitle,
    required this.isDeleting,
    required this.onCancel,
    required this.onConfirm,
  });

  final String entryTitle;
  final bool isDeleting;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isDeleting ? null : onCancel,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            color: const Color(0x99F8FAFC),
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 440,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE5EAF2)),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x140F172A),
                      blurRadius: 30,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Are you sure you want to delete\n"$entryTitle"?',
                      style: _text(
                        18,
                        const Color(0xFF202939),
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Once deleted, you can restore this item from Trash later. This confirmation is shown to prevent accidental removal.",
                      style: _text(
                        14,
                        const Color(0xFF4B5565),
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onConfirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kDangerButtonColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          isDeleting ? 'Deleting...' : 'Delete Item',
                          style: _text(
                            14,
                            Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: isDeleting ? null : onCancel,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          side: const BorderSide(color: Color(0xFFD6DCE6)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: _text(
                            14,
                            const Color(0xFF3E4A5E),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteCategoryConfirmationOverlay extends StatelessWidget {
  const _DeleteCategoryConfirmationOverlay({
    required this.categoryName,
    required this.onCancel,
    required this.onConfirm,
  });

  final String categoryName;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCancel,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            color: const Color(0x99F8FAFC),
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 440,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE5EAF2)),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x140F172A),
                      blurRadius: 30,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Delete "$categoryName"?',
                      style: _text(
                        18,
                        const Color(0xFF202939),
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'The category will be removed. Items inside it will be moved to the recycle bin along with the category. This action cannot be undone from here.',
                      style: _text(
                        14,
                        const Color(0xFF4B5565),
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onConfirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kDangerButtonColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Delete Category',
                          style: _text(
                            14,
                            Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: onCancel,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          side: const BorderSide(color: Color(0xFFD6DCE6)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: _text(
                            14,
                            const Color(0xFF3E4A5E),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RemovePasskeyConfirmationOverlay extends StatelessWidget {
  const _RemovePasskeyConfirmationOverlay({
    required this.entryTitle,
    required this.onCancel,
    required this.onConfirm,
  });

  final String entryTitle;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCancel,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            color: const Color(0x99F8FAFC),
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 420,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE5EAF2)),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x140F172A),
                      blurRadius: 30,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Remove passkey from\n"$entryTitle"?',
                      style: _text(
                        18,
                        const Color(0xFF202939),
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'This will remove the saved passkey data for this item. You can add a new passkey again later if needed.',
                      style: _text(
                        14,
                        const Color(0xFF4B5565),
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onConfirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kDangerButtonColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Remove Passkey',
                          style: _text(
                            14,
                            Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: onCancel,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          side: const BorderSide(color: Color(0xFFD6DCE6)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: _text(
                            14,
                            const Color(0xFF3E4A5E),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown briefly while the vault is being flushed to cloud storage before
/// the user leaves the screen (lock). Non-dismissible so the cache can't be
/// clobbered by a stale cloud copy on the next unlock.
class _CloudSyncBlockingDialog extends StatelessWidget {
  const _CloudSyncBlockingDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 36,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Syncing to cloud…',
                      style: _text(
                        15,
                        const Color(0xFF111827),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Finishing upload before locking the vault.',
                      style: _text(
                        12,
                        const Color(0xFF6B7280),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
