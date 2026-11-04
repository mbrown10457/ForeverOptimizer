local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Quest")

-- ===========================================================================
-- Quest database adapter. Reads QuestieDB (an optional dependency, installed
-- separately) through its public runtime API: quest names, levels, givers,
-- finishers, objectives, prerequisites and chains, plus NPC/object spawn
-- coordinates. Nothing from it is copied into this addon; it is queried live
-- and cached per session. Your own recorded positions (Quest.QuestTracker)
-- always count too, and win where QuestieDB has no coordinates, which its own
-- Forever notes say is common.
-- Without QuestieDB everything here reports unavailable and the quest modules
-- keep working from recorded data alone.
-- ===========================================================================
local Q = FO:NewModule("Quest.QuestDB", {
    account = "questdb",
    defaults = { settings = { levelAbove = 3, levelBelow = 6, showLowLevel = false, maxPinsPerQuest = 40 } },
})
FO.QuestDB = Q
Q.available, Q.reason = false, "not initialised"

local CLASS_BITS = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
local SCAN_TTL = 60

local LQ, QA, NA, OA, IA        -- LibQuestieDB and its entity APIs
local areaToMap, mapToArea = {}, {}
local qcache, spawnCache, objSpawnCache, itemCache = {}, {}, {}, {}
local scanCache = {}             -- mapID -> { at=, level=, rows= }

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, r = pcall(fn, ...)
    if ok then return r end
    return nil
end

local function LoadZoneMap()
    local ok, zdb = pcall(function() return LQ.Support.Get("ZoneDB") end)
    if not ok or type(zdb) ~= "table" then return false end
    local src = zdb.private and zdb.private.areaIdToUiMapId
    local t
    if type(src) == "string" then
        local chunk = (loadstring or load)(src)
        if chunk then local ok2, r = pcall(chunk) if ok2 and type(r) == "table" then t = r end end
    elseif type(src) == "table" then
        t = src
    end
    if not t then return false end
    for a, m in pairs(t) do
        local areaId, mapID = U.Num(a), U.Num(m)
        if areaId and mapID then
            areaToMap[areaId] = mapID
            mapToArea[mapID] = mapToArea[mapID] or areaId
        end
    end
    return true
end

function Q:OnEnable()
    LQ = _G.LibQuestieDB
    if not LQ then self.reason = "QuestieDB addon not installed (optional)" return end
    if LQ.RequireContract then
        local ok, res, msg = pcall(LQ.RequireContract, 1)
        if not ok or res == false then self.reason = "QuestieDB contract mismatch: " .. tostring(msg or res) return end
    end
    QA, NA, OA, IA = LQ.Quest or _G.QuestDB, LQ.Npc or _G.NpcDB, LQ.Object or _G.ObjectDB, LQ.Item or _G.ItemDB
    if not (QA and NA) then self.reason = "QuestieDB entity API missing" return end
    if not LoadZoneMap() then self.reason = "QuestieDB zone map unreadable" return end
    self.available, self.reason = true, nil
    self.mode = LQ.readMode or "?"
    print("QuestieDB connected (%s mode, contract %s): quest givers, objectives and turn-ins are seeded.", self.mode, tostring(LQ.contractVersion or "?"))
end

-- ---------------------------------------------------------------------------
-- Entities
-- ---------------------------------------------------------------------------
function Q:Quest(id)
    if not self.available or not id then return nil end
    local c = qcache[id]
    if c ~= nil then return c or nil end
    if Call(QA.Exists, id) ~= true then qcache[id] = false return nil end
    local q = {
        id = id, name = U.Str(Call(QA.name, id)) or ("quest " .. id),
        level = U.Num(Call(QA.questLevel, id)) or 0, reqLevel = U.Num(Call(QA.requiredLevel, id)) or 0, maxLevel = U.Num(Call(QA.requiredMaxLevel, id)) or 0,
        races = U.Num(Call(QA.requiredRaces, id)) or 0, classes = U.Num(Call(QA.requiredClasses, id)) or 0,
        zone = U.Num(Call(QA.zoneOrSort, id)) or 0,
        startedBy = Call(QA.startedBy, id) or {}, finishedBy = Call(QA.finishedBy, id) or {}, objectives = Call(QA.objectives, id) or {},
        preSingle = Call(QA.preQuestSingle, id), preGroup = Call(QA.preQuestGroup, id), exclusiveTo = Call(QA.exclusiveTo, id),
        nextInChain = U.Num(Call(QA.nextQuestInChain, id)) or 0, parent = U.Num(Call(QA.parentQuest, id)) or 0,
        flags = U.Num(Call(QA.questFlags, id)) or 0, special = U.Num(Call(QA.specialFlags, id)) or 0,
        objectivesText = Call(QA.objectivesText, id), triggerEnd = Call(QA.triggerEnd, id),
        childQuests = Call(QA.childQuests, id),
    }
    qcache[id] = q
    return q
end

-- spawns as { {mapID, x(0-1), y(0-1)}, ... }, instance sentinels dropped
local function ConvertSpawns(raw)
    local out = {}
    for areaId, pts in pairs(type(raw) == "table" and raw or {}) do
        local mapID = areaToMap[U.Num(areaId) or 0]
        if mapID then
            for _, p in ipairs(pts) do
                local x, y = U.Num(p[1]), U.Num(p[2])
                if x and y and x >= 0 and y >= 0 then out[#out + 1] = { mapID, x / 100, y / 100 } end
            end
        end
    end
    return out
end

function Q:NpcSpawns(npcID)
    if not self.available or not npcID then return {} end
    local c = spawnCache[npcID]
    if c then return c end
    c = ConvertSpawns(Call(NA.spawns, npcID))
    spawnCache[npcID] = c
    return c
end

function Q:ObjectSpawns(objectID)
    if not self.available or not objectID or not OA then return {} end
    local c = objSpawnCache[objectID]
    if c then return c end
    c = ConvertSpawns(Call(OA.spawns, objectID))
    objSpawnCache[objectID] = c
    return c
end

function Q:NpcName(npcID) return U.Str(Call(NA and NA.name, npcID)) end
function Q:ObjectName(objectID) return U.Str(Call(OA and OA.name, objectID)) end
function Q:NpcLevels(npcID) return U.Num(Call(NA and NA.minLevel, npcID)), U.Num(Call(NA and NA.maxLevel, npcID)) end

function Q:ItemSources(itemID)
    if not self.available or not IA or not itemID then return {}, {} end
    local c = itemCache[itemID]
    if c then return c.npcs, c.objects end
    c = { npcs = Call(IA.npcDrops, itemID) or {}, objects = Call(IA.objectDrops, itemID) or {} }
    itemCache[itemID] = c
    return c.npcs, c.objects
end

-- ---------------------------------------------------------------------------
-- Eligibility and availability
-- ---------------------------------------------------------------------------
local function Completed(qid)
    return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and Call(C_QuestLog.IsQuestFlaggedCompleted, qid) == true
end

local function PlayerRaceMask()
    local _, _, raceID = UnitRace("player")
    raceID = U.Num(raceID)
    local masks = LQ and LQ.Enum and LQ.Enum.raceMaskById
    if masks and raceID and masks[raceID] then return masks[raceID] end
    return nil
end

function Q:Eligible(q, level)
    level = level or FO.Player.level or 1
    if q.reqLevel > level then return false, "level" end
    if q.maxLevel ~= 0 and q.maxLevel < level then return false, "level" end
    local rm = PlayerRaceMask()
    if q.races ~= 0 and rm and (q.races % (rm * 2)) < rm then return false, "race" end   -- bit test without 32-bit ops
    local cb = CLASS_BITS[FO.Player.class or ""]
    if q.classes ~= 0 and cb and (q.classes % (cb * 2)) < cb then return false, "class" end
    return true
end

function Q:InLogSet()
    local set = {}
    local QT = FO:GetModule("Quest.QuestTracker")
    if QT and QT.LogQuestIDs then for _, e in ipairs(QT:LogQuestIDs()) do set[e.id] = true end end
    return set
end

-- true when the player could pick this quest up right now
function Q:Available(q, level, inLog)
    inLog = inLog or self:InLogSet()
    if Completed(q.id) and q.special % 2 == 0 then return false, "completed" end
    if inLog[q.id] then return false, "in log" end
    local ok, why = self:Eligible(q, level)
    if not ok then return false, why end
    if q.preSingle and #q.preSingle > 0 then
        local any = false
        for _, pid in ipairs(q.preSingle) do if Completed(math.abs(pid)) then any = true break end end
        if not any then return false, "prerequisite" end
    end
    if q.preGroup and #q.preGroup > 0 then
        for _, pid in ipairs(q.preGroup) do if not Completed(math.abs(pid)) then return false, "prerequisite" end end
    end
    if q.exclusiveTo then
        for _, xid in ipairs(q.exclusiveTo) do if Completed(xid) or inLog[xid] then return false, "exclusive" end end
    end
    if q.nextInChain ~= 0 and Completed(q.nextInChain) then return false, "chain done" end
    if q.parent ~= 0 and not inLog[q.parent] then return false, "parent" end
    return true
end

local function Dist(mapID, x1, y1, x2, y2)
    return U.YardsBetween(mapID, x1, y1, x2, y2) or math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) * 3000
end

-- Every quest you could pick up on this map, with the nearest giver position.
function Q:AvailableOnMap(mapID, px, py)
    if not self.available or not mapID then return {} end
    local level = FO.Player.level or 1
    local s = self.db.settings
    local c = scanCache[mapID]
    if c and c.level == level and GetTime() - c.at < SCAN_TTL and c.low == s.showLowLevel then
        if px then for _, r in ipairs(c.rows) do r.dist = Dist(mapID, px, py, r.x, r.y) end table.sort(c.rows, function(a, b) return (a.dist or 0) < (b.dist or 0) end) end
        return c.rows
    end
    local rows = {}
    local inLog = self:InLogSet()
    local QT = FO:GetModule("Quest.QuestTracker")
    local ids = Call(QA.GetAllIds) or {}
    for _, qid in ipairs(ids) do
        local req = U.Num(Call(QA.requiredLevel, qid)) or 0
        local ql = U.Num(Call(QA.questLevel, qid)) or 0
        if req <= level and ql <= level + s.levelAbove and (s.showLowLevel or ql >= level - s.levelBelow or ql == 0) then
            local q = self:Quest(qid)
            if q and self:Available(q, level, inLog) then
                local best
                local function consider(x, y, giver, kind)
                    local d = px and Dist(mapID, px, py, x, y) or 0
                    if not best or d < best.dist then best = { x = x, y = y, giver = giver, kind = kind, dist = d } end
                end
                -- your own record of where you accepted it beats the seed
                local rec = QT and QT.db.quests[qid]
                if rec and rec.accept and rec.accept.mapID == mapID and rec.accept.x then consider(rec.accept.x, rec.accept.y, rec.accept.npcName or "recorded", "recorded") end
                for _, npcID in ipairs(q.startedBy[1] or {}) do
                    for _, sp in ipairs(self:NpcSpawns(npcID)) do if sp[1] == mapID then consider(sp[2], sp[3], self:NpcName(npcID) or ("npc " .. npcID), "npc") end end
                end
                for _, objID in ipairs(q.startedBy[2] or {}) do
                    for _, sp in ipairs(self:ObjectSpawns(objID)) do if sp[1] == mapID then consider(sp[2], sp[3], self:ObjectName(objID) or ("object " .. objID), "object") end end
                end
                if best then rows[#rows + 1] = { q = q, id = qid, name = q.name, level = q.level, x = best.x, y = best.y, giver = best.giver, kind = best.kind, dist = best.dist } end
            end
        end
    end
    table.sort(rows, function(a, b) return (a.dist or 0) < (b.dist or 0) end)
    scanCache[mapID] = { at = GetTime(), level = level, low = s.showLowLevel, rows = rows }
    return rows
end

function Q:InvalidateScan() scanCache = {} end

-- ---------------------------------------------------------------------------
-- Objective and turn-in targets for a quest
-- ---------------------------------------------------------------------------
-- rows: { mapID=, x=, y=, label=, kind="creature"|"object"|"item"|"event" }
function Q:ObjectiveTargets(qid, onlyMap)
    local q = self:Quest(qid)
    if not q then return {} end
    local out, cap = {}, self.db.settings.maxPinsPerQuest or 40
    local function add(sp, label, kind)
        if #out >= cap then return end
        if not onlyMap or sp[1] == onlyMap then out[#out + 1] = { mapID = sp[1], x = sp[2], y = sp[3], label = label, kind = kind } end
    end
    local obj = q.objectives
    for _, row in ipairs(obj[1] or {}) do      -- creatures: {npcId, text?}
        local npcID = U.Num(row[1])
        if npcID then local name = U.Str(row[2]) or self:NpcName(npcID) or ("npc " .. npcID) for _, sp in ipairs(self:NpcSpawns(npcID)) do add(sp, name, "creature") end end
    end
    for _, row in ipairs(obj[2] or {}) do      -- objects
        local objID = U.Num(row[1])
        if objID then local name = U.Str(row[2]) or self:ObjectName(objID) or ("object " .. objID) for _, sp in ipairs(self:ObjectSpawns(objID)) do add(sp, name, "object") end end
    end
    for _, row in ipairs(obj[3] or {}) do      -- items: find who drops them
        local itemID = U.Num(row[1])
        if itemID then
            local label = U.Str(row[2]) or U.ItemName(itemID)
            local npcs, objects = self:ItemSources(itemID)
            for i = 1, math.min(6, #npcs) do for _, sp in ipairs(self:NpcSpawns(npcs[i])) do add(sp, label .. " (" .. (self:NpcName(npcs[i]) or "?") .. ")", "item") end end
            for i = 1, math.min(4, #objects) do for _, sp in ipairs(self:ObjectSpawns(objects[i])) do add(sp, label, "item") end end
        end
    end
    if type(q.triggerEnd) == "table" and type(q.triggerEnd[2]) == "table" then
        for _, sp in ipairs(ConvertSpawns(q.triggerEnd[2])) do add(sp, U.Str(q.triggerEnd[1]) or "event", "event") end
    end
    return out
end

function Q:Finishers(qid, onlyMap)
    local q = self:Quest(qid)
    if not q then return {} end
    local out = {}
    for _, npcID in ipairs(q.finishedBy[1] or {}) do
        for _, sp in ipairs(self:NpcSpawns(npcID)) do if not onlyMap or sp[1] == onlyMap then out[#out + 1] = { mapID = sp[1], x = sp[2], y = sp[3], label = self:NpcName(npcID) or ("npc " .. npcID), kind = "turnin" } end end
    end
    for _, objID in ipairs(q.finishedBy[2] or {}) do
        for _, sp in ipairs(self:ObjectSpawns(objID)) do if not onlyMap or sp[1] == onlyMap then out[#out + 1] = { mapID = sp[1], x = sp[2], y = sp[3], label = self:ObjectName(objID) or ("object " .. objID), kind = "turnin" } end end
    end
    return out
end

function Q:Starters(qid, onlyMap)
    local q = self:Quest(qid)
    if not q then return {} end
    local out = {}
    for _, npcID in ipairs(q.startedBy[1] or {}) do
        for _, sp in ipairs(self:NpcSpawns(npcID)) do if not onlyMap or sp[1] == onlyMap then out[#out + 1] = { mapID = sp[1], x = sp[2], y = sp[3], label = self:NpcName(npcID) or ("npc " .. npcID), kind = "giver" } end end
    end
    for _, objID in ipairs(q.startedBy[2] or {}) do
        for _, sp in ipairs(self:ObjectSpawns(objID)) do if not onlyMap or sp[1] == onlyMap then out[#out + 1] = { mapID = sp[1], x = sp[2], y = sp[3], label = self:ObjectName(objID) or ("object " .. objID), kind = "giver" } end end
    end
    return out
end

local function Nearest(rows, mapID, px, py)
    local best, bd
    for _, r in ipairs(rows) do
        if r.mapID == mapID then
            local d = (px and py) and Dist(mapID, px, py, r.x, r.y) or 0
            if not bd or d < bd then best, bd = r, d end
        end
    end
    return best, bd
end

function Q:NearestObjective(qid, mapID, px, py) return Nearest(self:ObjectiveTargets(qid, mapID), mapID, px, py) end
function Q:NearestFinisher(qid, mapID, px, py) return Nearest(self:Finishers(qid, mapID), mapID, px, py) end
function Q:NearestStarter(qid, mapID, px, py) return Nearest(self:Starters(qid, mapID), mapID, px, py) end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------
Q.messages = {
    FO_QUEST_ACCEPTED = function(self) self:InvalidateScan() end,
    FO_QUEST_TURNED_IN = function(self) self:InvalidateScan() end,
}

Q.commands = {
    nearby = {
        help = "Quests you can pick up on this map, nearest first (needs QuestieDB) | nearby all",
        fn = function(self, arg)
            if not self.available then print("quest database unavailable: %s", tostring(self.reason)) return end
            local showAll = (U.Str(arg) or "") == "all"
            local mapID, px, py = U.PlayerPosition()
            if not mapID then print("no map position.") return end
            local rows = self:AvailableOnMap(mapID, px, py)
            if #rows == 0 then print("nothing to pick up on %s at level %d (window -%d/+%d).", U.MapName(mapID), FO.Player.level or 0, self.db.settings.levelBelow, self.db.settings.levelAbove) return end
            print("%d quests available on %s:", #rows, U.MapName(mapID))
            for i = 1, math.min(showAll and #rows or 12, #rows) do
                local r = rows[i]
                local color = r.level > (FO.Player.level or 1) and "ff8040" or r.level < (FO.Player.level or 1) - 3 and "888888" or "ffd100"
                print("  %5.0fy  |cff%sL%-2d|r %-32s from %s (%.1f, %.1f)%s", r.dist or 0, color, r.level, U.Trunc(r.name, 32), U.Trunc(r.giver, 18), r.x * 100, r.y * 100, r.kind == "recorded" and " |cff80ff80seen|r" or "")
            end
        end,
    },
    questinfo = {
        help = "<id|name> — quest facts from the database: givers, objectives, prerequisites, chain",
        fn = function(self, arg)
            if not self.available then print("quest database unavailable: %s", tostring(self.reason)) return end
            local qid = tonumber(arg)
            if not qid then
                local ids = Call(QA.IdsByName, U.Str(arg) or "")
                qid = ids and ids[1]
            end
            local q = qid and self:Quest(qid)
            if not q then print("no quest '%s' in the database", tostring(arg)) return end
            local ok, why = self:Available(q)
            print("%s (%d) L%d req %d%s  [%s]", q.name, q.id, q.level, q.reqLevel, Completed(q.id) and "  |cff80ff80done|r" or "", ok and "available" or ("not available: " .. tostring(why)))
            for _, npcID in ipairs(q.startedBy[1] or {}) do local sp = self:NpcSpawns(npcID)[1] print("  starts: %s%s", self:NpcName(npcID) or npcID, sp and string.format(" at %s (%.1f, %.1f)", U.MapName(sp[1]), sp[2] * 100, sp[3] * 100) or " (no coordinates)") end
            for _, objID in ipairs(q.startedBy[2] or {}) do print("  starts: object %s", self:ObjectName(objID) or objID) end
            for _, itemID in ipairs(q.startedBy[3] or {}) do print("  starts: item %s", U.ItemName(itemID)) end
            for _, npcID in ipairs(q.finishedBy[1] or {}) do local sp = self:NpcSpawns(npcID)[1] print("  ends: %s%s", self:NpcName(npcID) or npcID, sp and string.format(" at %s (%.1f, %.1f)", U.MapName(sp[1]), sp[2] * 100, sp[3] * 100) or " (no coordinates)") end
            for _, line in ipairs(q.objectivesText or {}) do print("  objective: %s", line) end
            local targets = self:ObjectiveTargets(q.id)
            if #targets > 0 then print("  %d objective locations known", #targets) end
            if q.preSingle and #q.preSingle > 0 then print("  needs one of: %s", table.concat(q.preSingle, ", ")) end
            if q.preGroup and #q.preGroup > 0 then print("  needs all of: %s", table.concat(q.preGroup, ", ")) end
            if q.nextInChain ~= 0 then print("  next in chain: %d", q.nextInChain) end
        end,
    },
    qdb = {
        help = "Quest database status",
        fn = function(self)
            if not self.available then print("quest database: unavailable (%s). Install QuestieDB from CurseForge to seed quests.", tostring(self.reason)) return end
            local n = #(Call(QA.GetAllIds) or {})
            local zones = 0 for _ in pairs(areaToMap) do zones = zones + 1 end
            print("quest database: QuestieDB %s mode, %d quests, %d zone mappings, contract %s", self.mode or "?", n, zones, tostring(LQ.contractVersion or "?"))
        end,
    },
}
