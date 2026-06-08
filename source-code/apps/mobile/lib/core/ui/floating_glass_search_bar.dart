import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

const Color _glassInk = Color(0xFF0A3B48);
const Color _glassText = Color(0xFF0A3B48);
const Color _glassHint = Color(0xFF4A6670);

/// iOS 26-style "liquid glass" surface: a translucent fill behind a backdrop
/// blur, a hairline border, a soft drop shadow, and a top-down white highlight
/// to fake light refraction along the edge.
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
  });

  final Widget child;
  final double height;
  final double borderRadius;
  final double? width;
  final Color? tint;
  final Color? borderColor;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: tint ?? Colors.white.withValues(alpha: 0.55),
            borderRadius: radius,
            border: Border.all(
              color: borderColor ?? _glassInk.withValues(alpha: 0.16),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _glassInk.withValues(alpha: 0.18),
                blurRadius: 16,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Top highlight to fake light refraction along the glass edge.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0.0),
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

/// A floating toolbar that pairs a frosted-glass search field on the left with
/// a matching glass "add" button on the right. Meant to be dropped into a
/// [Stack] via [Positioned] so it overlays scrolling content.
class FloatingGlassSearchToolbar extends StatelessWidget {
  const FloatingGlassSearchToolbar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onAdd,
    this.searchKey,
    this.addKey,
    this.isLoading = false,
    this.addSemanticLabel = 'Add',
    this.height = 56,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onAdd;
  final GlobalKey? searchKey;
  final GlobalKey? addKey;
  final bool isLoading;
  final String addSemanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final search = GlassSurface(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, size: 20, color: _glassHint),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                readOnly: isLoading,
                showCursor: !isLoading,
                cursorColor: _glassInk,
                style: const TextStyle(
                  color: _glassText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: hintText,
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
            if (isLoading) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  valueColor: AlwaysStoppedAnimation<Color>(_glassInk),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final addButton = Semantics(
      button: true,
      label: addSemanticLabel,
      child: GlassSurface(
        height: height,
        width: height,
        tint: _glassInk.withValues(alpha: 0.82),
        borderColor: Colors.white.withValues(alpha: 0.28),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onAdd,
          child: const Center(
            child: Icon(Icons.add_rounded, size: 26, color: Colors.white),
          ),
        ),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: searchKey != null
              ? KeyedSubtree(key: searchKey, child: search)
              : search,
        ),
        const SizedBox(width: 10),
        addKey != null
            ? KeyedSubtree(key: addKey, child: addButton)
            : addButton,
      ],
    );
  }
}
