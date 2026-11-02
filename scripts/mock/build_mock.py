import json, re, sys
dump = open(sys.argv[1], encoding='utf-8').read().split('\n')
tabs, cmds, ctrls = {}, {}, {}
order = []
cur = None; kind = None
for line in dump:
    if line.startswith('##TABS'): order = line[7:].split('|'); continue
    if line.startswith('##CTRL'):
        ctrls[cur] = [{'label': x.lstrip('*'), 'active': x.startswith('*')} for x in line[7:].split('|') if x]
        continue
    if line.startswith('##TAB '): cur = line[6:]; kind = 'tab'; tabs[cur] = []; continue
    if line.startswith('##CMD '): cur = line[6:]; kind = 'cmd'; cmds[cur] = []; continue
    if cur is None or line == '': continue
    (tabs if kind == 'tab' else cmds)[cur].append(line)

# Sample Overview while a session is live (same string formats as Dashboard/Overview.lua + Classes/Hunter.lua)
tabs['Overview'] = [
    "|cff80c0ffgrind|r  00:42  Durotar",
    "XP 1830  |cffaaaaaa2614/hr|r  TTL 00:38",
    "Kills 31  |cffaaaaaa44/hr|r  deaths 0",
    "Net 9s 40c  |cffaaaaaa13s/hr|r",
    "Eff 42s 10c  |cffaaaaaa60s/hr|r  (bags 32s 70c)",
    "Downtime 18%  rest 05:10  travel 02:30",
    "|cffaaaaaaPos|r 52.3, 41.7",
]
HUNTER = ["Ammo 58 |cffff6060LOW|r", "Pet Boar content", "Aspect of the Hawk", "Pet damage 41%", "Auto Shot 112, clipped 6% (14s lost)"]
tabs['Hunter'] = HUNTER
tabs['Leveling'][0] = "quest 2900/hr  grind 2614/hr  dng --/hr"
tabs['Leveling'][1] = "Spot: 44 k/hr x 59 xp = 2614 xp/hr"
tabs['Leveling'][2] = "kill 7.1s + gap 74s"
tabs['Leveling'][3] = "Scorpid Worker Tail 6/10 42%"
tabs['Leveling'][4] = "Cactus Apple 3/10 37%"
tabs['Leveling'][5] = "L12 hist: q 2900  g 2614  d --"
tabs['Character'] = ["L12 Hunter  1g 12s", "Training: 1s 20c now, 9s 85c thru L16", "mount + ridin…: 1g 12s/90g", "First Aid 42/75", "Skinning 38/75", "Hearth: Razor Hill"]
tabs['Economy'] = ["Loot 9s 40c  quests 14s 0c  vendor 12s 30c", "Repairs 0c  buys 2s 40c  train 1s 20c", "Bags: AH 32s 70c  vendor 8s 15c  (14 items)", "Net 13s/hr  Eff 60s/hr", "Slots 9/36 free", "AH: 2 items priced, no scan yet"]
tabs['History'] = ["vs 1 sessions: xp |cff60ff60+12%|r  gold |cff60ff60+4%|r  down |cff60ff60-9|r", "11/04 L10 Durotar      2330 xp/hr 11s"]

tabs['Meter'] = [
    "|cffffd100DPS|r fight 00:38  total 7.9k",
    "1. |cffabd473Mike|r 118/s  57% |cffaaaaaapet 41%|r",
    "2. |cff8788eeGrok|r 90/s  43% |cffaaaaaapet 36%|r",
]
if 'Meter' not in order: order.insert(2, 'Meter')
ctrls['Meter'] = [{'label': l, 'active': a} for l, a in [('Fight', True), ('Last', False), ('Session', False), ('DPS', True), ('HPS', False), ('Mine', False)]]
c = {}
gr = "|cff66b3ffFO:Grinding|r "
core = "|cff4ce57fFO:Core|r "
cls = "|cffff99e6FO:Classes|r "
c['/fo hunter'] = [cls + l for l in HUNTER]
c['/fo build'] = [
    "|cff99ffccFO:Character|r Beast Mastery leveling (1/2)  level 12, 3 points to place",
    "|cff99ffccFO:Character|r   Endurance Training                 Beast Mastery 3/5  have 2",
    "|cff99ffccFO:Character|r   Deadly Aspects                     Beast Mastery 0/5  have 0",
    "|cff99ffccFO:Character|r   Unleashed Fury                     Beast Mastery 0/5  have 0",
    "|cff99ffccFO:Character|r |cffffd100next points:|r Endurance Training 2/3",
]
c['/fo rotation'] = cmds['/fo rotation']
c['/fo verify'] = cmds['/fo verify'][:8] + [core + "  ... 28 more lines ...", cmds['/fo verify'][-1]]
c['/fo checklist'] = cmds['/fo checklist']
c['/fo nearby'] = ["|cffe6cc4cFO:Quest|r 3 quests available on Durotar:",
    "|cffe6cc4cFO:Quest|r     140y  |cffffd100L7|r  Vanquish the Betrayers           from Gar'Thok (52.0, 43.0)",
    "|cffe6cc4cFO:Quest|r     160y  |cffffd100L7|r  Carry Your Weight                from Furl Scornbrow (52.4, 42.1)",
    "|cffe6cc4cFO:Quest|r     900y  |cffff8040L6|r  Legging It                       from Vel'rin Fang (55.6, 74.1)"]
c['/fo route'] = ["|cffe6cc4cFO:Quest|r Quest route on Durotar, 3 stops, ~1420 yards:",
    "|cffe6cc4cFO:Quest|r    1. Scorpid Worker Tail            (46.2, 60.8) +0y [recorded]",
    "|cffe6cc4cFO:Quest|r    2. Cactus Apple                   (43.9, 64.0) +380y [database: Cactus Apple]",
    "|cffe6cc4cFO:Quest|r    3. Gornek                         (46.3, 69.4) +1040y [turn in]",
    "|cffe6cc4cFO:Quest|r waypoint set to stop 1."]
c['/fo map'] = ["|cffccccccFO:Dashboard|r world map overlay: pins |cff80ff80available|r, coords on",
    "|cffccccccFO:Dashboard|r layers: nodes on, rares on, spawns on, quests on, objectives on, turnins on, min seen 1",
    "|cffccccccFO:Dashboard|r this map (Durotar): 4 herb, 3 ore, 1 rare, 6 spawn point, 3 quest available, 2 objective, 1 turn in"]
c['/fo combatlog'] = [core + "combat log: live, 1842 events this session, 0 secret values, amounts visible"]
c['/fo dps'] = [gr + "DPS, fight (00:38 active): 7.9k damage",
    gr + "   1. |cffabd473Mike          |r     4.5k     118/s   57.0%  pet 41%",
    gr + "      |cffaaaaaaAuto Shot 38%, Serpent Sting 14%, Arcane Shot 7%|r",
    gr + "   2. |cff8788eeGrok          |r     3.4k      90/s   43.0%  pet 36%"]
c['/fo hps'] = [gr + "HPS, fight (00:38 active): 420 healing",
    gr + "   1. |cff8788eeGrok          |r      420      11/s  100.0%  overheal 18%"]
c['/fo help'] = cmds.get('/fo help', [])
c['/fo manual'] = [core + "(the manual window opens; see the Window button on the Help tab)"]
c['/fo alerts'] = [core + "alerts: sound on | flash on | rare on | respawn on | bags on (<= 3 free) | ammo on (< 60) | shards on (< 3)"]
c['/fo errors'] = [core + "no errors saved."]
c['/fo eta 20'] = ["|cff99ffccFO:Character|r To L20: ~18400 xp at 2614 xp/hr (recent sessions near this level) = 07:02:20 of play. Rough: later levels are estimated at +9%/level."]
c['/fo note pet tamed'] = [core + "noted (2 this session): pet tamed"]
c['/fo qdb'] = ["|cffe6cc4cFO:Quest|r quest database: QuestieDB baked mode, 5232 quests, 341 zone mappings, contract 4"]
alert = core + "|cffff8000!|r |cffff6060ammo low:|r 58 left."
rare = core + "|cffff8000!|r |cffff8000rare|r Fizzle Darkstorm seen at Durotar (54.1, 51.0)"
data = {"tabOrder": order, "tabs": tabs, "ctrls": ctrls, "manual": cmds.get('/fo help', []), "cmds": c, "cmdOrder": ['/fo checklist','/fo verify','/fo hunter','/fo build','/fo rotation','/fo nearby','/fo route','/fo dps','/fo hps','/fo map','/fo combatlog','/fo qdb','/fo alerts','/fo eta 20','/fo note pet tamed','/fo errors','/fo help','/fo manual'], "alert": alert, "rare": rare}
tpl = open(sys.argv[2], encoding='utf-8').read()
out = tpl.replace('/*DATA*/null', json.dumps(data, ensure_ascii=False))
open(sys.argv[3], 'w', encoding='utf-8').write(out)
print("wrote", sys.argv[3], len(out))
