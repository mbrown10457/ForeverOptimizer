# Orc Enhancement shaman: launch checklist

Built 2026-11-04 for launch day (Wed 2026-11-04, 15:00). Duo: Orc Enhancement shaman with an Orc Beast
Mastery hunter (see [Hunter_Launch_Checklist](Hunter_Launch_Checklist)). Quest names, givers and chain
order come from the QuestieDB Forever data (release 1.0.10); spell levels and talent tiers come from the
client seed (build 1.60.1.70753). Quest IDs 9xxxx are new in Forever and were not in Classic. QuestieDB
has no coordinates for most of the shaman quest NPCs yet, so the quest text and the Classic locations
named here are what you have; the addon records every giver the first time you talk to them.

## Before Wednesday

- [ ] Install from PowerShell with the one line in [WINDOWS_README](https://github.com/mbrown10457/ForeverOptimizer/blob/main/WINDOWS_README.md). Run it today, not Wednesday, so any error is fixed in time.
- [ ] Same ruleset as the hunter (Forever has no realms: one mega-server per ruleset, Normal, PvP or RP, and no transfers between them), both Horde. Characters need a first and last name, unique as a pair.
- [ ] Both take First Aid. The shaman is the duo's healer, but bandages still cover the hunter while you drink.
- [ ] Decide who takes Skinning and who takes Mining for early cash. Mining suits the shaman: the Call of Earth quest sends you to the rocks anyway.

## Character creation

- [ ] Orc, Shaman. Classic Orc racials: Blood Fury, Hardiness, Axe Specialization, Command (pet damage, which you will not use). Confirm on the creation screen; Forever may have reworked them.
- [ ] You start with Healing Wave and Lightning Bolt. Rockbiter Weapon is a level 1 trainer spell, not a starting one: learn it from Shikrik before you leave the Den and put it on your weapon. Everything after that is melee.

## First five minutes in the world

- [ ] Character select: AddOns button shows both ForeverOptimizer and QuestieDB ticked. Tick "Load out of date AddOns" if the client complains.
- [ ] `/reload` if the HUD is not on screen.
- [ ] `/fo checklist`, then `/fo verify`, `/fo errors`, `/fo combatlog`, `/fo qdb`.
- [ ] Open the map (M). The coordinates line and the Full map button in the bottom corners confirm the overlay loaded. The button shows the unexplored parts of Durotar darker; click it to go back to the normal map.
- [ ] `/fo build use 1` selects "Enhancement leveling". `/fo build` shows the next points at every level.
- [ ] `/fo rotation` prints the shaman priority with estimated damage per mana.
- [ ] `/fo shaman` is your status line: shield charges, weapon imbue time left, totems down, mana. It also warns when a fight starts without a shield or an imbue, and when the imbue has two minutes left.
- [ ] Bind Toggle HUD and Next waypoint: Esc, Key Bindings, ForeverOptimizer.
- [ ] `/fo manual` if you want the whole command list in game.

## Levels 1 to 5: Valley of Trials

Kill quests count for both of you in a group. Collection quests need one drop per player.

- [ ] Your Place In The World (Kaltunk) to Gornek in the Den.
- [ ] Cutting Teeth: 10 Mottled Boars, back to Gornek.
- [ ] Rune-Inscribed Parchment from Gornek to Shikrik, the shaman trainer in the Den. The hunter gets Etched Parchment to Jen'shan.
- [ ] Sting of the Scorpid: 10 Scorpid Worker Tails, per player.
- [ ] Galgar's Cactus Apple Surprise: 10 Cactus Apples, per player.
- [ ] Wayward Weapons (new in Forever): 6 Abandoned Training Weapons to Kzan Thornslash in the Den.
- [ ] Level 3: Lazy Peons (Foreman Thazz'ril), then Thazz'ril's Pick.
- [ ] Level 4, the Earth Totem. Call of Earth from Canaga Earthcaller in the Valley: 2 Felstalker Hooves (Felstalkers, level 3 to 4, north side of the Valley), back to Canaga; then find Spirit Rock and drink the Earth Sapta; the Minor Manifestation of Earth hands you Rough Quartz; back to Canaga for the Earth Totem. Three short quests, do them before Sarkoth.
- [ ] Train at 4: Earth Shock, Stoneskin Totem (needs the Earth Totem in your bags).
- [ ] Vile Familiars (Zureetha Fargaze, outside the Den), then Burning Blade Medallion, then Report to Sen'jin Village.
- [ ] Level 5: Sarkoth (Hana'zua), then report to Gornek.

## Levels 5 to 10: Razor Hill and Sen'jin

- [ ] A Peon's Burden (Ukor, on the road) to Innkeeper Grosk. Set your hearth at Razor Hill.
- [ ] Train at 6: Earthbind Totem, Healing Wave II. Train at 8: Lightning Shield, Earth Shock II, Lightning Bolt II, Rockbiter Weapon II, Stoneclaw Totem. Lightning Shield stays up from here to 60.
- [ ] Razor Hill: Vanquish the Betrayers then From The Wreckage (Gar'Thok); Carry Your Weight; Encroachment at 10. New in Forever: Legging It, For Honor, This Fruit Could Bite Back, Break a Few Eggs.
- [ ] Sen'jin: Practical Prey, Thwarting Kolkar Aggression, Minshina's Skull, A Solvent Spirit. New: Forgotten Loa Idols, Lost in the Shadows, Bloodtalon Matriarch.
- [ ] Zalazane (10) as a duo once the hunter has a pet.
- [ ] Learn First Aid. Healing Wave is the duo's healing; bandages are for the hunter while you drink.
- [ ] `/fo shaman` between pulls. If the imbue line says LOW, recast Rockbiter before the next fight, not during it.

## Level 10: the Fire Totem

Four short quests and one trip to the Barrens. Searing Totem, your first damage totem, needs the Fire Totem, so start this the moment you hit 10.

- [ ] Call of Fire: Swart (Razor Hill shaman trainer) or Searn Firewarder (Orgrimmar) sends you to Kranal Fiss in the Barrens, in the hills east of the road from Durotar.
- [ ] Kranal Fiss gives you the Torch of the Dormant Flame to carry to Telf Joolam in Durotar.
- [ ] Telf Joolam wants 1 Fire Tar and 1 Reagent Pouch. Fire Tar drops from Razormane quilboar in the northern Barrens (levels 10 to 13). The Reagent Pouch drops from Burning Blade Cultists (10 to 11) in Durotar: Skull Rock, north of Orgrimmar, where the hunter and a warlock would be anyway.
- [ ] Defeat the Minor Manifestation of Fire (level 12) and place the Glowing Ember in the brazier atop the Shrine of Eternal Flame, then carry the Torch of Eternal Flame back to Kranal Fiss for the Fire Totem. Bring the hunter: the Manifestation is a duo fight at 10.
- [ ] Train at 10: Flame Shock, Flametongue Weapon, Searing Totem, Strength of Earth Totem.
- [ ] First talent point: Ancestral Knowledge. `/fo build` names the next point from here on.
- [ ] Hunter, same trip: The Hunter's Path, Taming the Beast three times, Training the Beast in Orgrimmar.

## Water and Air totems

- [ ] Level 20, Call of Water: Islen Waterseer on the Barrens coast near Ratchet sends you to Brine in the Southern Barrens, who wants three waterskins filled (the watering hole below her hut, the well at Tarren Mill in Hillsbrad, the Ruins of Stardust in Ashenvale), then Islen sends you to the Corrupt Manifestation of Water in Silverpine Forest. It is a long trip; Healing Stream Totem and Mana Spring Totem wait on it, so do it at 20 to 22 with the Ghost Wolf you train at 20.
- [ ] Level 30, Call of Air: Prate Cloudseer in Thousand Needles. Windfury Totem comes with it; Windfury Weapon is a trainer spell at 30 and replaces Rockbiter.

## Duo playbook

- The hunter's pet tanks. You are the healer with a weapon: Lightning Shield up, Rockbiter on, totems down, then melee.
- Pulling: the hunter pulls with Auto Shot onto the pet. You walk in behind it. Lightning Bolt only to pull something the hunter cannot reach, or at a runner.
- Totems do not move. Drop Strength of Earth and Searing where you will fight for two or more pulls, not for one mob.
- Earth Shock on cooldown; it is also your interrupt, so hold it when a caster is next. Flame Shock from 10 on anything that lives past 12 seconds. Frost Shock from 20 for runners.
- Healing: Healing Wave on the pet between pulls and on the hunter when a second mob gets through. Lesser Healing Wave from 20 in combat. Heal the pet before the hunter's Mend Pet; your mana regenerates faster than its health does.
- Adds: Stoneclaw Totem, then Earthbind to walk away. The hunter has Concussive Shot and, from 20, Freezing Trap.
- Mana: drink below 40%. `/fo shaman` shows drink share; above 30% means too many Lightning Bolts, or it is time to hunt for the Water Shield rune.
- Collection quests are the slow part of a duo. Split up only for those, inside shout range.

## Trainer milestones 10 to 30 (seed data)

| Level | Learn |
|---|---|
| 10 | Flame Shock, Flametongue Weapon, Searing Totem, Strength of Earth Totem |
| 12 | Ancestral Spirit, Purge, Healing Wave III |
| 14 | Earth Shock III, Lightning Bolt III, Stoneskin Totem II |
| 16 | Cure Poison, Lightning Shield II, Rockbiter Weapon III |
| 18 | Tremor Totem, Flame Shock II, Flametongue Weapon II, Healing Wave IV, Stoneclaw Totem II |
| 20 | Ghost Wolf, Frost Shock, Lesser Healing Wave, Healing Stream Totem, Frostbrand Weapon, Totemic Recall, Call of the Elements, Lightning Bolt IV, Searing Totem II |
| 22 | Cure Disease, Poison Cleansing Totem, Water Breathing |
| 24 | Frost Resistance Totem, Earth Shock IV, Lightning Shield III, Rockbiter Weapon IV, Strength of Earth Totem II, Stoneskin Totem III, Healing Wave V |
| 26 | Far Sight, Magma Totem, Mana Spring Totem, Flametongue Weapon III, Lightning Bolt V |
| 28 | Fire Resistance Totem, Flametongue Totem, Water Walking, Flame Shock III, Frostbrand Weapon II, Lesser Healing Wave II, Stoneclaw Totem III |
| 30 | Windfury Weapon, Grounding Totem, Reincarnation, Astral Recall, Nature Resistance Totem, Call of the Ancestors, Healing Stream Totem II, Searing Totem III |

`/fo skip` lists ranks that are cheap to skip when gold is short. Totemic Recall and Call of the Elements at 20 are Forever additions; Classic shamans never had them.

## Talent order (Enhancement leveling, `/fo build use 1`)

Forever's shaman trees are not the Classic ones (Elemental Alacrity and Elemental Mastery replaced the old deep Elemental talents), so this order was read from the seed, not from memory. Flurry needs Thundering Strikes 5; Stormstrike needs Elemental Weapons 3 and 30 points in the tree.

| Levels | Talent |
|---|---|
| 10 to 14 | Ancestral Knowledge 5 |
| 15 to 19 | Thundering Strikes 5 |
| 20 | Two-Handed Axes and Maces |
| 21 to 22 | Improved Ghost Wolf 2 |
| 23 to 24 | Enhancing Totems 2 |
| 25 to 29 | Flurry 5 |
| 30 to 32 | Elemental Weapons 3 |
| 33 to 34 | Improved Weapon Totems 2 |
| 35 to 39 | Weapon Mastery 5 |
| 40 | Stormstrike |
| 41 to 45 | Toughness 5 |
| 46 to 48 | Improved Lightning Shield 3 |
| 49 to 51 | Anticipation 3 |
| 52 to 60 | Elemental: Convection 5, Concussion 4 |

## Runes to watch for

Forever ships Season-of-Discovery-style engraved abilities. The shaman ones in the seed, by slot: gloves Water Shield, Lava Lash, Lava Burst, Molten Blast; chest Dual Wield Specialization, Two-Handed Mastery, Shield Mastery, Overload, Healing Rain; pants Earth Shield, Way of Earth, Ancestral Guidance, Greater Ghost Wolf; belt Maelstrom Weapon, Fire Nova, Power Surge; bracers Static Shock, Rolling Thunder, Overcharged, Riptide; boots Spirit of the Alpha, Decoy Totem, Ancestral Awakening; helm Mental Dexterity, Burn, Tidal Waves; cloak Feral Spirit, Coherence, Storm, Earth, and Fire. Water Shield (gloves) and Earth Shield (pants) change the duo the most: mana for free and a shield on the pet. How Forever hands them out is unknown. The addon announces each one the moment it appears in your spellbook and records where you were; `/fo runes` lists them. Read every unusual item and object in Durotar.

## After session one

Log out, then run the collect line from the Windows README. It zips your data to the Desktop; send the zip to Mike.
