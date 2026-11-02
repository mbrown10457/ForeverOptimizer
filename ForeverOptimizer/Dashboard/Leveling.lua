local ADDON, FO = ...
local U = FO.Util

FO.Dashboard:RegisterTab("Leveling", 2, function()
    local st = FO.Session:Stats()
    if not st then return { "no session" } end
    local out = {}
    local E = FO.Analytics:Estimate()
    out[#out + 1] = string.format("quest %s/hr  grind %s/hr  dng %s/hr", U.Rate(st.by.quest.xph), U.Rate(st.by.grind.xph), U.Rate(st.by.dungeon.xph))
    if E and E.xpPerHour then
        out[#out + 1] = string.format("Spot: %.0f k/hr x %.0f xp = %s xp/hr", E.killsPerHour, E.xpPerKill, U.Rate(E.xpPerHour))
        if E.ttk then out[#out + 1] = string.format("kill %.1fs + gap %.1fs", E.ttk, E.gapBetween or 0) end
    else
        out[#out + 1] = "Spot: need a few kills"
    end
    local QE = FO:GetModule("Quest.QuestEfficiency")
    local rows = QE and QE:ActiveEstimates() or {}
    for i = 1, math.min(3, #rows) do
        local r = rows[i]
        out[#out + 1] = string.format("%s %d/%d %s%s", U.Trunc(r.text or "?", 16), r.num or 0, r.req or 0,
            r.rate and string.format("%.0f%%", r.rate * 100) or "--", r.expTime and (" ~" .. U.FormatDuration(r.expTime)) or "")
    end
    local act = FO.Analytics:ActivityRows(3)
    out[#out + 1] = string.format("L%d hist: q %s  g %s  d %s", FO.Player.level, U.Rate(act.quest.xph), U.Rate(act.grind.xph), U.Rate(act.dungeon.xph))
    local best = FO.Analytics:BestZone(3)
    if best and best.zone ~= st.zone and best.xph then out[#out + 1] = string.format("Best zone: %s %s/hr", U.Trunc(best.zone, 14), U.Rate(best.xph)) end
    return out
end)
