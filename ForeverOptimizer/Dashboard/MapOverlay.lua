local ADDON, FO = ...
local U = FO.Util

-- ===========================================================================
-- World map overlay: player + cursor coordinates on the map, and pins for
-- everything the addon has recorded with a position: gathering nodes (herb /
-- ore, from Grinding.FarmingEfficiency), rare sightings, and mob spawn points
-- with their respawn estimate. Uses the map's own data-provider API so pins
-- scale and layer like Blizzard's; if that API is missing on this client the
-- module degrades to coordinates only and says so in /fo map.
-- ===========================================================================
local M = FO:NewModule("Dashboard.Map", {
    account = "map",
    defaults = { settings = { nodes = true, rares = true, spawns = false, coords = true, quests = true, objectives = true, turnins = true, minSeen = 1, maxPins = 400 } },
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
}

-- ---------------------------------------------------------------------------
-- Pin
-- ---------------------------------------------------------------------------
FOMapPinMixin = CreateFromMixins and MapCanvasPinMixin and CreateFromMixins(MapCanvasPinMixin) or {}

function FOMapPinMixin:OnLoad()
    if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.2) end
    if self.UseFrameLevelType then self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI") end
end

function FOMapPinMixin:OnAcquired(data)
    self.data = data
    local style = STYLE[data.kind] or STYLE.node
    if self.Icon and self.Icon.SetTexture then self.Icon:SetTexture(style.tex) end
    local size = 10 + math.min(6, (data.n or 1) - 1)   -- seen more often = slightly bigger
    if self.SetSize then self:SetSize(size, size) end
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
    if d.n then GameTooltip:AddLine(string.format("seen %d time%s", d.n, d.n == 1 and "" or "s"), 0.8, 0.8, 0.8) end
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
        local cx, cy = getter:GetNormalizedCursorPosition()
        cx, cy = U.Num(cx), U.Num(cy)
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
    -- Coordinates
    local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
    local ok, fs = pcall(function()
        local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 6)
        f:SetJustifyH("LEFT")
        return f
    end)
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
        pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnShow", function() M.dirty = true M:UpdateCoords() end)
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
        help = "World map overlay: status | nodes|rares|spawns|quests|objectives|turnins|coords on|off | minseen <n> | refresh",
        fn = function(self, arg)
            local s = self.db.settings
            local sub, rest = U.SplitCmd(arg or "")
            if sub == "nodes" or sub == "rares" or sub == "spawns" or sub == "coords" or sub == "quests" or sub == "objectives" or sub == "turnins" then
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
            local parts = {}
            for k, n in pairs(kinds) do parts[#parts + 1] = string.format("%d %s", n, (STYLE[k] or STYLE.node).label:lower()) end
            table.sort(parts)
            print("this map (%s): %s", U.ZoneName(), #parts > 0 and table.concat(parts, ", ") or "nothing recorded yet")
        end,
    },
}
