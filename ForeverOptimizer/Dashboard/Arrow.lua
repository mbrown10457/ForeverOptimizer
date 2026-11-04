local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Dashboard")

-- ===========================================================================
-- A TomTom-style direction arrow. Points from the player to one target with
-- the yards left, colours by how far off your heading is, and fires a
-- callback (or clears itself) on arrival. Targets come from /fo next,
-- /fo route, the leveling guide (/fo guide) or /fo arrow <x> <y>.
-- Bearings use world space when the client converts map positions
-- (C_Map.GetWorldPosFromMapPos), so a target on another map still works;
-- otherwise same-map yards from the map's world size.
-- ===========================================================================
local A = FO:NewModule("Dashboard.Arrow", {
    account = "arrow",
    defaults = { enabled = true, point = nil, scale = 1.0, arrive = 15, locked = false },
})
FO.Arrow = A

local frame, tex, labelFS, distFS
local elapsed = 0
A.target = nil     -- { mapID=, x=, y=, label=, onArrive= }
A.heading = nil    -- rotation last drawn (radians, counter-clockwise from "up")
A.yards = nil

local function Norm(a) return (a + math.pi) % (2 * math.pi) - math.pi end

local function WorldPos(mapID, x, y)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, inst, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or type(pos) ~= "table" then return nil end
    local wx, wy
    if pos.GetXY then wx, wy = pos:GetXY() else wx, wy = pos.x, pos.y end
    wx, wy = U.Num(wx), U.Num(wy)
    if wx and wy then return U.Num(inst) or 0, wx, wy end
end

-- Bearing in radians counter-clockwise from north (the GetPlayerFacing convention),
-- yards, and whether the yards are a guess (no world size for the map).
function A:Vector(pmap, px, py, tmap, tx, ty)
    local ia, ax, ay = WorldPos(pmap, px, py)
    local ib, bx, by = WorldPos(tmap, tx, ty)
    if ax and bx and ia == ib then
        local north, west = bx - ax, by - ay          -- world x grows north, y grows west
        return math.atan2(west, north), math.sqrt(north * north + west * west), false
    end
    if pmap ~= tmap then return nil end
    local w, h = U.MapSize(pmap)
    local approx = not w
    w, h = w or 3000, h or 2000
    local east, south = (tx - px) * w, (ty - py) * h  -- map x grows east, y grows south
    return math.atan2(-east, -south), math.sqrt(east * east + south * south), approx
end

local function Colour(off)
    if off < 0.26 then tex:SetVertexColor(0.25, 1, 0.25)
    elseif off < 1.2 then tex:SetVertexColor(1, 0.85, 0.2)
    else tex:SetVertexColor(1, 0.35, 0.2) end
end

function A:Update()
    local t = self.target
    if not (t and frame) then return end
    local pmap, px, py = U.PlayerPosition()
    if not (pmap and px) then distFS:SetText("no position") tex:SetVertexColor(0.6, 0.6, 0.6) self.yards = nil return end
    local bearing, yards, approx = self:Vector(pmap, px, py, t.mapID, t.x, t.y)
    if not bearing then
        distFS:SetText("on " .. U.MapName(t.mapID))
        tex:SetVertexColor(0.6, 0.6, 0.6)
        self.yards = nil
        return
    end
    self.yards = yards
    local facing = U.Num(GetPlayerFacing and GetPlayerFacing())
    if facing then
        local rot = Norm(bearing - facing)
        self.heading = rot
        tex:SetRotation(rot)
        Colour(math.abs(rot))
    else
        tex:SetVertexColor(0.6, 0.6, 0.6)
    end
    distFS:SetText(string.format("%s%.0f yd", approx and "~" or "", yards))
    if yards <= (self.db.arrive or 15) then self:Arrived() end
end

function A:Arrived()
    local t = self.target
    if not t then return end
    self.target, self.yards = nil, nil
    if frame then frame:Hide() end
    if t.onArrive then FO.Try("arrow arrive", t.onArrive, t)
    else print("arrived: %s", t.label or "waypoint") end
end

local function OnUpdate(self, dt)
    elapsed = elapsed + (dt or 0)
    if elapsed < 0.05 then return end
    elapsed = 0
    FO.TryCall("arrow", function() A:Update() end)
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "ForeverOptimizerArrow", UIParent)
    frame:SetSize(150, 90)
    frame:SetScale(A.db.scale or 1)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function(self) if not A.db.locked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        A.db.point = { p, rp, x, y }
    end)
    frame:SetScript("OnMouseUp", function(self, btn) if btn == "RightButton" then A:Clear() print("arrow cleared.") end end)
    frame:SetScript("OnEnter", function(self)
        if not (GameTooltip and A.target) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(A.target.label or "waypoint")
        GameTooltip:AddLine(string.format("%s %.1f, %.1f", U.MapName(A.target.mapID), A.target.x * 100, A.target.y * 100), 0.8, 0.8, 0.8)
        GameTooltip:AddLine("drag to move, right-click to clear", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local pt = A.db.point
    if pt then frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else frame:SetPoint("TOP", UIParent, "TOP", 0, -140) end

    tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetTexture("Interface\\Minimap\\MinimapArrow")
    tex:SetSize(44, 44)
    tex:SetPoint("TOP", frame, "TOP", 0, -2)

    labelFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelFS:SetPoint("TOP", tex, "BOTTOM", 0, -2)
    labelFS:SetWidth(150)
    labelFS:SetJustifyH("CENTER")
    labelFS:SetWordWrap(false)

    distFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    distFS:SetPoint("TOP", labelFS, "BOTTOM", 0, -1)

    frame:SetScript("OnUpdate", OnUpdate)
    frame:Hide()
end

-- x, y accept either 0-1 or 0-100. onArrive(target) replaces the default "arrived" print.
function A:Set(mapID, x, y, label, onArrive)
    mapID, x, y = U.Num(mapID), U.Num(x), U.Num(y)
    if not (mapID and x and y) then return false end
    if x > 1 or y > 1 then x, y = x / 100, y / 100 end
    Build()
    self.target = { mapID = mapID, x = x, y = y, label = label or "waypoint", onArrive = onArrive }
    labelFS:SetText(U.Trunc(self.target.label, 26))
    distFS:SetText("")
    if self.db.enabled ~= false then frame:Show() end
    self:Update()
    return true
end

function A:Clear()
    self.target, self.yards, self.heading = nil, nil, nil
    if frame then frame:Hide() end
end

function A:Active() return self.target ~= nil end

function A:OnEnable() Build() end

A.commands = {
    arrow = { help = "<x> <y> [label] | clear | on | off | lock | arrive <yards> | scale <n> — direction arrow to the current target", fn = function(self, arg)
        local sub, rest = U.SplitCmd(arg or "")
        if sub == "" then
            local t = self.target
            if not t then print("arrow: no target. /fo next, /fo route, /fo guide or /fo arrow <x> <y> set one.") return end
            print("arrow: %s on %s (%.1f, %.1f)%s%s", t.label, U.MapName(t.mapID), t.x * 100, t.y * 100,
                self.yards and string.format(", %.0f yd", self.yards) or "", self.db.enabled == false and " [hidden: /fo arrow on]" or "")
        elseif sub == "clear" then self:Clear() print("arrow cleared.")
        elseif sub == "on" then self.db.enabled = true if self.target and frame then frame:Show() end print("arrow on.")
        elseif sub == "off" then self.db.enabled = false if frame then frame:Hide() end print("arrow hidden. Targets still update; /fo arrow on brings it back.")
        elseif sub == "lock" then self.db.locked = not self.db.locked print("arrow %s", self.db.locked and "locked" or "unlocked")
        elseif sub == "arrive" then
            local n = tonumber(rest)
            if n and n >= 3 and n <= 200 then self.db.arrive = n print("arrive radius %d yards.", n) else print("arrive <3-200>") end
        elseif sub == "scale" then
            local s = tonumber(rest)
            if s and s >= 0.5 and s <= 2.5 then self.db.scale = s if frame then frame:SetScale(s) end print("arrow scale %.2f", s) else print("scale <0.5-2.5>") end
        else
            local x, y, label = (arg or ""):match("^%s*([%d%.]+)[,%s]+([%d%.]+)%s*(.-)$")
            x, y = tonumber(x), tonumber(y)
            if not (x and y) then print("arrow <x> <y> [label] — coordinates on the current map (0-100).") return end
            local mapID = U.PlayerPosition()
            if not mapID then print("no map position.") return end
            if self:Set(mapID, x, y, label ~= "" and label or string.format("%.1f, %.1f", x, y)) then
                print("arrow set: %s on %s.", self.target.label, U.MapName(mapID))
            end
        end
    end },
}
