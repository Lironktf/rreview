/// Dependency container exposed to the widget tree.
library;

import 'package:flutter/widgets.dart';
import 'package:review_core/review_core.dart';

import 'analysis_controller.dart';
import 'engine_service.dart';
import 'import_service.dart';
import 'settings_service.dart';

class AppServices {
  AppServices({
    required this.settings,
    required this.engine,
    required this.analysis,
    required this.importer,
  });

  final AppSettings settings;
  final EngineService engine;
  final AnalysisController analysis;
  final ImportService importer;
  OpeningBook? book;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});
  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;

  /// For initState and callbacks: no dependency is registered.
  static AppServices read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
