part of 'vault_screen.dart';

Future<String?> _showPasswordGeneratorDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Password generator',
    builder: (ctx) => const _PasswordGeneratorDialog(),
  );
}

class _PasswordGeneratorDialog extends StatefulWidget {
  const _PasswordGeneratorDialog();

  @override
  State<_PasswordGeneratorDialog> createState() =>
      _PasswordGeneratorDialogState();
}

class _PasswordGeneratorDialogState extends State<_PasswordGeneratorDialog> {
  _GenType _genType = _GenType.smart;
  int _genLength = 25;
  bool _genLetters = true;
  bool _genNumbers = true;
  bool _genSymbols = true;
  String _generatedPassword = '';
  bool _genCopied = false;
  Timer? _genCopiedTimer;
  String? _toastMessage;
  bool _toastDanger = false;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _generatedPassword = _genPassword(
      length: _genLength,
      letters: _genLetters,
      numbers: _genNumbers,
      symbols: _genSymbols,
    );
  }

  @override
  void dispose() {
    _genCopiedTimer?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  void _doRegen() {
    setState(() {
      _generatedPassword = _genPassword(
        length: _genLength,
        letters: _genLetters,
        numbers: _genNumbers,
        symbols: _genSymbols,
      );
    });
  }

  Future<void> _copyGen() async {
    if (_generatedPassword.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _generatedPassword));
    setState(() => _genCopied = true);
    _genCopiedTimer?.cancel();
    _genCopiedTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _genCopied = false);
    });
    _showToast('Password copied');
  }

  void _applyGenType(_GenType t) {
    final d = _genTypeDefaults(t);
    setState(() {
      _genType = t;
      _genLength = d.length;
      _genLetters = d.letters;
      _genNumbers = d.numbers;
      _genSymbols = d.symbols;
    });
    _doRegen();
  }

  void _toggleGenChar(String key, bool value) {
    final nextLetters = key == 'letters' ? value : _genLetters;
    final nextNumbers = key == 'numbers' ? value : _genNumbers;
    final nextSymbols = key == 'symbols' ? value : _genSymbols;
    if (!nextLetters && !nextNumbers && !nextSymbols) {
      _showToast('Choose at least one character set', danger: true);
      return;
    }
    setState(() {
      _genLetters = nextLetters;
      _genNumbers = nextNumbers;
      _genSymbols = nextSymbols;
    });
    _doRegen();
  }

  void _showToast(String message, {bool danger = false}) {
    _toastTimer?.cancel();
    setState(() {
      _toastMessage = message;
      _toastDanger = danger;
    });
    _toastTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  TextStyle _genText(
    double size,
    Color color, {
    FontWeight weight = FontWeight.w500,
  }) {
    return TextStyle(
      fontSize: size,
      color: color,
      fontWeight: weight,
      fontFamily: currentFontFamily,
    );
  }

  void _useThisPassword() {
    if (_generatedPassword.isEmpty) return;
    Navigator.of(context).pop(_generatedPassword);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Semantics(
        label: 'Password generator dialog',
        container: true,
        child: Container(
          width: 570,
          decoration: BoxDecoration(
            color: const Color(0xFFE7EBF0),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFC9D2DE)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x33172033),
                blurRadius: 32,
                offset: Offset(0, 14),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildHeader(),
              const SizedBox(height: 10),
              _buildContent(),
              const SizedBox(height: 12),
              _buildActionButtons(),
              if (_toastMessage != null) ...<Widget>[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.center,
                  child: _InAppToast(
                    message: _toastMessage!,
                    danger: _toastDanger,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF8BA9D8), width: 2),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            TablerIcons.shield_lock,
            color: Color(0xFF1F2937),
            size: 16,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Generate Password',
              style: _genText(
                13,
                const Color(0xFF1F2937),
                weight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Tooltip(
            message: 'Close',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    TablerIcons.x,
                    size: 16,
                    color: Color(0xFF5E6B7D),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE2E7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD0D8E2)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: _GenType.values.map((t) {
              final bool active = t == _genType;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Semantics(
                  button: true,
                  selected: active,
                  label: '${_genTypeLabel(t)} preset',
                  child: GestureDetector(
                    onTap: () => _applyGenType(t),
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF0F67D6)
                            : const Color(0xFFDDE4EC),
                        borderRadius: BorderRadius.circular(6),
                        border: active
                            ? null
                            : Border.all(color: const Color(0xFFCCD4DF)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _genTypeLabel(t),
                        style: _genText(
                          10,
                          active ? Colors.white : const Color(0xFF3A4A5C),
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD0D8E2)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    label: 'Generated password',
                    value: _generatedPassword,
                    readOnly: true,
                    child: _generatedPassword.isEmpty
                        ? Text(
                            'Generating...',
                            style: _genText(
                              11,
                              const Color(0xFF8A9BB0),
                            ),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _generatedPassword.split('').map((c) {
                                final Color col;
                                if (RegExp(r'[0-9]').hasMatch(c)) {
                                  col = const Color(0xFF0F67D6);
                                } else if (RegExp(r'[^A-Za-z0-9]')
                                    .hasMatch(c)) {
                                  col = const Color(0xFFEA8C00);
                                } else {
                                  col = const Color(0xFF252C35);
                                }
                                return Text(
                                  c,
                                  style: _genText(
                                    12,
                                    col,
                                    weight: FontWeight.w600,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: _genCopied ? 'Copied' : 'Copy password',
                  child: Semantics(
                    button: true,
                    label: 'Copy generated password',
                    child: GestureDetector(
                      onTap: _copyGen,
                      child: Icon(
                        _genCopied ? TablerIcons.check : TablerIcons.copy,
                        size: 15,
                        color: _genCopied
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF8A9BB0),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Regenerate',
                  child: Semantics(
                    button: true,
                    label: 'Regenerate password',
                    child: GestureDetector(
                      onTap: _doRegen,
                      child: const Icon(
                        TablerIcons.refresh,
                        size: 15,
                        color: Color(0xFF8A9BB0),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Text(
                'Length',
                style: _genText(
                  10,
                  const Color(0xFF5E6B7D),
                  weight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$_genLength',
                style: _genText(
                  10,
                  const Color(0xFF252C35),
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: const Color(0xFF0F67D6),
              inactiveTrackColor: const Color(0xFFCCD4DF),
              thumbColor: const Color(0xFF0F67D6),
              overlayColor: const Color(0x220F67D6),
            ),
            child: Slider(
              value: _genLength.toDouble(),
              min: 8,
              max: 64,
              divisions: 56,
              label: '$_genLength',
              onChanged: (v) {
                setState(() => _genLength = v.round());
                _doRegen();
              },
            ),
          ),
          _buildToggle(
            'Letters',
            _genLetters,
            (v) => _toggleGenChar('letters', v),
          ),
          _buildToggle(
            'Numbers',
            _genNumbers,
            (v) => _toggleGenChar('numbers', v),
          ),
          _buildToggle(
            'Symbols',
            _genSymbols,
            (v) => _toggleGenChar('symbols', v),
            last: true,
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    bool last = false,
  }) {
    return Container(
      height: 30,
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFCCD4DF), width: 0.5),
              ),
            ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: _genText(
                11,
                const Color(0xFF3A4A5C),
                weight: FontWeight.w500,
              ),
            ),
          ),
          Semantics(
            toggled: value,
            label: '$label toggle',
            child: GestureDetector(
              onTap: () => onChanged(!value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 34,
                height: 18,
                decoration: BoxDecoration(
                  color: value
                      ? const Color(0xFF0F67D6)
                      : const Color(0xFFCCD4DF),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: AnimatedAlign(
                  alignment:
                      value ? Alignment.centerRight : Alignment.centerLeft,
                  duration: const Duration(milliseconds: 140),
                  child: Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: <Widget>[
        Expanded(
          child: Semantics(
            button: true,
            label: 'Cancel',
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCCD4DF)),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Cancel',
                  style: _genText(
                    12,
                    const Color(0xFF3A4A5C),
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            button: true,
            label: 'Use this password',
            child: GestureDetector(
              onTap: _useThisPassword,
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F67D6),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Use Password',
                  style: _genText(
                    12,
                    Colors.white,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
