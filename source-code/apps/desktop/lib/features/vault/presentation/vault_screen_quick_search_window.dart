part of 'vault_screen.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Isolated Quick Search window (Option A — second Flutter engine)
/// ─────────────────────────────────────────────────────────────────────────
///
/// This widget is the *entire* UI hosted by the second Flutter engine that
/// backs the standalone Quick Search panel (see `quickSearchMain()` in
/// `main.dart` and the `QuickSearchPanel` in `MainFlutterWindow.swift`).
///
/// Because the second engine runs in its own Dart isolate it shares **no**
/// memory with the main app — most importantly it has no access to the
/// decrypted vault. The main engine therefore serialises the current entry
/// projection (`KdbxEntry`, which is `freezed` + `json_serializable`) into a
/// JSON snapshot and pushes it over the `lumenpass/quick_search` method
/// channel. Here we rebuild the identical `_MockEntry` list via
/// `_mockEntryFromKdbx`, so the panel renders byte-for-byte the same overlay
/// the in-window path renders — no colours, icons or detail-field metadata
/// have to cross the isolate boundary.
///
/// Channel contract (`lumenpass/quick_search`):
///   native → this engine:
///     • `setSnapshot`  (String jsonPayload)  — push the live entry snapshot
///   this engine → native:
///     • `ready`                    — engine booted, request a snapshot
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
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _timeNotifier.value = DateTime.now();
    });
    // Tell native we're up so it can push the first snapshot even before the
    // user opens the panel (keeps the first open instant).
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
            final kdbx = KdbxEntry.fromJson(Map<String, dynamic>.from(item));
            entries.add(_mockEntryFromKdbx(kdbx));
          } catch (_) {
            // Skip malformed entries rather than failing the whole snapshot.
          }
        }
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _entries = entries;
      _initialSelectedUuid = payload['initialSelectedUuid'] as String?;
      _initialShowGenerator = payload['initialShowGenerator'] as bool? ?? false;
      _hideCreditCardNumber = payload['hideCreditCardNumber'] as bool? ?? true;
      _shortcutDisplay = payload['shortcutDisplay'] as String? ?? '';
      _snapshotSeq++;
    });
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
