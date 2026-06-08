import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../../../core/ui/app_snack_bar.dart';

/// Matches desktop quick-search generator: Smart / Memorable / PIN presets,
/// length slider, character set toggles, colored preview, copy & regenerate.
Future<void> showPasswordGeneratorModal(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _PasswordGeneratorSheet(),
  );
}

enum _GenType { smart, memorable, pin }

class _PasswordGeneratorSheet extends StatefulWidget {
  const _PasswordGeneratorSheet();

  @override
  State<_PasswordGeneratorSheet> createState() =>
      _PasswordGeneratorSheetState();
}

class _PasswordGeneratorSheetState extends State<_PasswordGeneratorSheet> {
  static const _service = PasswordGeneratorService();

  _GenType _genType = _GenType.smart;
  int _length = 25;
  bool _letters = true;
  bool _numbers = true;
  bool _symbols = true;
  String _password = '';
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  void _regenerate() {
    try {
      final pwd = _service.generate(
        length: _length,
        includeUppercase: _letters,
        includeLowercase: _letters,
        includeNumbers: _numbers,
        includeSymbols: _symbols,
      );
      setState(() => _password = pwd);
    } catch (_) {
      setState(() => _password = '');
    }
  }

  void _applyType(_GenType t) {
    final d = _defaultsFor(t);
    setState(() {
      _genType = t;
      _length = d.$1;
      _letters = d.$2;
      _numbers = d.$3;
      _symbols = d.$4;
    });
    _regenerate();
  }

  /// (length, letters, numbers, symbols)
  (int, bool, bool, bool) _defaultsFor(_GenType t) {
    switch (t) {
      case _GenType.smart:
        return (25, true, true, true);
      case _GenType.memorable:
        return (16, true, true, false);
      case _GenType.pin:
        return (8, false, true, false);
    }
  }

  String _typeLabel(_GenType t) {
    switch (t) {
      case _GenType.smart:
        return 'Smart';
      case _GenType.memorable:
        return 'Memorable';
      case _GenType.pin:
        return 'PIN';
    }
  }

  void _toggleLetters(bool v) => _toggleChar(letters: v);
  void _toggleNumbers(bool v) => _toggleChar(numbers: v);
  void _toggleSymbols(bool v) => _toggleChar(symbols: v);

  void _toggleChar({bool? letters, bool? numbers, bool? symbols}) {
    final nextL = letters ?? _letters;
    final nextN = numbers ?? _numbers;
    final nextS = symbols ?? _symbols;
    if (!nextL && !nextN && !nextS) {
      AppSnackBar.error(context, 'Choose at least one character set');
      return;
    }
    setState(() {
      _letters = nextL;
      _numbers = nextN;
      _symbols = nextS;
    });
    _regenerate();
  }

  Future<void> _copy() async {
    if (_password.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _password));
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
    if (!mounted) return;
    AppSnackBar.success(context, 'Password copied');
  }

  static const _ink = Color(0xFF0A3B48);
  static const _surface = Color(0xFFF4F9FA);
  static const _text = Color(0xFF163640);
  static const _muted = Color(0xFF6B858D);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Color(0x290A2F3D),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCE6EC),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.shield_outlined, color: _ink, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Generate password',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: _muted,
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _GenType.values.map((t) {
                      final active = t == _genType;
                      return ChoiceChip(
                        label: Text(_typeLabel(t)),
                        selected: active,
                        onSelected: (_) => _applyType(t),
                        selectedColor: const Color(0xFFDCEEF2),
                        labelStyle: TextStyle(
                          color: active ? _ink : _muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        side: BorderSide(
                          color: active ? _ink : const Color(0xFFE3EAF0),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE3EAF0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE3EAF0)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _password.isEmpty
                                    ? Text(
                                        'Generating…',
                                        style: TextStyle(
                                          color: _muted,
                                          fontSize: 13,
                                        ),
                                      )
                                    : SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: _password.split('').map((
                                            c,
                                          ) {
                                            final Color col;
                                            if (RegExp(r'[0-9]').hasMatch(c)) {
                                              col = const Color(0xFF0F67D6);
                                            } else if (RegExp(
                                              r'[^A-Za-z0-9]',
                                            ).hasMatch(c)) {
                                              col = const Color(0xFFEA8C00);
                                            } else {
                                              col = const Color(0xFF252C35);
                                            }
                                            return Text(
                                              c,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ).copyWith(color: col),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                              ),
                              IconButton(
                                onPressed: _copy,
                                icon: Icon(
                                  _copied
                                      ? Icons.check_rounded
                                      : Icons.copy_rounded,
                                  size: 20,
                                  color: _copied
                                      ? const Color(0xFF16A34A)
                                      : _muted,
                                ),
                                tooltip: 'Copy',
                              ),
                              IconButton(
                                onPressed: _regenerate,
                                icon: const Icon(Icons.refresh_rounded),
                                color: _muted,
                                tooltip: 'Regenerate',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              'Length',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _text.withValues(alpha: 0.85),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '$_length',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _text,
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                            activeTrackColor: _ink,
                            inactiveTrackColor: const Color(0xFFCCD4DF),
                            thumbColor: _ink,
                            overlayColor: const Color(0x220A3B48),
                          ),
                          child: Slider(
                            value: _length.toDouble(),
                            min: 8,
                            max: 64,
                            divisions: 56,
                            onChanged: (v) {
                              setState(() => _length = v.round());
                              _regenerate();
                            },
                          ),
                        ),
                        _toggleRow('Letters', _letters, _toggleLetters),
                        _toggleRow('Numbers', _numbers, _toggleNumbers),
                        _toggleRow('Symbols', _symbols, _toggleSymbols),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _text,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: _ink,
            activeTrackColor: const Color(0xFF8EB8C2),
          ),
        ],
      ),
    );
  }
}
