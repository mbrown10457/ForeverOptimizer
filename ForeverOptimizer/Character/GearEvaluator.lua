local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Character")

-- ===========================================================================
-- Is this an upgrade? Weighted stat score vs what you're wearing in that
-- slot. Weights are per class for leveling; class modules can override.
-- Shows a line on item tooltips when the tooltip API allows it.
-- ===========================================================================
local GE = FO:NewModule("Character.GearEvaluator", {
    char = "gear",
    cdefaults = { weights = nil },   -- user overrides, nil = class default
})

-- Leveling weights (per point). Deliberately simple; tune with /fo weights set.
FO.StatWeights = {
    DEFAULT = { ITEM_MOD_STAMINA_SHORT = 0.6, ITEM_MOD_STRENGTH_SHORT = 0.5, ITEM_MOD_AGILITY_SHORT = 0.5, ITEM_MOD_INTELLECT_SHORT = 0.3,
                ITEM_MOD_SPIRIT_SHORT = 0.3, ITEM_MOD_ATTACK_POWER_SHORT = 0.25, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 3.0, RESISTANCE0_NAME = 0.02 },
    WARRIOR = { ITEM_MOD_STRENGTH_SHORT = 1.0, ITEM_MOD_STAMINA_SHORT = 0.7, ITEM_MOD_AGILITY_SHORT = 0.6, ITEM_MOD_ATTACK_POWER_SHORT = 0.5,
                ITEM_MOD_CRIT_RATING_SHORT = 0.8, ITEM_MOD_HIT_RATING_SHORT = 1.0, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 4.0, RESISTANCE0_NAME = 0.03 },
    PALADIN = { ITEM_MOD_STRENGTH_SHORT = 0.9, ITEM_MOD_STAMINA_SHORT = 0.7, ITEM_MOD_INTELLECT_SHORT = 0.5, ITEM_MOD_SPIRIT_SHORT = 0.2,
                ITEM_MOD_ATTACK_POWER_SHORT = 0.45, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 4.0, RESISTANCE0_NAME = 0.03 },
    HUNTER = { ITEM_MOD_AGILITY_SHORT = 1.0, ITEM_MOD_STAMINA_SHORT = 0.5, ITEM_MOD_INTELLECT_SHORT = 0.4, ITEM_MOD_SPIRIT_SHORT = 0.1,
               ITEM_MOD_ATTACK_POWER_SHORT = 0.45, ITEM_MOD_RANGED_ATTACK_POWER_SHORT = 0.5, ITEM_MOD_CRIT_RATING_SHORT = 0.8,
               ITEM_MOD_HIT_RATING_SHORT = 1.0, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 1.5, RESISTANCE0_NAME = 0.01 },
    ROGUE = { ITEM_MOD_AGILITY_SHORT = 1.0, ITEM_MOD_STRENGTH_SHORT = 0.5, ITEM_MOD_STAMINA_SHORT = 0.5, ITEM_MOD_ATTACK_POWER_SHORT = 0.5,
              ITEM_MOD_CRIT_RATING_SHORT = 0.9, ITEM_MOD_HIT_RATING_SHORT = 1.1, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 4.0, RESISTANCE0_NAME = 0.01 },
    PRIEST = { ITEM_MOD_SPIRIT_SHORT = 0.9, ITEM_MOD_INTELLECT_SHORT = 0.8, ITEM_MOD_STAMINA_SHORT = 0.5, ITEM_MOD_SPELL_POWER_SHORT = 1.0,
               ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 1.0, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 0.4, ITEM_MOD_POWER_REGEN0_SHORT = 2.0, RESISTANCE0_NAME = 0.005 },
    SHAMAN = { ITEM_MOD_INTELLECT_SHORT = 0.7, ITEM_MOD_STRENGTH_SHORT = 0.6, ITEM_MOD_STAMINA_SHORT = 0.6, ITEM_MOD_AGILITY_SHORT = 0.4,
               ITEM_MOD_SPIRIT_SHORT = 0.3, ITEM_MOD_ATTACK_POWER_SHORT = 0.3, ITEM_MOD_SPELL_POWER_SHORT = 0.6, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 3.5, RESISTANCE0_NAME = 0.02 },
    MAGE = { ITEM_MOD_INTELLECT_SHORT = 1.0, ITEM_MOD_SPIRIT_SHORT = 0.6, ITEM_MOD_STAMINA_SHORT = 0.5, ITEM_MOD_SPELL_POWER_SHORT = 1.0,
             ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 1.0, ITEM_MOD_CRIT_RATING_SHORT = 0.7, ITEM_MOD_POWER_REGEN0_SHORT = 1.5, RESISTANCE0_NAME = 0.005 },
    WARLOCK = { ITEM_MOD_STAMINA_SHORT = 0.8, ITEM_MOD_INTELLECT_SHORT = 0.8, ITEM_MOD_SPIRIT_SHORT = 0.5, ITEM_MOD_SPELL_POWER_SHORT = 1.0,
                ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 1.0, ITEM_MOD_POWER_REGEN0_SHORT = 1.0, RESISTANCE0_NAME = 0.005 },
    DRUID = { ITEM_MOD_INTELLECT_SHORT = 0.6, ITEM_MOD_SPIRIT_SHORT = 0.5, ITEM_MOD_STAMINA_SHORT = 0.6, ITEM_MOD_AGILITY_SHORT = 0.6,
              ITEM_MOD_STRENGTH_SHORT = 0.5, ITEM_MOD_ATTACK_POWER_SHORT = 0.3, ITEM_MOD_SPELL_POWER_SHORT = 0.6, RESISTANCE0_NAME = 0.02 },
}

local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18, 16 }, INVTYPE_RANGEDRIGHT = { 18, 16 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

function GE:Weights()
    if self.cdb.weights then return self.cdb.weights end
    local cls = FO.Player.class
    local classMod = FO.Classes and FO.Classes[cls]
    if classMod and classMod.weights then return classMod.weights end
    return FO.StatWeights[cls] or FO.StatWeights.DEFAULT
end

local function Stats(link)
    local GIS = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
    if not GIS or not link then return nil end
    local ok, t = pcall(GIS, link)
    if not ok or type(t) ~= "table" then return nil end
    return t
end

function GE:Score(link)
    local st = Stats(link)
    if not st then return nil end
    local w = self:Weights()
    local score, parts = 0, {}
    for key, v in pairs(st) do
        v = U.Num(v)
        local wt = w[key]
        if v and wt then score = score + v * wt parts[#parts + 1] = string.format("%s%+g", key:gsub("ITEM_MOD_", ""):gsub("_SHORT", ""):lower(), v) end
    end
    return score, parts
end

-- Compare to the weakest equipped item that this item could replace
function GE:Compare(link)
    local itemID = U.ItemIDFromLink(link)
    if not itemID then return nil end
    local _, _, equipLoc = U.ItemInstant(itemID)
    local slots = equipLoc and SLOTS[equipLoc]
    if not slots then return nil end
    local score = self:Score(link)
    if not score then return nil end
    local worst, worstLink
    for _, slot in ipairs(slots) do
        local eq = GetInventoryItemLink("player", slot)
        local s = eq and self:Score(eq) or 0
        if not worst or s < worst then worst, worstLink = s, eq end
    end
    worst = worst or 0
    local delta = score - worst
    local pct = worst > 0 and delta / worst * 100 or (score > 0 and 100 or 0)
    return { score = score, equipped = worst, equippedLink = worstLink, delta = delta, pct = pct, equipLoc = equipLoc }
end

-- Tooltip line
local function Hook()
    if not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall or not Enum or not Enum.TooltipDataType then return false end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        if not tooltip.GetItem then return end
        local _, link = tooltip:GetItem()
        if not link then return end
        local c = GE:Compare(link)
        if not c then return end
        local color = c.delta > 0 and "|cff60ff60" or c.delta < 0 and "|cffff6060" or "|cffaaaaaa"
        tooltip:AddLine(string.format("FO: %.1f vs equipped %.1f  %s%+.0f%%|r", c.score, c.equipped, color, c.pct))
    end)
    return true
end

function GE:OnEnable()
    if not Hook() then print("tooltip API not available; use /fo gear <link>.") end
end

GE.commands = {
    gear = { help = "<item link> — upgrade score vs equipped", fn = function(self, arg)
        local link = arg:match("|H(item:[^|]+)|h") and arg or nil
        if not link then
            local id = tonumber(arg)
            if id then local _, _, _, _, _, _, _, l = U.ItemInfo(id) link = l end
        end
        if not link then print("usage: /fo gear <shift-click an item>") return end
        local c = self:Compare(link)
        if not c then print("can't score that (no stats, or not equippable).") return end
        local _, parts = self:Score(link)
        print("%s: %.1f vs equipped %.1f (%+.0f%%)  [%s]", link, c.score, c.equipped, c.pct, table.concat(parts, " "))
        if c.equippedLink then print("  replaces %s", c.equippedLink) end
    end },
    weights = { help = "[set <STAT> <n> | reset] — stat weights for your class", fn = function(self, arg)
        local sub, rest = U.SplitCmd(arg)
        if sub == "reset" then self.cdb.weights = nil print("weights reset to class default.") return end
        if sub == "set" then
            local stat, n = rest:match("^(%S+)%s+(%S+)$")
            n = tonumber(n)
            if not stat or not n then print("usage: /fo weights set ITEM_MOD_AGILITY_SHORT 1.0") return end
            if not self.cdb.weights then self.cdb.weights = {} for k, v in pairs(self:Weights()) do self.cdb.weights[k] = v end end
            self.cdb.weights[stat:upper()] = n
            print("%s = %g", stat:upper(), n)
            return
        end
        print("Stat weights for %s%s:", FO.Player.classLocal, self.cdb.weights and " (custom)" or "")
        local w = self:Weights()
        for _, k in ipairs(U.Keys(w)) do print("  %-40s %g", k, w[k]) end
    end },
}
