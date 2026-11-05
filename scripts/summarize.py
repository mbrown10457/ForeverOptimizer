#!/usr/bin/env python3 -I
"""Print a launch-day summary of a ForeverOptimizer SavedVariables file converted to JSON.

Usage:
  scripts/savedvars_to_json.py ForeverOptimizer.lua --var ForeverOptimizerDB -o db.json
  scripts/summarize.py db.json

Shows: addon version, the last /fo verify run (fails and info lines), saved Lua errors,
sessions, and per character the first-hour checklist and runes learned.
"""
import json, sys, time


def as_list(x):
    if x is None:
        return []
    if isinstance(x, list):
        return x
    if isinstance(x, dict):
        try:
            return [x[k] for k in sorted(x, key=lambda k: int(k))]
        except (ValueError, TypeError):
            return list(x.values())
    return [x]


def when(t):
    try:
        return time.strftime("%Y-%m-%d %H:%M", time.localtime(int(t)))
    except (TypeError, ValueError):
        return "?"


def dur(s):
    try:
        s = int(s)
    except (TypeError, ValueError):
        return "?"
    return "%d:%02d:%02d" % (s // 3600, s % 3600 // 60, s % 60)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    with open(sys.argv[1], encoding="utf-8") as f:
        root = json.load(f)
    if isinstance(root, dict) and "ForeverOptimizerDB" in root:
        root = root["ForeverOptimizerDB"]
    acct = root.get("account") or {}
    print("ForeverOptimizer SavedVariables, schema v%s" % root.get("version"))

    v = (acct.get("verify") or {}).get("last")
    if v:
        checks = as_list(v.get("checks"))
        passed = sum(1 for c in checks if c.get("ok") is True)
        failed = [c for c in checks if c.get("ok") is False]
        info = [c for c in checks if c.get("ok") not in (True, False)]
        print("\n/fo verify at %s: addon %s, client build %s, TOC %s: %d pass, %d fail, %d info" % (
            when(v.get("t")), v.get("version"), v.get("build"), v.get("toc"), passed, len(failed), len(info)))
        for c in failed:
            print("  FAIL  %-36s %s" % (c.get("name"), c.get("detail", "")))
        for c in info:
            print("  INFO  %-36s %s" % (c.get("name"), c.get("detail", "")))
    else:
        print("\n/fo verify: never run")

    errors = as_list((acct.get("errors") or {}).get("log"))
    print("\nLua errors saved: %d" % len(errors))
    for e in sorted(errors, key=lambda e: -(e.get("last") or 0))[:10]:
        print("  x%-3s %s  %s: %s" % (e.get("count", 1), when(e.get("last")), e.get("where"), e.get("msg")))

    sessions = as_list((acct.get("sessions") or {}).get("list"))
    print("\nSessions: %d" % len(sessions))
    for s in sessions[-5:]:
        notes = as_list(s.get("notes"))
        print("  %s  L%-3s %-22s %s  xp %s  kills %s  deaths %s  notes %d" % (
            when(s.get("start")), s.get("level", "?"), (s.get("zone") or "?")[:22], dur(s.get("elapsed") or s.get("productive")),
            s.get("xp", "?"), s.get("kills", "?"), s.get("deaths", "?"), len(notes)))
        for n in notes:
            print("      note %s L%s %s: %s" % (when(n.get("t")), n.get("level"), n.get("zone"), n.get("text")))

    chars = root.get("chars") or {}
    for key, c in sorted(chars.items()):
        print("\nCharacter %s" % key)
        done = (c.get("checklist") or {}).get("done") or {}
        if done:
            print("  checklist done: %s" % ", ".join(sorted(done)))
        else:
            print("  checklist: nothing ticked")
        learned = (c.get("runes") or {}).get("learned") or {}
        if learned:
            for e in sorted(learned.values(), key=lambda e: e.get("t") or 0):
                pos = " (%.1f, %.1f)" % (e["x"] * 100, e["y"] * 100) if e.get("x") is not None else ""
                print("  rune %s  L%s %s%s%s" % (e.get("name"), e.get("level"), e.get("zone"), pos, "  (known at login)" if e.get("seenAtLogin") else ""))
        else:
            print("  runes: none learned")
    return 0


if __name__ == "__main__":
    sys.exit(main())
