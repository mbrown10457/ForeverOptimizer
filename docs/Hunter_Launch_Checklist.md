# Orc Beast Mastery hunter: launch checklist

Built 2026-11-02 for launch day (Wed 2026-11-04, 15:00). Duo: Orc Beast Mastery hunter (Mike) with an
Orc Demonology warlock. Quest names, givers and chain order come from the QuestieDB Forever data
(release 1.0.10); spell levels and talent tiers come from the client seed (build 1.60.1.70707).
Quest IDs 9xxxx are new in Forever and were not in Classic, so expect those to differ from memory.

## Before Wednesday

- [ ] `ForeverOptimizer` (symlink) and `QuestieDB` sit in `_forever_/Interface/AddOns`. Already done on this Mac.
- [ ] Friend installs from the v0.9.0 release zip with `scripts/install.ps1`, plus QuestieDB.
- [ ] Agree realm and names. Same realm, both Horde.
- [ ] Decide who handles First Aid (both should) and who takes Skinning + Leather/Mining for cash.

## Character creation

- [ ] Orc, Hunter. Orc racials worth knowing: Command (pet damage), Blood Fury, Hardiness, Axe Specialization. Confirm on the creation screen; Forever may have reworked them.
- [ ] Check the starting ranged weapon and ammo stack on first login. A Classic Orc hunter starts with a bow and arrows.

## First five minutes in the world

- [ ] Character select: AddOns button shows both addons ticked. Use "Load out of date AddOns" if the version check complains.
- [ ] `/reload` if the HUD is not on screen.
- [ ] `/fo checklist` (the in-game first-hour list), then `/fo verify`, `/fo errors`, `/fo combatlog`, `/fo qdb`.
- [ ] Open the map (M). Coordinates line and pins confirm the overlay loaded.
- [ ] `/fo build use 1` selects "Beast Mastery leveling". `/fo build` shows the next points at every level.
- [ ] `/fo rotation` prints the hunter priority with estimated damage per mana.
- [ ] `/fo alerts ammo 60` for the first session. The default threshold is 200 and would fire on a starting stack.
- [ ] Bind the HUD toggle and "next waypoint": Esc, Key Bindings, ForeverOptimizer.
- [ ] `/fo note first session` to stamp the start.

## Levels 1 to 5: Valley of Trials

Every kill quest counts for both of you in a group. Collection quests need one drop per player, so plan on them taking longer than the kill quests.

- [ ] Your Place In The World (Kaltunk) → Gornek in the Den.
- [ ] Cutting Teeth: 10 Mottled Boars, back to Gornek.
- [ ] Etched Parchment from Gornek → Jen'shan, the hunter trainer in the Valley. The warlock gets Tainted Parchment → Nartok inside the Den.
- [ ] Sting of the Scorpid: 10 Scorpid Worker Tails (per player).
- [ ] Galgar's Cactus Apple Surprise: 10 Cactus Apples near cactuses (per player).
- [ ] Wayward Weapons (new in Forever): 6 Abandoned Training Weapons → Kzan Thornslash in the Den.
- [ ] Level 3: Lazy Peons (Foreman Thazz'ril) → Thazz'ril's Pick.
- [ ] Train at 4: Serpent Sting, Aspect of the Monkey.
- [ ] Level 5: Sarkoth (Hana'zua) → report to Gornek.
- [ ] Vile Familiars → Burning Blade Medallion (Zureetha Fargaze, outside the Den) → Report to Sen'jin Village.

## Levels 5 to 10: Razor Hill and Sen'jin

- [ ] A Peon's Burden (Ukor, on the road) → Innkeeper Grosk. Set your hearth at Razor Hill while you are there.
- [ ] Train at 6: Arcane Shot, Hunter's Mark. Train at 8: Concussive Shot, Raptor Strike II.
- [ ] Razor Hill: Vanquish the Betrayers → From The Wreckage (Gar'Thok); Carry Your Weight (Furl Scornbrow); Encroachment at 10.
- [ ] Razor Hill, new in Forever: Legging It (Vel'rin Fang → Gar'Thok), For Honor (Tiragarde outskirts), This Fruit Could Bite Back (Cook Torka), Break a Few Eggs.
- [ ] Sen'jin: Practical Prey, Thwarting Kolkar Aggression, Minshina's Skull, A Solvent Spirit; new: Forgotten Loa Idols, Lost in the Shadows, A Pain in the Neck (needs an enchanter), Bloodtalon Matriarch.
- [ ] Zalazane (10) is a group quest in Classic. Do it as a duo with both pets once you have them.
- [ ] Learn First Aid. Linen bandages are the duo's only healing before Mend Pet and Health Funnel at 12.
- [ ] `/fo plan 10` for training costs ahead; `/fo eta 10` once an hour of data exists.

## Level 10: the pet

Thotar in Razor Hill runs the whole chain. The three tames go in this order.

- [ ] The Hunter's Path: from Jen'shan or an Orgrimmar hunter trainer, sends you to Thotar.
- [ ] Taming the Beast 1: Dire Mottled Boar.
- [ ] Taming the Beast 2: Surf Crawler.
- [ ] Taming the Beast 3: Armored Scorpid.
- [ ] Training the Beast: Ormak Grimshot in Orgrimmar teaches Tame Beast, Call Pet, Dismiss Pet, Revive Pet, Feed Pet and Beast Training.
- [ ] Tame your keeper. A boar (Charge) is the classic Durotar tank pet; cats in the Barrens hit harder. Forever adds pet abilities the seed lists under Beast Training (Savage Rend, Swipe, Tendon Rip, Web, Dust Cloud, Pinch, Mine!, Dismember). Which family teaches which is unknown until you tame one; `/fo spell <name>` shows ranks and levels.
- [ ] Feed it. `/fo hunter` reads happiness and the diet from the client. Boars eat everything.
- [ ] Growl on autocast. Pet on Defensive, not Aggressive, so it does not pull the next pack.
- [ ] First talent point: Endurance Training. `/fo build` confirms the next point from here on.
- [ ] Warlock, same trip: Gan'rul's Summons → Gan'rul Bloodeye in Orgrimmar's Cleft of Shadow → Creature of the Void (Tablet of Verga at Skull Rock) → The Binding (subdue a Voidwalker). Skull Rock is a duo job and feeds the Margoz chain at 12.

## Duo playbook

- Voidwalker tanks. Hunter pet attacks second. Hunter opens with Hunter's Mark, then Serpent Sting, then lets Auto Shot run. Warlock: Corruption, then Shadow Bolt.
- Runners: Concussive Shot, then Wing Clip at 12. Adds: warlock Fear, hunter Freezing Trap at 20.
- Pulling: the warlock sends the Voidwalker; the hunter does not Auto Shot until the mob is on the Voidwalker.
- Healing: nobody has one. Bandage between pulls, Mend Pet and Health Funnel from 12, Drain Life for the warlock.
- Collection quests are the slow part of a duo. Split up only for those, inside shout range.
- Both pets benefit from the Orc Command racial if it still exists in Forever.

## Trainer milestones 10 to 22 (seed data)

| Level | Learn |
|---|---|
| 10 | Aspect of the Hawk, Serpent Sting II, Track Humanoids, plus the pet spells from Training the Beast |
| 12 | Mend Pet, Wing Clip, Arcane Shot II, Distracting Shot |
| 14 | Eyes of the Beast, Eagle Eye, Scare Beast |
| 16 | Mongoose Bite, Immolation Trap, Raptor Strike III |
| 18 | Multi-Shot, Aspect of the Hawk II, Serpent Sting III, Track Undead |
| 20 | Freezing Trap, Disengage, Aspect of the Cheetah, Mend Pet II, Arcane Shot III, Distracting Shot II |
| 22 | Hunter's Mark II, Scorpid Sting |

`/fo skip` lists ranks that are cheap to skip when gold is short.

## Talent order (Beast Mastery leveling, `/fo build use 1`)

| Levels | Talent |
|---|---|
| 10 to 14 | Endurance Training 5 |
| 15 to 19 | Deadly Aspects 5 |
| 20 to 24 | Unleashed Fury 5 |
| 25 | Bestial Swiftness |
| 26 to 28 | Thick Hide 3 |
| 29 to 33 | Ferocity 5 |
| 34 | Intimidation |
| 35 to 39 | Frenzy 5 |
| 40 | Bestial Wrath |
| 41 to 46 | Improved Mend Pet 2, Spirit Bond 2, Bestial Discipline 2 |
| 47 to 60 | Marksmanship: Efficiency 5, Lethal Attacks 5, Improved Hunter's Mark 4 |

The warlock's "Demonology leveling" build was reordered the same way: Improved Voidwalker before Improved Imp.

## Runes to watch for

Forever ships Season-of-Discovery-style engraved abilities. The hunter ones in the seed: Kill Command, Chimera Shot, Flanking Strike, Carve, Heart of the Lion, Aspect of the Viper, Aspect of the Falcon, and rune versions of Serpent Sting and Raptor Strike. How Forever hands them out is unknown. In Season of Discovery the first ones came from starting-zone discoveries, so read every unusual item and object in Durotar. The rotation lists them as optional and `/fo rotation` shows which ones you know.

## After session one

Point Claude at the SavedVariables file:

```
/Applications/World of Warcraft/_forever_/WTF/Account/84702676#1/SavedVariables/ForeverOptimizerDB.lua
```

It answers the open questions: combat log restricted or not, secret values, map pins, QuestieDB loaded, and any errors from `/fo errors`.
