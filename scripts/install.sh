#!/usr/bin/env bash
# Symlink ForeverOptimizer into the WoW Forever AddOns directory.
# Usage: scripts/install.sh [path-to-AddOns-dir]   or   WOW_ADDONS=/path scripts/install.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ADDON="ForeverOptimizer"

find_addons_dir() {
  local base="/Applications/World of Warcraft"
  for c in "${1:-}" "${WOW_ADDONS:-}" "$base/_forever_/Interface/AddOns" "$base/_camelot_/Interface/AddOns"; do
    [[ -n "$c" && -d "$c" ]] && { echo "$c"; return 0; }
  done
  if [[ -d "$base" ]]; then
    for d in "$base"/_*_/Interface; do [[ -d "$d" ]] && echo "found game folder: $d" >&2; done
  fi
  return 1
}

if ! TARGET="$(find_addons_dir "${1:-}")"; then
  echo "Could not find the AddOns directory." >&2
  echo "Launch WoW Forever once so it creates _forever_/Interface, then re-run," >&2
  echo "or pass the path: scripts/install.sh '/Applications/World of Warcraft/_forever_/Interface/AddOns'" >&2
  exit 1
fi

# Remove links to the pre-unification addons if they're still there
for old in MikeLib GrindTracker QuestPath AHLedger BagSense CraftMargin TrainPlan; do
  [[ -L "$TARGET/$old" ]] && { echo "  unlink  $old"; rm "$TARGET/$old"; }
done

dst="$TARGET/$ADDON"
if [[ -L "$dst" ]]; then echo "  relink  $ADDON"; rm "$dst"
elif [[ -e "$dst" ]]; then echo "  SKIP    $ADDON (real folder exists at $dst; remove it to link the repo copy)"; exit 1
else echo "  link    $ADDON"; fi
ln -s "$REPO/$ADDON" "$dst"
echo "AddOns dir: $TARGET"
echo "Done. In game: /reload, then /fo help."
