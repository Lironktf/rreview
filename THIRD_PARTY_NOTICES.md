# Third-party notices

OpenReview itself is licensed under the GNU General Public License v3.0 or later (see LICENSE).

| Component | Location | Licence |
|---|---|---|
| Stockfish 19 (the Stockfish developers, see `Stockfish/AUTHORS`) | `packages/stockfish_ffi/ios/stockfish_ffi/Sources/stockfish_ffi/Stockfish/` | GPL-3.0-or-later (`Stockfish/Copying.txt`) |
| Stockfish NNUE network `nn-1a298aa575a0.nnue` | `app/assets/engine/` | GPL-3.0-or-later (part of the Stockfish distribution) |
| incbin (Dale Weiler) | `…/Stockfish/src/incbin/` | Unlicense (public domain); compiled out with `NNUE_EMBEDDING_OFF` |
| cburnett chess pieces (Colin M.L. Burnett) | `app/assets/pieces/cburnett/` | GPL-2.0-or-later |
| merida chess pieces (Armando Hernandez Marroquin) | `app/assets/pieces/merida/` | GPL-2.0-or-later |
| chessnut chess pieces (Alexis Luengas) | `app/assets/pieces/chessnut/` | Apache-2.0 |
| lichess-org/lila licence index for the piece sets | `app/assets/pieces/LICENSES-lila-COPYING.md` | (documentation) |
| lichess-org/chess-openings (ECO opening names) | `app/assets/openings/*.tsv`, `COPYING.txt` | CC0-1.0 |
| Flutter SDK and pub.dev packages (flutter_svg, path_provider, file_picker, share_plus, url_launcher, http, ffi) | `pubspec.lock` | BSD-3-Clause / MIT; full texts in the in-app licence page |

Chess.com and Lichess are trademarks of their respective owners. OpenReview is not affiliated with either; it reads
game data only through their documented public APIs.
