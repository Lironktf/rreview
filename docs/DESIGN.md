# rreview design rules

Distilled from design research (2026-10-11; sources in `docs/research/design-research.md`). Every screen is
checked against this list before it is considered done.

## Banned (the "vibe-coded" tells)

1. Untouched framework defaults: no `ColorScheme.fromSeed(deepPurple)`, no stock Material 3 chrome, no M3 purple.
2. Purple/indigo→blue gradients, gradient text, gradients on numbers, "gradients everywhere".
3. Glassmorphism, neon glows, coloured box-shadows, "dark background + glow".
4. Cards nested in cards; a 1 px grey border around every box; coloured stripe on the side of cards.
5. Icons inside rounded tinted squares; emoji as icons or bullets.
6. Identical 3-up feature card grids, stat banners, pills above every heading, decorative status dots.
7. Pure #000 dark mode; medium-grey body text that fails WCAG AA; all-caps section labels everywhere.
8. One radius for everything; a different shadow recipe per component; 5–6 saturated colours at equal volume.
9. Bounce easing, slow entrance animations, anything that moves without a state change.
10. Missing states (empty, loading, error, disabled, focus) and LLM-flavoured copy.

## Rules we follow

- **Type**: platform system font (SF Pro on iOS, Roboto on Android). 17 pt body, 15 pt secondary, 13 pt footnote,
  22/28 pt titles. Hierarchy comes from weight and colour, not from size. No weights below 400. Tabular figures
  (`FontFeature.tabularFigures()`) on every number that can change: evals, clocks, accuracy, move numbers.
  SAN is never set in monospace.
- **Spacing**: 4/8-pt scale only (4, 8, 12, 16, 24, 32). More space around a group than inside it.
- **Colour**: neutrals for ~85 % of every screen, one accent for interactive state only, plus the classification
  colours, which are the only other hues and always carry meaning (Okabe-Ito style: inaccuracy #56b4e9-ish blue,
  mistake #e69f00 amber, blunder #df5353 red, best/excellent muted greens). Separate regions with background
  shifts and spacing, not borders; one hairline colour when a divider is unavoidable. Dark mode uses warm dark greys
  (#1c1b19 … #2a2826), never #000. Both themes swap the same semantic tokens.
- **Board**: the brightest, largest object on the review screen. Light theme: Lichess-style brown #f0d9b5/#b58863.
  Dark theme: the same pair dimmed ~12 % (#d9c4a3/#9a7352), never near-black dark squares. Highlights are
  semi-transparent overlays so one set works in both themes. Pieces: cburnett (GPLv2+) by default, merida and
  chessnut selectable.
- **Eval bar**: ≤ 24 pt wide, theme-derived light/dark greys (not pure white/black), label in 10 pt bold tabular,
  one 300–400 ms ease tween, "#" for mate.
- **Move labels**: badge on the destination square (circle, ~0.45 × square, overhanging the top-right corner). Strong
  fills only for inaccuracy / mistake / blunder / missed win; best gets a quiet green mark; good/excellent get no
  badge on the board (they appear in the move list only). Best-move arrow: one semi-transparent colour.
- **Move list**: two columns with a tabular index column at 60 % opacity, moves 16 pt w600, soft rounded highlight
  for the current move, label colour as a small dot/glyph after the SAN, 44 pt tap height.
- **iOS conventions**: safe areas, 44×44 pt targets, standard navigation bar, bottom toolbar for board controls,
  sheets for secondary actions.
- **Motion**: only for state changes (board piece slide 150–200 ms, eval bar tween, badge scale-in 150 ms). Read
  `accessibilityFeatures.reduceMotion` (Flutter does not map iOS Reduce Motion to `disableAnimations`) and switch to
  instant transitions when set.
- **Copy**: short, specific, no exclamation marks, no coaching clichés. Every explanation states a verifiable fact
  about the position.
