#!/usr/bin/env python3
"""Compare the newest Forever client build on wago.tools with the build the seeds were generated from.

Prints the newest build and exits 0 when it is newer than ForeverOptimizer/Data/BUILD, exits 3 when
the seeds are current, and exits 1 on error. Used by the seed-update workflow and handy by hand.
"""
import json, os, sys, urllib.request

API = "https://wago.tools/api/builds"
HERE = os.path.dirname(os.path.abspath(__file__))
BUILD_FILE = os.path.join(HERE, "..", "ForeverOptimizer", "Data", "BUILD")

def key(v):
    return tuple(int(x) for x in v.split("."))

def main():
    product = sys.argv[1] if len(sys.argv) > 1 else "wowf"
    req = urllib.request.Request(API, headers={"User-Agent": "ForeverOptimizer-seed/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = json.load(r)
    builds = data.get(product) or []
    if not builds:
        print(f"product {product!r} not listed", file=sys.stderr)
        sys.exit(1)
    latest = builds[0]["version"]
    current = open(BUILD_FILE, encoding="utf-8").read().strip() if os.path.exists(BUILD_FILE) else "0.0.0.0"
    print(latest)
    if key(latest) > key(current):
        print(f"new build {latest} (seeds at {current})", file=sys.stderr)
        sys.exit(0)
    print(f"seeds current at {current}", file=sys.stderr)
    sys.exit(3)

if __name__ == "__main__":
    main()
