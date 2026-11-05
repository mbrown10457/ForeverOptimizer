local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Quest")

-- ===========================================================================
-- Step-by-step leveling guide. Routes live in Data\Routes.lua (generated from
-- scripts/routes/*.txt with QuestieDB names and coordinates baked in). Each
-- step is accept / complete / turn in a quest, go somewhere, set the hearth,
-- train, reach a level or a note. Quest steps complete themselves from the
-- quest log; travel steps complete when the arrow arrives; the rest are a
-- click. The direction arrow always points at the current step.
-- ===========================================================================
local G = FO:NewModule("Quest.Guide", {
    account = "guide",
    defaults = { chars = {}, shown = true, point = nil, locked = false, arrow = true, width = 330 },
})
FO.Guide = G

G.route, G.index, G.current = nil, 1, nil
local frame, widgets
local lastArrowKey

local KIND_WORD = { A = "Accept", C = "Do", T = "Turn in", GOTO = "Go to", HEARTH = "Set hearth", TRAIN = "Train", LEVEL = "Level", NOTE = "Note" }

-- ---------------------------------------------------------------------------
-- Per-character progress: { route = key, pos = index, done = { [index] = true } }
-- ---------------------------------------------------------------------------
function G:State()
    local key = FO.charKey or "?"
    local s = self.db.chars[key]
    if not s then s = { route = nil, pos = 1, done = {} } self.db.chars[key] = s end
    return s
end

-- Does this step apply to this character? class = "HUNTER,WARLOCK" or "-WARLOCK"; race = "Orc,Troll".
local function ClassOK(step)
    local c, r = step.class, step.race
    if r then
        local me, ok = FO.Player.race or "", false
        for tok in r:gmatch("[^,]+") do if tok == me then ok = true end end
        if not ok then return false end
    end
    if not c then return true end
    local me = FO.Player.class or ""
    if c:sub(1, 1) == "-" then return not c:sub(2):find(me, 1, true) end
    return c:find(me, 1, true) ~= nil
end

function G:Routes() return FO.Routes or {} end

function G:FindRoute(what)
    local routes = self:Routes()
    local n = tonumber(what)
    if n and routes[n] then return routes[n] end
    for _, r in ipairs(routes) do if r.key == what or r.name == what then return r end end
    for _, r in ipairs(routes) do if what and r.name:lower():find(what:lower(), 1, true) then return r end end
end

-- The first route for this character's faction and race whose level band fits.
function G:PickRoute()
    local P = FO.Player
    local level = U.Num(UnitLevel and UnitLevel("player")) or P.level or 1
    for _, r in ipairs(self:Routes()) do
        local raceOK = not r.races or (P.race and r.races[P.race])
        local factionOK = not r.faction or r.faction == P.faction or P.faction == "?"
        if raceOK and factionOK and level <= (r.levels and r.levels[2] or 60) then return r end
    end
end

-- ---------------------------------------------------------------------------
-- Step state
-- ---------------------------------------------------------------------------
local function LogSet()
    local QT = FO:GetModule("Quest.QuestTracker")
    local set = {}
    if QT and C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        for _, e in ipairs(QT:LogQuestIDs()) do set[e.id] = e end
    end
    return set
end

local function Flagged(qid)
    return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(qid) == true
end

local function ObjectivesDone(qid)
    if C_QuestLog.IsComplete and C_QuestLog.IsComplete(qid) == true then return true end
    local QT = FO:GetModule("Quest.QuestTracker")
    local objs = QT and QT.ReadObjectives(qid)
    if not objs or #objs == 0 then return false end
    for _, o in ipairs(objs) do if not o.finished then return false end end
    return true
end

local function Level() return U.Num(UnitLevel and UnitLevel("player")) or FO.Player.level or 1 end

function G:IsDone(i, step, log)
    local st = self:State()
    if st.done[i] then return true end
    local k, q = step[1], step[2]
    if k == "A" then return log[q] ~= nil or Flagged(q)
    elseif k == "C" then return Flagged(q) or (log[q] ~= nil and ObjectivesDone(q))
    elseif k == "T" then return Flagged(q)
    elseif k == "LEVEL" then return Level() >= q
    elseif k == "TRAIN" then return (st.trainedAt or 0) >= q and st.trainedStep == i
    elseif k == "HEARTH" then
        local bind = U.Str(GetBindLocation and GetBindLocation())
        return bind ~= nil and step[3] ~= nil and bind:lower():find(step[3]:lower(), 1, true) ~= nil
    end
    return false
end

-- Why a step cannot be done yet (shown, never auto-skipped)
function G:Blocker(step, log)
    local k, q = step[1], step[2]
    if k == "A" and step.req and Level() < step.req then return string.format("needs level %d", step.req) end
    if (k == "C" or k == "T") and not log[q] and not Flagged(q) then return "not in your log" end
    if k == "TRAIN" and Level() < q then return string.format("at level %d", q) end
    return nil
end

-- Walk forward from the saved position to the first step that is neither done nor filtered.
function G:Refresh(reason)
    local r = self.route
    if not r then self.current = nil self:Render() return end
    local st = self:State()
    local log = LogSet()
    local i = st.pos or 1
    local n = #r.steps
    while i <= n do
        local step = r.steps[i]
        if ClassOK(step) and not self:IsDone(i, step, log) then break end
        i = i + 1
    end
    local changed = (i ~= self.index)
    self.index = i
    st.pos = math.min(i, n + 1)
    self.current = r.steps[i]
    self.log = log
    if changed or reason == "arrow" then self:PointArrow(reason == "arrow") end
    self:Render()
    if changed and self.current and reason ~= "init" then
        print("step %d/%d: %s", i, n, self:StepText(self.current, true))
    end
end

-- ---------------------------------------------------------------------------
-- Where a step is: live data first (recorded points, QuestieDB on this map), then the baked coordinates.
-- Returns mapID, x, y (0-1), label
-- ---------------------------------------------------------------------------
function G:Location(step)
    local k, q = step[1], step[2]
    local QDB, RP = FO.QuestDB, FO:GetModule("Quest.QuestRoutePlanner")
    local pmap, px, py = U.PlayerPosition()
    if k == "A" and QDB and QDB.available and pmap and QDB.Starters then
        local s = QDB:NearestStarter(q, pmap, px, py)
        if s then return s.mapID, s.x, s.y, s.label end
    elseif k == "C" and RP and self.log and self.log[q] then
        local m, x, y = RP:NextWaypoint(q)
        if m and x then return m, x, y, step[3] end
    elseif k == "T" and QDB and QDB.available and pmap then
        local f = QDB:NearestFinisher(q, pmap, px, py)
        if f then return f.mapID, f.x, f.y, f.label end
    end
    if step[5] and step[6] then return step[5], step[6] / 100, step[7] / 100, (step[4] ~= "" and step[4]) or step[3] end
    return nil
end

function G:PointArrow(force)
    local A = FO.Arrow
    if not (A and self.db.arrow) then return end
    local step, i = self.current, self.index
    if not step then if lastArrowKey then A:Clear() lastArrowKey = nil end return end
    local m, x, y, label = self:Location(step)
    if not m then if lastArrowKey then A:Clear() lastArrowKey = nil end return end
    local key = string.format("%d:%d:%.4f:%.4f", i, m, x, y)
    if key == lastArrowKey and not force then return end
    lastArrowKey = key
    local word = KIND_WORD[step[1]] or step[1]
    A:Set(m, x, y, word .. ": " .. (label or step[3] or "?"), function()
        if (step[1] == "GOTO" or step[1] == "HEARTH" and false) and self.current == step then
            self:State().done[i] = true
            self:Refresh("arrive")
        end
        lastArrowKey = nil
    end)
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------
function G:StepText(step, plain)
    local k = step[1]
    local gold = plain and "%s" or "|cffffd100%s|r"
    local who = step[4] ~= "" and step[4] or nil
    local coords = step[6] and string.format(" (%.1f, %.1f)", step[6], step[7]) or ""
    if k == "A" then return string.format("Accept " .. gold .. "%s%s", step[3], who and (" from " .. who) or "", coords)
    elseif k == "C" then return string.format("Do " .. gold, step[3])
    elseif k == "T" then return string.format("Turn in " .. gold .. "%s%s", step[3], who and (" to " .. who) or "", coords)
    elseif k == "GOTO" then return string.format("Go to " .. gold .. "%s", step[3], coords)
    elseif k == "HEARTH" then return string.format("Set hearth at " .. gold .. "%s", step[3], coords)
    elseif k == "TRAIN" then return string.format("Train at level %d%s%s", step[2], who and (": " .. who) or "", coords)
    elseif k == "LEVEL" then return string.format("Reach level %d (now %d)", step[2], Level())
    end
    return step[3] or "?"
end

function G:Progress(step)
    if step[1] ~= "C" then return nil end
    local QT = FO:GetModule("Quest.QuestTracker")
    local objs = QT and QT.ReadObjectives(step[2])
    if not objs or #objs == 0 then return nil end
    local parts = {}
    for _, o in ipairs(objs) do
        if o.finished then parts[#parts + 1] = "|cff80ff80" .. U.Trunc(o.text or "?", 30) .. "|r"
        elseif o.req > 0 then parts[#parts + 1] = string.format("%d/%d %s", o.num, o.req, U.Trunc((o.text or "?"):gsub("^%d+/%d+%s*", ""), 26))
        else parts[#parts + 1] = U.Trunc(o.text or "?", 30) end
    end
    return table.concat(parts, ", ")
end

-- Lines for the HUD tab and /fo guide
function G:Lines()
    local r = self.route
    if not r then return { "No route for this character. /fo guide list, /fo guide use <n>." } end
    local out = {}
    local n, i, step = #r.steps, self.index, self.current
    if not step then
        out[1] = string.format("|cffffd100%s|r finished (%d steps). /fo guide list for more.", r.name, n)
        return out
    end
    out[#out + 1] = string.format("|cffaaaaaa%s|r  step %d/%d", r.name, i, n)
    out[#out + 1] = self:StepText(step)
    local block = self:Blocker(step, self.log or LogSet())
    if block then out[#out + 1] = "|cffff8040" .. block .. "|r, Skip moves on" end
    local prog = self:Progress(step)
    if prog then out[#out + 1] = prog end
    if step.note then out[#out + 1] = "|cffaaaaaa" .. step.note .. "|r" end
    local shown = 0
    for j = i + 1, n do
        if ClassOK(r.steps[j]) then
            out[#out + 1] = "|cff808080next: " .. self:StepText(r.steps[j], true) .. "|r"
            shown = shown + 1
            if shown >= 2 then break end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------
function G:Use(route, keepProgress)
    self.route = route
    local st = self:State()
    if st.route ~= route.key or not keepProgress then st.route, st.pos, st.done = route.key, 1, {} end
    self.index = nil
    lastArrowKey = nil
    self:Refresh("init")
end

function G:Skip()
    if not (self.route and self.current) then return end
    self:State().done[self.index] = true
    self:Refresh("skip")
end

function G:Back()
    if not self.route then return end
    local st = self:State()
    local i = self.index - 1
    while i >= 1 and not ClassOK(self.route.steps[i]) do i = i - 1 end
    if i < 1 then return end
    st.done[i] = nil
    st.pos = i
    self.index = i
    self.current = self.route.steps[i]
    lastArrowKey = nil
    self:PointArrow(true)
    self:Render()
    print("back to step %d: %s", i, self:StepText(self.current, true))
end

function G:Goto(i)
    if not self.route then return end
    i = math.max(1, math.min(#self.route.steps, i))
    local st = self:State()
    for j = i, #self.route.steps do st.done[j] = nil end
    st.pos = i
    self.index = nil
    lastArrowKey = nil
    self:Refresh("goto")
end

-- ---------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------
local MAX = 7
local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "ForeverOptimizerGuide", UIParent, "BackdropTemplate")
    frame:SetSize(G.db.width, 120)
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0, 0, 0, 0.65)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function(self) if not G.db.locked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        G.db.point = { p, rp, x, y }
    end)
    local pt = G.db.point
    if pt then frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -200) end

    widgets = { lines = {}, buttons = {} }
    local x = 8
    for _, b in ipairs({ { "Back", function() G:Back() end }, { "Skip", function() G:Skip() end }, { "Arrow", function() G:PointArrow(true) end }, { "Hide", function() G:Hide() end } }) do
        local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
        btn:SetSize(40, 14)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        btn:SetBackdropColor(1, 1, 1, 0.07)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn.text:SetText(b[1])
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -6)
        btn:SetScript("OnClick", function() FO.Try("guide " .. b[1], b[2]) end)
        btn:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
        btn:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 0.82, 0) end)
        widgets.buttons[#widgets.buttons + 1] = btn
        x = x + 44
    end
    for i = 1, MAX do
        local fs = frame:CreateFontString(nil, "OVERLAY", i == 2 and "GameFontNormal" or "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -24 - (i - 1) * 15)
        fs:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(i == 5)
        widgets.lines[i] = fs
    end
    if G.db.shown == false then frame:Hide() end
end

function G:Render()
    if not (frame and frame:IsShown()) then return end
    local ok, out = pcall(function() return self:Lines() end)
    if not ok then out = { "|cffff6060" .. tostring(out) .. "|r" } end
    local y = 24
    for i = 1, MAX do
        local fs = widgets.lines[i]
        fs:SetText(out[i] or "")
        fs:SetShown(out[i] ~= nil)
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -y)
        if out[i] then y = y + ((i == 5 and fs.GetStringHeight and math.max(15, fs:GetStringHeight() + 2)) or 15) end
    end
    frame:SetHeight(y + 8)
end

function G:Show() self.db.shown = true Build() frame:Show() self:Render() end
function G:Hide() self.db.shown = false if frame then frame:Hide() end end
function G:Toggle() if frame and frame:IsShown() then self:Hide() else self:Show() end end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
G.events = {
    QUEST_ACCEPTED = function(self) self:Schedule() end,
    QUEST_TURNED_IN = function(self) self:Schedule() end,
    QUEST_REMOVED = function(self) self:Schedule() end,
    QUEST_LOG_UPDATE = function(self) self:Schedule() end,
    UNIT_QUEST_LOG_CHANGED = function(self, unit) if unit == "player" then self:Schedule() end end,
    PLAYER_LEVEL_UP = function(self) self:Schedule() end,
    HEARTHSTONE_BOUND = function(self) self:Schedule() end,
    TRAINER_CLOSED = function(self)
        local st = self:State()
        if self.current and self.current[1] == "TRAIN" and Level() >= self.current[2] then
            st.trainedAt, st.trainedStep = Level(), self.index
            self:Schedule()
        end
    end,
    PLAYER_ENTERING_WORLD = function(self) self:Schedule() end,
}

function G:OnInit() self.Schedule = U.Debounce(0.5, function() FO.TryCall("guide refresh", function() self:Refresh("event") end) end) end

function G:OnEnable()
    local st = self:State()
    local route = (st.route and self:FindRoute(st.route)) or self:PickRoute()
    Build()
    if route then self:Use(route, true) else self:Refresh("init") end
    if FO.Dashboard and FO.Dashboard.RegisterTab then
        FO.Dashboard:RegisterTab("Guide", 1.7, function() return self:Lines() end, function()
            return { { label = "Back", fn = function() self:Back() end }, { label = "Skip", fn = function() self:Skip() end },
                     { label = "Arrow", fn = function() self:PointArrow(true) end },
                     { label = function() return (frame and frame:IsShown()) and "Hide window" or "Show window" end, fn = function() self:Toggle() end } }
        end)
    end
    local tick = 0
    self.OnTick = function(self2)
        tick = tick + 1
        if tick % 5 == 0 and self2.route then self2:Refresh("tick") end
    end
end

function ForeverOptimizer_GuideSkip() if FO.Guide then FO.Guide:Skip() end end
function ForeverOptimizer_GuideToggle() if FO.Guide then FO.Guide:Toggle() end end

G.commands = {
    guide = { help = "leveling guide: (status) | list | use <n|name> | skip | back | goto <step> | reset | show | hide | arrow on|off", fn = function(self, arg)
        local sub, rest = U.SplitCmd(arg or "")
        if sub == "" or sub == "status" then
            for _, l in ipairs(self:Lines()) do print("%s", l) end
        elseif sub == "list" then
            local routes = self:Routes()
            if #routes == 0 then print("no routes loaded.") return end
            print("routes (%s):", tostring(routes.source))
            for i, r in ipairs(routes) do
                local races = {}
                for k in pairs(r.races or {}) do races[#races + 1] = k end
                table.sort(races)
                print("  %d. %s%s  %s %s, %d steps", i, r.name, self.route == r and " |cff80ff80(active)|r" or "", r.faction or "", table.concat(races, "/"), #r.steps)
            end
        elseif sub == "use" then
            local r = self:FindRoute(rest)
            if not r then print("no route '%s'. /fo guide list", rest) return end
            self:Use(r, true)
            self:Show()
            print("guide: %s, step %d/%d.", r.name, self.index, #r.steps)
        elseif sub == "skip" or sub == "next" then self:Skip()
        elseif sub == "back" then self:Back()
        elseif sub == "goto" then
            local n = tonumber(rest)
            if not n then print("guide goto <step number>") return end
            self:Goto(n)
        elseif sub == "reset" then
            if not self.route then print("no route active.") return end
            self:Use(self.route, false)
            print("guide reset to step 1.")
        elseif sub == "show" then self:Show()
        elseif sub == "hide" then self:Hide()
        elseif sub == "arrow" then
            self.db.arrow = rest ~= "off"
            if self.db.arrow then lastArrowKey = nil self:PointArrow(true) elseif FO.Arrow then FO.Arrow:Clear() end
            print("guide arrow %s.", self.db.arrow and "on" or "off")
        else
            print("guide: status | list | use <n> | skip | back | goto <n> | reset | show | hide | arrow on|off")
        end
    end },
}
