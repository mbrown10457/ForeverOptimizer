local ADDON, FO = ...
local U = FO.Util
local print = FO:Printer("Quest")

-- ===========================================================================
-- Quest reader. Speaks quest and gossip text through the client's own
-- text-to-speech engine (C_VoiceChat.SpeakText, the one chat TTS uses) when
-- a quest window opens: title, description and objectives on QUEST_DETAIL,
-- the progress text on QUEST_PROGRESS, the reward text on QUEST_COMPLETE,
-- NPC gossip on GOSSIP_SHOW. Closing the window stops the voice.
-- /fo tts on|off, voice <n>, rate, volume, gossip on|off, again, test.
-- ===========================================================================
local R = FO:NewModule("Quest.Reader", {
    account = "tts",
    defaults = { enabled = true, gossip = true, objectives = true, voice = nil, rate = 0, volume = 100 },
})
FO.Reader = R
R.available, R.reason = false, "not initialised"
R.last = nil
R.spoken = 0

local function Dest()
    local e = Enum and Enum.VoiceTtsDestination
    return (e and (e.LocalPlayback or e.QueuedLocalPlayback)) or 1
end

local function Clean(s)
    s = U.Str(s)
    if not s or s == "" then return nil end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
    s = s:gsub("[\r\n]+", " "):gsub("%s%s+", " ")
    return s
end

function R:Voices()
    if not (C_VoiceChat and C_VoiceChat.GetTtsVoices) then return {} end
    local ok, list = pcall(C_VoiceChat.GetTtsVoices)
    if not ok or type(list) ~= "table" then return {} end
    local out = {}
    for _, v in ipairs(list) do
        local id, name = U.Num(v.voiceID), U.Str(v.name)
        if id then out[#out + 1] = { id = id, name = name or ("voice " .. id) } end
    end
    return out
end

function R:VoiceID()
    if self.db.voice then return self.db.voice end
    local v = self:Voices()[1]
    return v and v.id or 0
end

function R:Speak(text, force)
    if not self.available then return false end
    if self.db.enabled == false and not force then return false end
    text = Clean(text)
    if not text then return false end
    self:Stop()
    local ok, err = pcall(C_VoiceChat.SpeakText, self:VoiceID(), text, Dest(), U.Num(self.db.rate) or 0, U.Num(self.db.volume) or 100)
    if not ok then print("tts: %s", tostring(err)) return false end
    self.last = text
    self.spoken = self.spoken + 1
    return true
end

function R:Stop()
    if C_VoiceChat and C_VoiceChat.StopSpeakingText then pcall(C_VoiceChat.StopSpeakingText) end
end

local function Call(fn) if type(fn) == "function" then local ok, v = pcall(fn) if ok then return U.Str(v) end end end

function R:ReadDetail()
    local title, body, objectives = Call(GetTitleText), Call(GetQuestText), Call(GetObjectiveText)
    local parts = {}
    if title then parts[#parts + 1] = title .. "." end
    if body then parts[#parts + 1] = body end
    if self.db.objectives ~= false and objectives and objectives ~= "" then parts[#parts + 1] = "Objectives: " .. objectives end
    if #parts > 0 then self:Speak(table.concat(parts, " ")) end
end

function R:ReadProgress()
    local title, text = Call(GetTitleText), Call(GetProgressText)
    if text then self:Speak((title and (title .. ". ") or "") .. text) end
end

function R:ReadReward()
    local title, text = Call(GetTitleText), Call(GetRewardText)
    if text then self:Speak((title and (title .. ". ") or "") .. text) end
end

function R:ReadGossip()
    if self.db.gossip == false then return end
    local text
    if C_GossipInfo and C_GossipInfo.GetText then text = Call(C_GossipInfo.GetText) end
    if not text and GetGossipText then text = Call(GetGossipText) end
    if text then self:Speak(text) end
end

function R:ReadGreeting()
    if self.db.gossip == false then return end
    local text = Call(GetGreetingText)
    if text then self:Speak(text) end
end

function R:OnEnable()
    if not (C_VoiceChat and C_VoiceChat.SpeakText) then self.reason = "C_VoiceChat.SpeakText missing on this client" return end
    self.available, self.reason = true, nil
    FO:RegisterEvent("QUEST_DETAIL", function() self:ReadDetail() end)
    FO:RegisterEvent("QUEST_PROGRESS", function() self:ReadProgress() end)
    FO:RegisterEvent("QUEST_COMPLETE", function() self:ReadReward() end)
    FO:RegisterEvent("QUEST_GREETING", function() self:ReadGreeting() end)
    FO:RegisterEvent("GOSSIP_SHOW", function() self:ReadGossip() end)
    FO:RegisterEvent("QUEST_FINISHED", function() self:Stop() end)
    FO:RegisterEvent("GOSSIP_CLOSED", function() self:Stop() end)
end

R.commands = {
    tts = { help = "read quest text aloud: (status) | on | off | again | stop | voice [n] | rate <-10..10> | volume <0..100> | gossip on|off | objectives on|off | test", fn = function(self, arg)
        local sub, rest = U.SplitCmd(arg or "")
        if not self.available then print("quest reader unavailable: %s", tostring(self.reason)) return end
        if sub == "" then
            local voices = self:Voices()
            local name = "?"
            for _, v in ipairs(voices) do if v.id == self:VoiceID() then name = v.name end end
            print("quest reader: %s, voice %s (%d available), rate %d, volume %d, gossip %s, objectives %s, %d texts read this session",
                self.db.enabled == false and "off" or "on", name, #voices, self.db.rate or 0, self.db.volume or 100,
                self.db.gossip == false and "off" or "on", self.db.objectives == false and "off" or "on", self.spoken)
        elseif sub == "on" then self.db.enabled = true print("quest reader on: quest and gossip windows are read aloud.")
        elseif sub == "off" then self.db.enabled = false self:Stop() print("quest reader off.")
        elseif sub == "stop" then self:Stop()
        elseif sub == "again" then if self.last then self:Speak(self.last, true) else print("nothing read yet.") end
        elseif sub == "voice" then
            local voices = self:Voices()
            local n = tonumber(rest)
            if n then
                for _, v in ipairs(voices) do
                    if v.id == n then self.db.voice = n print("voice %d: %s", v.id, v.name) self:Speak("This is " .. v.name .. ".", true) return end
                end
                print("no voice %d. /fo tts voice lists them.", n)
            else
                if #voices == 0 then print("no voices reported by the client.") return end
                print("%d voices (/fo tts voice <id>):", #voices)
                for _, v in ipairs(voices) do print("  %3d  %s%s", v.id, v.name, v.id == self:VoiceID() and "  (current)" or "") end
            end
        elseif sub == "rate" then
            local n = tonumber(rest)
            if n and n >= -10 and n <= 10 then self.db.rate = math.floor(n) print("rate %d", self.db.rate) self:Speak("Reading at this speed.", true) else print("rate <-10..10> (0 is normal)") end
        elseif sub == "volume" then
            local n = tonumber(rest)
            if n and n >= 0 and n <= 100 then self.db.volume = math.floor(n) print("volume %d", self.db.volume) self:Speak("Reading at this volume.", true) else print("volume <0..100>") end
        elseif sub == "gossip" then self.db.gossip = rest ~= "off" print("gossip reading %s.", self.db.gossip and "on" or "off")
        elseif sub == "objectives" then self.db.objectives = rest ~= "off" print("objectives %s.", self.db.objectives and "read after the description" or "skipped")
        elseif sub == "test" then
            if self:Speak("Quest reader test. Kill ten boars and bring me their tusks.", true) then print("speaking a test line.") else print("the client refused to speak; check Options > Accessibility > Text to Speech.") end
        else
            print("tts: on | off | again | stop | voice [n] | rate <n> | volume <n> | gossip on|off | objectives on|off | test")
        end
    end },
}
