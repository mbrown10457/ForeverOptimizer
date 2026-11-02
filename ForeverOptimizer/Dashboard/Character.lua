local ADDON, FO = ...
local U = FO.Util

FO.Dashboard:RegisterTab("Character", 4, function()
    local C = FO.Player
    local out = { string.format("L%d %s  %s", C.level, C.classLocal, U.ShortMoney(C.money)) }
    local TP = FO:GetModule("Character.TrainingPlanner")
    if TP then
        local owedNow, _, total = TP:Upcoming(C.level + 5, false)
        out[#out + 1] = string.format("Training: %s now, %s thru L%d", U.ShortMoney(owedNow), U.ShortMoney(total), C.level + 5)
        local st = FO.Session:Stats()
        for _, g in ipairs(TP.cdb.goals) do
            if not g.level or g.level >= C.level then
                local need = g.cost + (g.level and select(3, TP:Upcoming(g.level, false)) or 0)
                local gap = need - C.money
                local eta = (gap > 0 and st and st.egph and st.egph > 0) and (" ~" .. U.FormatDuration(gap / st.egph * 3600)) or ""
                out[#out + 1] = string.format("%s: %s/%s%s", U.Trunc(g.name, 14), U.ShortMoney(math.min(C.money, need)), U.ShortMoney(need), eta)
                break
            end
        end
    end
    for name, pr in pairs(C.professions or {}) do out[#out + 1] = string.format("%s %d/%d", name, pr.rank, pr.max) end
    out[#out + 1] = "Hearth: " .. U.Trunc(C.bind or "?", 20)
    return out
end)
