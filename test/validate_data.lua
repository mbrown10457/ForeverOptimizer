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
print(string.format("%d errors, %d warnings", errs, #report - errs))
os.exit(errs == 0 and 0 or 1)
