local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Character")

-- ===========================================================================
-- Reputation planner, hearthstone/travel optimizer, level ETA.
-- Rep gains are attributed to the mob killed or quest turned in just before.
-- ===========================================================================
local PP = FO:NewModule("Character.ProgressionPlanner", {
    account = "progression",
    defaults = { rep = {} },   -- [faction] = { mobs = { [name] = { n, total } }, quests = { [title] = { n, total } } }
})

local lastKill, lastKillAt, lastQuest, lastQuestAt
local repPattern
local sessionRep = {} -- faction -> rep gained this session

local function FactionRows()
    local rows = {}
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        for i = 1, U.Num(C_Reputation.GetNumFactions()) or 0 do
            local f = C_Reputation.GetFactionDataByIndex(i)
            if f and not f.isHeader and f.name then
                rows[#rows + 1] = { name = U.Str(f.name), standing = U.Num(f.reaction), value = U.Num(f.currentStanding) or 0,
                                    min = U.Num(f.currentReactionThreshold) or 0, max = U.Num(f.nextReactionThreshold) or 0, watched = f.isWatched == true }
            end
        end
    elseif GetNumFactions then
        for i = 1, GetNumFactions() do
            local name, _, standingID, barMin, barMax, barValue, _, _, isHeader, _, _, isWatched = GetFactionInfo(i)
            if name and not isHeader then rows[#rows + 1] = { name = U.Str(name), standing = U.Num(standingID), value = U.Num(barValue) or 0, min = U.Num(barMin) or 0, max = U.Num(barMax) or 0, watched = isWatched == true } end
        end
    end
    return rows
end

local STANDING = { [1] = "Hated", [2] = "Hostile", [3] = "Unfriendly", [4] = "Neutral", [5] = "Friendly", [6] = "Honored", [7] = "Revered", [8] = "Exalted" }

PP.messages = {
    FO_KILL = function(self, name) lastKill, lastKillAt = name, GetTime() end,
    FO_QUEST_TURNED_IN = function(self, qid) 
        local title = qid and C_QuestLog.GetTitleForQuestID and U.Str(C_QuestLog.GetTitleForQuestID(qid))
        lastQuest, lastQuestAt = title or ("quest " .. tostring(qid)), GetTime()
    end,
}

PP.events = {
    CHAT_MSG_COMBAT_FACTION_CHANGE = function(self, msg)
        msg = U.Str(msg)
        if not msg then return end
        repPattern = repPattern or U.GlobalStringToPattern(FACTION_STANDING_INCREASED or "Reputation with %s increased by %d.")
        local faction, amount = msg:match(repPattern)
        if not faction then return end
        amount = tonumber(amount) or 0
        local r = self.db.rep[faction]
        if not r then r = { mobs = {}, quests = {} } self.db.rep[faction] = r end
        sessionRep[faction] = (sessionRep[faction] or 0) + amount
        local now = GetTime()
        if lastQuestAt and now - lastQuestAt < 5 then
            local q = r.quests[lastQuest] or { n = 0, total = 0 }
            q.n, q.total = q.n + 1, q.total + amount
            r.quests[lastQuest] = q
        elseif lastKillAt and now - lastKillAt < 5 then
            local m = r.mobs[lastKill] or { n = 0, total = 0 }
            m.n, m.total = m.n + 1, m.total + amount
            r.mobs[lastKill] = m
        end
    end,
}

function PP:RepReport(arg)
    local rows = FactionRows()
    local pick
    if arg ~= "" then for _, f in ipairs(rows) do if f.name:lower():find(arg:lower(), 1, true) then pick = f break end end
    else for _, f in ipairs(rows) do if f.watched then pick = f break end end end
    if not pick then
        print("factions with recorded sources:")
        for name, r in pairs(self.db.rep) do print("  %s: %d mob sources, %d quest sources", name, U.Count(r.mobs), U.Count(r.quests)) end
        print("usage: /fo rep <faction>  (or watch one on the reputation pane)")
        return
    end
    local toNext = pick.max - pick.value
    print("%s: %s, %d/%d (%d to %s)", pick.name, STANDING[pick.standing] or "?", pick.value - pick.min, pick.max - pick.min, toNext, STANDING[(pick.standing or 0) + 1] or "next")
    local gained = sessionRep[pick.name] or 0
    if gained > 0 then
        local rph = U.PerHour(gained, FO.Session:Elapsed(), 60)
        print("  this session: +%d (%s rep/hr%s)", gained, U.Rate(rph), rph and rph > 0 and (", " .. U.FormatDuration(toNext / rph * 3600) .. " to next standing at this pace") or "")
    end
    local r = self.db.rep[pick.name]
    if not r then print("  no sources recorded yet; kills and turn-ins will teach me.") return end
    local best
    local mobs = {}
    for name, m in pairs(r.mobs) do mobs[#mobs + 1] = { name = name, per = m.total / m.n, n = m.n } end
    table.sort(mobs, function(a, b) return a.per > b.per end)
    local XT = FO:GetModule("Grinding.XPTracker")
    local gap = XT and XT:InterKillGap()
    for i = 1, math.min(6, #mobs) do
        local m = mobs[i]
        local kills = toNext / m.per
        print("  %-26s %4.0f rep/kill (%d seen) -> %.0f kills%s", U.Trunc(m.name, 26), m.per, m.n, kills, gap and (", ~" .. U.FormatDuration(kills * gap)) or "")
    end
    local qs = {}
    for title, q in pairs(r.quests) do qs[#qs + 1] = { title = title, per = q.total / q.n } end
    table.sort(qs, function(a, b) return a.per > b.per end)
    for i = 1, math.min(6, #qs) do print("  quest %-28s %4.0f rep", U.Trunc(qs[i].title, 28), qs[i].per) end
end

-- Hearthstone / travel
local function HearthCooldown()
    local start, dur
    if C_Container and C_Container.GetItemCooldown then start, dur = C_Container.GetItemCooldown(6948)
    elseif GetItemCooldown then start, dur = GetItemCooldown(6948) end
    start, dur = U.Num(start), U.Num(dur)
    if not start or not dur or dur == 0 or start == 0 then return 0 end
    return math.max(0, start + dur - GetTime())
end

function PP:TravelReport()
    local DA = FO:GetModule("Grinding.DowntimeAnalyzer")
    local zone = U.ZoneName()
    local bind = FO.Player.bind or "?"
    local cd = HearthCooldown()
    print("Hearth: %s, %s.", bind, cd > 0 and ("ready in " .. U.FormatDuration(cd)) or "ready")
    local est, n = DA:LegEstimate(zone, bind)
    if est then print("  %s <-> %s has taken you %s on foot (%d trips).", zone, bind, U.FormatDuration(est), n) end
    -- where do you keep walking to?
    local cutoff = time() - 7 * 86400
    local dest = {}
    for _, l in ipairs(DA.db.legs) do
        if l.t >= cutoff and l.to ~= bind and l.seconds >= 120 then
            dest[l.to] = dest[l.to] or { n = 0, s = 0 }
            dest[l.to].n, dest[l.to].s = dest[l.to].n + 1, dest[l.to].s + l.seconds
        end
    end
    local rows = {}
    for z, d in pairs(dest) do rows[#rows + 1] = { zone = z, n = d.n, avg = d.s / d.n, total = d.s } end
    table.sort(rows, function(a, b) return a.total > b.total end)
    if rows[1] and rows[1].n >= 3 then
        print("  You've walked to %s %d times this week (%s each, %s total). If that's your hub, rebind there.", rows[1].zone, rows[1].n, U.FormatDuration(rows[1].avg), U.FormatDuration(rows[1].total))
    end
    if cd == 0 and zone ~= bind and not FO:AnyTownFrame() and est and est > 180 then
        print("  Hearth is ready and %s is %s away: hearth for the town trip, fly back.", bind, U.FormatDuration(est))
    end
    local st = FO.Session:Stats()
    print("  Travel this session: %s (%.0f%% of wall time).", U.FormatDuration(st.by.travel.t), st.elapsed > 0 and st.by.travel.t / st.elapsed * 100 or 0)
end

-- Level ETA. Vanilla xp-to-level grows ~ roughly geometrically; we use the current bar as the base.
function PP:Eta(arg)
    local target = math.min(math.max(tonumber(arg) or (FO.Player.level + 5), FO.Player.level + 1), 60)
    local st = FO.Session:Stats()
    local rows = FO.Analytics:ZoneRows(3)
    local xph = st.xph
    local src = "this session"
    if (not xph or st.elapsed < 1800) and rows[1] then
        local sumXp, sumT = 0, 0
        for _, r in ipairs(rows) do sumXp, sumT = sumXp + r.xp, sumT + r.prod + r.down end
        if sumT > 0 then xph = sumXp / sumT * 3600 src = "recent sessions near this level" end
    end
    if not xph or xph <= 0 then print("no xp rate yet.") return end
    local xp, xpMax = U.Num(UnitXP("player")) or 0, U.Num(UnitXPMax("player")) or 1
    local need = xpMax - xp
    local bar = xpMax
    for l = FO.Player.level + 1, target - 1 do bar = bar * 1.09 need = need + bar end
    print("To L%d: ~%.0f xp at %.0f xp/hr (%s) = %s of play. Rough: later levels are estimated at +9%%/level.", target, need, xph, src, U.FormatDuration(need / xph * 3600))
end

PP.commands = {
    rep = { help = "[faction] — rep sources and kills to next standing", fn = function(self, arg) self:RepReport(arg) end },
    hearth = { help = "hearth/travel suggestions", fn = function(self) self:TravelReport() end },
    eta = { help = "[level] — time to level estimate", fn = function(self, arg) self:Eta(arg) end },
}
