-- Minimal fake WoW client so ForeverOptimizer can be executed outside the game.
-- Not a faithful emulator: enough API surface to load every file, run the
-- lifecycle, and drive the main event paths. Lua 5.1 compat shims included.
unpack = unpack or table.unpack
function debugstack(level, top, bottom) return debug.traceback("", (level or 1)) end
local S = { clock = 1000, timers = {}, tickers = {}, out = {}, errors = {} }
_G.STUB = S

function strsplit(sep, str)
    local t = {}
    for piece in (str .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do t[#t + 1] = piece end
    return unpack(t)
end
function GetTime() return S.clock end
function time() return 1700000000 + S.clock end
date = os.date
function debugprofilestop() return S.clock * 1000 end
function InCombatLockdown() return S.inCombat == true end
function hooksecurefunc(name, fn)
    local orig = _G[name]
    _G[name] = function(...) local r = { orig(...) } fn(...) return unpack(r) end
end

DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg)
    S.out[#S.out + 1] = msg
    if msg:find("error in") or msg:find("failed:") or msg:find("OnTick error") then S.errors[#S.errors + 1] = msg end
    if S.verbose then print(msg) end
end }

C_Timer = {
    After = function(delay, fn) S.timers[#S.timers + 1] = { at = S.clock + delay, fn = fn } end,
    NewTicker = function(interval, fn) S.tickers[#S.tickers + 1] = { interval = interval, fn = fn, next = S.clock + interval } return { Cancel = function() end } end,
}
function S.advance(seconds)
    for i = 1, seconds do
        S.clock = S.clock + 1
        for _, t in ipairs(S.tickers) do
            if S.clock >= t.next then t.next = S.clock + t.interval t.fn() end
        end
        local due = {}
        for j = #S.timers, 1, -1 do
            if S.timers[j].at <= S.clock then due[#due + 1] = table.remove(S.timers, j) end
        end
        for _, t in ipairs(due) do t.fn() end
    end
end
function S.flush() S.advance(0) local due = S.timers S.timers = {} for _, t in ipairs(due) do t.fn() end end

-- Frames ---------------------------------------------------------------------
local function Region()
    local r = { shown = true }
    for _, m in ipairs({ "SetPoint", "SetText", "SetJustifyH", "SetWordWrap", "SetTextColor", "SetSize", "SetBackdrop", "SetBackdropColor",
                         "SetScale", "SetMovable", "EnableMouse", "RegisterForDrag", "SetClampedToScreen", "SetHeight", "StartMoving", "StopMovingOrSizing", "AddLine",
                         "SetTexture", "SetAlpha", "SetOwner", "ClearLines", "SetFontObject", "SetWidth" }) do
        r[m] = function() end
    end
    r.Show = function(self) self.shown = true end
    r.Hide = function(self) self.shown = false end
    r.IsShown = function(self) return self.shown end
    r.SetShown = function(self, v) self.shown = v end
    r.GetPoint = function() return "TOPRIGHT", nil, "TOPRIGHT", -20, -200 end
    r.CreateFontString = function() return Region() end
    r.SetScript = function(self, k, fn) self.scripts = self.scripts or {} self.scripts[k] = fn end
    return r
end
S.registered = {}
function CreateFrame(kind, name, parent, template)
    local f = Region()
    f.HookScript = Region_HookScript
    local setScript = f.SetScript
    f.SetScript = function(self, k, fn) setScript(self, k, fn) if k == "OnUpdate" then S.updaters = S.updaters or {} S.updaters[#S.updaters + 1] = self end end
    f.RegisterEvent = function(self, ev)
        if (ev == "COMBAT_LOG_EVENT_UNFILTERED" or ev == "COMBAT_LOG_EVENT") and not S.combatLogAllowed then error("event is restricted") end
        S.registered[ev] = true
        S.frames = S.frames or {}
        for _, f in ipairs(S.frames) do if f == self then return end end
        S.frames[#S.frames + 1] = self
    end
    return f
end
UIParent, GameTooltip, ItemRefTooltip = Region(), Region(), Region()

-- Combat log (optimistic path; S.combatLogAllowed=false simulates the 12.x refusal)
S.combatLogAllowed = true
S.clArgs = { n = 0 }
function CombatLogGetCurrentEventInfo() return unpack(S.clArgs, 1, S.clArgs.n) end
-- S.cl(subevent, src, dst, ...): src/dst = { guid=, name=, flags= }; ... = prefix+suffix params
function S.cl(sub, src, dst, ...)
    local a = { S.clock, sub, false, src.guid, src.name, src.flags or 0, 0, dst.guid, dst.name, dst.flags or 0, 0, ... }
    a.n = 11 + select("#", ...)
    S.clArgs = a
    S.fire("COMBAT_LOG_EVENT_UNFILTERED")
end
bit = bit or { band = load("return function(a, b) return a & b end")() }
COMBATLOG_OBJECT_AFFILIATION_MINE, COMBATLOG_OBJECT_TYPE_PLAYER, COMBATLOG_OBJECT_TYPE_PET, COMBATLOG_OBJECT_TYPE_GUARDIAN = 0x1, 0x400, 0x1000, 0x2000
function UnitRangedDamage() return 2.0, 50, 70 end
S.spellCost = {}
-- Spellbook / talents (classic tab API)
S.knownSpells = { [75] = true, [1978] = true, [3044] = true, [1130] = true, [2973] = true, [5116] = true, [2643] = true, [136] = true, [14260] = true }
function IsSpellKnown(id) return S.knownSpells[id] == true end
function IsPlayerSpell(id) return S.knownSpells[id] == true end
S.talents = {
    { "Beast Mastery", { { "Endurance Training", 1, 3, 5, 5 }, { "Deadly Aspects", 1, 2, 2, 5 }, { "Thick Hide", 2, 3, 0, 3 }, { "Unleashed Fury", 3, 3, 0, 5 } } },
    { "Marksmanship", { { "Efficiency", 1, 3, 0, 5 } } },
    { "Survival", { { "Deflection", 1, 3, 0, 5 } } },
}
function GetNumTalentTabs() return #S.talents end
function GetTalentTabInfo(i) local t = S.talents[i] local pts = 0 for _, x in ipairs(t[2]) do pts = pts + x[4] end return t[1], nil, pts end
function GetNumTalents(tab) return #S.talents[tab][2] end
function GetTalentInfo(tab, i) local x = S.talents[tab][2][i] return x[1], nil, x[2], x[3], x[4], x[5] end
function GetSpellPowerCost(id) return { { type = 0, cost = S.spellCost[id] or 0 } } end
function Region_HookScript(self, k, fn) self.hooks = self.hooks or {} self.hooks[k] = self.hooks[k] or {} table.insert(self.hooks[k], fn) end

-- World map (modern map canvas API subset: data providers + pin pools)
function Mixin(obj, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do obj[k] = v end end return obj end
function CreateFromMixins(...) return Mixin({}, ...) end
MapCanvasDataProviderMixin = { OnAdded = function(self, map) self.owningMap = map end, GetMap = function(self) return self.owningMap end, RefreshAllData = function() end, RemoveAllData = function() end }
MapCanvasPinMixin = { SetPosition = function(self, x, y) self.x, self.y = x, y end, SetScalingLimits = function() end, UseFrameLevelType = function() end, OnLoad = function() end }
S.worldMap = { mapID = nil, cursor = { 0.25, 0.5 } }
WorldMapFrame = Region()
WorldMapFrame.shown = false
WorldMapFrame.providers, WorldMapFrame.pins = {}, {}
WorldMapFrame.HookScript = Region_HookScript
WorldMapFrame.GetMapID = function() return S.worldMap.mapID or S.pos.map end
WorldMapFrame.AddDataProvider = function(self, p) self.providers[#self.providers + 1] = p p:OnAdded(self) end
WorldMapFrame.AcquirePin = function(self, template, ...)
    local pin = CreateFromMixins(_G[(template:gsub("Template$", "")) .. "Mixin"] or MapCanvasPinMixin)
    Mixin(pin, Region()) pin.Icon = Region() pin.template = template
    for k, v in pairs(_G[(template:gsub("Template$", "")) .. "Mixin"] or {}) do pin[k] = v end
    if pin.OnLoad then pin:OnLoad() end
    if pin.OnAcquired then pin:OnAcquired(...) end
    self.pins[#self.pins + 1] = pin
    return pin
end
WorldMapFrame.RemoveAllPinsByTemplate = function(self, template) for i = #self.pins, 1, -1 do if self.pins[i].template == template then table.remove(self.pins, i) end end end
WorldMapFrame.ScrollContainer = Region()
WorldMapFrame.ScrollContainer.GetNormalizedCursorPosition = function() return S.worldMap.cursor[1], S.worldMap.cursor[2] end
WorldMapFrame.Show = function(self)
    self.shown = true
    for _, p in ipairs(self.providers) do p:RefreshAllData() end
    for _, fn in ipairs(self.hooks and self.hooks.OnShow or {}) do fn(self) end
end
WorldMapFrame.Hide = function(self) self.shown = false for _, fn in ipairs(self.hooks and self.hooks.OnHide or {}) do fn(self) end end
function S.mapUpdate() for _, f in ipairs(S.updaters or {}) do f.scripts.OnUpdate(f, 0.2) end end
function S.fire(ev, ...)
    for _, f in ipairs(S.frames or {}) do
        local h = f.scripts and f.scripts.OnEvent
        if h and S.registered[ev] then h(f, ev, ...) end
    end
    S.flush()
end
SlashCmdList = {}

-- Player / world -------------------------------------------------------------
S.player = { name = "Mikeo", realm = "Forever", class = { "Hunter", "HUNTER" }, level = 23, xp = 4000, xpMax = 20000, money = 123456,
             zone = "Stranglethorn Vale", sub = "Grom'gol", dead = false, ghost = false, speed = 0, bind = "Booty Bay", inInstance = false }
local P = S.player
function UnitName(u) if u == "player" then return P.name end return S.units and S.units[u] and S.units[u].name end
function UnitFullName(u) return P.name, P.realm end
function GetRealmName() return P.realm end
function UnitClass() return P.class[1], P.class[2] end
function UnitRace() return "Orc", "Orc" end
function UnitFactionGroup() return "Horde", "Horde" end
function UnitLevel(u) if u == "player" then return P.level end return S.units and S.units[u] and S.units[u].level or 0 end
function UnitXP() return P.xp end
function UnitXPMax() return P.xpMax end
function GetMoney() return P.money end
function GetRealZoneText() return P.zone end
function GetZoneText() return P.zone end
function GetSubZoneText() return P.sub end
function GetBindLocation() return P.bind end
function GetUnitSpeed() return P.speed end
function UnitIsDeadOrGhost() return P.dead or P.ghost end
function UnitIsGhost() return P.ghost end
function UnitOnTaxi() return false end
function UnitPower() return 800 end
function UnitPowerMax() return 1000 end
function IsInInstance() return P.inInstance, P.inInstance and "party" or "none" end
function GetInstanceInfo() return P.inInstance and "The Deadmines" or P.zone, P.inInstance and "party" or "none" end
function UnitExists(u) return u == "player" or (S.units and S.units[u] ~= nil) end
function UnitGUID(u) if u == "player" then return "Player-1-ABC" end return S.units and S.units[u] and S.units[u].guid end
function UnitCanAttack(a, b) return S.units and S.units[b] and S.units[b].hostile or false end
function UnitIsPlayer(u) return S.units and S.units[u] and S.units[u].player or false end
function UnitIsDead(u) return S.units and S.units[u] and S.units[u].dead or false end
function UnitCreatureType(u) return S.units and S.units[u] and S.units[u].ctype or "Humanoid" end
function UnitClassification(u) return S.units and S.units[u] and S.units[u].cls or "normal" end
function UnitIsUnit(a, b) return a == b end
function UnitInParty() return false end
function UnitInRaid() return false end
function GetProfessions() return 1, 2 end
function GetProfessionInfo(i) if i == 1 then return "Mining", nil, 75, 150, nil, nil, 186 end return "Engineering", nil, 60, 150, nil, nil, 202 end
S.repairCost = 4000
function GetRepairAllCost() return S.repairCost, true end
function RepairAllItems() P.money = P.money - S.repairCost S.repairCost = 0 end
function GetInventoryItemLink(u, slot) return S.equipped and S.equipped[slot] end
function GetInventoryItemCount() return 0 end
function GetPetHappiness() return 3 end
function GetBuildInfo() return "1.60.1", "99999", "Oct 31 2026", 16001 end
function UnitHealth() return S.hp or 1000 end
function UnitHealthMax() return 1000 end
function UnitPowerType() return 0 end

-- Loot -----------------------------------------------------------------------
S.loot = {}
function GetNumLootItems() return #S.loot end
function GetLootSlotInfo(i) local l = S.loot[i] return "icon", l.name, l.qty, nil, l.quality, false, false, nil, true end
function GetLootSlotLink(i) local l = S.loot[i] return l.itemID and ("|cffffffff|Hitem:" .. l.itemID .. "::::::::23:::::|h[" .. l.name .. "]|h|r") or nil end
function GetLootSlotType(i) return S.loot[i].itemID and 1 or 2 end
function GetLootSourceInfo(i) return S.loot[i].guid, S.loot[i].qty end

-- Items ----------------------------------------------------------------------
S.items = {
    [2589] = { name = "Linen Cloth", quality = 1, sell = 13, class = 7, sub = 5, stack = 20 },
    [117] = { name = "Tough Jerky", quality = 1, sell = 1, class = 0, sub = 5, stack = 20 },
    [2318] = { name = "Light Leather", quality = 1, sell = 20, class = 7, sub = 6, stack = 20 },
    [3182] = { name = "Spider's Silk", quality = 2, sell = 100, class = 7, sub = 5, stack = 10 },
    [3300] = { name = "Rabbit's Foot", quality = 0, sell = 55, class = 15, sub = 0, stack = 5 },
    [6265] = { name = "Soul Shard", quality = 1, sell = 0, class = 15, sub = 0, stack = 1 },
    [2512] = { name = "Rough Arrow", quality = 1, sell = 0, class = 6, sub = 2, stack = 200 },
    [2770] = { name = "Copper Ore", quality = 1, sell = 15, class = 7, sub = 7, stack = 20 },
    [2840] = { name = "Copper Bar", quality = 1, sell = 20, class = 7, sub = 7, stack = 20 },
    [1515] = { name = "Rough Boomstick", quality = 1, sell = 500, class = 2, sub = 3, stack = 1, equip = "INVTYPE_RANGED", stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 8.2 } },
    [2092] = { name = "Worn Dagger", quality = 1, sell = 10, class = 2, sub = 15, stack = 1, equip = "INVTYPE_WEAPON", stats = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 3.1 } },
    [9797] = { name = "Elegant Robes", quality = 2, sell = 500, class = 4, sub = 1, stack = 1, equip = "INVTYPE_ROBE", stats = { ITEM_MOD_AGILITY_SHORT = 5, ITEM_MOD_STAMINA_SHORT = 4 } },
}
local function link(id) local it = S.items[id] return "|cffffffff|Hitem:" .. id .. "::::::::23:::::|h[" .. it.name .. "]|h|r" end
C_Item = {
    GetItemInfo = function(id) id = tonumber(id) or tonumber(tostring(id):match("item:(%d+)")) local it = S.items[id] if not it then return nil end
        return it.name, link(id), it.quality, 10, 1, "t", "st", it.stack, it.equip or "", "icon", it.sell, it.class, it.sub, 0 end,
    GetItemInfoInstant = function(id) id = tonumber(id) or tonumber(tostring(id):match("item:(%d+)")) local it = S.items[id] if not it then return nil end
        return id, "t", "st", it.equip or "", "icon", it.class, it.sub end,
    GetItemNameByID = function(id) local it = S.items[id] return it and it.name end,
    RequestLoadItemDataByID = function() end,
    GetItemCount = function(id) local n = 0 for _, b in ipairs(S.bags) do if b.itemID == id then n = n + b.count end end return n end,
    GetItemStats = function(lnk) local id = tonumber(lnk:match("item:(%d+)")) local it = S.items[id] return it and it.stats end,
}
S.bags = { { itemID = 2589, count = 14, quality = 1 }, { itemID = 3300, count = 2, quality = 0 }, { itemID = 117, count = 10, quality = 1 },
           { itemID = 2512, count = 150, quality = 1 }, { itemID = 3182, count = 3, quality = 2 } }
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 16 or (bag <= 4 and 6 or (bag == -1 and 24 or 0)) end,
    GetContainerNumFreeSlots = function(bag) return bag == 0 and (16 - #S.bags) or 6 end,
    GetContainerItemInfo = function(bag, slot) if bag ~= 0 then return nil end local b = S.bags[slot] if not b then return nil end
        return { itemID = b.itemID, stackCount = b.count, quality = b.quality, hyperlink = link(b.itemID), hasNoValue = S.items[b.itemID].sell == 0, isBound = false } end,
    UseContainerItem = function(bag, slot) local b = table.remove(S.bags, slot) if b then P.money = P.money + S.items[b.itemID].sell * b.count S.sold = (S.sold or 0) + 1 end end,
    GetItemCooldown = function() return 0, 0 end,
}
NUM_BAG_SLOTS, BANK_CONTAINER, NUM_BANKBAGSLOTS = 4, -1, 7

-- Map ------------------------------------------------------------------------
S.pos = { map = 1434, x = 0.40, y = 0.50 }
C_Map = {
    GetBestMapForUnit = function() return S.pos.map end,
    GetPlayerMapPosition = function() return { GetXY = function() return S.pos.x, S.pos.y end } end,
    GetMapWorldSize = function() return 6000, 4000 end,
    GetMapInfo = function(id) return { name = "Stranglethorn Vale", mapID = id } end,
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function(p) S.waypoint = p end,
}
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end, GetSuperTrackedQuestID = function() return 0 end }

-- Quests ---------------------------------------------------------------------
S.quests = { { questID = 101, title = "Bloodscalp Ears", level = 23, objectives = { { text = "Bloodscalp Ear", type = "item", numFulfilled = 2, numRequired = 12, finished = false } } },
             { questID = 102, title = "Singing Blue Shards", level = 24, objectives = { { text = "Singing Crystal Shard", type = "item", numFulfilled = 0, numRequired = 10, finished = false } } } }
C_QuestLog = {
    GetNumQuestLogEntries = function() return #S.quests end,
    GetInfo = function(i) local q = S.quests[i] return q and { questID = q.questID, title = q.title, level = q.level, isHeader = false } end,
    GetQuestObjectives = function(id) for _, q in ipairs(S.quests) do if q.questID == id then return q.objectives end end end,
    GetTitleForQuestID = function(id) for _, q in ipairs(S.quests) do if q.questID == id then return q.title end end return "Quest " .. id end,
    GetNextWaypoint = function() return nil end,
    AddQuestWatch = function() end,
    IsComplete = function(id) return S.completeInLog and S.completeInLog[id] == true end,
    IsQuestFlaggedCompleted = function(id) return S.qdb.completed[id] == true end,
}
function UnitRace() return "Orc", "Orc", 2 end

-- QuestieDB fake (public API subset: entity getters, GetAllIds, Exists, IdsByName, Support zone map)
S.qdb = {
    completed = { [204] = true },
    quests = {
        [101] = { name = "Bloodscalp Ears", questLevel = 23, requiredLevel = 20, startedBy = { { 2497 } }, finishedBy = { { 2497 } },
                  objectives = { { { 580, "Bloodscalp Warrior" } }, nil, { { 4106, "Bloodscalp Ear" } } }, zoneOrSort = 33, objectivesText = { "Collect 12 Bloodscalp Ears" } },
        [102] = { name = "Singing Blue Shards", questLevel = 24, requiredLevel = 22, startedBy = { { 2497 } }, finishedBy = { { 2498 } }, objectives = { nil, { { 3001, "Crystal" } } } },
        [201] = { name = "Welcome to the Jungle", questLevel = 24, requiredLevel = 22, startedBy = { { 2497 } }, finishedBy = { { 2498 } }, objectives = {} },
        [202] = { name = "Too High", questLevel = 40, requiredLevel = 38, startedBy = { { 2497 } }, finishedBy = { { 2497 } }, objectives = {} },
        [203] = { name = "Chained", questLevel = 23, requiredLevel = 20, startedBy = { { 2497 } }, finishedBy = { { 2497 } }, objectives = {}, preQuestSingle = { 101 } },
        [204] = { name = "Done Already", questLevel = 23, requiredLevel = 20, startedBy = { { 2497 } }, finishedBy = { { 2497 } }, objectives = {} },
        [205] = { name = "Horde Only Elsewhere", questLevel = 23, requiredLevel = 20, startedBy = { { 2499 } }, finishedBy = { { 2499 } }, objectives = {}, requiredRaces = 1 },
    },
    npcs = {
        [2497] = { name = "Nimboya", spawns = { [33] = { { 48.0, 85.0 } } }, questStarts = { 101, 201, 202, 203, 204 }, minLevel = 30, maxLevel = 30 },
        [2498] = { name = "Kebok", spawns = { [33] = { { 40.0, 60.0 } } }, questEnds = { 102, 201 } },
        [2499] = { name = "Far Away", spawns = { [1] = { { 10.0, 10.0 } } } },
        [580]  = { name = "Bloodscalp Warrior", spawns = { [33] = { { 50.0, 30.0 }, { 52.0, 33.0 } } }, minLevel = 22, maxLevel = 24 },
    },
    objects = { [3001] = { name = "Singing Crystal", spawns = { [33] = { { 30.0, 40.0 } } } } },
    items = { [4106] = { name = "Bloodscalp Ear", npcDrops = { 580 } } },
}
local function copy(v) if type(v) ~= "table" then return v end local t = {} for k, x in pairs(v) do t[k] = copy(x) end return t end
local function Entity(store, numericDefaults, tableAlways)
    local E = {}
    E.Exists = function(id) return store[id] ~= nil end
    E.GetAllIds = function(hash) local ids = {} for id in pairs(store) do ids[#ids + 1] = id end table.sort(ids) if hash then local h = {} for _, id in ipairs(ids) do h[id] = true end return h end return ids end
    E.IdsByName = function(name) local out = {} for id, r in pairs(store) do if r.name == name then out[#out + 1] = id end end table.sort(out) return #out > 0 and out or nil end
    E.Get = function(id, key) local r = store[id] if not r then return nil end local v = r[key] if v == nil then if numericDefaults[key] then return 0 end if tableAlways[key] then return {} end return nil end if type(v) == "table" and next(v) == nil and not tableAlways[key] then return nil end return copy(v) end
    return setmetatable(E, { __index = function(_, key) return function(id) return E.Get(id, key) end end })
end
local qNum = { questLevel = true, requiredLevel = true, requiredMaxLevel = true, requiredRaces = true, requiredClasses = true, zoneOrSort = true, nextQuestInChain = true, parentQuest = true, questFlags = true, specialFlags = true, sourceItemId = true }
QuestDB = Entity(S.qdb.quests, qNum, { startedBy = true, finishedBy = true, objectives = true })
NpcDB = Entity(S.qdb.npcs, { minLevel = true, maxLevel = true, rank = true, zoneID = true, factionID = true, npcFlags = true }, {})
ObjectDB = Entity(S.qdb.objects, { zoneID = true, factionID = true }, {})
ItemDB = Entity(S.qdb.items, { itemLevel = true, requiredLevel = true, class = true, subClass = true, startQuest = true, flags = true }, {})
LibQuestieDB = {
    Quest = QuestDB, Npc = NpcDB, Object = ObjectDB, Item = ItemDB,
    readMode = "baked", contractVersion = 4, minSupportedContract = 1,
    RequireContract = function(v) return v >= 1 and v <= 4, nil end,
    Enum = { raceMaskById = { [1] = 1, [2] = 2, [3] = 4, [4] = 8, [5] = 16, [6] = 32, [7] = 64, [8] = 128 } },
    Support = { Get = function(name) if name == "ZoneDB" then return { private = { areaIdToUiMapId = "return { [33] = " .. S.pos.map .. ", [1] = 1426 }" } } end end },
}

-- Misc API groups ------------------------------------------------------------
C_UnitAuras = { GetAuraDataByIndex = function(u, i) if i == 1 and S.eating then return { name = "Food" } end if i == 1 and S.buffed then return { name = "Well Fed" } end return nil end }
C_Spell = { GetSpellName = function(id) return ({ [2575] = "Mining", [2366] = "Herb Gathering" })[id] end }
C_Reputation = { GetNumFactions = function() return 1 end, GetFactionDataByIndex = function() return { name = "Booty Bay", reaction = 5, currentStanding = 3400, currentReactionThreshold = 3000, nextReactionThreshold = 9000, isWatched = true } end }
Enum = { LootSlotType = { Item = 1, Money = 2 }, ItemClass = { Consumable = 0, Weapon = 2, Armor = 4, Reagent = 5, Projectile = 6, Tradegoods = 7, Questitem = 12, Miscellaneous = 15 },
         BagIndex = { Backpack = 0, Bank = -1, BankBag_1 = 5 }, TooltipDataType = { Item = 0 }, CraftingReagentType = { Basic = 1 } }
TooltipDataProcessor = { AddTooltipPostCall = function(t, fn) S.tooltipFn = fn end }
GetNumTrainerServices = function() return 3 end
GetTrainerServiceInfo = function(i) return ({ { "Arcane Shot", "Rank 3", "available" }, { "Multi-Shot", "Rank 2", "unavailable" }, { "Aspect of the Hawk", "Rank 1", "used" } })[i][1],
    ({ { "Arcane Shot", "Rank 3", "available" }, { "Multi-Shot", "Rank 2", "unavailable" }, { "Aspect of the Hawk", "Rank 1", "used" } })[i][2],
    ({ { "Arcane Shot", "Rank 3", "available" }, { "Multi-Shot", "Rank 2", "unavailable" }, { "Aspect of the Hawk", "Rank 1", "used" } })[i][3] end
GetTrainerServiceCost = function(i) return ({ 4500, 9000, 0 })[i] end
GetTrainerServiceLevelReq = function(i) return ({ 22, 28, 10 })[i] end
GetTrainerServiceTypeFilter = function() return false end
SetTrainerServiceTypeFilter = function() end
IsTradeskillTrainer = function() return false end
GetMerchantNumItems = function() return 2 end
GetMerchantItemInfo = function(i) if i == 1 then return "Tough Jerky", "icon", 25, 1, -1, true, true, nil end return "Rough Arrow", "icon", 10, 200, -1, true, true, nil end
GetMerchantItemLink = function(i) return i == 1 and link(117) or link(2512) end

COMBAT_XP_GAIN1 = "%s dies, you gain %d experience."
GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT = "%d Gold", "%d Silver", "%d Copper"
FACTION_STANDING_INCREASED = "Reputation with %s increased by %d."

-- Loader ---------------------------------------------------------------------
function S.loadAddon(dir)
    local ns = {}
    local toc = io.open(dir .. "/ForeverOptimizer.toc"):read("*a")
    local order = {}
    for line in toc:gmatch("[^\r\n]+") do
        if line:match("^[%w\\/_]+%.lua$") then order[#order + 1] = line:gsub("\\", "/") end
    end
    for _, f in ipairs(order) do
        local chunk, err = loadfile(dir .. "/" .. f)
        if not chunk then error("load " .. f .. ": " .. err) end
        local ok, e = pcall(chunk, "ForeverOptimizer", ns)
        if not ok then error("exec " .. f .. ": " .. tostring(e)) end
    end
    return ns, order
end
return S
