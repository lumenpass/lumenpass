import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/vault/application/search_overlay_focus_policy.dart';

/// Faithful model of the vault title bar's search field + suggestions overlay.
///
/// Two platform/framework details matter and are reproduced here:
///
///  * [blursOnOverlayMount] — on Windows, mounting the suggestions
///    `OverlayPortal` transiently blurs the source `TextField`, synchronously
///    firing the field's focus listener.
///  * `FocusNode.requestFocus()` is **asynchronous**: `FocusManager` applies the
///    change in a microtask, i.e. *after* all of the frame's post-frame
///    callbacks have run. The title bar registers a `_syncSearchOverlay`
///    post-frame callback from `build`, so that sync observes the field as still
///    blurred and must not tear the overlay back down.
class _SearchFieldHarness {
  _SearchFieldHarness({
    required this.blursOnOverlayMount,
    required bool restoreFocusAfterShow,
  }) : policy = SearchOverlayFocusPolicy(
          shouldRestoreFocusAfterShow: () => restoreFocusAfterShow,
        );

  factory _SearchFieldHarness.windows() => _SearchFieldHarness(
        blursOnOverlayMount: true,
        restoreFocusAfterShow: true,
      );

  factory _SearchFieldHarness.appleOrLinux() => _SearchFieldHarness(
        blursOnOverlayMount: false,
        restoreFocusAfterShow: false,
      );

  final bool blursOnOverlayMount;
  final SearchOverlayFocusPolicy policy;

  String text = '';
  bool hasFocus = false;
  bool overlayMounted = false;
  int showCalls = 0;
  int hideCalls = 0;
  int refocusCalls = 0;

  final List<VoidCallback> _postFrameCallbacks = <VoidCallback>[];
  bool _focusRequested = false;

  bool get _hasQuery => text.trim().isNotEmpty;

  /// User clicks into the field. Focus changes do not rebuild the title bar.
  void focus() {
    hasFocus = true;
    _sync();
  }

  /// A single key press: controller text changes, `onChanged` syncs, and the
  /// draft provider change schedules a rebuild whose `build` registers another
  /// post-frame sync.
  void type(String character) {
    text += character;
    _sync();
    _postFrameCallbacks.add(_sync);
  }

  /// Ends the frame: post-frame callbacks run synchronously in registration
  /// order, then queued focus requests are applied as microtasks.
  void endFrame() {
    final callbacks = List<VoidCallback>.of(_postFrameCallbacks);
    _postFrameCallbacks.clear();
    for (final callback in callbacks) {
      callback();
    }

    if (_focusRequested) {
      _focusRequested = false;
      if (!hasFocus) {
        hasFocus = true;
        refocusCalls++;
        _sync();
      }
    }
  }

  /// Focus loss that did not come from a dismiss affordance (alt-tab, another
  /// field). Nothing is cancelled, because the user did not dismiss.
  void blur() {
    hasFocus = false;
    _sync();
  }

  /// Enter / Esc / tap-outside / suggestion tap all funnel through the widget's
  /// `_unfocusSearch`.
  void dismiss() {
    policy.cancelFocusRestore();
    _apply(policy.hide());
    hasFocus = false;
    _sync();
  }

  void clearQuery() {
    text = '';
    dismiss();
  }

  void _sync() {
    _apply(policy.sync(hasFocus: hasFocus, hasQuery: _hasQuery));
  }

  void _apply(SearchOverlayAction action) {
    switch (action) {
      case SearchOverlayAction.none:
        break;
      case SearchOverlayAction.show:
        showCalls++;
        overlayMounted = true;
        if (policy.isFocusRestorePending) {
          _scheduleRestore();
        }
        if (blursOnOverlayMount && hasFocus) {
          hasFocus = false;
          _sync();
        }
      case SearchOverlayAction.hide:
        hideCalls++;
        overlayMounted = false;
    }
  }

  void _scheduleRestore() {
    final generation = policy.focusRestoreGeneration;
    _postFrameCallbacks.add(() {
      final shouldRestore = policy.consumeFocusRestore(
        generation,
        hasQuery: _hasQuery,
        hasFocus: hasFocus,
      );
      if (!shouldRestore) {
        return;
      }
      // requestFocus() does not take effect synchronously.
      _focusRequested = true;
    });
  }
}

void main() {
  group('Windows top search box (regression: focus lost on every keystroke)',
      () {
    test('the overlay survives the mount blur and focus comes back', () {
      final harness = _SearchFieldHarness.windows();

      harness.focus();
      harness.type('f');

      expect(harness.overlayMounted, isTrue);
      expect(harness.hideCalls, 0);
      expect(harness.hasFocus, isFalse);

      harness.endFrame();

      expect(harness.hasFocus, isTrue,
          reason: 'focus must return the frame after the overlay mounts');
      expect(harness.refocusCalls, 1);
      expect(harness.overlayMounted, isTrue);
      expect(harness.hideCalls, 0,
          reason: "build's post-frame sync runs before the focus request is "
              'applied — it must not tear the overlay down');
    });

    test('a full word can be typed, mounting the overlay exactly once', () {
      final harness = _SearchFieldHarness.windows();

      harness.focus();
      harness.endFrame();

      for (final character in 'filez'.split('')) {
        harness.type(character);
        harness.endFrame();
        expect(harness.hasFocus, isTrue,
            reason: 'field lost focus while typing "${harness.text}"');
        expect(harness.overlayMounted, isTrue,
            reason: 'overlay flickered while typing "${harness.text}"');
      }

      expect(harness.text, 'filez');
      expect(harness.showCalls, 1,
          reason: 'show() must be idempotent — re-mounting the portal on every '
              'keystroke is what stole focus on Windows');
      expect(harness.hideCalls, 0);
      expect(harness.refocusCalls, 1,
          reason: 'only the initial mount should need a correction');
    });

    test('typing after a dismiss still works', () {
      final harness = _SearchFieldHarness.windows();

      harness.focus();
      harness.type('f');
      harness.endFrame();
      harness.clearQuery();
      harness.endFrame();

      expect(harness.overlayMounted, isFalse);

      harness.focus();
      harness.type('g');
      harness.endFrame();

      expect(harness.hasFocus, isTrue);
      expect(harness.overlayMounted, isTrue);
      expect(harness.showCalls, 2);
    });
  });

  group('Windows dismiss affordances still blur', () {
    test('tap-outside / Enter / suggestion tap cancel the pending correction',
        () {
      final harness = _SearchFieldHarness.windows();

      harness.focus();
      harness.type('f');
      harness.dismiss();
      harness.endFrame();

      expect(harness.hasFocus, isFalse,
          reason: 'the correction must not fight an intentional dismiss');
      expect(harness.refocusCalls, 0);
      expect(harness.overlayMounted, isFalse);
    });

    test('clearing the query hides the overlay', () {
      final harness = _SearchFieldHarness.windows();

      harness.focus();
      harness.type('f');
      harness.endFrame();
      expect(harness.overlayMounted, isTrue);

      harness.clearQuery();
      harness.endFrame();

      expect(harness.overlayMounted, isFalse);
      expect(harness.hideCalls, 1);
    });

    test('a genuine blur after focus settled hides the overlay', () {
      final harness = _SearchFieldHarness.windows();

      harness.focus();
      harness.type('f');
      harness.endFrame();
      expect(harness.overlayMounted, isTrue);
      expect(harness.hasFocus, isTrue);

      harness.blur();

      expect(harness.overlayMounted, isFalse,
          reason: 'with no correction in flight, blur must dismiss normally');
      expect(harness.hideCalls, 1);
    });
  });

  group('macOS / Linux behaviour is unchanged', () {
    test('no focus correction is ever armed or applied', () {
      final harness = _SearchFieldHarness.appleOrLinux();

      harness.focus();
      harness.endFrame();

      for (final character in 'filez'.split('')) {
        harness.type(character);
        harness.endFrame();
      }

      expect(harness.hasFocus, isTrue);
      expect(harness.showCalls, 1);
      expect(harness.hideCalls, 0);
      expect(harness.refocusCalls, 0,
          reason: 'off Windows the overlay never steals focus, so the field '
              'must never be re-focused programmatically');
      expect(harness.policy.isFocusRestorePending, isFalse);
    });

    test('blur dismisses immediately, with no grace frame', () {
      final harness = _SearchFieldHarness.appleOrLinux();

      harness.focus();
      harness.type('f');
      expect(harness.overlayMounted, isTrue);

      harness.blur();

      expect(harness.overlayMounted, isFalse);
      expect(harness.hideCalls, 1);
    });
  });

  group('SearchOverlayFocusPolicy', () {
    SearchOverlayFocusPolicy windowsPolicy() =>
        SearchOverlayFocusPolicy(shouldRestoreFocusAfterShow: () => true);

    test('show is emitted only on a real visibility transition', () {
      final policy = windowsPolicy();

      expect(policy.sync(hasFocus: true, hasQuery: true),
          SearchOverlayAction.show);
      expect(policy.sync(hasFocus: true, hasQuery: true),
          SearchOverlayAction.none);
      expect(policy.sync(hasFocus: true, hasQuery: true),
          SearchOverlayAction.none);
      expect(policy.isOverlayShown, isTrue);
    });

    test('hide is idempotent', () {
      final policy = windowsPolicy();

      expect(policy.hide(), SearchOverlayAction.none);
      policy.sync(hasFocus: true, hasQuery: true);
      expect(policy.hide(), SearchOverlayAction.hide);
      expect(policy.hide(), SearchOverlayAction.none);
    });

    test('an empty query hides even while a correction is pending', () {
      final policy = windowsPolicy();

      policy.sync(hasFocus: true, hasQuery: true);
      expect(policy.isFocusRestorePending, isTrue);

      expect(policy.sync(hasFocus: true, hasQuery: false),
          SearchOverlayAction.hide);
    });

    test('cancelFocusRestore invalidates a scheduled correction', () {
      final policy = windowsPolicy();

      policy.sync(hasFocus: true, hasQuery: true);
      final generation = policy.focusRestoreGeneration;

      policy.cancelFocusRestore();

      expect(policy.isFocusRestorePending, isFalse);
      expect(
        policy.consumeFocusRestore(
          generation,
          hasQuery: true,
          hasFocus: false,
        ),
        isFalse,
      );
    });

    test('a newer correction supersedes an older one', () {
      final policy = windowsPolicy();

      policy.sync(hasFocus: true, hasQuery: true);
      final stale = policy.focusRestoreGeneration;

      policy.cancelFocusRestore();
      policy.hide();
      policy.sync(hasFocus: true, hasQuery: true);
      final fresh = policy.focusRestoreGeneration;

      expect(fresh, isNot(stale));
      expect(
        policy.consumeFocusRestore(stale, hasQuery: true, hasFocus: false),
        isFalse,
      );
      expect(
        policy.consumeFocusRestore(fresh, hasQuery: true, hasFocus: false),
        isTrue,
      );
    });

    test('a correction is dropped when the query emptied out', () {
      final policy = windowsPolicy();

      policy.sync(hasFocus: true, hasQuery: true);

      expect(
        policy.consumeFocusRestore(
          policy.focusRestoreGeneration,
          hasQuery: false,
          hasFocus: false,
        ),
        isFalse,
      );
      expect(policy.isFocusRestorePending, isFalse);
    });

    test('a correction is a no-op when the mount did not steal focus', () {
      final policy = windowsPolicy();

      policy.sync(hasFocus: true, hasQuery: true);

      expect(
        policy.consumeFocusRestore(
          policy.focusRestoreGeneration,
          hasQuery: true,
          hasFocus: true,
        ),
        isFalse,
      );
      expect(policy.isFocusRestorePending, isFalse);
      expect(policy.isAwaitingFocusReturn, isFalse);
    });

    test('the overlay is guarded until a requested focus actually lands', () {
      final policy = windowsPolicy();

      policy.sync(hasFocus: true, hasQuery: true);
      final generation = policy.focusRestoreGeneration;

      // The mount stole focus; the correction asks for it back.
      expect(
        policy.consumeFocusRestore(
          generation,
          hasQuery: true,
          hasFocus: false,
        ),
        isTrue,
      );
      expect(policy.isFocusRestorePending, isFalse);
      expect(policy.isAwaitingFocusReturn, isTrue);

      // build()'s post-frame sync runs next, still observing a blurred field.
      expect(
        policy.sync(hasFocus: false, hasQuery: true),
        SearchOverlayAction.none,
        reason: 'the overlay must not be torn down while focus is in flight',
      );
      expect(policy.isOverlayShown, isTrue);

      // FocusManager applies the change in a microtask.
      expect(policy.sync(hasFocus: true, hasQuery: true),
          SearchOverlayAction.none);
      expect(policy.isAwaitingFocusReturn, isFalse);

      // Guard released: a later genuine blur dismisses normally.
      expect(policy.sync(hasFocus: false, hasQuery: true),
          SearchOverlayAction.hide);
    });

    test('a correction is dropped when the overlay was already hidden', () {
      final policy = windowsPolicy();

      policy.sync(hasFocus: true, hasQuery: true);
      final generation = policy.focusRestoreGeneration;
      policy.hide();

      expect(
        policy.consumeFocusRestore(
          generation,
          hasQuery: true,
          hasFocus: false,
        ),
        isFalse,
      );
    });

    test('arms the correction on Windows by default', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final policy = SearchOverlayFocusPolicy();

      expect(policy.sync(hasFocus: true, hasQuery: true),
          SearchOverlayAction.show);
      expect(policy.isFocusRestorePending, isTrue);
    });

    for (final platform in <TargetPlatform>[
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      test('does not arm the correction on $platform by default', () {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        final policy = SearchOverlayFocusPolicy();

        expect(policy.sync(hasFocus: true, hasQuery: true),
            SearchOverlayAction.show);
        expect(policy.isFocusRestorePending, isFalse);
        expect(policy.sync(hasFocus: false, hasQuery: true),
            SearchOverlayAction.hide);
      });
    }

    test('resolves the platform per transition, not at construction', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final policy = SearchOverlayFocusPolicy();

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      policy.sync(hasFocus: true, hasQuery: true);

      expect(policy.isFocusRestorePending, isTrue);
    });
  });
}
