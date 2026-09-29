part of 'vault_screen.dart';

/// ─────────────────────────────────────────────────────────────────────────

/// The macOS panel only needs searchable/list data until an item is opened.
/// Keep custom fields and passwords in the main isolate until that point.
@visibleForTesting
Map<String, Object?> compactQuickSearchEntry(KdbxEntry entry) {
  final display = _mockEntryFromKdbx(entry);
  return <String, Object?>{
    'uuid': entry.uuid,
    'groupUuid': entry.groupUuid,
    'title': entry.title,
    if (entry.username?.isNotEmpty ?? false) 'username': entry.username,
    if (entry.url?.isNotEmpty ?? false) 'url': entry.url,
    if (entry.notes?.isNotEmpty ?? false) 'notes': entry.notes,
    if (entry.otpAuthUrl?.isNotEmpty ?? false) 'otpAuthUrl': entry.otpAuthUrl,
    if (entry.createdAt != null)
      'createdAt': entry.createdAt!.toIso8601String(),
    if (entry.updatedAt != null)
      'updatedAt': entry.updatedAt!.toIso8601String(),
    if (entry.tags.isNotEmpty) 'tags': entry.tags,
    if (entry.faviconPngBase64 != null)
      'faviconPngBase64': entry.faviconPngBase64,
    'quickItemType': display.itemType.id,
    if (display.subtitle.isNotEmpty) 'quickSubtitle': display.subtitle,
    if (display.hasPasskeyChip) 'quickHasPasskey': true,
    if (display.socialProvider.isNotEmpty)
      'quickSocialProvider': display.socialProvider,
    if (display.cardBrand != null) 'quickCardBrand': display.cardBrand!.name,
  };
}

_MockEntry _mockEntryFromCompactQuickSearchJson(Map<String, dynamic> json) {
  final entry = KdbxEntry.fromJson(json);
  final display = _computeMockEntryFromKdbx(entry);
  _CardBrand? cardBrand;
  for (final candidate in _CardBrand.values) {
    if (candidate.name == json['quickCardBrand']) {
      cardBrand = candidate;
      break;
    }
  }
  return display.copyWith(
    itemType: VaultItemType.fromId(json['quickItemType'] as String? ?? '') ??
        VaultItemType.login,
    subtitle: json['quickSubtitle'] as String? ?? display.subtitle,
    hasPasskeyChip: json['quickHasPasskey'] as bool? ?? false,
    socialProvider: json['quickSocialProvider'] as String? ?? '',
    cardBrand: cardBrand,
    faviconPngBase64: display.faviconPngBase64,
  );
}

/// Isolated Quick Search window (Option A — second Flutter engine)
/// ─────────────────────────────────────────────────────────────────────────
///
/// This widget is the *entire* UI hosted by the second Flutter engine that
/// backs the standalone Quick Search panel (see `quickSearchMain()` in
/// `main.dart` and the `QuickSearchPanel` in `MainFlutterWindow.swift`).
///
/// Because the second engine runs in its own Dart isolate it shares **no**
/// memory with the main app — most importantly it has no access to the
/// decrypted vault. The main engine sends a JSON snapshot over the
/// `lumenpass/quick_search` channel. macOS sends searchable summaries and
/// resolves full entry details on demand; Windows and Linux currently send
/// full entry projections.
///
/// Channel contract (`lumenpass/quick_search`):
///   native → this engine:
///     • `setSnapshot`  (String jsonPayload)  — push the live entry snapshot
///     • `clearSnapshot`                    — drop the hidden panel's entries
///   this engine → native:
///     • `ready`                    — engine booted
///     • `getEntry` (String uuid)   — request full details on macOS
///     • `close`                    — dismiss the panel
///     • `openEntry`   (String uuid)
///     • `editEntry`   (String uuid)
///     • `createItem`
///     • `heightChanged` ({ 'height': double })
///
/// Everything the panel does that does *not* need the vault (search ranking,
/// clipboard copy, password generator, TOTP ticks, favicon fetch) happens
/// locally in this engine. Actions that *do* need the vault (open / edit /
/// create) are relayed to the main engine, which brings its window forward
/// and navigates.
class QuickSearchWindow extends StatelessWidget {
  const QuickSearchWindow({super.key});

  @override
  Widget build(BuildContext context) {
    // Own ProviderScope: `_FaviconTile` is a ConsumerWidget and reads a few
    // providers (auto-fetch toggle, favicon-fetch cache, persistence
    // service). In this engine there is no open database, so the
    // persistence service safely no-ops — favicons still fetch & display,
    // they just aren't written back.
    return const ProviderScope(child: _QuickSearchWindowShell());
  }
}

class _QuickSearchWindowShell extends StatefulWidget {
  const _QuickSearchWindowShell();

  @override
  State<_QuickSearchWindowShell> createState() =>
      _QuickSearchWindowShellState();
}

class _QuickSearchWindowShellState extends State<_QuickSearchWindowShell> {
  static const MethodChannel _channel = MethodChannel('lumenpass/quick_search');

  final ValueNotifier<DateTime> _timeNotifier =
      ValueNotifier<DateTime>(DateTime.now());
  Timer? _ticker;

  // Snapshot-derived state.
  List<_MockEntry> _entries = const <_MockEntry>[];
  bool _compactSnapshot = false;
  String? _initialSelectedUuid;
  bool _initialShowGenerator = false;
  bool _hideCreditCardNumber = true;
  String _shortcutDisplay = '';
  // Bumped on every snapshot so the overlay is rebuilt from scratch (fresh
  // search box, generator state, selection) each time the panel is shown.
  int _snapshotSeq = 0;

  // Local toast overlay (the panel has no access to the main window's toast).
  OverlayEntry? _toastOverlayEntry;
  String? _toastMessage;
  bool _toastIsDanger = false;
  Timer? _toastTimer;
  final GlobalKey<OverlayState> _overlayKey = GlobalKey<OverlayState>();

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeCall);
    // The macOS host waits for this signal before sending the first snapshot.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _channel.invokeMethod<void>('ready');
    });
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _ticker?.cancel();
    _toastTimer?.cancel();
    _removeToastOverlay();
    _timeNotifier.dispose();
    _clearMockEntryCache();
    super.dispose();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'setSnapshot':
        final raw = call.arguments;
        if (raw is String) {
          _applySnapshot(raw);
        }
        return null;
      case 'clearSnapshot':
        _ticker?.cancel();
        _ticker = null;
        if (mounted) {
          setState(() {
            _entries = const <_MockEntry>[];
            _compactSnapshot = false;
            _initialSelectedUuid = null;
            _initialShowGenerator = false;
            _hideCreditCardNumber = true;
            _shortcutDisplay = '';
            _snapshotSeq++;
          });
        }
        _toastTimer?.cancel();
        _toastMessage = null;
        _removeToastOverlay();
        _clearMockEntryCache();
        return null;
      default:
        return null;
    }
  }

  void _applySnapshot(String jsonPayload) {
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(jsonPayload) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    // Appearance globals are read by `_quickText`/`_text` helpers. They must
    // be set before the overlay rebuilds so fonts match the main window.
    final fontFamily = payload['fontFamily'] as String?;
    if (fontFamily != null && fontFamily.isNotEmpty) {
      currentFontFamily = fontFamily;
    }
    final textSizeDelta = payload['textSizeDelta'];
    if (textSizeDelta is int) {
      currentTextSizeDelta = textSizeDelta;
    }

    final rawEntries = payload['entries'];
    final entries = <_MockEntry>[];
    if (rawEntries is List) {
      for (final item in rawEntries) {
        if (item is Map) {
          try {
            final json = Map<String, dynamic>.from(item);
            entries.add(payload['compact'] == true
                ? _mockEntryFromCompactQuickSearchJson(json)
                : _mockEntryFromKdbx(KdbxEntry.fromJson(json)));
          } catch (_) {
            // Skip malformed entries rather than failing the whole snapshot.
          }
        }
      }
    }

    if (!mounted) {
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _timeNotifier.value = DateTime.now();
    });
    setState(() {
      _entries = entries;
      _compactSnapshot = payload['compact'] == true;
      _initialSelectedUuid = payload['initialSelectedUuid'] as String?;
      _initialShowGenerator = payload['initialShowGenerator'] as bool? ?? false;
      _hideCreditCardNumber = payload['hideCreditCardNumber'] as bool? ?? true;
      _shortcutDisplay = payload['shortcutDisplay'] as String? ?? '';
      _snapshotSeq++;
    });
  }

  Future<_MockEntry?> _loadEntry(_MockEntry summary) async {
    if (!_compactSnapshot) return summary;
    try {
      final raw = await _channel.invokeMethod<String>('getEntry', summary.uuid);
      if (raw == null) return null;
      return _computeMockEntryFromKdbx(
        KdbxEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Actions relayed to the main engine ────────────────────────────────

  void _close() {
    _channel.invokeMethod<void>('close');
  }

  void _openEntry(String uuid) {
    _channel.invokeMethod<void>('openEntry', uuid);
  }

  void _editItem(String uuid) {
    _channel.invokeMethod<void>('editEntry', uuid);
  }

  Future<void> _createNewItem() async {
    await _channel.invokeMethod<void>('createItem');
  }

  void _handleHeightChanged(double height) {
    _channel.invokeMethod<void>(
      'heightChanged',
      <String, double>{'height': height},
    );
  }

  // ── Local toast ────────────────────────────────────────────────────────

  void _showToast(String message, {bool danger = false}) {
    _toastTimer?.cancel();
    _toastMessage = message;
    _toastIsDanger = danger || _isDangerToastMessage(message);
    _insertOrUpdateToastOverlay();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      _toastMessage = null;
      _removeToastOverlay();
    });
  }

  bool _isDangerToastMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('unable') ||
        normalized.contains('failed') ||
        normalized.contains('error') ||
        normalized.contains('invalid') ||
        normalized.contains('required') ||
        normalized.contains('unavailable') ||
        normalized.contains('empty');
  }

  void _insertOrUpdateToastOverlay() {
    final overlay = _overlayKey.currentState;
    if (overlay == null || _toastMessage == null) {
      return;
    }
    if (_toastOverlayEntry != null) {
      _toastOverlayEntry!.markNeedsBuild();
      return;
    }
    _toastOverlayEntry = OverlayEntry(
      builder: (_) {
        final message = _toastMessage;
        if (message == null) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          child: SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: _InAppToast(
                    key: ValueKey(
                      '$message-${_toastIsDanger ? 'danger' : 'normal'}',
                    ),
                    message: message,
                    danger: _toastIsDanger,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_toastOverlayEntry!);
  }

  void _removeToastOverlay() {
    _toastOverlayEntry?.remove();
    _toastOverlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(
        fontFamily: currentFontFamily,
        sizeDelta: currentTextSizeDelta,
      ),
      darkTheme: AppTheme.dark(
        fontFamily: currentFontFamily,
        sizeDelta: currentTextSizeDelta,
      ),
      themeMode: ThemeMode.dark,
      home: Overlay(
        key: _overlayKey,
        initialEntries: <OverlayEntry>[
          OverlayEntry(
            builder: (_) => ValueListenableBuilder<DateTime>(
              valueListenable: _timeNotifier,
              builder: (_, currentTime, __) => KeyedSubtree(
                // Fresh key per snapshot → overlay re-inits (focus, generator,
                // cleared query) every time the panel is shown.
                key: ValueKey<int>(_snapshotSeq),
                child: _QuickSearchOverlay(
                  entries: _entries,
                  initialSelectedUuid: _initialSelectedUuid,
                  // No dimmed backdrop — this *is* its own borderless window.
                  showBackdrop: false,
                  onClose: _close,
                  onEntrySelected: _openEntry,
                  onCreateNewItem: _createNewItem,
                  onShowToast: _showToast,
                  onEditItem: _editItem,
                  onLoadEntry: _loadEntry,
                  onPreferredHeightChanged: _handleHeightChanged,
                  currentTime: currentTime,
                  initialShowGenerator: _initialShowGenerator,
                  hideCreditCardNumber: _hideCreditCardNumber,
                  shortcutDisplay: _shortcutDisplay,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
