local ADDON, FO = ...
local U = FO.Util

-- ===========================================================================
-- World map overlay: player + cursor coordinates on the map, and pins for
-- everything the addon has recorded with a position: gathering nodes (herb /
-- ore, from Grinding.FarmingEfficiency), rare sightings, and mob spawn points
-- with their respawn estimate. Uses the map's own data-provider API so pins
-- scale and layer like Blizzard's; if that API is missing on this client the
-- module degrades to coordinates only and says so in /fo map.
-- Reveal: the parts of a zone map the character has not explored yet, drawn
-- from the client's own overlay art (Data/MapOverlays.lua lists every
-- exploration overlay; C_MapExplorationInfo says which are already shown), so
-- the whole zone is readable from level 1. Toggle with the button on the map,
-- /fo map reveal, or the key binding; unexplored pieces are tinted darker.
-- ===========================================================================
local M = FO:NewModule("Dashboard.Map", {
    account = "map",
    defaults = { settings = { nodes = true, rares = true, spawns = false, coords = true, quests = true, objectives = true, turnins = true, route = true, minSeen = 1, maxPins = 400,
                             reveal = true, revealTint = true } },
})
local print = FO:Printer("Dashboard")

local PIN_TEMPLATE = "FOMapPinTemplate"
local STYLE = {
    herb  = { tex = "Interface\\COMMON\\Indicator-Green",  label = "Herb" },
    ore   = { tex = "Interface\\COMMON\\Indicator-Yellow", label = "Ore" },
    rare  = { tex = "Interface\\COMMON\\Indicator-Red",    label = "Rare" },
    spawn = { tex = "Interface\\COMMON\\Indicator-Gray",   label = "Spawn point" },
    node  = { tex = "Interface\\COMMON\\Indicator-Green",  label = "Node" },
    quest = { tex = "Interface\\GossipFrame\\AvailableQuestIcon", label = "Quest available" },
    objective = { tex = "Interface\\GossipFrame\\IncompleteQuestIcon", label = "Objective" },
    turnin = { tex = "Interface\\GossipFrame\\ActiveQuestIcon", label = "Turn in" },
    route = { tex = "Interface\\COMMON\\Indicator-Yellow", label = "Route stop" },
}

-- ---------------------------------------------------------------------------
-- Pin
-- ---------------------------------------------------------------------------
FOMapPinMixin = CreateFromMixins and MapCanvasPinMixin and CreateFromMixins(MapCanvasPinMixin) or {}

function FOMapPinMixin:OnLoad()
    if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.2) end
    if self.UseFrameLevelType then self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI") end
    if self.CreateFontString then
        local ok, fs = pcall(self.CreateFontString, self, nil, "OVERLAY", "GameFontNormalSmall")
        if ok and fs then fs:SetPoint("CENTER", self, "CENTER", 0, 0) self.Num = fs end
    end
end

-- MapCanvasMixin:AcquirePin ends with pin:CheckMouseButtonPassthrough("RightButton"),
-- which calls the protected SetPassThroughButtons twice. Reached through addon code
-- the live client refuses it (ADDON_ACTION_FORBIDDEN "UNKNOWN()" x2 and the "blocked
-- from an action" dialog). Our pins never take clicks, so there is nothing to pass.
function FOMapPinMixin:CheckMouseButtonPassthrough() end

function FOMapPinMixin:OnAcquired(data)
    self.data = data
    -- hover for the tooltip, but let clicks (right-click zoom out) fall through to the map
    if self.SetMouseClickEnabled then pcall(self.SetMouseClickEnabled, self, false) end
    local style = STYLE[data.kind] or STYLE.node
    if self.Icon and self.Icon.SetTexture then self.Icon:SetTexture(style.tex) end
    local size = 10 + math.min(6, (data.n or 1) - 1)   -- seen more often = slightly bigger
    if data.num then size = 18 end
    if self.SetSize then self:SetSize(size, size) end
    if self.Num then
        if data.num then self.Num:SetText(tostring(data.num)) self.Num:Show() else self.Num:SetText("") self.Num:Hide() end
    end
    if self.SetAlpha then self:SetAlpha(data.kind == "spawn" and 0.7 or 1) end
    self:SetPosition(data.x, data.y)
end

function FOMapPinMixin:OnMouseEnter()
    local d = self.data
    if not d or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(d.name or "?")
    local style = STYLE[d.kind] or STYLE.node
    GameTooltip:AddLine(string.format("%s  %.1f, %.1f", style.label, d.x * 100, d.y * 100), 0.8, 0.8, 0.8)
    if d.n and not d.num then GameTooltip:AddLine(string.format("seen %d time%s", d.n, d.n == 1 and "" or "s"), 0.8, 0.8, 0.8) end
    if d.last then GameTooltip:AddLine("last " .. U.FormatDuration(math.max(0, time() - d.last)) .. " ago", 0.8, 0.8, 0.8) end
    if d.extra then GameTooltip:AddLine(d.extra, 1, 0.82, 0) end
    GameTooltip:Show()
end

function FOMapPinMixin:OnMouseLeave()
    if GameTooltip then GameTooltip:Hide() end
end

-- ---------------------------------------------------------------------------
-- Data provider: gathers everything for the displayed map
-- ---------------------------------------------------------------------------
FOMapDataProviderMixin = CreateFromMixins and MapCanvasDataProviderMixin and CreateFromMixins(MapCanvasDataProviderMixin) or nil

function M:Layers(mapID)
    local s = self.db.settings
    local FE = FO:GetModule("Grinding.FarmingEfficiency")
    local rows = {}
    if not FE or FE.disabled or not FE.db then return rows end
    if s.nodes then
        for name, node in pairs(FE.db.nodes or {}) do
            for _, p in ipairs(node.points or {}) do
                if p[1] == mapID and (p.n or 1) >= (s.minSeen or 1) then
                    rows[#rows + 1] = { kind = node.kind or "node", name = name, x = p[2], y = p[3], n = p.n or 1, last = p.last }
                end
            end
        end
    end
    if s.rares then
        for npcID, r in pairs(FE.db.rares or {}) do
            local seen = {}
            for _, sgt in ipairs(r.sightings or {}) do
                if sgt[1] == mapID then
                    local key = string.format("%.3f,%.3f", sgt[2], sgt[3])
                    local e = seen[key]
                    if e then e.n = e.n + 1 e.last = math.max(e.last or 0, sgt[4] or 0)
                    else e = { kind = "rare", name = r.name or ("npc " .. npcID), x = sgt[2], y = sgt[3], n = 1, last = sgt[4] } seen[key] = e rows[#rows + 1] = e end
                end
            end
        end
    end
    if s.spawns then
        for npcID, sp in pairs(FE.db.spawns or {}) do
            local est, kind = FE:RespawnEstimate(npcID)
            for _, p in ipairs(sp.points or {}) do
                if p[1] == mapID then
                    rows[#rows + 1] = { kind = "spawn", name = sp.name or ("npc " .. npcID), x = p[2], y = p[3], n = p.kills or p.n, last = p.lastKillT,
                                        extra = est and string.format("respawn %s (%s)", U.FormatDuration(est), kind) or "respawn unknown" }
                end
            end
        end
    end
    -- Quest layers from the quest database (QuestieDB) plus your own records
    local QDB = FO.QuestDB
    if QDB and QDB.available then
        if s.quests then
            for _, r in ipairs(QDB:AvailableOnMap(mapID)) do
                rows[#rows + 1] = { kind = "quest", name = string.format("[%d] %s", r.level, r.name), x = r.x, y = r.y, n = 50, extra = "from " .. r.giver .. (r.kind == "recorded" and " (you were here)" or "") }
            end
        end
        if s.objectives or s.turnins then
            local QT = FO:GetModule("Quest.QuestTracker")
            for _, e in ipairs(QT and QT:LogQuestIDs() or {}) do
                local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(e.id)
                if s.objectives and not complete then
                    for _, t in ipairs(QDB:ObjectiveTargets(e.id, mapID)) do
                        rows[#rows + 1] = { kind = "objective", name = e.title or ("quest " .. e.id), x = t.x, y = t.y, n = 20, extra = t.label }
                    end
                end
                if s.turnins and complete then
                    for _, t in ipairs(QDB:Finishers(e.id, mapID)) do
                        rows[#rows + 1] = { kind = "turnin", name = e.title or ("quest " .. e.id), x = t.x, y = t.y, n = 60, extra = "turn in to " .. t.label }
                    end
                end
            end
        end
    end
    -- Numbered stops of the planned quest route (/fo route)
    local R = FO.Router
    if s.route ~= false and R and R.plan and R.plan.mapID == mapID then
        for _, st in ipairs(R.plan.stops) do
            rows[#rows + 1] = { kind = "route", name = string.format("%d. %s", st.num, st.label), x = st.x, y = st.y, n = 100, num = st.num,
                                extra = string.format("%s, +%.0f yd%s", st.kind == "objective" and "objectives" or st.kind == "turnin" and "turn in" or "pick up", st.leg or 0, R.following and R.current and R.current.key == st.key and " (arrow)" or "") }
        end
    end
    table.sort(rows, function(a, b) return (a.n or 1) > (b.n or 1) end)
    for i = #rows, (s.maxPins or 400) + 1, -1 do rows[i] = nil end
    return rows
end

if FOMapDataProviderMixin then
    function FOMapDataProviderMixin:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
    end
    function FOMapDataProviderMixin:RefreshAllData()
        self:RemoveAllData()
        if M.disabled then return end
        local mapID = self:GetMap():GetMapID()
        if not mapID then return end
        local rows = M:Layers(mapID)
        for _, row in ipairs(rows) do self:GetMap():AcquirePin(PIN_TEMPLATE, row) end
        M.lastPins, M.lastMap = #rows, mapID
    end
end

-- ---------------------------------------------------------------------------
-- Reveal: unexplored map art. One full-canvas pin per map; the overlays the
-- client has not revealed are tiled onto it exactly the way Blizzard's own
-- exploration pin tiles the revealed ones (256x256 files, power-of-two edges).
-- ---------------------------------------------------------------------------
local REVEAL_TEMPLATE = "FOMapRevealPinTemplate"
local TINT = 0.62

FOMapRevealPinMixin = CreateFromMixins and MapCanvasPinMixin and CreateFromMixins(MapCanvasPinMixin) or {}

function FOMapRevealPinMixin:OnLoad()
    if self.SetIgnoreGlobalPinScale then pcall(self.SetIgnoreGlobalPinScale, self, true) end
    if self.UseFrameLevelType then
        if not pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_MAP_EXPLORATION") then pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_DEFAULT") end
    end
    -- art only: never take clicks or hover away from the map and the pins above
    if self.EnableMouse then pcall(self.EnableMouse, self, false) end
    if self.SetMouseClickEnabled then pcall(self.SetMouseClickEnabled, self, false) end
    if self.SetMouseMotionEnabled then pcall(self.SetMouseMotionEnabled, self, false) end
    self.textures, self.used = {}, 0
end

function FOMapRevealPinMixin:OnAcquired() end
function FOMapRevealPinMixin:CheckMouseButtonPassthrough() end   -- see FOMapPinMixin

function FOMapRevealPinMixin:OnCanvasSizeChanged()
    local map = self.GetMap and self:GetMap()
    if map and map.DenormalizeHorizontalSize and map.DenormalizeVerticalSize then
        pcall(self.SetSize, self, map:DenormalizeHorizontalSize(1), map:DenormalizeVerticalSize(1))
    end
end

function FOMapRevealPinMixin:AcquireTexture()
    self.used = self.used + 1
    local t = self.textures[self.used]
    if not t then t = self:CreateTexture(nil, "ARTWORK", nil, -1) self.textures[self.used] = t end
    return t
end

function FOMapRevealPinMixin:ReleaseAll()
    for i = 1, self.used do self.textures[i]:Hide() end
    self.used = 0
end

local function LastEdge(size, tile, index, count)
    -- pixel size and file size of tile `index` of `count` along one axis
    if index < count then return tile, tile end
    local px = size % tile
    if px == 0 then px = tile end
    local file = 16
    while file < px do file = file * 2 end
    return px, file
end

function FOMapRevealPinMixin:Refresh()
    self:ReleaseAll()
    M.revealCount = 0
    local map = self.GetMap and self:GetMap()
    local okID, mapID = pcall(function() return U.Num(map:GetMapID()) end)
    if not okID then mapID = nil end
    local s = M.db and M.db.settings
    if not (mapID and s and s.reveal) then return end
    local list = FO.Seed and FO.Seed.mapOverlays and FO.Seed.mapOverlays[mapID]
    if not list then return end
    self:OnCanvasSizeChanged()
    -- tile size of the art layer on screen (zone maps: 256x256). Every call into the
    -- map canvas or the exploration API is guarded: the live client errored inside
    -- MapCanvas_ScrollContainerMixin on the first map open, and a failure here should
    -- cost the layer lookup, not the whole draw.
    local tw, th = 256, 256
    local layerIndex = 1
    pcall(function()
        local cc = map.GetCanvasContainer and map:GetCanvasContainer()
        if cc and cc.GetCurrentLayerIndex then layerIndex = U.Num(cc:GetCurrentLayerIndex()) or 1 end
    end)
    local okL, layers = pcall(function() return C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID) end)
    local li = okL and type(layers) == "table" and (layers[layerIndex] or layers[1])
    if type(li) == "table" then tw, th = U.Num(li.tileWidth) or tw, U.Num(li.tileHeight) or th end
    -- what the client already shows, keyed the same way as the seed rows
    local explored = {}
    local okE, ex = pcall(function() return C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures and C_MapExplorationInfo.GetExploredMapTextures(mapID) end)
    if not okE then ex = nil end
    for _, e in ipairs(type(ex) == "table" and ex or {}) do
        local w, h, x, y = U.Num(e.textureWidth), U.Num(e.textureHeight), U.Num(e.offsetX), U.Num(e.offsetY)
        if w and h and x and y then explored[string.format("%d:%d:%d:%d", w, h, x, y)] = true end
    end
    local shade = s.revealTint and TINT or 1
    local drawn = 0
    for _, o in ipairs(list) do
        local w, h, x, y, files = o[1], o[2], o[3], o[4], o[5]
        if not explored[string.format("%d:%d:%d:%d", w, h, x, y)] then
            local wide, tall = math.ceil(w / tw), math.ceil(h / th)
            for j = 1, tall do
                local ph, fh = LastEdge(h, th, j, tall)
                for k = 1, wide do
                    local pw, fw = LastEdge(w, tw, k, wide)
                    local file = files[(j - 1) * wide + k]
                    if file then
                        local t = self:AcquireTexture()
                        t:SetSize(pw, ph)
                        t:SetTexCoord(0, pw / fw, 0, ph / fh)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", self, "TOPLEFT", x + tw * (k - 1), -(y + th * (j - 1)))
                        t:SetTexture(file, nil, nil, "TRILINEAR")
                        t:SetVertexColor(shade, shade, shade)
                        t:Show()
                        drawn = drawn + 1
                    end
                end
            end
        end
    end
    M.revealCount, M.revealMap = drawn, mapID
end

FOMapRevealProviderMixin = CreateFromMixins and MapCanvasDataProviderMixin and CreateFromMixins(MapCanvasDataProviderMixin) or nil

if FOMapRevealProviderMixin then
    function FOMapRevealProviderMixin:OnAdded(map)
        if MapCanvasDataProviderMixin.OnAdded then MapCanvasDataProviderMixin.OnAdded(self, map) end
        self.owningMap = self.owningMap or map
        self.pin = map:AcquirePin(REVEAL_TEMPLATE)
        if self.pin.SetPosition then self.pin:SetPosition(0.5, 0.5) end
        if self.pin.Show then self.pin:Show() end
        if self.RegisterEvent then pcall(self.RegisterEvent, self, "MAP_EXPLORATION_UPDATED") end
    end
    function FOMapRevealProviderMixin:RemoveAllData() if self.pin then self.pin:ReleaseAll() end end
    function FOMapRevealProviderMixin:RefreshAllData() if self.pin then FO.Try("Dashboard.Map reveal", self.pin.Refresh, self.pin) end end
    function FOMapRevealProviderMixin:OnMapChanged() self:RefreshAllData() end
    function FOMapRevealProviderMixin:OnEvent(event) if event == "MAP_EXPLORATION_UPDATED" then self:RefreshAllData() end end
end

function M:RefreshReveal()
    if self.revealProvider then self.revealProvider:RefreshAllData() end
    if self.revealButton then self.revealButton:SetText(self.db.settings.reveal and "Explored only" or "Full map") end
end

function M:ToggleReveal(on)
    local s = self.db.settings
    if on == nil then s.reveal = not s.reveal else s.reveal = on end
    self:RefreshReveal()
    print("unexplored map art %s", s.reveal and "|cff80ff80shown|r" or "|cffff6060hidden|r")
end

function ForeverOptimizer_ToggleReveal() if not M.disabled and M.db then M:ToggleReveal() end end

-- ---------------------------------------------------------------------------
-- Coordinates text on the map
-- ---------------------------------------------------------------------------
local function MapShown() return WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown() end

function M:UpdateCoords()
    local fs = self.coordText
    if not fs then return end
    if not self.db.settings.coords or not MapShown() then fs:Hide() return end
    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local player = "--"
    if mapID and C_Map and C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        local x, y = pos and pos:GetXY()
        x, y = U.Num(x), U.Num(y)
        if x and y and (x > 0 or y > 0) then player = string.format("%.1f, %.1f", x * 100, y * 100) end
    end
    local cursor = "--"
    local sc = WorldMapFrame.ScrollContainer
    local getter = (sc and sc.GetNormalizedCursorPosition and sc) or (WorldMapFrame.GetNormalizedCursorPosition and WorldMapFrame)
    if getter then
        local okC, cx, cy = pcall(getter.GetNormalizedCursorPosition, getter)
        cx, cy = okC and U.Num(cx), okC and U.Num(cy)
        if cx and cy and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then cursor = string.format("%.1f, %.1f", cx * 100, cy * 100) end
    end
    fs:SetText(string.format("|cffffd100Player|r %s   |cffffd100Cursor|r %s%s", player, cursor,
        self.lastPins and self.lastPins > 0 and string.format("   |cffaaaaaa%d pins|r", self.lastPins) or ""))
    fs:Show()
end

function M:OnEnable()
    self.available = false
    if not WorldMapFrame then self.reason = "no WorldMapFrame" return end
    -- Pins
    if FOMapDataProviderMixin and WorldMapFrame.AddDataProvider then
        local ok, err = pcall(function()
            self.provider = CreateFromMixins(FOMapDataProviderMixin)
            WorldMapFrame:AddDataProvider(self.provider)
        end)
        if ok then self.available = true else self.reason = tostring(err) end
    else
        self.reason = "map data-provider API missing"
    end
    -- Unexplored map art
    if FOMapRevealProviderMixin and WorldMapFrame.AddDataProvider and FO.Seed and FO.Seed.mapOverlays then
        local ok, err = pcall(function()
            self.revealProvider = CreateFromMixins(FOMapRevealProviderMixin)
            WorldMapFrame:AddDataProvider(self.revealProvider)
        end)
        if not ok then self.revealProvider, self.revealReason = nil, tostring(err) end
    else
        self.revealReason = FO.Seed and FO.Seed.mapOverlays and "map data-provider API missing" or "no overlay seed"
    end
    -- Our own widgets live on a frame levelled above the pins so the map art never covers them
    local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
    local okTop, top = pcall(function()
        local f = CreateFrame("Frame", nil, parent)
        f:SetAllPoints(parent)
        if f.SetFrameLevel and parent.GetFrameLevel then pcall(f.SetFrameLevel, f, (parent:GetFrameLevel() or 0) + 4000) end
        return f
    end)
    if not okTop then top = parent end
    self.topFrame = top
    local ok, fs = pcall(function()
        local f = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", 8, 6)
        f:SetJustifyH("LEFT")
        return f
    end)
    local okBtn, btn = pcall(function()
        local b = CreateFrame("Button", nil, top, "UIPanelButtonTemplate")
        b:SetSize(104, 20)
        b:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", -8, 6)
        b:SetScript("OnClick", function() M:ToggleReveal() end)
        b:SetScript("OnEnter", function(bf)
            if not GameTooltip then return end
            GameTooltip:SetOwner(bf, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Unexplored map art")
            GameTooltip:AddLine("Shows the whole zone before you have walked it; unexplored parts are darker. Also /fo map reveal and the key binding.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        return b
    end)
    if okBtn and btn and btn.SetText then self.revealButton = btn self:RefreshReveal() end
    if ok and fs then
        self.coordText = fs
        local upd = CreateFrame("Frame")
        upd.elapsed = 0
        upd:SetScript("OnUpdate", function(_, dt)
            upd.elapsed = upd.elapsed + (dt or 0)
            if upd.elapsed < 0.1 then return end
            upd.elapsed = 0
            if MapShown() then M:UpdateCoords() end
        end)
        self.updater = upd
    end
    if WorldMapFrame.HookScript then
        pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnShow", function() M.dirty = true M:UpdateCoords() FO:Fire("FO_MAP_SHOWN") end)
        pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnHide", function() if M.coordText then M.coordText:Hide() end end)
    end
end

-- Refresh pins while the map is open and new data arrived (cheap: once per second at most)
function M:OnTick()
    if self.dirty and self.provider and MapShown() then
        self.dirty = false
        FO.Try("Dashboard.Map refresh", self.provider.RefreshAllData, self.provider)
    end
end

M.messages = {
    FO_NODE = function(self) self.dirty = true end,
    FO_RARE = function(self) self.dirty = true end,
    FO_KILL = function(self) if self.db.settings.spawns then self.dirty = true end end,
    FO_ROUTE_PLANNED = function(self) self.dirty = true end,
}

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------
local function Coords()
    local mapID, x, y = U.PlayerPosition()
    local zone, sub = U.ZoneName()
    if not x then return zone, sub, mapID, nil end
    return zone, sub, mapID, string.format("%.1f, %.1f", x * 100, y * 100)
end

M.commands = {
    coords = {
        help = "Your current map coordinates",
        fn = function()
            local zone, sub, mapID, c = Coords()
            if not c then print("%s%s: position unavailable here (map %s)", zone, sub ~= "" and (" / " .. sub) or "", tostring(mapID)) return end
            print("%s%s  |cffffd100%s|r  (map %d)", zone, sub ~= "" and (" / " .. sub) or "", c, mapID or 0)
        end,
    },
    map = {
        help = "World map overlay: status | reveal|tint on|off (unexplored art) | nodes|rares|spawns|quests|objectives|turnins|coords on|off | minseen <n> | refresh",
        fn = function(self, arg)
            local s = self.db.settings
            local sub, rest = U.SplitCmd(arg or "")
            if sub == "reveal" or sub == "tint" then
                local key = sub == "reveal" and "reveal" or "revealTint"
                if rest == "on" or rest == "off" then s[key] = (rest == "on") else s[key] = not s[key] end
                self:RefreshReveal()
                if sub == "reveal" then print("unexplored map art %s", s.reveal and "|cff80ff80shown|r" or "|cffff6060hidden|r")
                else print("unexplored tint %s", s.revealTint and "|cff80ff80on|r (darker)" or "|cffff6060off|r (same as explored)") end
                return
            elseif sub == "nodes" or sub == "rares" or sub == "spawns" or sub == "coords" or sub == "quests" or sub == "objectives" or sub == "turnins" then
                if rest == "on" or rest == "off" then s[sub] = (rest == "on") else s[sub] = not s[sub] end
                self.dirty = true
                print("%s layer %s", sub, s[sub] and "|cff80ff80on|r" or "|cffff6060off|r")
                if sub == "coords" then self:UpdateCoords() end
                return
            elseif sub == "minseen" then
                s.minSeen = math.max(1, math.floor(tonumber(rest) or 1))
                self.dirty = true
                print("showing nodes seen at least %d time%s", s.minSeen, s.minSeen == 1 and "" or "s")
                return
            elseif sub == "refresh" then
                if self.provider then FO.Try("Dashboard.Map refresh", self.provider.RefreshAllData, self.provider) print("refreshed (%d pins)", self.lastPins or 0)
                else print("pins unavailable: %s", tostring(self.reason)) end
                return
            end
            local mapID = U.PlayerPosition()
            local rows = mapID and self:Layers(mapID) or {}
            local kinds = {}
            for _, r in ipairs(rows) do kinds[r.kind] = (kinds[r.kind] or 0) + 1 end
            print("world map overlay: pins %s, coords %s", self.available and "|cff80ff80available|r" or ("|cffff6060unavailable|r (" .. tostring(self.reason) .. ")"), s.coords and "on" or "off")
            print("layers: nodes %s, rares %s, spawns %s, quests %s, objectives %s, turnins %s, min seen %d", s.nodes and "on" or "off", s.rares and "on" or "off", s.spawns and "on" or "off", s.quests and "on" or "off", s.objectives and "on" or "off", s.turnins and "on" or "off", s.minSeen or 1)
            if not (FO.QuestDB and FO.QuestDB.available) then print("quest layers need QuestieDB: %s", tostring(FO.QuestDB and FO.QuestDB.reason)) end
            local nMaps = 0
            for _ in pairs(FO.Seed and FO.Seed.mapOverlays or {}) do nMaps = nMaps + 1 end
            print("unexplored art: %s, tint %s, seed %s (%d maps)%s", s.reveal and "|cff80ff80shown|r" or "|cffff6060hidden|r", s.revealTint and "on" or "off",
                tostring(FO.Seed and FO.Seed.mapOverlayBuild or "?"), nMaps,
                self.revealProvider and (self.revealCount and string.format(", %d pieces drawn on the last map", self.revealCount) or "")
                    or (" |cffff6060unavailable|r (" .. tostring(self.revealReason) .. ")"))
            local parts = {}
            for k, n in pairs(kinds) do parts[#parts + 1] = string.format("%d %s", n, (STYLE[k] or STYLE.node).label:lower()) end
            table.sort(parts)
            print("this map (%s): %s", U.ZoneName(), #parts > 0 and table.concat(parts, ", ") or "nothing recorded yet")
        end,
    },
}
