local _, WT = ...

WT.Modules.Audio = {}
local Module = WT.Modules.Audio

-- A dynamic registry for conditional hardcoded mutes.
-- Whenever a specific addon feature uses a custom sound (not "None"), 
-- the original Blizzard sounds listed in 'ids' will be muted.
local HARDCODED_MUTES = {
    {
        name = "Guild Logins",
        -- Extended list to include ALL known offline/online toasts and quick joins
        ids = { 567472, 567473, 567439, 567440, 567441, 567442, 567443, 567444, 567445, 567446, 642646, 642647, 1411325, 1411326, 3508930, 3508931, 567421 }, -- Guild567421 
        condition = function()
            return WT.DB.Chat and WT.DB.Chat.SmartGuildLogins and WT.DB.Chat.SmartLoginSound and WT.DB.Chat.SmartLoginSound ~= "None"
        end
    },
    {
        name = "Whispers",
        ids = { 567436 }, -- TellMessage (SoundKit 3081)
        condition = function()
            if not WT.DB.ChatChannels then return false end
            local w = WT.DB.ChatChannels.ChanWhisperSound and WT.DB.ChatChannels.ChanWhisperSound ~= "None"
            local bw = WT.DB.ChatChannels.ChanBNetWhisperSound and WT.DB.ChatChannels.ChanBNetWhisperSound ~= "None"
            return w or bw
        end
    },
    {
        name = "LFG Applicant",
        ids = { 1067667 }, -- UI_GroupFinderReceiveApplication_01
        condition = function()
            return WT.DB.LFG and WT.DB.LFG.AudioAlert and WT.DB.LFG.AudioAlertSound and WT.DB.LFG.AudioAlertSound ~= "None"
        end
    },
    {
        name = "Raid Warning",
        ids = { 567432 }, -- RaidWarning
        condition = function()
            return WT.DB.ChatChannels and WT.DB.ChatChannels.ChanRaidWarningSound and WT.DB.ChatChannels.ChanRaidWarningSound ~= "None"
        end
    },
}

local customMutedIDs = {}

function Module:UpdateMutes()
    if not WT.DB.Modules.Audio then
        for id in pairs(customMutedIDs) do UnmuteSoundFile(id) end
        wipe(customMutedIDs)
        for _, group in ipairs(HARDCODED_MUTES) do
            for _, id in ipairs(group.ids) do UnmuteSoundFile(id) end
        end
        
        -- Removed CVar resets here to prevent overriding user's native WoW settings.
        return
    end

    for id in pairs(customMutedIDs) do UnmuteSoundFile(id) end
    wipe(customMutedIDs)
    
    if WT.DB.Audio.CustomMutes and WT.DB.Audio.CustomMutes ~= "" then
        for idStr in string.gmatch(WT.DB.Audio.CustomMutes, "([^,;%s]+)") do
            local id = tonumber(idStr)
            if id then MuteSoundFile(id); customMutedIDs[id] = true end
        end
    end
    
    for _, group in ipairs(HARDCODED_MUTES) do
        local shouldMute = group.condition()
        for _, id in ipairs(group.ids) do
            if not customMutedIDs[id] then
                if shouldMute then MuteSoundFile(id) else UnmuteSoundFile(id) end
            end
        end
    end
    
    -- Removed CVar overrides that forcefully disabled visual toasts and chat messages.
    -- MuteSoundFile handles the audio suppression safely on its own without breaking visual UI elements.
end

function Module:Initialize()
    if not WT.DB.Modules.Audio then return end
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