local _, WT = ...

WT.Modules.ChatChannels = {}
local Module = WT.Modules.ChatChannels

local strtrim = strtrim or string.trim or function(s) return s and string.match(s, "^%s*(.-)%s*$") or "" end

local Unsecret = WT.Utils.Safety.Unsecret
local SafeNum = WT.Utils.Safety.SafeNum

local function CreateChannelRow(panel, builder, title, dbPrefix)
    panel:CreateSubTitle(builder, title)
    local soundInit = panel:CreateSoundDropdown(builder, WT.L.OPT_CHAN_SOUND, WT.L.OPT_DESC_CHAN_SOUND, "ChatChannels",
        dbPrefix .. "Sound", nil, function() if WT.Modules.Audio then WT.Modules.Audio:UpdateMutes() end end)

    local colInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAN_COLOR, WT.L.OPT_DESC_CHAN_COLOR, "ChatChannels",
        dbPrefix .. "ColorEnabled", nil)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_TEXT, WT.L.OPT_DESC_COLOR_VALUE, "ChatChannels", dbPrefix .. "Color",
        false, colInit)

    local aliasInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAN_ALIAS, WT.L.OPT_DESC_CHAN_ALIAS, "ChatChannels",
        dbPrefix .. "AliasEnabled", nil)
    panel:CreateEditBox(builder, WT.L.OPT_CHAN_NAME, WT.L.OPT_DESC_CHAN_ALIAS, "ChatChannels", dbPrefix .. "Alias",
        aliasInit)
end

local function CreateCustomChannelRow(panel, builder, title, dbPrefix)
    panel:CreateSubTitle(builder, title)
    local nameInit = panel:CreateEditBox(builder, WT.L.OPT_CHAN_NAME, WT.L.OPT_DESC_CHAN_NAME, "ChatChannels",
        dbPrefix .. "Name", nil)

    local enableInit = panel:CreateCheckbox(builder, WT.L.OPT_ENABLE, WT.L.OPT_DESC_ENABLE, "ChatChannels",
        dbPrefix .. "Enabled", nil, nameInit)
    panel:CreateSoundDropdown(builder, WT.L.OPT_CHAN_SOUND, WT.L.OPT_DESC_CHAN_SOUND, "ChatChannels", dbPrefix .. "Sound",
        nameInit, function() if WT.Modules.Audio then WT.Modules.Audio:UpdateMutes() end end)

    local colInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAN_COLOR, WT.L.OPT_DESC_CHAN_COLOR, "ChatChannels",
        dbPrefix .. "ColorEnabled", nil, nameInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_TEXT, WT.L.OPT_DESC_COLOR_VALUE, "ChatChannels", dbPrefix .. "Color",
        false, colInit)

    local histDesc = (WT.L.OPT_DESC_CHAN_HISTORY) ..
    "\n\n|cFFFF5555" ..
    (WT.L.OPT_DESC_CHAT_HISTORY_BLIZZ_RESTRICTION) ..
    "|r"
    panel:CreateCheckbox(builder, WT.L.OPT_CHAN_HISTORY, histDesc, "ChatChannels",
        dbPrefix .. "History", nil, nameInit)

    local aliasInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAN_ALIAS, WT.L.OPT_DESC_CHAN_ALIAS, "ChatChannels",
        dbPrefix .. "AliasEnabled", nil, nameInit)
    panel:CreateEditBox(builder, WT.L.OPT_CHAN_NAME, WT.L.OPT_DESC_CHAN_ALIAS, "ChatChannels", dbPrefix .. "Alias",
        aliasInit)
end

local function CreateColorSoundRow(panel, builder, title, dbPrefix)
    panel:CreateSubTitle(builder, title)
    panel:CreateSoundDropdown(builder, WT.L.OPT_CHAN_SOUND, WT.L.OPT_DESC_CHAN_SOUND, "ChatChannels", dbPrefix .. "Sound",
        nil, function() if WT.Modules.Audio then WT.Modules.Audio:UpdateMutes() end end)

    local colInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAN_COLOR, WT.L.OPT_DESC_CHAN_COLOR, "ChatChannels",
        dbPrefix .. "ColorEnabled", nil)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_TEXT, WT.L.OPT_DESC_COLOR_VALUE, "ChatChannels", dbPrefix .. "Color",
        false, colInit)
end

local function CreateSoundOnlyRow(panel, builder, title, dbPrefix)
    panel:CreateSubTitle(builder, title)
    panel:CreateSoundDropdown(builder, WT.L.OPT_CHAN_SOUND, WT.L.OPT_DESC_CHAN_SOUND, "ChatChannels", dbPrefix .. "Sound",
        nil, function() if WT.Modules.Audio then WT.Modules.Audio:UpdateMutes() end end)
end

local function CreateCustomSenderRow(panel, builder, title, dbPrefix)
    panel:CreateSubTitle(builder, title)
    local nameInit = panel:CreateEditBox(builder, WT.L.OPT_CHAN_SENDER_NAME,
        WT.L.OPT_DESC_CHAN_SENDER_NAME, "ChatChannels", dbPrefix .. "Name", nil)

    local enableInit = panel:CreateCheckbox(builder, WT.L.OPT_ENABLE, WT.L.OPT_DESC_ENABLE, "ChatChannels",
        dbPrefix .. "Enabled", nil, nameInit)
    panel:CreateSoundDropdown(builder, WT.L.OPT_CHAN_SOUND, WT.L.OPT_DESC_CHAN_SOUND, "ChatChannels", dbPrefix .. "Sound",
        nameInit, function() if WT.Modules.Audio then WT.Modules.Audio:UpdateMutes() end end)
end

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

    panel:CreateTitle(builder, WT.L.GROUP_CHAT_MUTES)
    AddDescription(WT.L.OPT_DESC_GROUP_CHAT_MUTES)
    panel:CreateCheckbox(builder, WT.L.OPT_CHAN_MUTE_COMBAT, WT.L.OPT_DESC_CHAN_MUTE_COMBAT,
        "ChatChannels", "MuteInCombat")
    panel:CreateCheckbox(builder, WT.L.OPT_CHAN_MUTE_AFK, WT.L.OPT_DESC_CHAN_MUTE_AFK, "ChatChannels",
        "MuteAFK")
    panel:CreateCheckbox(builder, WT.L.OPT_CHAN_MUTE_DND, WT.L.OPT_DESC_CHAN_MUTE_DND, "ChatChannels",
        "MuteDND")

    panel:CreateTitle(builder, WT.L.GROUP_CHAT_CHANNELS)
    AddDescription(WT.L.OPT_DESC_GROUP_CHAT_CHANNELS)
    CreateChannelRow(panel, builder, WT.L.BINDING_WHISPER, "ChanWhisper")
    CreateChannelRow(panel, builder, WT.L.BINDING_BNET_WHISPER, "ChanBNetWhisper")
    CreateChannelRow(panel, builder, WT.L.BINDING_GUILD, "ChanGuild")
    CreateChannelRow(panel, builder, WT.L.BINDING_PARTY, "ChanParty")
    CreateChannelRow(panel, builder, WT.L.BINDING_RAID, "ChanRaid")
    CreateChannelRow(panel, builder, WT.L.BINDING_INSTANCE, "ChanInstance")
    CreateChannelRow(panel, builder, WT.L.BINDING_OFFICER, "ChanOfficer")

    CreateColorSoundRow(panel, builder, WT.L.BINDING_SAY, "ChanSay")
    CreateColorSoundRow(panel, builder, WT.L.BINDING_YELL, "ChanYell")
    CreateSoundOnlyRow(panel, builder, WT.L.BINDING_EMOTE, "ChanEmote")
    CreateSoundOnlyRow(panel, builder, WT.L.BINDING_SYSTEM, "ChanSystem")
    CreateSoundOnlyRow(panel, builder, WT.L.BINDING_RAID_WARNING, "ChanRaidWarning")
    CreateSoundOnlyRow(panel, builder, WT.L.BINDING_COMMUNITIES, "ChanCommunities")
    CreateSoundOnlyRow(panel, builder, WT.L.BINDING_IGNORED, "ChanIgnored")

    panel:CreateTitle(builder, WT.L.GROUP_CHAT_CUSTOM_CHANNELS)
    AddDescription(WT.L.OPT_DESC_GROUP_CHAT_CUSTOM_CHANNELS)
    CreateCustomChannelRow(panel, builder, "Custom Channel 1", "CustomChan1")
    CreateCustomChannelRow(panel, builder, "Custom Channel 2", "CustomChan2")
    CreateCustomChannelRow(panel, builder, "Custom Channel 3", "CustomChan3")

    panel:CreateTitle(builder, WT.L.GROUP_CHAT_VIP)
    AddDescription(WT.L.OPT_DESC_GROUP_CHAT_VIP)
    CreateCustomSenderRow(panel, builder, "VIP Player 1", "CustomSender1")
    CreateCustomSenderRow(panel, builder, "VIP Player 2", "CustomSender2")
    CreateCustomSenderRow(panel, builder, "VIP Player 3", "CustomSender3")
end

function Module:Initialize()
    if not WT.DB.Modules.Chat then return end
    local function ChatSoundFilter(self, event, ...)
        if not WT.DB.Modules.Chat then return false end

        local msg, sender, _, channelString, _, _, _, channelNumber, channelName, _, _, guid, bnSenderID = ...

        -- BATTLE-SAFE: Prevent secret strings and numbers from crashing string/comparison operations
        local uMsg = Unsecret(msg)
        local uSender = Unsecret(sender)
        local uChannelString = Unsecret(channelString)
        local uChannelName = Unsecret(channelName)
        local uGuid = Unsecret(guid)
        local uChannelNumber = SafeNum(channelNumber) or 0
        local uBnSenderID = SafeNum(bnSenderID) or 0

        -- Prevent sound from playing multiple times when multiple chat frames are active
        local now = GetTime()
        local msgHash = tostring(uMsg) .. tostring(uSender) .. tostring(uChannelNumber)
        if Module.lastSoundMsg == msgHash and (now - (Module.lastSoundTime or 0) < 0.2) then
            return false
        end
        Module.lastSoundMsg = msgHash
        Module.lastSoundTime = now

        -- Direct fail-safe self check 0: Outgoing message sent recently by player
        local lastSend = (WT.Modules.Chat and WT.Modules.Chat.LastSendTime) or (WT.Modules.Chat_Filter and WT.Modules.Chat_Filter.LastSendTime) or 0
        if lastSend > 0 and (now - lastSend < 1.5) then
            return false
        end

        -- Direct fail-safe self check 1: Player GUID match
        local pGuid = UnitGUID("player")
        if uGuid and pGuid and uGuid ~= "" and uGuid == pGuid then
            return false
        end

        -- Direct fail-safe self check 2: Player Name match (immune to cross-realm suffixes and UTF-8 casing)
        local pName = UnitName("player")
        if uSender and pName and pName ~= "" then
            local sClean = tostring(uSender):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            sClean = sClean:gsub("|[Hh].-|[hH](.-)|[hH]", "%1"):gsub("|[Hh].-|[hH]", ""):gsub("|h", "")
            sClean = sClean:gsub("%s*%(%*%)", ""):gsub("[%[%]]", "")
            sClean = strtrim(sClean)
            local sBase = string.match(sClean, "^([^%-]+)") or sClean
            sBase = strtrim(sBase)
            local sBaseLower = (strlower and strlower(sBase)) or (_G["mbstrlower"] and _G["mbstrlower"](sBase)) or
            string.lower(sBase)
            local pLower = (strlower and strlower(pName)) or (_G["mbstrlower"] and _G["mbstrlower"](pName)) or
            string.lower(pName)
            if sBase == pName or (sBaseLower ~= "" and sBaseLower == pLower) or sClean == pName then
                return false
            end
        end

        local isSelf = WT.Modules.Chat:IsSelfMessage(event, uGuid, uBnSenderID, uSender, uMsg, uChannelString)
        if not isSelf and WT.Modules.Chat.DetectSelfMessage and uMsg then
            isSelf = WT.Modules.Chat.DetectSelfMessage(uMsg, uSender)
        end

        if isSelf then
            return false
        end

        if WT.DB.ChatChannels.MuteInCombat and InCombatLockdown() then return end
        if WT.DB.ChatChannels.MuteAFK and UnitIsAFK("player") then return end
        if WT.DB.ChatChannels.MuteDND and UnitIsDND("player") then return end

        local function CheckSenderMatches(senderName)
            if not senderName then return false end
            local sAmbig = Ambiguate(senderName, "none")
            local sLower = string.lower(sAmbig)
            for idx = 1, 3 do
                local cEnabled = WT.DB.ChatChannels["CustomSender" .. idx .. "Enabled"]
                local cName = WT.DB.ChatChannels["CustomSender" .. idx .. "Name"]
                local cSound = WT.DB.ChatChannels["CustomSender" .. idx .. "Sound"]
                if cEnabled and cName and cName ~= "" and cSound and cSound ~= "None" then
                    if string.find(string.lower(cName), sLower, 1, true) or string.find(sLower, string.lower(cName), 1, true) then
                        WT.Utils.Audio:Play(cSound, "SENDER" .. idx,
                            WT.DB.ChatChannels["CustomSender" .. idx .. "SoundChannel"])
                        return true
                    end
                end
            end
            return false
        end
        if CheckSenderMatches(uSender) then return end

        local dbPrefix
        if event == "CHAT_MSG_SAY" then
            dbPrefix = "ChanSay"
        elseif event == "CHAT_MSG_YELL" then
            dbPrefix = "ChanYell"
        elseif event == "CHAT_MSG_EMOTE" or event == "CHAT_MSG_TEXT_EMOTE" then
            dbPrefix = "ChanEmote"
        elseif event == "CHAT_MSG_SYSTEM" then
            local msgLower = string.lower(uMsg or "")
            if string.find(msgLower, "channel") or string.find(msgLower, "kanal") or string.find(msgLower, "passwort") or string.find(msgLower, "password") then
                return false
            end
            dbPrefix = "ChanSystem"
        elseif event == "CHAT_MSG_RAID_WARNING" then
            dbPrefix = "ChanRaidWarning"
        elseif event == "CHAT_MSG_IGNORED" then
            dbPrefix = "ChanIgnored"
        elseif event == "CHAT_MSG_WHISPER" then
            dbPrefix = "ChanWhisper"
        elseif event == "CHAT_MSG_BN_WHISPER" then
            dbPrefix = "ChanBNetWhisper"
        elseif event == "CHAT_MSG_GUILD" then
            dbPrefix = "ChanGuild"
        elseif event == "CHAT_MSG_OFFICER" then
            dbPrefix = "ChanOfficer"
        elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
            dbPrefix = "ChanParty"
        elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
            dbPrefix = "ChanRaid"
        elseif event == "CHAT_MSG_INSTANCE_CHAT" or event == "CHAT_MSG_INSTANCE_CHAT_LEADER" then
            dbPrefix = "ChanInstance"
        elseif event == "CHAT_MSG_CHANNEL" or event == "CHAT_MSG_COMMUNITIES_CHANNEL" then
            -- Prevents custom channel sounds from firing on "Invalid Channel" errors masquerading as channel messages
            if event == "CHAT_MSG_CHANNEL" and (not uChannelNumber or uChannelNumber == 0) then return false end

            local matchedCustom = false
            for idx = 1, 3 do
                local cEnabled = WT.DB.ChatChannels["CustomChan" .. idx .. "Enabled"]
                local cName = WT.DB.ChatChannels["CustomChan" .. idx .. "Name"]
                local cSound = WT.DB.ChatChannels["CustomChan" .. idx .. "Sound"]

                if cEnabled and cName and cName ~= "" and cSound and cSound ~= "None" then
                    local searchNameLower = string.lower(strtrim(cName))
                    if searchNameLower ~= "" then
                        local searchNum = tonumber(searchNameLower)
                        local isMatch = false

                        local cStr = uChannelString and string.lower(uChannelString) or ""
                        local cNameStr = uChannelName and string.lower(uChannelName) or ""

                        local cNum = tonumber(string.match(cNameStr, "^(%d+)%.")) or channelNumber
                        local cNameOnly = string.match(cNameStr, "^%d+%.%s*(.+)") or cNameStr

                        if searchNum then
                            if cNum == searchNum then isMatch = true end
                        else
                            if cNameOnly == searchNameLower or string.find(cNameOnly, searchNameLower, 1, true) then
                                isMatch = true
                            elseif cStr ~= "" and string.find(cStr, searchNameLower, 1, true) then
                                isMatch = true
                            end
                        end

                        if isMatch then
                            WT.Utils.Audio:Play(cSound, "CHANNEL", WT.DB.ChatChannels["CustomChan" .. idx .. "SoundChannel"])
                            matchedCustom = true
                            break
                        end
                    end
                end
            end
            if event == "CHAT_MSG_COMMUNITIES_CHANNEL" and not matchedCustom then
                dbPrefix = "ChanCommunities"
            end
        end

        if dbPrefix then
            local s = WT.DB.ChatChannels[dbPrefix .. "Sound"]
            if s and s ~= "None" then
                WT.Utils.Audio:Play(s, "CHANNEL", WT.DB.ChatChannels[dbPrefix .. "SoundChannel"])
            end
        end
        return false
    end

    local soundFrame = CreateFrame("Frame")
    soundFrame:SetScript("OnEvent", function(self, event, ...)
        pcall(ChatSoundFilter, self, event, ...)
    end)

    local events = {
        "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
        "CHAT_MSG_SYSTEM", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_IGNORED",
        "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL"
    }
    for _, ev in ipairs(events) do
        soundFrame:RegisterEvent(ev)
    end
end

WT.Core.Events:Register("PLAYER_LOGIN", function() Module:Initialize() end)
