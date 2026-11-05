local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Dashboard")

-- ===========================================================================
-- Minimap node icons. The herb and ore nodes the world map pins (recorded by
-- Grinding.FarmingEfficiency) drawn on the minimap too, with the same item
-- icons, placed by yards from the player and the minimap's zoom radius, and
-- turned with the minimap when it rotates. Hover a pin for the name, how
-- often it was seen and when. /fo minimap on|off, herb|ore on|off, size, minseen.
-- ===========================================================================
local MN = FO:NewModule("Dashboard.Minimap", {
    account = "minimap",
    defaults = { settings = { enabled = true, herb = true, ore = true, size = 14, minSeen = 1, maxPins = 80 } },
})
FO.MinimapNodes = MN

-- Minimap diameter in yards per zoom level (Blizzard's values, as HereBeDragons lists them)
local DIAMETER = {
    outdoor = { [0] = 466.67, 400, 333.33, 266.67, 200, 133.33 },
    indoor  = { [0] = 300, 240, 180, 120, 80, 50 },
}

local frame, pool, rows = nil, {}, {}
local radius, halfW, halfH = 233.33, 70, 70
local elapsed = 0
MN.mapID, MN.shown, MN.dirty = nil, 0, true

local function WorldPos(mapID, x, y)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, inst, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not ok or type(pos) ~= "table" then return nil end
    local wx, wy
    if pos.GetXY then wx, wy = pos:GetXY() else wx, wy = pos.x, pos.y end
    wx, wy = U.Num(wx), U.Num(wy)
    if wx and wy then return wx, wy end
end

-- Zoom radius in yards. Indoors and outdoors have different scales and the same zoom
-- index; the two CVars tell which one is in force (the HereBeDragons trick).
function MN:UpdateZoom()
    if not Minimap then return end
    local zoom = U.Num(Minimap.GetZoom and Minimap:GetZoom()) or 0
    local inside = false
    if GetCVar then
        local okZ, z = pcall(GetCVar, "minimapZoom")
        local okI, iz = pcall(GetCVar, "minimapInsideZoom")
        if okZ and okI and z ~= nil and iz ~= nil then
            if tostring(z) == tostring(iz) and Minimap.SetZoom then
                -- both CVars agree: nudge the zoom to see which one follows
                pcall(Minimap.SetZoom, Minimap, zoom < 2 and zoom + 1 or zoom - 1)
                local okZ2, z2 = pcall(GetCVar, "minimapZoom")
                inside = not (okZ2 and tonumber(z2) == Minimap:GetZoom())
                pcall(Minimap.SetZoom, Minimap, zoom)
            else
                inside = tonumber(z) ~= zoom
            end
        end
    end
    local d = DIAMETER[inside and "indoor" or "outdoor"][zoom] or DIAMETER.outdoor[0]
    radius = d / 2
    halfW = (U.Num(Minimap.GetWidth and Minimap:GetWidth()) or 140) / 2
    halfH = (U.Num(Minimap.GetHeight and Minimap:GetHeight()) or 140) / 2
    self.radius, self.inside = radius, inside
end

local function Tooltip(pin)
    if not (GameTooltip and pin.row) then return end
    local r = pin.row
    GameTooltip:SetOwner(pin, "ANCHOR_LEFT")
    GameTooltip:AddLine(r.name)
    GameTooltip:AddLine(string.format("%s, seen %d time%s%s", r.kind == "herb" and "Herb" or "Ore", r.n or 1, (r.n or 1) == 1 and "" or "s",
        r.last and (", last " .. U.FormatDuration(time() - r.last) .. " ago") or ""), 0.8, 0.8, 0.8)
    if pin.yards then GameTooltip:AddLine(string.format("%.0f yd away", pin.yards), 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function NewPin(i)
    local pin = CreateFrame("Frame", nil, frame)
    pin:SetSize(MN.db.settings.size or 14, MN.db.settings.size or 14)
    if pin.SetFrameLevel and frame.GetFrameLevel then pin:SetFrameLevel((frame:GetFrameLevel() or 0) + 1) end
    pin.tex = pin:CreateTexture(nil, "OVERLAY")
    pin.tex:SetAllPoints(pin)
    pin.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    pin:EnableMouse(true)
    pin:SetScript("OnEnter", function(self) Tooltip(self) end)
    pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    pin:Hide()
    pool[i] = pin
    return pin
end

local function Build()
    if frame or not Minimap then return end
    frame = CreateFrame("Frame", "ForeverOptimizerMinimapNodes", Minimap)
    frame:SetAllPoints(Minimap)
    if frame.SetFrameLevel and Minimap.GetFrameLevel then pcall(frame.SetFrameLevel, frame, (Minimap:GetFrameLevel() or 0) + 5) end
    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed < 0.1 then return end
        elapsed = 0
        FO.TryCall("minimap nodes", function() MN:Update() end)
    end)
    MN.frame = frame
end

-- Rows for the current map: the same points the world map pins, with world coordinates cached
function MN:Rebuild()
    local mapID = U.PlayerPosition()
    self.mapID = mapID
    rows = {}
    self.dirty = false
    local s = self.db.settings
    local FE, M = FO:GetModule("Grinding.FarmingEfficiency"), FO:GetModule("Dashboard.Map")
    if not (mapID and FE and FE.db and not FE.disabled) then return rows end
    local w, h = U.MapSize(mapID)
    for name, node in pairs(FE.db.nodes or {}) do
        local kind = node.kind
        if (kind == "herb" and s.herb ~= false) or (kind == "ore" and s.ore ~= false) then
            for _, p in ipairs(node.points or {}) do
                if p[1] == mapID and (p.n or 1) >= (s.minSeen or 1) then
                    local wx, wy = WorldPos(mapID, p[2], p[3])
                    rows[#rows + 1] = { name = name, kind = kind, x = p[2], y = p[3], n = p.n, last = p.last, wx = wx, wy = wy,
                                        icon = M and M.NodeIcon and M:NodeIcon(name, kind) or nil }
                end
            end
        end
    end
    self.rows = rows
    return rows
end

-- Place every row within the zoom radius; hide the rest
function MN:Update()
    if not frame then return end
    local s = self.db.settings
    if s.enabled == false then self:HideAll() return end
    local mapID, px, py = U.PlayerPosition()
    if not (mapID and px) then self:HideAll() return end
    if mapID ~= self.mapID or self.dirty then self:Rebuild() end
    local pwx, pwy = WorldPos(mapID, px, py)
    local w, h = U.MapSize(mapID)
    local rotate = false
    if GetCVar then local ok, v = pcall(GetCVar, "rotateMinimap") rotate = ok and tostring(v) == "1" end
    local facing = rotate and U.Num(GetPlayerFacing and GetPlayerFacing()) or nil
    local vis = {}
    for _, r in ipairs(rows) do
        local north, west
        if pwx and r.wx then north, west = r.wx - pwx, r.wy - pwy        -- world x grows north, y grows west
        elseif w then north, west = -(r.y - py) * h, -(r.x - px) * w    -- map x grows east, y grows south
        end
        if north then
            local d = math.sqrt(north * north + west * west)
            r.d = d
            if d <= radius then
                local bearing = math.atan2(west, north)
                if facing then bearing = bearing - facing end
                r.sx, r.sy = -math.sin(bearing) * d / radius * halfW, math.cos(bearing) * d / radius * halfH
                vis[#vis + 1] = r
            end
        end
    end
    local maxPins = s.maxPins or 80
    if #vis > maxPins then table.sort(vis, function(a, b) return a.d < b.d end) end
    local n = math.min(#vis, maxPins)
    for i = 1, n do
        local r, pin = vis[i], pool[i] or NewPin(i)
        pin.row, pin.yards = r, r.d
        pin.sx, pin.sy = r.sx, r.sy
        pin:SetSize(s.size or 14, s.size or 14)
        pin.tex:SetTexture(r.icon or (r.kind == "herb" and "Interface\\Icons\\Trade_Herbalism" or "Interface\\Icons\\Trade_Mining"))
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", Minimap, "CENTER", r.sx, r.sy)
        pin:Show()
    end
    for i = n + 1, #pool do pool[i]:Hide() pool[i].row = nil end
    self.shown = n
end

function MN:HideAll()
    for _, pin in ipairs(pool) do pin:Hide() pin.row = nil end
    self.shown = 0
end

function MN:OnEnable()
    if not Minimap then self.reason = "no Minimap frame" return end
    Build()
    self:UpdateZoom()
    FO:RegisterEvent("MINIMAP_UPDATE_ZOOM", function() self:UpdateZoom() end)
    FO:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() self.dirty = true end)
    FO:RegisterEvent("PLAYER_ENTERING_WORLD", function() self.dirty = true self:UpdateZoom() end)
end

MN.messages = {
    FO_NODE = function(self) self.dirty = true end,
}

MN.commands = {
    minimap = { help = "node icons on the minimap: status | on | off | herb on|off | ore on|off | size <8-32> | minseen <n>", fn = function(self, arg)
        local s = self.db.settings
        local sub, rest = U.SplitCmd(arg or "")
        if sub == "" or sub == "status" then
            print("minimap nodes: %s, herbs %s, ores %s, size %d, min seen %d; %d of %d on this map in view, zoom radius %.0f yd%s",
                s.enabled == false and "off" or "on", s.herb == false and "off" or "on", s.ore == false and "off" or "on", s.size or 14, s.minSeen or 1,
                self.shown or 0, #(self.rows or {}), self.radius or radius, self.inside and " (indoors)" or "")
        elseif sub == "on" then s.enabled = true self.dirty = true print("minimap nodes on.")
        elseif sub == "off" then s.enabled = false self:HideAll() print("minimap nodes off.")
        elseif sub == "herb" or sub == "ore" then s[sub] = rest ~= "off" self.dirty = true print("%s nodes %s on the minimap.", sub, s[sub] and "shown" or "hidden")
        elseif sub == "size" then
            local n = tonumber(rest)
            if n and n >= 8 and n <= 32 then s.size = math.floor(n) print("minimap node icons %d px.", s.size) else print("size <8-32>") end
        elseif sub == "minseen" then
            local n = tonumber(rest)
            if n and n >= 1 then s.minSeen = math.floor(n) self.dirty = true print("showing nodes seen at least %d time%s.", s.minSeen, s.minSeen == 1 and "" or "s") else print("minseen <n>") end
        else print("minimap: status | on | off | herb on|off | ore on|off | size <n> | minseen <n>") end
    end },
}
