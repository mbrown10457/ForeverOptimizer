local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Character")

-- ===========================================================================
-- Rotation and talent-build optimizer.
--   Data: FO.Seed.spells / FO.Seed.talents (generated from the client's own
--         tables) + FO.Rotations (hand-authored priorities and builds).
--   Live: which ranks you know (IsSpellKnown), your level, your talents, and
--         what the combat log measured for each spell this session.
-- The estimate column comes from the client's base points and is a prior;
-- measured damage/heal per cast and per mana override it once there are
-- enough casts. Every name in FO.Rotations is validated against the seed so
-- a patch that renames an ability is caught by /fo rotation check and CI.
-- ===========================================================================
local R = FO:NewModule("Character.Rotation", { account = "rotation", defaults = { build = {} } })
FO.Rotation = R

local MIN_CASTS = 5
-- seed row layout (Data/Spells.lua)
local F = { name = 1, class = 2, tree = 3, rank = 4, level = 5, cost = 6, power = 7, cast = 8, cd = 9, gcd = 10, dur = 11,
            school = 12, dd = 13, heal = 14, dot = 15, hot = 16, period = 17, ppl = 18, next = 19, acquire = 20 }
-- talent row layout (Data/Talents.lua)
local T = { id = 1, name = 2, class = 3, tab = 4, tabOrder = 5, tier = 6, col = 7, ranks = 8, prereq = 9, desc = 10 }

-- ---------------------------------------------------------------------------
-- Seed indexes (built lazily)
-- ---------------------------------------------------------------------------
local byName          -- class -> lowercased name -> { {id=, row=}, ... } sorted by rank
local talentsByClass  -- class -> { rows }, talentIndex: class -> lowername -> { rows }

local function BuildIndex()
    byName = {}
    for id, row in pairs(FO.Seed and FO.Seed.spells or {}) do
        local cls = row[F.class]
        byName[cls] = byName[cls] or {}
        local key = row[F.name]:lower()
        local list = byName[cls][key]
        if not list then list = {} byName[cls][key] = list end
        list[#list + 1] = { id = id, row = row }
    end
    for _, lists in pairs(byName) do
        for _, list in pairs(lists) do table.sort(list, function(a, b) return a.row[F.rank] < b.row[F.rank] or (a.row[F.rank] == b.row[F.rank] and a.id < b.id) end) end
    end
    talentsByClass = {}
    for _, row in ipairs(FO.Seed and FO.Seed.talents or {}) do
        local cls = row[T.class]
        local tc = talentsByClass[cls]
        if not tc then tc = { rows = {}, index = {} } talentsByClass[cls] = tc end
        tc.rows[#tc.rows + 1] = row
        local key = row[T.name]:lower()
        tc.index[key] = tc.index[key] or {}
        table.insert(tc.index[key], row)
    end
end

function R:Ranks(class, name)
    if not byName then BuildIndex() end
    return byName[class] and byName[class][(name or ""):lower()] or nil
end

-- is any rank of this spell known?
local function SpellKnown(id)
    if IsPlayerSpell then local ok, r = pcall(IsPlayerSpell, id) if ok and r then return true end end
    if IsSpellKnown then local ok, r = pcall(IsSpellKnown, id) if ok and r then return true end end
    return false
end

function R:Known(class, name)
    local ranks = self:Ranks(class, name)
    if not ranks then return nil end
    local best
    for _, r in ipairs(ranks) do if SpellKnown(r.id) then best = r end end
    return best, ranks
end

-- the lowest-level unknown rank that the player's level already allows
function R:Trainable(class, name, level)
    local ranks = self:Ranks(class, name)
    if not ranks then return nil end
    for _, r in ipairs(ranks) do
        local lv = r.row[F.level]
        if lv > 0 and lv <= level and not SpellKnown(r.id) then return r end
    end
    return nil
end

function R:NextRankLevel(class, name, level)
    local ranks = self:Ranks(class, name)
    if not ranks then return nil end
    local best
    for _, r in ipairs(ranks) do
        local lv = r.row[F.level]
        if lv > level and (not best or lv < best.row[F.level]) then best = r end
    end
    return best
end

-- Prior from base points: total damage / heal of one cast, its cost and time
function R:Estimate(row)
    local ticks = (row[F.period] > 0 and row[F.dur] > 0) and math.floor(row[F.dur] / row[F.period]) or 0
    local dmg = row[F.dd] + row[F.dot] * ticks
    local heal = row[F.heal] + row[F.hot] * ticks
    local time = math.max(row[F.cast], row[F.gcd] > 0 and row[F.gcd] or 1500) / 1000
    local cost = row[F.cost]
    return {
        dmg = dmg, heal = heal, cost = cost, time = time, ticks = ticks,
        dpm = (cost > 0 and dmg > 0) and dmg / cost or nil, hpm = (cost > 0 and heal > 0) and heal / cost or nil,
        dps = dmg > 0 and dmg / time or nil, hps = heal > 0 and heal / time or nil,
    }
end

-- Measured from the combat log this session, by spell name
function R:Measured(name)
    local CS = FO.CombatStats
    if not (CS and CS:Available()) then return nil end
    local c = CS:Stats()
    local out
    for _, sp in ipairs(c.spells) do
        if sp.name == name and (sp.casts or sp.n) >= MIN_CASTS then
            out = out or {}
            out.dmgPerCast = sp.total / math.max(1, sp.casts or sp.n)
            out.dpm = sp.perMana
            out.casts = sp.casts or sp.n
        end
    end
    for _, h in ipairs(c.heals) do
        if h.name == name and (h.casts or h.n) >= MIN_CASTS then
            out = out or {}
            out.healPerCast = h.total / math.max(1, h.casts or h.n)
            out.hpm = h.perMana
            out.overPct = h.overPct
            out.casts = h.casts or h.n
        end
    end
    for _, d in ipairs(c.dots) do
        if d.name == name and d.applied >= 3 then
            out = out or {}
            out.dotEff = d.efficiency
            out.dmgPerApply = d.perApply
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Validation of the hand-authored data against the seed
-- ---------------------------------------------------------------------------
local function ParseTalentRef(ref)
    local name, tier, col = ref:match("^(.-)@t(%d+)c(%d+)$")
    if name then return name, tonumber(tier), tonumber(col) end
    return ref, nil, nil
end

function R:FindTalent(class, ref)
    if not talentsByClass then BuildIndex() end
    local tc = talentsByClass[class]
    if not tc then return nil, "no talents for class" end
    local name, tier, col = ParseTalentRef(ref)
    local rows = tc.index[name:lower()]
    if not rows then return nil, "unknown talent" end
    if #rows == 1 and not tier then return rows[1] end
    for _, row in ipairs(rows) do
        if tier and row[T.tier] == tier and row[T.col] == col then return row end
    end
    if #rows > 1 and not tier then return nil, string.format("%d talents share this name; use Name@t<tier>c<col>", #rows) end
    return nil, "no talent at that tier/column"
end

-- Walks a build in order checking existence, max rank, tier gates and prerequisites.
function R:ValidateBuild(class, build)
    local problems = {}
    local spent = {}       -- tab -> points
    local rankOf = {}      -- talent id -> rank
    local total = 0
    for i, entry in ipairs(build.talents or {}) do
        local row, why = self:FindTalent(class, entry[1])
        if not row then
            problems[#problems + 1] = string.format("#%d %s: %s", i, entry[1], why)
        else
            local pts = entry[2] or 1
            if pts > #row[T.ranks] then problems[#problems + 1] = string.format("#%d %s: %d points but max rank is %d", i, entry[1], pts, #row[T.ranks]) end
            local tab = row[T.tab]
            local need = row[T.tier] * 5
            if (spent[tab] or 0) < need then
                problems[#problems + 1] = string.format("#%d %s: tier %d needs %d points in %s, only %d spent before it", i, entry[1], row[T.tier], need, tab, spent[tab] or 0)
            end
            for _, pre in ipairs(row[T.prereq] or {}) do
                if (rankOf[pre[1]] or 0) < pre[2] then
                    problems[#problems + 1] = string.format("#%d %s: needs prerequisite talent %d at rank %d first", i, entry[1], pre[1], pre[2])
                end
            end
            spent[tab] = (spent[tab] or 0) + pts
            rankOf[row[T.id]] = (rankOf[row[T.id]] or 0) + pts
            total = total + pts
        end
    end
    if total > 51 then problems[#problems + 1] = string.format("%d points total; level 60 has 51", total) end
    return problems, total
end

function R:Validate(class)
    local out = {}
    local data = FO.Rotations and FO.Rotations[class]
    if not data then return { "no rotation data for " .. tostring(class) } end
    for i, e in ipairs(data.rotation or {}) do
        if not e.generic and not self:Ranks(class, e[1]) then
            out[#out + 1] = string.format("rotation #%d '%s' not in %s spells%s", i, e[1], class, e.optional and " (optional)" or "")
        end
    end
    for _, b in ipairs(data.builds or {}) do
        for _, p in ipairs(self:ValidateBuild(class, b)) do out[#out + 1] = b.name .. ": " .. p end
    end
    return out
end

function R:ValidateAll()
    local report = {}
    for class in pairs(FO.Rotations or {}) do
        for _, line in ipairs(self:Validate(class)) do
            -- an optional entry missing from the seed is a warning, anything else is an error
            report[#report + 1] = { class = class, line = line, warning = line:find("%(optional%)$") ~= nil }
        end
    end
    table.sort(report, function(a, b) return a.class < b.class end)
    return report
end

-- ---------------------------------------------------------------------------
-- Live talent state (classic tab API), nil if the client has none
-- ---------------------------------------------------------------------------
function R:LiveTalents()
    -- Forever documents C_SpecializationInfo.GetTalentInfo({ specializationIndex, talentIndex }) -> table
    local SI = C_SpecializationInfo
    if SI and SI.GetTalentInfo and not (GetTalentInfo and GetNumTalents) then
        local out = {}
        for tab = 1, 3 do
            for i = 1, 60 do
                local ok, r = pcall(SI.GetTalentInfo, { specializationIndex = tab, talentIndex = i })
                if not ok or type(r) ~= "table" or not r.name then break end
                out[#out + 1] = { name = U.Str(r.name), tier = (U.Num(r.tier) or 1) - 1, col = (U.Num(r.column) or 1) - 1, rank = U.Num(r.rank) or 0, max = U.Num(r.maxRank) or 0, tab = tab }
            end
        end
        return #out > 0 and out or nil
    end
    if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return nil end
    local ok, tabs = pcall(GetNumTalentTabs)
    if not ok or not tabs then return nil end
    local out = {}
    for tab = 1, tabs do
        local okN, n = pcall(GetNumTalents, tab)
        for i = 1, (okN and n or 0) do
            local okT, name, _, tier, col, rank, maxRank = pcall(GetTalentInfo, tab, i)
            if okT and name then
                out[#out + 1] = { name = U.Str(name), tier = (U.Num(tier) or 1) - 1, col = (U.Num(col) or 1) - 1, rank = U.Num(rank) or 0, max = U.Num(maxRank) or 0, tab = tab }
            end
        end
    end
    return out
end

function R:PointsAvailable(level)
    return math.max(0, level - 9)
end

-- Next points to spend for the current level, from the chosen build vs live ranks
function R:BuildProgress(class, build, level)
    local live = self:LiveTalents()
    local liveRank = {}
    for _, t in ipairs(live or {}) do liveRank[(t.name or ""):lower() .. "@" .. t.tier .. "c" .. t.col] = t.rank end
    local budget = self:PointsAvailable(level)
    local rows, spentPlanned, next = {}, 0, {}
    for _, entry in ipairs(build.talents or {}) do
        local row = self:FindTalent(class, entry[1])
        local pts = entry[2] or 1
        local have = row and liveRank[row[T.name]:lower() .. "@" .. row[T.tier] .. "c" .. row[T.col]] or nil
        local planned = math.max(0, math.min(pts, budget - spentPlanned))
        rows[#rows + 1] = { name = entry[1], tab = row and row[T.tab] or "?", pts = pts, planned = planned, have = have }
        if have and have < planned then next[#next + 1] = string.format("%s %d/%d", entry[1], have, planned) end
        spentPlanned = spentPlanned + pts
    end
    return rows, next, live ~= nil
end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------
local function Metric(est, m, resource)
    if m then
        if m.healPerCast then return string.format("|cff80ff80%.0f heal/cast%s%s|r", m.healPerCast, m.hpm and string.format(", %.2f/mana", m.hpm) or "", m.overPct and string.format(", %.0f%% over", m.overPct * 100) or "") end
        if m.dmgPerCast then return string.format("|cff80ff80%.0f dmg/cast%s%s|r", m.dmgPerCast, m.dpm and string.format(", %.1f/mana", m.dpm) or "", m.dotEff and string.format(", %.0f%% dot eff", m.dotEff * 100) or "") end
    end
    if est.heal > 0 then return string.format("|cffaaaaaaest %.0f heal%s|r", est.heal, est.hpm and string.format(", %.2f/mana", est.hpm) or "") end
    if est.dmg > 0 then return string.format("|cffaaaaaaest %.0f dmg%s|r", est.dmg, est.dpm and resource == "mana" and string.format(", %.1f/mana", est.dpm) or "") end
    return ""
end

function R:Print(class)
    class = class or FO.Player.class
    local data = FO.Rotations and FO.Rotations[class]
    if not data then print("no rotation data for %s", tostring(class)) return end
    local level = FO.Player.level or 1
    local CL = FO.CombatLog
    print("%s rotation at level %d  (%s; seed build %s)", class, level, (CL and CL.available) and (CL.estimated and "measured from hits on your target where 5+ casts" or "measured where 5+ casts") or "estimates only, no combat log", FO.Seed and FO.Seed.spellBuild or "?")
    local n, unlearned, train = 0, {}, {}
    for _, e in ipairs(data.rotation) do
        local known, ranks = self:Known(class, e[1])
        if e.generic then
            n = n + 1
            local m = self:Measured(e[1])
            print("%2d. %-22s |cffffd100%-9s|r %s  %s", n, e[1], e[2], e[3], m and m.dmgPerCast and string.format("|cff80ff80%.0f dmg/hit|r", m.dmgPerCast) or "")
        elseif known then
            n = n + 1
            local est = self:Estimate(known.row)
            local tr = self:Trainable(class, e[1], level)
            print("%2d. %-22s |cffffd100%-9s|r %s  %s%s", n, e[1] .. (known.row[F.rank] > 0 and (" r" .. known.row[F.rank]) or ""), e[2], e[3],
                Metric(est, self:Measured(e[1]), data.resource), tr and (" |cffff6060train r" .. tr.row[F.rank] .. "|r") or "")
            if tr then train[#train + 1] = string.format("%s rank %d", e[1], tr.row[F.rank]) end
        elseif ranks then
            local nxt = self:NextRankLevel(class, e[1], level - 1)
            local lv = nxt and nxt.row[F.level] or 0
            if not e.optional then unlearned[#unlearned + 1] = lv > level and string.format("%s (L%d)", e[1], lv) or string.format("%s (|cffff6060train now|r)", e[1]) end
        end
    end
    if #unlearned > 0 then print("not yet: %s", table.concat(unlearned, ", ")) end
    if #train > 0 then print("|cffff6060upgrades at the trainer:|r %s", table.concat(train, ", ")) end
end

function R:PrintBuild(class, which)
    class = class or FO.Player.class
    local data = FO.Rotations and FO.Rotations[class]
    if not data or #(data.builds or {}) == 0 then print("no builds for %s", tostring(class)) return end
    local idx = tonumber(which) or self.db.build[class] or 1
    local build = data.builds[idx] or data.builds[1]
    local level = FO.Player.level or 1
    local problems = self:ValidateBuild(class, build)
    local rows, next, live = self:BuildProgress(class, build, level)
    print("%s (%d/%d)  level %d, %d points to place%s", build.name, idx, #data.builds, level, self:PointsAvailable(level), live and "" or "  (talent API absent: plan only)")
    for _, p in ipairs(problems) do print("  |cffff6060%s|r", p) end
    local shown = 0
    for _, r in ipairs(rows) do
        if r.planned > 0 or shown < 3 then
            shown = shown + 1
            print("  %-34s %-13s %d/%d%s", r.name, r.tab, r.planned, r.pts, r.have and string.format("  have %d", r.have) or "")
        end
    end
    if #next > 0 then print("|cffffd100next points:|r %s", table.concat(next, ", ")) end
end

R.commands = {
    rotation = {
        help = "Leveling priority for your class with measured/estimated efficiency | check | <CLASS>",
        fn = function(self, arg)
            local sub = U.Str(arg) or ""
            if sub == "check" then
                local report = self:ValidateAll()
                if #report == 0 then print("rotation data matches seed build %s: all spells and talents found.", FO.Seed.spellBuild or "?") return end
                local errs = 0
                for _, r in ipairs(report) do if not r.warning then errs = errs + 1 end print("  %s%s: %s|r", r.warning and "|cffffd100" or "|cffff6060", r.class, r.line) end
                print("%d problems (%d errors, %d optional runes absent)", #report, errs, #report - errs)
                return
            end
            self:Print(sub ~= "" and sub:upper() or nil)
        end,
    },
    build = {
        help = "Talent build vs your points: build | build list | build <n> | build use <n>",
        fn = function(self, arg)
            local sub, rest = U.SplitCmd(arg or "")
            local class = FO.Player.class
            local data = FO.Rotations and FO.Rotations[class]
            if sub == "list" then
                for i, b in ipairs(data and data.builds or {}) do print("  %d. %s%s", i, b.name, (self.db.build[class] or 1) == i and "  (active)" or "") end
                return
            elseif sub == "use" then
                self.db.build[class] = tonumber(rest) or 1
                print("active build set to %d", self.db.build[class])
                return
            end
            self:PrintBuild(nil, sub ~= "" and sub or nil)
        end,
    },
    spell = {
        help = "Look a class spell up in the client seed: ranks, levels, cost, cast, cooldown",
        fn = function(self, arg)
            local name = U.Str(arg)
            if not name or name == "" then print("usage: /fo spell <name>") return end
            local class = FO.Player.class
            local ranks = self:Ranks(class, name)
            if not ranks then
                for cls, lists in pairs(byName or {}) do if lists[name:lower()] then ranks = lists[name:lower()] class = cls break end end
            end
            if not ranks then print("'%s' is not a class spell in the seed", name) return end
            print("%s (%s, %s): %d rank%s", ranks[1].row[F.name], class, ranks[1].row[F.tree], #ranks, #ranks == 1 and "" or "s")
            for _, r in ipairs(ranks) do
                local row, est = r.row, self:Estimate(r.row)
                print("  r%-2d L%-2d id %-6d cost %-4d cast %.1fs cd %.0fs%s%s%s%s", row[F.rank], row[F.level], r.id, row[F.cost], row[F.cast] / 1000, row[F.cd] / 1000,
                    est.dmg > 0 and string.format("  ~%.0f dmg", est.dmg) or "", est.heal > 0 and string.format("  ~%.0f heal", est.heal) or "",
                    est.ticks > 0 and string.format(" (%d ticks)", est.ticks) or "", SpellKnown(r.id) and "  |cff80ff80known|r" or "")
            end
        end,
    },
}

function R:OnEnable()
    local report = self:ValidateAll()
    local errs = 0
    for _, r in ipairs(report) do if not r.warning then errs = errs + 1 end end
    if errs > 0 then print("|cffff6060rotation data has %d mismatches with the client seed|r; /fo rotation check", errs) end
end
