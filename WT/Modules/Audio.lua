local _, WT = ...

WT.Modules.Audio = {}
local Module = WT.Modules.Audio

local function HasCustomSound(value)
    return value ~= nil and value ~= "None"
end

-- Blizzard sounds that WT replaces with a sound chosen by the user.
-- While the replacing feature is active (its module enabled and a custom sound selected),
-- the original Blizzard sound is muted so that both sounds don't play on top of each other.
-- IDs are FileDataIDs; verify them on https://wago.tools/files before changing anything.
local REPLACED_SOUNDS = {
    { -- "<name> has come online" chime (guild members and character friends)
        ids = { 567518 }, -- sound/interface/friendjoin.ogg
        condition = function()
            local db = WT.DB.Chat
            return WT.DB.Modules.Chat and db and db.SmartGuildLogins and HasCustomSound(db.SmartLoginSound)
        end,
    },
    { -- Incoming whisper / Battle.net whisper
        ids = { 567421 }, -- sound/interface/itellmessage.ogg
        condition = function()
            local db = WT.DB.ChatChannels
            return WT.DB.Modules.Chat and db and (HasCustomSound(db.ChanWhisperSound) or HasCustomSound(db.ChanBNetWhisperSound))
        end,
    },
    { -- Raid warning
        ids = { 567397 }, -- sound/interface/raidwarning.ogg
        condition = function()
            local db = WT.DB.ChatChannels
            return WT.DB.Modules.Chat and db and HasCustomSound(db.ChanRaidWarningSound)
        end,
    },
    { -- New applicant in the Group Finder
        ids = { 1067667 }, -- sound/interface/ui_groupfinderreceiveapplication_01.ogg
        condition = function()
            local db = WT.DB.LFG
            return WT.DB.Modules.Groups and db and db.AudioAlert and HasCustomSound(db.AudioAlertSound)
        end,
    },
}

-- Every FileDataID that WT itself has muted. Only these are ever unmuted again,
-- so mutes set by the game or by other addons are never touched.
local mutedByWT = {}

function Module:UpdateMutes()
    local wanted = {}

    -- Custom mute list from the Audio module
    if WT.DB.Modules.Audio and WT.DB.Audio.CustomMutes and WT.DB.Audio.CustomMutes ~= "" then
        for idStr in string.gmatch(WT.DB.Audio.CustomMutes, "([^,;%s]+)") do
            local id = tonumber(idStr)
            if id then wanted[id] = true end
        end
    end

    -- Blizzard sounds replaced by WT features (independent of the Audio module)
    for _, group in ipairs(REPLACED_SOUNDS) do
        if group.condition() then
            for _, id in ipairs(group.ids) do wanted[id] = true end
        end
    end

    for id in pairs(mutedByWT) do
        if not wanted[id] then
            UnmuteSoundFile(id)
            mutedByWT[id] = nil
        end
    end
    for id in pairs(wanted) do
        if not mutedByWT[id] then
            MuteSoundFile(id)
            mutedByWT[id] = true
        end
    end
end

function Module:Initialize()
    self:UpdateMutes()
end

WT.Core.Events:Register("PLAYER_LOGIN", function() Module:Initialize() end)

function Module:BuildOptions(builder, panel)
    local function AddDescription(text)
        if not text then return end
        local desc = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
        desc:SetWidth(550)
        desc:SetJustifyH("LEFT")
        desc:SetText(text)
        builder:AddSpace(desc:GetStringHeight() + 25)
    end

    panel:CreateTitle(builder, WT.L.CATEGORY_AUDIO)
    AddDescription(WT.L.OPT_DESC_MODULE_AUDIO_EXT)
    
    panel:CreateSlider(builder, WT.L.OPT_AUDIO_THROTTLE, WT.L.OPT_DESC_AUDIO_THROTTLE, "Audio", "SoundCooldown", 0, 30, 1)
    
    panel:CreateSubTitle(builder, WT.L.OPT_CHAT_CUSTOM_MUTES)
    AddDescription(WT.L.OPT_DESC_CHAT_CUSTOM_MUTES_EXT)
    
    panel:CreateMultiLineEditBox(builder, "", "", "Audio", "CustomMutes", 80, function() self:UpdateMutes() end)
end