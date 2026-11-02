local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Grinding")

-- ===========================================================================
-- Where the non-fighting time goes: corpse runs, rest (eat/drink), travel,
-- town, idle. Travel legs are recorded zone-to-zone so the travel optimizer
-- can learn how long it takes to get places.
-- ===========================================================================
local DA = FO:NewModule("Grinding.DowntimeAnalyzer", {
    account = "downtime",
    defaults = { legs = {}, byZone = {} },   -- legs: { from=, to=, seconds=, t= }; byZone[zone] = { rest=, travel=, dead=, town=, idle=, prod= }
})

local travelStart, travelFrom
local restStart, restCount = nil, 0
local deathLog = {}

DA.messages = {
    FO_ACTIVITY = function(self, new, old, dur)
        local zone = U.ZoneName()
        local z = self.db.byZone[zone]
        if not z then z = { rest = 0, travel = 0, dead = 0, town = 0, idle = 0, prod = 0, rests = 0 } self.db.byZone[zone] = z end
        if old == "quest" or old == "grind" or old == "dungeon" then z.prod = z.prod + dur
        elseif z[old] then z[old] = z[old] + dur end
        if new == "travel" then travelStart, travelFrom = GetTime(), zone
        elseif old == "travel" and travelStart then
            local secs = GetTime() - travelStart
            if secs >= 20 then U.Push(self.db.legs, { from = travelFrom, to = zone, seconds = math.floor(secs), t = time() }, 300) end
            travelStart = nil
        end
        if new == "rest" then restStart = GetTime() z.rests = (z.rests or 0) + 1
        elseif old == "rest" then restStart = nil end
    end,
    FO_ALIVE = function(self, dur)
        U.Push(deathLog, { zone = U.ZoneName(), seconds = dur, t = time() }, 50)
    end,
}

-- Average travel time between two zones from recorded legs (either direction)
function DA:LegEstimate(fromZone, toZone)
    local secs = {}
    for _, l in ipairs(self.db.legs) do
        if (l.from == fromZone and l.to == toZone) or (l.from == toZone and l.to == fromZone) then secs[#secs + 1] = l.seconds end
    end
    return U.Median(secs), #secs
end

function DA:Report()
    local st = FO.Session:Stats()
    if not st then return end
    local by = st.by
    local prod = st.productive
    local function row(label, t, extra)
        print("  %-10s %8s  %5.1f%% of wall  %s", label, U.FormatDuration(t), st.elapsed > 0 and t / st.elapsed * 100 or 0, extra or "")
    end
    print("Downtime this session (%s wall, %s fighting = %.0f%%):", U.FormatDuration(st.elapsed), U.FormatDuration(prod),
          st.elapsed > 0 and prod / st.elapsed * 100 or 0)
    row("corpse", by.dead.t, string.format("%d deaths, avg run %s", st.deaths, st.deaths > 0 and U.FormatDuration(st.deathTime / st.deaths) or "--"))
    if st.deaths > 0 then
        local perDeath = st.deathTime / st.deaths
        local xpLost = st.xphProd and st.xphProd * perDeath / 3600 or nil
        print("  each death: ~%s of time%s%s (repairs/deaths is an approximation)", U.FormatDuration(perDeath),
              xpLost and string.format(" = ~%.0f xp", xpLost) or "", st.repairs > 0 and (" + ~" .. U.FormatMoney(st.repairs / st.deaths) .. " repairs") or "")
    end
    row("rest", by.rest.t, "eating / drinking")
    row("travel", by.travel.t, "")
    row("town", by.town.t, string.format("repairs %s", U.FormatMoney(st.repairs)))
    row("idle", by.idle.t, "")
    -- what downtime costs in xp
    if st.xphProd and st.downtime > 0 then
        local lost = st.xphProd * st.downtime / 3600
        print("  at your fighting rate of %.0f xp/hr, downtime cost ~%.0f xp (%s of leveling).", st.xphProd, lost,
              U.FormatDuration(lost / st.xphProd * 3600))
    end
    -- per-zone downtime share, to spot the "lower level but no downtime" zones
    local rows = {}
    for zone, z in pairs(self.db.byZone) do
        local wall = z.prod + z.rest + z.travel + z.dead + z.town + z.idle
        if wall >= 300 then rows[#rows + 1] = { zone = zone, wall = wall, pct = (wall - z.prod) / wall * 100, rest = z.rest / wall * 100, dead = z.dead / wall * 100 } end
    end
    table.sort(rows, function(a, b) return a.pct < b.pct end)
    if #rows > 0 then
        print("Zones by downtime share (lowest first):")
        for i = 1, math.min(8, #rows) do
            local r = rows[i]
            print("  %-22s %4.0f%% downtime (rest %.0f%%, dead %.0f%%) over %s", U.Trunc(r.zone, 22), r.pct, r.rest, r.dead, U.FormatDuration(r.wall))
        end
    end
end

DA.commands = {
    downtime = { help = "where non-fighting time goes", fn = function(self) self:Report() end },
    deaths = { help = "recent corpse runs", fn = function(self)
        local st = FO.Session:Stats()
        print("Deaths this session: %d, %s lost.", st.deaths, U.FormatDuration(st.deathTime))
        for i = math.max(1, #st.corpseRuns - 9), #st.corpseRuns do
            local c = st.corpseRuns[i]
            print("  %s  %s%s", U.FormatDuration(c.seconds), c.zone, c.rez and " (rezzed)" or "")
        end
    end },
    legs = { help = "recorded travel legs between zones", fn = function(self)
        local agg = {}
        for _, l in ipairs(self.db.legs) do
            local k = l.from .. " -> " .. l.to
            agg[k] = agg[k] or { n = 0, s = 0 }
            agg[k].n, agg[k].s = agg[k].n + 1, agg[k].s + l.seconds
        end
        print("Travel legs:")
        local any = false
        for k, a in pairs(agg) do any = true print("  %-48s avg %s over %d trips", U.Trunc(k, 48), U.FormatDuration(a.s / a.n), a.n) end
        if not any then print("  none yet.") end
    end },
}
