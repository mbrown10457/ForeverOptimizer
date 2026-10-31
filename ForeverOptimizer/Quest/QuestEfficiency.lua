local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Quest")

-- ===========================================================================
-- Quest drop probability calculator + quest xp efficiency.
--
-- For each active objective we count kills of the mobs that have produced a
-- tick for it (the "source set"). Before the first tick, every kill counts
-- provisionally; once we know the sources we re-filter. Observed rate =
-- ticks / source kills. Remaining kills = remaining / rate. Time = kills *
-- current seconds-per-kill.
--
-- Historical rates are saved per quest objective so an alt (or a friend's
-- data later) can see "this one is a 9% drop" before taking it.
-- ===========================================================================
local QE = FO:NewModule("Quest.QuestEfficiency", {
    account = "questeff",
    defaults = { history = {} },   -- [questID.."/"..idx] = { kills=, items=, text= }
})

local track = {}  -- questID -> idx -> { killsBy = {name=n}, sources = {name=true}, items = 0, lastTickKill = nil, startedAt }
local lastKillName, lastKillAt

local function Key(qid, idx) return qid .. "/" .. idx end

-- Wilson score interval (95%) for a proportion k/n. Wide for small n, which is the point.
local function Wilson(k, n)
    if n == 0 then return 0, 1 end
    local z = 1.96
    local p = k / n
    local denom = 1 + z * z / n
    local centre = (p + z * z / (2 * n)) / denom
    local half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return math.max(0, centre - half), math.min(1, centre + half)
end
QE.Wilson = Wilson

local function Tracker(qid, idx)
    track[qid] = track[qid] or {}
    local t = track[qid][idx]
    if not t then
        t = { killsBy = {}, sources = {}, items = 0, startedAt = GetTime() }
        track[qid][idx] = t
    end
    return t
end

local function SourceKills(t)
    local n, any = 0, false
    for name in pairs(t.sources) do any = true n = n + (t.killsBy[name] or 0) end
    if not any then for _, k in pairs(t.killsBy) do n = n + k end end
    return n, any
end

QE.messages = {
    FO_KILL = function(self, name)
        lastKillName, lastKillAt = name, GetTime()
        for _, perQuest in pairs(track) do
            for _, t in pairs(perQuest) do t.killsBy[name] = (t.killsBy[name] or 0) + 1 end
        end
    end,
    FO_OBJECTIVE = function(self, qid, idx, delta, text, otype, num, req)
        if otype ~= "item" and otype ~= "monster" then return end
        local t = Tracker(qid, idx)
        t.text, t.type, t.num, t.req = text, otype, num, req
        t.items = t.items + delta
        -- credit the mob killed in the last few seconds as a source
        if lastKillName and lastKillAt and (GetTime() - lastKillAt) < 30 then t.sources[lastKillName] = true end
        local h = self.db.history[Key(qid, idx)]
        if not h then h = { kills = 0, items = 0, text = text } self.db.history[Key(qid, idx)] = h end
        h.items = h.items + delta
        h.text = text or h.text
    end,
    FO_QUEST_TURNED_IN = function(self, qid) self:Flush(qid) end,
}

QE.events = {
    QUEST_REMOVED = function(self, qid) self:Flush(U.Num(qid)) end,
}

-- Bank source kills into history and forget live tracking for a quest
function QE:Flush(qid)
    local perQuest = qid and track[qid]
    if not perQuest then return end
    for idx, t in pairs(perQuest) do
        local kills = SourceKills(t)
        local h = self.db.history[Key(qid, idx)]
        if h and kills > 0 then h.kills = h.kills + kills end
    end
    track[qid] = nil
end

function QE:Estimate(qid, idx)
    local t = track[qid] and track[qid][idx]
    if not t then return nil end
    local kills, haveSources = SourceKills(t)
    local rate = kills > 0 and t.items / kills or nil
    local hist = self.db.history[Key(qid, idx)]
    local histRate = hist and hist.kills > 0 and hist.items / hist.kills or nil
    local useRate = rate
    -- blend in history when live sample is tiny
    if histRate and (kills < 10) then useRate = rate and (rate * kills + histRate * 10) / (kills + 10) or histRate end
    local remaining = (t.req or 0) - (t.num or 0)
    local expKills = (useRate and useRate > 0) and remaining / useRate or nil
    local rateLo, rateHi = Wilson(t.items, kills)
    local expKillsLo = rateHi > 0 and remaining / rateHi or nil   -- optimistic
    local expKillsHi = rateLo > 0 and remaining / rateLo or nil   -- pessimistic; nil = unbounded
    local confidence = kills >= 30 and "ok" or kills >= 10 and "rough" or "guess"
    local XT = FO:GetModule("Grinding.XPTracker")
    local gap = XT and XT:InterKillGap()
    local expTime = (expKills and gap) and expKills * gap or nil
    return {
        kills = kills, items = t.items, rate = rate, histRate = histRate, useRate = useRate, haveSources = haveSources,
        remaining = remaining, expKills = expKills, expTime = expTime, text = t.text, sources = t.sources,
        num = t.num, req = t.req, rateLo = rateLo, rateHi = rateHi, expKillsLo = expKillsLo, expKillsHi = expKillsHi, confidence = confidence,
    }
end

function QE:ActiveEstimates()
    local QT = FO:GetModule("Quest.QuestTracker")
    local out = {}
    for _, e in ipairs(QT:LogQuestIDs()) do
        local objs = QT.ReadObjectives(e.id)
        for idx, o in ipairs(objs or {}) do
            if (o.type == "item" or o.type == "monster") and not o.finished then
                Tracker(e.id, idx).text = o.text
                local t = Tracker(e.id, idx)
                t.num, t.req, t.type = o.num, o.req, o.type
                local est = self:Estimate(e.id, idx)
                if est then est.qid, est.idx, est.title = e.id, idx, e.title out[#out + 1] = est end
            end
        end
    end
    table.sort(out, function(a, b) return (a.expTime or 1e9) < (b.expTime or 1e9) end)
    return out
end

QE.commands = {
    drops = { help = "quest drop odds and kills-to-finish for active objectives", fn = function(self)
        local rows = self:ActiveEstimates()
        if #rows == 0 then print("no active kill/item objectives.") return end
        print("Quest objectives (observed rate [95%% range] -> expected kills [range], time):")
        for _, r in ipairs(rows) do
            local rateS = r.rate and string.format("%.0f%% [%.0f-%.0f%%]", r.rate * 100, r.rateLo * 100, r.rateHi * 100) or "--"
            local histS = r.histRate and string.format(" hist %.0f%%", r.histRate * 100) or ""
            local srcs = {}
            for n in pairs(r.sources) do srcs[#srcs + 1] = n end
            local range = (r.expKillsLo and r.expKills) and string.format(" [%.0f-%s]", r.expKillsLo, r.expKillsHi and string.format("%.0f", r.expKillsHi) or "∞") or ""
            print("  %-30s %d/%d  %d items / %d kills = %s%s -> ~%s%s kills, %s (%s)%s",
                U.Trunc(r.text or "?", 30), r.num or 0, r.req or 0, r.items, r.kills, rateS, histS,
                r.expKills and string.format("%.0f", r.expKills) or "?", range,
                r.expTime and U.FormatDuration(r.expTime) or "?", r.confidence,
                #srcs > 0 and ("  [" .. table.concat(srcs, ", ") .. "]") or (r.haveSources and "" or "  (no source mob yet)"))
        end
    end },
    questxp = { help = "xp per hour of questing vs reward sizes", fn = function(self)
        local QT = FO:GetModule("Quest.QuestTracker")
        local st = FO.Session:Stats()
        print("Questing this session: %s, %d xp from turn-ins, %s/hr in quest mode.", U.FormatDuration(st.by.quest.t), st.questXP, U.Rate(st.by.quest.xph))
        local rows = {}
        for qid, q in pairs(QT.db.quests) do
            if q.rewardXP and q.lastDuration and q.lastDuration > 60 then
                rows[#rows + 1] = { title = q.title or qid, xph = q.rewardXP / q.lastDuration * 3600, dur = q.lastDuration, xp = q.rewardXP }
            end
        end
        table.sort(rows, function(a, b) return a.xph > b.xph end)
        if #rows > 0 then
            print("Completed quests by reward xp per hour held (accept -> turn-in):")
            for i = 1, math.min(10, #rows) do print("  %-34s %5d xp in %s = %.0f/hr", U.Trunc(rows[i].title, 34), rows[i].xp, U.FormatDuration(rows[i].dur), rows[i].xph) end
        end
    end },
}
