/// Analysis depth presets and engine resource settings.
library;

enum AnalysisPreset { quick, standard, deep }

class AnalysisSettings {
  const AnalysisSettings({
    required this.preset,
    required this.passDepth,
    required this.refineDepth,
    required this.refineBudget,
    this.threads = 1,
    this.hashMb = 16,
  });

  final AnalysisPreset preset;

  /// Depth for the first pass over every position.
  final int passDepth;

  /// Depth for the second pass over flagged positions (0 disables refinement).
  final int refineDepth;

  /// Maximum share of positions (0..1) refined in the second pass.
  final double refineBudget;
  final int threads;
  final int hashMb;

  static const quick =
      AnalysisSettings(preset: AnalysisPreset.quick, passDepth: 12, refineDepth: 16, refineBudget: 0.15);
  static const standard =
      AnalysisSettings(preset: AnalysisPreset.standard, passDepth: 16, refineDepth: 20, refineBudget: 0.25);
  static const deep =
      AnalysisSettings(preset: AnalysisPreset.deep, passDepth: 20, refineDepth: 24, refineBudget: 0.35);

  static AnalysisSettings forPreset(AnalysisPreset p, {int threads = 1, int hashMb = 16}) {
    final base = switch (p) {
      AnalysisPreset.quick => quick,
      AnalysisPreset.standard => standard,
      AnalysisPreset.deep => deep,
    };
    return base.copyWith(threads: threads, hashMb: hashMb);
  }

  AnalysisSettings copyWith({int? threads, int? hashMb}) => AnalysisSettings(
        preset: preset,
        passDepth: passDepth,
        refineDepth: refineDepth,
        refineBudget: refineBudget,
        threads: threads ?? this.threads,
        hashMb: hashMb ?? this.hashMb,
      );

  String get label => switch (preset) {
        AnalysisPreset.quick => 'Quick',
        AnalysisPreset.standard => 'Standard',
        AnalysisPreset.deep => 'Deep',
      };

  Map<String, dynamic> toJson() => {
        'preset': preset.name,
        'passDepth': passDepth,
        'refineDepth': refineDepth,
        'refineBudget': refineBudget,
        'threads': threads,
        'hashMb': hashMb,
      };

  static AnalysisSettings fromJson(Map<String, dynamic> j) => AnalysisSettings(
        preset: AnalysisPreset.values.firstWhere((p) => p.name == j['preset'], orElse: () => AnalysisPreset.standard),
        passDepth: j['passDepth'] as int,
        refineDepth: j['refineDepth'] as int,
        refineBudget: (j['refineBudget'] as num).toDouble(),
        threads: j['threads'] as int? ?? 1,
        hashMb: j['hashMb'] as int? ?? 16,
      );
}
