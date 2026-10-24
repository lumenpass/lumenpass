import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../domain/import_provider.dart';
import '../application/import_state.dart';
import 'import_light_colors.dart';
import '../../../presentation/widgets/drive_clue/dc_dialog_title_bar.dart';

enum _ImportStep { chooseProvider, uploadFile }

class ImportProviderModal extends ConsumerStatefulWidget {
  const ImportProviderModal({
    super.key,
    required this.onClose,
    required this.onNext,
  });

  final VoidCallback onClose;
  final VoidCallback onNext;

  @override
  ConsumerState<ImportProviderModal> createState() =>
      _ImportProviderModalState();
}

class _ImportProviderModalState extends ConsumerState<ImportProviderModal> {
  ImportProviderDefinition? _selectedProvider;
  String? _selectedFilePath;
  String? _selectedFileName;
  String? _localError;
  _ImportStep _step = _ImportStep.chooseProvider;
  bool _isDragOver = false;

  bool get _canGoNext {
    if (_step == _ImportStep.chooseProvider) {
      return _selectedProvider != null;
    }
    return _selectedFilePath != null && _selectedFileName != null;
  }

  void _selectProvider(ImportProviderDefinition provider) {
    if (_selectedProvider?.type == provider.type) return;

    setState(() {
      _selectedProvider = provider;
      _selectedFilePath = null;
      _selectedFileName = null;
      _localError = null;
    });

    ref.read(importStateProvider.notifier).selectProvider(provider);
    ref.read(importStateProvider.notifier).clearParseError();
  }

  String _acceptedLabel(ImportProviderDefinition provider) {
    final exts = provider.acceptedExtensions
        .map((e) => e.toUpperCase().replaceFirst('.', ''))
        .toList();
    if (exts.length == 1) return exts.first;
    if (exts.length == 2) return '${exts.first} or ${exts.last}';
    return '${exts.sublist(0, exts.length - 1).join(", ")}, or ${exts.last}';
  }

  bool _hasValidExtension(String name, ImportProviderDefinition provider) {
    final lower = name.toLowerCase();
    return provider.acceptedExtensions
        .map((e) => e.toLowerCase())
        .any((e) => lower.endsWith(e));
  }

  void _applyPickedFile(String path, String name) {
    final provider = _selectedProvider;
    if (provider == null) return;

    if (!_hasValidExtension(name, provider)) {
      setState(() {
        _localError =
            'That file is not a valid ${provider.displayName} export. '
            'Please select the correct file '
            '(${provider.acceptedExtensions.join(", ")}).';
      });
      return;
    }

    setState(() {
      _selectedFilePath = path;
      _selectedFileName = name;
      _localError = null;
    });

    ref.read(importStateProvider.notifier).selectFile(path, name);
    ref.read(importStateProvider.notifier).clearParseError();
  }

  Future<void> _pickFile() async {
    final provider = _selectedProvider;
    if (provider == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select ${provider.displayName} export file',
        allowMultiple: false,
        lockParentWindow: true,
        type: FileType.custom,
        allowedExtensions: provider.acceptedExtensions
            .map((e) => e.replaceFirst('.', ''))
            .toList(growable: false),
      );

      final file = result?.files.single;
      if (file == null || file.path == null) return;
      if (!mounted) return;

      _applyPickedFile(file.path!, file.name);
    } catch (error) {
      if (mounted) {
        setState(() {
          _localError = 'Unable to pick file: $error';
        });
      }
    }
  }

  void _handleDroppedFiles(DropDoneDetails details) {
    if (details.files.isEmpty) return;
    final dropped = details.files.first;
    _applyPickedFile(dropped.path, dropped.name);
  }

  void _handleNext() {
    if (!_canGoNext) return;
    if (_step == _ImportStep.chooseProvider) {
      setState(() {
        _step = _ImportStep.uploadFile;
        _localError = null;
      });
      return;
    }
    widget.onNext();
  }

  void _handleBack() {
    setState(() {
      _step = _ImportStep.chooseProvider;
      _localError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String? parseError =
        ref.watch(importStateProvider.select((s) => s.parseError));
    final String? errorMessage = _localError ?? parseError;
    final providerName = _selectedProvider?.displayName ?? '';

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Container(
          width: 520,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: ImportColors.panel,
            borderRadius: BorderRadius.circular(7),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: ImportColors.shadow,
                blurRadius: 32,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DcDialogTitleBar(
                title: _step == _ImportStep.chooseProvider
                    ? 'Import Passwords from providers'
                    : 'Upload $providerName export',
                onClose: widget.onClose,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: _Stepper(currentStep: _step),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _step == _ImportStep.chooseProvider
                      ? _buildProviderStep(errorMessage)
                      : _buildUploadStep(errorMessage),
                ),
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: ImportColors.lineStrong),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                child: _buildFooter(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProviderStep(String? errorMessage) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.1,
          children: ImportProviderDefinition.all.map((provider) {
            final isSelected = _selectedProvider?.type == provider.type;
            return _ProviderCard(
              provider: provider,
              isSelected: isSelected,
              onTap: () => _selectProvider(provider),
            );
          }).toList(growable: false),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 12),
          _InlineError(message: errorMessage),
        ],
      ],
    );
  }

  Widget _buildUploadStep(String? errorMessage) {
    final provider = _selectedProvider!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _InfoBanner(
          message: 'Drag and drop your export file into the area below, '
              'or click "Browse files" to pick it from your computer. '
              'The file is parsed locally — nothing leaves your device.',
        ),
        const SizedBox(height: 16),
        _ProviderSummary(provider: provider),
        const SizedBox(height: 14),
        DropTarget(
          onDragEntered: (_) => setState(() => _isDragOver = true),
          onDragExited: (_) => setState(() => _isDragOver = false),
          onDragDone: (details) {
            setState(() => _isDragOver = false);
            _handleDroppedFiles(details);
          },
          child: _DropZoneShell(
            isDragOver: _isDragOver,
            hasFile: _selectedFileName != null,
            child: _selectedFileName != null
                ? _DropAreaSelectedFile(
                    fileName: _selectedFileName!,
                    onPickAnother: _pickFile,
                  )
                : _DropAreaPrompt(
                    isDragOver: _isDragOver,
                    acceptedLabel: _acceptedLabel(provider),
                    onBrowse: _pickFile,
                  ),
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 12),
          _InlineError(message: errorMessage),
        ],
      ],
    );
  }

  Widget _buildFooter() {
    return Row(
      children: <Widget>[
        if (_step == _ImportStep.uploadFile)
          _FooterButton(
            label: 'Back',
            backgroundColor: Colors.transparent,
            textColor: ImportColors.muted,
            borderColor: ImportColors.lineStrong,
            onTap: _handleBack,
          ),
        const Spacer(),
        _FooterButton(
          label: 'Cancel',
          backgroundColor: Colors.transparent,
          textColor: ImportColors.muted,
          borderColor: ImportColors.lineStrong,
          onTap: widget.onClose,
        ),
        const SizedBox(width: 10),
        _FooterButton(
          label: 'Next',
          backgroundColor:
              _canGoNext ? ImportColors.selection : ImportColors.row,
          textColor: _canGoNext ? Colors.white : ImportColors.faint,
          onTap: _canGoNext ? _handleNext : null,
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.currentStep});

  final _ImportStep currentStep;

  @override
  Widget build(BuildContext context) {
    final bool isStep2 = currentStep == _ImportStep.uploadFile;
    const Color accent = ImportColors.selection;
    const Color mutedText = ImportColors.faint;
    return Row(
      children: <Widget>[
        _StepBadge(
          number: 1,
          label: 'Choose provider',
          isActive: !isStep2,
          isDone: isStep2,
        ),
        Expanded(
          child: Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: isStep2 ? accent : ImportColors.line,
          ),
        ),
        _StepBadge(
          number: 2,
          label: 'Upload file',
          isActive: isStep2,
          isDone: false,
          inactiveTextColor: mutedText,
        ),
      ],
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({
    required this.number,
    required this.label,
    required this.isActive,
    required this.isDone,
    this.inactiveTextColor,
  });

  final int number;
  final String label;
  final bool isActive;
  final bool isDone;
  final Color? inactiveTextColor;

  @override
  Widget build(BuildContext context) {
    const Color accent = ImportColors.selection;
    final bool filled = isActive || isDone;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? accent : ImportColors.rowAlternate,
            border: Border.all(
              color: filled ? accent : ImportColors.lineStrong,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: isDone
              ? const Icon(TablerIcons.check, size: 14, color: Colors.white)
              : Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: filled ? Colors.white : ImportColors.faint,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isActive
                ? accent
                : (isDone ? accent : (inactiveTextColor ?? accent)),
          ),
        ),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ImportColors.selectionSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ImportColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(TablerIcons.info_circle,
              size: 16, color: ImportColors.teal),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: ImportColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderSummary extends StatelessWidget {
  const _ProviderSummary({required this.provider});

  final ImportProviderDefinition provider;

  String _acceptedLabel() {
    final exts = provider.acceptedExtensions
        .map((e) => e.toUpperCase().replaceFirst('.', ''))
        .toList();
    if (exts.length == 1) return exts.first;
    if (exts.length == 2) return '${exts.first} or ${exts.last}';
    return '${exts.sublist(0, exts.length - 1).join(", ")}, or ${exts.last}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ImportColors.row,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ImportColors.lineStrong),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: provider.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Image.asset(
              provider.assetPath,
              width: 18,
              height: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  provider.displayName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ImportColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Accepted: ${_acceptedLabel()}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: ImportColors.muted,
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

class _DropZoneShell extends StatelessWidget {
  const _DropZoneShell({
    required this.isDragOver,
    required this.hasFile,
    required this.child,
  });

  final bool isDragOver;
  final bool hasFile;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const Color accent = ImportColors.selection;
    final Color borderColor = isDragOver ? accent : ImportColors.lineStrong;
    final double borderWidth = isDragOver ? 1.8 : 1.4;

    final LinearGradient background = isDragOver
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[ImportColors.selectionSoft, ImportColors.row],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[ImportColors.rowAlternate, ImportColors.row],
          );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 140),
      decoration: BoxDecoration(
        gradient: background,
        borderRadius: BorderRadius.circular(7),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: isDragOver ? 0.08 : 0.03),
            blurRadius: isDragOver ? 22 : 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: _DashedRRectBorderPainter(
          color: borderColor,
          strokeWidth: borderWidth,
          radius: 16,
          dashLength: 6,
          gapLength: 4,
        ),
        child: child,
      ),
    );
  }
}

class _DashedRRectBorderPainter extends CustomPainter {
  const _DashedRRectBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.dashLength,
    required this.gapLength,
  });

  final Color color;
  final double strokeWidth;
  final double radius;
  final double dashLength;
  final double gapLength;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final Path path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ));

    final Path dashed = Path();
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double next = distance + dashLength;
        dashed.addPath(
          metric.extractPath(distance, next.clamp(0.0, metric.length)),
          Offset.zero,
        );
        distance = next + gapLength;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRRectBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.gapLength != gapLength;
  }
}

class _DropAreaPrompt extends StatelessWidget {
  const _DropAreaPrompt({
    required this.isDragOver,
    required this.acceptedLabel,
    required this.onBrowse,
  });

  final bool isDragOver;
  final String acceptedLabel;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _DropIconStack(isDragOver: isDragOver),
          const SizedBox(height: 8),
          Text(
            isDragOver ? 'Release to drop file' : 'Drag & drop your file here',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: ImportColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Supported: $acceptedLabel',
            style: const TextStyle(fontSize: 11, color: ImportColors.muted),
          ),
          const SizedBox(height: 6),
          Text(
            'or',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: ImportColors.faint,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          _BrowseButton(onTap: onBrowse),
        ],
      ),
    );
  }
}

class _DropIconStack extends StatelessWidget {
  const _DropIconStack({required this.isDragOver});

  final bool isDragOver;

  @override
  Widget build(BuildContext context) {
    const Color accent = ImportColors.selection;
    return SizedBox(
      width: 42,
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: isDragOver ? 42 : 40,
            height: isDragOver ? 42 : 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: isDragOver ? 0.10 : 0.06),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: isDragOver ? 36 : 34,
            height: isDragOver ? 36 : 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: isDragOver ? 0.16 : 0.10),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  isDragOver ? ImportColors.teal : ImportColors.rowAlternate,
                  isDragOver ? ImportColors.selection : ImportColors.row,
                ],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              isDragOver ? TablerIcons.download : TablerIcons.cloud_upload,
              size: 18,
              color: isDragOver ? Colors.white : accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowseButton extends StatefulWidget {
  const _BrowseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_BrowseButton> createState() => _BrowseButtonState();
}

class _BrowseButtonState extends State<_BrowseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: _hovered
                  ? ImportColors.selectionSoft
                  : ImportColors.rowAlternate,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: ImportColors.selection,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(TablerIcons.folder_open,
                    size: 16, color: ImportColors.selection),
                const SizedBox(width: 8),
                const Text(
                  'Browse files',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ImportColors.selection,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DropAreaSelectedFile extends StatelessWidget {
  const _DropAreaSelectedFile({
    required this.fileName,
    required this.onPickAnother,
  });

  final String fileName;
  final VoidCallback onPickAnother;

  String _fileBadgeLabel(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.1pux')) return '1PUX';
    if (lower.endsWith('.json')) return 'JSON';
    if (lower.endsWith('.csv')) return 'CSV';
    final dot = lower.lastIndexOf('.');
    if (dot >= 0 && dot < lower.length - 1) {
      return lower.substring(dot + 1).toUpperCase();
    }
    return 'FILE';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: ImportColors.selectionSoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              TablerIcons.file_check,
              size: 26,
              color: ImportColors.selection,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  fileName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ImportColors.text,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ImportColors.rowAlternate,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: ImportColors.greenSoft),
                ),
                child: Text(
                  _fileBadgeLabel(fileName),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: ImportColors.green,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _BrowseButton(onTap: onPickAnother),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.isSelected,
    required this.onTap,
  });

  final ImportProviderDefinition provider;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected ? ImportColors.selection : ImportColors.line;
    final bgColor = isSelected ? ImportColors.selectionSoft : ImportColors.row;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                top: 0,
                left: 0,
                child: _ProviderCheckbox(checked: isSelected),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: provider.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      alignment: Alignment.center,
                      child: Image.asset(
                        provider.assetPath,
                        width: 28,
                        height: 28,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      provider.displayName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: ImportColors.text,
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

class _ProviderCheckbox extends StatelessWidget {
  const _ProviderCheckbox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: checked ? ImportColors.selection : ImportColors.rowAlternate,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: checked ? ImportColors.selection : ImportColors.lineStrong,
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: checked
          ? const Icon(TablerIcons.check, size: 11, color: Colors.white)
          : null,
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ImportColors.redSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ImportColors.redLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(TablerIcons.alert_triangle,
              size: 18, color: ImportColors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: ImportColors.red,
              ),
            ),
          ),
        ],
      ),
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
          onTap: isEnabled ? widget.onTap : null,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _hovered && isEnabled
                  ? widget.backgroundColor.withValues(alpha: 0.85)
                  : widget.backgroundColor,
              borderRadius: BorderRadius.circular(6),
              border: widget.borderColor != null
                  ? Border.all(color: widget.borderColor!)
                  : null,
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 13,
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
