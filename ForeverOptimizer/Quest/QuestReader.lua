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
    defaults = { enabled = true, gossip = true, objectives = true, voice = nil, rate = 0, volume = 100, path = 1 },
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
    local paths = self:Paths()
    local p = paths[self.db.path or 1]
    if not (p and p.available()) then
        p = nil
        for _, q in ipairs(paths) do if q.available() then p = q break end end
        if not p then return false end
    end
    local ok, err = pcall(p.speak, text, U.Num(self.db.rate) or 0, U.Num(self.db.volume) or 100)
    if not ok then print("tts: %s", tostring(err)) return false end
    self.last = text
    self.spoken = self.spoken + 1
    return true
end

function R:Stop()
    if C_VoiceChat and C_VoiceChat.StopSpeakingText then pcall(C_VoiceChat.StopSpeakingText) end
end

local function Call(fn) if type(fn) == "function" then local ok, v = pcall(fn) if ok then return U.Str(v) end end end

-- Diagnostics: what the client reports about its speech and voice chat state, then every
-- playback path tried a few seconds apart so the one that makes a sound can be named.
local function CVar(name)
    if not GetCVar then return "n/a" end
    local ok, v = pcall(GetCVar, name)
    return ok and v ~= nil and tostring(v) or "n/a"
end

local function VC(fnName, ...)
    local fn = C_VoiceChat and C_VoiceChat[fnName]
    if type(fn) ~= "function" then return "absent" end
    local ok, v = pcall(fn, ...)
    if not ok then return "err" end
    if type(v) == "table" then return U.Str(v.deviceName) or U.Str(v.name) or "table" end
    return tostring(v)
end

-- Every way this client might play speech. Each entry: name, available(), speak(text, rate, volume).
-- Path 1, the client's own chat-TTS wrapper, is the one that produces sound on Forever (verified
-- 2026-11-05); direct C_VoiceChat.SpeakText calls go through without audio there. /fo tts debug
-- tries them all and /fo tts path <n> picks another. The wrapper takes rate and volume from the
-- client's Accessibility settings, so ours are written there first when the setters exist.
local function hasVC() return C_VoiceChat and type(C_VoiceChat.SpeakText) == "function" end
local function hasBlizz() return type(TextToSpeech_Speak) == "function" end
local function ApplyClientSettings(r, v)
    local T = C_TTSSettings
    if not T then return end
    if T.SetSpeechRate then pcall(T.SetSpeechRate, r) end
    if T.SetSpeechVolume then pcall(T.SetSpeechVolume, v) end
end

function R:Paths()
    local dest = Enum and Enum.VoiceTtsDestination or {}
    local voice = self:VoiceID()
    return {
        { name = "client chat TTS (TextToSpeech_Speak)", available = hasBlizz, speak = function(t, r, v) ApplyClientSettings(r, v) TextToSpeech_Speak(t, { voiceID = voice }) end },
        { name = "client chat TTS with its own voice choice", available = hasBlizz, speak = function(t, r, v)
            ApplyClientSettings(r, v)
            local sel = (TextToSpeech_GetSelectedVoice and TextToSpeech_GetSelectedVoice()) or (TEXTTOSPEECH_CONFIG and TEXTTOSPEECH_CONFIG.ttsVoiceOptionStandard)
            TextToSpeech_Speak(t, sel) end },
        { name = "SpeakText, local playback", available = hasVC, speak = function(t, r, v) C_VoiceChat.SpeakText(voice, t, dest.LocalPlayback or 1, r, v) end },
        { name = "SpeakText, queued local playback", available = hasVC, speak = function(t, r, v) C_VoiceChat.SpeakText(voice, t, dest.QueuedLocalPlayback or 4, r, v) end },
        { name = "SpeakText, screen reader destination", available = hasVC, speak = function(t, r, v) C_VoiceChat.SpeakText(voice, t, dest.ScreenReader or 6, r, v) end },
        { name = "SpeakText, voice 0, destination 1", available = hasVC, speak = function(t, r, v) C_VoiceChat.SpeakText(0, t, 1, r, v) end },
    }
end

function R:Debug()
    local voices = self:Voices()
    local names = {}
    for i = 1, math.min(#voices, 4) do names[#names + 1] = voices[i].name end
    print("tts debug: %d voices%s; using voice %d", #voices, #names > 0 and (" (" .. table.concat(names, ", ") .. (#voices > 4 and ", ..." or "") .. ")") or "", self:VoiceID())
    local dest = Enum and Enum.VoiceTtsDestination
    local keys = {}
    if type(dest) == "table" then for k, v in pairs(dest) do keys[#keys + 1] = k .. "=" .. tostring(v) end table.sort(keys) end
    print("  Enum.VoiceTtsDestination: %s", #keys > 0 and table.concat(keys, " ") or "absent (using 1)")
    print("  voice chat: enabled %s, logged in %s, output device %s, output volume %s, muted %s, deafened %s",
        VC("IsEnabled"), VC("IsLoggedIn"), VC("GetActiveOutputDevice"), VC("GetOutputVolume"), VC("IsMuted"), VC("IsDeafened"))
    print("  cvars: EnableVoiceChat %s, VoiceChatMasterVolumeScale %s, Sound_EnableAllSound %s, Sound_MasterVolume %s, Sound_EnableSoundWhenGameIsInBackground %s, textToSpeech %s",
        CVar("EnableVoiceChat"), CVar("VoiceChatMasterVolumeScale"), CVar("Sound_EnableAllSound"), CVar("Sound_MasterVolume"), CVar("Sound_EnableSoundWhenGameIsInBackground"), CVar("textToSpeech"))
    print("  Blizzard TTS: TextToSpeech_Speak %s, C_TTSSettings %s, TextToSpeechFrame %s",
        type(TextToSpeech_Speak) == "function" and "present" or "absent", C_TTSSettings and "present" or "absent", TextToSpeechFrame and "present" or "absent")
    local paths = self:Paths()
    print("  trying %d playback paths, four seconds apart. Note which number you hear:", #paths)
    for i, p in ipairs(paths) do
        C_Timer.After((i - 1) * 4, function()
            if not p.available() then print("  path %d: %s: not on this client", i, p.name) return end
            local ok, err = pcall(p.speak, string.format("Quest reader path %d.", i), 0, 100)
            print("  path %d: %s: %s", i, p.name, ok and "called" or ("error " .. tostring(err)))
        end)
    end
    print("  then: /fo tts path <n> makes the reader use the one that worked (path 1 is the default).")
end

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
    tts = { help = "read quest text aloud: (status) | on | off | again | stop | voice [n] | rate <-10..10> | volume <0..100> | gossip on|off | objectives on|off | test | debug | path [n]; voice <name part> filters, voice more pages", fn = function(self, arg)
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
                -- long lists (a Mac reports every system voice) page 25 at a time; any other word filters by name
                local PAGE = 25
                local filter = rest ~= "" and rest ~= "more" and rest:lower() or nil
                local rows = {}
                for _, v in ipairs(voices) do if not filter or v.name:lower():find(filter, 1, true) then rows[#rows + 1] = v end end
                if filter and #rows == 0 then print("no voice matches '%s'. /fo tts voice lists them, /fo tts voice en finds English ones.", rest) return end
                if rest == "more" then self.voicePage = (self.voicePage or 0) + 1 else self.voicePage = 0 end
                local first = self.voicePage * PAGE + 1
                if first > #rows then self.voicePage = 0 first = 1 end
                local last = math.min(first + PAGE - 1, #rows)
                print("%d voices%s, %d-%d (/fo tts voice <id> picks one):", #rows, filter and (" matching '" .. rest .. "'") or "", first, last)
                for i = first, last do local v = rows[i] print("  %3d  %s%s", v.id, v.name, v.id == self:VoiceID() and "  (current)" or "") end
                if last < #rows then print("  ... %d more: /fo tts voice more, or /fo tts voice <part of a name> to filter.", #rows - last) end
            end
        elseif sub == "rate" then
            local n = tonumber(rest)
            if n and n >= -10 and n <= 10 then self.db.rate = math.floor(n) print("rate %d", self.db.rate) self:Speak("Reading at this speed.", true) else print("rate <-10..10> (0 is normal)") end
        elseif sub == "volume" then
            local n = tonumber(rest)
            if n and n >= 0 and n <= 100 then self.db.volume = math.floor(n) print("volume %d", self.db.volume) self:Speak("Reading at this volume.", true) else print("volume <0..100>") end
        elseif sub == "gossip" then self.db.gossip = rest ~= "off" print("gossip reading %s.", self.db.gossip and "on" or "off")
        elseif sub == "objectives" then self.db.objectives = rest ~= "off" print("objectives %s.", self.db.objectives and "read after the description" or "skipped")
        elseif sub == "debug" then self:Debug()
        elseif sub == "path" then
            local n, paths = tonumber(rest), self:Paths()
            if n and paths[n] then
                self.db.path = n
                print("reader uses path %d: %s%s", n, paths[n].name, paths[n].available() and "" or " (not on this client; the first available path is used)")
                self:Speak("Reading through path " .. n .. ".", true)
            else
                print("playback path %d of %d (/fo tts debug tries each one):", self.db.path or 1, #paths)
                for i, p in ipairs(paths) do print("  %d  %s%s", i, p.name, p.available() and "" or "  (not on this client)") end
            end
        elseif sub == "test" then
            if self:Speak("Quest reader test. Kill ten boars and bring me their tusks.", true) then print("speaking a test line.") else print("the client refused to speak; /fo tts debug tries every playback path. Leave Options > Accessibility > Text to Speech off, it narrates chat and loot.") end
        else
            print("tts: on | off | again | stop | voice [n] | rate <n> | volume <n> | gossip on|off | objectives on|off | test | debug | path [n]")
        end
    end },
}
