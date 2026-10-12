import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/tokens.dart';

const sourceUrl = 'https://github.com/Lironktf/rreview';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    Widget link(String label, String url) => TextButton(
          style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
          onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Text(label),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Licences')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xxl),
        children: [
          Text('rreview', style: t.titleLarge),
          const SizedBox(height: Space.xs),
          Text(
            'Free software under the GNU General Public License v3.0 or later. The complete corresponding source code '
            'of this app, including the engine and the modifications used to embed it, is published at:',
            style: t.bodyMedium,
          ),
          link(sourceUrl, sourceUrl),
          const SizedBox(height: Space.l),
          Text('Stockfish 19', style: t.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            'Chess engine by the Stockfish developers (see AUTHORS), GPL-3.0-or-later. Compiled from the unmodified '
            'sf_19 release sources with NNUE_EMBEDDING_OFF; the network nn-1a298aa575a0.nnue is loaded from the app '
            'bundle. A small bridge (sf_bridge.cpp) replaces the standard streams so the engine runs in-process.',
            style: t.bodyMedium,
          ),
          link('stockfishchess.org', 'https://stockfishchess.org'),
          link('github.com/official-stockfish/Stockfish', 'https://github.com/official-stockfish/Stockfish'),
          const SizedBox(height: Space.l),
          Text('Chess pieces', style: t.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            'cburnett by Colin M.L. Burnett (GPLv2+), merida by Armando Hernandez Marroquin (GPLv2+), chessnut by '
            'Alexis Luengas (Apache 2.0). Distributed by lichess.org; licence texts are bundled with the app.',
            style: t.bodyMedium,
          ),
          link('lichess-org/lila COPYING.md', 'https://github.com/lichess-org/lila/blob/master/COPYING.md'),
          const SizedBox(height: Space.l),
          Text('Opening names', style: t.titleMedium),
          const SizedBox(height: Space.xs),
          Text('lichess-org/chess-openings, released under CC0 1.0.', style: t.bodyMedium),
          link('github.com/lichess-org/chess-openings', 'https://github.com/lichess-org/chess-openings'),
          const SizedBox(height: Space.l),
          Text('Game data', style: t.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            'Chess.com games are fetched through the public Published-Data API (player archives); Lichess games through '
            'the public game export API. Nothing is uploaded anywhere: games and reviews stay on this device.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: Space.l),
          Text('Flutter packages', style: t.titleMedium),
          const SizedBox(height: Space.xs),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
            onPressed: () => showLicensePage(context: context, applicationName: 'rreview', applicationLegalese: 'GPL-3.0-or-later'),
            child: const Text('Show package licences'),
          ),
          const SizedBox(height: Space.l),
          Text('No affiliation with Chess.com or Lichess.', style: t.bodySmall?.copyWith(color: c.textTertiary)),
        ],
      ),
    );
  }
}
