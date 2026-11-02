local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Core")

-- ===========================================================================
-- Alerts: one place that turns "something you should look at now" into a
-- sound plus a single chat line, with per-kind toggles and a throttle so a
-- rare that keeps re-entering nameplate range doesn't ping every second.
-- Modules call FO:Alert(kind, fmt, ...). Kinds: rare, respawn, bags, ammo,
-- shards, custom.
-- ===========================================================================
local A = FO:NewModule("Core.Alerts", {
    account = "alerts",
    defaults = { settings = { sound = true, rare = true, respawn = true, bags = true, ammo = true, shards = true, bagSlots = 3, ammoMin = 200, shardsMin = 3, throttle = 20 } },
})
FO.Alerts = A
local lastAt = {}
A.fired = {}   -- session log of alerts (kind, text, t)

local SOUNDS = {
    rare = "RAID_WARNING", respawn = "READY_CHECK", bags = "IG_QUEST_LOG_OPEN", ammo = "RAID_WARNING", shards = "RAID_WARNING", custom = "RAID_WARNING",
}
local SOUND_IDS = { RAID_WARNING = 8959, READY_CHECK = 8960, IG_QUEST_LOG_OPEN = 844 }

local function Play(kind)
    if not PlaySound then return end
    local name = SOUNDS[kind] or "RAID_WARNING"
    local id = (SOUNDKIT and SOUNDKIT[name]) or SOUND_IDS[name]
    if id then pcall(PlaySound, id, "Master") end
end

function FO:Alert(kind, fmt, ...)
    local s = A.db and A.db.settings
    if s and s[kind] == false then return false end
    local text = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
    local now = GetTime()
    local key = kind .. "|" .. text
    if lastAt[key] and now - lastAt[key] < ((s and s.throttle) or 20) then return false end
    lastAt[key] = now
    print("|cffff8000!|r %s", text)
    if not s or s.sound then Play(kind) end
    A.fired[#A.fired + 1] = { kind = kind, text = text, t = time() }
    if #A.fired > 50 then table.remove(A.fired, 1) end
    return true
end

A.commands = {
    alerts = {
        help = "Alert settings: list | <rare|respawn|bags|ammo|shards|sound> on|off | bags <slots> | ammo <n> | shards <n>",
        fn = function(self, arg)
            local s = self.db.settings
            local sub, rest = U.SplitCmd(arg or "")
            if sub == "rare" or sub == "respawn" or sub == "bags" or sub == "ammo" or sub == "shards" or sub == "sound" then
                if (rest == "on" or rest == "off") then s[sub] = (rest == "on")
                elseif tonumber(rest) then
                    if sub == "bags" then s.bagSlots = tonumber(rest) elseif sub == "ammo" then s.ammoMin = tonumber(rest) elseif sub == "shards" then s.shardsMin = tonumber(rest) end
                else s[sub] = not s[sub] end
                print("alert %s: %s", sub, tostring(s[sub]))
                return
            elseif sub == "test" then
                FO:Alert("custom", "test alert (sound %s)", s.sound and "on" or "off")
                return
            end
            print("alerts: sound %s | rare %s | respawn %s | bags %s (<= %d free) | ammo %s (< %d) | shards %s (< %d)",
                s.sound and "on" or "off", s.rare and "on" or "off", s.respawn and "on" or "off", s.bags and "on" or "off", s.bagSlots,
                s.ammo and "on" or "off", s.ammoMin, s.shards and "on" or "off", s.shardsMin)
            if #self.fired > 0 then
                for i = math.max(1, #self.fired - 4), #self.fired do local f = self.fired[i] print("  %s ago  %s", U.FormatDuration(time() - f.t), f.text) end
            end
        end,
    },
}
