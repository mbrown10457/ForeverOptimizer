#!/usr/bin/env python3
"""Build Data/Spells.lua and Data/Talents.lua from the Forever client's own spell and talent tables.

Source: wago.tools DB2 CSV exports for the `wowf` product. Tables used:
  SkillLine, SkillLineAbility     which class learns which spell, in which tree, rank chain (SupercedesSpell)
  SpellName, Spell                name, "Rank N" subtext, description
  SpellLevels                     learn level
  SpellPower                      cost and power type (0 mana, 1 rage, 3 energy)
  SpellMisc, SpellCastTimes, SpellDuration   cast time, duration, school
  SpellCooldowns                  cooldown, GCD
  SpellEffect                     direct damage / heal base points, periodic tick + period
  Talent, TalentTab               talent trees: tab, tier, column, rank spells, prerequisites

Usage:
  scripts/build_spells.py                        # latest wowf build
  scripts/build_spells.py --build 1.60.1.70707
  scripts/build_spells.py --csv-dir cache/       # reuse downloaded CSVs

Numbers that come from SpellEffect base points are priors only: the addon prefers what it measures in the
combat log. Structure (ranks, levels, costs, cast times, cooldowns, durations, trees) is what this seed is for.
"""
import argparse, collections, csv, json, os, sys, urllib.request

API_BUILDS = "https://wago.tools/api/builds"
CSV_URL = "https://wago.tools/db2/{table}/csv?build={build}"
TABLES = ["SkillLine", "SkillLineAbility", "SpellName", "Spell", "SpellLevels", "SpellPower", "SpellMisc",
          "SpellCastTimes", "SpellDuration", "SpellCooldowns", "SpellEffect", "Talent", "TalentTab", "ChrClasses"]
CLASS_BITS = {1: "WARRIOR", 2: "PALADIN", 4: "HUNTER", 8: "ROGUE", 16: "PRIEST", 64: "SHAMAN", 128: "MAGE", 256: "WARLOCK", 1024: "DRUID"}
CHUNK = 1500

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

def lua_str(s):
    return '"' + (s or "").replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", "") + '"'

def num(v, default=0):
    try:
        return float(v) if "." in str(v) else int(v)
    except (TypeError, ValueError):
        return default

def classes_for_mask(mask):
    out = []
    for bit, name in CLASS_BITS.items():
        if mask & bit:
            out.append(name)
    return out

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--product", default="wowf")
    ap.add_argument("--build")
    ap.add_argument("--csv-dir")
    ap.add_argument("--cache", default=os.path.join(os.path.dirname(__file__), ".seedcache"))
    ap.add_argument("--out-dir", default=os.path.join(os.path.dirname(__file__), "..", "ForeverOptimizer", "Data"))
    a = ap.parse_args()

    build = a.build or (None if a.csv_dir else latest_build(a.product))
    if a.csv_dir:
        d = a.csv_dir
        build = build or "unknown"
    else:
        d = os.path.join(a.cache, build)
        for t in TABLES:
            fetch(CSV_URL.format(table=t, build=build), os.path.join(d, f"{t}.csv"))

    def rows(t):
        with open(os.path.join(d, f"{t}.csv"), newline="", encoding="utf-8") as f:
            return list(csv.DictReader(f))

    names = {r["ID"]: r["Name_lang"] for r in rows("SpellName")}
    spell_text = {r["ID"]: (r.get("NameSubtext_lang") or "", r.get("Description_lang") or "") for r in rows("Spell")}
    levels = {r["SpellID"]: r for r in rows("SpellLevels") if r.get("DifficultyID", "0") == "0"}
    power = {}
    for r in rows("SpellPower"):
        if r["SpellID"] not in power or num(r["OrderIndex"]) == 0:
            power[r["SpellID"]] = r
    misc = {r["SpellID"]: r for r in rows("SpellMisc") if r.get("DifficultyID", "0") == "0"}
    cast_times = {r["ID"]: num(r["Base"]) for r in rows("SpellCastTimes")}
    durations = {r["ID"]: num(r["Duration"]) for r in rows("SpellDuration")}
    cooldowns = {r["SpellID"]: r for r in rows("SpellCooldowns") if r.get("DifficultyID", "0") == "0"}
    effects = collections.defaultdict(list)
    for r in rows("SpellEffect"):
        if r.get("DifficultyID", "0") == "0":
            effects[r["SpellID"]].append(r)
    class_lines = {r["ID"]: r["DisplayName_lang"] for r in rows("SkillLine") if r["CategoryID"] == "7"}

    # ---- class spells
    spells = {}
    for r in rows("SkillLineAbility"):
        line = r["SkillLine"]
        if line not in class_lines:
            continue
        mask = int(num(r["ClassMask"]))
        cls = classes_for_mask(mask)
        if len(cls) != 1:
            continue                       # pet / shared / racial lines
        sid = r["Spell"]
        name = names.get(sid)
        if not name:
            continue
        subtext, desc = spell_text.get(sid, ("", ""))
        rank = 0
        if subtext.lower().startswith("rank "):
            rank = int(num(subtext[5:].strip(), 0))
        lv = levels.get(sid, {})
        pw = power.get(sid, {})
        ms = misc.get(sid, {})
        cd = cooldowns.get(sid, {})
        dd = heal = dot = hot = 0.0
        period = 0
        ppl = 0.0
        for e in effects.get(sid, []):
            eff, aura = int(num(e["Effect"])), int(num(e["EffectAura"]))
            base = num(e["EffectBasePointsF"], 0)
            if eff in (2, 9):            # school damage, health leech
                dd += base
            elif eff == 10:              # heal
                heal += base
            elif eff == 6:               # apply aura
                if aura in (3, 53, 89):  # periodic damage / leech / percent damage
                    dot += base
                    period = int(num(e["EffectAuraPeriod"], 0)) or period
                elif aura in (8, 20):    # periodic heal / obs health
                    hot += base
                    period = int(num(e["EffectAuraPeriod"], 0)) or period
            ppl = max(ppl, num(e["EffectRealPointsPerLevel"], 0))
        spells[int(sid)] = {
            "name": name, "class": cls[0], "tree": class_lines[line], "rank": rank,
            "level": int(num(lv.get("BaseLevel", 0)) or num(lv.get("SpellLevel", 0))),
            "cost": int(num(pw.get("ManaCost", 0))), "costPct": num(pw.get("PowerCostPct", 0)), "power": int(num(pw.get("PowerType", 0))),
            "cast": max(0, int(cast_times.get(ms.get("CastingTimeIndex", ""), 0))),
            "cd": int(max(num(cd.get("RecoveryTime", 0)), num(cd.get("CategoryRecoveryTime", 0)))),
            "gcd": int(num(cd.get("StartRecoveryTime", 0))),
            "dur": int(durations.get(ms.get("DurationIndex", ""), 0)),
            "school": int(num(ms.get("SchoolMask", 0))),
            "dd": dd, "heal": heal, "dot": dot, "hot": hot, "period": period, "ppl": ppl,
            "next": int(num(r["SupercedesSpell"], 0)),   # SupercedesSpell = the rank this one replaces (lower rank)
            "acquire": int(num(r["AcquireMethod"], 0)),
            "desc": desc,
        }
    # SupercedesSpell points DOWN the chain (this spell supersedes X). Invert it to get "next rank".
    next_rank = {}
    for sid, s in spells.items():
        if s["next"] and s["next"] in spells:
            next_rank[s["next"]] = sid
    for sid, s in spells.items():
        s["next"] = next_rank.get(sid, 0)

    # ---- talents
    tabs = {}
    for r in rows("TalentTab"):
        mask = int(num(r["ClassMask"]))
        cls = classes_for_mask(mask)
        if len(cls) == 1:
            tabs[r["ID"]] = {"name": r["Name_lang"], "class": cls[0], "order": int(num(r["OrderIndex"]))}
    talents = []
    for r in rows("Talent"):
        tab = tabs.get(r["TabID"])
        if not tab:
            continue
        ranks = [int(num(r[f"SpellRank_{i}"])) for i in range(9)]
        ranks = [x for x in ranks if x]
        if not ranks:
            continue
        name = names.get(str(ranks[0]), "?")
        desc = spell_text.get(str(ranks[0]), ("", ""))[1]
        prereq = [int(num(r[f"PrereqTalent_{i}"])) for i in range(3)]
        prereq_rank = [int(num(r[f"PrereqRank_{i}"])) for i in range(3)]
        pre = [(p, prereq_rank[i] + 1) for i, p in enumerate(prereq) if p]
        talents.append({
            "id": int(r["ID"]), "name": name, "class": tab["class"], "tab": tab["name"], "tabOrder": tab["order"],
            "tier": int(num(r["TierID"])), "col": int(num(r["ColumnIndex"])), "ranks": ranks, "prereq": pre, "desc": desc,
        })
    talents.sort(key=lambda t: (t["class"], t["tabOrder"], t["tier"], t["col"]))

    os.makedirs(a.out_dir, exist_ok=True)
    # ---- Spells.lua
    out = [
        "-- GENERATED by scripts/build_spells.py from wago.tools DB2 exports. Do not edit by hand.",
        f"-- product {a.product}, client build {build}, {len(spells)} class spells",
        "-- Row layout: name, class, tree, rank, level, cost, power(0 mana/1 rage/3 energy), cast ms, cooldown ms, gcd ms, duration ms,",
        "--             school, direct base, heal base, dot tick base, hot tick base, period ms, points per level, next rank id, acquire",
        "local ADDON, FO = ...",
        "FO.Seed = FO.Seed or {}",
        f'FO.Seed.spellBuild = "{build}"',
        f"FO.Seed.spellCount = {len(spells)}",
        "FO.Seed.spells = {}",
        "local S = FO.Seed.spells",
    ]
    ids = sorted(spells)
    for start in range(0, len(ids), CHUNK):
        out.append("do local f = function()")
        for sid in ids[start:start + CHUNK]:
            s = spells[sid]
            out.append("S[%d]={%s,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%g,%g,%g,%g,%d,%g,%d,%d}" % (
                sid, lua_str(s["name"]), lua_str(s["class"]), lua_str(s["tree"]), s["rank"], s["level"], s["cost"], s["power"],
                s["cast"], s["cd"], s["gcd"], s["dur"], s["school"], s["dd"], s["heal"], s["dot"], s["hot"], s["period"], s["ppl"],
                s["next"], s["acquire"]))
        out.append("end f() end")
    with open(os.path.join(a.out_dir, "Spells.lua"), "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")

    # ---- Talents.lua
    out = [
        "-- GENERATED by scripts/build_spells.py from wago.tools DB2 exports. Do not edit by hand.",
        f"-- product {a.product}, client build {build}, {len(talents)} talents",
        "-- Row layout: id, name, class, tab, tabOrder, tier, col, {rank spell ids}, {{prereq talent id, rank}}, description",
        "local ADDON, FO = ...",
        "FO.Seed = FO.Seed or {}",
        f'FO.Seed.talentBuild = "{build}"',
        "FO.Seed.talents = {}",
        "local T = FO.Seed.talents",
    ]
    for t in talents:
        ranks = "{" + ",".join(str(x) for x in t["ranks"]) + "}"
        pre = "{" + ",".join("{%d,%d}" % p for p in t["prereq"]) + "}"
        out.append("T[#T+1]={%d,%s,%s,%s,%d,%d,%d,%s,%s,%s}" % (
            t["id"], lua_str(t["name"]), lua_str(t["class"]), lua_str(t["tab"]), t["tabOrder"], t["tier"], t["col"], ranks, pre, lua_str(t["desc"][:160])))
    with open(os.path.join(a.out_dir, "Talents.lua"), "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    with open(os.path.join(a.out_dir, "BUILD"), "w", encoding="utf-8") as f:
        f.write(build + "\n")
    by_class = collections.Counter(s["class"] for s in spells.values())
    print(f"Spells.lua: {len(spells)} spells ({', '.join(f'{k} {v}' for k, v in sorted(by_class.items()))}); Talents.lua: {len(talents)} talents; build {build}", file=sys.stderr)

if __name__ == "__main__":
    main()
