local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Dashboard")

-- ===========================================================================
-- The HUD. One movable frame, tabs across the top, a handful of lines per
-- tab. Tabs register themselves: FO.Dashboard:RegisterTab(name, order, fn)
-- where fn returns a list of strings.
-- ===========================================================================
local D = FO:NewModule("Dashboard.Overview", {
    account = "dashboard",
    defaults = { shown = true, tab = "Overview", scale = 1.0, locked = false, point = nil, width = 320 },
})
FO.Dashboard = D

local tabs, tabOrder = {}, {}
function D:RegisterTab(name, order, fn)
    tabs[name] = { fn = fn, order = order }
    tabOrder[#tabOrder + 1] = name
    table.sort(tabOrder, function(a, b) return tabs[a].order < tabs[b].order end)
end

local frame, lines, buttons
local MAX_LINES = 12

local function Render()
    if not frame or not frame:IsShown() then return end
    local tab = tabs[D.db.tab] or tabs.Overview
    local ok, out = pcall(tab.fn)
    if not ok then out = { "|cffff6060" .. tostring(out) .. "|r" } end
    out = out or {}
    for i = 1, MAX_LINES do
        lines[i]:SetText(out[i] or "")
        lines[i]:SetShown(out[i] ~= nil)
    end
    local n = math.min(#out, MAX_LINES)
    frame:SetHeight(30 + n * 15 + 8)
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
end)

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
}
