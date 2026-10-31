-- ForeverOptimizer: one addon, one core, many modules.
-- Load order is the TOC. Core/* first, then feature modules, Classes, Dashboard last.
local ADDON, FO = ...
_G.ForeverOptimizer = FO

FO.NAME = ADDON
FO.VERSION = "0.4.0"
FO.modules = {}        -- ordered list of module defs
FO.moduleIndex = {}    -- name -> def
FO.commands = {}       -- subcommand -> { fn=, help=, module= }
FO.commandOrder = {}

-- ---------------------------------------------------------------------------
-- Module registry
-- A module def may contain:
--   account  = "ns"      account-wide saved namespace -> self.db
--   char     = "ns"      per-character saved namespace -> self.cdb
--   defaults / cdefaults tables merged into those namespaces
--   events   = { EVENT = function(self, ...) end }
--   messages = { FO_MSG = function(self, ...) end }
--   commands = { sub = { fn = function(self, arg) end, help = "..." } }
--   OnInit(self)         after SavedVariables are available
--   OnEnable(self)       at PLAYER_LOGIN
--   OnTick(self, now)    every second (only if defined)
--   OnLogout(self)
-- ---------------------------------------------------------------------------
function FO:NewModule(name, def)
    assert(not self.moduleIndex[name], "duplicate module " .. name)
    def.name = name
    def.FO = self
    table.insert(self.modules, def)
    self.moduleIndex[name] = def
    return def
end

function FO:GetModule(name)
    return self.moduleIndex[name]
end

function FO:RegisterCommand(sub, fn, help, module)
    sub = sub:lower()
    if not self.commands[sub] then table.insert(self.commandOrder, sub) end
    self.commands[sub] = { fn = fn, help = help or "", module = module }
end

-- Chat output. Colored prefix per module area.
local COLORS = {
    Core = "4ce57f", Quest = "e6cc4c", Economy = "ffb333", Grinding = "66b3ff",
    Character = "99ffcc", Classes = "ff99e6", Dashboard = "cccccc",
}
function FO:Print(area, fmt, ...)
    local color = COLORS[area] or COLORS.Core
    local msg = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff%sFO:%s|r %s", color, area, msg))
end

-- Convenience: module-scoped printer
function FO:Printer(area)
    return function(fmt, ...) FO:Print(area, fmt, ...) end
end

-- Runtime flags set by the core
FO.state = {
    loaded = false,
    enabled = false,
    frames = {      -- which "town" windows are open; used for money attribution
        merchant = false, trainer = false, auction = false, mail = false, bank = false, trade = false, taxi = false,
    },
}
