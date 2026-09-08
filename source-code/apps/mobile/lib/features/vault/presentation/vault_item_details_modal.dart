import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/repository/providers.dart';
import '../../../core/ui/app_snack_bar.dart';
import '../application/vault_items_list_providers.dart';
import '../../../features/settings/application/vault_security_provider.dart';
import 'vault_create_item.dart';
import 'vault_entry_avatar.dart';
import 'vault_totp_capture_overlay.dart';

const _totpService = TOTPService();
OverlayEntry? _copyToastEntry;
Timer? _copyToastTimer;

Future<void> showItemDetailsModal(
  BuildContext context, {
  required KdbxEntry entry,
  String? categoryName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ItemDetailsSheet(entry: entry, categoryName: categoryName),
  );
}

class _ItemDetailsSheet extends ConsumerStatefulWidget {
  const _ItemDetailsSheet({required this.entry, this.categoryName});

  final KdbxEntry entry;
  final String? categoryName;

  @override
  ConsumerState<_ItemDetailsSheet> createState() => _ItemDetailsSheetState();
}

class _ItemDetailsSheetState extends ConsumerState<_ItemDetailsSheet> {
  Timer? _ticker;

  /// Drives only the TOTP row. The per-second tick updates this notifier so a
  /// [ValueListenableBuilder] scoped to the OTP field rebuilds — instead of
  /// calling `setState` and rebuilding the entire sheet every second while a
  /// TOTP is visible.
  final ValueNotifier<DateTime> _totpTime = ValueNotifier<DateTime>(
    DateTime.now(),
  );
  final Set<String> _revealedFieldKeys = <String>{};
  late KdbxEntry _entry;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _syncTotpTicker();
    _recordLastUsed();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hide = ref
          .read(vaultSecuritySettingsProvider)
          .hidePasswordsByDefault;
      if (!hide) {
        // Reveal all secret fields by default.
        final fields = _entry.fields
            .where((f) => f.isProtected)
            .map((f) => f.key);
        setState(() => _revealedFieldKeys.addAll(fields));
      }
    });
  }

  void _syncTotpTicker() {
    _ticker?.cancel();
    if (!entryHasTotp(_entry)) {
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        // Only the TOTP row listens to this notifier, so the per-second tick
        // rebuilds that single leaf instead of the whole sheet.
        _totpTime.value = DateTime.now();
      }
    });
  }

  /// Records that this entry was just viewed and persists the updated "last
  /// used" timestamp so the default Last-Used sort reflects it. The snapshot
  /// publishes immediately so lists re-sort at once; the disk write is
  /// debounced in the background because a usage stamp is low-priority and
  /// must never block (or even slow down) opening the details view.
  void _recordLastUsed() {
    final uuid = _entry.uuid;
    if (uuid.isEmpty) {
      return;
    }
    unawaited(() async {
      try {
        final repository = ref.read(kdbxRepositoryProvider);
        if (!repository.hasOpenDatabase) {
          return;
        }
        await repository.touchEntryLastUsedAt(uuid);
        publishAndScheduleSave(ref, repository, immediate: false);
      } catch (_) {
        // Best-effort: never surface usage-tracking failures to the user.
      }
    }());
  }

  KdbxEntry? _findEntryByUuid(KdbxDatabase database, String uuid) {
    for (final entry
        in database.rootGroup.subtreeEntriesExcludingRecycleBin()) {
      if (entry.uuid == uuid) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _handleTotpAction() async {
    final itemType = classifyVaultItemType(_entry);
    if (itemType != VaultItemType.login) {
      return;
    }
    final hadTotp = entryHasTotp(_entry);
    final url = await showTotpCaptureOverlay(context);
    if (!mounted || url == null || url.trim().isEmpty) {
      return;
    }

    try {
      final repository = ref.read(kdbxRepositoryProvider);
      final fields = <EntryField>[
        for (final field in _entry.fields)
          if (!isOtpFieldKey(field.key)) field,
        EntryField(
          key: preferredOtpFieldKey(_entry),
          value: url,
          isProtected: true,
          isStandard: true,
        ),
      ];

      await repository.updateEntry(
        entryUuid: _entry.uuid,
        fields: fields,
        notes: _entry.notes,
        tags: List<String>.unmodifiable(_entry.tags),
      );
      final database = publishAndScheduleSave(ref, repository);
      final updated = _findEntryByUuid(database, _entry.uuid);
      if (updated != null && mounted) {
        setState(() => _entry = updated);
        _syncTotpTicker();
      }
      if (!mounted) {
        return;
      }
      _showCopyToast(
        context,
        hadTotp ? '2FA code updated' : '2FA code added to item',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showCopyToast(context, 'Unable to save 2FA code: $error');
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _totpTime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    final itemType = classifyVaultItemType(entry);
    final hideCardNumber = ref.watch(
      vaultSecuritySettingsProvider.select((s) => s.hideCreditCardNumber),
    );
    final category = (widget.categoryName ?? '').trim();
    final fields = <_FieldVm>[
      if (category.isNotEmpty)
        const _FieldVm(
          key: 'category',
          label: 'Category',
          value: '',
          isSecret: false,
          icon: TablerIcons.folder,
          iconColor: Color(0xFF5D79C2),
          labelColor: Color(0xFF5D79C2),
        ).copyWith(value: category),
      ..._buildDesktopLikeFields(entry: entry, now: DateTime.now()),
    ];
    final title = entry.title.trim().isEmpty
        ? '(Untitled)'
        : entry.title.trim();
    final hasPasskey = entryHasPasskeyChip(entry);
    final canScanOtp = itemType == VaultItemType.login;
    final website = (entry.url ?? '').trim();
    final canOpenUrl = website.isNotEmpty;
    final sheetHeight = MediaQuery.sizeOf(context).height;
    final safeTop = MediaQuery.paddingOf(context).top;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      top: false,
      bottom: false,
      child: SizedBox(
        height: sheetHeight,
        child: Padding(
          padding: EdgeInsets.only(top: safeTop + 60),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x290A2F3D),
                  blurRadius: 24,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE1EAF0)),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Center(
                              child: Container(
                                width: 38,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD2DCE2),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _TopActionIcon(
                                      icon: TablerIcons.qrcode,
                                      enabled: canScanOtp,
                                      tooltip: 'Scan QR Code',
                                      onTap: _handleTotpAction,
                                    ),
                                    const SizedBox(width: 6),
                                    _TopActionIcon(
                                      icon: TablerIcons.pencil,
                                      tooltip: 'Edit item',
                                      onTap: () {
                                        Navigator.of(context).pop();
                                        showEditItemModal(
                                          context,
                                          entry: entry,
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                    _TopActionIcon(
                                      icon: TablerIcons.external_link,
                                      enabled: canOpenUrl,
                                      tooltip: 'Open URL',
                                      onTap: () async {
                                        var target = website;
                                        if (!target.startsWith('http://') &&
                                            !target.startsWith('https://')) {
                                          target = 'https://$target';
                                        }
                                        final uri = Uri.tryParse(target);
                                        if (uri == null) {
                                          _showCopyToast(
                                            context,
                                            'Invalid URL',
                                          );
                                          return;
                                        }
                                        await launchUrl(
                                          uri,
                                          mode: LaunchMode.externalApplication,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                _HeaderCloseButton(
                                  onTap: () => Navigator.of(context).pop(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _EntryTitleCard(entry: entry, title: title),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 14),
                    children: [
                      if (hasPasskey) ...[
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _PasskeyBanner(
                            onRemove: () {
                              AppSnackBar.info(
                                context,
                                'Passkey remove action will be wired next',
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      for (var i = 0; i < fields.length; i++)
                        Builder(
                          builder: (_) {
                            final field = fields[i];
                            final isRevealed = _revealedFieldKeys.contains(
                              field.key,
                            );
                            final showBottomBorder = i < fields.length - 1;
                            // The TOTP row ticks every second; scope the
                            // rebuild to that single leaf via the notifier so
                            // the rest of the sheet stays still.
                            if (field.key == 'totp' &&
                                field.otpAuthUrl != null) {
                              return _LiveTotpFieldRow(
                                time: _totpTime,
                                otpAuthUrl: field.otpAuthUrl!,
                                showBottomBorder: showBottomBorder,
                                onCopy: () => _copyFieldValue(
                                  context,
                                  field: field,
                                  ref: ref,
                                ),
                              );
                            }
                            return _DesktopLikeFieldRow(
                              icon: field.icon,
                              iconColor: field.iconColor,
                              labelColor: field.labelColor,
                              label: field.label,
                              countdownSeconds: field.countdownSeconds,
                              countdownPeriodSeconds:
                                  field.countdownPeriodSeconds,
                              value: field.isSecret && !isRevealed
                                  ? '••••••••••••'
                                  : (field.isCardNumber && hideCardNumber
                                        ? maskCreditCardNumberForDisplay(
                                            field.value,
                                          )
                                        : field.value),
                              isSecret: field.isSecret,
                              isRevealed: isRevealed,
                              showBottomBorder: showBottomBorder,
                              onToggleReveal: field.isSecret
                                  ? () {
                                      setState(() {
                                        if (isRevealed) {
                                          _revealedFieldKeys.remove(field.key);
                                        } else {
                                          _revealedFieldKeys.add(field.key);
                                        }
                                      });
                                    }
                                  : null,
                              onCopy: () => _copyFieldValue(
                                context,
                                field: field,
                                ref: ref,
                              ),
                            );
                          },
                        ),
                      _EntryStatsSection(entry: entry),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    8,
                    12,
                    8 + (safeBottom * 0.35),
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE1EAF0))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _FooterButton(
                          label: 'Edit item',
                          color: const Color(0xFF0A3B48),
                          onTap: () {
                            Navigator.of(context).pop();
                            showEditItemModal(context, entry: entry);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FooterButton(
                          label: 'Delete',
                          color: const Color(0xFFB42318),
                          onTap: () => _confirmDelete(entry),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(KdbxEntry entry) async {
    final title = entry.title.trim().isEmpty
        ? '(Untitled)'
        : entry.title.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Delete "$title"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB42318),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repo = ref.read(kdbxRepositoryProvider);
      await repo.deleteEntry(entry.uuid);
      publishAndScheduleSave(ref, repo);
      if (!mounted) return;
      _showCopyToast(context, 'Item deleted');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _showCopyToast(context, 'Failed to delete: ${e.toString()}');
    }
  }
}

class _EntryTitleCard extends StatelessWidget {
  const _EntryTitleCard({required this.entry, required this.title});

  final KdbxEntry entry;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: VaultEntryAvatar(entry: entry, size: 42),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    height: 1.08,
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

class _EntryStatsSection extends StatelessWidget {
  const _EntryStatsSection({required this.entry});

  final KdbxEntry entry;

  @override
  Widget build(BuildContext context) {
    final headingStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: const Color(0xFF7D8795),
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.2,
    );
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: const Color(0xFF7D8795),
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    final valueStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: const Color(0xFF344150),
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE1EAF0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stats', style: headingStyle),
          const SizedBox(height: 10),
          _EntryStatRow(
            label: 'Created',
            value: _formatEntryDetailTimestamp(context, entry.createdAt),
            labelStyle: labelStyle,
            valueStyle: valueStyle,
          ),
          const SizedBox(height: 8),
          _EntryStatRow(
            label: 'Updated',
            value: _formatEntryDetailTimestamp(context, entry.updatedAt),
            labelStyle: labelStyle,
            valueStyle: valueStyle,
          ),
          const SizedBox(height: 8),
          _EntryStatRow(
            label: 'Last used',
            value: _formatEntryDetailTimestamp(context, entry.lastUsedAt),
            labelStyle: labelStyle,
            valueStyle: valueStyle,
          ),
        ],
      ),
    );
  }
}

class _EntryStatRow extends StatelessWidget {
  const _EntryStatRow({
    required this.label,
    required this.value,
    required this.labelStyle,
    required this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 72, child: Text(label, style: labelStyle)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(value, textAlign: TextAlign.right, style: valueStyle),
        ),
      ],
    );
  }
}

String _formatEntryDetailTimestamp(BuildContext context, DateTime? value) {
  if (value == null) {
    return '—';
  }

  final localizations = MaterialLocalizations.of(context);
  final local = value.toLocal();
  final date = localizations.formatCompactDate(local);
  final time = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  return '$date $time';
}

class _TopActionIcon extends StatelessWidget {
  const _TopActionIcon({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Tooltip(
        message: tooltip,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: const Color(0xFFF7F9FB),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFD0D8E2)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(icon, size: 19, color: const Color(0xFF5A677A)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderCloseButton extends StatelessWidget {
  const _HeaderCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x180F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(side: BorderSide(color: Color(0xFFD7E2E8))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              Icons.close_rounded,
              color: Color(0xFF5E7180),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _PasskeyBanner extends StatelessWidget {
  const _PasskeyBanner({required this.onRemove});

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF6B5FD3),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                TablerIcons.chevron_down,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              const Text(
                'Passkey Created',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                width: 24,
                height: 24,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.92),
                    width: 1.1,
                  ),
                ),
                child: const Image(
                  image: AssetImage('assets/images/passkey_icon.png'),
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'You can now use Passkey to login to your account seamlessly without using password.',
            style: TextStyle(
              color: Color(0xFFF0EDFF),
              fontSize: 13,
              height: 1.28,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 30,
            child: ElevatedButton(
              onPressed: onRemove,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF4338CA),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                elevation: 0,
              ),
              child: const Text(
                'Remove Passkey',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A TOTP field row that rebuilds only itself when [_totpTime] ticks, keeping
/// the rest of the details sheet static. Mirrors the layout of
/// [_DesktopLikeFieldRow] but derives the code and countdown live.
class _LiveTotpFieldRow extends StatelessWidget {
  const _LiveTotpFieldRow({
    required this.time,
    required this.otpAuthUrl,
    required this.showBottomBorder,
    required this.onCopy,
  });

  final ValueNotifier<DateTime> time;
  final String otpAuthUrl;
  final bool showBottomBorder;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: time,
      builder: (context, now, _) {
        final code = _totpService.generateCode(otpAuthUrl, timestamp: now);
        final countdownSeconds = _totpService.secondsRemaining(
          otpAuthUrl,
          timestamp: now,
        );
        final periodSeconds = _totpPeriodSeconds(otpAuthUrl);
        final displayCode = code != null && code.trim().isNotEmpty
            ? _formatTotp(code)
            : '------';
        final countdownAccent = _totpCountdownColor(countdownSeconds);
        final countdownProgress = periodSeconds > 0
            ? (countdownSeconds / periodSeconds).clamp(0.0, 1.0)
            : null;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: showBottomBorder
                ? const Border(bottom: BorderSide(color: Color(0xFFE1EAF0)))
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.timelapse_rounded,
                          size: 15,
                          color: Color(0xFF3B82F6),
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'OTP',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFF3B82F6),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: countdownAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 12,
                                color: countdownAccent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${countdownSeconds.toString().padLeft(2, '0')}s',
                                style: TextStyle(
                                  color: countdownAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      displayCode,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: countdownAccent,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1.16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: countdownProgress,
                          backgroundColor: const Color(0xFFE8EDF5),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            countdownAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _FieldActionButton(
                icon: Icons.copy_rounded,
                tooltip: 'Copy OTP',
                onPressed: onCopy,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DesktopLikeFieldRow extends StatelessWidget {
  const _DesktopLikeFieldRow({
    required this.icon,
    required this.iconColor,
    required this.labelColor,
    required this.label,
    required this.countdownSeconds,
    required this.countdownPeriodSeconds,
    required this.value,
    required this.isSecret,
    required this.isRevealed,
    required this.onCopy,
    required this.showBottomBorder,
    this.onToggleReveal,
  });

  final IconData icon;
  final Color iconColor;
  final Color? labelColor;
  final String label;
  final int? countdownSeconds;
  final int? countdownPeriodSeconds;
  final String value;
  final bool isSecret;
  final bool isRevealed;
  final VoidCallback onCopy;
  final bool showBottomBorder;
  final VoidCallback? onToggleReveal;

  @override
  Widget build(BuildContext context) {
    final hasCountdown =
        countdownSeconds != null &&
        countdownPeriodSeconds != null &&
        countdownPeriodSeconds! > 0;
    final countdownAccent = hasCountdown
        ? _totpCountdownColor(countdownSeconds!)
        : (labelColor ?? iconColor);
    final countdownProgress = hasCountdown
        ? (countdownSeconds! / countdownPeriodSeconds!).clamp(0.0, 1.0)
        : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: showBottomBorder
            ? const Border(bottom: BorderSide(color: Color(0xFFE1EAF0)))
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 15, color: iconColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: labelColor ?? const Color(0xFF6D63D6),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (hasCountdown)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: countdownAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 12,
                              color: countdownAccent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${countdownSeconds!.toString().padLeft(2, '0')}s',
                              style: TextStyle(
                                color: countdownAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasCountdown
                        ? countdownAccent
                        : const Color(0xFF1F2937),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.16,
                  ),
                ),
                if (hasCountdown) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: countdownProgress,
                        backgroundColor: const Color(0xFFE8EDF5),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          countdownAccent,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSecret) ...[
                _FieldActionButton(
                  icon: isRevealed
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  tooltip: isRevealed ? 'Hide $label' : 'Show $label',
                  onPressed: onToggleReveal,
                ),
                const SizedBox(width: 8),
              ],
              _FieldActionButton(
                icon: Icons.copy_rounded,
                tooltip: 'Copy $label',
                onPressed: onCopy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FieldActionButton extends StatelessWidget {
  const _FieldActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFFF3F7FA),
          foregroundColor: const Color(0xFF637483),
          disabledBackgroundColor: const Color(0xFFE9EEF3),
          disabledForegroundColor: const Color(0xFF9AA7B4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE1EAF0)),
          ),
        ),
        icon: Icon(icon, size: 19),
        tooltip: tooltip,
      ),
    );
  }
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          elevation: 0,
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
    );
  }
}

class _FieldVm {
  const _FieldVm({
    required this.key,
    required this.label,
    required this.value,
    required this.isSecret,
    required this.icon,
    required this.iconColor,
    required this.labelColor,
    this.countdownSeconds,
    this.countdownPeriodSeconds,
    this.otpAuthUrl,
    this.isCardNumber = false,
  });

  final String key;
  final String label;
  final String value;
  final bool isSecret;
  final IconData icon;
  final Color iconColor;
  final Color? labelColor;
  final int? countdownSeconds;
  final int? countdownPeriodSeconds;
  final String? otpAuthUrl;
  final bool isCardNumber;
}

List<_FieldVm> _buildDesktopLikeFields({
  required KdbxEntry entry,
  required DateTime now,
}) {
  final itemType = classifyVaultItemType(entry);
  final normalizedStandardKeys = AppKdbxFieldKeys.standardKeys
      .map((key) => key.toLowerCase())
      .toSet();
  final sourceFields = entry.fields
      .where((field) => field.value.trim().isNotEmpty)
      .toList(growable: false);
  final consumedIndexes = <int>{};
  final result = <_FieldVm>[];

  void consumeMatchingKeys(Iterable<String> keys) {
    final normalizedKeys = keys.map((key) => key.toLowerCase()).toSet();
    for (var index = 0; index < sourceFields.length; index++) {
      if (normalizedKeys.contains(sourceFields[index].key.toLowerCase())) {
        consumedIndexes.add(index);
      }
    }
  }

  void addField({
    required String label,
    required String value,
    String? sourceKey,
    bool isSecret = false,
    bool isCardNumber = false,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    if (_shouldHideFromDetailFields(label: label, sourceKey: sourceKey)) return;
    final effectiveIsSecret =
        isSecret ||
        AppKdbxFieldKeys.isProtectedKey(sourceKey ?? label) ||
        AppKdbxFieldKeys.isProtectedKey(label);
    final visual = _fieldVisualForDesktop(
      sourceKey: sourceKey ?? label,
      label: label,
      itemType: itemType,
      isSecret: effectiveIsSecret,
    );
    result.add(
      _FieldVm(
        key: (sourceKey ?? label).toLowerCase(),
        label: label,
        value: trimmed,
        isSecret: effectiveIsSecret,
        icon: visual.icon,
        iconColor: visual.iconColor,
        labelColor: visual.labelColor,
        isCardNumber: isCardNumber,
      ),
    );
  }

  void addMappedField({
    required String label,
    required List<String> matches,
    bool isSecret = false,
    bool isCardNumber = false,
    String Function(String)? valueTransformer,
  }) {
    for (var index = 0; index < sourceFields.length; index++) {
      if (consumedIndexes.contains(index)) continue;
      final field = sourceFields[index];
      final normalizedKey = field.key.toLowerCase();
      final normalizedValue = field.value.toLowerCase();
      if (normalizedStandardKeys.contains(normalizedKey)) continue;
      final isMatch = matches.any(
        (match) =>
            normalizedKey.contains(match) || normalizedValue.contains(match),
      );
      if (!isMatch) continue;
      consumedIndexes.add(index);
      addField(
        label: label,
        value: valueTransformer != null
            ? valueTransformer(field.value)
            : field.value,
        sourceKey: field.key,
        isSecret: isCardNumber ? false : (isSecret || field.isProtected),
        isCardNumber: isCardNumber,
      );
      return;
    }
  }

  void addStandardWebsite() {
    final website = entry.url?.trim() ?? '';
    if (website.isEmpty) return;
    consumeMatchingKeys(const <String>[AppKdbxFieldKeys.url]);
    addField(label: 'Website', value: website, sourceKey: AppKdbxFieldKeys.url);
  }

  void addStandardUsername({String label = 'Username'}) {
    final username = entry.username?.trim() ?? '';
    if (username.isEmpty) return;
    consumeMatchingKeys(const <String>[AppKdbxFieldKeys.userName]);
    addField(
      label: label,
      value: username,
      sourceKey: AppKdbxFieldKeys.userName,
    );
  }

  void addStandardPassword({String label = 'Password'}) {
    final password =
        entry.fieldByKey(AppKdbxFieldKeys.password)?.value.trim() ?? '';
    if (password.isEmpty) return;
    consumeMatchingKeys(const <String>[AppKdbxFieldKeys.password]);
    addField(
      label: label,
      value: password,
      sourceKey: AppKdbxFieldKeys.password,
      isSecret: true,
    );
  }

  switch (itemType) {
    case VaultItemType.creditCard:
      addMappedField(
        label: 'Cardholder',
        matches: const <String>[
          'cardholder',
          'name on card',
          'cardholder name',
          'card holder',
        ],
      );
      if (result.isEmpty && (entry.username?.trim().isNotEmpty ?? false)) {
        addStandardUsername(label: 'Cardholder');
      }
      addMappedField(
        label: 'Card Number',
        matches: const <String>[
          'card number',
          'card no',
          'credit card number',
          'cc number',
          'pan',
        ],
        isCardNumber: true,
      );
      addMappedField(
        label: 'Expiry Date',
        matches: const <String>[
          'expiry',
          'expiration',
          'exp date',
          'valid thru',
          'valid through',
        ],
        valueTransformer: _formatCardDateDesktop,
      );
      addMappedField(
        label: 'Valid From',
        matches: const <String>['valid from'],
        valueTransformer: _formatCardDateDesktop,
      );
      addMappedField(
        label: 'CVC',
        matches: const <String>['cvc', 'cvv', 'cvn', 'security code'],
        isSecret: true,
      );
      addMappedField(
        label: 'PIN',
        matches: const <String>['pin'],
        isSecret: true,
      );
      addStandardWebsite();
      break;
    case VaultItemType.bankAccount:
      addMappedField(
        label: 'Account Holder',
        matches: const <String>['account holder', 'holder name', 'beneficiary'],
      );
      addMappedField(
        label: 'Bank Name',
        matches: const <String>['bank name', 'bank'],
      );
      addMappedField(
        label: 'Account Number',
        matches: const <String>['account number', 'acct number', 'iban'],
      );
      addMappedField(
        label: 'Routing Number',
        matches: const <String>['routing', 'sort code', 'transit'],
      );
      addMappedField(
        label: 'SWIFT / BIC',
        matches: const <String>['swift', 'bic'],
      );
      addStandardWebsite();
      break;
    case VaultItemType.identity:
      addMappedField(
        label: 'Full Name',
        matches: const <String>['full name', 'name'],
      );
      addMappedField(
        label: 'Email',
        matches: const <String>['email', 'e-mail'],
      );
      addMappedField(
        label: 'Phone',
        matches: const <String>['phone', 'mobile', 'telephone'],
      );
      addMappedField(
        label: 'Address',
        matches: const <String>['address', 'street', 'city', 'postal'],
      );
      addMappedField(
        label: 'ID Number',
        matches: const <String>[
          'id number',
          'identity number',
          'driver license',
          'driver licence',
        ],
      );
      break;
    case VaultItemType.sshKey:
      addMappedField(
        label: 'Private Key',
        matches: const <String>['private key', 'ssh key', 'pem', 'openssh'],
        isSecret: true,
      );
      addMappedField(
        label: 'Public Key',
        matches: const <String>['public key', 'authorized key'],
      );
      addMappedField(
        label: 'Passphrase',
        matches: const <String>['passphrase'],
        isSecret: true,
      );
      addMappedField(
        label: 'Fingerprint',
        matches: const <String>['fingerprint'],
      );
      break;
    case VaultItemType.document:
      addStandardWebsite();
      addMappedField(
        label: 'Document ID',
        matches: const <String>['document id', 'serial number', 'reference'],
      );
      break;
    case VaultItemType.apiCredential:
      addMappedField(
        label: 'Client ID',
        matches: const <String>['client id', 'app id'],
      );
      addMappedField(
        label: 'Client Secret',
        matches: const <String>['client secret'],
        isSecret: true,
      );
      addMappedField(
        label: 'Access Token',
        matches: const <String>['access token', 'bearer token'],
        isSecret: true,
      );
      addMappedField(
        label: 'API Key',
        matches: const <String>['api key', 'secret key'],
        isSecret: true,
      );
      addStandardWebsite();
      break;
    case VaultItemType.server:
      addMappedField(
        label: 'Host',
        matches: const <String>['hostname', 'host', 'ip address'],
      );
      addMappedField(label: 'Port', matches: const <String>['port']);
      addStandardUsername();
      addStandardPassword();
      addMappedField(
        label: 'Private Key',
        matches: const <String>['private key'],
        isSecret: true,
      );
      addMappedField(
        label: 'Public Key',
        matches: const <String>['public key'],
      );
      addStandardWebsite();
      break;
    case VaultItemType.wifiPassword:
      addMappedField(
        label: 'SSID',
        matches: const <String>['ssid', 'network name'],
      );
      addMappedField(
        label: 'Security',
        matches: const <String>['security', 'wireless type'],
      );
      addStandardPassword();
      break;
    case VaultItemType.passport:
      addMappedField(
        label: 'Passport Number',
        matches: const <String>['passport number', 'passport no'],
      );
      addMappedField(
        label: 'Full Name',
        matches: const <String>['full name', 'name'],
      );
      addMappedField(
        label: 'Nationality',
        matches: const <String>['nationality'],
      );
      addMappedField(
        label: 'Expiry Date',
        matches: const <String>['expiry', 'expiration', 'exp date'],
      );
      break;
    case VaultItemType.secureNote:
      addStandardWebsite();
      break;
    case VaultItemType.login:
      addStandardWebsite();
      addStandardUsername();
      addStandardPassword();
      break;
  }

  if (entryHasTotp(entry)) {
    final code = _totpService.generateCode(entry.otpAuthUrl, timestamp: now);
    final countdownSeconds = _totpService.secondsRemaining(
      entry.otpAuthUrl,
      timestamp: now,
    );
    final countdownPeriodSeconds = _totpPeriodSeconds(entry.otpAuthUrl);
    if (code != null && code.trim().isNotEmpty) {
      result.add(
        const _FieldVm(
          key: 'totp',
          label: 'OTP',
          value: '',
          isSecret: false,
          icon: Icons.timelapse_rounded,
          iconColor: Color(0xFF3B82F6),
          labelColor: Color(0xFF3B82F6),
        ).copyWith(
          value: _formatTotp(code),
          countdownSeconds: countdownSeconds,
          countdownPeriodSeconds: countdownPeriodSeconds,
          otpAuthUrl: entry.otpAuthUrl,
        ),
      );
    }
  }

  for (var index = 0; index < sourceFields.length; index++) {
    if (consumedIndexes.contains(index)) continue;
    final field = sourceFields[index];
    if (normalizedStandardKeys.contains(field.key.toLowerCase())) continue;
    addField(
      label: _displayLabelForFieldKeyDesktop(field.key),
      value: field.value,
      sourceKey: field.key,
      isSecret:
          field.isProtected ||
          field.key.toLowerCase() == AppKdbxFieldKeys.password.toLowerCase(),
    );
  }

  final notes = (entry.notes ?? '').trim();
  if (notes.isNotEmpty) {
    addField(label: 'Notes', value: notes, sourceKey: AppKdbxFieldKeys.notes);
  }

  return result;
}

extension on _FieldVm {
  _FieldVm copyWith({
    String? value,
    int? countdownSeconds,
    int? countdownPeriodSeconds,
    String? otpAuthUrl,
  }) {
    return _FieldVm(
      key: key,
      label: label,
      value: value ?? this.value,
      isSecret: isSecret,
      icon: icon,
      iconColor: iconColor,
      labelColor: labelColor,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      countdownPeriodSeconds:
          countdownPeriodSeconds ?? this.countdownPeriodSeconds,
      otpAuthUrl: otpAuthUrl ?? this.otpAuthUrl,
    );
  }
}

int _totpPeriodSeconds(String? otpAuthUrl) {
  final uri = Uri.tryParse(otpAuthUrl ?? '');
  final parsed = int.tryParse(uri?.queryParameters['period'] ?? '');
  if (parsed == null || parsed <= 0) {
    return 30;
  }
  return parsed;
}

Color _totpCountdownColor(int secondsRemaining) {
  if (secondsRemaining <= 9) {
    return const Color(0xFFDC2626);
  }
  if (secondsRemaining <= 15) {
    return const Color(0xFFF59E0B);
  }
  return const Color(0xFF16A34A);
}

bool _shouldHideFromDetailFields({required String label, String? sourceKey}) {
  final normalizedLabel = label.toLowerCase().trim();
  final normalizedSourceKey = sourceKey?.toLowerCase().trim() ?? '';
  if (normalizedSourceKey == 'lp_social_provider' ||
      normalizedSourceKey == 'lp_social_label') {
    return true;
  }

  final combined = '$normalizedSourceKey $normalizedLabel';
  final isPasskeyInternalField =
      normalizedSourceKey.contains('kpex_passkey_') ||
      combined.contains('kpex passkey') ||
      (combined.contains('passkey') &&
          (combined.contains('credential id') ||
              combined.contains('relying party') ||
              combined.contains('user handle') ||
              combined.contains('private key') ||
              combined.contains('username')));

  return normalizedLabel == 'otp' ||
      normalizedSourceKey == AppKdbxFieldKeys.itemIconPresetId.toLowerCase() ||
      AppKdbxFieldKeys.isAttachmentMetaKey(sourceKey ?? '') ||
      normalizedLabel == 'totp' ||
      normalizedSourceKey == 'otp' ||
      normalizedSourceKey == 'totp' ||
      combined.contains('otp auth') ||
      combined.contains('otpauth') ||
      combined.contains('time otp') ||
      combined.contains('time otp secret') ||
      combined.contains('totp secret') ||
      combined.contains('base32') ||
      isPasskeyInternalField;
}

String _displayLabelForFieldKeyDesktop(String key) {
  const directLabels = <String, String>{
    'url': 'Website',
    'username': 'Username',
    'user name': 'Username',
    'otp auth': 'OTP',
    'otpauth': 'OTP',
    'cvv': 'CVV',
    'cvc': 'CVC',
    'ssid': 'SSID',
    'iban': 'IBAN',
  };

  final spaced = key
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (spaced.isEmpty) return key;

  final normalized = spaced.toLowerCase();
  if (directLabels.containsKey(normalized)) return directLabels[normalized]!;

  return spaced
      .split(' ')
      .map((part) {
        final upper = part.toUpperCase();
        if (upper.length <= 4 && RegExp(r'^[A-Z0-9]+$').hasMatch(upper)) {
          return upper;
        }
        return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
      })
      .join(' ');
}

({IconData icon, Color iconColor, Color? labelColor}) _fieldVisualForDesktop({
  required String sourceKey,
  required String label,
  required VaultItemType itemType,
  required bool isSecret,
}) {
  final normalized = '${sourceKey.toLowerCase()} ${label.toLowerCase()}';

  if (normalized.contains('url') || normalized.contains('website')) {
    return (
      icon: TablerIcons.world_www,
      iconColor: const Color(0xFF635BDB),
      labelColor: const Color(0xFF635BDB),
    );
  }
  if (normalized.contains('email')) {
    return (
      icon: Icons.alternate_email_rounded,
      iconColor: const Color(0xFF5C7CFA),
      labelColor: null,
    );
  }
  if (normalized.contains('username') ||
      normalized.contains('cardholder') ||
      normalized.contains('full name') ||
      normalized.contains('account holder') ||
      normalized.contains('holder')) {
    return (
      icon: TablerIcons.user,
      iconColor: const Color(0xFF5C7CFA),
      labelColor: null,
    );
  }
  if (normalized.contains('card') ||
      normalized.contains('cvv') ||
      normalized.contains('cvc') ||
      itemType == VaultItemType.creditCard) {
    return (
      icon: TablerIcons.credit_card,
      iconColor: const Color(0xFF4A9EE8),
      labelColor: null,
    );
  }
  if (normalized.contains('expiry') ||
      normalized.contains('expiration') ||
      normalized.contains('date')) {
    return (
      icon: Icons.calendar_today_outlined,
      iconColor: const Color(0xFF2DA8B6),
      labelColor: null,
    );
  }
  if (normalized.contains('bank') ||
      normalized.contains('routing') ||
      normalized.contains('iban') ||
      normalized.contains('swift') ||
      normalized.contains('bic')) {
    return (
      icon: TablerIcons.building_bank,
      iconColor: const Color(0xFF1F9A76),
      labelColor: null,
    );
  }
  if (normalized.contains('private key') ||
      normalized.contains('public key') ||
      normalized.contains('fingerprint') ||
      normalized.contains('ssh')) {
    return (
      icon: TablerIcons.key,
      iconColor: const Color(0xFF1D6570),
      labelColor: null,
    );
  }
  if (normalized.contains('phone')) {
    return (
      icon: Icons.phone_outlined,
      iconColor: const Color(0xFF2DA8B6),
      labelColor: null,
    );
  }
  if (normalized.contains('address')) {
    return (
      icon: Icons.location_on_outlined,
      iconColor: const Color(0xFF56B676),
      labelColor: null,
    );
  }
  if (isSecret) {
    return (
      icon: TablerIcons.key,
      iconColor: const Color(0xFFC08A1A),
      labelColor: null,
    );
  }

  return (
    icon: Icons.label_outline_rounded,
    iconColor: const Color(0xFF8A97AC),
    labelColor: null,
  );
}

String _formatCardDateDesktop(String value) {
  final trimmed = value.trim();
  final m1 = RegExp(r'^(\d{4})[/\-](\d{1,2})$').firstMatch(trimmed);
  if (m1 != null) return '${m1.group(2)!.padLeft(2, '0')} / ${m1.group(1)}';
  final m2 = RegExp(r'^(\d{1,2})[/\-](\d{4})$').firstMatch(trimmed);
  if (m2 != null) return '${m2.group(1)!.padLeft(2, '0')} / ${m2.group(2)}';
  return value;
}

Timer? _clipboardClearTimer;

Future<void> _copyFieldValue(
  BuildContext context, {
  required _FieldVm field,
  required WidgetRef ref,
}) async {
  final otpAuthUrl = field.otpAuthUrl;
  if (otpAuthUrl != null && otpAuthUrl.trim().isNotEmpty) {
    await _copyTotpValue(context, otpAuthUrl: otpAuthUrl, ref: ref);
    return;
  }

  await _copyValue(context, value: field.value, label: field.label, ref: ref);
}

Future<void> _copyTotpValue(
  BuildContext context, {
  required String otpAuthUrl,
  required WidgetRef ref,
}) async {
  final secondsRemaining = _totpService.secondsRemaining(otpAuthUrl);
  if (secondsRemaining <= 5) {
    _showCopyToast(context, 'Refreshing OTP...');
    await Future<void>.delayed(
      Duration(seconds: secondsRemaining) + const Duration(milliseconds: 250),
    );
    if (!context.mounted) return;
  }

  final code = _totpService.generateCode(otpAuthUrl);
  if (code == null || code.trim().isEmpty) {
    if (context.mounted) {
      _showCopyToast(context, 'Unable to copy OTP');
    }
    return;
  }

  await _copyValue(
    context,
    value: code.replaceAll(RegExp(r'\s+'), ''),
    label: 'OTP',
    ref: ref,
  );
}

Future<void> _copyValue(
  BuildContext context, {
  required String value,
  required String label,
  WidgetRef? ref,
}) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  _showCopyToast(context, '$label copied');

  // Arm clipboard-clear timer from security settings.
  _clipboardClearTimer?.cancel();
  final seconds = ref
      ?.read(vaultSecuritySettingsProvider)
      .clipboardClear
      .seconds;
  if (seconds != null) {
    _clipboardClearTimer = Timer(Duration(seconds: seconds), () {
      Clipboard.setData(const ClipboardData(text: ''));
    });
  }
}

String _formatTotp(String raw) {
  final digits = raw.replaceAll(RegExp(r'\s+'), '');
  if (digits.length == 6) {
    return '${digits.substring(0, 3)} ${digits.substring(3)}';
  }
  return raw;
}

void _showCopyToast(BuildContext context, String message) {
  _copyToastTimer?.cancel();
  _copyToastEntry?.remove();
  _copyToastEntry = null;

  final overlay = Overlay.of(context, rootOverlay: true);
  final media = MediaQuery.of(context);
  final bottomOffset = media.padding.bottom + media.viewInsets.bottom + 110;

  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 16,
      right: 16,
      bottom: bottomOffset,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  _copyToastEntry = entry;
  _copyToastTimer = Timer(const Duration(milliseconds: 1300), () {
    _copyToastEntry?.remove();
    _copyToastEntry = null;
    _copyToastTimer = null;
  });
}
