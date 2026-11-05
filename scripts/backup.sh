#!/usr/bin/env bash
# Nightly backup of ForeverOptimizer SavedVariables (Mac). Keeps 30 days.
# Installed as a launchd agent by scripts/backup-install.sh; safe to run by hand.
#
#   WOW_FOREVER     game folder (default /Applications/World of Warcraft/_forever_)
#   FO_BACKUP_DIR   destination (default ~/Backups/ForeverOptimizer)
set -euo pipefail
GAME="${WOW_FOREVER:-/Applications/World of Warcraft/_forever_}"
DEST="${FO_BACKUP_DIR:-$HOME/Backups/ForeverOptimizer}"
STAMP="$(date +%Y%m%d-%H%M)"
mkdir -p "$DEST"
n=0
for f in "$GAME"/WTF/Account/*/SavedVariables/ForeverOptimizer.lua; do
  [ -f "$f" ] || continue
  acct="$(basename "$(dirname "$(dirname "$f")")")"
  mkdir -p "$DEST/$STAMP"
  cp "$f" "$DEST/$STAMP/ForeverOptimizerDB-$acct.lua"
  n=$((n + 1))
done
# prune backup folders older than 30 days (only this script's own dated folders)
find "$DEST" -mindepth 1 -maxdepth 1 -type d -name '20*' -mtime +30 -exec rm -rf {} +
echo "$(date '+%Y-%m-%d %H:%M') backed up $n file(s) to $DEST/$STAMP" | tee -a "$DEST/backup.log"
