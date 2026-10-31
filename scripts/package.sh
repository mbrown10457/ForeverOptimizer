#!/usr/bin/env bash
# Zip ForeverOptimizer for handing to friends: ForeverOptimizer-<version>.zip in dist/
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
VER="$(grep -E '^## Version:' "$REPO/ForeverOptimizer/ForeverOptimizer.toc" | awk '{print $3}')"
mkdir -p "$REPO/dist"
OUT="$REPO/dist/ForeverOptimizer-${VER}.zip"
rm -f "$OUT"
( cd "$REPO" && zip -qr "$OUT" ForeverOptimizer -x '*.DS_Store' )
echo "wrote $OUT ($(du -h "$OUT" | cut -f1)). Recipient unzips into Interface/AddOns/."
