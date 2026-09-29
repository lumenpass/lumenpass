import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:path/path.dart' as p;

import '../../../core/models/database_record.dart';
import '../../../core/services/backup_service.dart';

// ── Palette (mirrors unlock_screen) ─────────────────────────────────────────
const Color _kCanvas = Color(0xFFF6F8FB);
const Color _kBorderSoft = Color(0xFFE1E7F0);
const Color _kBorderRow = Color(0xFFE6EAF0);
const Color _kTitle = Color(0xFF22314A);
const Color _kLabel = Color(0xFF73839D);
const Color _kIcon = Color(0xFF8A97AC);
const Color _kActionDark = Color(0xFF0A3B48);
const Color _kDanger = Color(0xFFDC2626);

TextStyle _uText(
  double size,
  Color color, {
  FontWeight fontWeight = FontWeight.w400,
  double? letterSpacing,
  double? height,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: fontWeight,
    fontFamily: 'Ubuntu Sans',
    letterSpacing: letterSpacing,
    height: height,
  );
}

/// Modal listing local backups for a locked (or corrupted) database so the
/// user can restore without unlocking first.
///
/// Returns `true` when a restore completed successfully so the caller can
/// refresh selection / prompt unlock.
class RestoreBackupsModal extends ConsumerStatefulWidget {
  const RestoreBackupsModal({
    super.key,
    required this.record,
    required this.targetVaultPath,
  });

  final DatabaseRecord record;
  final String targetVaultPath;

  @override
  ConsumerState<RestoreBackupsModal> createState() =>
      _RestoreBackupsModalState();
}

class _RestoreBackupsModalState extends ConsumerState<RestoreBackupsModal> {
  static const int _pageSize = 10;

  late Future<List<LocalBackupInfo>> _backupsFuture;
  final ScrollController _verticalController = ScrollController();
  bool _busy = false;

  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _backupsFuture = _loadBackups();
  }

  @override
  void dispose() {
    _verticalController.dispose();
    super.dispose();
  }

  Future<List<LocalBackupInfo>> _loadBackups() {
    return BackupService.instance.listLocalBackups(
      vaultPath: widget.targetVaultPath,
    );
  }

  void _reload({bool resetPage = true}) {
    setState(() {
      if (resetPage) _currentPage = 1;
      _backupsFuture = _loadBackups();
    });
  }

  int _totalPages(int total) {
    if (total <= 0) return 1;
    return (total / _pageSize).ceil();
  }

  int _clampPage(int page, int total) {
    final pages = _totalPages(total);
    if (page < 1) return 1;
    if (page > pages) return pages;
    return page;
  }

  List<LocalBackupInfo> _pageSlice(List<LocalBackupInfo> all) {
    if (all.isEmpty) return const <LocalBackupInfo>[];
    final page = _clampPage(_currentPage, all.length);
    final from = (page - 1) * _pageSize;
    final to = (from + _pageSize).clamp(0, all.length);
    return all.sublist(from, to);
  }

  void _goToPage(int page, int total) {
    final clamped = _clampPage(page, total);
    if (clamped == _currentPage) return;
    setState(() => _currentPage = clamped);
    if (_verticalController.hasClients) {
      _verticalController.jumpTo(0);
    }
  }

  Widget _buildBackupsList(List<LocalBackupInfo> backups) {
    final paged = _pageSlice(backups);
    if (paged.isEmpty) return const SizedBox.shrink();
    return Scrollbar(
      controller: _verticalController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _verticalController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        itemCount: paged.length,
        itemBuilder: (context, index) {
          final backup = paged[index];
          final counter =
              ((_clampPage(_currentPage, backups.length) - 1) * _pageSize) +
                  index +
                  1;
          return _BackupRow(
            counter: counter,
            backup: backup,
            createdAt: _formatCreatedAt(context, backup.createdAt),
            size: _formatBytes(backup.sizeBytes),
            enabled: !_busy,
            onRestore: () => _restoreBackup(backup),
            onDownload: () => _downloadBackup(backup),
            onDelete: () => _deleteBackup(backup),
          );
        },
      ),
    );
  }

  static String _formatBytes(int bytes) {
    const units = <String>['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  String _formatCreatedAt(BuildContext context, DateTime createdAt) {
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatShortDate(createdAt);
    final time = TimeOfDay.fromDateTime(createdAt).format(context);
    return '$date · $time';
  }

  Future<void> _downloadBackup(LocalBackupInfo backup) async {
    try {
      final source = File(backup.path);
      if (!await source.exists()) {
        _showSnack('Backup file no longer exists on disk.', danger: true);
        _reload();
        return;
      }

      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Download backup',
        fileName: backup.fileName,
        lockParentWindow: true,
        type: Platform.isMacOS ? FileType.any : FileType.custom,
        allowedExtensions: Platform.isMacOS ? null : <String>['kdbx'],
      );
      if (destination == null || destination.isEmpty) return;

      final normalized = destination.toLowerCase().endsWith('.kdbx')
          ? destination
          : '$destination.kdbx';
      if (p.normalize(normalized) == p.normalize(backup.path)) {
        _showSnack(
          'Pick a different location — that is the source backup file.',
          danger: true,
        );
        return;
      }

      await source.copy(normalized);
      if (!mounted) return;
      _showSnack('Downloaded ${p.basename(normalized)}');
    } on MissingPluginException {
      _showSnack('File picker is unavailable.', danger: true);
    } catch (e) {
      _showSnack('Could not download backup: $e', danger: true);
    }
  }

  Future<void> _deleteBackup(LocalBackupInfo backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ConfirmDialog(
        title: 'Delete backup?',
        message:
            'Delete "${backup.fileName}"? This permanently removes the backup file from disk.',
        confirmLabel: 'Delete',
        isDestructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final file = File(backup.path);
      if (await file.exists()) {
        await file.delete();
      }
      if (!mounted) return;
      _reload(resetPage: false);
      _showSnack('Deleted ${backup.fileName}');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not delete backup: $e', danger: true);
    }
  }

  Future<void> _restoreBackup(LocalBackupInfo backup) async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RestoreConfirmDialog(
        backup: backup,
        vaultName: widget.record.nickname,
      ),
    );
    if (confirmed != true || !mounted) return;

    final structuralIssue = await BackupService.instance.validateBackupFile(
      backupPath: backup.path,
      targetVaultPath: widget.targetVaultPath,
    );
    if (!mounted) return;
    if (structuralIssue != null) {
      _showSnack(structuralIssue, danger: true);
      return;
    }

    setState(() => _busy = true);
    ref.read(backupRestoreProgressProvider.notifier).state = null;

    bool progressOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => const _RestoreProgressDialog(),
      ).whenComplete(() => progressOpen = false),
    );

    Object? failure;
    try {
      await BackupService.instance.restoreLocalBackup(
        backup,
        targetVaultPath: widget.targetVaultPath,
      );
    } catch (e, stack) {
      failure = e;
      debugPrint('[UnlockRestore] failed: $e\n$stack');
    }

    if (mounted && progressOpen) {
      // Keep the success state visible briefly before dismissing.
      if (failure == null) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
      }
      if (mounted && progressOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!mounted) return;
    setState(() => _busy = false);

    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }

    _showSnack(
      'Restore failed: ${_formatRestoreError(failure)}',
      danger: true,
    );
  }

  String _formatRestoreError(Object error) {
    final raw = error.toString();
    if (raw.contains('PathAccessException') ||
        raw.contains('Permission denied')) {
      return 'Insufficient permissions to read or write the vault file.';
    }
    if (raw.contains('not in KDBX format') || raw.contains('bad magic')) {
      return 'The selected file is not a valid KDBX backup.';
    }
    if (raw.contains('FileSystemException')) {
      return 'File system error — verify the backup is on a writable disk and retry.';
    }
    if (raw.contains('truncated') || raw.contains('corrupt')) {
      return 'Backup file is corrupt or incompatible with this app version.';
    }
    if (raw.contains('onto itself')) {
      return 'Cannot restore the live vault onto itself.';
    }
    if (raw.contains('missing') || raw.contains('no longer exists')) {
      return 'The vault file or backup could not be found on disk.';
    }
    return raw.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');
  }

  Future<void> _openBackupFolder() async {
    try {
      await BackupService.instance
          .openLocalBackupFolder(vaultPath: widget.targetVaultPath);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not open backup folder: $e', danger: true);
    }
  }

  void _showSnack(String message, {bool danger = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: _uText(12, Colors.white),
        ),
        backgroundColor: danger ? _kDanger : _kActionDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 720,
          maxHeight: 560,
          minWidth: 560,
          minHeight: 360,
        ),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          elevation: 18,
          shadowColor: const Color(0x33000000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHeader(),
              const Divider(height: 1, color: _kBorderSoft),
              Expanded(child: _buildBody()),
              const Divider(height: 1, color: _kBorderSoft),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(
              TablerIcons.history,
              size: 20,
              color: _kTitle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Restore from backup',
                  style: _uText(16, _kTitle, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Replace "${widget.record.nickname}" with a previous snapshot.',
                  style: _uText(12, _kLabel, height: 1.35),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            icon: const Icon(TablerIcons.x, size: 18, color: _kIcon),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return FutureBuilder<List<LocalBackupInfo>>(
      future: _backupsFuture,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final backups = snapshot.data ?? const <LocalBackupInfo>[];

        if (isLoading) {
          return const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(_kActionDark),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(TablerIcons.alert_circle,
                      size: 32, color: _kDanger),
                  const SizedBox(height: 12),
                  Text(
                    'Could not load backups',
                    style: _uText(14, _kTitle, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: _uText(12, _kLabel, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _reload,
                    icon: const Icon(TablerIcons.refresh, size: 16),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        if (backups.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _kCanvas,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      TablerIcons.database_off,
                      size: 28,
                      color: _kIcon,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'No backups available',
                    style: _uText(14, _kTitle, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'LumenPass has not created any local backups for this '
                    'database yet. Enable backup in Settings after unlocking '
                    'to protect this vault.',
                    textAlign: TextAlign.center,
                    style: _uText(12, _kLabel, height: 1.45),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
              child: Row(
                children: <Widget>[
                  Text(
                    '${backups.length} backup${backups.length == 1 ? '' : 's'} · ${_formatBytes(backups.fold(0, (sum, b) => sum + b.sizeBytes))} · newest first',
                    style: _uText(12, _kLabel, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Tooltip(
                    message: 'Open Folder',
                    child: IconButton(
                      onPressed: _busy ? null : _openBackupFolder,
                      icon: const Icon(TablerIcons.folder_open, size: 16),
                      color: _kActionDark,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  Tooltip(
                    message: 'Refresh',
                    child: IconButton(
                      onPressed: _busy ? null : _reload,
                      icon: const Icon(TablerIcons.refresh, size: 16),
                      color: _kActionDark,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _TableHeader(),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: _buildBackupsList(backups),
            ),
            if (backups.isNotEmpty)
              _PaginationBar(
                page: _clampPage(_currentPage, backups.length),
                totalPages: _totalPages(backups.length),
                pageSize: _pageSize,
                total: backups.length,
                enabled: !_busy,
                onChanged: (page) => _goToPage(page, backups.length),
              ),
          ],
        );
      },
    );
  }

  Widget _buildFooter() {
    return Container(
      color: _kCanvas,
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Restoring overwrites the current database file on disk. '
              'You will unlock with the backup’s credentials after.',
              style: _uText(11, _kLabel, height: 1.4),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text(
              'Close',
              style: _uText(12, _kTitle, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pagination ───────────────────────────────────────────────────────────────

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.page,
    required this.totalPages,
    required this.pageSize,
    required this.total,
    required this.enabled,
    required this.onChanged,
  });

  final int page;
  final int totalPages;
  final int pageSize;
  final int total;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final from = total == 0 ? 0 : ((page - 1) * pageSize) + 1;
    final to = (page * pageSize).clamp(0, total);
    final hasMultiple = totalPages > 1;

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kBorderSoft)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: <Widget>[
          Text(
            total == 0 ? 'No items' : 'Showing $from–$to of $total',
            style: _uText(11, _kLabel, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          _PagerButton(
            icon: TablerIcons.chevron_left,
            tooltip: 'Previous page',
            onTap: !enabled || page <= 1 ? null : () => onChanged(page - 1),
          ),
          const SizedBox(width: 6),
          ..._buildPageButtons(
              hasMultiple, page, totalPages, enabled, onChanged),
          const SizedBox(width: 6),
          _PagerButton(
            icon: TablerIcons.chevron_right,
            tooltip: 'Next page',
            onTap: !enabled || page >= totalPages
                ? null
                : () => onChanged(page + 1),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPageButtons(
    bool hasMultiple,
    int page,
    int totalPages,
    bool enabled,
    ValueChanged<int> onChanged,
  ) {
    if (!hasMultiple) {
      return <Widget>[
        _PageChip(
          label: '1',
          active: true,
          enabled: false,
          onTap: null,
        ),
      ];
    }

    final pages = _visiblePages(page, totalPages);
    final widgets = <Widget>[];
    var last = 0;
    for (final p in pages) {
      if (p - last > 1) {
        widgets.add(const _PageEllipsis());
      }
      widgets.add(
        _PageChip(
          label: '$p',
          active: p == page,
          enabled: enabled,
          onTap: () => onChanged(p),
        ),
      );
      last = p;
    }
    return widgets;
  }

  /// Returns up to 5 visible page numbers centered around the active page.
  static List<int> _visiblePages(int page, int totalPages) {
    const window = 5;
    if (totalPages <= window) {
      return List<int>.generate(totalPages, (i) => i + 1);
    }
    var start = page - 2;
    var end = page + 2;
    if (start < 1) {
      end += 1 - start;
      start = 1;
    }
    if (end > totalPages) {
      start -= end - totalPages;
      end = totalPages;
    }
    start = start.clamp(1, totalPages);
    end = end.clamp(1, totalPages);
    return List<int>.generate(end - start + 1, (i) => start + i);
  }
}

class _PagerButton extends StatelessWidget {
  const _PagerButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: Material(
        color: active ? _kCanvas : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 28,
            child: Icon(
              icon,
              size: 14,
              color: active ? _kTitle : _kIcon.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageChip extends StatelessWidget {
  const _PageChip({
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active ? _kActionDark : _kCanvas;
    final fg = active ? Colors.white : _kTitle;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 30,
            height: 28,
            child: Center(
              child: Text(
                label,
                style: _uText(
                  11,
                  enabled ? fg : _kIcon.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageEllipsis extends StatelessWidget {
  const _PageEllipsis();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 28,
      child: Center(
        child: Text(
          '…',
          style: _uText(12, _kLabel, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ── Table pieces ────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _kCanvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorderSoft),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 36,
            child: Text(
              '#',
              style: _uText(11, _kLabel, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              'Name',
              style: _uText(11, _kLabel, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            width: 150,
            child: Text(
              'Created',
              style: _uText(11, _kLabel, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              'Size',
              style: _uText(11, _kLabel, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            width: 168,
            child: Text(
              'Actions',
              textAlign: TextAlign.right,
              style: _uText(11, _kLabel, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupRow extends StatefulWidget {
  const _BackupRow({
    required this.counter,
    required this.backup,
    required this.createdAt,
    required this.size,
    required this.enabled,
    required this.onRestore,
    required this.onDownload,
    required this.onDelete,
  });

  final int counter;
  final LocalBackupInfo backup;
  final String createdAt;
  final String size;
  final bool enabled;
  final VoidCallback onRestore;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  State<_BackupRow> createState() => _BackupRowState();
}

class _BackupRowState extends State<_BackupRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _hovered ? const Color(0xFFF8FAFC) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hovered ? const Color(0xFFD4DDEA) : _kBorderRow,
          ),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 36,
              child: Text(
                '${widget.counter}',
                style: _uText(11, _kLabel, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              flex: 5,
              child: Row(
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      TablerIcons.database,
                      size: 15,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.backup.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _uText(
                        10,
                        _kTitle,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 150,
              child: Text(
                widget.createdAt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _uText(11, _kLabel, height: 1.3),
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(
                widget.size,
                style: _uText(11, _kTitle, fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              width: 168,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  _ActionChip(
                    tooltip: 'Restore',
                    icon: TablerIcons.history,
                    color: _kActionDark,
                    onTap: widget.enabled ? widget.onRestore : null,
                  ),
                  const SizedBox(width: 6),
                  _ActionChip(
                    tooltip: 'Download',
                    icon: TablerIcons.download,
                    color: const Color(0xFF4F46E5),
                    onTap: widget.enabled ? widget.onDownload : null,
                  ),
                  const SizedBox(width: 6),
                  _ActionChip(
                    tooltip: 'Delete',
                    icon: TablerIcons.trash,
                    color: _kDanger,
                    onTap: widget.enabled ? widget.onDelete : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color:
            enabled ? color.withValues(alpha: 0.08) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 32,
            height: 30,
            child: Icon(
              icon,
              size: 15,
              color: enabled ? color : _kIcon.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Confirm dialogs ─────────────────────────────────────────────────────────

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.isDestructive = false,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(
        title,
        style: _uText(15, _kTitle, fontWeight: FontWeight.w700),
      ),
      content: Text(
        message,
        style: _uText(12, _kLabel, height: 1.45),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: _uText(12, _kLabel)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isDestructive ? _kDanger : _kActionDark,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            confirmLabel,
            style: _uText(12, Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _RestoreConfirmDialog extends StatefulWidget {
  const _RestoreConfirmDialog({
    required this.backup,
    required this.vaultName,
  });

  final LocalBackupInfo backup;
  final String vaultName;

  @override
  State<_RestoreConfirmDialog> createState() => _RestoreConfirmDialogState();
}

class _RestoreConfirmDialogState extends State<_RestoreConfirmDialog> {
  bool _ackOverwrite = false;
  bool _ackUnlock = false;

  bool get _canSubmit => _ackOverwrite && _ackUnlock;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(
        'Restore from backup',
        style: _uText(15, _kTitle, fontWeight: FontWeight.w700),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'You are about to overwrite "${widget.vaultName}" with:',
              style: _uText(12, _kLabel, height: 1.4),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _kCanvas,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorderSoft),
              ),
              child: Text(
                widget.backup.fileName,
                style: _uText(12, _kTitle, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Text(
                'After restore you must unlock again using the credentials '
                'that were configured for this backup.',
                style: _uText(11, const Color(0xFF92400E), height: 1.4),
              ),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _ackOverwrite,
              activeColor: _kActionDark,
              onChanged: (v) => setState(() => _ackOverwrite = v ?? false),
              title: Text(
                'I understand the current database will be overwritten and cannot be undone.',
                style: _uText(12, _kTitle, height: 1.35),
              ),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _ackUnlock,
              activeColor: _kActionDark,
              onChanged: (v) => setState(() => _ackUnlock = v ?? false),
              title: Text(
                'I have the credentials needed to unlock the restored database.',
                style: _uText(12, _kTitle, height: 1.35),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: _uText(12, _kLabel)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _kActionDark,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _kActionDark.withValues(alpha: 0.4),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: _canSubmit ? () => Navigator.of(context).pop(true) : null,
          child: Text(
            'Restore',
            style: _uText(12, Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// ── Progress dialog (import-style) ──────────────────────────────────────────

/// Live restore progress modal listening to [backupRestoreProgressProvider].
/// Styled like the import password items progress dialog.
class _RestoreProgressDialog extends ConsumerStatefulWidget {
  const _RestoreProgressDialog();

  @override
  ConsumerState<_RestoreProgressDialog> createState() =>
      _RestoreProgressDialogState();
}

class _RestoreProgressDialogState extends ConsumerState<_RestoreProgressDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _successController;
  late final Animation<double> _successScale;
  final ScrollController _logScrollController = ScrollController();
  int _lastLogCount = 0;

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
  Widget build(BuildContext context) {
    final progress = ref.watch(backupRestoreProgressProvider);
    final value = progress?.value ?? 0.0;
    final isComplete = value >= 1.0;
    final message = progress?.message ?? 'Preparing restore…';
    final logs = progress?.logs ?? const <String>[];

    if (isComplete &&
        !_successController.isAnimating &&
        _successController.value == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_successController.value == 0 && !_successController.isAnimating) {
          _successController.forward();
        }
      });
    }

    if (logs.length != _lastLogCount) {
      _lastLogCount = logs.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_logScrollController.hasClients) return;
        _logScrollController.jumpTo(
          _logScrollController.position.maxScrollExtent,
        );
      });
    }

    final percent = (value * 100).clamp(0, 100).round();

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 420,
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
                Text(
                  'Restore Complete',
                  style: _uText(20, const Color(0xFF1A1D23),
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Unlock the database to access the restored data.',
                  textAlign: TextAlign.center,
                  style: _uText(13, _kLabel, height: 1.4),
                ),
              ] else ...<Widget>[
                Text(
                  'Restoring Database',
                  style: _uText(18, const Color(0xFF1A1D23),
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: _uText(13, _kLabel, height: 1.4),
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: value <= 0 ? null : value,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFF3F4F6),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      _kActionDark,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$percent%',
                    style: _uText(
                      24,
                      const Color(0xFF1F2937),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (logs.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Restore log',
                      style: _uText(11, _kIcon, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    height: 120,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: ListView.builder(
                      controller: _logScrollController,
                      padding: EdgeInsets.zero,
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            '• ${logs[index]}',
                            style: _uText(11, _kLabel, height: 1.35),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
