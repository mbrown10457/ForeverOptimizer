local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Quest")

-- ===========================================================================
-- Records what the client won't tell you about vanilla quests: where you
-- picked it up, where you turned it in, and where each objective ticked.
-- Fires FO_OBJECTIVE(questID, idx, delta, text, type) on progress.
--
-- db.quests[questID] = { title, level, accept={npcID,npcName,mapID,x,y}, turnin={...},
--                        objectives = { [idx] = { text, type, points = { {mapID,x,y,t} } } },
--                        rewardXP, rewardMoney, acceptedAt, completedAt, timesDone }
-- ===========================================================================
local QT = FO:NewModule("Quest.QuestTracker", {
    account = "quests",
    defaults = { quests = {}, settings = { autoTrack = true, maxPoints = 50 } },
})

local last = {} -- questID -> { [idx] = numFulfilled }

function QT:Quest(questID, title)
    local q = self.db.quests[questID]
    if not q then q = { title = title, objectives = {} } self.db.quests[questID] = q
    elseif title and not q.title then q.title = title end
    return q
end

local function NpcHere()
    local guid = U.Str(UnitGUID("npc")) or U.Str(UnitGUID("target"))
    local name = U.Str(UnitName("npc")) or U.Str(UnitName("target"))
    local mapID, x, y = U.PlayerPosition()
    return { npcID = U.NpcIDFromGUID(guid), npcName = name, mapID = mapID, x = x, y = y }
end

local function ReadObjectives(questID)
    local objs = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID)
    if not objs then return nil end
    local out = {}
    for i, o in ipairs(objs) do
        out[i] = { text = U.Str(o.text), type = U.Str(o.type), finished = o.finished == true,
                   num = U.Num(o.numFulfilled) or 0, req = U.Num(o.numRequired) or 0 }
    end
    return out
end
QT.ReadObjectives = ReadObjectives

function QT:LogQuestIDs()
    local ids = {}
    local n = U.Num(C_QuestLog.GetNumQuestLogEntries()) or 0
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then ids[#ids + 1] = { id = info.questID, title = U.Str(info.title), level = U.Num(info.level) } end
    end
    return ids
end

function QT:Snapshot()
    if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return end
    local live = {}
    for _, e in ipairs(self:LogQuestIDs()) do
        local qid = e.id
        live[qid] = true
        local q = self:Quest(qid, e.title)
        q.level = e.level or q.level
        local objs = ReadObjectives(qid)
        if objs then
            last[qid] = last[qid] or {}
            for idx, o in ipairs(objs) do
                local saved = q.objectives[idx]
                if not saved then saved = { text = o.text, type = o.type, points = {} } q.objectives[idx] = saved end
                if o.text then saved.text = o.text end
                saved.type = o.type or saved.type
                saved.req = o.req
                local prev = last[qid][idx]
                if prev ~= nil and o.num > prev then
                    local mapID, x, y = U.PlayerPosition()
                    if mapID and x then U.Push(saved.points, { mapID, x, y, time() }, self.db.settings.maxPoints) end
                    FO:Fire("FO_OBJECTIVE", qid, idx, o.num - prev, o.text, o.type, o.num, o.req)
                end
                last[qid][idx] = o.num
            end
        end
    end
    for qid in pairs(last) do if not live[qid] then last[qid] = nil end end
end

QT.events = {
    QUEST_LOG_UPDATE = function(self) self:Schedule() end,
    UNIT_QUEST_LOG_CHANGED = function(self, unit) if unit == "player" then self:Schedule() end end,
    QUEST_WATCH_UPDATE = function(self) self:Schedule() end,
    QUEST_REMOVED = function(self, questID) last[U.Num(questID) or 0] = nil end,
}

QT.messages = {
    FO_QUEST_ACCEPTED = function(self, questID)
        if not questID then return end
        local title = C_QuestLog.GetTitleForQuestID and U.Str(C_QuestLog.GetTitleForQuestID(questID))
        local q = self:Quest(questID, title)
        q.accept = NpcHere()
        q.acceptedAt = time()
        if self.db.settings.autoTrack and C_QuestLog.AddQuestWatch then pcall(C_QuestLog.AddQuestWatch, questID) end
        self:Schedule()
    end,
    FO_QUEST_TURNED_IN = function(self, questID, xp, money)
        if not questID then return end
        local q = self:Quest(questID)
        q.turnin = NpcHere()
        q.rewardXP, q.rewardMoney = xp, money
        q.completedAt = time()
        q.timesDone = (q.timesDone or 0) + 1
        if q.acceptedAt then q.lastDuration = time() - q.acceptedAt end
        last[questID] = nil
    end,
}

function QT:OnInit() self.Schedule = U.Debounce(0.3, function() self:Snapshot() end) end
function QT:OnEnable() self:Snapshot() end

QT.commands = {
    quests = { help = "list quests in log with known locations", fn = function(self)
        local RP = FO:GetModule("Quest.QuestRoutePlanner")
        local ids = self:LogQuestIDs()
        print("%d quests in log:", #ids)
        for _, e in ipairs(ids) do
            local mapID, x, y, src
            if RP then mapID, x, y, src = RP:NextWaypoint(e.id) end
            local where = (mapID and x) and string.format("%s (%.1f, %.1f) %s", U.MapName(mapID), x * 100, y * 100, src) or "unknown"
            print("  [%d] L%s %s -> %s", e.id, tostring(e.level or "?"), U.Trunc(e.title or "?", 34), where)
        end
    end },
    quest = { help = "<questID> — recorded detail", fn = function(self, arg)
        local qid = tonumber(arg)
        local q = qid and self.db.quests[qid]
        if not q then print("nothing recorded for '%s'", arg) return end
        print("%s (%d) L%s, done %d times%s", q.title or "?", qid, tostring(q.level), q.timesDone or 0,
              q.lastDuration and (", last took " .. U.FormatDuration(q.lastDuration)) or "")
        local function loc(tag, l)
            if l and l.mapID and l.x then print("  %s: %s (%s) at %s (%.1f, %.1f)", tag, l.npcName or "?", tostring(l.npcID), U.MapName(l.mapID), l.x * 100, l.y * 100) end
        end
        loc("accept", q.accept) loc("turn-in", q.turnin)
        for idx, o in pairs(q.objectives) do print("  obj %d [%s]: %s (%d points)", idx, o.type or "?", o.text or "?", #o.points) end
        if q.rewardXP then print("  reward %d xp, %s", q.rewardXP, U.FormatMoney(q.rewardMoney or 0)) end
    end },
    autotrack = { help = "toggle auto-watch on accept", fn = function(self)
        self.db.settings.autoTrack = not self.db.settings.autoTrack
        print("auto-track on accept: %s", tostring(self.db.settings.autoTrack))
    end },
}
