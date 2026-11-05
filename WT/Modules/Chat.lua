local _, WT = ...

WT.Modules.Chat = {}
local Module = WT.Modules.Chat

local strtrim = strtrim or string.trim or function(s) return s and string.match(s, "^%s*(.-)%s*$") or "" end
local strsplit = strsplit or string.split or function(d, s)
    if not s then return nil end
    local t, i = {}, 1
    while true do
        local j = string.find(s, d, i, true)
        if not j then
            table.insert(t, string.sub(s, i))
            break
        end
        table.insert(t, string.sub(s, i, j - 1))
        i = j + #d
    end
    return (unpack or rawget(table, "unpack"))(t)
end

local Unsecret = WT.Utils.Safety.Unsecret
local SafeNum = WT.Utils.Safety.SafeNum

local SafeUnitIsAFK = WT.Utils.Units.SafeUnitIsAFK

local function IsSafeString(str)
    if type(str) == "number" then return true end
    if type(str) == "string" then return true end
    return false
end

local function SafeLower(str)
    if not str or type(str) ~= "string" then return "" end
    if strlower then return strlower(str) end
    if _G["mbstrlower"] then return _G["mbstrlower"](str) end
    return string.lower(str)
end

local cachedPlayerName = nil
local cachedPlayerGuid = nil

local function GetPlayerIdentity()
    if not cachedPlayerName then
        local ok, n = pcall(UnitName, "player")
        if ok and n and n ~= "" and n ~= "Unknown" then cachedPlayerName = n end
    end
    if not cachedPlayerGuid then
        local ok, g = pcall(UnitGUID, "player")
        if ok and g and g ~= "" then cachedPlayerGuid = g end
    end
    return cachedPlayerName, cachedPlayerGuid
end

local Ambiguate = Ambiguate or
    function(name, context)
        return name and
            ((context == "short" or context == "guild") and string.match(name, "^([^%-]+)") or name) or ""
    end

function Module:IsSelfMessage(event, guid, bnSenderID, sender, msg, channelString, _)
    local safeSender = Unsecret(sender)
    local safeGuid = Unsecret(guid)
    local safeChan = Unsecret(channelString)
    local safeMsg = Unsecret(msg)

    local pName, pGuid = GetPlayerIdentity()
    if not pGuid and UnitGUID then pGuid = UnitGUID("player") end
    if not pName and UnitName then pName = UnitName("player") end
    pName = pName or ""

    if safeGuid and safeGuid ~= "" and pGuid and pGuid ~= "" and safeGuid == pGuid then
        return true
    end

    local bnetID = SafeNum(bnSenderID) or 0
    if bnetID == 0 and bnSenderID ~= nil then
        local ok = pcall(function() return bnSenderID == "" end)
        if ok then bnetID = SafeNum(tonumber(bnSenderID)) or 0 end
    end

    if event == "CHAT_MSG_COMMUNITIES_CHANNEL" and safeChan and bnetID > 0 then
        local clubId = string.match(safeChan, "Community:(%d+):")
        if type(clubId) == "string" then
            local ok, memberInfo = false, nil

            -- Feature Compatibility: The Communities API (C_Club) is exclusive to the modern client.
            if C_Club and C_Club.GetMemberInfo then
                ok, memberInfo = pcall(C_Club.GetMemberInfo, clubId, bnetID)
            end

            if ok and memberInfo and memberInfo.isSelf then
                return true
            end
        end
    end

    if bnetID > 0 and event ~= "CHAT_MSG_COMMUNITIES_CHANNEL" then
        local okBN, myInfo = false, nil
        if C_BattleNet and C_BattleNet.GetMyAccountInfo then okBN, myInfo = pcall(C_BattleNet.GetMyAccountInfo) end
        if okBN and myInfo and myInfo.bnetAccountID == bnetID then
            return true
        end

        local okAcc, acc = false, nil
        if C_BattleNet and C_BattleNet.GetAccountInfoByID then okAcc, acc = pcall(C_BattleNet.GetAccountInfoByID, bnetID) end
        if okAcc and acc and acc["isSelf"] then
            return true
        end
    end

    if safeSender and safeSender ~= "" then
        local s = safeSender
        if string.find(s, "|", 1, true) then
            s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|[Kk].-|[kK]", "")
            s = string.gsub(s, "|[Tt].-|[tT]", ""):gsub("|[Aa].-|[aA]", "")
            s = string.gsub(s, "|[Hh].-|[hH](.-)|[hH]", "%1"):gsub("|[Hh].-|[hH]", ""):gsub("|h", "")
        end
        s = string.gsub(s, "%s*%(%*%)", "")
        s = string.gsub(s, "[%[%]]", "")
        s = strtrim(s)

        local pLower = SafeLower(pName)
        local sLower = SafeLower(s)

        -- 1. Direct name match (e.g. "Gaìjín" == "Gaìjín")
        if s == pName or (pLower ~= "" and sLower == pLower) then
            return true
        end

        local sBase = string.match(s, "^([^%-]+)")
        if sBase then sBase = strtrim(sBase) end
        local sBaseLower = sBase and SafeLower(sBase) or ""

        -- 2. Base name match (Name part before realm dash matches player, regardless of cross-realm tag)
        if sBase and pName ~= "" and (sBase == pName or (sBaseLower ~= "" and sBaseLower == pLower)) then
            return true
        end

        local sAmbig = Ambiguate(s, "short")
        if sAmbig then sAmbig = strtrim(string.gsub(sAmbig, "%s*%(%*%)", "")) end
        local sAmbigLower = sAmbig and SafeLower(sAmbig) or ""
        if sAmbig and pName ~= "" and (sAmbig == pName or (sAmbigLower ~= "" and sAmbigLower == pLower)) then
            return true
        end

        local ok1, isU1 = pcall(UnitIsUnit, s, "player")
        local ok2, isU2 = pcall(UnitIsUnit, sAmbig, "player")
        if (ok1 and isU1) or (ok2 and isU2) then
            return true
        end

        local okBN, myInfo = false, nil
        if C_BattleNet and C_BattleNet.GetMyAccountInfo then okBN, myInfo = pcall(C_BattleNet.GetMyAccountInfo) end
        if okBN and myInfo then
            if myInfo.battleTag and SafeLower(s) == SafeLower(myInfo.battleTag) then
                return true
            end
            if myInfo.battleTag then
                local bName = strsplit("#", myInfo.battleTag)
                if bName and SafeLower(s) == SafeLower(bName) then
                    return true
                end
                if bName and sBase and SafeLower(sBase) == SafeLower(bName) then
                    return true
                end
            end
            if myInfo.accountName and SafeLower(s) == SafeLower(myInfo.accountName) then
                return true
            end
        end

        local okLegacy, accountName, myBattleTag = false, nil, nil
        if BNGetInfo then okLegacy, _, accountName, myBattleTag = pcall(BNGetInfo) end
        if okLegacy then
            if type(myBattleTag) == "string" then
                if SafeLower(s) == SafeLower(myBattleTag) then
                    return true
                end
                local bName = strsplit("#", myBattleTag)
                if bName and SafeLower(s) == SafeLower(bName) then
                    return true
                end
                if bName and sBase and SafeLower(sBase) == SafeLower(bName) then
                    return true
                end
            end
            if type(accountName) == "string" and SafeLower(s) == SafeLower(accountName) then
                return true
            end
        end

        -- ULTIMATE FALLBACK: If the base name matches our character name
        if sBase and pName ~= "" and (sBase == pName or (sBaseLower ~= "" and sBaseLower == pLower)) then
            return true
        end
    end

    -- Hard-Block for Communities to cover completely stripped/masked |K messages (similar to CSC)
    local isMaskedEvent = (event == "CHAT_MSG_COMMUNITIES_CHANNEL") or
        (event == "CHAT_MSG_CHANNEL" and safeSender and string.find(safeSender, "|[Kk]"))
    local lastSend = WT.Modules.Chat.LastSendTime or 0
    local lastCommSend = WT.Modules.Chat.LastCommunitySendTime or 0
    local mostRecentSend = math.max(lastSend, lastCommSend)

    if isMaskedEvent and mostRecentSend > 0 and (GetTime() - mostRecentSend < 3.0) then
        return true
    end

    -- 100% BULLETPROOF TEXT CACHE FALLBACK
    -- If the WoW API completely fails to identify the sender (e.g., severe BNet lag),
    -- we check if the exact text was sent by the player within the last 15 seconds.
    if safeMsg and WT.Modules.Chat.LastSentMessages then
        local cleanMsg = safeMsg
        if string.find(cleanMsg, "|", 1, true) then
            cleanMsg = string.gsub(cleanMsg, "|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            cleanMsg = string.gsub(cleanMsg, "|[Hh].-|[hH](.-)|[hH]", "%1"):gsub("|[Tt].-|[tT]", ""):gsub("|[Aa].-|[aA]",
                ""):gsub("|[Kk].-|[kK]", "")
        end
        local payload = string.match(cleanMsg, "^%b[]%s*%b[]%s*:%s*(.*)")
        if not payload then payload = string.match(cleanMsg, "^%b[]%s*:%s*(.*)") end
        if not payload then payload = string.match(cleanMsg, ":%s*(.*)$") end
        if payload and payload ~= "" then cleanMsg = payload end

        local pureMsg = string.lower(string.gsub(cleanMsg, "[%p%s]", ""))
        if pureMsg == "" then pureMsg = string.lower(strtrim(cleanMsg)) end

        if pureMsg ~= "" then
            local now = GetTime()
            for i = #WT.Modules.Chat.LastSentMessages, 1, -1 do
                local sent = WT.Modules.Chat.LastSentMessages[i]
                if now - sent.time < 15.0 and sent.text ~= "" then
                    local pureSent = string.lower(string.gsub(sent.text, "[%p%s]", ""))
                    if pureSent == "" then pureSent = string.lower(strtrim(sent.text)) end

                    if pureSent == pureMsg or string.find(pureMsg, pureSent, 1, true) or string.find(pureSent, pureMsg, 1, true) then
                        return true
                    end
                end
            end
        end
    end

    return false
end

function Module:ApplyHooksToNewFrames()
    if self.HookAddMessage then self:HookAddMessage() end
    if self.UpdateInputHistoryHooks then self:UpdateInputHistoryHooks() end
end

-- Function to globally enable or disable class colors in chat
function Module:UpdateClassColors(enable)
    if WT.Utils and WT.Utils.Flags then
        WT.Utils.Flags:SetCVar("colorChatNamesByClass", enable and "1" or "0")
    else
        pcall(function() C_CVar.SetCVar("colorChatNamesByClass", enable and "1" or "0") end)
    end
end

function Module:UpdateChatBubbles(enable)
    local val = enable and "1" or "0"
    if WT.Utils and WT.Utils.Flags then
        WT.Utils.Flags:SetCVar("chatBubblesParty", val)
    else
        pcall(function() C_CVar.SetCVar("chatBubblesParty", val) end)
    end
end

function Module:GetTimestampString()
    if not WT.DB.Chat.Timestamps then return "" end
    local formatStr = WT.DB.Chat.TimestampFormat or "%H:%M"
    local colorStr = type(WT.DB.Chat.TimestampColor) == "table" and
        (WT.Colors and WT.Colors.GetHex and WT.Colors:GetHex(WT.DB.Chat.TimestampColor) or "888888") or
        WT.DB.Chat.TimestampColor or "888888"
    if type(colorStr) == "table" then colorStr = "888888" end
    colorStr = string.gsub(colorStr, "^#", "")
    if #colorStr < 8 then colorStr = "FF" .. colorStr end

    local style = WT.DB.Chat.TimestampStyle or 1
    local bCol = type(WT.DB.Chat.TimestampBracketColor) == "table" and
        (WT.Colors and WT.Colors.GetHex and WT.Colors:GetHex(WT.DB.Chat.TimestampBracketColor) or "888888") or
        WT.DB.Chat.TimestampBracketColor or "888888"
    if type(bCol) == "table" then bCol = "888888" end
    bCol = string.gsub(bCol, "^#", "")
    if #bCol < 8 then bCol = "FF" .. bCol end

    local b1, b2 = "", ""
    if style == 1 then
        b1, b2 = "(", ")"
    elseif style == 2 then
        b1, b2 = "[", "]"
    elseif style == 3 then
        b1, b2 = "", " |"
    end

    local tsString = ""
    if b1 ~= "" then tsString = tsString .. "|c" .. bCol .. b1 .. "|r" end
    tsString = tsString .. "|c" .. colorStr .. date(formatStr) .. "|r"
    if b2 ~= "" then tsString = tsString .. "|c" .. bCol .. b2 .. "|r" end
    return tsString .. " "
end

local lastAutoGz = 0

function Module:FixBlizzardBugs()
    -- Fix for monster_say taint in 10.1.5+ caused by AddOns hooking ChatFrame:AddMessage
    if _G.ChatHistory_GetAccessID then
        local oldGetAccessID = _G.ChatHistory_GetAccessID
        _G.ChatHistory_GetAccessID = function(chatType, chatTarget)
            if type(chatTarget) == "string" and scrub then
                local cleanTarget = scrub(chatTarget)
                if cleanTarget ~= chatTarget then
                    return oldGetAccessID(chatType, cleanTarget or "")
                end
            end
            return oldGetAccessID(chatType, chatTarget)
        end
    end
end

function Module:Initialize()
    if not WT.DB.Modules.Chat then return end

    if WT.DB.Chat.ClassColors then self:UpdateClassColors(true) end
    if WT.DB.Chat.SmartGuildLogins then
        self:UpdateSmartLogins(true)
    end

    self:UpdateChatFilters()
    self:HookAddMessage()

    if self.FixBlizzardBugs then self:FixBlizzardBugs() end

    if _G["FCF_OpenTemporaryWindow"] then
        hooksecurefunc("FCF_OpenTemporaryWindow", function() Module:ApplyHooksToNewFrames() end)
    end
    if _G["FCF_OpenNewWindow"] then
        hooksecurefunc("FCF_OpenNewWindow", function() Module:ApplyHooksToNewFrames() end)
    end

    if WT.DB.Chat.ShowPlayerLevels then
        self:UpdatePlayerLevelCache()
    end

    local cacheTimer
    local function TriggerCacheUpdate()
        if cacheTimer then cacheTimer:Cancel() end
        cacheTimer = C_Timer.NewTimer(0.5, function()
            if Module.BuildRosterCache then Module:BuildRosterCache() end
            if Module.UpdatePlayerLevelCache then Module:UpdatePlayerLevelCache() end
        end)
    end

    WT.Core.Events:Register("GUILD_ROSTER_UPDATE", TriggerCacheUpdate)
    WT.Core.Events:Register("GROUP_ROSTER_UPDATE", TriggerCacheUpdate)
    WT.Core.Events:Register("FRIENDLIST_UPDATE", TriggerCacheUpdate)
    WT.Core.Events:Register("BN_FRIEND_INFO_CHANGED", TriggerCacheUpdate)
    WT.Core.Events:Register("BN_FRIEND_LIST_SIZE_CHANGED", TriggerCacheUpdate)
    WT.Core.Events:Register("PLAYER_TARGET_CHANGED", function() Module:CacheUnitLevel("target") end)
    WT.Core.Events:Register("UPDATE_MOUSEOVER_UNIT", function() Module:CacheUnitLevel("mouseover") end)

    local function CheckSelfGuildAchiev(guid, sender)
        local sGuid = Unsecret(guid)
        local sSender = Unsecret(sender)
        if sGuid and sGuid == UnitGUID("player") then return true end
        if sSender and sSender ~= "" then return Ambiguate(sSender, "none") == UnitName("player") end
        return false
    end

    local lastGuildAchievSound = 0
    local guildAchievCache = {}

    WT.Core.Events:Register("CHAT_MSG_GUILD_ACHIEVEMENT", function(_, msg, sender, _, _, _, _, _, _, _, _, _, guid)
        local uMsg = Unsecret(msg)
        local uSender = Unsecret(sender)
        local uGuid = Unsecret(guid)
        if not uMsg or not IsSafeString(uMsg) then return end

        -- Spam protection: Ignore achievements pushed by the server as catch-up during login (15-second buffer)
        if GetTime() - (WT.Core.LoadTime or 0) < 15 then return end

        -- Server bug protection: Ignore duplicate achievements from the same player in the same session
        local achID = string.match(uMsg, "achievement:(%d+):")
        local cacheKey = (uGuid and achID) and (uGuid .. "_" .. achID) or nil
        if cacheKey then
            if guildAchievCache[cacheKey] then return end
            guildAchievCache[cacheKey] = true
        end

        local ok, isSelf = pcall(CheckSelfGuildAchiev, uGuid, uSender)

        if WT.DB.Chat.GuildAchievEnabled then
            if not isSelf or WT.DB.Chat.GuildAchievSelf then
                -- Global throttle to prevent overlapping sounds during achievement bursts
                if GetTime() - lastGuildAchievSound > 2.0 then
                    lastGuildAchievSound = GetTime()
                    WT.Utils.Audio:Play(WT.DB.Chat.GuildAchievSound, "CHANNEL", WT.DB.Chat.GuildAchievSoundChannel)
                end
            end
        end

        if WT.DB.Chat.AutoGZ and not isSelf and not SafeUnitIsAFK("player") then
            local currentTime = GetTime()
            if currentTime - lastAutoGz > 30 then
                lastAutoGz = currentTime
                local rawTxt = WT.DB.Chat.AutoGZText or "GZ!"
                local options = {}; for str in string.gmatch(rawTxt, "([^,]+)") do
                    if strtrim(str) ~= "" then
                        table
                            .insert(options, strtrim(str))
                    end
                end
                local txt = #options > 0 and options[math.random(1, #options)] or "GZ!"

                C_Timer.After(math.random(40, 90) / 10.0, function()
                    if not InCombatLockdown() and not SafeUnitIsAFK("player") and IsInGuild() then
                        local finalTxt = txt
                        local f = rawget(_G, "SendChatMessage")
                        if type(f) == "function" then
                            -- API Safety: Prevents immediate client disconnects caused by hidden line breaks
                            finalTxt = string.gsub(finalTxt, "[\r\n]", "")
                            f(finalTxt, "GUILD")
                        end
                    end
                end)
            end
        end
    end)
end

WT.Core.Events:Register("PLAYER_LOGIN", function()
    Module:Initialize()

    -- Defer the heavy guild roster calculation to prevent login stutters
    C_Timer.After(2.0, function()
        if IsInGuild() then
            C_GuildInfo.GuildRoster()
            if Module.BuildRosterCache then Module:BuildRosterCache() end
        end
    end)
end)

-- Function to build the module's option panel
function Module:BuildOptions(builder, panel)
    local function PromptReload()
        if WT.Config and WT.Config.OptionsPanel and WT.Config.OptionsPanel.ShowReloadPrompt then
            WT.Config.OptionsPanel:ShowReloadPrompt()
        end
    end

    local function AddDescription(text)
        if not text then return end
        local desc = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
        desc:SetWidth(550)
        desc:SetJustifyH("LEFT")
        desc:SetText(text)
        builder:AddSpace(desc:GetStringHeight() + 25)
    end

    panel:CreateTitle(builder, WT.L.GROUP_CHAT_HISTORY)
    local descText = (WT.L.OPT_DESC_GROUP_CHAT_HISTORY)
    descText = descText ..
    "\n\n|cFFFF5555" ..
    (WT.L.OPT_DESC_CHAT_HISTORY_BLIZZ_RESTRICTION) ..
    "|r"
    AddDescription(descText)

    local memHint = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    memHint:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
    memHint:SetWidth(550)
    memHint:SetJustifyH("LEFT")
    memHint:SetText(WT.L.OPT_DESC_CHAT_HISTORY_RAM_HINT)
    memHint:SetTextColor(WT.Colors.SUBTEXT_R, WT.Colors.SUBTEXT_G, WT.Colors.SUBTEXT_B)
    builder:AddSpace(memHint:GetStringHeight() + 25)

    local histInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_HISTORY, WT.L.OPT_DESC_CHAT_HISTORY, "Chat",
        "ChatHistory", PromptReload)
    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_HIST_INCLUDE_GEN, WT.L.OPT_DESC_CHAT_HIST_INCLUDE_GEN, "Chat",
        "HistoryIncludeGeneral", nil, histInit)
    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_HIST_GEN, WT.L.OPT_DESC_CHAT_HIST_GEN, "Chat", "HistoryChanGeneral", nil,
        histInit)
    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_HIST_TRADE, WT.L.OPT_DESC_CHAT_HIST_TRADE, "Chat", "HistoryChanTrade",
        nil, histInit)
    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_HIST_LOCAL, WT.L.OPT_DESC_CHAT_HIST_LOCAL, "Chat", "HistoryChanLocalDef",
        nil, histInit)
    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_HIST_SERV, WT.L.OPT_DESC_CHAT_HIST_SERV, "Chat", "HistoryChanServices",
        nil, histInit)

    panel:CreateSlider(builder, WT.L.OPT_CHAT_HIST_LINES, WT.L.OPT_DESC_CHAT_HIST_LINES, "Chat", "HistoryMaxLines", 10,
        500, 10, nil, histInit)

    builder:AddSpace(20)
    panel:CreateTitle(builder, WT.L.GROUP_CHAT_VISUALS)
    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_BUBBLES_PARTY,
        WT.L.OPT_DESC_CHAT_BUBBLES_PARTY, "Chat", "ChatBubblesParty", function(value) self:UpdateChatBubbles(value) end)

    panel:CreateButton(builder, " ", WT.L.BTN_CLEAR_CHAT_HIST, "", function()
        if WT.DB.Internal.ChatLog then wipe(WT.DB.Internal.ChatLog) end
        for _, frameName in ipairs(CHAT_FRAMES or {}) do
            local cf = _G[frameName]
            if cf then
                if type(cf.Clear) == "function" then cf:Clear() end
                if cf.historyBuffer and type(cf.historyBuffer.Clear) == "function" then cf.historyBuffer:Clear() end
                cf:AddMessage(" "); cf:Clear()
            end
        end
        if WT.Utils and WT.Utils.Logger then WT.Utils.Logger:Print(WT.L.MSG_CHAT_HIST_CLEARED) end
    end)

    local inpInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_INPUT_HISTORY, WT.L.OPT_DESC_CHAT_INPUT_HISTORY, "Chat",
        "InputHistory", PromptReload)
    panel:CreateSlider(builder, WT.L.OPT_CHAT_INPUT_HIST_LINES, WT.L.OPT_DESC_CHAT_INPUT_HIST_LINES, "Chat",
        "InputHistoryMaxLines", 5, 100, 5, nil, inpInit)

    panel:CreateButton(builder, " ", WT.L.BTN_CLEAR_INPUT_HIST, "", function()
        if WT.DB.Internal.InputLog then wipe(WT.DB.Internal.InputLog) end
        for i = 1, 50 do
            local eb = _G["ChatFrame" .. i .. "EditBox"]
            if eb and type(eb.ClearHistory) == "function" then eb:ClearHistory() end
        end
        if WT.Utils and WT.Utils.Logger then WT.Utils.Logger:Print(WT.L.MSG_INPUT_CLEARED) end
    end)

    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_RESTORE_TABS, WT.L.OPT_DESC_CHAT_RESTORE_TABS, "Chat", "RestoreTempTabs",
        PromptReload)





    panel:CreateTitle(builder, WT.L.GROUP_CHAT_GUILD)
    AddDescription(WT.L.OPT_DESC_GROUP_CHAT_GUILD)

    local slInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_SMART_LOGINS, WT.L.OPT_DESC_CHAT_SMART_LOGINS, "Chat",
        "SmartGuildLogins",
        function(value)
            self:UpdateSmartLogins(value); if WT.Modules.Audio then WT.Modules.Audio:UpdateMutes() end
        end)
    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_SHOW_FRIEND_LOGINS,
        WT.L.OPT_DESC_CHAT_SHOW_FRIEND_LOGINS, "Chat", "SmartLoginShowFriends", nil, slInit)
    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_SHOW_BNET_LOGINS,
        WT.L.OPT_DESC_CHAT_SHOW_BNET_LOGINS, "Chat", "SmartLoginShowBNetFriends", nil, slInit)
    if WT.Utils and WT.Utils.SharedMedia then
        panel:CreateSoundDropdown(builder, WT.L.OPT_CHAT_LOGIN_SOUND, WT.L.OPT_DESC_CHAT_LOGIN_SOUND,
            "Chat", "SmartLoginSound", slInit, function() if WT.Modules.Audio then WT.Modules.Audio:UpdateMutes() end end)
    end
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LOGIN, WT.L.OPT_DESC_COLOR_LOGIN, "Chat", "ColGuildLogin", false,
        slInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LOGOUT, WT.L.OPT_DESC_COLOR_LOGOUT, "Chat", "ColGuildLogout", false,
        slInit)

    local noteInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_GUILD_NOTES, WT.L.OPT_DESC_CHAT_GUILD_NOTES, "Chat",
        "ShowGuildNotes")
    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_OWN_NOTE, WT.L.OPT_DESC_CHAT_OWN_NOTE, "Chat", "ShowOwnGuildNote", nil,
        noteInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_NOTE, WT.L.OPT_DESC_COLOR_VALUE, "Chat", "NoteColor", false, noteInit)

    local gzInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_AUTOGZ, WT.L.OPT_DESC_CHAT_AUTOGZ, "Chat", "AutoGZ")
    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_AUTOGZ_TOOLTIP,
        WT.L.OPT_DESC_CHAT_AUTOGZ_TOOLTIP, "Chat", "AutoGZTooltip", nil, gzInit)

    panel:CreateEditBox(builder, WT.L.OPT_CHAT_AUTOGZ_TEXT, WT.L.OPT_DESC_CHAT_AUTOGZ_TEXT, "Chat", "AutoGZText", gzInit)

    local achInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_GUILD_ACHIEV, WT.L.OPT_DESC_CHAT_GUILD_ACHIEV, "Chat",
        "GuildAchievEnabled")
    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_GUILD_ACHIEV_SELF, WT.L.OPT_DESC_CHAT_GUILD_ACHIEV_SELF, "Chat",
        "GuildAchievSelf", nil, achInit)
    if WT.Utils and WT.Utils.SharedMedia then
        panel:CreateSoundDropdown(builder, WT.L.OPT_CHAN_SOUND, WT.L.OPT_DESC_CHAN_SOUND, "Chat", "GuildAchievSound",
            achInit)
    end
end
