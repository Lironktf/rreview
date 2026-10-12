# Chess.com / Lichess game-import research (verified 2026-10-11)

Research conducted by a sub-agent for OpenReview; [V] = verified by fetching the page or endpoint,
[S] = sourced from a third party, [I] = inference.

## 1. What the Chess.com mobile app puts in the share sheet

No official documentation of the payload exists.

- [V] Support article "How do I share a game (link, PGN, GIF, or image)?"
  (https://support.chess.com/en/articles/14463498-how-do-i-share-a-game-link-pgn-gif-or-image):
  mobile: Options → Share Game → "Choose your preferred sharing method".
- [V] Support article "How do I get a PGN of my game?"
  (https://support.chess.com/en/articles/8705305-how-do-i-get-a-pgn-of-my-game): Android: More → "Export PGN"
  (PGN text through the share sheet) vs "Share Game" (a hyperlink). iOS: Game Analysis → Options → Share → the share
  sheet carries **PGN text** ('Copy' copies the PGN).
- [S] Forums (2020, 2022): the app's share either copies PGN text or gives the game link depending on the entry point.
- [I] Conclusion: the share extension must accept both a plain URL (possibly with surrounding text) and raw PGN text,
  plus `public.url`. No `link.chess.com` short-link domain was observed (returns 404/400).

Game URL formats (all HTTP 200 on 2026-10-11):

| Form | Example |
|---|---|
| Live, canonical (API `url` / PGN `Link`) | `https://www.chess.com/game/live/97872578329` |
| Live, older order | `https://www.chess.com/live/game/81447794469` |
| Bare | `https://www.chess.com/game/120030506058` |
| Daily | `https://www.chess.com/game/daily/781647993` (`/daily/game/{id}` redirects here) |
| Analysis / review | `https://www.chess.com/analysis/game/live/{id}[/review|/analysis]` |
| Computer | `https://www.chess.com/game/computer/{id}` |
| Query / locale | `?username=…`, `?move=N`, `/de/live/game/{id}` |

Recommended regex [I]: `chess\.com/(?:[a-z]{2}/)?(?:analysis/game/)?(?:(live|daily|computer)/game/|game/(?:(live|daily|computer)/)?)(\d+)`.
The id is always a decimal integer. The type segment may be absent; default to live. Chess.com changed the live URL
shape in March 2025 and may again.

## 2. Published-Data API (https://www.chess.com/news/view/published-data-api)

- [V] No single-game-by-id endpoint exists; `https://api.chess.com/pub/game/{id}` → 404. Staff answer on the forum
  (2021–2023): "You have to go through a player archive."
- [V] `GET /pub/player/{username}/games/archives` → `{"archives":[".../games/2014/01", …]}` ascending. CORS `*`.
- [V] `GET /pub/player/{username}/games/{YYYY}/{MM}` → `{"games":[…]}` with fields `url, pgn, time_control, end_time,
  rated, accuracies{white,black}, tcn, uuid, initial_setup, fen, time_class, rules, eco, tournament, white{rating,result,
  @id,username,uuid}, black{…}` (`start_time` for daily). CORS `*`, `cache-control: public, max-age=5`. Username is
  case-insensitive.
- [V] `GET …/games/{YYYY}/{MM}/pgn` → multi-game PGN, `Content-Type: application/x-chess-pgn`.
- [V] Rate limits: serial access unlimited; parallel requests may get 429. A recognisable User-Agent with contact
  info is requested. Read-only; respect Chess.com IP (board colours, piece sets, glyphs).
- [V] Undocumented/private: `https://www.chess.com/callback/live/game/{id}` returns JSON with TCN-encoded moves,
  `cache-control: private`, no CORS header; the chess-web-api README says its use violates the Terms of Service.
  **OpenReview does not use it.**

## 3. Resolving a game URL with public endpoints only

The URL carries only `{type, id}`: no username, no date. Open-source tools (en-croissant, chess-fetcher, pychess
boards) all go through the private callback. Public-only approach [I]: the user stores their Chess.com username(s)
once; fetch `archives`, scan newest month backwards, compare each game's `url` id (integer compare, tolerant of
`/live/game/` vs `/game/live/`), stop on hit; cap months scanned. Live ids increase monotonically, so months can be
skipped by comparing ids. If no stored username matches, ask for either player's name.

## 4. Lichess

- [V] `GET https://lichess.org/game/export/{gameId}` with `Accept: application/x-chess-pgn`; gameId is exactly 8
  chars (12-char URLs = 8-char game id + 4-char player id; take the first 8). Params `clocks`, `evals`, `opening`,
  `literate`. No auth, CORS `*`. "Only make one request at a time"; on 429 wait one minute.
- [V] URL formats: `/{8}`, `/{8}/black`, `/{8}/white`, `/{8}{4}`, `/embed/game/{8}`. Non-existent ids 303 to `/@/{id}`.
  Study chapters: `/study/{studyId}/{chapterId}` → `/api/study/{studyId}/{chapterId}.pgn`.
- [V] PGN headers: Event, Site, Date, Round, White, Black, Result, GameId, UTCDate, UTCTime, WhiteElo, BlackElo,
  Variant, TimeControl, ECO, Opening, Termination, Annotator, [FEN, SetUp]; moves `1. e4 { [%clk 0:10:00] } 1... c5 …`.

## 5. Chess.com API PGN sample [V]

```
[Event "Live Chess"]
[Site "Chess.com"]
[Date "2024.01.01"]
[Round "-"]
[White "Hikaru"]
[Black "Gravity_Chess"]
[Result "1-0"]
[CurrentPosition "8/5k2/8/5p1p/4b3/R7/PP1B1K1P/8 b - -"]
[Timezone "UTC"]
[ECO "B23"]
[ECOUrl "https://www.chess.com/openings/Closed-Sicilian-Defense-Grand-Prix-Attack-3...g6-4.Bc4-Bg7-5.Nf3"]
[UTCDate "2024.01.01"]
[UTCTime "18:23:37"]
[WhiteElo "3236"]
[BlackElo "2867"]
[TimeControl "180"]
[Termination "Hikaru won by resignation"]
[StartTime "18:23:37"]
[EndDate "2024.01.01"]
[EndTime "18:28:26"]
[Link "https://www.chess.com/game/live/97872578329"]

1. e4 {[%clk 0:03:00]} 1... c5 {[%clk 0:03:00]} 2. Nc3 {[%clk 0:02:59.9]} 2... g6 {[%clk 0:02:57.5]} ...
```

Black moves are re-numbered (`1...`), clock comments have tenth-second precision, Chess960 games add
`[SetUp "1"][FEN "…"]` and `rules: "chess960"`; bughouse games have no PGN.

## Recommended import strategy

Accept `public.url` and `public.plain-text` (and `.pgn` files). If the text parses as PGN, import directly. Otherwise
extract URLs: Lichess → export API; Chess.com → Published-Data archives of the stored username(s). Serialise requests,
honour ETag/gzip, back off on 429, send a User-Agent with contact info. Never use `www.chess.com/callback/*`.
