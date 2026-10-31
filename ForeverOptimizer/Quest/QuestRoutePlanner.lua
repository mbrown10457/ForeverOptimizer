local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Quest")

-- ===========================================================================
-- Where to go next. Blizzard waypoint if the client has one, else our own
-- recorded objective points, else the turn-in NPC. The route command orders
-- all known quest targets on the current map by nearest-neighbour.
-- ===========================================================================
local RP = FO:NewModule("Quest.QuestRoutePlanner", {})

function RP:NextWaypoint(questID)
    local QT = FO:GetModule("Quest.QuestTracker")
    if C_QuestLog.GetNextWaypoint then
        local mapID, x, y = C_QuestLog.GetNextWaypoint(questID)
        mapID, x, y = U.Num(mapID), U.Num(x), U.Num(y)
        if mapID and x and y then return mapID, x, y, "blizzard" end
    end
    local q = QT.db.quests[questID]
    if not q then return nil end
    local objs = QT.ReadObjectives(questID) or {}
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
    if allDone or (C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)) then
        if q.turnin and q.turnin.mapID and q.turnin.x then return q.turnin.mapID, q.turnin.x, q.turnin.y, "turn-in" end
        if q.accept and q.accept.mapID and q.accept.x then return q.accept.mapID, q.accept.x, q.accept.y, "accept npc (turn-in unknown)" end
    end
    return nil
end

local function SetWaypoint(mapID, x, y)
    if not C_Map.CanSetUserWaypointOnMap or not C_Map.CanSetUserWaypointOnMap(mapID) then return false end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    return true
end

local function Yards(mapID, x1, y1, x2, y2)
    return U.YardsBetween(mapID, x1, y1, x2, y2) or math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) * 3000
end

-- All quest targets on the current map, ordered greedily from the player
function RP:Route()
    local QT = FO:GetModule("Quest.QuestTracker")
    local mapID, px, py = U.PlayerPosition()
    if not mapID or not px then return nil, "no position" end
    local targets = {}
    for _, e in ipairs(QT:LogQuestIDs()) do
        local m, x, y, src = self:NextWaypoint(e.id)
        if m == mapID and x then targets[#targets + 1] = { qid = e.id, title = e.title or "?", x = x, y = y, src = src } end
    end
    if #targets == 0 then return nil, "no quest targets known on this map" end
    local route, cx, cy, total = {}, px, py, 0
    while #targets > 0 do
        local bi, bd
        for i, t in ipairs(targets) do
            local d = Yards(mapID, cx, cy, t.x, t.y)
            if not bd or d < bd then bi, bd = i, d end
        end
        local t = table.remove(targets, bi)
        t.leg = bd total = total + bd
        route[#route + 1] = t
        cx, cy = t.x, t.y
    end
    return route, nil, total, mapID
end

RP.commands = {
    next = { help = "[questID] — waypoint to the next known quest location", fn = function(self, arg)
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
        if SetWaypoint(mapID, x, y) then print("waypoint set.") end
    end },
    route = { help = "(quest) ordered route through quest targets on this map", fn = function(self)
        local route, err, total, mapID = self:Route()
        if not route then print("route: %s", err) return end
        print("Quest route on %s, %d stops, ~%.0f yards:", U.MapName(mapID), #route, total)
        for i, t in ipairs(route) do print("  %2d. %-30s (%.1f, %.1f) +%.0fy [%s]", i, U.Trunc(t.title, 30), t.x * 100, t.y * 100, t.leg, t.src) end
        if SetWaypoint(mapID, route[1].x, route[1].y) then print("waypoint set to stop 1.") end
    end },
}
