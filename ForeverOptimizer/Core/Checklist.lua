local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Core")

-- ===========================================================================
-- First-hour checklist: the one-time visits and commands that seed every
-- data layer on a fresh character or client. Items tick themselves off as
-- the matching event or command happens; progress is saved per character.
-- ===========================================================================
local C = FO:NewModule("Core.Checklist", { char = "checklist", cdefaults = { done = {} } })

local ITEMS = {
    { key = "verify",    label = "/fo verify",     hint = "probe the client API; the table is saved for offline review" },
    { key = "errors",    label = "/fo errors",     hint = "confirm the error log is empty after the first minutes" },
    { key = "combatlog", label = "/fo combatlog",  hint = "is the combat log live, refused, or secret?" },
    { key = "qdb",       label = "/fo qdb",        hint = "is QuestieDB connected for quest pins and /fo nearby?" },
    { key = "map",       label = "open the world map", hint = "pins and coordinates render? (/fo map)" },
    { key = "vendor",    label = "visit a vendor", hint = "seeds vendor prices and auto-sells trash" },
    { key = "trainer",   label = "visit your class trainer", hint = "seeds training costs for /fo plan" },
    { key = "ah",        label = "run an AH scan", hint = "open the auction house, then /fo scan" },
    { key = "bank",      label = "open the bank",  hint = "snapshots bank contents for /fo bank" },
    { key = "tradeskill", label = "open a profession window", hint = "captures recipes for /fo craft" },
}

function C:Mark(key)
    if self.disabled or not self.cdb then return end
    if self.cdb.done[key] then return end
    self.cdb.done[key] = time()
    local n, total = self:Progress()
    local label
    for _, it in ipairs(ITEMS) do if it.key == key then label = it.label end end
    print("checklist: %s |cff80ff80done|r (%d/%d)%s", label or key, n, total, n == total and "  all seeded!" or "")
end

function C:Progress()
    local n = 0
    for _, it in ipairs(ITEMS) do if self.cdb.done[it.key] then n = n + 1 end end
    return n, #ITEMS
end

C.messages = {
    FO_COMMAND = function(self, sub)
        if sub == "verify" or sub == "errors" or sub == "combatlog" or sub == "qdb" then self:Mark(sub)
        elseif sub == "scan" then self:Mark("ah") end
    end,
    FO_AH_SCAN = function(self) self:Mark("ah") end,
    FO_MAP_SHOWN = function(self) self:Mark("map") end,
}

C.events = {
    MERCHANT_SHOW = function(self) self:Mark("vendor") end,
    TRAINER_SHOW = function(self) self:Mark("trainer") end,
    BANKFRAME_OPENED = function(self) self:Mark("bank") end,
    TRADE_SKILL_SHOW = function(self) self:Mark("tradeskill") end,
}

function C:OnEnable()
    local n, total = self:Progress()
    if n < total then print("first-hour checklist: %d/%d done. /fo checklist", n, total) end
end

C.commands = {
    checklist = {
        help = "First-hour checklist of visits and commands that seed the data | checklist reset",
        fn = function(self, arg)
            if (U.Str(arg) or "") == "reset" then self.cdb.done = {} print("checklist reset.") return end
            local n, total = self:Progress()
            print("first-hour checklist, %d/%d:", n, total)
            for i, it in ipairs(ITEMS) do
                local t = self.cdb.done[it.key]
                print("  %s %d. %-28s |cffaaaaaa%s|r", t and "|cff80ff80[x]|r" or "|cffff6060[ ]|r", i, it.label, t and ("done " .. U.FormatDuration(time() - t) .. " ago") or it.hint)
            end
        end,
    },
}
