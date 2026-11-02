#!/usr/bin/env bash
# Download the latest QuestieDB Forever release into dist/questiedb/ and verify its checksum
# against the release manifest. scripts/install.sh installs it from there alongside ForeverOptimizer.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$REPO/dist/questiedb"
mkdir -p "$DIR"
cd "$DIR"
rm -f QuestieDB-Forever.zip release.json
gh release download --repo Questie/QuestieDB --pattern 'QuestieDB-Forever.zip' --pattern 'release.json'
expected="$(python3 -I -c "import json; d=json.load(open('release.json')); print([a['sha256'] for a in d['questiedb']['artifacts'] if a['flavor']=='Forever'][0])")"
actual="$(shasum -a 256 QuestieDB-Forever.zip | cut -d' ' -f1)"
if [[ "$expected" != "$actual" ]]; then echo "checksum mismatch: expected $expected got $actual" >&2; rm -f QuestieDB-Forever.zip; exit 1; fi
ver="$(python3 -I -c "import json; print(json.load(open('release.json'))['questiedb']['version'])")"
echo "QuestieDB $ver (Forever) staged at $DIR, checksum verified. scripts/install.sh will install it."
