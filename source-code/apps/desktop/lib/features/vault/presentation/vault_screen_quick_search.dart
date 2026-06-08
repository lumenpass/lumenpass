part of 'vault_screen.dart';

enum _GenType { smart, memorable, pin }

const int _kQuickSearchResultLimit = 50;
const int _kQuickSearchCacheCapacity = 32;

/// Per-entry memoized [SearchableEntryView] used by the Quick Search
/// ranker. Rebuilding this struct is cheap, but we still cache it because
/// large vaults are scanned on every keystroke and the per-key allocation
/// pressure is what showed up in profiles.
final Expando<SearchableEntryView> _quickSearchViewCache =
    Expando<SearchableEntryView>('quickSearchView');

SearchableEntryView _quickSearchViewFor(_MockEntry entry) {
  final cached = _quickSearchViewCache[entry];
  if (cached != null) {
    return cached;
  }
  // _MockEntry only exposes a small subset of the underlying KdbxEntry,
  // so we project it into the same generic shape used by the title-bar
  // search. `subtitle` is folded into the notes haystack — it's a UI
  // string (e.g. social-provider label) that users may search for but
  // shouldn't outrank URL/email matches.
  final extras = <MapEntry<String, String>>[
    MapEntry('subtitle', entry.subtitle),
  ];
  final view = SearchableEntryView(
    title: entry.title,
    url: entry.website,
    username: entry.username,
    notes: entry.notes,
    otpAuthUrl: entry.totpAuthUrl,
    tags: entry.tags,
    extraFields: extras,
    lastTouchedAt: entry.lastTouchedAt,
  );
  _quickSearchViewCache[entry] = view;
  return view;
}

typedef _QuickSearchToastCallback = void Function(
  String message, {
  bool danger,
});

class _QuickSearchOverlay extends StatefulWidget {
  const _QuickSearchOverlay({
    required this.entries,
    required this.onClose,
    required this.onEntrySelected,
    required this.onCreateNewItem,
    required this.onShowToast,
    required this.onEditItem,
    required this.currentTime,
    this.showBackdrop = true,
    this.onPreferredHeightChanged,
    this.initialSelectedUuid,
    this.initialShowGenerator = false,
    required this.shortcutDisplay,
  });

  final List<_MockEntry> entries;
  final String? initialSelectedUuid;
  final bool showBackdrop;
  final VoidCallback onClose;
  final ValueChanged<String> onEntrySelected;
  final Future<void> Function() onCreateNewItem;
  final _QuickSearchToastCallback onShowToast;
  final void Function(String uuid) onEditItem;
  final ValueChanged<double>? onPreferredHeightChanged;
  final DateTime currentTime;
  final bool initialShowGenerator;
  final String shortcutDisplay;

  @override
  State<_QuickSearchOverlay> createState() => _QuickSearchOverlayState();
}

class _QuickSearchOverlayState extends State<_QuickSearchOverlay> {
  static const int _kMaxVisibleRows = 5;
  static const double _kResultRowHeight = 40;
  static const double _kResultRowSpacing = 2;
  static const double _kResultListVerticalPadding = 12;
  static const double _kNoResultsHeight = 50;
  static const double _kTopSectionHeight = 62;
  static const double _kFooterMarginTop = 8;
  static const double _kFooterHeight = 52;
  static const double _kFooterMarginBottom = 10;
  static const double _kActionRowHeight = 34;
  static const double _kActionRowMarginBottom = 10;
  static const double _kStandaloneWindowHeightCompensation = 4;
  static const double _kDetailFieldRowHeight = 42.0;
  static const double _kDetailFieldListPadding = 12.0;
  static const double _kGeneratorContentHeight = 248.0;

  final TextEditingController _queryController = TextEditingController();
  final FocusNode _scopeFocusNode = FocusNode();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _resultsScrollController = ScrollController();
  int _activeIndex = 0;
  double? _lastPreferredHeight;
  _MockEntry? _detailEntry;
  int _detailFieldIndex = -1;

  bool _showGenerator = false;
  _GenType _genType = _GenType.smart;
  int _genLength = 25;
  bool _genLetters = true;
  bool _genNumbers = true;
  bool _genSymbols = true;
  String _generatedPassword = '';
  bool _genCopied = false;
  Timer? _genCopiedTimer;
  final Set<int> _revealedFieldIndices = <int>{};

  String _debouncedQuery = '';
  Timer? _debounceTimer;
  bool _isSearching = false;
  int _searchSeq = 0;
  List<_MockEntry> _visibleResults = const <_MockEntry>[];
  final LinkedHashMap<String, List<_MockEntry>> _resultLruCache =
      LinkedHashMap<String, List<_MockEntry>>();

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_handleQueryChanged);
    if (widget.initialShowGenerator) {
      _showGenerator = true;
      _generatedPassword = _genPassword(
        length: _genLength,
        letters: _genLetters,
        numbers: _genNumbers,
        symbols: _genSymbols,
      );
    }
    final selectedUuid = widget.initialSelectedUuid;
    if (selectedUuid != null && selectedUuid.isNotEmpty) {
      final initialIndex = widget.entries.indexWhere(
        (entry) => entry.uuid == selectedUuid,
      );
      if (initialIndex >= 0) {
        _activeIndex = initialIndex;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _scopeFocusNode.requestFocus();
      _inputFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _queryController
      ..removeListener(_handleQueryChanged)
      ..dispose();
    _scopeFocusNode.dispose();
    _inputFocusNode.dispose();
    _resultsScrollController.dispose();
    _genCopiedTimer?.cancel();
    _debounceTimer?.cancel();
    _resultLruCache.clear();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _QuickSearchOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entries, widget.entries)) {
      _resultLruCache.clear();
      _visibleResults = _debouncedQuery.isEmpty
          ? const <_MockEntry>[]
          : _computeResultsFor(_debouncedQuery);
    }
  }

  void _handleQueryChanged() {
    if (!mounted) {
      return;
    }
    final raw = _queryController.text.trim();
    // Cancel any pending search — this is the request-cancellation path
    // for outdated keystrokes and bumps the sequence token so any in-flight
    // result that arrives late is discarded.
    _debounceTimer?.cancel();
    _searchSeq++;

    if (raw.isEmpty) {
      // Empty query bypasses debounce so the UI clears instantly.
      if (_debouncedQuery.isNotEmpty ||
          _visibleResults.isNotEmpty ||
          _activeIndex != 0 ||
          _isSearching) {
        setState(() {
          _isSearching = false;
          _debouncedQuery = '';
          _visibleResults = const <_MockEntry>[];
          _activeIndex = 0;
        });
      }
      _schedulePreferredHeightReport();
      return;
    }

    final lowered = raw.toLowerCase();
    final mySeq = _searchSeq;
    _debounceTimer = Timer(kVaultSearchDebounce, () {
      unawaited(_runSearch(lowered, mySeq));
    });
  }

  Future<void> _runSearch(String loweredQuery, int seq) async {
    if (!mounted || seq != _searchSeq) {
      return;
    }

    final stopwatch = Stopwatch()..start();
    setState(() {
      _isSearching = true;
    });
    await Future<void>.delayed(kVaultSearchLoadingFrame);
    if (!mounted || seq != _searchSeq) {
      return;
    }

    try {
      final results = _computeResultsFor(loweredQuery);
      final remaining = kVaultSearchLoadingMinVisible - stopwatch.elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      if (!mounted || seq != _searchSeq) {
        return;
      }
      setState(() {
        _debouncedQuery = loweredQuery;
        _visibleResults = results;
        _isSearching = false;
        _activeIndex = 0;
      });
    } catch (_) {
      if (!mounted || seq != _searchSeq) {
        return;
      }
      setState(() {
        _isSearching = false;
      });
    }
    _schedulePreferredHeightReport();
  }

  List<_MockEntry> _computeResultsFor(String loweredQuery) {
    if (loweredQuery.isEmpty) {
      return const <_MockEntry>[];
    }
    final cached = _resultLruCache.remove(loweredQuery);
    if (cached != null) {
      // Touch — move to most-recently-used position.
      _resultLruCache[loweredQuery] = cached;
      return cached;
    }
    // Delegate matching + ordering to the shared ranker so the Quick
    // Search panel and the title-bar dropdown agree on which item should
    // surface first (URL > recent > email > title > notes).
    final ranked = rankSearchResults<_MockEntry>(
      entries: widget.entries,
      query: loweredQuery,
      viewOf: _quickSearchViewFor,
      titleOf: (entry) => entry.title,
      limit: _kQuickSearchResultLimit,
      now: widget.currentTime,
    );
    final frozen = List<_MockEntry>.unmodifiable(ranked);
    _resultLruCache[loweredQuery] = frozen;
    while (_resultLruCache.length > _kQuickSearchCacheCapacity) {
      _resultLruCache.remove(_resultLruCache.keys.first);
    }
    return frozen;
  }

  List<_MockEntry> get _filteredEntries => _visibleResults;

  _MockEntry? get _activeEntry {
    final results = _filteredEntries;
    if (results.isEmpty) {
      return null;
    }
    final resolvedIndex = _activeIndex.clamp(0, results.length - 1);
    return results[resolvedIndex];
  }

  double _resultsViewportHeight(int resultCount) {
    if (resultCount <= 0) {
      return _kNoResultsHeight;
    }
    final visibleCount = math.min(resultCount, _kMaxVisibleRows);
    return visibleCount * _kResultRowHeight +
        ((visibleCount - 1) * _kResultRowSpacing) +
        _kResultListVerticalPadding;
  }

  double _preferredHeightFor({
    required bool hasQuery,
    required int resultCount,
  }) {
    final baseHeight = _kTopSectionHeight +
        _kFooterMarginTop +
        _kFooterHeight +
        _kFooterMarginBottom +
        _kActionRowHeight +
        _kActionRowMarginBottom;
    if (!hasQuery) {
      return baseHeight + _kStandaloneWindowHeightCompensation;
    }
    return baseHeight +
        _resultsViewportHeight(resultCount) +
        _kStandaloneWindowHeightCompensation;
  }

  double _preferredHeightForDetail() {
    final entry = _detailEntry;
    if (entry == null) {
      return _preferredHeightFor(hasQuery: false, resultCount: 0);
    }
    int rows = _computeDetailFieldCount(entry);
    rows = rows.clamp(1, 6);
    return _kTopSectionHeight +
        _kFooterMarginTop +
        (rows * _kDetailFieldRowHeight) +
        _kDetailFieldListPadding +
        _kFooterHeight +
        _kFooterMarginBottom +
        _kActionRowHeight +
        _kActionRowMarginBottom +
        _kStandaloneWindowHeightCompensation;
  }

  double _preferredHeightForGenerator() {
    return _kTopSectionHeight +
        _kGeneratorContentHeight +
        _kFooterMarginTop +
        _kFooterHeight +
        _kFooterMarginBottom +
        _kActionRowHeight +
        _kActionRowMarginBottom +
        _kStandaloneWindowHeightCompensation;
  }

  void _schedulePreferredHeightReport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final callback = widget.onPreferredHeightChanged;
      if (callback == null) {
        return;
      }
      final nextHeight = _showGenerator
          ? _preferredHeightForGenerator()
          : _detailEntry != null
              ? _preferredHeightForDetail()
              : _preferredHeightFor(
                  hasQuery: _queryController.text.trim().isNotEmpty,
                  resultCount: _filteredEntries.length,
                );
      if (_lastPreferredHeight != null &&
          (_lastPreferredHeight! - nextHeight).abs() < 0.5) {
        return;
      }
      _lastPreferredHeight = nextHeight;
      callback(nextHeight);
    });
  }

  void _scrollActiveResultIntoView(int resultCount) {
    if (resultCount <= _kMaxVisibleRows ||
        !_resultsScrollController.hasClients) {
      return;
    }
    final rowExtent = _kResultRowHeight + _kResultRowSpacing;
    final targetTop = _activeIndex * rowExtent;
    final targetBottom = targetTop + _kResultRowHeight;
    final currentTop = _resultsScrollController.offset;
    final currentBottom =
        currentTop + _resultsScrollController.position.viewportDimension;

    double? nextOffset;
    if (targetTop < currentTop) {
      nextOffset = targetTop;
    } else if (targetBottom > currentBottom) {
      nextOffset =
          targetBottom - _resultsScrollController.position.viewportDimension;
    }
    if (nextOffset == null) {
      return;
    }

    final clampedOffset = nextOffset
        .clamp(0, _resultsScrollController.position.maxScrollExtent)
        .toDouble();
    _resultsScrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (_showGenerator) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _exitGenerator();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_detailEntry != null) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() {
          _detailEntry = null;
          _detailFieldIndex = -1;
          _revealedFieldIndices.clear();
        });
        _schedulePreferredHeightReport();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        final count = _computeDetailFieldCount(_detailEntry!);
        if (count > 0) {
          setState(() {
            _detailFieldIndex = (_detailFieldIndex + 1).clamp(0, count - 1);
          });
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _detailFieldIndex = (_detailFieldIndex - 1).clamp(-1, 999);
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        final entry = _detailEntry;
        if (entry != null && _detailFieldIndex >= 0) {
          final field = _getDetailFieldAt(entry, _detailFieldIndex);
          if (field.value.isNotEmpty) {
            unawaited(Clipboard.setData(ClipboardData(text: field.value)));
            widget.onClose();
          }
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }

    final entries = _filteredEntries;
    if (entries.isNotEmpty) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _activeIndex = (_activeIndex + 1).clamp(0, entries.length - 1);
        });
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollActiveResultIntoView(entries.length),
        );
        return KeyEventResult.handled;
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _activeIndex = (_activeIndex - 1).clamp(0, entries.length - 1);
        });
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollActiveResultIntoView(entries.length),
        );
        return KeyEventResult.handled;
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        final active = _activeEntry;
        if (active != null && active.uuid.isNotEmpty) {
          setState(() {
            _detailEntry = active;
            _detailFieldIndex = -1;
            _revealedFieldIndices.clear();
          });
          _schedulePreferredHeightReport();
        }
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.keyC && _isPrimaryModifierDown) {
      if (_isShiftDown) {
        _copyActivePassword();
      } else {
        _copyActiveUsername();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool get _isPrimaryModifierDown {
    final keyboard = HardwareKeyboard.instance;
    return Platform.isMacOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
  }

  bool get _isShiftDown => HardwareKeyboard.instance.isShiftPressed;

  Future<void> _copyActiveUsername() async {
    final username = _activeEntry?.username.trim() ?? '';
    if (username.isEmpty) {
      widget.onShowToast('No username on selected item', danger: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: username));
    widget.onShowToast('Username copied');
  }

  Future<void> _copyActivePassword() async {
    final password = _activeEntry?.password.trim() ?? '';
    if (password.isEmpty) {
      widget.onShowToast('No password on selected item', danger: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: password));
    widget.onShowToast('Password copied');
  }

  void _enterGenerator() {
    setState(() {
      _showGenerator = true;
      _detailEntry = null;
      _detailFieldIndex = -1;
      _revealedFieldIndices.clear();
    });
    if (_generatedPassword.isEmpty) _doRegen();
    _schedulePreferredHeightReport();
  }

  void _exitGenerator() {
    setState(() => _showGenerator = false);
    _schedulePreferredHeightReport();
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
    widget.onShowToast('Password copied');
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
      widget.onShowToast('Choose at least one character set', danger: true);
      return;
    }
    setState(() {
      _genLetters = nextLetters;
      _genNumbers = nextNumbers;
      _genSymbols = nextSymbols;
    });
    _doRegen();
  }

  String _subtitleFor(_MockEntry entry) {
    final username = entry.username.trim();
    if (username.isNotEmpty) {
      return username;
    }

    final website = entry.website.trim();
    if (website.isNotEmpty) {
      return website;
    }

    return entry.subtitle;
  }

  TextStyle _quickText(
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

  /// Builds the ordered list of rows shown in the quick-search detail view.
  ///
  /// [entry.detailFields] is the canonical source for standard fields
  /// (Username/Password/Website and type-specific fields such as Card Number,
  /// Cardholder, etc.). TOTP and Notes are appended because they're stored
  /// separately on the entry and aren't part of `detailFields`.
  List<_QuickSearchDetailRow> _orderedDetailRows(_MockEntry entry) {
    final rows = <_QuickSearchDetailRow>[];

    for (final f in entry.detailFields) {
      rows.add(
        _QuickSearchDetailRow(
          icon: f.icon,
          label: f.label,
          value: f.value,
          isSecret: f.isSecret,
        ),
      );
    }

    if (entry.totpAuthUrl.isNotEmpty) {
      final rawCode = _mockTotpService.generateCode(
            entry.totpAuthUrl,
            timestamp: widget.currentTime,
          ) ??
          '';
      final formattedCode = rawCode.length == 6
          ? '${rawCode.substring(0, 3)} ${rawCode.substring(3)}'
          : rawCode;
      rows.add(
        _QuickSearchDetailRow(
          icon: TablerIcons.clock,
          label: 'OTP',
          value: formattedCode,
          copyValue: rawCode,
          countdownSeconds: _totpSecondsRemaining(entry, widget.currentTime),
        ),
      );
    }

    if (entry.notes.isNotEmpty) {
      rows.add(
        _QuickSearchDetailRow(
          icon: TablerIcons.notes,
          label: 'Notes',
          value: entry.notes,
        ),
      );
    }

    return rows;
  }

  int _computeDetailFieldCount(_MockEntry entry) =>
      _orderedDetailRows(entry).length;

  ({String label, String value}) _getDetailFieldAt(
      _MockEntry entry, int index) {
    final rows = _orderedDetailRows(entry);
    if (index < 0 || index >= rows.length) {
      return (label: '', value: '');
    }
    final row = rows[index];
    return (label: row.label, value: row.copyValue ?? row.value);
  }

  Widget _buildDetailHeader(_MockEntry entry) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF8BA9D8),
            width: 2,
          ),
        ),
        child: Row(
          children: <Widget>[
            GestureDetector(
              onTap: () {
                setState(() {
                  _detailEntry = null;
                  _detailFieldIndex = -1;
                  _revealedFieldIndices.clear();
                });
                _schedulePreferredHeightReport();
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    TablerIcons.arrow_left,
                    color: Color(0xFF0F67D6),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Back',
                    style: _quickText(
                      11,
                      const Color(0xFF0F67D6),
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: const Color(0xFFD0D8E2),
            ),
            _FaviconTile(entry: entry, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.title,
                style: _quickText(
                  13,
                  const Color(0xFF1F2937),
                  weight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailField(
    IconData icon,
    String label,
    String value, {
    bool isSecret = false,
    bool isActive = false,
    bool isRevealed = false,
    VoidCallback? onToggleReveal,
    Color? valueColor,
    String? copyValue,
    int? countdownSeconds,
  }) {
    final bgColor =
        isActive ? const Color(0xFF116CD8) : const Color(0xFFEFF2F6);
    final iconColor = isActive ? Colors.white : const Color(0xFF5E6B7D);
    final labelColor =
        isActive ? const Color(0xFFBDD9FF) : const Color(0xFF7B8A9B);
    final resolvedValueColor =
        valueColor ?? (isActive ? Colors.white : const Color(0xFF252C35));
    final copyIconColor =
        isActive ? const Color(0xFFBDD9FF) : const Color(0xFF8A9BB0);
    final countdownColor = countdownSeconds != null
        ? (isActive
            ? const Color(0xFFBDD9FF)
            : _totpCountdownColor(countdownSeconds))
        : null;
    final displayValue = isSecret && !isRevealed ? '••••••••' : value;

    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: _quickText(
                    9,
                    labelColor,
                    weight: FontWeight.w600,
                  ),
                ),
                Text(
                  displayValue,
                  style: _quickText(
                    11,
                    resolvedValueColor,
                    weight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (countdownSeconds != null && countdownColor != null) ...<Widget>[
            Text(
              countdownSeconds.toString().padLeft(2, '0'),
              style: _quickText(
                11,
                countdownColor,
                weight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (isSecret && onToggleReveal != null) ...<Widget>[
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onToggleReveal,
                child: Icon(
                  isRevealed ? TablerIcons.eye_off : TablerIcons.eye,
                  size: 14,
                  color: copyIconColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () async {
                await Clipboard.setData(
                    ClipboardData(text: copyValue ?? value));
                widget.onShowToast('$label copied');
              },
              child: Icon(
                TablerIcons.copy,
                size: 14,
                color: copyIconColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailFields(_MockEntry entry) {
    final rows = _orderedDetailRows(entry);
    final fields = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final isActive = i == _detailFieldIndex;
      final isRevealed = _revealedFieldIndices.contains(i);
      final countdownSeconds = row.countdownSeconds;
      final valueColor = countdownSeconds != null && !isActive
          ? _totpCountdownColor(countdownSeconds)
          : null;
      fields.add(_buildDetailField(
        row.icon,
        row.label,
        row.value,
        isSecret: row.isSecret,
        isActive: isActive,
        isRevealed: isRevealed,
        onToggleReveal: row.isSecret
            ? () {
                setState(() {
                  if (_revealedFieldIndices.contains(i)) {
                    _revealedFieldIndices.remove(i);
                  } else {
                    _revealedFieldIndices.add(i);
                  }
                });
              }
            : null,
        valueColor: valueColor,
        copyValue: row.copyValue,
        countdownSeconds: countdownSeconds,
      ));
    }
    if (fields.isEmpty) {
      fields.add(
        SizedBox(
          height: 50,
          child: Center(
            child: Text(
              'No details available',
              style: _quickText(
                12,
                const Color(0xFF5E6B7D),
                weight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 240),
        decoration: BoxDecoration(
          color: const Color(0xFFE2E7ED),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD0D8E2)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ListView(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            children: fields,
          ),
        ),
      ),
    );
  }

  Widget _buildGeneratorHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF8BA9D8), width: 2),
        ),
        child: Row(
          children: <Widget>[
            GestureDetector(
              onTap: _exitGenerator,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    TablerIcons.arrow_left,
                    color: Color(0xFF0F67D6),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Back',
                    style: _quickText(
                      11,
                      const Color(0xFF0F67D6),
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: const Color(0xFFD0D8E2),
            ),
            const Icon(
              TablerIcons.shield_lock,
              color: Color(0xFF1F2937),
              size: 16,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Generate Password',
                style: _quickText(
                  13,
                  const Color(0xFF1F2937),
                  weight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratorContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      child: Container(
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
                        style: _quickText(
                          10,
                          active ? Colors.white : const Color(0xFF3A4A5C),
                          weight: FontWeight.w600,
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
                    child: _generatedPassword.isEmpty
                        ? Text(
                            'Generating...',
                            style: _quickText(
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
                                  style: _quickText(
                                    12,
                                    col,
                                    weight: FontWeight.w600,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: _copyGen,
                    child: Icon(
                      _genCopied ? TablerIcons.check : TablerIcons.copy,
                      size: 15,
                      color: _genCopied
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF8A9BB0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _doRegen,
                    child: const Icon(
                      TablerIcons.refresh,
                      size: 15,
                      color: Color(0xFF8A9BB0),
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
                  style: _quickText(
                    10,
                    const Color(0xFF5E6B7D),
                    weight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '$_genLength',
                  style: _quickText(
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
                onChanged: (v) {
                  setState(() => _genLength = v.round());
                  _doRegen();
                },
              ),
            ),
            _buildGenToggle(
              'Letters',
              _genLetters,
              (v) => _toggleGenChar('letters', v),
            ),
            _buildGenToggle(
              'Numbers',
              _genNumbers,
              (v) => _toggleGenChar('numbers', v),
            ),
            _buildGenToggle(
              'Symbols',
              _genSymbols,
              (v) => _toggleGenChar('symbols', v),
              last: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenToggle(
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
              style: _quickText(
                11,
                const Color(0xFF3A4A5C),
                weight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 34,
              height: 18,
              decoration: BoxDecoration(
                color:
                    value ? const Color(0xFF0F67D6) : const Color(0xFFCCD4DF),
                borderRadius: BorderRadius.circular(9),
              ),
              child: AnimatedAlign(
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final standalone = !widget.showBackdrop;
    final hasQuery = _queryController.text.trim().isNotEmpty;
    final results = _filteredEntries;
    final selectedIndex =
        results.isEmpty ? 0 : _activeIndex.clamp(0, results.length - 1);
    final shouldScroll = results.length > _kMaxVisibleRows;
    final resultsHeight = _resultsViewportHeight(results.length);
    _schedulePreferredHeightReport();

    final panel = Container(
      margin: standalone
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16),
      alignment: (standalone && Platform.isMacOS) ? Alignment.topCenter : null,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFE7EBF0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC9D2DE)),
        boxShadow: standalone
            ? null
            : const <BoxShadow>[
                BoxShadow(
                  color: Color(0x3D0F172A),
                  blurRadius: 22,
                  offset: Offset(0, 12),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_showGenerator) ...[
            _buildGeneratorHeader(),
            _buildGeneratorContent(),
          ] else if (_detailEntry != null) ...[
            _buildDetailHeader(_detailEntry!),
            _buildDetailFields(_detailEntry!),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _isSearching
                      ? const Color(0xFFEFF4FA)
                      : const Color(0xFFF7F9FB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF8BA9D8),
                    width: 2,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      TablerIcons.search,
                      color: Color(0xFF0F67D6),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        focusNode: _inputFocusNode,
                        controller: _queryController,
                        readOnly: _isSearching,
                        showCursor: !_isSearching,
                        textAlignVertical: TextAlignVertical.center,
                        cursorColor: const Color(0xFF0F67D6),
                        cursorHeight: 16,
                        cursorWidth: 1.5,
                        onSubmitted: (_) {
                          final active = _activeEntry;
                          if (active != null && active.uuid.isNotEmpty) {
                            setState(() {
                              _detailEntry = active;
                              _detailFieldIndex = -1;
                              _revealedFieldIndices.clear();
                            });
                            _schedulePreferredHeightReport();
                          }
                        },
                        style: _quickText(
                          13,
                          const Color(0xFF1F2937),
                          weight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search LumenPass',
                          hintStyle: _quickText(
                            13,
                            const Color(0xFF6E7783),
                            weight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                          filled: false,
                          fillColor: Colors.transparent,
                        ),
                      ),
                    ),
                    if (_isSearching) ...<Widget>[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF0F67D6),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (hasQuery)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E7ED),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFD0D8E2),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: resultsHeight,
                      child: results.isEmpty
                          ? Center(
                              child: Text(
                                'No matching items',
                                style: _quickText(
                                  12,
                                  const Color(0xFF5E6B7D),
                                  weight: FontWeight.w600,
                                ),
                              ),
                            )
                          : Scrollbar(
                              controller: _resultsScrollController,
                              thumbVisibility: shouldScroll,
                              // ListView.builder + a fixed `itemExtent` lets
                              // the sliver children manager skip layout for
                              // off-screen rows, and lets the scroll engine
                              // jump directly to any pixel offset without
                              // measuring intervening children. The 2px
                              // gap previously rendered by `.separated` is
                              // folded into the row's bottom padding so we
                              // keep the visual rhythm without paying for
                              // an extra widget per gap.
                              child: ListView.builder(
                                controller: _resultsScrollController,
                                physics: shouldScroll
                                    ? const ClampingScrollPhysics()
                                    : const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 6,
                                ),
                                itemCount: results.length,
                                itemExtent:
                                    _kResultRowHeight + _kResultRowSpacing,
                                addAutomaticKeepAlives: false,
                                addRepaintBoundaries: false,
                                itemBuilder: (context, index) {
                                  final entry = results[index];
                                  final isActive = index == selectedIndex;
                                  // Manual RepaintBoundary so each row's
                                  // raster is cached independently — when
                                  // the active row changes (or a TOTP chip
                                  // ticks) only the affected row repaints
                                  // instead of the whole list.
                                  return RepaintBoundary(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: _kResultRowSpacing,
                                      ),
                                      child: _QuickSearchResultRow(
                                        entry: entry,
                                        subtitle: _subtitleFor(entry),
                                        active: isActive,
                                        currentTime: widget.currentTime,
                                        onShowToast: widget.onShowToast,
                                        onHover: () {
                                          if (_activeIndex == index) {
                                            return;
                                          }
                                          setState(() {
                                            _activeIndex = index;
                                          });
                                          _scrollActiveResultIntoView(
                                              results.length);
                                        },
                                        onTap: () {
                                          if (entry.uuid.isNotEmpty) {
                                            setState(() {
                                              _detailEntry = entry;
                                              _detailFieldIndex = -1;
                                              _revealedFieldIndices.clear();
                                            });
                                            _schedulePreferredHeightReport();
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ),
                ),
              ),
          ],
          Container(
            height: _kFooterHeight,
            margin: EdgeInsets.fromLTRB(
              10,
              (hasQuery || _detailEntry != null) ? _kFooterMarginTop : 4,
              10,
              _kFooterMarginBottom,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFDDE4EC),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFFCCD4DF)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: const <Widget>[
                      _QuickSearchShortcutHint(
                        keys: <_QuickSearchKeyCapData>[
                          _QuickSearchKeyCapData.icon(TablerIcons.arrow_up),
                          _QuickSearchKeyCapData.icon(TablerIcons.arrow_down),
                        ],
                        label: 'navigate item',
                      ),
                      _QuickSearchShortcutHint(
                        keys: <_QuickSearchKeyCapData>[
                          _QuickSearchKeyCapData.icon(TablerIcons.arrow_left),
                          _QuickSearchKeyCapData.icon(TablerIcons.arrow_right),
                        ],
                        label: 'forward/back',
                      ),
                      _QuickSearchShortcutHint(
                        keys: <_QuickSearchKeyCapData>[
                          _QuickSearchKeyCapData.text('Enter'),
                        ],
                        label: 'open / copy',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      widget.shortcutDisplay,
                      style: _quickText(
                        10,
                        const Color(0xFF526178),
                        weight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Lumenpass - Your Right Password Manager',
                      style: _quickText(
                        8,
                        const Color(0xFF6E7B8D),
                        weight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            height: _kActionRowHeight,
            margin: const EdgeInsets.fromLTRB(
              10,
              0,
              10,
              _kActionRowMarginBottom,
            ),
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (!_showGenerator) ...[
                  _QuickSearchGenerateButton(onPressed: _enterGenerator),
                  const SizedBox(width: 8),
                ],
                _QuickSearchCloseButton(onPressed: widget.onClose),
                const SizedBox(width: 8),
                if (_detailEntry != null)
                  _QuickSearchEditButton(
                    onPressed: () => widget.onEditItem(_detailEntry!.uuid),
                  )
                else
                  _QuickSearchCreateButton(
                    onPressed: widget.onCreateNewItem,
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    final dismissiblePanel = TapRegion(
      behavior: HitTestBehavior.opaque,
      onTapOutside: (_) => widget.onClose(),
      child: panel,
    );

    final content = Stack(
      children: <Widget>[
        if (widget.showBackdrop)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
            ),
          ),
        if (standalone && Platform.isMacOS)
          Positioned.fill(
            child: Focus(
              focusNode: _scopeFocusNode,
              onKeyEvent: _onKeyEvent,
              child: dismissiblePanel,
            ),
          )
        else if (standalone)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Focus(
              focusNode: _scopeFocusNode,
              onKeyEvent: _onKeyEvent,
              child: dismissiblePanel,
            ),
          )
        else
          Positioned.fill(
            child: Focus(
              focusNode: _scopeFocusNode,
              onKeyEvent: _onKeyEvent,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: 540,
                    maxWidth: 700,
                    maxHeight: _showGenerator ? 460.0 : 420.0,
                  ),
                  child: dismissiblePanel,
                ),
              ),
            ),
          ),
      ],
    );

    return Material(
      color: widget.showBackdrop
          ? const Color(0x260A152B)
          : const Color(0xFFE7EBF0),
      child: widget.showBackdrop ? SafeArea(child: content) : content,
    );
  }
}

class _QuickSearchKeyCapData {
  const _QuickSearchKeyCapData.text(this.text) : icon = null;
  const _QuickSearchKeyCapData.icon(this.icon) : text = null;

  final String? text;
  final IconData? icon;
}

class _QuickSearchShortcutHint extends StatelessWidget {
  const _QuickSearchShortcutHint({
    required this.keys,
    required this.label,
  });

  final List<_QuickSearchKeyCapData> keys;
  final String label;

  TextStyle _hintText(
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

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final key in keys)
          Container(
            margin: const EdgeInsets.only(right: 5),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFEBEEF3),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFC0C9D4)),
            ),
            child: key.icon != null
                ? Icon(
                    key.icon,
                    size: 12,
                    color: const Color(0xFF3E4B60),
                  )
                : Text(
                    key.text ?? '',
                    style: _hintText(
                      10,
                      const Color(0xFF3E4B60),
                      weight: FontWeight.w700,
                    ),
                  ),
          ),
        Text(
          label,
          style: _hintText(
            10,
            const Color(0xFF3B4658),
            weight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _QuickSearchGenerateButton extends StatefulWidget {
  const _QuickSearchGenerateButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_QuickSearchGenerateButton> createState() =>
      _QuickSearchGenerateButtonState();
}

class _QuickSearchGenerateButtonState
    extends State<_QuickSearchGenerateButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onPressed,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF116CD8) : const Color(0xFFEBEEF3),
            borderRadius: BorderRadius.circular(8),
            border:
                _hovered ? null : Border.all(color: const Color(0xFFC0C9D4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                TablerIcons.lock_password,
                size: 13,
                color: _hovered ? Colors.white : const Color(0xFF3E4B60),
              ),
              const SizedBox(width: 6),
              Text(
                'Generate',
                style: TextStyle(
                  fontSize: 10,
                  color: _hovered ? Colors.white : const Color(0xFF3E4B60),
                  fontWeight: FontWeight.w700,
                  fontFamily: currentFontFamily,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickSearchCloseButton extends StatefulWidget {
  const _QuickSearchCloseButton({
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  State<_QuickSearchCloseButton> createState() =>
      _QuickSearchCloseButtonState();
}

class _QuickSearchCloseButtonState extends State<_QuickSearchCloseButton> {
  bool _hovered = false;

  TextStyle _buttonText(
    double size,
    Color color, {
    FontWeight weight = FontWeight.w600,
  }) {
    return TextStyle(
      fontSize: size,
      color: color,
      fontWeight: weight,
      fontFamily: currentFontFamily,
    );
  }

  @override
  Widget build(BuildContext context) {
    const borderColor = Color(0xFFC0C9D4);
    final backgroundColor =
        _hovered ? const Color(0xFFE7EDF5) : const Color(0xFFEBEEF3);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onPressed,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Center(
            child: Text(
              'Close',
              style: _buttonText(
                10,
                const Color(0xFF3E4B60),
                weight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickSearchCreateButton extends StatefulWidget {
  const _QuickSearchCreateButton({
    required this.onPressed,
  });

  final Future<void> Function() onPressed;

  @override
  State<_QuickSearchCreateButton> createState() =>
      _QuickSearchCreateButtonState();
}

class _QuickSearchCreateButtonState extends State<_QuickSearchCreateButton> {
  bool _hovered = false;

  TextStyle _buttonText(
    double size,
    Color color, {
    FontWeight weight = FontWeight.w600,
  }) {
    return TextStyle(
      fontSize: size,
      color: color,
      fontWeight: weight,
      fontFamily: currentFontFamily,
    );
  }

  @override
  Widget build(BuildContext context) {
    const baseColor = Color(0xFF0B4C5D);
    const hoverColor = Color(0xFF0E5E74);
    final backgroundColor = _hovered ? hoverColor : baseColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: () {
          unawaited(widget.onPressed());
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: backgroundColor.withValues(alpha: 0.22),
                blurRadius: _hovered ? 12 : 6,
                offset: Offset(0, _hovered ? 4 : 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(TablerIcons.plus, size: 13, color: Colors.white),
              const SizedBox(width: 7),
              Text(
                'Create New Item',
                style: _buttonText(10, Colors.white, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickSearchEditButton extends StatefulWidget {
  const _QuickSearchEditButton({
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  State<_QuickSearchEditButton> createState() => _QuickSearchEditButtonState();
}

class _QuickSearchEditButtonState extends State<_QuickSearchEditButton> {
  bool _hovered = false;

  TextStyle _buttonText(
    double size,
    Color color, {
    FontWeight weight = FontWeight.w600,
  }) {
    return TextStyle(
      fontSize: size,
      color: color,
      fontWeight: weight,
      fontFamily: currentFontFamily,
    );
  }

  @override
  Widget build(BuildContext context) {
    const baseColor = Color(0xFF0B4C5D);
    const hoverColor = Color(0xFF0E5E74);
    final backgroundColor = _hovered ? hoverColor : baseColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onPressed,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: backgroundColor.withValues(alpha: 0.22),
                blurRadius: _hovered ? 12 : 6,
                offset: Offset(0, _hovered ? 4 : 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(TablerIcons.pencil, size: 13, color: Colors.white),
              const SizedBox(width: 7),
              Text(
                'Edit',
                style: _buttonText(10, Colors.white, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickSearchResultRow extends StatelessWidget {
  const _QuickSearchResultRow({
    required this.entry,
    required this.subtitle,
    required this.active,
    required this.currentTime,
    required this.onHover,
    required this.onTap,
    required this.onShowToast,
  });

  final _MockEntry entry;
  final String subtitle;
  final bool active;
  final DateTime currentTime;
  final VoidCallback onHover;
  final VoidCallback onTap;
  final ValueChanged<String> onShowToast;

  TextStyle _rowText(
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

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        active ? const Color(0xFF116CD8) : const Color(0x00FFFFFF);
    final titleColor = active ? Colors.white : const Color(0xFF252C35);
    final subtitleColor =
        active ? const Color(0xFFDCEAFF) : const Color(0xFF616A77);

    final hasTotpUrl = entry.totpAuthUrl.isNotEmpty;
    final totpCode = hasTotpUrl ? _formattedTotpCode(entry, currentTime) : null;
    final totpSecs =
        hasTotpUrl ? _totpSecondsRemaining(entry, currentTime) : null;
    final totpColor = totpSecs != null
        ? (active ? const Color(0xFFDCEAFF) : _totpCountdownColor(totpSecs))
        : null;

    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: <Widget>[
                _FaviconTile(entry: entry, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: entry.title,
                          style: _rowText(
                            11,
                            titleColor,
                            weight: FontWeight.w700,
                          ),
                        ),
                        const TextSpan(text: ' - '),
                        TextSpan(
                          text: subtitle,
                          style: _rowText(
                            11,
                            subtitleColor,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasTotpUrl || entry.hasPasskeyChip) ...<Widget>[
                  const SizedBox(width: 8),
                  if (hasTotpUrl && totpCode != null && totpColor != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: totpColor.withValues(
                          alpha: active ? 0.25 : 0.12,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            TablerIcons.clock,
                            size: 10,
                            color: totpColor,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            totpCode,
                            style: _rowText(
                              10,
                              totpColor,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (entry.hasPasskeyChip) ...<Widget>[
                    if (hasTotpUrl) const SizedBox(width: 4),
                    // Cap raster decode to ~2× logical size. Without
                    // cacheWidth/cacheHeight Flutter decodes the full asset
                    // resolution (often 256+px) for every visible passkey
                    // row, which is wasted GPU memory and a measurable
                    // scroll-frame cost.
                    Image.asset(
                      'assets/images/passkey_icon.png',
                      width: 26,
                      height: 26,
                      cacheWidth: 52,
                      cacheHeight: 52,
                      filterQuality: FilterQuality.medium,
                    ),
                  ],
                ],
                const SizedBox(width: 10),
                if (active && hasTotpUrl && totpCode != null) ...<Widget>[
                  GestureDetector(
                    onTap: () async {
                      final rawCode = _mockTotpService.generateCode(
                            entry.totpAuthUrl,
                            timestamp: currentTime,
                          ) ??
                          '';
                      await Clipboard.setData(ClipboardData(text: rawCode));
                      onShowToast('OTP copied');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCEAFF).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Copy OTP',
                        style: _rowText(
                          10,
                          const Color(0xFFE9F4FF),
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (active && entry.website.trim().isNotEmpty)
                  Text(
                    'Open',
                    style: _rowText(
                      10,
                      const Color(0xFFE9F4FF),
                      weight: FontWeight.w700,
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

String _genPassword({
  required int length,
  required bool letters,
  required bool numbers,
  required bool symbols,
}) {
  const lower = 'abcdefghijkmnopqrstuvwxyz';
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const nums = '23456789';
  const syms = r'!@#$%^&*()-_=+[]{};:,.?';

  final pools = <String>[
    if (letters) lower,
    if (letters) upper,
    if (numbers) nums,
    if (symbols) syms,
  ];
  if (pools.isEmpty) return '';

  final rand = math.Random.secure();
  final combined = pools.join();
  final buf = <String>[];
  for (final pool in pools) {
    buf.add(pool[rand.nextInt(pool.length)]);
  }
  while (buf.length < length) {
    buf.add(combined[rand.nextInt(combined.length)]);
  }
  buf.shuffle(rand);
  return buf.take(length).join();
}

String _genTypeLabel(_GenType t) {
  switch (t) {
    case _GenType.smart:
      return 'Smart';
    case _GenType.memorable:
      return 'Memorable';
    case _GenType.pin:
      return 'PIN';
  }
}

({int length, bool letters, bool numbers, bool symbols}) _genTypeDefaults(
    _GenType t) {
  switch (t) {
    case _GenType.smart:
      return (length: 25, letters: true, numbers: true, symbols: true);
    case _GenType.memorable:
      return (length: 16, letters: true, numbers: true, symbols: false);
    case _GenType.pin:
      return (length: 8, letters: false, numbers: true, symbols: false);
  }
}

class _QuickSearchDetailRow {
  const _QuickSearchDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isSecret = false,
    this.copyValue,
    this.countdownSeconds,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isSecret;
  final String? copyValue;
  final int? countdownSeconds;
}
