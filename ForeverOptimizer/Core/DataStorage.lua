local ADDON, FO = ...
local U = FO.Util

-- ===========================================================================
-- ForeverOptimizerDB = {
--   version = 1,
--   account = { [namespace] = {...} },           -- shared across characters
--   chars   = { [charKey] = { [namespace] = {...} } },
-- }
-- Modules never touch the root; they get a namespace table via FO:Account / FO:Char.
-- ===========================================================================
local DB_VERSION = 3

-- Versioned migrations: FO.migrations[n] upgrades a root at version n-1 to n.
-- Add a new entry whenever a saved layout changes; never edit an old one.
FO.migrations = {
    [2] = function(root)
        -- v2: module enable flags live under account.modules
        root.account.modules = root.account.modules or { disabled = {} }
    end,
    [3] = function(root)
        -- v3: persistent Lua error log (see FO:Error in Init.lua)
        root.account.errors = root.account.errors or { log = {} }
    end,
}

-- ---------------------------------------------------------------------------
-- Error persistence: account.errors.log keeps the last MAX_SAVED_ERRORS
-- distinct errors across sessions, each with where/msg/stack/first/last/count/
-- version/char. Errors raised before storage is ready are flushed on init.
-- ---------------------------------------------------------------------------
local MAX_SAVED_ERRORS = 60

local function SavedLog()
    if not FO.root then return nil end
    FO.root.account.errors = FO.root.account.errors or { log = {} }
    return FO.root.account.errors.log
end

function FO:PersistError(e)
    local log = SavedLog()
    if not log then return end
    local rec
    for i = #log, 1, -1 do
        if log[i].key == e.key then rec = log[i] break end
    end
    if not rec then
        rec = { key = e.key, where = e.where, msg = e.msg, stack = e.stack, first = e.first, count = 0 }
        log[#log + 1] = rec
        while #log > MAX_SAVED_ERRORS do table.remove(log, 1) end
    end
    rec.last = e.last
    rec.count = (rec.count or 0) + 1
    rec.version = self.VERSION
    rec.char = self.charKey
    if (rec.stack == nil or rec.stack == "") and e.stack and e.stack ~= "" then rec.stack = e.stack end
end

function FO:FlushErrors()
    for _, e in ipairs(self.errors) do
        if not e.persisted then
            -- replay the session count so early errors land with the right total
            for _ = 1, e.count do self:PersistError(e) end
            e.persisted = true
        end
    end
end

function FO:InitStorage()
    if type(ForeverOptimizerDB) ~= "table" then ForeverOptimizerDB = {} end
    local db = ForeverOptimizerDB
    db.account = db.account or {}
    db.chars = db.chars or {}
    db.version = db.version or 1
    while db.version < DB_VERSION do
        local nextV = db.version + 1
        local fn = self.migrations[nextV]
        if fn then
            local ok, err = pcall(fn, db)
            if not ok then self:Print("Core", "|cffff6060migration to v%d failed:|r %s", nextV, tostring(err)) break end
        end
        db.version = nextV
        db.migratedAt = time()
    end
    self.charKey = U.CharKey()
    db.chars[self.charKey] = db.chars[self.charKey] or {}
    self.root = db
    self:FlushErrors()
end

-- Rough size of a saved table: nodes and string bytes (what SavedVariables growth looks like)
local function Measure(t, acc)
    acc = acc or { nodes = 0, bytes = 0 }
    for k, v in pairs(t) do
        acc.nodes = acc.nodes + 1
        if type(k) == "string" then acc.bytes = acc.bytes + #k + 6 else acc.bytes = acc.bytes + 8 end
        if type(v) == "table" then Measure(v, acc)
        elseif type(v) == "string" then acc.bytes = acc.bytes + #v + 4
        else acc.bytes = acc.bytes + 8 end
    end
    return acc
end
FO.MeasureTable = Measure

FO:RegisterCommand("errors", function(arg)
    local log = SavedLog() or {}
    local sub = U.SplitCmd(arg or "")
    if sub == "clear" then
        for i = #log, 1, -1 do log[i] = nil end
        FO.errors, FO.errorIndex = {}, {}
        FO:Print("Core", "error log cleared.")
        return
    end
    local idx = tonumber(sub)
    if idx then
        local e = log[#log - idx + 1]
        if not e then FO:Print("Core", "no error #%d", idx) return end
        FO:Print("Core", "#%d %s x%d (v%s, %s)", idx, e.where, e.count, tostring(e.version), tostring(e.char))
        FO:Print("Core", "  %s", e.msg)
        for line in tostring(e.stack or ""):gmatch("[^\n]+") do FO:Print("Core", "    %s", line) end
        return
    end
    if #log == 0 then FO:Print("Core", "no Lua errors recorded. (/fo errors <n> for a stack, /fo errors clear)") return end
    local now = time()
    FO:Print("Core", "%d distinct errors saved (newest first; /fo errors <n> for the stack):", #log)
    for i = #log, math.max(1, #log - 9), -1 do
        local e = log[i]
        FO:Print("Core", "  #%d %s x%d, last %s ago: %s", #log - i + 1, U.Trunc(e.where, 28), e.count, U.FormatDuration(now - (e.last or now)), U.Trunc(e.msg, 70))
    end
end, "Saved Lua errors: list, <n> for stack, clear")

FO:RegisterCommand("dbstats", function()
    local rows = {}
    for ns, t in pairs(FO.root.account) do local m = Measure(t) rows[#rows + 1] = { name = "account." .. ns, nodes = m.nodes, bytes = m.bytes } end
    for ck, c in pairs(FO.root.chars) do
        for ns, t in pairs(c) do local m = Measure(t) rows[#rows + 1] = { name = ck .. "." .. ns, nodes = m.nodes, bytes = m.bytes } end
    end
    table.sort(rows, function(a, b) return a.bytes > b.bytes end)
    local total = 0
    for _, r in ipairs(rows) do total = total + r.bytes end
    FO:Print("Core", "SavedVariables v%d, ~%.0f KB across %d namespaces:", FO.root.version, total / 1024, #rows)
    for i = 1, math.min(12, #rows) do FO:Print("Core", "  %-36s %6.0f KB  %d nodes", U.Trunc(rows[i].name, 36), rows[i].bytes / 1024, rows[i].nodes) end
end, "SavedVariables size by namespace")

function FO:Account(ns, defaults)
    local t = self.root.account[ns]
    if not t then t = {} self.root.account[ns] = t end
    return U.DeepDefaults(t, defaults)
end

function FO:Char(ns, defaults, charKey)
    local chars = self.root.chars
    local key = charKey or self.charKey
    chars[key] = chars[key] or {}
    local t = chars[key][ns]
    if not t then t = {} chars[key][ns] = t end
    return U.DeepDefaults(t, defaults)
end

-- Iterate every character's namespace: for key, data in FO:EachChar("inventory") do
function FO:EachChar(ns)
    local chars = self.root.chars
    local keys = U.Keys(chars)
    table.sort(keys)
    local i = 0
    return function()
        while true do
            i = i + 1
            local k = keys[i]
            if not k then return nil end
            if chars[k][ns] then return k, chars[k][ns] end
        end
    end
end

function FO:WipeNamespace(ns, perChar)
    if perChar then
        for k in pairs(self.root.chars) do self.root.chars[k][ns] = nil end
    else
        self.root.account[ns] = nil
    end
end

FO:RegisterCommand("wipe", function(arg)
    local sub, confirm = U.SplitCmd(arg)
    if confirm ~= "confirm" then
        FO:Print("Core", "usage: /fo wipe <namespace|all> confirm   — namespaces: %s", table.concat(U.Keys(FO.root.account), ", "))
        return
    end
    if sub == "all" then
        for k in pairs(FO.root.account) do FO.root.account[k] = nil end
        for k in pairs(FO.root.chars) do FO.root.chars[k] = {} end
        FO:Print("Core", "all saved data wiped. /reload to re-init cleanly.")
    else
        FO:WipeNamespace(sub, false)
        FO:WipeNamespace(sub, true)
        FO:Print("Core", "namespace '%s' wiped. /reload recommended.", sub)
    end
end, "<namespace|all> confirm — delete saved data")
