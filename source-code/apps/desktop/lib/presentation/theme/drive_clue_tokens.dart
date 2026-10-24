import 'package:flutter/painting.dart';

/// Design tokens for the DriveClue-inspired desktop look:
/// a light blue-gray sidebar, a dark slate content area, rounded-7 panels,
/// striped table rows and a gray status bar.
///
/// Values mirror `DiagnosticTheme` in DriveClue's `App/Theme.swift`.
abstract final class DcColors {
  // ── Sidebar (light) ───────────────────────────────────────────────────────
  static const Color sidebar = Color(0xFFE3EBF2);
  static const Color sidebarText = Color(0xFF263340);
  static const Color sidebarMuted = Color(0xFF6B7D8C);

  /// `sidebarMuted @ 22%`: hairlines inside the sidebar.
  static const Color sidebarLine = Color(0x386B7D8C);

  /// Hover wash for sidebar rows.
  static const Color sidebarHover = Color(0x1F3882C2);

  // ── Light surfaces (sidebar-toned dialogs and panels) ─────────────────────
  /// Cards, inputs and bordered buttons sitting on the [sidebar] color.
  static const Color lightSurface = Color(0xFFFFFFFF);

  /// Very light blue-gray for rows nested inside a [lightSurface] card.
  static const Color lightInset = Color(0xFFF3F6F9);

  /// `sidebarMuted @ 35%`: outlines of controls on light surfaces.
  static const Color lightLineStrong = Color(0x596B7D8C);

  /// `selection @ 10%`: selected card fill on light surfaces.
  static const Color lightSelectionFill = Color(0x1A3882C2);

  /// Darker red that stays readable on white and [sidebar].
  static const Color redOnLight = Color(0xFFD64541);

  /// Darker teal for "healthy" text on light surfaces.
  static const Color tealOnLight = Color(0xFF1F8A7D);

  /// Darker amber for warning text on light surfaces.
  static const Color amberOnLight = Color(0xFF9C7200);

  /// Soft drop shadow for white cards on the [sidebar] color.
  static const Color lightCardShadow = Color(0x14263340);

  // ── Selection / brand ─────────────────────────────────────────────────────
  static const Color selection = Color(0xFF3882C2);
  static const Color selectionHover = Color(0xFF2F73AE);

  /// `selection @ 22%`: tinted fills on dark slate (chips, focus wash).
  static const Color selectionSoft = Color(0x383882C2);

  /// `selection @ 38%`: hovered tinted fills.
  static const Color selectionTint = Color(0x613882C2);

  // ── Content (dark slate) ──────────────────────────────────────────────────
  static const Color background = Color(0xFF4A545C);
  static const Color panel = Color(0xFF616B73);
  static const Color row = Color(0xFF5C666E);
  static const Color rowAlternate = Color(0xFF545E66);

  /// Slightly lifted panel used for hovered rows and inputs inside panels.
  static const Color panelRaised = Color(0xFF6A747C);

  /// Recessed surface used for inputs and code wells.
  static const Color well = Color(0xFF434C53);

  static const Color text = Color(0xFFF5F7FA);
  static const Color muted = Color(0xFFC2CCD4);

  /// Dimmer than [muted]: placeholders, disabled glyphs.
  static const Color faint = Color(0xFF97A3AD);

  /// `white @ 13%`: hairlines on dark slate.
  static const Color line = Color(0x21FFFFFF);

  /// `white @ 22%`: stronger outlines (bordered buttons, inputs).
  static const Color lineStrong = Color(0x38FFFFFF);

  /// `black @ 25%`: the shell divider between sidebar and content.
  static const Color shellDivider = Color(0x40000000);

  // ── Status bar ────────────────────────────────────────────────────────────
  static const Color footer = Color(0xFFC2C9CF);

  // ── Status ────────────────────────────────────────────────────────────────
  static const Color green = Color(0xFF6ED433);
  static const Color amber = Color(0xFFFAC733);
  static const Color deepOrange = Color(0xFFF28533);
  static const Color red = Color(0xFFF75C57);

  // ── Accents ───────────────────────────────────────────────────────────────
  static const Color teal = Color(0xFF47C7B8);
  static const Color orange = Color(0xFFFC9942);
  static const Color purple = Color(0xFFB38FF2);
  static const Color rose = Color(0xFFF57094);
  static const Color cyan = Color(0xFF5CBDEB);
  static const Color indigo = Color(0xFF9499F5);

  // ── Soft status fills (status @ 20%) for banners and chips on slate ─────
  static const Color redSoft = Color(0x33F75C57);
  static const Color greenSoft = Color(0x336ED433);
  static const Color amberSoft = Color(0x33FAC733);
  static const Color tealSoft = Color(0x3347C7B8);

  /// Status borders (status @ 40%).
  static const Color redLine = Color(0x66F75C57);
  static const Color greenLine = Color(0x666ED433);
  static const Color amberLine = Color(0x66FAC733);
  static const Color tealLine = Color(0x6647C7B8);
  static const Color selectionLine = Color(0x663882C2);

  /// Readable blue for links and accent text on slate.
  static const Color link = Color(0xFF8CC4F2);

  /// Track behind thin progress bars (`black @ 25%`).
  static const Color barTrack = Color(0x40000000);

  /// Modal backdrop over the dark slate window.
  static const Color scrim = Color(0x8C1E252B);

  /// Lighter backdrop for in-dialog pickers and popovers.
  static const Color scrimSoft = Color(0x4D1E252B);

  /// Drop shadow under panels, dialogs and menus.
  static const Color shadow = Color(0x40000000);

  /// Softer drop shadow for small raised controls.
  static const Color shadowSoft = Color(0x26000000);
}

/// Shape and size constants shared by DriveClue-style widgets.
abstract final class DcMetrics {
  static const double panelRadius = 7;
  static const double controlRadius = 6;
  static const double badgeRadius = 4;
  static const double panelPadding = 14;

  static const double sidebarWidth = 244;
  static const double headerHeight = 46;
  static const double statusBarHeight = 28;
  static const double tableHeaderHeight = 27;
  static const double sidebarRowHeight = 29;

  static const double sectionLabelSize = 11;
  static const double sectionLabelTracking = 0.8;
}
