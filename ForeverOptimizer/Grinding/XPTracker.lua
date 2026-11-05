local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Grinding")

-- ===========================================================================
-- Kill detection without the combat log: "<Mob> dies, you gain N experience."
-- Keeps a ring of kill timestamps for cadence estimates and fires FO_KILL.
-- Also banks xp/hr by activity per player level for the leveling optimizer.
-- ===========================================================================
local XT = FO:NewModule("Grinding.XPTracker", {
    account = "xp",
    defaults = { byLevel = {} },   -- [level] = { quest={xp,t}, grind={xp,t}, dungeon={xp,t} }
})

local xpPattern
local killTimes = {}
local RING = 30

local function Pattern()
    if not xpPattern then
        xpPattern = U.GlobalStringToPattern(COMBAT_XP_GAIN1 or COMBAT_XP_GAIN or "%s dies, you gain %d experience.")
    end
    return xpPattern
end

function XT:OnKillLine(msg)
    msg = U.Str(msg)
    if not msg then return end
    local name, xp = msg:match(Pattern())
    if not name then return end
    xp = tonumber(xp) or 0
    local now = GetTime()
    U.Push(killTimes, now, RING)
    local MD = FO:GetModule("Grinding.MobDatabase")
    local npcID, guid = nil, nil
    if MD then npcID, guid = MD:ResolveEngaged(name) end
    FO.Session:RecordKill(name, xp, npcID)
    FO:Fire("FO_KILL", name, xp, npcID, guid, now)
end

-- Median gap between recent kills (ignoring gaps > 3 min, which are breaks), and sample count
function XT:InterKillGap()
    local gaps = {}
    for i = 2, #killTimes do
        local g = killTimes[i] - killTimes[i - 1]
        if g > 0 and g <= 180 then gaps[#gaps + 1] = g end
    end
    return U.Median(gaps), #gaps
end

function XT:RecentKillsPerHour()
    local gap, n = self:InterKillGap()
    if gap and n >= 3 then return 3600 / gap, n end
    return nil, n
end

-- Level-bucketed xp by activity (fed by SessionManager's FO_XP)
local function Bucket(level)
    local b = XT.db.byLevel[level]
    if not b then
        b = { quest = { xp = 0, t = 0 }, grind = { xp = 0, t = 0 }, dungeon = { xp = 0, t = 0 } }
        XT.db.byLevel[level] = b
    end
    return b
end

XT.messages = {
    FO_XP = function(self, delta, activity)
        local b = Bucket(FO.Player.level or 0)
        if b[activity] then b[activity].xp = b[activity].xp + delta end
    end,
    FO_ACTIVITY = function(self, new, old, dur)
        local b = Bucket(FO.Player.level or 0)
        if b[old] then b[old].t = b[old].t + dur end
    end,
}

XT.events = {
    CHAT_MSG_COMBAT_XP_GAIN = function(self, msg) self:OnKillLine(msg) end,
}

XT.commands = {
    levels = { help = "xp/hr by activity for each level you've played", fn = function(self)
        local levels = U.Keys(self.db.byLevel)
        table.sort(levels)
        print("XP/hr by level (quest / grind / dungeon), min 5 minutes each:")
        for _, lvl in ipairs(levels) do
            local b = self.db.byLevel[lvl]
            local function r(a) local x = U.PerHour(b[a].xp, b[a].t, 300) return x and string.format("%6.0f", x) or "    --" end
            print("  L%-3d %s / %s / %s", lvl, r("quest"), r("grind"), r("dungeon"))
        end
        if #levels == 0 then print("  nothing yet.") end
    end },
}
