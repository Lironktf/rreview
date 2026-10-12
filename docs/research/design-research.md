# Design research (sub-agent report, 2026-10-11)

See docs/DESIGN.md for the distilled rules. Key sources:

- Reddit-mined study of "vibe-coded" tells: https://github.com/JCarterJohnson/vibecoded-design-tells
- https://news.ycombinator.com/item?id=47984512 (shadcn default look), https://news.ycombinator.com/item?id=49901973
- https://dev.to/james_anderson_h/the-purple-gradient-problem-why-ai-ui-all-looks-alike-and-how-to-fix-it-3j65
- https://www.developersdigest.tech/blog/ai-design-slop-and-how-to-spot-it (16 patterns)
- https://www.thefountaininstitute.com/blog/signs-vibe-coded-ui, https://smoothui.dev/blog/ai-design-slop
- Yuwen Lu, "Signs of vibe coded UI": https://x.com/yuwen_lu_/article/2041187936738447565
- Apple HIG Typography/Layout; https://www.learnui.design/blog/ios-font-size-guidelines.html
- Refactoring UI notes: https://gist.github.com/selcukcihan/b9418596a98abfcd4bbc622550820cc5
- Lichess mobile (Flutter): lib/src/view/analysis/analysis_layout.dart, lib/src/view/engine/engine_gauge.dart,
  lib/src/widgets/pgn.dart, lib/src/styles/lichess_colors.dart; flutter-chessground board_annotation.dart and
  board_color_scheme.dart.
- Chess.com Game Review: https://support.chess.com/en/articles/8584089-how-does-game-review-work,
  https://www.chess.com/news/view/chesscom-launches-game-review-v2
- Piece licences: https://github.com/lichess-org/lila/blob/master/COPYING.md — commercial-OK: cburnett (GPLv2+),
  merida (GPLv2+), mono (GPLv2+), mpchess (GPLv3+), chessnut (Apache 2.0), fantasy/spatial/celtic (MIT),
  kiwen-suwi and firi (CC BY 4.0), shapes (CC BY-SA 4.0), rhosgfx (CC0). NOT usable: maestro, staunty, fresca,
  gioco, kosal, tatiana, cardinal, icpieces, dubrovny, caliente, horsey, cooke, monarchy, anarcandy (CC BY-NC-SA),
  alpha, chess7, companion, leipzig, riohacha (non-free).
- Fonts with tabular figures: Geist, Figtree, Instrument Sans, Inter, Manrope, Public Sans (tnum); IBM Plex Sans,
  Source Sans 3, Hanken Grotesk (tabular by default); Albert Sans and DM Sans have none. Recommendation: platform
  system font with FontFeature.tabularFigures().
- Board colours (flutter-chessground): brown #f0d9b5/#b58863, blue #dee3e6/#8ca2ad, green #ffffdd/#86a666,
  grey #b8b8b8/#7d7d7d; last-move rgba(155,199,0,.41); selected rgba(20,85,30,.5).
