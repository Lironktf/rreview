/// Design tokens. Two palettes (light, dark) over the same semantic names.
/// Rules: docs/DESIGN.md. Neutrals carry the UI; one accent for interaction;
/// classification colours are the only other hues and always mean something.
library;

import 'package:flutter/material.dart';
import 'package:review_core/review_core.dart';

@immutable
class ReviewColors extends ThemeExtension<ReviewColors> {
  const ReviewColors({
    required this.background,
    required this.surface,
    required this.surfaceSunken,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.hairline,
    required this.accent,
    required this.onAccent,
    required this.boardLight,
    required this.boardDark,
    required this.boardCoordinatesOnLight,
    required this.boardCoordinatesOnDark,
    required this.lastMove,
    required this.selected,
    required this.destination,
    required this.check,
    required this.arrowBest,
    required this.arrowUser,
    required this.evalLight,
    required this.evalDark,
    required this.labelBook,
    required this.labelBest,
    required this.labelExcellent,
    required this.labelGood,
    required this.labelInaccuracy,
    required this.labelMistake,
    required this.labelMissedWin,
    required this.labelBlunder,
    required this.success,
    required this.danger,
  });

  final Color background;
  final Color surface;
  final Color surfaceSunken;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color hairline;
  final Color accent;
  final Color onAccent;
  final Color boardLight;
  final Color boardDark;
  final Color boardCoordinatesOnLight;
  final Color boardCoordinatesOnDark;
  final Color lastMove;
  final Color selected;
  final Color destination;
  final Color check;
  final Color arrowBest;
  final Color arrowUser;
  final Color evalLight;
  final Color evalDark;
  final Color labelBook;
  final Color labelBest;
  final Color labelExcellent;
  final Color labelGood;
  final Color labelInaccuracy;
  final Color labelMistake;
  final Color labelMissedWin;
  final Color labelBlunder;
  final Color success;
  final Color danger;

  Color forLabel(MoveLabel l) => switch (l) {
        MoveLabel.book => labelBook,
        MoveLabel.best => labelBest,
        MoveLabel.excellent => labelExcellent,
        MoveLabel.good => labelGood,
        MoveLabel.inaccuracy => labelInaccuracy,
        MoveLabel.mistake => labelMistake,
        MoveLabel.missedWin => labelMissedWin,
        MoveLabel.blunder => labelBlunder,
      };

  static const light = ReviewColors(
    background: Color(0xFFF6F5F2),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEDEBE6),
    textPrimary: Color(0xFF1C1B19),
    textSecondary: Color(0xFF5F5D57),
    textTertiary: Color(0xFF8E8B83),
    hairline: Color(0xFFE3E1DB),
    accent: Color(0xFF2E5EC8),
    onAccent: Color(0xFFFFFFFF),
    boardLight: Color(0xFFF0D9B5),
    boardDark: Color(0xFFB58863),
    boardCoordinatesOnLight: Color(0xFFB58863),
    boardCoordinatesOnDark: Color(0xFFF0D9B5),
    lastMove: Color(0x669BC700),
    selected: Color(0x80145A1E),
    destination: Color(0x4D145A1E),
    check: Color(0x99E0442E),
    arrowBest: Color(0xB32E5EC8),
    arrowUser: Color(0x994A4A4A),
    evalLight: Color(0xFFF2F0EB),
    evalDark: Color(0xFF3A3834),
    labelBook: Color(0xFFA38363),
    labelBest: Color(0xFF3F9E52),
    labelExcellent: Color(0xFF6FAE63),
    labelGood: Color(0xFF8C968A),
    labelInaccuracy: Color(0xFFD9A800),
    labelMistake: Color(0xFFE2792E),
    labelMissedWin: Color(0xFFB8558F),
    labelBlunder: Color(0xFFD64545),
    success: Color(0xFF3F9E52),
    danger: Color(0xFFD64545),
  );

  static const dark = ReviewColors(
    background: Color(0xFF1B1A18),
    surface: Color(0xFF24221F),
    surfaceSunken: Color(0xFF151412),
    textPrimary: Color(0xFFEDEBE5),
    textSecondary: Color(0xFFA8A59C),
    textTertiary: Color(0xFF7B786F),
    hairline: Color(0xFF34322D),
    accent: Color(0xFF7FA3FF),
    onAccent: Color(0xFF0E1A3A),
    boardLight: Color(0xFFD6C1A0),
    boardDark: Color(0xFF977052),
    boardCoordinatesOnLight: Color(0xFF977052),
    boardCoordinatesOnDark: Color(0xFFD6C1A0),
    lastMove: Color(0x669BC700),
    selected: Color(0x80145A1E),
    destination: Color(0x4D145A1E),
    check: Color(0x99E0442E),
    arrowBest: Color(0xB37FA3FF),
    arrowUser: Color(0x99C8C8C8),
    evalLight: Color(0xFFE6E3DC),
    evalDark: Color(0xFF3A3834),
    labelBook: Color(0xFFB8956F),
    labelBest: Color(0xFF5BB46E),
    labelExcellent: Color(0xFF86BE78),
    labelGood: Color(0xFF8E978C),
    labelInaccuracy: Color(0xFFE2B52B),
    labelMistake: Color(0xFFE88A45),
    labelMissedWin: Color(0xFFC96CA3),
    labelBlunder: Color(0xFFE05B5B),
    success: Color(0xFF5BB46E),
    danger: Color(0xFFE05B5B),
  );

  @override
  ReviewColors copyWith() => this;

  @override
  ReviewColors lerp(ReviewColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

/// 4/8-pt spacing scale.
abstract final class Space {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii: two values only.
abstract final class Radii {
  static const double small = 6;
  static const double medium = 10;
}

extension ReviewColorsX on BuildContext {
  ReviewColors get colors => Theme.of(this).extension<ReviewColors>()!;
}

/// Tabular figures for anything numeric that can change.
const tabularFigures = [FontFeature.tabularFigures()];
