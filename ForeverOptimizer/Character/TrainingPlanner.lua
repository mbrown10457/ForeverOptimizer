local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Character")

-- ===========================================================================
-- Trainer costs (including ranks you can't learn yet), savings goals, and
-- projection against your gold/hr. Default goals use 1.12 base prices.
-- ===========================================================================
local TP = FO:NewModule("Character.TrainingPlanner", {
    char = "training",
    cdefaults = { skills = {}, spent = 0, goals = {
        { name = "mount + riding (L40)", cost = 100 * 10000, level = 40 },
        { name = "epic mount + riding (L60)", cost = 1000 * 10000, level = 60 },
    } },
})

local capturing = false
function TP:Capture()
    if capturing or not GetNumTrainerServices then return end
    capturing = true
    local prevUnavail, prevUsed
    if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
        prevUnavail, prevUsed = GetTrainerServiceTypeFilter("unavailable"), GetTrainerServiceTypeFilter("used")
        SetTrainerServiceTypeFilter("unavailable", true)
        SetTrainerServiceTypeFilter("used", true)
    end
    local isProf = IsTradeskillTrainer and IsTradeskillTrainer() == true
    local trainer = U.Str(UnitName("npc")) or "?"
    local n = U.Num(GetNumTrainerServices()) or 0
    local added, now = 0, time()
    for i = 1, n do
        local name, rank, category = GetTrainerServiceInfo(i)
        name, rank, category = U.Str(name), U.Str(rank) or "", U.Str(category)
        if name and category ~= "header" then
            local cost = U.Num((GetTrainerServiceCost(i))) or 0
            local reqLevel = U.Num(GetTrainerServiceLevelReq(i)) or 0
            local key = name .. "|" .. rank
            local prev = self.cdb.skills[key]
            if not prev then added = added + 1 end
            self.cdb.skills[key] = { name = name, rank = rank, cost = cost, reqLevel = reqLevel, category = category, trainer = trainer,
                                     prof = isProf, t = now, learned = category == "used" or (prev and prev.learned) or false }
        end
    end
    if prevUnavail ~= nil then SetTrainerServiceTypeFilter("unavailable", prevUnavail) SetTrainerServiceTypeFilter("used", prevUsed) end
    capturing = false
    if added > 0 then print("%s: %d new services recorded (%d total).", trainer, added, U.Count(self.cdb.skills)) end
end

TP.messages = {
    FO_MONEY = function(self, delta, ctx) if ctx == "training" then self.cdb.spent = (self.cdb.spent or 0) - delta end end,
}

TP.events = {
    TRAINER_SHOW = function(self) C_Timer.After(0.5, function() self:Capture() end) end,
}
function TP:OnInit() self.events.TRAINER_UPDATE = U.Debounce(1, function() if FO.state.frames.trainer then self:Capture() end end) end

local function Level() return FO.Player.level or 1 end

function TP:Upcoming(toLevel, includeProf)
    local lvl = Level()
    local byLevel, owedNow, total = {}, 0, 0
    for _, s in pairs(self.cdb.skills) do
        if not s.learned and (includeProf or not s.prof) then
            local rl = s.reqLevel or 0
            if rl <= lvl then owedNow = owedNow + s.cost total = total + s.cost
            elseif rl <= toLevel then
                byLevel[rl] = byLevel[rl] or { cost = 0, items = {} }
                byLevel[rl].cost = byLevel[rl].cost + s.cost
                table.insert(byLevel[rl].items, s)
                total = total + s.cost
            end
        end
    end
    return owedNow, byLevel, total
end

function TP:Plan(arg)
    local toLevel = math.min(math.max(tonumber(arg) or (Level() + 10), Level()), 60)
    local money = FO.Player.money or 0
    local owedNow, byLevel, trainingTotal = self:Upcoming(toLevel, false)
    print("Level %d, %s on hand. Class training through L%d costs %s (%s owed now).", Level(), U.FormatMoney(money), toLevel, U.FormatMoney(trainingTotal), U.FormatMoney(owedNow))
    local levels = U.Keys(byLevel)
    table.sort(levels)
    for _, l in ipairs(levels) do
        local names = {}
        for _, s in ipairs(byLevel[l].items) do names[#names + 1] = s.name .. (s.rank ~= "" and (" (" .. s.rank .. ")") or "") end
        print("  L%-2d %-9s %s", l, U.FormatMoney(byLevel[l].cost), U.Trunc(table.concat(names, ", "), 90))
    end
    local st = FO.Session:Stats()
    local gph = st and st.egph or nil
    for _, g in ipairs(self.cdb.goals) do
        if not g.level or g.level >= Level() then
            local need = g.cost + (g.level and select(3, self:Upcoming(g.level, false)) or 0)
            local gap = need - money
            local line = string.format("Goal %s: %s + training = %s, gap %s", g.name, U.FormatMoney(g.cost), U.FormatMoney(need), U.FormatMoney(math.max(gap, 0)))
            if gap > 0 and gph and gph > 0 then line = line .. string.format("  (~%s at %s/hr effective)", U.FormatDuration(gap / gph * 3600), U.ShortMoney(gph)) end
            print("%s", line)
        end
    end
    if U.Count(self.cdb.skills) == 0 then print("No trainer data yet. Visit your class trainer once; unavailable ranks are recorded too.") end
    print("Lifetime trainer spend: %s", U.FormatMoney(self.cdb.spent or 0))
end

function TP:Skippable(arg)
    local threshold = U.ParseMoney(arg) or 5000
    local known = {}
    for _, s in pairs(self.cdb.skills) do if s.learned then known[s.name] = true end end
    local rows = {}
    for _, s in pairs(self.cdb.skills) do
        if not s.learned and not s.prof and known[s.name] and s.cost >= threshold then rows[#rows + 1] = s end
    end
    table.sort(rows, function(a, b) return a.cost > b.cost end)
    print("Higher ranks of skills you already know, >= %s (skipping delays only the rank):", U.FormatMoney(threshold))
    local total = 0
    for i = 1, math.min(20, #rows) do local s = rows[i] total = total + s.cost print("  L%-2d %-9s %s (%s)", s.reqLevel, U.FormatMoney(s.cost), s.name, s.rank) end
    print("  total shown: %s", U.FormatMoney(total))
end

TP.commands = {
    plan = { help = "[level] — training costs ahead and savings goals", fn = function(self, arg) self:Plan(arg) end },
    skip = { help = "[min price] — skippable spell ranks", fn = function(self, arg) self:Skippable(arg) end },
    proftrain = { help = "profession training not yet learned", fn = function(self)
        local rows = {}
        for _, s in pairs(self.cdb.skills) do if s.prof and not s.learned then rows[#rows + 1] = s end end
        table.sort(rows, function(a, b) return (a.reqLevel or 0) < (b.reqLevel or 0) end)
        local sum = 0
        print("Profession training not yet learned (%d):", #rows)
        for i = 1, math.min(25, #rows) do local s = rows[i] sum = sum + s.cost print("  L%-2d %-9s %s%s @ %s", s.reqLevel or 0, U.FormatMoney(s.cost), s.name, s.rank ~= "" and (" (" .. s.rank .. ")") or "", s.trainer or "?") end
        print("  total: %s", U.FormatMoney(sum))
    end },
    goal = { help = "[add <name> <price> [level] | del <n>]", fn = function(self, arg)
        local sub, rest = U.SplitCmd(arg)
        if sub == "add" then
            local name, price, level = rest:match("^(.-)%s+(%S+)%s*(%d*)$")
            local c = U.ParseMoney(price)
            if not name or not c then print("usage: /fo goal add <name> <price> [level]") return end
            table.insert(self.cdb.goals, { name = name, cost = c, level = tonumber(level) })
            print("goal added: %s %s", name, U.FormatMoney(c))
        elseif sub == "del" then
            local i = tonumber(rest)
            if i and self.cdb.goals[i] then print("removed %s", self.cdb.goals[i].name) table.remove(self.cdb.goals, i) end
        else
            for i, g in ipairs(self.cdb.goals) do print("  %d. %s %s%s", i, g.name, U.FormatMoney(g.cost), g.level and (" @L" .. g.level) or "") end
        end
    end },
}
