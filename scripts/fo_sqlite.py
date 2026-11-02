#!/usr/bin/env python3 -I
"""Offline analytics pipeline: ForeverOptimizer SavedVariables -> SQLite.

Usage:
  scripts/fo_sqlite.py <ForeverOptimizer.lua> [-o fo.sqlite]

Re-running upserts into the same database, so you can ingest after every
logout and keep history beyond the in-game caps. Tables:
  sessions, dungeons, zone_segments, mobs, drops, encounters, loot,
  prices, price_daily, vendor_prices, quests, nodes, respawns, verify, errors, notes
"""
import argparse, json, os, sqlite3, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))

def load(path):
    out = subprocess.run([sys.executable, "-I", os.path.join(HERE, "savedvars_to_json.py"), path, "--var", "ForeverOptimizerDB"],
                         capture_output=True, text=True, encoding="utf-8", check=True)
    return json.loads(out.stdout)

SCHEMA = """
create table if not exists sessions (id text primary key, char text, class text, level int, start int, stop int, elapsed int, zone text,
  xp int, kills int, gold int, loot_gold int, quest_gold int, vendor_sales int, repairs int, purchases int, training int, ah_spend int,
  ah_est int, vendor_est int, items int, consumables int, taxi int, deaths int, death_time real, quests_done int,
  t_quest int, t_grind int, t_dungeon int, t_travel int, t_rest int, t_town int, t_dead int, t_idle int,
  xp_quest int, xp_grind int, xp_dungeon int);
create table if not exists zone_segments (session_id text, zone text, xp int, kills int, gold int, loot_gold int, ah_est int, vendor_est int, deaths int,
  t_quest int, t_grind int, t_dungeon int, t_travel int, t_rest int, t_town int, t_dead int, t_idle int, primary key (session_id, zone));
create table if not exists dungeons (id text primary key, char text, name text, level int, start int, stop int, seconds int, xp int, kills int,
  gold int, ah_est int, vendor_est int, repairs int, post_repairs int, deaths int, drops_json text);
create table if not exists mobs (npc text primary key, name text, level int, type text, classification text, zone text, kills int, xp int, looted int,
  deaths int, kill_time real, kill_n int, gap_time real, gap_n int, hp_loss real, hp_n int);
create table if not exists drops (npc text, item int, name text, count int, loots int, primary key (npc, item));
create table if not exists encounters (t int, npc text, name text, mob_level int, player_level int, zone text, xp int, dur real, hp_loss real,
  mana_loss real, mobs_in_fight int, map_id int, x real, y real, primary key (t, npc, xp));
create table if not exists loot (t int, item int, qty int, npc text, vendor int, ah int, zone text, primary key (t, item, qty));
create table if not exists prices (item int, t int, min int, qty int, n int, primary key (item, t));
create table if not exists price_daily (item int, day int, lo int, hi int, sum real, n int, primary key (item, day));
create table if not exists vendor_prices (item int primary key, price real, t int, name text);
create table if not exists item_names (item int primary key, name text);
create table if not exists quests (quest int primary key, title text, level int, accept_json text, turnin_json text, objectives_json text,
  reward_xp int, reward_money int, accepted_at int, completed_at int, times_done int, last_duration int);
create table if not exists nodes (name text, kind text, map_id int, x real, y real, n int, last int, primary key (name, map_id, x, y));
create table if not exists respawns (npc text, name text, map_id int, x real, y real, confirmed_json text, bounds_json text, last_kill int,
  primary key (npc, map_id, x, y));
create table if not exists verify (t int primary key, version text, build text, toc text, checks_json text);
create table if not exists notes (session text, t int, elapsed int, level int, zone text, activity text, text text, primary key (session, t, text));
create table if not exists errors (key text primary key, where_ text, msg text, stack text, first int, last int, count int, version text, char text);
"""

def arr(x):
    """Lua arrays come through as lists, or dicts with "1","2" keys if sparse."""
    if isinstance(x, list): return x
    if isinstance(x, dict): return [x[k] for k in sorted(x, key=lambda k: int(k) if str(k).isdigit() else 0) if str(k).isdigit()]
    return []

def g(d, k, default=0):
    v = d.get(k, default) if isinstance(d, dict) else default
    return v if v is not None else default

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file"); ap.add_argument("-o", "--out", default="fo.sqlite")
    a = ap.parse_args()
    db = load(a.file)
    acc = db.get("account", {}); chars = db.get("chars", {})
    con = sqlite3.connect(a.out); con.executescript(SCHEMA); cur = con.cursor()
    n = {}
    def count(k): n[k] = n.get(k, 0) + 1

    for s in arr(g(acc.get("sessions", {}), "list", [])):
        t = g(s, "time", {}); xb = g(s, "xpBy", {})
        sid = f"{g(s,'char','?')}:{g(s,'start')}"
        cur.execute("insert or replace into sessions values (" + ",".join("?" * 37) + ")", (
            sid, g(s,"char"), g(s,"class"), g(s,"level"), g(s,"start"), g(s,"stop"), g(s,"elapsed"), g(s,"zone"),
            g(s,"xp"), g(s,"kills"), g(s,"gold"), g(s,"lootGold"), g(s,"questGold"), g(s,"vendorSales"), g(s,"repairs"), g(s,"purchases"),
            g(s,"training"), g(s,"ahSpend"), g(s,"ahEst"), g(s,"vendorEst"), g(s,"items"), g(s,"consumables"), g(s,"taxi"), g(s,"deaths"),
            g(s,"deathTime"), g(s,"questsDone"), g(t,"quest"), g(t,"grind"), g(t,"dungeon"), g(t,"travel"), g(t,"rest"), g(t,"town"), g(t,"dead"), g(t,"idle"),
            g(xb,"quest"), g(xb,"grind"), g(xb,"dungeon")))
        count("sessions")
        for note in arr(g(s, "notes", [])):
            cur.execute("insert or replace into notes values (?,?,?,?,?,?,?)", (sid, g(note,"t"), g(note,"elapsed"), g(note,"level"), g(note,"zone"), g(note,"activity"), g(note,"text")))
            count("notes")
        for zone, z in g(s, "zones", {}).items():
            zt = g(z, "time", {})
            cur.execute("insert or replace into zone_segments values (" + ",".join("?" * 17) + ")", (
                sid, zone, g(z,"xp"), g(z,"kills"), g(z,"gold"), g(z,"lootGold"), g(z,"ahEst"), g(z,"vendorEst"), g(z,"deaths"),
                g(zt,"quest"), g(zt,"grind"), g(zt,"dungeon"), g(zt,"travel"), g(zt,"rest"), g(zt,"town"), g(zt,"dead"), g(zt,"idle")))
            count("zone_segments")
    for d in arr(g(acc.get("sessions", {}), "dungeons", [])):
        cur.execute("insert or replace into dungeons values (" + ",".join("?" * 16) + ")", (
            f"{g(d,'char','?')}:{g(d,'start')}", g(d,"char"), g(d,"name"), g(d,"level"), g(d,"start"), g(d,"stop"), g(d,"seconds"), g(d,"xp"), g(d,"kills"),
            g(d,"gold"), g(d,"ahEst"), g(d,"vendorEst"), g(d,"repairs"), g(d,"postRepairs"), g(d,"deaths"), json.dumps(g(d,"drops",[]))))
        count("dungeons")
    mobs = acc.get("mobs", {})
    for npc, m in g(mobs, "mobs", {}).items():
        cur.execute("insert or replace into mobs values (" + ",".join("?" * 16) + ")", (
            str(npc), g(m,"name"), g(m,"level"), g(m,"type"), g(m,"classification"), g(m,"zone"), g(m,"kills"), g(m,"xp"), g(m,"looted"),
            g(m,"deaths"), g(m,"killTime"), g(m,"killN"), g(m,"gapTime"), g(m,"gapN"), g(m,"hpLoss"), g(m,"hpN")))
        count("mobs")
        for item, dd in g(m, "drops", {}).items():
            cur.execute("insert or replace into drops values (?,?,?,?,?)", (str(npc), int(item), g(dd,"name"), g(dd,"count"), g(dd,"n")))
            count("drops")
    for e in arr(g(mobs, "encounters", [])):
        cur.execute("insert or replace into encounters values (" + ",".join("?" * 14) + ")", (
            g(e,"t"), str(g(e,"npc")), g(e,"name"), g(e,"lvl"), g(e,"plvl"), g(e,"zone"), g(e,"xp"), g(e,"dur"), g(e,"hpLoss"), g(e,"manaLoss"),
            g(e,"mobsInFight"), g(e,"mapID"), g(e,"x"), g(e,"y")))
        count("encounters")
    for l in arr(g(acc.get("loot", {}), "log", [])):
        cur.execute("insert or replace into loot values (?,?,?,?,?,?,?)", (g(l,"t"), g(l,"item"), g(l,"qty"), str(g(l,"npc")), g(l,"vendor"), g(l,"ah"), g(l,"zone")))
        count("loot")
    pr = acc.get("prices", {})
    for item, name in g(pr, "names", {}).items():
        cur.execute("insert or replace into item_names values (?,?)", (int(item), name))
    for item, series in g(pr, "prices", {}).items():
        for p in arr(series):
            cur.execute("insert or replace into prices values (?,?,?,?,?)", (int(item), g(p,"t"), g(p,"min"), g(p,"qty"), g(p,"n"))); count("prices")
    for item, days in g(pr, "daily", {}).items():
        for day, r in days.items():
            cur.execute("insert or replace into price_daily values (?,?,?,?,?,?)", (int(item), int(day), g(r,"lo"), g(r,"hi"), g(r,"sum"), g(r,"n"))); count("price_daily")
    for item, v in g(pr, "vendor", {}).items():
        cur.execute("insert or replace into vendor_prices values (?,?,?,?)", (int(item), g(v,"price"), g(v,"t"), g(v,"name"))); count("vendor_prices")
    for qid, q in g(acc.get("quests", {}), "quests", {}).items():
        cur.execute("insert or replace into quests values (" + ",".join("?" * 12) + ")", (
            int(qid), g(q,"title"), g(q,"level"), json.dumps(g(q,"accept",{})), json.dumps(g(q,"turnin",{})), json.dumps(g(q,"objectives",{})),
            g(q,"rewardXP"), g(q,"rewardMoney"), g(q,"acceptedAt"), g(q,"completedAt"), g(q,"timesDone"), g(q,"lastDuration")))
        count("quests")
    farm = acc.get("farming", {})
    for name, node in g(farm, "nodes", {}).items():
        for p in arr(g(node, "points", [])):
            # a point is {mapID, x, y, n=, last=}: a list when the Lua table was pure-array, else a dict keyed "1","2","3","n","last"
            if isinstance(p, list): m, x, y, pn, last = p[0], p[1], p[2], 1, 0
            else: m, x, y, pn, last = p.get("1"), p.get("2"), p.get("3"), g(p, "n", 1), g(p, "last", 0)
            cur.execute("insert or replace into nodes values (?,?,?,?,?,?,?)", (name, g(node, "kind"), m, x, y, pn, last))
            count("nodes")
    for npc, sp in g(farm, "spawns", {}).items():
        for p in arr(g(sp, "points", [])):
            if isinstance(p, list): p = {"1": p[0], "2": p[1], "3": p[2]}
            if isinstance(p, dict):
                m, x, y = p.get("1"), p.get("2"), p.get("3")
                cur.execute("insert or replace into respawns values (?,?,?,?,?,?,?,?)", (str(npc), g(sp,"name"), m, x, y, json.dumps(arr(g(p,"confirmed",[]))), json.dumps(arr(g(p,"bounds",[]))), g(p,"lastKillT")))
                count("respawns")
    for e in arr(g(acc.get("errors", {}), "log", [])):
        cur.execute("insert or replace into errors values (?,?,?,?,?,?,?,?,?)", (g(e,"key"), g(e,"where"), g(e,"msg"), g(e,"stack"), g(e,"first"), g(e,"last"), g(e,"count"), g(e,"version"), g(e,"char")))
        count("errors")
    v = g(acc.get("verify", {}), "last", None)
    if v:
        cur.execute("insert or replace into verify values (?,?,?,?,?)", (g(v,"t"), g(v,"version"), g(v,"build"), g(v,"toc"), json.dumps(g(v,"checks",[])))); count("verify")
    con.commit()
    print(f"{a.out}: " + ", ".join(f"{k} {v}" for k, v in sorted(n.items())), file=sys.stderr)

if __name__ == "__main__":
    main()
