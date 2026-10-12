/// User settings persisted as one JSON file in the app's support directory.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:review_core/review_core.dart';

enum PieceSet { cburnett, merida, chessnut }

enum BoardStyle { brown, blue, green, grey }

class AppSettings extends ChangeNotifier {
  AppSettings(this._file);

  final File _file;

  ThemeMode themeMode = ThemeMode.system;
  PieceSet pieceSet = PieceSet.cburnett;
  BoardStyle boardStyle = BoardStyle.brown;
  AnalysisPreset preset = AnalysisPreset.standard;
  int threads = 1;
  int hashMb = 16;
  List<String> chesscomUsernames = [];
  bool showBestArrow = true;
  bool showBadges = true;
  bool autoFlipToMe = true;
  bool hasSeenWelcome = false;

  static Future<AppSettings> load(File file) async {
    final s = AppSettings(file);
    try {
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        s.themeMode = ThemeMode.values.firstWhere((m) => m.name == j['themeMode'], orElse: () => ThemeMode.system);
        s.pieceSet = PieceSet.values.firstWhere((p) => p.name == j['pieceSet'], orElse: () => PieceSet.cburnett);
        s.boardStyle = BoardStyle.values.firstWhere((b) => b.name == j['boardStyle'], orElse: () => BoardStyle.brown);
        s.preset = AnalysisPreset.values.firstWhere((p) => p.name == j['preset'], orElse: () => AnalysisPreset.standard);
        s.threads = (j['threads'] as int?)?.clamp(1, 4) ?? 1;
        s.hashMb = (j['hashMb'] as int?)?.clamp(16, 128) ?? 16;
        s.chesscomUsernames = ((j['chesscomUsernames'] as List?) ?? const []).cast<String>();
        s.showBestArrow = j['showBestArrow'] as bool? ?? true;
        s.showBadges = j['showBadges'] as bool? ?? true;
        s.autoFlipToMe = j['autoFlipToMe'] as bool? ?? true;
        s.hasSeenWelcome = j['hasSeenWelcome'] as bool? ?? false;
      }
    } catch (_) {
      // Corrupt settings: fall back to defaults.
    }
    return s;
  }

  AnalysisSettings get analysisSettings => AnalysisSettings.forPreset(preset, threads: threads, hashMb: hashMb);

  Future<void> update(void Function(AppSettings s) change) async {
    change(this);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final j = {
      'themeMode': themeMode.name,
      'pieceSet': pieceSet.name,
      'boardStyle': boardStyle.name,
      'preset': preset.name,
      'threads': threads,
      'hashMb': hashMb,
      'chesscomUsernames': chesscomUsernames,
      'showBestArrow': showBestArrow,
      'showBadges': showBadges,
      'autoFlipToMe': autoFlipToMe,
      'hasSeenWelcome': hasSeenWelcome,
    };
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(j));
  }
}
