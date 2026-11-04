#!/usr/bin/env python3
"""Build ForeverOptimizer/Data/MapOverlays.lua: every exploration overlay of every world map in the
Forever client, so the addon can draw the parts of a zone map the character has not explored yet.

Source: wago.tools DB2 CSV exports for the `wowf` product.
  UiMap, UiMapXMapArt        which map art a uiMapID uses (phase 0)
  UiMapArt, UiMapArtStyleLayer   tile size of that art (256x256 for zone maps)
  WorldMapOverlay            one row per explorable area: texture size and offset on the map art
  WorldMapOverlayTile        the 256x256 texture files that make up each overlay, by row and column

The game reveals an overlay by drawing those files at that offset once the area is explored
(C_MapExplorationInfo.GetExploredMapTextures). The addon draws the ones that call does not return.

Usage:
  scripts/build_mapoverlays.py                        # latest wowf build
  scripts/build_mapoverlays.py --build 1.60.1.70753
  scripts/build_mapoverlays.py --csv-dir cache/       # reuse downloaded CSVs
"""
import argparse, collections, csv, json, math, os, sys, urllib.request

API_BUILDS = "https://wago.tools/api/builds"
CSV_URL = "https://wago.tools/db2/{table}/csv?build={build}"
TABLES = ["UiMap", "UiMapXMapArt", "UiMapArt", "UiMapArtStyleLayer", "WorldMapOverlay", "WorldMapOverlayTile"]

def fetch(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return dest
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "ForeverOptimizer-seed/1.0"})
    with urllib.request.urlopen(req, timeout=180) as r, open(dest, "wb") as f:
        f.write(r.read())
    return dest

def latest_build(product):
    with urllib.request.urlopen(urllib.request.Request(API_BUILDS, headers={"User-Agent": "ForeverOptimizer-seed/1.0"}), timeout=60) as r:
        data = json.load(r)
    builds = data.get(product) or []
    if not builds:
        sys.exit(f"product {product!r} not listed at {API_BUILDS}")
    return builds[0]["version"]

def rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--product", default="wowf")
    ap.add_argument("--build")
    ap.add_argument("--csv-dir")
    ap.add_argument("--cache", default=os.path.join(os.path.dirname(__file__), ".seedcache"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "ForeverOptimizer", "Data", "MapOverlays.lua"))
    a = ap.parse_args()

    build = a.build or (None if a.csv_dir else latest_build(a.product))
    if a.csv_dir:
        paths = {t: os.path.join(a.csv_dir, t + ".csv") for t in TABLES}
        build = build or "unknown"
    else:
        d = os.path.join(a.cache, build)
        paths = {t: fetch(CSV_URL.format(table=t, build=build), os.path.join(d, t + ".csv")) for t in TABLES}

    names = {int(r["ID"]): r["Name_lang"] for r in rows(paths["UiMap"])}
    art_of = {}                                          # uiMapID -> uiMapArtID (phase 0 wins)
    for r in rows(paths["UiMapXMapArt"]):
        m, art, phase = int(r["UiMapID"]), int(r["UiMapArtID"]), int(r["PhaseID"])
        if m not in art_of or phase == 0:
            art_of[m] = art
    style_of = {int(r["ID"]): int(r["UiMapArtStyleID"]) for r in rows(paths["UiMapArt"])}
    tile_of_style = {}                                   # styleID -> (tileW, tileH) of layer 0
    for r in rows(paths["UiMapArtStyleLayer"]):
        if int(r["LayerIndex"]) == 0:
            tile_of_style[int(r["UiMapArtStyleID"])] = (int(r["TileWidth"]), int(r["TileHeight"]))
    tiles = collections.defaultdict(list)                # overlayID -> [(row, col, fileID)]
    for r in rows(paths["WorldMapOverlayTile"]):
        if int(r["LayerIndex"]) == 0:
            tiles[int(r["WorldMapOverlayID"])].append((int(r["RowIndex"]), int(r["ColIndex"]), int(r["FileDataID"])))
    overlays = collections.defaultdict(list)             # uiMapArtID -> [(w, h, x, y, [fileIDs])]
    skipped = mismatched = 0
    for r in rows(paths["WorldMapOverlay"]):
        if int(r["PlayerConditionID"] or 0) != 0:
            skipped += 1
            continue
        oid, art = int(r["ID"]), int(r["UiMapArtID"])
        w, h, x, y = int(r["TextureWidth"]), int(r["TextureHeight"]), int(r["OffsetX"]), int(r["OffsetY"])
        tw, th = tile_of_style.get(style_of.get(art, 0), (256, 256))
        want = math.ceil(w / tw) * math.ceil(h / th)
        files = [f for _, _, f in sorted(tiles.get(oid, []))]
        if len(files) != want:
            mismatched += 1
            print(f"warning: overlay {oid} on art {art} has {len(files)} tiles, expected {want} for {w}x{h}", file=sys.stderr)
            if not files:
                continue
        overlays[art].append((w, h, x, y, files))

    by_map = {}
    for m, art in art_of.items():
        if overlays.get(art):
            by_map[m] = sorted(overlays[art], key=lambda o: (o[3], o[2]))
    n_overlays = sum(len(v) for v in by_map.values())
    n_tiles = sum(len(o[4]) for v in by_map.values() for o in v)

    out = [
        "-- GENERATED by scripts/build_mapoverlays.py from wago.tools DB2 exports. Do not edit by hand.",
        f"-- product {a.product}, client build {build}: {len(by_map)} maps, {n_overlays} exploration overlays, {n_tiles} texture tiles",
        "-- Layout: FO.Seed.mapOverlays[uiMapID] = { { textureWidth, textureHeight, offsetX, offsetY, { fileDataIDs row-major } }, ... }",
        "-- The game draws exactly these files at these offsets when an area is explored; the addon draws the ones still missing.",
        "local ADDON, FO = ...",
        "FO.Seed = FO.Seed or {}",
        f'FO.Seed.mapOverlayBuild = "{build}"',
        "FO.Seed.mapOverlays = {}",
        "local M = FO.Seed.mapOverlays",
    ]
    for m in sorted(by_map):
        out.append(f"M[{m}] = {{ -- {names.get(m, '?')}")
        for w, h, x, y, files in by_map[m]:
            out.append(f"  {{{w},{h},{x},{y},{{{','.join(map(str, files))}}}}},")
        out.append("}")
    out.append("")
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print(f"wrote {a.out}: build {build}, {len(by_map)} maps, {n_overlays} overlays, {n_tiles} tiles"
          f" ({skipped} condition-gated overlays skipped, {mismatched} tile-count mismatches)")

if __name__ == "__main__":
    main()
