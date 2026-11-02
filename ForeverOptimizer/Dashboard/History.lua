local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Dashboard")

-- ===========================================================================
-- Session history and "versus comparable sessions": same character, within
-- 3 levels, at least 10 minutes long.
-- ===========================================================================
local H = FO:NewModule("Dashboard.History", {})

local function Rates(s)
    local el = s.elapsed or 0
    return U.PerHour(s.xp or 0, el, 60), U.PerHour((s.gold or 0) + (s.ahEst or 0), el, 60), U.PerHour(s.deaths or 0, el, 60) or 0
end

function H:Comparable()
    local live = FO.Session:Live()
    local lvl = live and live.level or FO.Player.level
    local out = {}
    for _, s in ipairs(FO.Session.db.list) do
        if s.char == FO.charKey and (s.elapsed or 0) >= 600 and math.abs((s.level or 0) - lvl) <= 3 then out[#out + 1] = s end
    end
    return out
end

-- Current session vs the average of comparable ones. Returns nil if nothing to compare.
function H:Compare()
    local st = FO.Session:Stats()
    local comp = self:Comparable()
    if not st or #comp == 0 then return nil end
    local sx, sg, sd, sdown = 0, 0, 0, 0
    for _, s in ipairs(comp) do
        local x, g, d = Rates(s)
        sx, sg, sd = sx + (x or 0), sg + (g or 0), sd + d
        local t = s.time or {}
        local wall = s.elapsed or 1
        sdown = sdown + ((t.travel or 0) + (t.rest or 0) + (t.town or 0) + (t.dead or 0) + (t.idle or 0)) / wall * 100
    end
    local n = #comp
    local function delta(cur, avg) if not cur or not avg or avg == 0 then return nil end return (cur - avg) / avg * 100 end
    return {
        n = n, xph = sx / n, egph = sg / n, dph = sd / n, down = sdown / n,
        dXph = delta(st.xph, sx / n), dEgph = delta(st.egph, sg / n), dDown = st.downtimePct - sdown / n,
    }
end

FO.Dashboard:RegisterTab("History", 5, function()
    local out = {}
    local c = H:Compare()
    if c then
        out[#out + 1] = string.format("vs %d sessions: xp %s%+.0f%%|r  gold %s%+.0f%%|r  down %s%+.0f|r", c.n,
            (c.dXph or 0) >= 0 and "|cff60ff60" or "|cffff6060", c.dXph or 0, (c.dEgph or 0) >= 0 and "|cff60ff60" or "|cffff6060", c.dEgph or 0,
            c.dDown <= 0 and "|cff60ff60" or "|cffff6060", c.dDown)
    else
        out[#out + 1] = "no comparable sessions yet"
    end
    local list = FO.Session.db.list
    H.page = H.page or 0
    local top = #list - H.page * 6
    if top < 1 then H.page = 0 top = #list end
    for i = top, math.max(1, top - 5), -1 do
        local s = list[i]
        local x, g = Rates(s)
        out[#out + 1] = string.format("%s L%d %s %s xp/hr %s", date("%m/%d", s.start), s.level or 0, U.Trunc(s.zone or "?", 12), U.Rate(x), g and U.ShortMoney(g) or "--")
    end
    if H.page > 0 then out[#out + 1] = string.format("|cffaaaaaapage %d of %d|r", H.page + 1, math.ceil(#list / 6)) end
    return out
end, function()
    local n = #FO.Session.db.list
    return {
        { label = "Newer", fn = function() H.page = math.max(0, (H.page or 0) - 1) end },
        { label = "Older", fn = function() if n - ((H.page or 0) + 1) * 6 >= 1 then H.page = (H.page or 0) + 1 end end, active = (H.page or 0) > 0 },
        { label = "Report", fn = FO.Dashboard.Cmd("history") },
    }
end)

H.commands = {
    history = { help = "[n] — last sessions and comparison with comparable ones", fn = function(self, arg)
        local n = tonumber(arg) or 10
        local list = FO.Session.db.list
        print("Last %d sessions (date, level, zone, length, xp/hr, eff gold/hr, deaths, quests, downtime):", math.min(n, #list))
        for i = #list, math.max(1, #list - n + 1), -1 do
            local s = list[i]
            local x, g = Rates(s)
            local t = s.time or {}
            local down = (s.elapsed or 0) > 0 and ((t.travel or 0) + (t.rest or 0) + (t.town or 0) + (t.dead or 0) + (t.idle or 0)) / s.elapsed * 100 or 0
            print("  %s L%-2d %-18s %7s %6s %8s %2d %2d %3.0f%%", date("%m/%d %H:%M", s.start), s.level or 0, U.Trunc(s.zone or "?", 18),
                  U.FormatDuration(s.elapsed), U.Rate(x), g and U.ShortMoney(g) or "--", s.deaths or 0, s.questsDone or 0, down)
        end
        local c = self:Compare()
        local st = FO.Session:Stats()
        if c and st then
            print("This session vs %d comparable (L%d±3, ≥10 min): xp/hr %s vs %.0f (%+.0f%%), eff gold/hr %s vs %s (%+.0f%%), downtime %.0f%% vs %.0f%%, deaths/hr %.1f vs %.1f",
                  c.n, st.level, U.Rate(st.xph), c.xph, c.dXph or 0, st.egph and U.ShortMoney(st.egph) or "--", U.ShortMoney(c.egph), c.dEgph or 0,
                  st.downtimePct, c.down, U.PerHour(st.deaths, st.elapsed, 60) or 0, c.dph)
        else
            print("No comparable sessions yet for a comparison.")
        end
    end },
}
