# Orc Demonology warlock: launch checklist

Built 2026-11-02 for launch day (Wed 2026-11-04, 15:00). Duo: Orc Demonology warlock with an Orc
Beast Mastery hunter (see [Hunter_Launch_Checklist](Hunter_Launch_Checklist)). Quest names, givers and
chain order come from the QuestieDB Forever data (release 1.0.10); spell levels and talent tiers come
from the client seed (build 1.60.1.70707). Quest IDs 9xxxx are new in Forever and were not in Classic.

## Before Wednesday

- [ ] Install from PowerShell with the one line in [WINDOWS_README](https://github.com/mbrown10457/ForeverOptimizer/blob/main/WINDOWS_README.md). Run it today, not Wednesday, so any error is fixed in time.
- [ ] Same ruleset as the hunter (Forever has no realms: one mega-server per ruleset, Normal, PvP or RP, and no transfers between them), both Horde. Characters need a first and last name, unique as a pair.
- [ ] Both take First Aid. Decide who takes Skinning and who takes Mining for early cash.

## Character creation

- [ ] Orc, Warlock. Classic Orc racials: Command (pet damage, which includes the Voidwalker), Blood Fury, Hardiness, Axe Specialization. Confirm on the creation screen; Forever may have reworked them.
- [ ] You start with Shadow Bolt, Immolate, Demon Skin and Summon Imp. Summon the Imp before leaving the Den.

## First five minutes in the world

- [ ] Character select: AddOns button shows both ForeverOptimizer and QuestieDB ticked. Tick "Load out of date AddOns" if the client complains.
- [ ] `/reload` if the HUD is not on screen.
- [ ] `/fo checklist`, then `/fo verify`, `/fo errors`, `/fo combatlog`, `/fo qdb`.
- [ ] Open the map (M). The coordinates line and pins confirm the overlay loaded.
- [ ] `/fo build use 2` selects "Demonology leveling". `/fo build` shows the next points at every level.
- [ ] `/fo rotation` prints the warlock priority with estimated damage per mana.
- [ ] `/fo alerts shards 2` so the shard warning fires before you are out, not at zero.
- [ ] Bind Toggle HUD and Next waypoint: Esc, Key Bindings, ForeverOptimizer.
- [ ] `/fo manual` if you want the whole command list in game.

## Levels 1 to 5: Valley of Trials

Kill quests count for both of you in a group. Collection quests need one drop per player.

- [ ] Your Place In The World (Kaltunk) to Gornek in the Den.
- [ ] Cutting Teeth: 10 Mottled Boars, back to Gornek.
- [ ] Tainted Parchment from Gornek to Nartok, the warlock trainer inside the Den. The hunter gets Etched Parchment to Jen'shan.
- [ ] Sting of the Scorpid: 10 Scorpid Worker Tails, per player.
- [ ] Galgar's Cactus Apple Surprise: 10 Cactus Apples, per player.
- [ ] Wayward Weapons (new in Forever): 6 Abandoned Training Weapons to Kzan Thornslash in the Den.
- [ ] Level 3: Lazy Peons (Foreman Thazz'ril), then Thazz'ril's Pick.
- [ ] Train at 4: Corruption, Curse of Weakness. Corruption is your main damage from here to 60.
- [ ] Vile Familiars, warlock version: 6 Vile Familiar Heads to Ruzan, then speak with Zureetha Fargaze outside the Den.
- [ ] Level 5: Sarkoth (Hana'zua), then report to Gornek.
- [ ] Burning Blade Medallion (Zureetha Fargaze) to Report to Sen'jin Village.

## Levels 5 to 10: Razor Hill and Sen'jin

- [ ] A Peon's Burden (Ukor, on the road) to Innkeeper Grosk. Set your hearth at Razor Hill.
- [ ] Train at 6: Life Tap, Shadow Bolt II. Train at 8: Bane of Agony, Fear.
- [ ] Razor Hill: Vanquish the Betrayers then From The Wreckage (Gar'Thok); Carry Your Weight; Encroachment at 10. New in Forever: Legging It, For Honor, This Fruit Could Bite Back, Break a Few Eggs.
- [ ] Sen'jin: Practical Prey, Thwarting Kolkar Aggression, Minshina's Skull, A Solvent Spirit. New: Forgotten Loa Idols, Lost in the Shadows, Bloodtalon Matriarch.
- [ ] Zalazane (10) as a duo once both pets exist.
- [ ] Learn First Aid. Bandages plus Drain Life are the duo's healing before Health Funnel at 12.
- [ ] `/fo warlock` shows shards, demon and mana. Keep 3 to 5 Soul Shards; Drain Soul the last mob of a pull.

## Level 10: the Voidwalker

- [ ] Gan'rul's Summons from Ophek (Durotar warlock trainer) sends you to Gan'rul Bloodeye in Orgrimmar's Cleft of Shadow.
- [ ] Creature of the Void: retrieve the Tablet of Verga from Skull Rock, north of Orgrimmar. A duo job; the hunter is doing the same trip for Training the Beast.
- [ ] The Binding: use the Glyphs of Summoning to summon and subdue a Voidwalker, then return to Gan'rul.
- [ ] Train at 10: Summon Voidwalker, Drain Soul, Create Healthstone, Demon Skin II, Immolate II.
- [ ] Voidwalker on Defensive. Torment on autocast, Sacrifice off autocast (keep it for emergencies).
- [ ] First talent point: Demonic Embrace. `/fo build` names the next point from here on.

## Duo playbook

- Voidwalker tanks. The hunter's pet attacks second. You open with Corruption, then Shadow Bolt; Bane of Agony on anything that lives past 12 seconds.
- Pulling: you send the Voidwalker; the hunter holds Auto Shot until the mob is on it.
- Life Tap below 40% mana when above 60% health. The Voidwalker has the aggro, not you.
- Runners and adds: Fear the second mob; the hunter has Concussive Shot and, from 20, Freezing Trap.
- Healing: Health Funnel from 12, Drain Life from 14, bandages between pulls.
- Collection quests are the slow part of a duo. Split up only for those, inside shout range.

## Trainer milestones 10 to 22 (seed data)

| Level | Learn |
|---|---|
| 10 | Summon Voidwalker, Drain Soul, Create Healthstone, Demon Skin II, Immolate II |
| 12 | Health Funnel, Curse of Weakness II, Shadow Bolt III |
| 14 | Drain Life, Corruption II, Curse of Recklessness |
| 16 | Life Tap II, Unending Breath |
| 18 | Create Soulstone, Searing Pain |
| 20 | Demon Armor, Rain of Fire, Shadowburn, Ritual of Summoning, Summon Succubus or Incubus, Health Funnel II, Immolate III, Shadow Bolt IV |
| 22 | Eye of Kilrogg, Drain Life II, Curse of Weakness III, Create Healthstone II |

`/fo skip` lists ranks that are cheap to skip when gold is short.

## Talent order (Demonology leveling, `/fo build use 2`)

| Levels | Talent |
|---|---|
| 10 to 14 | Demonic Embrace 5 |
| 15 to 17 | Improved Voidwalker 3 |
| 18 to 22 | Fel Vitality 5 |
| 23 to 25 | Improved Imp 3 |
| 26 | Fel Domination |
| 27 to 29 | Improved Sayaad 3 |
| 30 to 34 | Unholy Power 5 |
| 35 | Demonic Sacrifice |
| 36 to 47 | Affliction: Improved Corruption 5, Improved Life Tap 2, Soul Siphon 5 |
| 48 to 60 | 13 points left to your taste; `/fo build` stops suggesting once the build is spent |

## Runes to watch for

Forever ships Season-of-Discovery-style engraved abilities. The warlock ones in the seed: Chaos Bolt, Haunt, Metamorphosis, Shadow Bolt Volley (gloves); Lake of Fire, Master Channeler, Demonic Tactics (chest); Demonic Grace, Demonic Pact, Everlasting Affliction (pants); Incinerate, Unstable Affliction, Immolation Aura, Summon Felguard (bracers); Shadowflame, Decimation, Dance of the Wicked, Demonic Knowledge (boots); Grimoire of Synergy, Invocation, Shadow and Flame (belt); Backdraft, Pandemic, Vengeance (helm); Infernal Armor, Mark of Chaos, Soul Siphon (cloak). How Forever hands them out is unknown. The addon announces each one the moment it appears in your spellbook and records where you were; `/fo runes` lists them. Read every unusual item and object in Durotar.

## After session one

Log out, then run the collect line from the Windows README. It zips your data to the Desktop; send the zip to Mike.
