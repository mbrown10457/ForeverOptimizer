#!/usr/bin/env bash
# Install (or remove) the nightly SavedVariables backup as a launchd user agent (Mac).
# Runs scripts/backup.sh at 04:30 every day and once at login. No admin rights, no extra permissions:
# both the game folder and ~/Backups are ordinary user-readable paths.
#
#   scripts/backup-install.sh            # install and start
#   scripts/backup-install.sh remove     # stop and remove
#   scripts/backup-install.sh status     # is it loaded, and the last log lines
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.foreveroptimizer.backup"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGDIR="${FO_BACKUP_DIR:-$HOME/Backups/ForeverOptimizer}"
case "${1:-install}" in
  remove)
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "removed $LABEL"
    ;;
  status)
    if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then echo "$LABEL: loaded"; else echo "$LABEL: not loaded"; fi
    [ -f "$LOGDIR/backup.log" ] && tail -n 5 "$LOGDIR/backup.log" || echo "no backups yet"
    ;;
  install)
    mkdir -p "$HOME/Library/LaunchAgents" "$LOGDIR"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$REPO/scripts/backup.sh</string></array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>4</integer><key>Minute</key><integer>30</integer></dict>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOGDIR/launchd.out</string>
  <key>StandardErrorPath</key><string>$LOGDIR/launchd.err</string>
</dict>
</plist>
EOF
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    echo "installed $LABEL: runs $REPO/scripts/backup.sh daily at 04:30 and now. Backups in $LOGDIR"
    ;;
  *) echo "usage: $0 [install|remove|status]" >&2; exit 2 ;;
esac
