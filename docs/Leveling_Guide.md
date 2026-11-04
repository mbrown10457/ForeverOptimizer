# Leveling guide and direction arrow

`/fo guide` is a step-by-step leveling route in the style of Wisp or RestedXP: accept this quest, do it, turn it in, go here, set your hearth, train, reach a level. The window follows you; the arrow at the top of the screen points at the current step. Built 2026-11-04 for launch.

## Using it

- The guide picks a route for your faction and race on login when one fits your level. `/fo guide list` shows every route, `/fo guide use <n>` picks one by hand.
- Quest steps complete themselves from your quest log: accepting moves to the objectives, finishing them moves to the turn-in, turning in moves on. Travel steps complete when the arrow arrives. Train, hearth and note steps complete when you do them (training is detected when you close a trainer at the right level, the hearth from your bind location) or when you press Skip.
- Steps for another class are hidden. A step you cannot do yet says why ("needs level 6", "not in your log") and waits for Skip rather than guessing.
- Buttons: Back, Skip, Arrow (re-point), Hide. Same buttons on the HUD's Guide tab. Key bindings: "Toggle leveling guide window" and "Leveling guide: skip step".
- `/fo guide goto <n>` jumps to a step, `/fo guide reset` starts the route over, `/fo guide arrow off` keeps the window but leaves the arrow to `/fo next` and `/fo route`.
- Progress is saved per character.

## The arrow

A TomTom-style arrow with yards left. Green when you are heading at it, yellow when off to a side, red when it is behind you. Right-click clears it; drag moves it; `/fo arrow lock` pins it. Arrival radius is 15 yards (`/fo arrow arrive <yards>`).

Targets come from the guide, from `/fo next` and `/fo route` (which also set the client's own map waypoint when the client allows it), or by hand: `/fo arrow 52 43 Razor Hill` points at 52,43 on the current map.

Bearings use the client's world-space conversion when it exists, so a target on another map still points the right way; without it the arrow uses the current map's world size and only works on the same map.

## Routes

| Route | Faction | Races | Levels | Steps |
|---|---|---|---|---|
| Orc & Troll 1-20 | Horde | Orc, Troll | 1 to 20 | 438 |
| Tauren 1-20 | Horde | Tauren | 1 to 20 | 408 |

Orc & Troll 1-20: Valley of Trials, Razor Hill, Sen'jin and the Echo Isles, the northern Durotar loop, Orgrimmar at 10 with the class quests (hunter pet, warlock Voidwalker, shaman fire totem, priest Hex of Weakness), the Skull Rock loop at 11 with the warrior's Path of Defense, then the Barrens from Far Watch and the Crossroads through Ratchet, the Sludge Fen, Regthar's bunker and Camp Taurajo.

Tauren 1-20: Red Cloud Mesa, Bloodhoof Village with the well-cleansing and Rite of Vision chains, the eastern and northern loops (Venture Co., Red Rocks, the Wildmane well), Thunder Bluff at 10 with the class quests (hunter tames, druid Bear Form through Moonglade, shaman Call of Earth earlier on the mesa), the Barrens from Camp Taurajo to the Crossroads with Devrak's free flight back to Thunder Bluff, the warrior and shaman detour to Far Watch and Durotar, then the same Barrens section as the Orc route.

Both routes share the Barrens from the Crossroads quest board to Camp Taurajo (`scripts/routes/barrens-crossroads-12-20.inc`, spliced in with `INCLUDE`). The druid's Cure Poison chain sits there at 14, and the level 20 notes point warriors, priests and druids at their next class quest. It takes the Forever-only quests (IDs above 90000) where they sit on the way; their objective text comes from your log since nobody has mapped them yet. Group quests (Zalazane, Counterattack, Northwatch) are marked so a solo player skips them.

The step order is a first draft written from the quest database, not from a measured run. Expect to reorder a few things; `/fo guide goto` and Skip get you past anything wrong, and the route file is easy to fix.

## Adding or fixing a route

Routes are text files in `scripts/routes/`, one step per line:

```
ROUTE orc-troll-1-20 | Orc & Troll 1-20 | Horde | Orc,Troll | 1 | 20
A 4641 | Kaltunk stands right where you spawn.          accept quest 4641, with a note
C 788  | Mottled Boars all over the valley floor.        complete its objectives
T 788                                                     turn it in
@HUNTER A 3087                                            hunter only (@-WARLOCK = everyone but warlocks)
@HUNTER,Troll A 3082                                      hunter and Troll only (a race token limits a step to that race)
INCLUDE barrens-crossroads-12-20.inc                      splice a shared file in here
GOTO Razor Hill | 1411 52.0 43.5 | Follow the road north.
HEARTH Razor Hill | 1411 51.5 41.6
@HUNTER TRAIN 6 | Thotar | 1411 51.9 43.5 | Arcane Shot, Hunter's Mark.
LEVEL 6 | Encroachment needs level 6.
NOTE Buy a bag.
```

`scripts/build_routes.py <QuestieDB_Forever.toc>` turns them into `ForeverOptimizer/Data/Routes.lua`, looking up every quest's title, giver, finisher and first objective position in QuestieDB so the guide works for people who do not install QuestieDB. With QuestieDB installed the guide prefers its live nearest-spawn data, and your own recorded quest positions win over both. `lua test/validate_data.lua` checks every step (known kinds, class tags, coordinates on accept, turn-in and travel steps, turn-ins without an accept).

Coordinates are `map x y` with the uiMap id (Durotar 1411, Orgrimmar 1454, Mulgore 1412, Thunder Bluff 1456, the Barrens 1413, Moonglade 1450) and 0 to 100 map percentages.

Class quest IDs differ by race in the starting zones (Orc hunters read Etched Parchment, Troll hunters Etched Tablet), so those steps carry both a class and a race tag. Steps with no race tag show to every race on the route.
