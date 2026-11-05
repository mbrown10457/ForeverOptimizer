#!/usr/bin/env bash
# Gather ForeverOptimizer data after a session (Mac): copies every account's SavedVariables file,
# converts it to JSON, prints the launch-day summary and zips the lot for sending.
#
#   scripts/collect.sh                 # default game folder
#   WOW_FOREVER="/Volumes/Games/World of Warcraft/_forever_" scripts/collect.sh
#
# The game writes SavedVariables on logout and /reload, so log out (or /reload) first.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
GAME="${WOW_FOREVER:-/Applications/World of Warcraft/_forever_}"
STAMP="$(date +%Y%m%d-%H%M)"
OUT="$REPO/dist/collect/$STAMP"
mkdir -p "$OUT"
found=0
for f in "$GAME"/WTF/Account/*/SavedVariables/ForeverOptimizer.lua; do
  [ -f "$f" ] || continue
  acct="$(basename "$(dirname "$(dirname "$f")")")"
  cp "$f" "$OUT/ForeverOptimizerDB-$acct.lua"
  python3 -I "$REPO/scripts/savedvars_to_json.py" "$OUT/ForeverOptimizerDB-$acct.lua" --var ForeverOptimizerDB -o "$OUT/ForeverOptimizerDB-$acct.json"
  echo "== account $acct  ($(du -h "$f" | cut -f1), written $(date -r "$f" '+%Y-%m-%d %H:%M'))"
  python3 -I "$REPO/scripts/summarize.py" "$OUT/ForeverOptimizerDB-$acct.json" | tee "$OUT/summary-$acct.txt"
  found=1
done
if [ "$found" = 0 ]; then
  echo "no ForeverOptimizer.lua under $GAME/WTF/Account/*/SavedVariables" >&2
  echo "log out once so the game writes it; if the game lives elsewhere: WOW_FOREVER=<path to _forever_> $0" >&2
  exit 1
fi
cp "$GAME/Logs/General.log" "$OUT/" 2>/dev/null || true
( cd "$REPO/dist/collect" && rm -f "$STAMP.zip" && zip -qr "$STAMP.zip" "$STAMP" )
echo
echo "collected into $OUT"
echo "zip for sending: $REPO/dist/collect/$STAMP.zip"
