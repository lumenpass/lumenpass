import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

const Color _glassInk = Color(0xFF111418);
const Color _glassText = Color(0xFF111418);
const Color _glassHint = Color(0x99888E96);
const Color _glassSurface = Color(0x33FFFFFF);

/// Shared bright-white "liquid glass" configuration.
///
/// This mirrors the settings used by the bottom navigation bar
/// (`home_screen.dart` `_buildExpandedBar`) so the floating circular action
/// buttons render with the same crisp white glass look instead of the dull
/// gray fallback produced when no `settings` are supplied to [GlassButton].
const LiquidGlassSettings _kWhiteGlassSettings = LiquidGlassSettings(
  thickness: 38,
  blur: 2.5,
  chromaticAberration: 0.42,
  lightIntensity: 0.30,
  refractiveIndex: 1.59,
  saturation: 1.18,
  ambientStrength: 0.30,
  lightAngle: 0.75 * math.pi,
  glassColor: Color(0x33FFFFFF),
  shadowElevation: 2.4,
);

/// Foreground ink colour used inside the floating glass surfaces
/// (search field text, action icons, tray toggle).
///
/// Public so callers can construct matching icon colours for
/// [FloatingGlassToolbarAction.icon].
const Color kFloatingGlassToolbarInk = _glassInk;

class FloatingGlassToolbarAction {
  const FloatingGlassToolbarAction({
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
    this.closeTrayOnTap = true,
    this.key,
  });

  final Key? key;
  final String semanticLabel;
  final Widget icon;
  final VoidCallback onTap;
  final bool closeTrayOnTap;
}

/// App-level glass surface backed by `liquid_glass_widgets`.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    required this.height,
    this.borderRadius = 16,
    this.width,
    this.tint,
    this.borderColor,
    this.blurSigma = 20,
    this.highlightOpacity = 0.28,
    this.quality = GlassQuality.standard,
    this.thickness = 28,
    this.chromaticAberration = 0.08,
    this.lightIntensity = 0.65,
    this.saturation = 1.25,
    this.ambientStrength = 1,
    this.refractiveIndex = 1.59,
    this.shadowOpacity = 0.16,
    this.shadowBlurRadius = 18,
    this.shadowSpreadRadius = -5,
    this.useOwnLayer = true,
  });

  final Widget child;
  final double height;
  final double borderRadius;
  final double? width;
  final Color? tint;
  final Color? borderColor;
  final double blurSigma;
  final double highlightOpacity;
  final GlassQuality quality;
  final double thickness;
  final double chromaticAberration;
  final double lightIntensity;
  final double saturation;
  final double ambientStrength;
  final double refractiveIndex;
  final double shadowOpacity;
  final double shadowBlurRadius;
  final double shadowSpreadRadius;
  final bool useOwnLayer;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final glassTint = tint ?? Colors.white.withValues(alpha: 0.24);
    final glassBlur = blurSigma.clamp(2, 14).toDouble();

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: shadowOpacity),
            blurRadius: shadowBlurRadius,
            spreadRadius: shadowSpreadRadius,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: GlassContainer(
          height: height,
          width: width,
          clipBehavior: Clip.antiAlias,
          quality: quality,
          shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
          settings: LiquidGlassSettings(
            blur: glassBlur,
            thickness: thickness,
            glassColor: glassTint,
            chromaticAberration: chromaticAberration,
            lightIntensity: lightIntensity,
            saturation: saturation,
            ambientStrength: ambientStrength,
            refractiveIndex: refractiveIndex,
            lightAngle: 0.75 * math.pi,
          ),
          useOwnLayer: useOwnLayer,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: borderColor ?? _glassInk.withValues(alpha: 0.16),
                      width: 1,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: highlightOpacity),
                        Colors.white.withValues(
                          alpha: (highlightOpacity * 0.07)
                              .clamp(0.0, 1.0)
                              .toDouble(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Material(color: Colors.transparent, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating liquid-glass search/add controls.
///
/// It starts as a single compact action button. Tapping it reveals Search and
/// Add controls, and tapping Search expands the search field leftward.
class FloatingGlassSearchToolbar extends StatefulWidget {
  const FloatingGlassSearchToolbar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onAdd,
    this.actions = const [],
    this.onSearchTap,
    this.searchKey,
    this.addKey,
    this.isLoading = false,
    this.addSemanticLabel = 'Add',
    this.height = 56,
    this.initiallyExpanded = false,
    this.forceActionButtonsVisible = false,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onAdd;
  final List<FloatingGlassToolbarAction> actions;
  final VoidCallback? onSearchTap;
  final GlobalKey? searchKey;
  final GlobalKey? addKey;
  final bool isLoading;
  final String addSemanticLabel;
  final double height;
  final bool initiallyExpanded;
  final bool forceActionButtonsVisible;

  @override
  State<FloatingGlassSearchToolbar> createState() =>
      _FloatingGlassSearchToolbarState();
}

class _FloatingGlassSearchToolbarState
    extends State<FloatingGlassSearchToolbar> {
  static const _gap = 10.0;
  static const _animationDuration = Duration(milliseconds: 320);
  static const _animationCurve = Curves.easeOutCubic;

  late bool _isTrayOpen;
  late bool _isSearchExpanded;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    final hasText = widget.controller.text.trim().isNotEmpty;
    _isTrayOpen = widget.initiallyExpanded || hasText;
    _isSearchExpanded = hasText;
    _focusNode = FocusNode();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant FloatingGlassSearchToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      if (widget.controller.text.trim().isNotEmpty && !_isSearchExpanded) {
        _isTrayOpen = true;
        _isSearchExpanded = true;
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText && (!_isTrayOpen || !_isSearchExpanded)) {
      setState(() {
        _isTrayOpen = true;
        _isSearchExpanded = true;
      });
    }
  }

  void _toggleTray() {
    if (_isTrayOpen) {
      _closeTray();
      return;
    }

    setState(() => _isTrayOpen = true);
  }

  void _closeTray() {
    _focusNode.unfocus();
    setState(() {
      _isTrayOpen = false;
      _isSearchExpanded = false;
    });
  }

  void _toggleSearch() {
    if (!_isTrayOpen) {
      setState(() => _isTrayOpen = true);
    }
    if (_isSearchExpanded) {
      if (widget.controller.text.trim().isEmpty) {
        _focusNode.unfocus();
        setState(() => _isSearchExpanded = false);
        return;
      }
      _focusNode.requestFocus();
      return;
    }

    setState(() => _isSearchExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void _handleSearchTap() {
    final onSearchTap = widget.onSearchTap;
    if (onSearchTap == null) {
      _toggleSearch();
      return;
    }

    _closeTray();
    onSearchTap();
  }

  void _runAction(FloatingGlassToolbarAction action) {
    if (action.closeTrayOnTap) {
      _closeTray();
    }
    action.onTap();
  }

  void _clearSearch() {
    if (widget.controller.text.isEmpty) {
      return;
    }

    widget.controller.clear();
    widget.onChanged('');
    _focusNode.requestFocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSearchField =
            !widget.forceActionButtonsVisible &&
            _isTrayOpen &&
            _isSearchExpanded;
        final showActionButtons =
            widget.forceActionButtonsVisible ||
            (_isTrayOpen && !_isSearchExpanded);
        final trayOpen = widget.forceActionButtonsVisible || _isTrayOpen;
        final fieldWidth = math.max(
          0.0,
          constraints.maxWidth -
              (widget.height * (showSearchField ? 1 : 3)) -
              (_gap * (showSearchField ? 1 : 3)),
        );

        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: _animationDuration,
              curve: _animationCurve,
              width: showSearchField ? fieldWidth : 0,
              height: widget.height,
              child: IgnorePointer(
                ignoring: !showSearchField,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerRight,
                    minWidth: fieldWidth,
                    maxWidth: fieldWidth,
                    minHeight: widget.height,
                    maxHeight: widget.height,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: showSearchField ? 1 : 0,
                      child: SizedBox(
                        width: fieldWidth,
                        child: _buildSearchField(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedContainer(
              duration: _animationDuration,
              curve: _animationCurve,
              width: showSearchField ? _gap : 0,
            ),
            AnimatedSize(
              duration: _animationDuration,
              curve: _animationCurve,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showActionButtons) ...[
                    // The search button is only rendered when the parent does
                    // NOT wire it to an external destination. When [onSearchTap]
                    // is set (e.g. the home screen, which now exposes search via
                    // the bottom bar), the local search button is hidden to
                    // avoid two redundant entry points.
                    if (widget.onSearchTap == null)
                      _buildCircleButton(
                        key: widget.searchKey,
                        semanticLabel: 'Search',
                        icon: widget.isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _glassInk,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.search_rounded,
                                size: 25,
                                color: _glassInk,
                              ),
                        onTap: _handleSearchTap,
                      ),
                    if (widget.onSearchTap == null) const SizedBox(width: _gap),
                    _buildCircleButton(
                      key: widget.addKey,
                      semanticLabel: widget.addSemanticLabel,
                      icon: const Icon(
                        Icons.add_rounded,
                        size: 30,
                        color: _glassInk,
                      ),
                      onTap: widget.onAdd,
                    ),
                    for (final action in widget.actions) ...[
                      const SizedBox(width: _gap),
                      _buildCircleButton(
                        key: action.key,
                        semanticLabel: action.semanticLabel,
                        icon: action.icon,
                        onTap: () => _runAction(action),
                      ),
                    ],
                    const SizedBox(width: _gap),
                  ],
                  _buildCircleButton(
                    key: null,
                    semanticLabel: trayOpen ? 'Close' : 'Open actions',
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: Icon(
                        trayOpen
                            ? Icons.close_rounded
                            : Icons.view_list_rounded,
                        key: ValueKey<bool>(trayOpen),
                        size: 28,
                        color: _glassInk,
                      ),
                    ),
                    onTap: widget.forceActionButtonsVisible
                        ? null
                        : _toggleTray,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final hasText = widget.controller.text.trim().isNotEmpty;

    return GlassSurface(
      height: widget.height,
      borderRadius: widget.height / 2,
      tint: _glassSurface,
      borderColor: Colors.black.withValues(alpha: 0.06),
      blurSigma: 2.5,
      highlightOpacity: 0.045,
      quality: GlassQuality.premium,
      thickness: 38,
      chromaticAberration: 0.42,
      lightIntensity: 0.30,
      saturation: 1.2,
      ambientStrength: 0.30,
      shadowOpacity: 0.18,
      shadowBlurRadius: 20,
      shadowSpreadRadius: -5,
      useOwnLayer: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                onChanged: widget.onChanged,
                readOnly: widget.isLoading,
                showCursor: !widget.isLoading,
                cursorColor: _glassInk,
                style: const TextStyle(
                  color: _glassText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: const TextStyle(
                    color: _glassHint,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (widget.isLoading) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  valueColor: AlwaysStoppedAnimation<Color>(_glassInk),
                ),
              ),
            ] else if (hasText) ...[
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: 'Clear search',
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _clearSearch,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: _glassHint,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required Key? key,
    required String semanticLabel,
    required Widget icon,
    required VoidCallback? onTap,
  }) {
    // Renders through the package's own [GlassButton]. It is given an explicit
    // white-glass [LiquidGlassSettings] (see [_kWhiteGlassSettings]) so it
    // matches the bottom navigation bar. Without this, GlassButton falls back
    // to DefaultButtonSettings, which renders a dull gray surface rather than
    // the intended bright "liquid glass" look. `useOwnLayer` is required for
    // premium quality on a standalone button (the package asserts this) and
    // also self-sizes the button via an internal SizedBox, so it never
    // overflows inside the toolbar's min-width Row.
    //
    // The drop shadow that lifts the button off the list content comes from
    // the package's own `shadowElevation`, which is inverse-clipped to draw
    // only *outside* the glass boundary. A manual BoxShadow behind the button
    // must NOT be used: the glass is translucent, so an external shadow bleeds
    // through it and pools as a gray/black smudge inside the circle.
    final button = GlassButton.custom(
      onTap: onTap ?? () {},
      enabled: onTap != null,
      label: semanticLabel,
      width: widget.height,
      height: widget.height,
      shape: const LiquidOval(),
      settings: _kWhiteGlassSettings,
      useOwnLayer: true,
      quality: GlassQuality.premium,
      child: icon,
    );

    return key != null ? KeyedSubtree(key: key, child: button) : button;
  }
}
