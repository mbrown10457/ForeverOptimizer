local ADDON, FO = ...
local U = FO.Util

-- ===========================================================================
-- One frame, one dispatcher. Game events fan out to every module that asked
-- for them; internal messages (FO_*) connect modules without hard references.
-- Events that the client refuses (combat log on 12.x) fail quietly per event.
-- ===========================================================================
local frame = CreateFrame("Frame")
local eventHandlers = {}   -- event -> { fn, ... }
local messageHandlers = {} -- msg -> { fn, ... }
local registered = {}      -- event -> true if RegisterEvent succeeded

function FO:RegisterEvent(event, fn)
    if not eventHandlers[event] then
        eventHandlers[event] = {}
        local ok = pcall(frame.RegisterEvent, frame, event)
        registered[event] = ok
        if not ok then FO.Print(FO, "Core", "event %s refused by client; feature degraded.", event) end
    end
    table.insert(eventHandlers[event], fn)
end

function FO:On(msg, fn)
    messageHandlers[msg] = messageHandlers[msg] or {}
    table.insert(messageHandlers[msg], fn)
end

function FO:Fire(msg, ...)
    local list = messageHandlers[msg]
    if not list then return end
    for _, fn in ipairs(list) do
        FO.Try(msg .. " handler", fn, ...)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        FO.Try(event, fn, ...)
    end
end)

-- ---------------------------------------------------------------------------
-- Town-frame tracking (used for money attribution and activity detection)
-- ---------------------------------------------------------------------------
local F = FO.state.frames
local frameEvents = {
    MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
    TRAINER_SHOW = { "trainer", true }, TRAINER_CLOSED = { "trainer", false },
    AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction", false },
    MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
    BANKFRAME_OPENED = { "bank", true }, BANKFRAME_CLOSED = { "bank", false },
    TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
    TAXIMAP_OPENED = { "taxi", true }, TAXIMAP_CLOSED = { "taxi", false },
    TRADE_SKILL_SHOW = { "tradeskill", true }, TRADE_SKILL_CLOSE = { "tradeskill", false },
}
for ev, spec in pairs(frameEvents) do
    FO:RegisterEvent(ev, function() F[spec[1]] = spec[2]; FO:Fire("FO_FRAME", spec[1], spec[2]) end)
end
function FO:AnyTownFrame()
    return F.merchant or F.trainer or F.auction or F.mail or F.bank or F.trade or F.taxi or F.tradeskill
end

-- ---------------------------------------------------------------------------
-- Module lifecycle
-- ---------------------------------------------------------------------------
-- Core.* and the dashboard shell can't be disabled; everything else can, via /fo module.
function FO:ModuleDisabled(name)
    if name:match("^Core%.") or name == "Dashboard.Overview" then return false end
    local flags = self.root.account.modules
    return flags and flags.disabled and flags.disabled[name] == true or false
end

local function WireModule(m)
    if FO:ModuleDisabled(m.name) then m.disabled = true return end
    if m.account then m.db = FO:Account(m.account, m.defaults) end
    if m.char then m.cdb = FO:Char(m.char, m.cdefaults) end
    if m.OnInit then
        FO.Try(m.name .. " OnInit", m.OnInit, m)
    end
    for ev, fn in pairs(m.events or {}) do
        FO:RegisterEvent(ev, function(...) return fn(m, ...) end)
    end
    for msg, fn in pairs(m.messages or {}) do
        FO:On(msg, function(...) return fn(m, ...) end)
    end
    for sub, spec in pairs(m.commands or {}) do
        FO:RegisterCommand(sub, function(arg) return spec.fn(m, arg) end, spec.help, m.name)
    end
end

local tickers = {}
FO:RegisterEvent("ADDON_LOADED", function(name)
    if name ~= ADDON or FO.state.loaded then return end
    FO.state.loaded = true
    FO:InitStorage()
    for _, m in ipairs(FO.modules) do WireModule(m) end
    FO:Fire("FO_INIT")
end)

FO:RegisterEvent("PLAYER_LOGIN", function()
    if not FO.state.loaded then
        FO.state.loaded = true
        FO:InitStorage()
        for _, m in ipairs(FO.modules) do WireModule(m) end
    end
    FO.state.enabled = true
    local disabled = 0
    for _, m in ipairs(FO.modules) do
        if m.disabled then disabled = disabled + 1
        else
            if m.OnEnable then
                FO.Try(m.name .. " OnEnable", m.OnEnable, m)
            end
            if m.OnTick then tickers[#tickers + 1] = m end
        end
    end
    FO.state.disabledCount = disabled
    C_Timer.NewTicker(1, function()
        local now = GetTime()
        for _, m in ipairs(tickers) do
            FO.Try(m.name .. " OnTick", m.OnTick, m, now)
        end
    end)
    FO:Fire("FO_ENABLE")
    FO:Print("Core", "v%s loaded, %d modules%s. /fo for commands.", FO.VERSION, #FO.modules - disabled, disabled > 0 and (" (" .. disabled .. " disabled)") or "")
end)

FO:RegisterEvent("PLAYER_LOGOUT", function()
    for _, m in ipairs(FO.modules) do
        if m.OnLogout then FO.Try(m.name .. " OnLogout", m.OnLogout, m) end
    end
end)

-- ---------------------------------------------------------------------------
-- Slash commands: /fo <sub> <args>
-- ---------------------------------------------------------------------------
SLASH_FOREVEROPTIMIZER1 = "/fo"
SLASH_FOREVEROPTIMIZER2 = "/forever"
SlashCmdList.FOREVEROPTIMIZER = function(msg)
    local sub, arg = U.SplitCmd(msg)
    if sub == "" then sub = "help" end
    local c = FO.commands[sub]
    if not c then
        FO:Print("Core", "unknown command '%s'. /fo help", sub)
        return
    end
    FO.Try("/fo " .. sub, c.fn, arg)
end

FO:RegisterCommand("module", function(arg)
    local sub, name = U.SplitCmd(arg)
    local flags = FO.root.account.modules
    flags.disabled = flags.disabled or {}
    if sub == "on" or sub == "off" then
        local m
        for _, def in ipairs(FO.modules) do if def.name:lower() == name:lower() or def.name:lower():match("%." .. name:lower() .. "$") then m = def end end
        if not m then FO:Print("Core", "no module '%s'", name) return end
        if sub == "off" and not m.name:match("^Core%.") and m.name ~= "Dashboard.Overview" then flags.disabled[m.name] = true
        elseif sub == "off" then FO:Print("Core", "%s can't be disabled.", m.name) return
        else flags.disabled[m.name] = nil end
        FO:Print("Core", "%s %s. Takes effect after /reload.", m.name, sub == "off" and "disabled" or "enabled")
        return
    end
    FO:Print("Core", "modules (/fo module on|off <name>, applies on /reload):")
    for _, def in ipairs(FO.modules) do
        FO:Print("Core", "  %s %s", (flags.disabled[def.name] or def.disabled) and "|cffff6060off|r" or "|cff60ff60on |r", def.name)
    end
end, "list | on <name> | off <name> — enable/disable modules")

FO:RegisterCommand("help", function(arg)
    FO:Print("Core", "commands:")
    local byModule = {}
    for _, sub in ipairs(FO.commandOrder) do
        local c = FO.commands[sub]
        local area = (c.module or "Core"):match("^(%w+)") or "Core"
        byModule[area] = byModule[area] or {}
        table.insert(byModule[area], string.format("|cffffffff%s|r %s", sub, c.help))
    end
    for _, area in ipairs({ "Core", "Dashboard", "Grinding", "Quest", "Economy", "Character", "Classes" }) do
        if byModule[area] then
            for _, line in ipairs(byModule[area]) do FO:Print(area, "  /fo %s", line) end
        end
    end
end, "this list")
