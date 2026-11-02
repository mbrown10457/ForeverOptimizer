local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Economy")

-- ===========================================================================
-- Gold efficiency: the full breakdown of where money came from and went,
-- plus the "effective" rate that counts what's in your bags at AH value.
-- Dungeon profitability lives here too since it's the same arithmetic.
-- ===========================================================================
local GP = FO:NewModule("Economy.GoldPerHour", {})

function GP:Report()
    local st = FO.Session:Stats()
    if not st then return end
    local M = U.FormatMoney
    print("Gold this session (%s):", U.FormatDuration(st.elapsed))
    print("  + loot coin     %s", M(st.lootGold))
    print("  + quest rewards %s", M(st.questGold))
    print("  + vendor sales  %s", M(st.vendorSales))
    print("  + mail in       %s", M(st.mailIn))
    print("  - repairs       %s", M(st.repairs))
    print("  - purchases     %s   (vendor goods, consumables)", M(st.purchases))
    print("  - flights       %s", M(st.taxi))
    print("  - training      %s", M(st.training))
    print("  - AH spend      %s", M(st.ahSpend))
    print("  - mail out      %s", M(st.mailOut))
    if st.transfers ~= 0 then print("  ~ transfers     %s   (bank/trade, excluded from rates)", M(st.transfers)) end
    print("  = net wallet    %s   %s/hr", M(st.gold), st.gph and M(st.gph) or "--")
    print("  bags: %s AH-sellable + %s vendor (%d items looted)", M(st.ahEst), M(st.vendorEst), st.items)
    print("  effective       %s   %s/hr   (net + AH estimate net of %d%% cut)", M(st.effective), st.egph and M(st.egph) or "--", U.AH_CUT * 100)
    if st.consumables > 0 then print("  consumables used %s (%s/hr)", M(st.consumables), M(st.consumables / math.max(st.elapsed, 60) * 3600)) end
    if st.ahEst == 0 and st.items > 0 then print("  (no AH prices known yet; /fo scan at an auction house)") end
end

function GP:DungeonReport()
    local runs = FO.Session.db.dungeons
    local live = FO.Session:Live()
    local agg = {}
    local function add(run)
        local a = agg[run.name]
        if not a then a = { name = run.name, n = 0, sec = 0, xp = 0, gold = 0, loot = 0, repairs = 0, deaths = 0, kills = 0 } agg[run.name] = a end
        a.n, a.sec, a.xp, a.gold = a.n + 1, a.sec + run.seconds, a.xp + run.xp, a.gold + run.gold
        a.loot, a.repairs, a.deaths, a.kills = a.loot + run.ahEst + run.vendorEst, a.repairs + run.repairs + (run.postRepairs or 0), a.deaths + run.deaths, a.kills + run.kills
    end
    for _, run in ipairs(runs) do add(run) end
    if live and live.dungeon then add(live.dungeon) end
    local rows = {}
    for _, a in pairs(agg) do
        a.xph = U.PerHour(a.xp, a.sec, 60)
        a.gph = U.PerHour(a.gold + a.loot - a.repairs, a.sec, 60)
        rows[#rows + 1] = a
    end
    table.sort(rows, function(x, y) return (x.xph or 0) > (y.xph or 0) end)
    print("Dungeons (avg time | xp/hr | eff gold/hr incl. loot - repairs | deaths/run):")
    for _, a in ipairs(rows) do
        print("  %-26s x%-2d %7s | %6s | %8s | %.1f", U.Trunc(a.name, 26), a.n, U.FormatDuration(a.sec / a.n), U.Rate(a.xph), a.gph and U.ShortMoney(a.gph) or "--", a.deaths / a.n)
    end
    if #rows == 0 then print("  no runs yet.") return end
    local act = FO.Analytics:ActivityRows(3)
    print("  vs open world near your level: grind %s xp/hr, quest %s xp/hr", U.Rate(act.grind.xph), U.Rate(act.quest.xph))
    local lastRun = runs[#runs]
    if lastRun and #lastRun.drops > 0 then
        print("Valuable drops last run (%s):", lastRun.name)
        for _, d in ipairs(lastRun.drops) do print("  %s x%d  %s", U.ItemName(d.itemID), d.qty, U.FormatMoney(d.value * d.qty)) end
    end
end

GP.commands = {
    gold = { help = "gold breakdown and effective gold/hr", fn = function(self) self:Report() end },
    dungeons = { help = "dungeon profitability vs open world", fn = function(self) self:DungeonReport() end },
}
