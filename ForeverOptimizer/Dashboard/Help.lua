local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Dashboard")

-- ===========================================================================
-- In-game manual. A Help tab on the HUD pages through every registered
-- command by area, and a Window button (or /fo manual) opens a scrollable
-- frame with the whole thing: syntax, HUD tabs and their buttons, key binds,
-- the day-one sequence, and every command with its help text. The list is
-- built from FO.commands at display time, so it cannot drift from the code.
-- ===========================================================================
local H = FO:NewModule("Dashboard.Help", {})
FO.Help = H

local AREAS = { "Core", "Dashboard", "Grinding", "Quest", "Economy", "Character", "Classes" }
local LABEL = { Core = "Core", Dashboard = "HUD", Grinding = "Grind", Quest = "Quest", Economy = "Econ", Character = "Char", Classes = "Class" }
local TITLE = { Core = "Setup and session", Dashboard = "HUD and map", Grinding = "Grinding and combat", Quest = "Quests",
                Economy = "Economy", Character = "Character, talents and rotation", Classes = "Class modules" }
local PER_PAGE = 10
H.area, H.page = "Core", 1

-- area -> ordered list of { sub, help }, in registration order (related commands stay together)
function H:Index()
    local by = {}
    for _, sub in ipairs(FO.commandOrder) do
        local c = FO.commands[sub]
        local area = (c.module or "Core"):match("^(%w+)") or "Core"
        if not LABEL[area] then area = "Core" end
        by[area] = by[area] or {}
        by[area][#by[area] + 1] = { sub = sub, help = c.help or "" }
    end
    return by
end

function H:Lines()
    local list = self:Index()[self.area] or {}
    local pages = math.max(1, math.ceil(#list / PER_PAGE))
    if self.page > pages then self.page = pages end
    if self.page < 1 then self.page = 1 end
    local out = { string.format("|cffffd100%s|r  %d commands, page %d/%d   |cffaaaaaa/fo <cmd> [args]|r", TITLE[self.area] or self.area, #list, self.page, pages) }
    for i = (self.page - 1) * PER_PAGE + 1, math.min(#list, self.page * PER_PAGE) do
        local e = list[i]
        out[#out + 1] = string.format("|cffffffff%s|r %s", e.sub, e.help)
    end
    if self.page == pages then out[#out + 1] = "|cffaaaaaaWindow: the full manual. [a|b] pick one, <n> a value.|r" end
    return out
end

function H:Controls()
    local out = {}
    for _, area in ipairs(AREAS) do
        out[#out + 1] = { label = LABEL[area], fn = function() self.area = area self.page = 1 end, active = self.area == area }
    end
    out[#out + 1] = { label = "<", fn = function() self.page = math.max(1, self.page - 1) end }
    out[#out + 1] = { label = ">", fn = function() self.page = self.page + 1 end }
    out[#out + 1] = { label = "Window", fn = function() self:Toggle() end, active = self:IsOpen() }
    return out
end

-- ---------------------------------------------------------------------------
-- The manual window
-- ---------------------------------------------------------------------------
local win

function H:Text()
    local D = FO.Dashboard
    local t = {}
    local function add(fmt, ...) t[#t + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt end
    add("|cffffd100ForeverOptimizer v%s|r", FO.VERSION or "?")
    add("Every command is |cffffffff/fo <command> [arguments]|r (|cffffffff/forever|r works too). In the lists below, |cffffffff[a|b]|r means pick one, |cffffffff<n>|r a number, |cffffffff<item>|r an item link or name. Most commands print to chat; the HUD shows the live version of the same numbers.")
    add("")
    add("|cffffd100HUD|r  Drag to move, |cffffffff/fo lock|r to pin, |cffffffff/fo toggle|r or the key bind to hide. Tabs across the top, buttons under them. Buttons do exactly what the matching command does; |cffffffff/fo hud click <button>|r presses one from a macro.")
    if D and D.TabNames then
        for _, name in ipairs(D:TabNames()) do
            local labels = {}
            for _, c in ipairs(D:ControlsFor(name)) do labels[#labels + 1] = c.label end
            add("  |cffffffff%s|r%s", name, #labels > 0 and ("  buttons: " .. table.concat(labels, ", ")) or "")
        end
    end
    add("")
    add("|cffffd100Key binds|r  Esc > Key Bindings > ForeverOptimizer: Toggle HUD, Next waypoint, Nearby quests.")
    add("")
    add("|cffffd100First hour|r  /fo checklist walks it: /fo verify, /fo errors, /fo combatlog, /fo qdb, open the map, visit a vendor, trainer, the auction house (/fo scan), bank, a profession window. Then /fo build use <n> and /fo rotation.")
    add("")
    local by = self:Index()
    for _, area in ipairs(AREAS) do
        local list = by[area]
        if list and #list > 0 then
            add("|cffffd100%s|r", TITLE[area] or area)
            for _, e in ipairs(list) do add("  |cffffffff/fo %s|r  %s", e.sub, e.help) end
            add("")
        end
    end
    add("|cffaaaaaaData is yours: SavedVariables/ForeverOptimizerDB.lua. Errors: /fo errors. Questions on launch day: /fo verify.|r")
    return table.concat(t, "\n")
end

local function Build()
    win = CreateFrame("Frame", "ForeverOptimizerManual", UIParent, "BackdropTemplate")
    win:SetSize(620, 460)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    if win.SetFrameStrata then win:SetFrameStrata("DIALOG") end
    win:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                      tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", win, "TOP", 0, -18)
    title:SetText("ForeverOptimizer manual")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() win:Hide() end)
    local scroll = CreateFrame("ScrollFrame", "ForeverOptimizerManualScroll", win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", win, "TOPLEFT", 22, -46)
    scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -40, 22)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(540, 10)
    if scroll.SetScrollChild then scroll:SetScrollChild(child) end
    local fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    fs:SetWidth(540)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    if fs.SetSpacing then fs:SetSpacing(2) end
    win.text, win.child = fs, child
    if UISpecialFrames then table.insert(UISpecialFrames, "ForeverOptimizerManual") end
    win:Hide()
end

function H:Refresh()
    if not win then return end
    local text = self:Text()
    win.text:SetText(text)
    local _, n = text:gsub("\n", "")
    local h = (win.text.GetStringHeight and win.text:GetStringHeight()) or (n * 14)
    win.child:SetHeight((h or 0) + 24)
end

function H:IsOpen() return win ~= nil and win:IsShown() end

function H:Open()
    if not win then Build() end
    self:Refresh()
    win:Show()
end

function H:Toggle()
    if self:IsOpen() then win:Hide() else self:Open() end
end

-- Registered at load (this file comes after Overview in the TOC), so the tab button exists when the HUD is built
FO.Dashboard:RegisterTab("Help", 9, function() return H:Lines() end, function() return H:Controls() end)

H.commands = {
    manual = { help = "open or close the in-game manual: every command, HUD tab and button", fn = function(self) self:Toggle() end },
}
