import 'package:flutter/material.dart';
import 'package:review_core/review_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_scope.dart';
import '../services/engine_service.dart';
import '../services/settings_service.dart';
import '../theme/tokens.dart';
import 'about_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: Listenable.merge([s.settings, s.engine.state]),
        builder: (context, _) {
          final st = s.settings;
          return ListView(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xxl),
            children: [
              _header(context, 'Analysis'),
              _card(context, [
                _row(
                  context,
                  'Depth',
                  SegmentedButton<AnalysisPreset>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: AnalysisPreset.quick, label: Text('Quick')),
                      ButtonSegment(value: AnalysisPreset.standard, label: Text('Standard')),
                      ButtonSegment(value: AnalysisPreset.deep, label: Text('Deep')),
                    ],
                    selected: {st.preset},
                    onSelectionChanged: (v) => st.update((x) => x.preset = v.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
                  child: Text(
                    switch (st.preset) {
                      AnalysisPreset.quick => 'Depth 12 for every move, 16 for key moments. About a minute per game.',
                      AnalysisPreset.standard => 'Depth 16 for every move, 20 for key moments. A few minutes per game.',
                      AnalysisPreset.deep => 'Depth 20 for every move, 24 for key moments. Can take a long time and drains battery.',
                    },
                    style: t.bodySmall,
                  ),
                ),
                const Divider(),
                _row(
                  context,
                  'Engine threads',
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1')),
                      ButtonSegment(value: 2, label: Text('2')),
                      ButtonSegment(value: 4, label: Text('4')),
                    ],
                    selected: {st.threads},
                    onSelectionChanged: (v) {
                      st.update((x) => x.threads = v.first);
                      s.engine.applyResources(threads: v.first, hashMb: st.hashMb);
                    },
                  ),
                ),
                _row(
                  context,
                  'Hash table',
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 16, label: Text('16 MB')),
                      ButtonSegment(value: 32, label: Text('32 MB')),
                      ButtonSegment(value: 64, label: Text('64 MB')),
                    ],
                    selected: {st.hashMb},
                    onSelectionChanged: (v) {
                      st.update((x) => x.hashMb = v.first);
                      s.engine.applyResources(threads: st.threads, hashMb: v.first);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
                  child: Text('One thread and 16 MB keep the phone cool. More threads analyse faster.', style: t.bodySmall),
                ),
              ]),
              _header(context, 'Chess.com'),
              _card(context, [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.xs),
                  child: Text(
                    'Game links are resolved through Chess.com\'s public game archives, which are organised by player. '
                    'Add the usernames you play under (no login needed).',
                    style: t.bodySmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.m),
                  child: Wrap(
                    spacing: Space.s,
                    runSpacing: Space.s,
                    children: [
                      for (final u in st.chesscomUsernames)
                        InputChip(
                          label: Text(u),
                          onDeleted: () => st.update((x) => x.chesscomUsernames = x.chesscomUsernames.where((e) => e != u).toList()),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add username'),
                        onPressed: () => _addUsername(context, st),
                      ),
                    ],
                  ),
                ),
              ]),
              _header(context, 'Review'),
              _card(context, [
                SwitchListTile(
                  title: const Text('Best-move arrow'),
                  subtitle: const Text('Show the engine\'s alternative on mistakes'),
                  value: st.showBestArrow,
                  onChanged: (v) => st.update((x) => x.showBestArrow = v),
                ),
                SwitchListTile(
                  title: const Text('Move labels on the board'),
                  value: st.showBadges,
                  onChanged: (v) => st.update((x) => x.showBadges = v),
                ),
                SwitchListTile(
                  title: const Text('Show my side at the bottom'),
                  subtitle: const Text('Uses your Chess.com usernames'),
                  value: st.autoFlipToMe,
                  onChanged: (v) => st.update((x) => x.autoFlipToMe = v),
                ),
              ]),
              _header(context, 'Appearance'),
              _card(context, [
                _row(
                  context,
                  'Theme',
                  SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                      ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                    ],
                    selected: {st.themeMode},
                    onSelectionChanged: (v) => st.update((x) => x.themeMode = v.first),
                  ),
                ),
                _row(
                  context,
                  'Pieces',
                  SegmentedButton<PieceSet>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: PieceSet.cburnett, label: Text('Classic')),
                      ButtonSegment(value: PieceSet.merida, label: Text('Merida')),
                      ButtonSegment(value: PieceSet.chessnut, label: Text('Chessnut')),
                    ],
                    selected: {st.pieceSet},
                    onSelectionChanged: (v) => st.update((x) => x.pieceSet = v.first),
                  ),
                ),
                _row(
                  context,
                  'Board',
                  SegmentedButton<BoardStyle>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: BoardStyle.brown, label: Text('Brown')),
                      ButtonSegment(value: BoardStyle.blue, label: Text('Blue')),
                      ButtonSegment(value: BoardStyle.green, label: Text('Green')),
                      ButtonSegment(value: BoardStyle.grey, label: Text('Grey')),
                    ],
                    selected: {st.boardStyle},
                    onSelectionChanged: (v) => st.update((x) => x.boardStyle = v.first),
                  ),
                ),
                const SizedBox(height: Space.s),
              ]),
              _header(context, 'Engine'),
              _card(context, [
                ListTile(
                  title: Text(s.engine.state.value.status == EngineStatus.ready ? s.engine.engineId : 'Stockfish 19'),
                  subtitle: Text(_engineStatus(s.engine.state.value)),
                  trailing: s.engine.state.value.status == EngineStatus.failed
                      ? TextButton(onPressed: () => s.engine.start(threads: st.threads, hashMb: st.hashMb), child: const Text('Retry'))
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
                  child: Text(
                    'Runs entirely on this device. Importing a game link needs internet; analysing an imported game does not.',
                    style: t.bodySmall,
                  ),
                ),
              ]),
              _header(context, 'About'),
              _card(context, [
                ListTile(
                  title: const Text('Licences and source code'),
                  subtitle: const Text('GPL-3.0 · Stockfish · piece sets · opening data'),
                  trailing: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
                ),
                ListTile(
                  title: const Text('How moves are labelled'),
                  subtitle: const Text('Expected-score loss, thresholds and the accuracy formula'),
                  trailing: Icon(Icons.open_in_new_rounded, size: 18, color: c.textTertiary),
                  onTap: () => launchUrl(Uri.parse('https://github.com/Lironktf/openreview/blob/main/docs/CLASSIFICATION.md'),
                      mode: LaunchMode.externalApplication),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }

  static String _engineStatus(EngineState e) => switch (e.status) {
        EngineStatus.idle => 'Not started',
        EngineStatus.installing => 'Installing network… ${(e.progress * 100).round()}%',
        EngineStatus.starting => 'Starting',
        EngineStatus.ready => 'Ready · ${e.message}',
        EngineStatus.failed => e.message,
      };

  Widget _header(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(top: Space.l, bottom: Space.s),
        child: Text(title, style: Theme.of(context).textTheme.labelMedium),
      );

  Widget _card(BuildContext context, List<Widget> children) => Material(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(Radii.medium),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _row(BuildContext context, String label, Widget control) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: Space.s),
            SizedBox(width: double.infinity, child: control),
          ],
        ),
      );

  Future<void> _addUsername(BuildContext context, AppSettings st) async {
    final ctl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chess.com username'),
        content: TextField(controller: ctl, autofocus: true, autocorrect: false, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Add')),
        ],
      ),
    );
    final u = value?.trim();
    if (u == null || u.isEmpty) return;
    await st.update((x) {
      if (!x.chesscomUsernames.map((e) => e.toLowerCase()).contains(u.toLowerCase())) x.chesscomUsernames = [...x.chesscomUsernames, u];
    });
  }
}
