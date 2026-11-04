-- Loads the addon in the stub client and prints every mismatch between the hand-authored
-- rotation/build data and the generated seeds. Exit 1 on errors (optional runes only warn).
package.path = "./test/?.lua;" .. package.path
local S = require("wowstub")
local FO = S.loadAddon("ForeverOptimizer")
S.fire("ADDON_LOADED", "ForeverOptimizer") S.fire("PLAYER_LOGIN")
local report = FO.Rotation:ValidateAll()
local errs = 0
print(string.format("seed build %s: %d spells, %d talents, %d items", FO.Seed.spellBuild, FO.Seed.spellCount, #FO.Seed.talents, FO.Seed.itemCount))
for _, r in ipairs(report) do
    if not r.warning then errs = errs + 1 end
    print(string.format("%s %s: %s", r.warning and "warn " or "ERROR", r.class, r.line))
end
-- Leveling routes (Data/Routes.lua): every step well formed, class tags valid, quest steps placed
local KINDS = { A = true, C = true, T = true, GOTO = true, HEARTH = true, TRAIN = true, LEVEL = true, NOTE = true }
local CLASSES = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true }
local warns = #report - errs
local nsteps = 0
for _, r in ipairs(FO.Routes or {}) do
    local seen = {}
    for i, st in ipairs(r.steps or {}) do
        nsteps = nsteps + 1
        local where = string.format("%s step %d", r.key, i)
        if not KINDS[st[1]] then errs = errs + 1 print("ERROR " .. where .. ": unknown kind " .. tostring(st[1])) end
        if (st[1] == "A" or st[1] == "C" or st[1] == "T") and type(st[2]) ~= "number" then errs = errs + 1 print("ERROR " .. where .. ": quest id missing") end
        if (st[1] == "A" or st[1] == "T" or st[1] == "GOTO" or st[1] == "HEARTH") and not (st[5] and st[6] and st[7]) then errs = errs + 1 print("ERROR " .. where .. ": no coordinates") end
        if st.class then
            for tok in st.class:gsub("^%-", ""):gmatch("[^,]+") do
                if not CLASSES[tok] then errs = errs + 1 print("ERROR " .. where .. ": unknown class " .. tok) end
            end
        end
        if st[1] == "C" or st[1] == "T" then
            local key = (st.class or "") .. ":" .. tostring(st[2])
            if not st.auto and not seen[key] and not seen[":" .. tostring(st[2])] then warns = warns + 1 print("warn  " .. where .. ": " .. st[1] .. " " .. tostring(st[2]) .. " (" .. tostring(st[3]) .. ") before any accept step") end
        elseif st[1] == "A" then
            seen[(st.class or "") .. ":" .. tostring(st[2])] = true
        end
    end
end
print(string.format("routes: %d, %d steps", #(FO.Routes or {}), nsteps))
print(string.format("%d errors, %d warnings", errs, warns))
os.exit(errs == 0 and 0 or 1)
