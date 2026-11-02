-- ForeverOptimizer: one addon, one core, many modules.
-- Load order is the TOC. Core/* first, then feature modules, Classes, Dashboard last.
local ADDON, FO = ...
_G.ForeverOptimizer = FO

FO.NAME = ADDON
FO.VERSION = "0.9.5"
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

-- ---------------------------------------------------------------------------
-- Error capture. Every protected call in the core routes failures here, so a
-- Lua error is printed (first few times) and kept in FO.errors with a stack.
-- DataStorage mirrors FO.errors into account.errors.log so it survives
-- /reload and can be read straight from the SavedVariables file.
-- ---------------------------------------------------------------------------
FO.errors = {}            -- session list of { key, where, msg, stack, first, last, count }
FO.errorIndex = {}        -- key -> entry
local ERROR_PRINT_LIMIT = 3
local MAX_SESSION_ERRORS = 50

local function Stack()
    if debugstack then return debugstack(4, 12, 0) end
    if debug and debug.traceback then return debug.traceback("", 3) end
    return ""
end

function FO:Error(where, msg, stack)
    msg = tostring(msg)
    local firstLine = msg:match("^[^\n]*") or msg
    local key = where .. "|" .. firstLine
    local e = self.errorIndex[key]
    local now = time()
    if e then
        e.count = e.count + 1
        e.last = now
    else
        e = { key = key, where = where, msg = firstLine, stack = stack or "", first = now, last = now, count = 1, version = self.VERSION }
        self.errorIndex[key] = e
        self.errors[#self.errors + 1] = e
        if #self.errors > MAX_SESSION_ERRORS then
            local old = table.remove(self.errors, 1)
            self.errorIndex[old.key] = nil
        end
    end
    if e.count <= ERROR_PRINT_LIMIT then
        self:Print("Core", "|cffff6060error in %s:|r %s", where, firstLine)
        if e.count == ERROR_PRINT_LIMIT then self:Print("Core", "(further repeats of this error are silent; /fo errors)") end
    end
    if self.PersistError then self:PersistError(e) end
    return e
end

-- Protected call with stack capture. Returns ok, result...
local function Handler(err) return { err = err, stack = Stack() } end
function FO.Try(where, fn, ...)
    local n, args = select("#", ...), { ... }
    local ok, res = xpcall(function() return fn(unpack(args, 1, n)) end, Handler)
    if not ok then
        FO:Error(where, res.err, res.stack)
        return false
    end
    return true, res
end

-- Runtime flags set by the core
FO.state = {
    loaded = false,
    enabled = false,
    frames = {      -- which "town" windows are open; used for money attribution
        merchant = false, trainer = false, auction = false, mail = false, bank = false, trade = false, taxi = false,
    },
}
