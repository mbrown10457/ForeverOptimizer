local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Grinding")

-- ===========================================================================
-- Spawn & respawn intelligence, resource nodes, rares, competition.
--
-- Respawn honesty: an interval is "confirmed" only if we stayed within range
-- of the kill spot the whole time and a never-before-seen unit of that type
-- entered nameplate range there at least 30s after the kill. Otherwise it's
-- an upper bound: "respawned sometime before we came back". Patrols walking
-- in can still fool this; the median over many samples is what to trust.
--
-- db.spawns[npcID] = { points = { { mapID, x, y, lastKill=<GetTime>, lastKillT=<time>,
--                                   confirmed = {sec,...}, bounds = {sec,...} } } }
-- db.nodes[name]   = { points = { { mapID, x, y, n=, last= } } }      -- herbs / ore
-- db.rares[npcID]  = { name=, sightings = { {mapID,x,y,t}, ... } }
-- db.competition[zone] = { samples = { {t=, players=} } }
-- ===========================================================================
local FE = FO:NewModule("Grinding.FarmingEfficiency", {
    account = "farming",
    defaults = { spawns = {}, nodes = {}, rares = {}, competition = {}, settings = {
        clusterYards = 20,   -- kills within this radius are the same spawn point
        presenceYards = 45,  -- stay within this of the point to confirm a respawn
        gatherSpells = { ["Herb Gathering"] = "herb", ["Herbalism"] = "herb", ["Mining"] = "ore" },
    } },
})

local presence = {}   -- npcID -> list of { point=, since=GetTime, broken=false }
local recentKills = {} -- guid -> true (so a nameplate for the same corpse isn't a "respawn")
local playersSeen = {} -- guid -> GetTime last seen (competition)
local seenGUIDs, seenOrder = {}, {} -- every creature GUID we've laid eyes on, with first-seen time
local MIN_RESPAWN = 30
local function NoteSeen(guid, now)
    if seenGUIDs[guid] then return false end
    seenGUIDs[guid] = now
    table.insert(seenOrder, guid)
    if #seenOrder > 3000 then seenGUIDs[table.remove(seenOrder, 1)] = nil end
    return true
end

local function Yards(mapID, x1, y1, x2, y2)
    local d = U.YardsBetween(mapID, x1, y1, x2, y2)
    if d then return d end
    -- unknown map size: fall back to normalized distance * a typical zone width
    return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) * 3000
end

local function FindPoint(points, mapID, x, y, radius)
    local best, bestD
    for _, p in ipairs(points) do
        if p[1] == mapID then
            local d = Yards(mapID, p[2], p[3], x, y)
            if d <= radius and (not bestD or d < bestD) then best, bestD = p, d end
        end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- Kill -> remember the spawn point and start a presence watch
-- ---------------------------------------------------------------------------
FE.messages = {
    FO_KILL = function(self, name, xp, npcID, guid, now)
        if not npcID then return end
        local mapID, x, y = U.PlayerPosition()
        if not mapID or not x then return end
        if guid then recentKills[guid] = true end
        local s = self.db.spawns[npcID]
        if not s then s = { name = name, points = {} } self.db.spawns[npcID] = s end
        s.name = s.name or name
        local p = FindPoint(s.points, mapID, x, y, self.db.settings.clusterYards)
        if not p then
            p = { mapID, x, y, confirmed = {}, bounds = {} }
            table.insert(s.points, p)
            while #s.points > 40 do table.remove(s.points, 1) end
        end
        p.lastKill, p.lastKillT = now, time()
        presence[npcID] = presence[npcID] or {}
        -- replace any existing watch for this point
        for i = #presence[npcID], 1, -1 do if presence[npcID][i].point == p then table.remove(presence[npcID], i) end end
        table.insert(presence[npcID], { point = p, since = now, broken = false })
    end,
    FO_ZONE = function(self) presence = {} end,
}

-- Every second: are we still near the points we're watching?
function FE:OnTick(now)
    local mapID, x, y = U.PlayerPosition()
    for npcID, list in pairs(presence) do
        for i = #list, 1, -1 do
            local w = list[i]
            if now - w.since > 3600 then table.remove(list, i)
            elseif not w.broken then
                if not mapID or mapID ~= w.point[1] or not x then w.broken = true
                elseif Yards(mapID, w.point[2], w.point[3], x, y) > self.db.settings.presenceYards then w.broken = true end
            end
        end
    end
    -- respawn windows: a point you killed at, whose estimate has elapsed, while you're still nearby
    if mapID and x and math.floor(now) % 5 == 0 then
        for npcID, s in pairs(self.db.spawns) do
            local est, kind = self:RespawnEstimate(npcID)
            if est then
                for _, p in ipairs(s.points) do
                    if p.lastKill and p.alertedFor ~= p.lastKill and now - p.lastKill >= est and p[1] == mapID
                       and Yards(mapID, p[2], p[3], x, y) <= 150 then
                        p.alertedFor = p.lastKill
                        FO:Alert("respawn", "%s should be back (%s %s, killed %s ago) at %.1f, %.1f", s.name or npcID, kind, U.FormatDuration(est), U.FormatDuration(now - p.lastKill), p[2] * 100, p[3] * 100)
                    end
                end
            end
        end
    end
    -- competition sample every 60s
    if math.floor(now) % 60 == 0 then
        local n = 0
        for guid, t in pairs(playersSeen) do
            if now - t <= 60 then n = n + 1 else playersSeen[guid] = nil end
        end
        local zone, sub = U.ZoneName()
        local key = zone .. (sub ~= "" and (" / " .. sub) or "")
        local c = self.db.competition[key]
        if not c then c = { samples = {} } self.db.competition[key] = c end
        if n > 0 or #c.samples > 0 then U.Push(c.samples, { t = time(), players = n }, 120) end
    end
end

-- A unit appeared: respawn candidate (nameplates only), rare sighting, or competition
local function OnUnitAppeared(unit, viaNameplate)
    if not UnitExists(unit) then return end
    local guid = U.Str(UnitGUID(unit))
    if not guid then return end
    if UnitIsPlayer(unit) then
        if not UnitIsUnit(unit, "player") and not UnitInParty(unit) and not UnitInRaid(unit) then playersSeen[guid] = GetTime() end
        return
    end
    local now = GetTime()
    local firstSight = NoteSeen(guid, now)
    if UnitIsDead(unit) or recentKills[guid] then return end
    local npcID = U.NpcIDFromGUID(guid)
    if not npcID then return end
    local mapID, x, y = U.PlayerPosition()

    -- rare?
    local cls = U.Str(UnitClassification(unit))
    if (cls == "rare" or cls == "rareelite") and mapID and x then
        local r = FE.db.rares[npcID]
        if not r then r = { name = U.Str(UnitName(unit)), sightings = {} } FE.db.rares[npcID] = r end
        local last = r.sightings[#r.sightings]
        if not last or (time() - last[4]) > 300 then
            U.Push(r.sightings, { mapID, x, y, time() }, 30)
            FO:Alert("rare", "|cffff80ffRare:|r %s seen at %s (%.1f, %.1f)", r.name or "?", U.MapName(mapID), x * 100, y * 100)
            FO:Fire("FO_RARE", npcID, r.name, mapID, x, y)
        end
    end

    -- respawn candidate? Only a unit we've never seen, entering nameplate range.
    local list = presence[npcID]
    if not viaNameplate or not firstSight or not list or not mapID or not x then return end
    for i = #list, 1, -1 do
        local w = list[i]
        local p = w.point
        if mapID == p[1] and Yards(mapID, p[2], p[3], x, y) <= FE.db.settings.presenceYards and w.since == (p.lastKill or 0) then
            local interval = now - w.since
            if interval >= MIN_RESPAWN then
                if w.broken then U.Push(p.bounds, math.floor(interval), 30)
                else U.Push(p.confirmed, math.floor(interval), 30) end
                table.remove(list, i)
                recentKills[guid] = nil
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Gathering nodes: the spell cast tells us the node name; success tells us it's real
-- ---------------------------------------------------------------------------
local pendingGather = {}
local function SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then return U.Str(C_Spell.GetSpellName(spellID)) end
    if GetSpellInfo then return U.Str((GetSpellInfo(spellID))) end
    return nil
end

local function RecordNode(name, kind)
    local mapID, x, y = U.PlayerPosition()
    if not mapID or not x then return end
    local node = FE.db.nodes[name]
    if not node then node = { kind = kind, points = {} } FE.db.nodes[name] = node end
    local p = FindPoint(node.points, mapID, x, y, 15)
    if p then p.n = (p.n or 1) + 1; p.last = time()
    else
        table.insert(node.points, { mapID, x, y, n = 1, last = time() })
        while #node.points > 200 do table.remove(node.points, 1) end
    end
    FO:Fire("FO_NODE", name, kind, mapID, x, y)
end

FE.events = {
    NAME_PLATE_UNIT_ADDED = function(self, unit) OnUnitAppeared(unit, true) end,
    UPDATE_MOUSEOVER_UNIT = function(self) OnUnitAppeared("mouseover") end,
    PLAYER_TARGET_CHANGED = function(self) OnUnitAppeared("target") end,
    UNIT_SPELLCAST_SENT = function(self, unit, target, castGUID, spellID)
        if unit ~= "player" then return end
        local kind = self.db.settings.gatherSpells[SpellName(U.Num(spellID)) or ""]
        if kind and U.Str(target) and target ~= "" then pendingGather[castGUID or 0] = { name = U.Str(target), kind = kind } end
    end,
    UNIT_SPELLCAST_SUCCEEDED = function(self, unit, castGUID)
        if unit ~= "player" then return end
        local g = pendingGather[castGUID or 0]
        if g then pendingGather[castGUID or 0] = nil RecordNode(g.name, g.kind) end
    end,
    UNIT_SPELLCAST_FAILED = function(self, unit, castGUID) if unit == "player" then pendingGather[castGUID or 0] = nil end end,
    UNIT_SPELLCAST_INTERRUPTED = function(self, unit, castGUID) if unit == "player" then pendingGather[castGUID or 0] = nil end end,
}

-- ---------------------------------------------------------------------------
-- Estimates & routes
-- ---------------------------------------------------------------------------
function FE:RespawnEstimate(npcID)
    local s = self.db.spawns[npcID]
    if not s then return nil end
    local confirmed, bounds = {}, {}
    for _, p in ipairs(s.points) do
        for _, v in ipairs(p.confirmed) do confirmed[#confirmed + 1] = v end
        for _, v in ipairs(p.bounds) do bounds[#bounds + 1] = v end
    end
    if #confirmed > 0 then return U.Median(confirmed), "confirmed", #confirmed, #s.points end
    if #bounds > 0 then
        table.sort(bounds)
        return bounds[1], "upper bound", #bounds, #s.points
    end
    return nil, "none", 0, #s.points
end

function FE:Competition(zoneKey)
    local c = self.db.competition[zoneKey]
    if not c or #c.samples == 0 then return nil end
    local recent, all = {}, {}
    local cutoff = time() - 600
    for _, smp in ipairs(c.samples) do
        all[#all + 1] = smp.players
        if smp.t >= cutoff then recent[#recent + 1] = smp.players end
    end
    return U.Mean(recent), U.Mean(all), #all
end

-- Greedy nearest-neighbour route through node points on the current map
function FE:Route(kind, maxStops)
    local mapID, x, y = U.PlayerPosition()
    if not mapID or not x then return nil, "no position" end
    local pts = {}
    for name, node in pairs(self.db.nodes) do
        if not kind or node.kind == kind then
            for _, p in ipairs(node.points) do
                if p[1] == mapID then pts[#pts + 1] = { name = name, x = p[2], y = p[3], n = p.n or 1 } end
            end
        end
    end
    -- seeded spawn points (Data/Nodes.lua) fill in where you have not gathered yet
    local M = FO:GetModule("Dashboard.Map")
    if M and M.SeedRows and self.db.settings.seedRoute ~= false then
        for _, r in ipairs(M:SeedRows(mapID, 3000)) do
            if not kind or r.kind == kind then pts[#pts + 1] = { name = r.name, x = r.x, y = r.y, n = 0, seed = true } end
        end
    end
    if #pts == 0 then return nil, "no nodes recorded or seeded on this map" end
    local route, cx, cy, total = {}, x, y, 0
    while #pts > 0 and #route < (maxStops or 15) do
        local bi, bd
        for i, p in ipairs(pts) do
            local d = Yards(mapID, cx, cy, p.x, p.y)
            if not bd or d < bd then bi, bd = i, d end
        end
        local p = table.remove(pts, bi)
        p.leg = bd
        total = total + bd
        route[#route + 1] = p
        cx, cy = p.x, p.y
    end
    return route, nil, total, mapID
end

local function SetWaypoint(mapID, x, y)
    if not C_Map.CanSetUserWaypointOnMap or not C_Map.CanSetUserWaypointOnMap(mapID) then return false end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    return true
end
FE.SetWaypoint = SetWaypoint

FE.commands = {
    respawn = { help = "[npcID|name] — respawn intervals (confirmed vs upper bound)", fn = function(self, arg)
        if arg ~= "" then
            local id = tonumber(arg)
            if not id then for k, s in pairs(self.db.spawns) do if s.name == arg then id = k end end end
            local est, kind, n, pts = self:RespawnEstimate(id)
            if not id or not pts then print("no spawn data for '%s'", arg) return end
            print("%s: %s respawn %s (%d samples, %d spawn points)", self.db.spawns[id].name or id,
                  est and U.FormatDuration(est) or "unknown", kind, n, pts)
            return
        end
        local rows = {}
        for id, s in pairs(self.db.spawns) do
            local est, kind, n, pts = self:RespawnEstimate(id)
            if est then rows[#rows + 1] = { name = s.name or id, est = est, kind = kind, n = n, pts = pts } end
        end
        table.sort(rows, function(a, b) return a.est < b.est end)
        print("Respawn estimates (%d mobs with data):", #rows)
        for i = 1, math.min(15, #rows) do
            local r = rows[i]
            print("  %-24s %s  %s (%d samples, %d points)", U.Trunc(r.name, 24), U.FormatDuration(r.est), r.kind, r.n, r.pts)
        end
    end },
    nodes = { help = "[herb|ore] — recorded gathering nodes on this map", fn = function(self, arg)
        local mapID = C_Map.GetBestMapForUnit("player")
        local kind = (arg == "herb" or arg == "ore") and arg or nil
        print("Nodes on %s:", U.MapName(mapID))
        local any = false
        for name, node in pairs(self.db.nodes) do
            if not kind or node.kind == kind then
                local n, times = 0, 0
                for _, p in ipairs(node.points) do if p[1] == mapID then n = n + 1; times = times + (p.n or 1) end end
                if n > 0 then any = true print("  %-24s %s  %d spots, gathered %d times", U.Trunc(name, 24), node.kind, n, times) end
            end
        end
        if not any then print("  none yet. Gather something; nodes record on successful casts.") end
    end },
    route = { help = "[herb|ore] [stops] — greedy route through known and seeded nodes, sets first waypoint", fn = function(self, arg)
        local kind, stops = U.SplitCmd(arg)
        kind = (kind == "herb" or kind == "ore") and kind or nil
        local route, err, total, mapID = self:Route(kind, tonumber(stops) or 12)
        if not route then print("route: %s", err) return end
        print("Route on %s, %d stops, ~%.0f yards:", U.MapName(mapID), #route, total)
        for i, p in ipairs(route) do
            print("  %2d. %-22s (%.1f, %.1f)  +%.0fy  %s", i, U.Trunc(p.name, 22), p.x * 100, p.y * 100, p.leg, p.seed and "Wowhead spawn" or ("seen x" .. p.n))
        end
        if SetWaypoint(mapID, route[1].x, route[1].y) then print("waypoint set to stop 1.") end
    end },
    rares = { help = "rare spawn sightings", fn = function(self)
        print("Rares seen:")
        local any = false
        for id, r in pairs(self.db.rares) do
            any = true
            local s = r.sightings[#r.sightings]
            print("  %-24s x%d  last %s (%.1f, %.1f) %s ago [%d]", U.Trunc(r.name or "?", 24), #r.sightings, U.MapName(s[1]), s[2] * 100, s[3] * 100,
                  U.FormatDuration(time() - s[4]), id)
        end
        if not any then print("  none yet.") end
    end },
    competition = { help = "other players seen around here", fn = function(self)
        local zone, sub = U.ZoneName()
        local key = zone .. (sub ~= "" and (" / " .. sub) or "")
        local recent, all, n = self:Competition(key)
        if not recent and not all then print("%s: no samples yet (one per minute while you're here).", key) return end
        print("%s: %.1f players/min lately, %.1f average over %d minutes.", key, recent or 0, all or 0, n)
        local rows = {}
        for k, c in pairs(self.db.competition) do
            local m = 0
            for _, s in ipairs(c.samples) do m = m + s.players end
            if #c.samples >= 5 then rows[#rows + 1] = { k = k, avg = m / #c.samples, n = #c.samples } end
        end
        table.sort(rows, function(a, b) return a.avg < b.avg end)
        for i = 1, math.min(8, #rows) do print("  %-36s %.1f avg over %d min", U.Trunc(rows[i].k, 36), rows[i].avg, rows[i].n) end
    end },
}
