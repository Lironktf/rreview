#!/usr/bin/env sh
# Downloads the Stockfish 19 NNUE network the app bundles (98 MB, GPLv3, not kept in git).
set -eu
NAME=nn-1a298aa575a0.nnue
DEST="$(dirname "$0")/../app/assets/engine/$NAME"
if [ -f "$DEST" ] && [ "$(wc -c < "$DEST")" -eq 98511183 ]; then
  echo "already present: $DEST"; exit 0
fi
echo "downloading $NAME ..."
curl -L --fail -o "$DEST.part" "https://tests.stockfishchess.org/api/nn/$NAME"
# The file name is the first 12 hex digits of its sha256.
SUM=$(sha256sum "$DEST.part" | cut -c1-12)
[ "$SUM" = "1a298aa575a0" ] || { echo "checksum mismatch: $SUM"; rm -f "$DEST.part"; exit 1; }
mv "$DEST.part" "$DEST"
echo "ok: $DEST"
