#!/usr/bin/env bash
# Zip ForeverOptimizer for handing to friends (Windows or macOS):
#   dist/ForeverOptimizer-<version>.zip  =  ForeverOptimizer/  +  INSTALL.txt
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
VER="$(grep -E '^## Version:' "$REPO/ForeverOptimizer/ForeverOptimizer.toc" | awk '{print $3}')"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/fo-package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$REPO/dist"
OUT="$REPO/dist/ForeverOptimizer-${VER}.zip"
rm -f "$OUT"

# Stage a clean copy: no Finder metadata, no editor backups.
rsync -a --exclude '.DS_Store' --exclude '*~' --exclude '*.swp' "$REPO/ForeverOptimizer" "$STAGE/"
# CRLF so Windows Notepad shows line breaks.
perl -pe 's/\r?\n/\r\n/' "$REPO/scripts/INSTALL.txt" > "$STAGE/INSTALL.txt"

# -X drops macOS extended attributes so Windows sees no __MACOSX or ._ files.
( cd "$STAGE" && zip -qrX "$OUT" ForeverOptimizer INSTALL.txt )
echo "wrote $OUT ($(du -h "$OUT" | cut -f1)), $(unzip -l "$OUT" | tail -1 | awk '{print $2}') files."
echo "Recipient extracts it into Interface/AddOns (see INSTALL.txt inside the zip)."
