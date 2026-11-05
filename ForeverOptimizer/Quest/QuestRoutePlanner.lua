local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Quest")

-- ===========================================================================
-- Quest router. Turns the quest log into an ordered loop of stops on the
-- current map and drives the direction arrow through it.
--
--   objective stops  every unfinished objective's spawn points (QuestieDB) and
--                    the spots where it ticked for you, grouped into patches;
--                    patches shared by several quests become one stop
--   turn-in stops    the finisher NPC, placed only after every objective stop
--                    of that quest; quests sharing a finisher share the stop
--   pickup stops     (route all) quests you can accept on this map; a pickup's
--                    objectives join existing patches, delivery quests get
--                    their turn-in queued right behind the pickup
--
-- Ordering is nearest-neighbour under those precedence rules, then 2-opt.
-- /fo route follow keeps the plan live: every quest log change replans and
-- the arrow moves to the next stop. /fo next is the single-quest waypoint.
-- Group, dungeon and raid quests stay out of the loop unless asked for.
-- ===========================================================================
local RP = FO:NewModule("Quest.QuestRoutePlanner", {
    account = "router",
    defaults = { settings = { patchYards = 80, mergeYards = 25, group = false, pickups = false, parkSeconds = 180 } },
})
FO.Router = RP
RP.plan = nil          -- { stops = {...}, total =, mapID =, skipped = {...}, offMap = {...}, at = }
RP.following = false
RP.parked = {}         -- stop key -> GetTime() when the arrow arrived or the stop was skipped
RP.current = nil       -- stop the arrow points at

-- ---------------------------------------------------------------------------
-- Single-quest waypoint (/fo next): Blizzard waypoint, your recording, database
-- ---------------------------------------------------------------------------
function RP:NextWaypoint(questID)
    local QT = FO:GetModule("Quest.QuestTracker")
    if C_QuestLog.GetNextWaypoint then
        local mapID, x, y = C_QuestLog.GetNextWaypoint(questID)
        mapID, x, y = U.Num(mapID), U.Num(x), U.Num(y)
        if mapID and x and y then return mapID, x, y, "blizzard" end
    end
    local q = QT.db.quests[questID] or { objectives = {} }
    local QDB = FO.QuestDB
    local pmap, px, py = U.PlayerPosition()
    local objs = QT.ReadObjectives(questID) or {}
    local complete = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)) == true
    if not complete then
        local allDone = #objs > 0
        for idx, o in ipairs(objs) do
            if not o.finished then
                allDone = false
                local saved = q.objectives[idx]
                if saved and #saved.points > 0 then
                    local pt = saved.points[#saved.points]
                    return pt[1], pt[2], pt[3], "recorded"
                end
            end
        end
        complete = allDone
    end
    if complete then
        if q.turnin and q.turnin.mapID and q.turnin.x then return q.turnin.mapID, q.turnin.x, q.turnin.y, "turn-in" end
        if QDB and QDB.available and pmap then
            local f = QDB:NearestFinisher(questID, pmap, px, py)
            if f then return f.mapID, f.x, f.y, "turn-in (database)" end
        end
        if q.accept and q.accept.mapID and q.accept.x then return q.accept.mapID, q.accept.x, q.accept.y, "accept npc (turn-in unknown)" end
    elseif QDB and QDB.available and pmap then
        local t = QDB:NearestObjective(questID, pmap, px, py)
        if t then return t.mapID, t.x, t.y, "database: " .. (t.label or t.kind) end
    end
    return nil
end

local function SetWaypoint(mapID, x, y, label, onArrive, arrive)
    local ok = false
    if C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID) and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, x, y))
        if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
    end
    if FO.Arrow and FO.Arrow:Set(mapID, x, y, label, onArrive, arrive) then ok = true end
    return ok
end

local function Yards(mapID, x1, y1, x2, y2)
    return U.YardsBetween(mapID, x1, y1, x2, y2) or math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) * 3000
end

-- ---------------------------------------------------------------------------
-- Quest classification
-- ---------------------------------------------------------------------------
local GROUP_TAGS = { [1] = "group", [41] = "pvp", [62] = "raid", [81] = "dungeon", [83] = "legendary", [85] = "heroic", [88] = "raid", [89] = "raid" }

-- "group" / "dungeon" / "raid" / nil for a quest the loop should not drag you to
function RP:GroupKind(qid, dbq)
    if C_QuestLog.GetQuestTagInfo then
        local ok, tag = pcall(C_QuestLog.GetQuestTagInfo, qid)
        if ok then
            local id = type(tag) == "table" and U.Num(tag.tagID) or U.Num(tag)
            if id and GROUP_TAGS[id] then return GROUP_TAGS[id] end
        end
    end
    if dbq then
        local flags = dbq.flags or 0
        if flags % 128 >= 64 then return "raid" end          -- RAID bit
        if flags % 4 >= 2 then return "group" end            -- PARTY_ACCEPT bit
    end
    return nil
end

-- Client objective index -> database target rows, matched by type and order.
-- Falls back to every target of the quest when the shapes do not line up.
local function ObjectiveRows(QDB, qid, objs, mapID)
    local q = QDB:Quest(qid)
    if not q then return {} end
    local byType = { monster = {}, object = {}, item = {}, event = {} }
    local obj = q.objectives or {}
    for _, row in ipairs(obj[1] or {}) do
        local npcID = U.Num(row[1])
        if npcID then
            local name = U.Str(row[2]) or QDB:NpcName(npcID) or ("npc " .. npcID)
            local pts = {}
            for _, sp in ipairs(QDB:NpcSpawns(npcID)) do if sp[1] == mapID then pts[#pts + 1] = { x = sp[2], y = sp[3], label = name } end end
            byType.monster[#byType.monster + 1] = pts
        end
    end
    for _, row in ipairs(obj[2] or {}) do
        local objID = U.Num(row[1])
        if objID then
            local name = U.Str(row[2]) or QDB:ObjectName(objID) or ("object " .. objID)
            local pts = {}
            for _, sp in ipairs(QDB:ObjectSpawns(objID)) do if sp[1] == mapID then pts[#pts + 1] = { x = sp[2], y = sp[3], label = name } end end
            byType.object[#byType.object + 1] = pts
        end
    end
    for _, row in ipairs(obj[3] or {}) do
        local itemID = U.Num(row[1])
        if itemID then
            local label = U.Str(row[2]) or U.ItemName(itemID)
            local pts = {}
            local npcs, objects = QDB:ItemSources(itemID)
            for i = 1, math.min(6, #npcs) do
                local who = QDB:NpcName(npcs[i]) or "?"
                for _, sp in ipairs(QDB:NpcSpawns(npcs[i])) do if sp[1] == mapID then pts[#pts + 1] = { x = sp[2], y = sp[3], label = label .. " (" .. who .. ")" } end end
            end
            for i = 1, math.min(4, #objects) do
                for _, sp in ipairs(QDB:ObjectSpawns(objects[i])) do if sp[1] == mapID then pts[#pts + 1] = { x = sp[2], y = sp[3], label = label } end end
            end
            byType.item[#byType.item + 1] = pts
        end
    end
    if type(q.triggerEnd) == "table" and type(q.triggerEnd[2]) == "table" then
        local pts = {}
        for _, t in ipairs(QDB:ObjectiveTargets(qid, mapID)) do if t.kind == "event" then pts[#pts + 1] = { x = t.x, y = t.y, label = t.label } end end
        byType.event[1] = pts
    end
    local out, cursor, mismatch = {}, { monster = 0, object = 0, item = 0, event = 0 }, false
    for idx, o in ipairs(objs) do
        local list = byType[o.type or ""]
        if list then
            cursor[o.type] = cursor[o.type] + 1
            local pts = list[cursor[o.type]]
            if pts then out[idx] = pts else mismatch = true end
        else
            mismatch = true
        end
    end
    if mismatch then
        local all = {}
        for _, t in ipairs(QDB:ObjectiveTargets(qid, mapID)) do all[#all + 1] = { x = t.x, y = t.y, label = t.label } end
        for idx in ipairs(objs) do out[idx] = out[idx] or all end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Stops
-- ---------------------------------------------------------------------------
-- stop = { kind = "objective"|"turnin"|"pickup", key, mapID, x, y, label, quests = { [qid] = title },
--          needs = { [qid] = true } (objective: which quests' objectives it serves),
--          after = { stop, ... } (stops that must come first), weight, n (spawn points), leg }

local function NewPatch(mapID, x, y)
    return { kind = "objective", mapID = mapID, sx = 0, sy = 0, n = 0, quests = {}, objs = {}, labels = {}, recorded = 0, after = {} }
end

local function PatchAdd(p, x, y, qid, title, idx, label, remaining, recorded)
    p.sx, p.sy, p.n = p.sx + x, p.sy + y, p.n + 1
    p.x, p.y = p.sx / p.n, p.sy / p.n
    p.quests[qid] = title
    local k = qid .. "/" .. idx
    local o = p.objs[k]
    if not o then o = { qid = qid, idx = idx, label = label, remaining = remaining, n = 0, recorded = 0 } p.objs[k] = o end
    o.n = o.n + 1
    if recorded then o.recorded = o.recorded + 1 p.recorded = p.recorded + 1 end
end

local function PatchWeight(p, totals)
    -- one point per objective served, scaled by this patch's share of that objective's points;
    -- spots where it actually ticked for you count double
    local w = 0
    for k, o in pairs(p.objs) do
        local share = totals[k] and totals[k] > 0 and (o.n / totals[k]) or 1
        w = w + 0.5 + share + o.recorded * 1.0
    end
    return w
end

-- short: what the stop is ("Boar x6", "Bloodscalp Ears to Nimboya"); label: with the verb, for the arrow
local function Label(stop)
    if stop.kind == "objective" then
        local parts, seen = {}, {}
        for _, o in pairs(stop.objs) do
            local l = o.label or "?"
            if o.remaining and o.remaining > 0 then l = l .. " x" .. o.remaining end
            if not seen[l] then seen[l] = true parts[#parts + 1] = l end
        end
        table.sort(parts)
        local nq = U.Count(stop.quests)
        local short = table.concat(parts, ", ") .. (nq > 1 and string.format(" (%d quests)", nq) or "")
        return short, short
    elseif stop.kind == "turnin" then
        local titles = {}
        for _, t in pairs(stop.quests) do titles[#titles + 1] = t end
        table.sort(titles)
        local short = table.concat(titles, ", ") .. (stop.npc and (" to " .. stop.npc) or "")
        return short, "Turn in " .. short
    else
        local short = (stop.title or "?") .. (stop.npc and (" from " .. stop.npc) or "")
        return short, "Pick up " .. short
    end
end

-- Merge a turn-in / pickup at an NPC already in the list (same giver within mergeYards)
local function FindNPCStop(list, kind, mapID, x, y, yards)
    for _, s in ipairs(list) do
        if s.kind == kind and Yards(mapID, s.x, s.y, x, y) <= yards then return s end
    end
end

-- ---------------------------------------------------------------------------
-- Planning
-- ---------------------------------------------------------------------------
function RP:Plan(opts)
    opts = opts or {}
    local only = opts.only          -- { [qid] = true }: plan these quests only, say nothing, keep self.plan
    local s = self.db.settings
    local QT, QDB = FO:GetModule("Quest.QuestTracker"), FO.QuestDB
    local mapID, px, py = U.PlayerPosition()
    if not mapID or not px then return nil, "no position" end
    local hasDB = QDB and QDB.available
    local includeGroup = opts.group or s.group
    local includePickups = opts.pickups or s.pickups
    local patchYards, mergeYards = s.patchYards or 80, s.mergeYards or 25
    local now = GetTime()

    local patches, totals, turnins, pickups, skipped, offMap = {}, {}, {}, {}, {}, {}

    local function AddPoint(x, y, qid, title, idx, label, remaining, recorded)
        local best, bd
        for _, p in ipairs(patches) do
            local d = Yards(mapID, p.x, p.y, x, y)
            if d <= patchYards and (not bd or d < bd) then best, bd = p, d end
        end
        if not best then best = NewPatch(mapID, x, y) patches[#patches + 1] = best end
        PatchAdd(best, x, y, qid, title, idx, label, remaining, recorded)
        local k = qid .. "/" .. idx
        totals[k] = (totals[k] or 0) + 1
    end

    local function AddTurnin(qid, title, after, fromPickup)
        local rec = QT.db.quests[qid]
        local candidates = {}
        if rec and rec.turnin and rec.turnin.mapID == mapID and rec.turnin.x then candidates[1] = { x = rec.turnin.x, y = rec.turnin.y, label = rec.turnin.npcName } end
        if #candidates == 0 and hasDB then
            for _, f in ipairs(QDB:Finishers(qid, mapID)) do candidates[#candidates + 1] = { x = f.x, y = f.y, label = f.label } end
        end
        if #candidates == 0 then
            local where
            if hasDB then local f = QDB:Finishers(qid)[1] if f then where = U.MapName(f.mapID) end end
            if not fromPickup then offMap[#offMap + 1] = { qid = qid, title = title, where = where } end
            return nil
        end
        -- nearest finisher to the objective stops it follows, else to the player
        local ax, ay, n = 0, 0, 0
        for _, st in ipairs(after) do ax, ay, n = ax + st.x, ay + st.y, n + 1 end
        if n == 0 then ax, ay, n = px, py, 1 end
        ax, ay = ax / n, ay / n
        local best, bd
        for _, c in ipairs(candidates) do local d = Yards(mapID, ax, ay, c.x, c.y) if not bd or d < bd then best, bd = c, d end end
        local stop = FindNPCStop(turnins, "turnin", mapID, best.x, best.y, mergeYards)
        if not stop then
            stop = { kind = "turnin", mapID = mapID, x = best.x, y = best.y, npc = best.label, quests = {}, after = {} }
            turnins[#turnins + 1] = stop
        end
        stop.quests[qid] = title
        for _, st in ipairs(after) do stop.after[#stop.after + 1] = st end
        return stop
    end

    -- quests in the log
    local logIDs, inLog = QT:LogQuestIDs(), {}
    local questObjStops = {}        -- qid -> { stop, ... } objective stops serving it (filled after patch selection)
    local questInfo = {}
    for _, e in ipairs(logIDs) do
        local qid, title = e.id, e.title or ("quest " .. e.id)
        inLog[qid] = true
        local dbq = hasDB and QDB:Quest(qid) or nil
        local gk = self:GroupKind(qid, dbq)
        if only and not only[qid] then
            -- not part of this plan
        elseif gk and not includeGroup and not only then
            skipped[#skipped + 1] = { qid = qid, title = title, why = gk }
        else
            local objs = QT.ReadObjectives(qid) or {}
            local complete = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(qid)) == true
            local anyOpen = false
            for _, o in ipairs(objs) do if not o.finished then anyOpen = true end end
            if not complete and #objs > 0 and not anyOpen then complete = true end
            if #objs == 0 and not complete then complete = true end     -- delivery quest: nothing to do but turn in
            questInfo[qid] = { title = title, complete = complete, objs = objs }
            if not complete then
                local rec = QT.db.quests[qid]
                local rows = hasDB and ObjectiveRows(QDB, qid, objs, mapID) or {}
                for idx, o in ipairs(objs) do
                    if not o.finished then
                        local remaining = (o.req or 0) > 0 and ((o.req or 0) - (o.num or 0)) or nil
                        local label = o.text and o.text:gsub("^%d+/%d+%s*", ""):gsub("^(.-):%s*%d+/%d+$", "%1") or ("objective " .. idx)
                        local any = false
                        for _, pt in ipairs(rows[idx] or {}) do AddPoint(pt.x, pt.y, qid, title, idx, label, remaining, false) any = true end
                        local saved = rec and rec.objectives[idx]
                        for _, pt in ipairs(saved and saved.points or {}) do
                            if pt[1] == mapID then AddPoint(pt[2], pt[3], qid, title, idx, label, remaining, true) any = true end
                        end
                        if not any then questInfo[qid].unknown = (questInfo[qid].unknown or 0) + 1 end
                    end
                end
            end
        end
    end

    -- pickups: quests available on this map (route all)
    local pickupInfo = {}
    if includePickups and hasDB and not only then
        for _, r in ipairs(QDB:AvailableOnMap(mapID, px, py)) do
            local gk = self:GroupKind(r.id, r.q)
            if gk and not includeGroup then
                skipped[#skipped + 1] = { qid = r.id, title = r.name, why = gk .. " (pickup)" }
            else
                local stop = FindNPCStop(pickups, "pickup", mapID, r.x, r.y, mergeYards)
                if not stop then
                    stop = { kind = "pickup", mapID = mapID, x = r.x, y = r.y, npc = r.giver, quests = {}, titles = {}, after = {} }
                    pickups[#pickups + 1] = stop
                end
                stop.quests[r.id] = r.name
                stop.titles[#stop.titles + 1] = r.name
                pickupInfo[r.id] = { stop = stop, q = r.q, title = r.name }
            end
        end
        for _, p in ipairs(pickups) do table.sort(p.titles) p.title = table.concat(p.titles, ", ") end
    end

    -- choose patches: greedy set cover, richest patch first, every open objective served once
    local stops = {}
    local uncovered = {}
    for k in pairs(totals) do uncovered[k] = true end
    local pool = {}
    for _, p in ipairs(patches) do pool[#pool + 1] = p end
    while next(uncovered) do
        local best, bw
        for _, p in ipairs(pool) do
            local w = 0
            for k, o in pairs(p.objs) do
                if uncovered[k] then
                    local share = totals[k] > 0 and (o.n / totals[k]) or 1
                    w = w + 0.5 + share + o.recorded
                end
            end
            if w > 0 and (not bw or w > bw) then best, bw = p, w end
        end
        if not best then break end
        best.weight = bw
        for k in pairs(best.objs) do uncovered[k] = nil end
        stops[#stops + 1] = best
        for qid in pairs(best.quests) do
            questObjStops[qid] = questObjStops[qid] or {}
            table.insert(questObjStops[qid], best)
        end
    end
    -- a pickup's objectives ride along on patches that already exist, with the pickup first
    for pid, info in pairs(pickupInfo) do
        local q = info.q
        local nObj = 0
        for _, list in ipairs({ q.objectives[1] or {}, q.objectives[2] or {}, q.objectives[3] or {} }) do nObj = nObj + #list end
        if nObj == 0 then
            local t = AddTurnin(pid, info.title, { info.stop }, true)
            if t then t.after[#t.after + 1] = info.stop end
        else
            local rows = ObjectiveRows(QDB, pid, {}, mapID)
            local all = {}
            for _, t in ipairs(QDB:ObjectiveTargets(pid, mapID)) do all[#all + 1] = t end
            for _, pt in ipairs(all) do
                for _, p in ipairs(stops) do
                    if p.kind == "objective" and Yards(mapID, p.x, p.y, pt.x, pt.y) <= patchYards then
                        if not p.quests[pid] then
                            p.quests[pid] = info.title
                            p.objs["p" .. pid] = { qid = pid, idx = 0, label = pt.label, n = 1, recorded = 0 }
                            p.after[#p.after + 1] = info.stop
                        end
                        break
                    end
                end
            end
        end
    end
    -- turn-ins for every log quest: complete ones now, the rest after their patches
    for qid, info in pairs(questInfo) do
        AddTurnin(qid, info.title, questObjStops[qid] or {}, false)
    end
    for _, t in ipairs(turnins) do stops[#stops + 1] = t end
    for _, p in ipairs(pickups) do stops[#stops + 1] = p end

    for i, st in ipairs(stops) do
        st.short, st.label = Label(st)
        st.key = string.format("%s:%.3f:%.3f", st.kind, st.x, st.y)
        st.after = st.after or {}
    end
    if #stops == 0 then
        return nil, (#skipped > 0 or #offMap > 0) and "nothing to do on this map" or "no quest targets known on this map", { skipped = skipped, offMap = offMap }
    end

    -- order: nearest neighbour under precedence, then 2-opt that keeps precedence
    local placed, order = {}, {}
    local function Ready(st) for _, a in ipairs(st.after) do if not placed[a] then return false end end return true end
    local cx, cy = px, py
    local remaining = {}
    for _, st in ipairs(stops) do remaining[#remaining + 1] = st end
    while #remaining > 0 do
        local bi, bd
        for i, st in ipairs(remaining) do
            if Ready(st) then
                local d = Yards(mapID, cx, cy, st.x, st.y)
                if not bd or d < bd then bi, bd = i, d end
            end
        end
        if not bi then bi = 1 end    -- cycle in precedence (should not happen): take anything
        local st = table.remove(remaining, bi)
        placed[st] = true
        order[#order + 1] = st
        cx, cy = st.x, st.y
    end
    local function Valid(seq)
        local seen = {}
        for _, st in ipairs(seq) do
            for _, a in ipairs(st.after) do if not seen[a] then return false end end
            seen[st] = true
        end
        return true
    end
    local function Length(seq)
        local total, lx, ly = 0, px, py
        for _, st in ipairs(seq) do total = total + Yards(mapID, lx, ly, st.x, st.y) lx, ly = st.x, st.y end
        return total
    end
    local n = #order
    if n >= 3 then
        local improved, passes = true, 0
        local bestLen = Length(order)
        while improved and passes < 20 do
            improved, passes = false, passes + 1
            for i = 1, n - 1 do
                for j = i + 1, n do
                    local cand = {}
                    for k = 1, i - 1 do cand[#cand + 1] = order[k] end
                    for k = j, i, -1 do cand[#cand + 1] = order[k] end
                    for k = j + 1, n do cand[#cand + 1] = order[k] end
                    if Valid(cand) then
                        local len = Length(cand)
                        if len < bestLen - 1 then order, bestLen, improved = cand, len, true end
                    end
                end
            end
        end
    end
    local total, lx, ly = 0, px, py
    for i, st in ipairs(order) do
        st.leg = Yards(mapID, lx, ly, st.x, st.y)
        total = total + st.leg
        st.cum = total
        st.num = i
        lx, ly = st.x, st.y
    end
    local plan = { stops = order, total = total, mapID = mapID, skipped = skipped, offMap = offMap, at = now, pickups = includePickups }
    if only then return plan end
    self.plan = plan
    FO:Fire("FO_ROUTE_PLANNED", self.plan)
    return self.plan
end

-- ---------------------------------------------------------------------------
-- Following
-- ---------------------------------------------------------------------------
local function Park(self, key) self.parked[key] = GetTime() end

local function Parked(self, st)
    local t = self.parked[st.key]
    if not t then return false end
    if GetTime() - t > (self.db.settings.parkSeconds or 180) then self.parked[st.key] = nil return false end
    return true
end

-- the first stop the arrow should point at
function RP:NextStop()
    if not self.plan then return nil end
    for _, st in ipairs(self.plan.stops) do
        if not Parked(self, st) then return st end
    end
    return nil
end

function RP:Point(force)
    local A = FO.Arrow
    local st = self:NextStop()
    if not st then
        if self.current then self.current = nil if A then A:Clear() end end
        return nil
    end
    if self.current and self.current.key == st.key and not force then
        if self.current.label ~= st.label and A and A.target then A.target.label = st.label end
        return st
    end
    self.current = st
    local word = st.kind == "objective" and (st.num .. ". ") or (st.num .. ". ")
    SetWaypoint(st.mapID, st.x, st.y, word .. st.label, function()
        FO.TryCall("route arrive", function() self:Arrived(st) end)
    end)
    return st
end

function RP:Arrived(st)
    if st.kind == "objective" then
        -- stay on the patch: the arrow keeps showing the way back to its centre while you
        -- work it, and the next replan moves on once the objectives there are done
        print("at stop %d: %s. Working it; the arrow moves on when the objectives tick off.", st.num, st.label)
        self.current = nil
        if FO.Arrow then FO.Arrow:Set(st.mapID, st.x, st.y, "here: " .. st.label, nil, 0) end
        self.current = st
    else
        print("at stop %d: %s", st.num, st.label)
        Park(self, st.key)
        self.current = nil
        self:Replan("arrive")
    end
end

function RP:Replan(reason)
    if not self.following then return end
    local plan, err = self:Plan()
    if not plan then
        if self.current or (FO.Arrow and FO.Arrow:Active()) then
            self.current = nil
            if FO.Arrow then FO.Arrow:Clear() end
        end
        if reason ~= "tick" then print("route: %s. Still following; the plan refreshes on the next quest log change.", err) end
        return
    end
    local before = self.current and self.current.key
    local st = self:Point(false)
    if st and st.key ~= before and reason ~= "start" then print("route -> stop %d: %s (%.0f yd)", st.num, st.label, st.leg or 0) end
end

function RP:Follow(on, opts)
    if on then
        if opts and opts.pickups ~= nil then self.db.settings.pickups = opts.pickups end
        self.following = true
        self.parked = {}
        local plan, err = self:Plan()
        if not plan then print("route: %s. Following anyway; I will plan as soon as there is something on this map.", err) return end
        self:Print(plan)
        local st = self:Point(true)
        if st then print("following. The arrow advances on quest log changes; /fo route skip jumps a stop, /fo route stop ends it.") end
    else
        self.following = false
        self.current = nil
        if FO.Arrow then FO.Arrow:Clear() end
        if FO.Guide and FO.Guide.PointArrow then FO.Guide:PointArrow(true) end
        print("route following off.")
    end
end

function RP:Skip()
    local st = self.current or self:NextStop()
    if not st then print("route: nothing to skip.") return end
    Park(self, st.key)
    print("skipped stop %d: %s (comes back in %d s if still needed)", st.num, st.label, self.db.settings.parkSeconds or 180)
    self.current = nil
    if self.following then self:Replan("skip") else self:Point(true) end
end

-- ---------------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------------
local KIND_TAG = { objective = "|cff66b3ffdo|r", turnin = "|cff60ff60turn in|r", pickup = "|cffffd100pick up|r" }

function RP:Print(plan)
    print("Quest route on %s: %d stops, ~%.0f yards%s", U.MapName(plan.mapID), #plan.stops, plan.total, plan.pickups and " (with pickups)" or "")
    for i, st in ipairs(plan.stops) do
        local extra = st.kind == "objective" and st.n and string.format(" [%d pts%s]", st.n, st.recorded > 0 and ", seen" or "") or ""
        print("  %2d. %-8s %-44s (%.1f, %.1f) +%.0fy%s", i, KIND_TAG[st.kind] or st.kind, U.Trunc(st.short, 44), st.x * 100, st.y * 100, st.leg or 0, extra)
    end
    if #plan.offMap > 0 then
        local parts = {}
        for _, o in ipairs(plan.offMap) do parts[#parts + 1] = o.title .. (o.where and (" (" .. o.where .. ")") or "") end
        print("  turn in elsewhere: %s", table.concat(parts, ", "))
    end
    if #plan.skipped > 0 then
        local parts = {}
        for _, o in ipairs(plan.skipped) do parts[#parts + 1] = o.title .. " (" .. o.why .. ")" end
        print("  left out: %s. /fo route group includes them.", table.concat(parts, ", "))
    end
end

function RP:Lines()
    local out = {}
    local plan = self.plan
    if not plan then
        out[1] = "No route planned. /fo route plans a loop through your quests on this map; /fo route follow keeps it live."
        return out
    end
    out[#out + 1] = string.format("|cffaaaaaa%s|r  %d stops, ~%.0f yd%s", U.MapName(plan.mapID), #plan.stops, plan.total, self.following and "  |cff60ff60following|r" or "")
    local cur = self.current
    for i, st in ipairs(plan.stops) do
        if i > 8 then out[#out + 1] = string.format("  ... %d more", #plan.stops - 8) break end
        local mark = (cur and cur.key == st.key) and "|cffffd100>|r" or (Parked(self, st) and "|cff888888-|r" or " ")
        out[#out + 1] = string.format("%s%d. %s %s  |cffaaaaaa%.0fy|r", mark, i, KIND_TAG[st.kind] or st.kind, U.Trunc(st.short, 40), st.leg or 0)
    end
    if #plan.offMap > 0 then out[#out + 1] = string.format("|cffaaaaaa%d turn-in%s on other maps|r", #plan.offMap, #plan.offMap == 1 and "" or "s") end
    return out
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
function RP:OnInit()
    self.Schedule = U.Debounce(0.6, function() FO.TryCall("route replan", function() self:Replan("event") end) end)
end

function RP:OnEnable()
    if FO.Dashboard and FO.Dashboard.RegisterTab then
        FO.Dashboard:RegisterTab("Route", 1.8, function() return self:Lines() end, function()
            return { { label = function() return self.following and "Stop" or "Follow" end, fn = function() self:Follow(not self.following) end },
                     { label = "Skip", fn = function() self:Skip() end },
                     { label = "Replan", fn = function() if self.following then self:Replan("manual") else local p, e = self:Plan() if p then self:Print(p) else print("route: %s", e) end end end },
                     { label = function() return self.db.settings.pickups and "Pickups: on" or "Pickups: off" end, fn = function() self.db.settings.pickups = not self.db.settings.pickups if self.following then self:Replan("manual") end end } }
        end)
    end
end

local lastMap
function RP:OnTick()
    if not self.following then return end
    local mapID = U.PlayerPosition()
    if mapID and mapID ~= lastMap then
        lastMap = mapID
        if self.plan and self.plan.mapID ~= mapID then self:Schedule() end
    end
end

RP.events = {
    QUEST_LOG_UPDATE = function(self) if self.following then self:Schedule() end end,
    UNIT_QUEST_LOG_CHANGED = function(self, unit) if unit == "player" and self.following then self:Schedule() end end,
    QUEST_ACCEPTED = function(self) if self.following then self:Schedule() end end,
    QUEST_TURNED_IN = function(self) if self.following then self:Schedule() end end,
    QUEST_REMOVED = function(self) if self.following then self:Schedule() end end,
    PLAYER_ENTERING_WORLD = function(self) if self.following then self:Schedule() end end,
}

RP.commands = {
    next = { help = "[questID] — waypoint to the next known location of one quest", fn = function(self, arg)
        local qid = tonumber(arg)
        if not qid and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
            qid = U.Num(C_SuperTrack.GetSuperTrackedQuestID())
            if qid == 0 then qid = nil end
        end
        local QT = FO:GetModule("Quest.QuestTracker")
        if not qid then
            for _, e in ipairs(QT:LogQuestIDs()) do if self:NextWaypoint(e.id) then qid = e.id break end end
        end
        if not qid then print("no quest with a known location yet. I learn as objectives tick.") return end
        local mapID, x, y, src = self:NextWaypoint(qid)
        local title = C_QuestLog.GetTitleForQuestID and U.Str(C_QuestLog.GetTitleForQuestID(qid)) or ("quest " .. qid)
        if not mapID then print("%s: no location known yet.", title) return end
        print("%s -> %s (%.1f, %.1f) [%s]", title, U.MapName(mapID), x * 100, y * 100, src)
        if SetWaypoint(mapID, x, y, title) then print("waypoint set.") end
    end },
    route = { help = "(quest) plan a loop through your quests on this map | route all (adds pickups) | follow [all] | stop | skip | group | show | herb|ore [stops] (gathering nodes)", fn = function(self, arg)
        local sub, rest = U.SplitCmd(arg or "")
        if sub == "herb" or sub == "ore" then
            local FE = FO:GetModule("Grinding.FarmingEfficiency")
            if FE and FE.commands and FE.commands.route then FE.commands.route.fn(FE, arg) else print("gathering routes unavailable.") end
        elseif sub == "follow" then
            self:Follow(true, { pickups = rest == "all" and true or (rest == "" and nil) })
        elseif sub == "stop" or sub == "off" then
            self:Follow(false)
        elseif sub == "skip" then
            self:Skip()
        elseif sub == "group" then
            self.db.settings.group = not self.db.settings.group
            print("group, dungeon and raid quests %s the route.", self.db.settings.group and "join" or "stay out of")
            if self.following then self:Replan("manual") end
        elseif sub == "show" then
            if self.plan then self:Print(self.plan) else print("route: nothing planned yet.") end
        elseif sub == "" or sub == "all" then
            local plan, err, info = self:Plan({ pickups = sub == "all" })
            if not plan then
                print("route: %s", err)
                if info and #info.skipped > 0 then
                    local parts = {}
                    for _, o in ipairs(info.skipped) do parts[#parts + 1] = o.title .. " (" .. o.why .. ")" end
                    print("  left out: %s", table.concat(parts, ", "))
                end
                if info and #info.offMap > 0 then
                    local parts = {}
                    for _, o in ipairs(info.offMap) do parts[#parts + 1] = o.title .. (o.where and (" (" .. o.where .. ")") or "") end
                    print("  turn in elsewhere: %s", table.concat(parts, ", "))
                end
                return
            end
            self:Print(plan)
            if not self.following then
                self.parked = {}
                local st = self:Point(true)
                if st then print("arrow on stop 1. /fo route follow keeps the arrow moving through the loop.") end
            else
                self:Point(false)
            end
        else
            print("route: (plan) | all | follow [all] | stop | skip | group | show")
        end
    end },
}
