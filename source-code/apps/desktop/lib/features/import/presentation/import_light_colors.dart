import 'package:flutter/painting.dart';

import '../../../presentation/theme/drive_clue_tokens.dart';

/// Import-flow colors: readable light content with the desktop's slate title bar.
abstract final class ImportColors {
  static const Color header = DcColors.background;
  static const Color headerText = DcColors.text;
  static const Color headerMuted = DcColors.muted;
  static const Color headerIconSurface = DcColors.panel;

  static const Color panel = DcColors.lightSurface;
  static const Color row = DcColors.lightInset;
  static const Color rowAlternate = DcColors.lightSurface;
  static const Color text = DcColors.sidebarText;
  static const Color muted = DcColors.sidebarMuted;
  static const Color faint = DcColors.sidebarMuted;
  static const Color line = DcColors.sidebarLine;
  static const Color lineStrong = DcColors.lightLineStrong;
  static const Color shadow = DcColors.lightCardShadow;
  static const Color selection = DcColors.selection;
  static const Color selectionSoft = DcColors.lightSelectionFill;
  static const Color green = Color(0xFF27804C);
  static const Color greenSoft = Color(0xFFE9F5ED);
  static const Color red = DcColors.redOnLight;
  static const Color redSoft = Color(0xFFFFEDEC);
  static const Color redLine = Color(0x59D64541);
  static const Color amber = DcColors.amberOnLight;
  static const Color teal = DcColors.tealOnLight;
}
