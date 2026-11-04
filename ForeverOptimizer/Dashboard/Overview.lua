local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Dashboard")

-- ===========================================================================
-- The HUD. One movable frame, tabs across the top, a handful of lines per
-- tab. Tabs register themselves: FO.Dashboard:RegisterTab(name, order, fn, controls)
-- where fn returns a list of strings and the optional controls() returns a
-- list of buttons { label, fn, active } drawn in a row under the tabs. label
-- and active may be functions so a button can read "Pause" / "Resume".
-- ===========================================================================
local D = FO:NewModule("Dashboard.Overview", {
    account = "dashboard",
    defaults = { shown = true, tab = "Overview", scale = 1.0, locked = false, point = nil, width = 360 },
})
FO.Dashboard = D

local tabs, tabOrder = {}, {}
function D:RegisterTab(name, order, fn, controls)
    tabs[name] = { fn = fn, order = order, controls = controls }
    tabOrder[#tabOrder + 1] = name
    table.sort(tabOrder, function(a, b) return tabs[a].order < tabs[b].order end)
end

local frame, lines, buttons, controlButtons
local MAX_LINES = 12
local MAX_CONTROLS = 10
local Render

local function Eval(v) if type(v) == "function" then local ok, r = pcall(v) return ok and r or nil end return v end

-- Resolved buttons for a tab: { label = string, fn, active = boolean }
local function ControlList(tab)
    if not (tab and tab.controls) then return {} end
    local ok, list = pcall(tab.controls)
    if not ok or type(list) ~= "table" then return {} end
    local out = {}
    for i, c in ipairs(list) do
        if i > MAX_CONTROLS then break end
        out[#out + 1] = { label = tostring(Eval(c.label) or "?"), fn = c.fn, active = Eval(c.active) and true or false }
    end
    return out
end

local function LayoutControls(tab)
    local list = ControlList(tab)
    local x = 8
    for i = 1, MAX_CONTROLS do
        local b, c = controlButtons[i], list[i]
        if c then
            b.text:SetText(c.label)
            local w = ((b.text.GetStringWidth and b.text:GetStringWidth()) or (#c.label * 6)) + 8
            b:SetSize(w, 14)
            b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -24)
            b.control = c
            if c.active then b.text:SetTextColor(1, 0.82, 0) b:SetBackdropColor(1, 0.82, 0, 0.18) else b.text:SetTextColor(0.78, 0.78, 0.78) b:SetBackdropColor(1, 1, 1, 0.07) end
            b:Show()
            x = x + w + 3
        else
            b.control = nil
            b:Hide()
        end
    end
    return #list > 0
end

Render = function()
    if not frame or not frame:IsShown() then return end
    local tab = tabs[D.db.tab] or tabs.Overview
    local ok, out = pcall(tab.fn)
    if not ok then out = { "|cffff6060" .. tostring(out) .. "|r" } end
    out = out or {}
    local top = LayoutControls(tab) and 42 or 26
    for i = 1, MAX_LINES do
        lines[i]:SetText(out[i] or "")
        lines[i]:SetShown(out[i] ~= nil)
        lines[i]:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -top - (i - 1) * 15)
    end
    local n = math.min(#out, MAX_LINES)
    frame:SetHeight(top + 4 + n * 15 + 8)
    for _, b in ipairs(buttons) do
        if b.tabName == D.db.tab then b.text:SetTextColor(1, 0.82, 0) else b.text:SetTextColor(0.7, 0.7, 0.7) end
    end
end

function D:SelectTab(name)
    if not tabs[name] then
        for _, t in ipairs(tabOrder) do if t:lower() == tostring(name):lower() then name = t break end end
    end
    if tabs[name] then self.db.tab = name Render() end
end

-- Buttons of the current tab (resolved), for /fo hud and the harness
function D:Controls() return ControlList(tabs[self.db.tab] or tabs.Overview) end
function D:ControlsFor(name) return ControlList(tabs[name]) end
function D:TabNames() local t = {} for _, n in ipairs(tabOrder) do t[#t + 1] = n end return t end

-- Press a button of the current tab by label (case-insensitive)
function D:ClickControl(label)
    label = tostring(label or ""):lower()
    for _, c in ipairs(self:Controls()) do
        if c.label:lower() == label then
            FO.Try("HUD " .. c.label, c.fn)
            Render()
            return true
        end
    end
    return false
end

local function Build()
    frame = CreateFrame("Frame", "ForeverOptimizerHUD", UIParent, "BackdropTemplate")
    frame:SetSize(D.db.width, 120)
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0, 0, 0, 0.65)
    frame:SetScale(D.db.scale)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if not D.db.locked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        D.db.point = { p, rp, x, y }
    end)
    frame:SetClampedToScreen(true)
    local pt = D.db.point
    if pt then frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200) end

    buttons = {}
    local x = 8
    local step = math.max(44, math.floor((D.db.width - 16) / math.max(1, #tabOrder)))
    for _, name in ipairs(tabOrder) do
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(step - 4, 16)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -6)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
        b.text:SetText(name)
        b.tabName = name
        b:SetScript("OnClick", function() D:SelectTab(name) end)
        buttons[#buttons + 1] = b
        x = x + step
    end

    controlButtons = {}
    for i = 1, MAX_CONTROLS do
        local b = CreateFrame("Button", nil, frame, "BackdropTemplate")
        b:SetSize(40, 14)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        b:SetBackdropColor(1, 1, 1, 0.07)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
        b:SetScript("OnClick", function(self) if self.control then FO.Try("HUD " .. self.control.label, self.control.fn) Render() end end)
        b:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
        b:SetScript("OnLeave", function(self) Render() end)
        b:Hide()
        controlButtons[i] = b
    end

    lines = {}
    for i = 1, MAX_LINES do
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -26 - (i - 1) * 15)
        fs:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        lines[i] = fs
    end
    if D.db.shown == false then frame:Hide() end
end

-- Overview tab: the one-glance summary
-- Buttons map onto existing commands so the HUD and the command line stay in step.
local function Cmd(s) return function() SlashCmdList.FOREVEROPTIMIZER(s) end end
D.Cmd = Cmd

local function OverviewControls()
    local st = FO.Session:Stats()
    local al = FO.Alerts and FO.Alerts.db and FO.Alerts.db.settings
    return {
        { label = (st and st.paused) and "Resume" or "Pause", fn = Cmd("session pause"), active = st and st.paused },
        { label = "Reset", fn = Cmd("session reset") },
        { label = D.db.locked and "Unlock" or "Lock", fn = Cmd("lock"), active = D.db.locked },
        { label = "Sound", fn = Cmd("alerts sound"), active = al and al.sound },
        { label = "Flash", fn = Cmd("alerts flash"), active = al and al.flash ~= false },
    }
end

D:RegisterTab("Overview", 1, function()
    local st = FO.Session:Stats()
    if not st then return { "no session" } end
    local xp, xpMax = U.Num(UnitXP("player")), U.Num(UnitXPMax("player"))
    local actColor = ({ quest = "ffd100", grind = "80c0ff", dungeon = "ff8040", travel = "c0c0c0", rest = "80ff80", town = "c0a0ff", dead = "ff6060", idle = "888888" })[st.activity] or "ffffff"
    local out = {
        string.format("%s  %s  %s%s", U.Color(actColor, st.activity), U.FormatDuration(st.elapsed), U.Trunc(st.zone, 18), st.paused and " |cffff6060(paused)|r" or ""),
        string.format("XP %d  |cffaaaaaa%s/hr|r  TTL %s", st.xp, U.Rate(st.xph), U.FormatDuration(st.ttl)),
        string.format("Kills %d  |cffaaaaaa%s/hr|r  deaths %d", st.kills, U.Rate(st.kph), st.deaths),
        string.format("Net %s  |cffaaaaaa%s/hr|r", U.ShortMoney(st.gold), st.gph and U.ShortMoney(st.gph) or "--"),
        string.format("Eff %s  |cffaaaaaa%s/hr|r  (bags %s)", U.ShortMoney(st.effective), st.egph and U.ShortMoney(st.egph) or "--", U.ShortMoney(st.ahEst)),
        string.format("Downtime %.0f%%  rest %s  travel %s", st.downtimePct, U.FormatDuration(st.by.rest.t), U.FormatDuration(st.by.travel.t)),
    }
    local _, px, py = U.PlayerPosition()
    if px and py then out[#out + 1] = string.format("|cffaaaaaaPos|r %.1f, %.1f", px * 100, py * 100) end
    if st.dungeon then out[#out + 1] = string.format("|cffff8040%s|r %s  %d xp  %s", U.Trunc(st.dungeon.name, 16), U.FormatDuration(st.dungeon.seconds), st.dungeon.xp, U.ShortMoney(st.dungeon.gold + st.dungeon.ahEst + st.dungeon.vendorEst)) end
    return out
end, OverviewControls)

-- The class module (Hunter, Warlock, Priest) gets its own tab so its lines
-- never push the Overview past the 12-line cap once the combat log fills in.
local function RegisterClassTab()
    local cls = FO.Classes and FO.Classes[FO.Player.class]
    if not (cls and cls.Lines) then return end
    local label = tostring(FO.Player.class or "Class")
    label = label:sub(1, 1):upper() .. label:sub(2):lower()
    if not tabs[label] then D:RegisterTab(label, 1.5, function() return cls:Lines() end) end
end

function D:OnEnable()
    RegisterClassTab()
    Build()
    C_Timer.NewTicker(1, Render)
    Render()
end

-- Key bindings (Bindings.xml)
BINDING_HEADER_FOREVEROPTIMIZER = "ForeverOptimizer"
BINDING_NAME_FOREVEROPTIMIZER_TOGGLE = "Toggle HUD"
BINDING_NAME_FOREVEROPTIMIZER_NEXT = "Waypoint to next quest target"
BINDING_NAME_FOREVEROPTIMIZER_NEARBY = "List quests to pick up nearby"
BINDING_NAME_FOREVEROPTIMIZER_REVEAL = "Toggle unexplored map art"
function ForeverOptimizer_ToggleHUD() SlashCmdList.FOREVEROPTIMIZER("toggle") end
function ForeverOptimizer_NextWaypoint() SlashCmdList.FOREVEROPTIMIZER("next") end
function ForeverOptimizer_Nearby() SlashCmdList.FOREVEROPTIMIZER("nearby") end

D.commands = {
    show = { help = "show HUD", fn = function(self) self.db.shown = true frame:Show() Render() end },
    hide = { help = "hide HUD", fn = function(self) self.db.shown = false frame:Hide() end },
    toggle = { help = "toggle HUD", fn = function(self) if frame:IsShown() then self.db.shown = false frame:Hide() else self.db.shown = true frame:Show() Render() end end },
    tab = { help = "<Overview|Leveling|Economy|Character>", fn = function(self, arg) self:SelectTab(arg) end },
    scale = { help = "<0.5-2>", fn = function(self, arg) local s = tonumber(arg) if s and s >= 0.5 and s <= 2 then self.db.scale = s frame:SetScale(s) end end },
    lock = { help = "toggle HUD drag lock", fn = function(self) self.db.locked = not self.db.locked print("HUD %s", self.db.locked and "locked" or "unlocked") end },
    hud = { help = "list | click <button> — the buttons on the current HUD tab (for macros and key binds)", fn = function(self, arg)
        local sub, rest = U.SplitCmd(arg or "")
        if sub == "click" then
            if not self:ClickControl(rest) then print("no button '%s' on the %s tab; /fo hud list", rest, self.db.tab) end
            return
        end
        local parts = {}
        for _, c in ipairs(self:Controls()) do parts[#parts + 1] = (c.active and "|cffffd100[" or "[") .. c.label .. (c.active and "]|r" or "]") end
        print("%s tab buttons: %s", self.db.tab, #parts > 0 and table.concat(parts, " ") or "none")
    end },
}
