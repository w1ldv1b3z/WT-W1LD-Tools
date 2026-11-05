local _, WT = ...

WT.Utils.Audio = {}
local Audio = WT.Utils.Audio

local lastSoundTimes = { HIGHLIGHT = 0, CHANNEL = 0, GLOBAL = 0 }
local addonLoadTime = GetTime()

Audio.w1ldSounds = {
    ["W1LD - 01"] = 642841, -- UI_Pet_Levelup_01
    ["W1LD - 02"] = 1067667, -- UI_GroupFinderReceiveApplication_01
    ["W1LD - 03"] = 2173884, -- UI_80_Scrapping_Window_Open
    ["W1LD - 04"] = 7466100, -- 12.0_UI_Alert_Tonal_Guitar_Chug_Triplets_7466100
    ["W1LD - 05"] = 5342387, -- 10.1.7_UI_PingSystem_WarningDanger
    ["W1LD - 06"] = 899283, -- UI_DigsiteCompletionToast
    ["W1LD - 07"] = 4191878, -- UI_91_ToastGeneric_02_Stereo
    ["W1LD - 08"] = 18019, -- UI_BnetToast 
    ["W1LD - 09"] = 876098, -- UI_RaidBossWhisperWarning
    ["W1LD - 10"] = 4191882, -- UI_91_ToastGeneric_04_Stereo
}

-- Inject custom media sounds
if WT.CustomMedia and WT.CustomMedia.Sounds then
    for sName, sPath in pairs(WT.CustomMedia.Sounds) do
        Audio.w1ldSounds[sName] = sPath
    end
end

Audio.standardSounds = {
    ["None"] = nil, ["Bell"] = 12867, ["Chime"] = 8959, ["Ding"] = 5274,
    ["Gong"] = 12889, ["Splash"] = 6235076, ["ReadyCheck"] = 8960,
}

local resolvedSoundCache = {}
local cachedLSM = nil
local hasCheckedLSM = false

local function GetLSM()
    if not hasCheckedLSM then
        cachedLSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        hasCheckedLSM = true
    end
    return cachedLSM
end

function Audio:Play(sName, cooldownKey, channel)
    if not sName or sName == "None" or sName == "Kein Sound" or sName == "No Sound" then return end
    local currentTime = GetTime()
    
    -- Prevents spam during initial login, reload, or loading screens
    if (currentTime - addonLoadTime < 2) or (currentTime - (WT.Core.LoadTime or 0) < 2) then return end
    
    if cooldownKey == "PREVIEW" then
        local lastPreview = lastSoundTimes["PREVIEW"] or 0
        if (currentTime - lastPreview < 0.3) then return end
        lastSoundTimes["PREVIEW"] = currentTime
        cooldownKey = nil
    end
    
    if cooldownKey then
        local lastTime = lastSoundTimes[cooldownKey] or 0
        local lastGlobal = lastSoundTimes["GLOBAL"] or 0
        
        local cd = (WT.DB and WT.DB.Audio and WT.DB.Audio.SoundCooldown) and WT.DB.Audio.SoundCooldown or 4
        local globalCd = math.min(2, cd)
        
        if (currentTime - lastGlobal < globalCd) then return end
        if (currentTime - lastTime < cd) then return end
        
        lastSoundTimes[cooldownKey] = currentTime
        lastSoundTimes["GLOBAL"] = currentTime
    end
    
    local playChannel = channel or "Master"
    local soundData = self.w1ldSounds[sName] or self.standardSounds[sName]
    local willPlay
    if soundData then
        if type(soundData) == "string" then
            willPlay = PlaySoundFile(soundData, playChannel)
        elseif type(soundData) == "number" and soundData > 250000 then
            local ok
            ok, willPlay = pcall(PlaySoundFile, soundData, playChannel)
            if not ok or willPlay == false then
                pcall(PlaySound, 8960, playChannel)
            end
        else
            local ok
            ok, willPlay = pcall(PlaySound, soundData, playChannel)
            if not ok or willPlay == false then
                pcall(PlaySound, 8960, playChannel)
            end
        end
    else
        soundData = resolvedSoundCache[sName]
        if not soundData then
            local LSM = GetLSM()
            local lsmSound = LSM and LSM:Fetch("sound", sName)
            if lsmSound then
                local soundNum = type(lsmSound) == "number" and lsmSound or tonumber(tostring(lsmSound))
                soundData = soundNum or tostring(lsmSound)
                resolvedSoundCache[sName] = soundData
            end
        end
        if soundData then
            willPlay = PlaySoundFile(soundData, playChannel)
        end
    end

    -- Logger:Debug only prints while debug mode is enabled (/wt debug)
    WT.Utils.Logger:Debug(string.format(WT.L.MSG_DEBUG_AUDIO, tostring(sName), tostring(soundData),
        willPlay and WT.L.LBL_YES or WT.L.LBL_NO))
end