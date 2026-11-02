package.path = "./test/?.lua;" .. package.path
local S = require("wowstub")
local orig = S.loadAddon
local FO
S.loadAddon = function(dir) local ns, order = orig(dir) FO = ns return ns, order end
arg = {}
os.exit = function() end
local realprint = print
print = function() end          -- silence harness checks
dofile("test/run.lua")
print = realprint
local D = FO.Dashboard
local tabs
for i = 1, 20 do local n, v = debug.getupvalue(D.SelectTab, i) if n == "tabs" then tabs = v end end
local names = {}
for n, t in pairs(tabs) do names[#names + 1] = n end
table.sort(names, function(a, b) return tabs[a].order < tabs[b].order end)
print("##TABS " .. table.concat(names, "|"))
for _, n in ipairs(names) do
    local ok, out = pcall(tabs[n].fn)
    print("##TAB " .. n)
    for _, l in ipairs(ok and out or { tostring(out) }) do print(l) end
    D:SelectTab(n)
    local parts = {}
    for _, c in ipairs(D:Controls()) do parts[#parts + 1] = (c.active and "*" or "") .. c.label end
    print("##CTRL " .. table.concat(parts, "|"))
end
D:SelectTab("Overview")
SlashCmdList.FOREVEROPTIMIZER("build use 1")
FO.Player.level = 12
local cmds = { "verify", "checklist", "hunter", "rotation", "build", "combatlog", "qdb", "nearby", "route", "combat", "autoshot", "alerts", "map", "note first session", "errors", "mob 595", "eta 30", "dps session", "hps session", "meter", "help", "manual" }
for _, c in ipairs(cmds) do
    S.out = {}
    SlashCmdList.FOREVEROPTIMIZER(c)
    print("##CMD /fo " .. c)
    for _, l in ipairs(S.out) do print(l) end
end
