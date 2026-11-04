part of 'vault_screen.dart';

Future<String?> _showPasswordGeneratorDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Password generator',
    builder: (ctx) => const PasswordGeneratorDialog(),
  );
}

class PasswordGeneratorDialog extends StatefulWidget {
  const PasswordGeneratorDialog({super.key});

  @override
  State<PasswordGeneratorDialog> createState() =>
      PasswordGeneratorDialogState();
}

class PasswordGeneratorDialogState extends State<PasswordGeneratorDialog> {
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
    return _text(size, color, fontWeight: weight);
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
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            // Light body under the shared dark title bar, matching the other
            // refreshed dialogs (add item, confirmations, cloud services).
            //
            // No outer border here: a border insets the child by its width, so
            // the white panel would peek out as a ring around the dark title
            // bar. The other light modals rely on the shadow alone too.
            color: DcColors.lightSurface,
            borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: DcColors.shadow,
                blurRadius: 36,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DcDialogTitleBar(
                title: 'Generate Password',
                onClose: () => Navigator.of(context).pop(),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildContent(),
                      const SizedBox(height: 16),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      decoration: BoxDecoration(
        color: DcColors.lightInset,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DcColors.sidebarLine),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
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
                  child: InkWell(
                    onTap: () => _applyGenType(t),
                    borderRadius: BorderRadius.circular(7),
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: active
                            ? _kPrimaryButtonColor
                            : DcColors.lightSurface,
                        borderRadius: BorderRadius.circular(7),
                        border: active
                            ? null
                            : Border.all(color: DcColors.lightLineStrong),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _genTypeLabel(t),
                        style: _genText(
                          12,
                          active ? Colors.white : DcColors.sidebarText,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: DcColors.lightSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DcColors.lightLineStrong),
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
                              12,
                              DcColors.sidebarMuted,
                            ),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _generatedPassword.split('').map((c) {
                                final Color col;
                                if (RegExp(r'[0-9]').hasMatch(c)) {
                                  col = _kPrimaryButtonColor;
                                } else if (RegExp(r'[^A-Za-z0-9]')
                                    .hasMatch(c)) {
                                  col = DcColors.deepOrange;
                                } else {
                                  col = DcColors.sidebarText;
                                }
                                return Text(
                                  c,
                                  style: _genText(
                                    14,
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
                IconButton(
                  tooltip: _genCopied ? 'Copied' : 'Copy password',
                  onPressed: _copyGen,
                  icon: Icon(
                    _genCopied ? TablerIcons.check : TablerIcons.copy,
                    size: 18,
                  ),
                  color:
                      _genCopied ? DcColors.tealOnLight : DcColors.sidebarMuted,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Regenerate password',
                  onPressed: _doRegen,
                  icon: const Icon(TablerIcons.refresh, size: 18),
                  color: DcColors.sidebarMuted,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Text(
                'Length',
                style: _genText(
                  12,
                  DcColors.sidebarMuted,
                  weight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$_genLength',
                style: _genText(
                  12,
                  DcColors.sidebarText,
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
              activeTrackColor: _kPrimaryButtonColor,
              inactiveTrackColor: DcColors.sidebarLine,
              thumbColor: _kPrimaryButtonColor,
              overlayColor: DcColors.lightSelectionFill,
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
      height: 36,
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: DcColors.sidebarLine, width: 0.5),
              ),
            ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: _genText(
                12,
                DcColors.sidebarText,
                weight: FontWeight.w500,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: _kPrimaryButtonColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
              foregroundColor: DcColors.sidebarMuted,
              backgroundColor: DcColors.lightSurface,
              side: const BorderSide(color: DcColors.lightLineStrong),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text('Cancel',
                style: _genText(13, DcColors.sidebarMuted,
                    weight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: _useThisPassword,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
              backgroundColor: _kPrimaryButtonColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text('Use Password',
                style: _genText(13, Colors.white, weight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
