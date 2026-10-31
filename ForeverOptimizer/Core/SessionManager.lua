local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Core")

-- ===========================================================================
-- The unified session. Every second it decides what you are doing
-- (activity), banks that second, and attributes XP / gold / kills to it.
--
-- Activities:
--   quest   productive: an objective ticked recently
--   grind   productive: fighting with no quest involvement
--   dungeon productive: inside an instance
--   travel  moving for a while with no fighting, or on a flight path
--   rest    eating / drinking
--   town    a vendor / trainer / AH / mail / bank / trade window is open
--   dead    dead or ghost (corpse run)
--   idle    none of the above
--
-- Other modules read FO.Session:Live() / :Stats() and listen to FO_* messages.
-- ===========================================================================
local SM = FO:NewModule("Core.SessionManager", {
    account = "sessions",
    defaults = { list = {}, dungeons = {}, settings = {
        questWindow = 120,        -- s after an objective tick that still counts as questing
        combatWindow = 15,        -- s after combat/kill/loot that still counts as fighting
        travelAfter = 12,         -- s of continuous movement before we call it travel
        restAuras = { "Food", "Drink", "Refreshment", "Well Fed" },
        valuableDrop = 10000,     -- 1g: drops above this are listed per dungeon run
        maxSessions = 300, maxDungeons = 200,
    } },
})
FO.Session = SM

local ACTIVITIES = { "quest", "grind", "dungeon", "travel", "rest", "town", "dead", "idle" }
local PRODUCTIVE = { quest = true, grind = true, dungeon = true }
SM.ACTIVITIES, SM.PRODUCTIVE = ACTIVITIES, PRODUCTIVE

local S -- live session

local function ZeroByActivity()
    local t = {}
    for _, a in ipairs(ACTIVITIES) do t[a] = 0 end
    return t
end

local function NewZoneBucket()
    return { time = ZeroByActivity(), xp = 0, kills = 0, gold = 0, lootGold = 0, ahEst = 0, vendorEst = 0, deaths = 0 }
end

local function NewSession()
    local zone = U.ZoneName()
    return {
        char = FO.charKey, class = FO.Player.class, level = FO.Player.level,
        start = time(), startGT = GetTime(), stop = nil,
        zone = zone,
        activity = "idle", activitySince = GetTime(), lastProductive = "grind",
        time = ZeroByActivity(),
        xpBy = ZeroByActivity(), killsBy = ZeroByActivity(), goldBy = ZeroByActivity(),

        xp = 0, questXP = 0, killXP = 0, kills = 0,
        gold = 0, lootGold = 0, questGold = 0, vendorSales = 0, repairs = 0, purchases = 0,
        training = 0, ahSpend = 0, mailIn = 0, mailOut = 0, transfers = 0, otherGold = 0, taxi = 0, questsDone = 0,
        ahEst = 0, vendorEst = 0, items = 0, consumables = 0,
        deaths = 0, deathTime = 0, corpseRuns = {},
        zones = { [zone] = NewZoneBucket() },

        -- internals
        lastXP = U.Num(UnitXP("player")), lastXPMax = U.Num(UnitXPMax("player")),
        lastMoney = U.Num(GetMoney()),
        lastCombat = 0, lastObjective = 0, lastQuestTurnIn = 0, movingSince = nil,
        repairCost = 0, expectRepair = nil, deathStart = nil,
        pausedAt = nil, pausedTotal = 0,
        dungeon = nil, -- live dungeon run
    }
end

local function Zone()
    local z = S.zones[S.zone]
    if not z then z = NewZoneBucket() S.zones[S.zone] = z end
    return z
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function SM:Start()
    S = NewSession()
    self.live = S
    FO:Fire("FO_SESSION_START", S)
end

function SM:Live() return S end

function SM:Elapsed()
    if not S then return 0 end
    local paused = S.pausedTotal + (S.pausedAt and (GetTime() - S.pausedAt) or 0)
    return (GetTime() - S.startGT) - paused
end

function SM:ProductiveTime()
    if not S then return 0 end
    return S.time.quest + S.time.grind + S.time.dungeon
end

local function Archive()
    if not S then return end
    S.stop = time()
    if S.xp == 0 and S.kills == 0 and S.items == 0 and S.gold == 0 and SM:Elapsed() < 300 then return end
    local rec = {
        char = S.char, class = S.class, level = S.level, start = S.start, stop = S.stop,
        elapsed = math.floor(SM:Elapsed()), zone = S.zone,
        time = S.time, xpBy = S.xpBy, killsBy = S.killsBy, goldBy = S.goldBy,
        xp = S.xp, questXP = S.questXP, killXP = S.killXP, kills = S.kills,
        gold = S.gold, lootGold = S.lootGold, questGold = S.questGold, vendorSales = S.vendorSales, repairs = S.repairs,
        purchases = S.purchases, training = S.training, ahSpend = S.ahSpend, mailIn = S.mailIn, mailOut = S.mailOut,
        ahEst = S.ahEst, vendorEst = S.vendorEst, items = S.items, consumables = S.consumables, taxi = S.taxi,
        deaths = S.deaths, deathTime = S.deathTime, zones = S.zones, questsDone = S.questsDone,
    }
    U.Push(SM.db.list, rec, SM.db.settings.maxSessions)
    FO:Fire("FO_SESSION_END", rec)
end

function SM:Reset()
    Archive()
    self:Start()
    print("session reset.")
end

function SM:OnLogout() Archive() end

function SM:TogglePause()
    if not S then return end
    if S.pausedAt then
        S.pausedTotal = S.pausedTotal + (GetTime() - S.pausedAt)
        S.pausedAt = nil
        print("resumed.")
    else
        S.pausedAt = GetTime()
        print("paused.")
    end
end

-- ---------------------------------------------------------------------------
-- Activity detection
-- ---------------------------------------------------------------------------
local function IsResting()
    local pats = SM.db.settings.restAuras
    for _, name in ipairs(U.PlayerBuffNames()) do
        for _, p in ipairs(pats) do
            if name == p or name:find("^" .. p) then return true end
        end
    end
    return false
end

local function DetectActivity(now)
    local st = SM.db.settings
    if UnitIsDeadOrGhost("player") then return "dead" end
    if FO:AnyTownFrame() then return "town" end
    if UnitOnTaxi and UnitOnTaxi("player") then return "travel" end
    local inInst = U.InInstance()
    if inInst then return "dungeon" end
    local fighting = InCombatLockdown() or (now - S.lastCombat) < st.combatWindow
    if not fighting and IsResting() then return "rest" end
    if fighting then
        if (now - S.lastObjective) < st.questWindow then return "quest" end
        return "grind"
    end
    -- not fighting, not resting
    local speed = U.Num(GetUnitSpeed and GetUnitSpeed("player")) or 0
    if speed > 0 then
        S.movingSince = S.movingSince or now
        if (now - S.movingSince) >= st.travelAfter then return "travel" end
    else
        S.movingSince = nil
    end
    -- short gaps between pulls still count toward whatever we were doing
    if (now - S.lastCombat) < 45 then return S.lastProductive end
    if (now - S.lastObjective) < 30 then return "quest" end
    return "idle"
end

local function SetActivity(new, now)
    local old = S.activity
    if new == old then return end
    local dur = now - S.activitySince
    S.activity, S.activitySince = new, now
    if PRODUCTIVE[new] then S.lastProductive = new end
    FO:Fire("FO_ACTIVITY", new, old, dur)
end

function SM:OnTick(now)
    if not S or S.pausedAt then return end
    SetActivity(DetectActivity(now), now)
    local a = S.activity
    S.time[a] = S.time[a] + 1
    Zone().time[a] = Zone().time[a] + 1
    if S.dungeon then S.dungeon.seconds = S.dungeon.seconds + 1 end
end

function SM:Activity() return S and S.activity or "idle" end
function SM:ProductiveActivity() return S and (PRODUCTIVE[S.activity] and S.activity or S.lastProductive) or "grind" end
function SM:Force(activity)
    -- manual override: pretend an objective tick (quest) or clear it (grind)
    if activity == "quest" then S.lastObjective = GetTime() + 3600
    elseif activity == "grind" then S.lastObjective = 0
    else print("force: quest | grind") return end
    print("activity forced to %s for this session (until /fo session force auto).", activity)
end

-- ---------------------------------------------------------------------------
-- XP
-- ---------------------------------------------------------------------------
local function OnXPUpdate()
    if not S then return end
    local xp, xpMax = U.Num(UnitXP("player")), U.Num(UnitXPMax("player"))
    if not xp or not xpMax then return end
    if S.lastXP then
        local delta
        if xp >= S.lastXP then delta = xp - S.lastXP
        else delta = ((S.lastXPMax or xpMax) - S.lastXP) + xp end
        if delta > 0 then
            S.lastCombat = math.max(S.lastCombat, GetTime() - 5) -- xp usually means we just fought
            local act = SM:ProductiveActivity()
            S.xp = S.xp + delta
            S.xpBy[act] = S.xpBy[act] + delta
            Zone().xp = Zone().xp + delta
            if S.dungeon then S.dungeon.xp = S.dungeon.xp + delta end
            FO:Fire("FO_XP", delta, act)
        end
    end
    S.lastXP, S.lastXPMax = xp, xpMax
end

-- Grinding.XPTracker parses kill lines and calls this
function SM:RecordKill(name, xp, npcID)
    if not S then return end
    local now = GetTime()
    S.lastCombat = now
    local act = SM:ProductiveActivity()
    S.kills = S.kills + 1
    S.killXP = S.killXP + (xp or 0)
    S.killsBy[act] = S.killsBy[act] + 1
    Zone().kills = Zone().kills + 1
    if S.dungeon then S.dungeon.kills = S.dungeon.kills + 1 end
end

-- Grinding.LootTracker calls this per looted item
function SM:RecordLootItem(itemID, qty, value, src, npcID)
    if not S then return end
    S.lastCombat = math.max(S.lastCombat, GetTime() - 5)
    S.items = S.items + 1
    local vend = U.VendorSell(itemID) * qty
    S.vendorEst = S.vendorEst + vend
    Zone().vendorEst = Zone().vendorEst + vend
    if src == "ah" then
        S.ahEst = S.ahEst + value * qty
        Zone().ahEst = Zone().ahEst + value * qty
    end
    if S.dungeon then
        S.dungeon.ahEst = S.dungeon.ahEst + (src == "ah" and value * qty or 0)
        S.dungeon.vendorEst = S.dungeon.vendorEst + vend
        if value * qty >= SM.db.settings.valuableDrop then
            table.insert(S.dungeon.drops, { itemID = itemID, qty = qty, value = value })
        end
    end
end

-- ---------------------------------------------------------------------------
-- Money
-- ---------------------------------------------------------------------------
local function OnMoney()
    if not S then return end
    local money = U.Num(GetMoney())
    if not money then return end
    if S.lastMoney then
        local delta = money - S.lastMoney
        if delta ~= 0 then
            local F = FO.state.frames
            local ctx
            S.gold = S.gold + delta
            Zone().gold = Zone().gold + delta
            if F.merchant then
                if delta > 0 then S.vendorSales = S.vendorSales + delta; ctx = "sale"
                elseif S.expectRepair and math.abs(-delta - S.expectRepair) <= 1 then S.expectRepair = nil; ctx = "repair"
                else S.purchases = S.purchases - delta; ctx = "purchase" end
            elseif F.trainer and delta < 0 then S.training = S.training - delta; ctx = "training"
            elseif F.auction and delta < 0 then S.ahSpend = S.ahSpend - delta; ctx = "auction"
            elseif F.mail then
                if delta > 0 then S.mailIn = S.mailIn + delta; ctx = "mailin" else S.mailOut = S.mailOut - delta; ctx = "mailout" end
            elseif F.bank or F.trade then S.transfers = S.transfers + delta; ctx = "transfer"
            elseif F.taxi and delta < 0 then S.taxi = S.taxi - delta; ctx = "taxi"
            elseif delta > 0 and (GetTime() - S.lastQuestTurnIn) < 3 then ctx = "quest" -- questGold set by QUEST_TURNED_IN
            elseif delta > 0 then ctx = "loot" -- lootGold set by CHAT_MSG_MONEY
            else S.otherGold = S.otherGold + delta; ctx = "other" end
            local act = SM:ProductiveActivity()
            S.goldBy[act] = S.goldBy[act] + delta
            if S.dungeon then
                S.dungeon.gold = S.dungeon.gold + delta
                if ctx == "repair" then S.dungeon.repairs = S.dungeon.repairs + (-delta) end
            end
            FO:Fire("FO_MONEY", delta, ctx)
        end
    end
    S.lastMoney = money
end

local moneyPatterns
local function ParseCoinString(s)
    if not moneyPatterns then
        moneyPatterns = {
            { (U.GlobalStringToPattern(GOLD_AMOUNT or "%d Gold"):gsub("^%^", "")), 10000 },
            { (U.GlobalStringToPattern(SILVER_AMOUNT or "%d Silver"):gsub("^%^", "")), 100 },
            { (U.GlobalStringToPattern(COPPER_AMOUNT or "%d Copper"):gsub("^%^", "")), 1 },
        }
    end
    local total = 0
    for _, p in ipairs(moneyPatterns) do
        local n = s:match(p[1])
        if n then total = total + (tonumber(n) or 0) * p[2] end
    end
    return total
end
SM.ParseCoinString = ParseCoinString

local function CacheRepairCost()
    if not S or not GetRepairAllCost then return end
    local cost = U.Num(GetRepairAllCost())
    if cost and cost > 0 then S.repairCost = cost end
end

U.HookGlobal("RepairAllItems", function()
    if not S then return end
    local cost = GetRepairAllCost and U.Num(GetRepairAllCost()) or 0
    if not cost or cost == 0 then cost = S.repairCost or 0 end
    if cost > 0 then
        S.repairs = S.repairs + cost
        S.expectRepair = cost
        FO:Fire("FO_REPAIR", cost)
    end
    S.repairCost = 0
end)

-- ---------------------------------------------------------------------------
-- Dungeon runs
-- ---------------------------------------------------------------------------
local function EnterInstance()
    local name, instType, diff, diffName = GetInstanceInfo()
    S.dungeon = {
        name = U.Str(name) or "?", type = U.Str(instType), start = time(), seconds = 0,
        xp = 0, kills = 0, gold = 0, ahEst = 0, vendorEst = 0, repairs = 0, deaths = 0, drops = {},
        level = FO.Player.level, char = FO.charKey,
    }
    FO:Fire("FO_INSTANCE_ENTER", S.dungeon)
end

local function LeaveInstance()
    local run = S.dungeon
    if not run then return end
    S.dungeon = nil
    run.stop = time()
    if run.seconds >= 120 or run.kills > 0 then
        U.Push(SM.db.dungeons, run, SM.db.settings.maxDungeons)
        SM.lastRun = run
        SM.lastRunLeftAt = GetTime()
        FO:Fire("FO_INSTANCE_LEAVE", run)
        print("%s: %s, %d xp, %d kills, net %s, loot est %s", run.name, U.FormatDuration(run.seconds), run.xp, run.kills,
              U.FormatMoney(run.gold), U.FormatMoney(run.ahEst + run.vendorEst))
    end
end

local function CheckInstance()
    if not S then return end
    local inInst = U.InInstance()
    if inInst and not S.dungeon then EnterInstance()
    elseif not inInst and S.dungeon then LeaveInstance() end
end

-- Repairs within 10 minutes of leaving a dungeon belong to that run
FO:On("FO_REPAIR", function(cost)
    if SM.lastRun and SM.lastRunLeftAt and (GetTime() - SM.lastRunLeftAt) < 600 then
        SM.lastRun.postRepairs = (SM.lastRun.postRepairs or 0) + cost
    end
end)

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
SM.events = {
    PLAYER_XP_UPDATE = function(self, unit) if unit == "player" then OnXPUpdate() end end,
    PLAYER_LEVEL_UP = function(self, lvl)
        if S then S.level = U.Num(lvl) or S.level end
        C_Timer.After(0.5, OnXPUpdate)
    end,
    PLAYER_MONEY = function() OnMoney() end,
    CHAT_MSG_MONEY = function(self, msg)
        if not S then return end
        msg = U.Str(msg)
        if not msg then return end
        local c = ParseCoinString(msg)
        if c > 0 then
            S.lootGold = S.lootGold + c
            Zone().lootGold = Zone().lootGold + c
            FO:Fire("FO_LOOT_MONEY", c)
        end
    end,
    PLAYER_REGEN_DISABLED = function() if S then S.lastCombat = GetTime() end end,
    PLAYER_REGEN_ENABLED = function() if S then S.lastCombat = GetTime() end end,
    LOOT_OPENED = function() if S then S.lastCombat = math.max(S.lastCombat, GetTime() - 5) end end,
    UNIT_QUEST_LOG_CHANGED = function(self, unit) if unit == "player" and S then S.lastObjective = GetTime() end end,
    QUEST_WATCH_UPDATE = function() if S then S.lastObjective = GetTime() end end,
    QUEST_ACCEPTED = function(self, questID) if S then S.lastObjective = GetTime() end FO:Fire("FO_QUEST_ACCEPTED", U.Num(questID)) end,
    QUEST_TURNED_IN = function(self, questID, xp, money)
        if not S then return end
        xp, money = U.Num(xp) or 0, U.Num(money) or 0
        S.lastObjective, S.lastQuestTurnIn = GetTime(), GetTime()
        S.questXP = S.questXP + xp
        S.questGold = S.questGold + money
        S.questsDone = S.questsDone + 1
        FO:Fire("FO_QUEST_TURNED_IN", U.Num(questID), xp, money)
    end,
    PLAYER_DEAD = function()
        if not S then return end
        S.deaths = S.deaths + 1
        Zone().deaths = Zone().deaths + 1
        S.deathStart = GetTime()
        if S.dungeon then S.dungeon.deaths = S.dungeon.deaths + 1 end
        FO:Fire("FO_DEATH")
    end,
    PLAYER_UNGHOST = function()
        if not S or not S.deathStart then return end
        local dur = GetTime() - S.deathStart
        S.deathStart = nil
        S.deathTime = S.deathTime + dur
        U.Push(S.corpseRuns, { zone = S.zone, seconds = dur, t = time() }, 50)
        FO:Fire("FO_ALIVE", dur)
    end,
    PLAYER_ALIVE = function()
        -- fires on resurrection at corpse (not ghost) too; UNGHOST handles the ghost case
        if not S or not S.deathStart or UnitIsGhost("player") then return end
        local dur = GetTime() - S.deathStart
        S.deathStart = nil
        S.deathTime = S.deathTime + dur
        U.Push(S.corpseRuns, { zone = S.zone, seconds = dur, t = time(), rez = true }, 50)
        FO:Fire("FO_ALIVE", dur)
    end,
    ZONE_CHANGED_NEW_AREA = function()
        if not S then return end
        local zone = U.ZoneName()
        if zone ~= S.zone then
            S.zone = zone
            Zone()
            FO:Fire("FO_ZONE", zone)
        end
        CheckInstance()
    end,
    PLAYER_ENTERING_WORLD = function()
        C_Timer.After(1, function() OnXPUpdate(); CheckInstance() end)
    end,
    MERCHANT_SHOW = function() CacheRepairCost() end,
    MERCHANT_CLOSED = function() if S then S.expectRepair = nil end end,
    UPDATE_INVENTORY_DURABILITY = function() if FO.state.frames.merchant then CacheRepairCost() end end,
}

function SM:OnEnable()
    self:Start()
    C_Timer.After(2, CheckInstance)
end

-- ---------------------------------------------------------------------------
-- Snapshot for dashboards & analytics
-- ---------------------------------------------------------------------------
function SM:Stats()
    if not S then return nil end
    local el = self:Elapsed()
    local prod = self:ProductiveTime()
    local xp, xpMax = U.Num(UnitXP("player")), U.Num(UnitXPMax("player"))
    local xph = U.PerHour(S.xp, el)
    local xphProd = U.PerHour(S.xp, prod, 60)
    local ttl
    if xph and xph > 0 and xp and xpMax then ttl = (xpMax - xp) / xph * 3600 end
    local effective = S.gold + S.ahEst
    local downtime = S.time.travel + S.time.rest + S.time.town + S.time.dead + S.time.idle
    local by = {}
    for _, a in ipairs(ACTIVITIES) do
        by[a] = { t = S.time[a], xp = S.xpBy[a], kills = S.killsBy[a], gold = S.goldBy[a], xph = U.PerHour(S.xpBy[a], S.time[a], 60) }
    end
    return {
        elapsed = el, productive = prod, downtime = downtime, downtimePct = el > 0 and downtime / el * 100 or 0,
        paused = S.pausedAt ~= nil, zone = S.zone, level = S.level, activity = S.activity, by = by,
        xp = S.xp, xph = xph, xphProd = xphProd, ttl = ttl, questXP = S.questXP, killXP = S.killXP,
        kills = S.kills, kph = U.PerHour(S.kills, el),
        gold = S.gold, gph = U.PerHour(S.gold, el), effective = effective, egph = U.PerHour(effective, el),
        lootGold = S.lootGold, questGold = S.questGold, vendorSales = S.vendorSales, repairs = S.repairs,
        purchases = S.purchases, training = S.training, ahSpend = S.ahSpend, mailIn = S.mailIn, mailOut = S.mailOut,
        transfers = S.transfers, otherGold = S.otherGold, ahEst = S.ahEst, vendorEst = S.vendorEst, items = S.items,
        consumables = S.consumables, taxi = S.taxi, questsDone = S.questsDone,
        deaths = S.deaths, deathTime = S.deathTime, corpseRuns = S.corpseRuns,
        dungeon = S.dungeon, zones = S.zones,
    }
end

SM.commands = {
    session = { help = "report | reset | pause | force quest|grind|auto", fn = function(self, arg)
        local sub, rest = U.SplitCmd(arg)
        if sub == "reset" then self:Reset()
        elseif sub == "pause" then self:TogglePause()
        elseif sub == "force" then
            if rest == "auto" then S.lastObjective = 0 print("activity detection back to auto.") else self:Force(rest) end
        else
            local st = self:Stats()
            print("Session %s (%s productive, %.0f%% downtime) in %s, L%d, now: %s", U.FormatDuration(st.elapsed),
                  U.FormatDuration(st.productive), st.downtimePct, st.zone, st.level, st.activity)
            print("  XP %d (%s/hr wall, %s/hr productive), TTL %s", st.xp, U.Rate(st.xph), U.Rate(st.xphProd), U.FormatDuration(st.ttl))
            print("  kills %d (%s/hr), net %s (%s/hr), effective %s/hr", st.kills, U.Rate(st.kph), U.FormatMoney(st.gold),
                  st.gph and U.FormatMoney(st.gph) or "--", st.egph and U.FormatMoney(st.egph) or "--")
            local parts = {}
            for _, a in ipairs(ACTIVITIES) do if st.by[a].t > 0 then parts[#parts + 1] = string.format("%s %s", a, U.FormatDuration(st.by[a].t)) end end
            print("  time: %s", table.concat(parts, ", "))
        end
    end },
}
