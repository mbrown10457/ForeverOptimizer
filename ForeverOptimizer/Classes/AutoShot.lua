local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Classes")

-- ===========================================================================
-- Auto Shot timer. A bar that fills from the last Auto Shot (or wand Shoot)
-- to the next: the client fires UNIT_SPELLCAST_SUCCEEDED for every shot and
-- START/STOP_AUTOREPEAT_SPELL when auto-repeat turns on or off, and the
-- weapon speed comes from UnitRangedDamage. The last half second of each
-- cycle is the aim window: the shot only fires if you stand still through
-- it, so that part of the bar is marked and turns red while you are moving.
-- A cast (Aimed Shot, Multi-Shot) pauses the cycle and restarts it when the
-- cast lands, which is what the bar shows. Spell IDs that arrive as secret
-- values are read from the cast GUID instead (Cast-3-...-<spellID>-...).
-- ===========================================================================
local AS = FO:NewModule("Classes.AutoShot", {
    account = "autoshot",
    defaults = { enabled = true, point = nil, width = 220, height = 16, scale = 1.0, locked = false, always = false, aim = 0.5, wand = true },
})
FO.AutoShot = AS

local AUTO_SPELLS = { [75] = "Auto Shot", [5019] = "Shoot" }
local LINGER = 1.5      -- seconds the bar stays after auto-repeat stops

AS.active = false       -- auto-repeat on
AS.lastShot = nil       -- GetTime() of the last shot
AS.speed = nil          -- weapon speed in seconds
AS.casting = nil        -- { guid=, start=, finish=, name= } while a cast is up
AS.shots, AS.secret, AS.resets = 0, 0, 0
AS.name = "Auto Shot"
local stoppedAt
local frame, bar, aimTex, textFS, spark

local function RangedSpeed()
    if not UnitRangedDamage then return nil end
    local ok, speed = pcall(function() return U.Num((UnitRangedDamage("player"))) end)
    return ok and speed and speed > 0 and speed or nil
end

-- spell id from the event, or from the cast GUID when the id itself is secret
local function SpellIDOf(spellID, castGUID)
    local id = U.Num(spellID)
    if id then return id end
    local g = U.Str(castGUID)
    if g then
        local s = g:match("^Cast%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
        if s then return tonumber(s) end
    end
    return nil
end

local function SpellName(id)
    if AUTO_SPELLS[id] then return AUTO_SPELLS[id] end
    local ok, name = pcall(function()
        if C_Spell and C_Spell.GetSpellName then return U.Str(C_Spell.GetSpellName(id)) end
        if GetSpellInfo then return U.Str((GetSpellInfo(id))) end
    end)
    return ok and name or ("spell " .. tostring(id))
end

local function Moving()
    if not GetUnitSpeed then return false end
    local ok, v = pcall(GetUnitSpeed, "player")
    v = ok and U.Num(v) or 0
    return v > 0
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
function AS:Shot(now, name)
    now = now or GetTime()
    if self.lastShot and now - self.lastShot < 0.3 then return end   -- same shot reported twice
    self.lastShot = now
    self.speed = RangedSpeed() or self.speed
    self.shots = self.shots + 1
    self.name = name or self.name
    self.casting = nil
    if frame and self.db.enabled ~= false then frame:Show() end
end

-- seconds until the next shot can fire (0 = ready, waiting for the aim window or range)
function AS:Remaining(now)
    if not (self.lastShot and self.speed) then return nil end
    return math.max(0, self.speed - ((now or GetTime()) - self.lastShot))
end

function AS:InAimWindow(now)
    local r = self:Remaining(now)
    return r ~= nil and r <= (self.db.aim or 0.5)
end

local function OnAutoStart()
    AS.active = true
    stoppedAt = nil
    AS.speed = RangedSpeed() or AS.speed
    if not AS.lastShot then AS.lastShot = GetTime() end    -- first shot follows a full cycle from the press
    if frame and AS.db.enabled ~= false then frame:Show() end
end

local function OnAutoStop()
    AS.active = false
    stoppedAt = GetTime()
end

local function OnSucceeded(unit, castGUID, spellID)
    if unit ~= "player" then return end
    local id = SpellIDOf(spellID, castGUID)
    if not id then AS.secret = AS.secret + 1 return end
    local auto = AUTO_SPELLS[id]
    if auto then
        if auto == "Shoot" and AS.db.wand == false then return end
        AS:Shot(GetTime(), auto)
        return
    end
    local c = AS.casting
    if c and (c.guid == nil or c.guid == U.Str(castGUID) or c.id == id) then c.done = true end
end

local function OnCastStart(unit, castGUID, spellID)
    if unit ~= "player" then return end
    local id = SpellIDOf(spellID, castGUID)
    local now = GetTime()
    local finish
    if UnitCastingInfo then
        local ok, _, _, _, startMS, endMS = pcall(UnitCastingInfo, "player")
        startMS, endMS = ok and U.Num(startMS), ok and U.Num(endMS)
        if startMS and endMS and endMS > startMS then finish = now + (endMS - startMS) / 1000 end
    end
    AS.casting = { guid = U.Str(castGUID), id = id, start = now, finish = finish, name = id and SpellName(id) or "cast" }
end

local function OnCastStop(unit, castGUID)
    if unit ~= "player" then return end
    local c = AS.casting
    if not c then return end
    AS.casting = nil
    -- a landed cast restarts the auto shot cycle; an interrupted one leaves it where it was
    if c.done then AS.lastShot = GetTime() AS.resets = AS.resets + 1 end
end

local function OnCastInterrupted(unit)
    if unit ~= "player" then return end
    AS.casting = nil
end

-- ---------------------------------------------------------------------------
-- Bar
-- ---------------------------------------------------------------------------
local function Layout()
    if not frame then return end
    local w, h = AS.db.width or 220, AS.db.height or 16
    frame:SetSize(w, h)
    frame:SetScale(AS.db.scale or 1)
    local aim = math.min(1, (AS.db.aim or 0.5) / (AS.speed or 2))
    aimTex:ClearAllPoints()
    aimTex:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    aimTex:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    aimTex:SetWidth(math.max(1, w * aim))
end

local elapsed = 0
local function OnUpdate(self, dt)
    elapsed = elapsed + (dt or 0)
    if elapsed < 0.02 then return end
    elapsed = 0
    FO.TryCall("autoshot bar", function() AS:Draw() end)
end

function AS:Draw()
    if not frame then return end
    local now = GetTime()
    if not self.active and not self.db.always and (not stoppedAt or now - stoppedAt > LINGER) and not self.testUntil then
        frame:Hide()
        return
    end
    if self.testUntil and now > self.testUntil then self.testUntil = nil if not self.active then frame:Hide() return end end
    local speed = self.speed or RangedSpeed() or 2
    local c = self.casting
    if c then
        local frac = c.finish and math.min(1, (now - c.start) / math.max(0.1, c.finish - c.start)) or 0
        bar:SetValue(frac)
        bar:SetStatusBarColor(0.35, 0.6, 1)
        aimTex:Hide()
        textFS:SetText(c.name)
        return
    end
    aimTex:Show()
    local remaining = self:Remaining(now)
    if not remaining then
        bar:SetValue(0)
        bar:SetStatusBarColor(0.6, 0.6, 0.6)
        textFS:SetText(self.name)
        return
    end
    local frac = 1 - remaining / speed
    bar:SetValue(math.max(0, math.min(1, frac)))
    local inAim = remaining <= (self.db.aim or 0.5)
    if inAim and Moving() then
        bar:SetStatusBarColor(1, 0.25, 0.2)
        textFS:SetText("stop moving")
    elseif remaining <= 0 then
        bar:SetStatusBarColor(0.3, 1, 0.3)
        textFS:SetText(self.name .. " ready")
    else
        bar:SetStatusBarColor(inAim and 1 or 0.95, inAim and 0.75 or 0.6, 0.2)
        textFS:SetText(string.format("%s  %.1f s", self.name, remaining))
    end
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "ForeverOptimizerAutoShot", UIParent)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function(self) if not AS.db.locked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        AS.db.point = { p, rp, x, y }
    end)
    local pt = AS.db.point
    if pt then frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else frame:SetPoint("CENTER", UIParent, "CENTER", 0, -120) end

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 0.6)

    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    aimTex = frame:CreateTexture(nil, "OVERLAY")
    aimTex:SetColorTexture(1, 1, 1, 0.22)

    textFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    textFS:SetPoint("CENTER", frame, "CENTER", 0, 0)

    frame:SetScript("OnUpdate", OnUpdate)
    frame:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Auto Shot timer")
        GameTooltip:AddLine(string.format("weapon speed %.2f s, aim window %.1f s", AS.speed or RangedSpeed() or 0, AS.db.aim or 0.5), 0.8, 0.8, 0.8)
        GameTooltip:AddLine("drag to move; /fo shotbar lock | always | scale | width", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    Layout()
    frame:Hide()
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------
function AS:OnEnable()
    local class = FO.Player.class
    if class ~= "HUNTER" and self.db.wand == false then return end
    self.speed = RangedSpeed()
    Build()
    FO:RegisterEvent("START_AUTOREPEAT_SPELL", OnAutoStart)
    FO:RegisterEvent("STOP_AUTOREPEAT_SPELL", OnAutoStop)
    FO:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", OnSucceeded)
    FO:RegisterEvent("UNIT_SPELLCAST_START", OnCastStart)
    FO:RegisterEvent("UNIT_SPELLCAST_STOP", OnCastStop)
    FO:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", OnCastInterrupted)
    FO:RegisterEvent("UNIT_SPELLCAST_FAILED", OnCastInterrupted)
    FO:RegisterEvent("UNIT_INVENTORY_CHANGED", function(unit) if unit == "player" then AS.speed = RangedSpeed() or AS.speed Layout() end end)
    FO:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() AS.speed = RangedSpeed() or AS.speed Layout() end)
    self.ready = true
end

function AS:Status()
    if not self.ready then return "off (not a hunter; /fo shotbar wand on enables it for wands)" end
    return string.format("%s, speed %s, %d shots this session%s%s%s", self.db.enabled == false and "hidden" or (self.active and "firing" or "idle"),
        self.speed and string.format("%.2f s", self.speed) or "unknown", self.shots,
        self.resets > 0 and string.format(", %d restarts after casts", self.resets) or "",
        self.secret > 0 and string.format(", %d casts with hidden spell ids", self.secret) or "",
        self.db.always and ", always shown" or "")
end

AS.commands = {
    shotbar = { help = "Auto Shot timer bar: (status) | on | off | lock | always | scale <n> | width <n> | aim <s> | wand on|off | test", fn = function(self, arg)
        local sub, rest = U.SplitCmd(arg or "")
        if sub == "" then print("auto shot bar: %s", self:Status())
        elseif sub == "on" then self.db.enabled = true print("auto shot bar on.")
        elseif sub == "off" then self.db.enabled = false if frame then frame:Hide() end print("auto shot bar off.")
        elseif sub == "lock" then self.db.locked = not self.db.locked print("auto shot bar %s.", self.db.locked and "locked" or "unlocked")
        elseif sub == "always" then self.db.always = not self.db.always print("auto shot bar %s.", self.db.always and "always shown" or "shown while shooting")
        elseif sub == "scale" then
            local n = tonumber(rest)
            if n and n >= 0.5 and n <= 3 then self.db.scale = n Layout() print("scale %.2f", n) else print("scale <0.5-3>") end
        elseif sub == "width" then
            local n = tonumber(rest)
            if n and n >= 80 and n <= 600 then self.db.width = n Layout() print("width %d", n) else print("width <80-600>") end
        elseif sub == "aim" then
            local n = tonumber(rest)
            if n and n >= 0 and n <= 2 then self.db.aim = n Layout() print("aim window %.2f s", n) else print("aim <0-2> seconds (0.5 is the classic value)") end
        elseif sub == "wand" then
            self.db.wand = rest ~= "off"
            print("wand Shoot timer %s%s.", self.db.wand and "on" or "off", self.ready and "" or " (takes effect after /reload)")
        elseif sub == "test" then
            if not frame then print("bar not built (not a hunter).") return end
            self.speed = self.speed or RangedSpeed() or 2.0
            self.lastShot = GetTime()
            self.testUntil = GetTime() + 10
            Layout()
            frame:Show()
            print("showing the bar for 10 s with a %.2f s cycle.", self.speed)
        else
            print("shotbar: on | off | lock | always | scale <n> | width <n> | aim <s> | wand on|off | test")
        end
    end },
}
