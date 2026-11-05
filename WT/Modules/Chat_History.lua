local addonName, WT = ...
local Module = WT.Modules.Chat

local Unsecret = WT.Utils.Safety.Unsecret
local SafeNum = WT.Utils.Safety.SafeNum

local strtrim = strtrim or string.trim or function(s) return s and string.match(s, "^%s*(.-)%s*$") or "" end

local wipe = table.wipe or wipe or function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

-- Function to log and restore lightweight chat history across sessions
function Module:EnableChatHistory()
    if not WT.DB or not WT.DB.Chat or not WT.DB.Chat.ChatHistory then return end
    if not WT.DB.Internal then WT.DB.Internal = {} end

    -- 1. Restore temporary tabs (Whispers & BNet) FIRST
    if WT.DB.Chat.RestoreTempTabs and WT.DB.Internal.TempTabs then
        for i = 1, #WT.DB.Internal.TempTabs do
            local tabInfo = WT.DB.Internal.TempTabs[i]
            local currentTarget = tabInfo.target
            if tabInfo.type == "BN_WHISPER" then
                local okBN, numFriendsRaw = pcall(function() return (C_BattleNet and C_BattleNet.GetFriendCount and C_BattleNet.GetFriendCount()) or
                    (BNGetNumFriends and BNGetNumFriends()) or 0 end)
                local numFriends = okBN and SafeNum(numFriendsRaw) or 0
                if numFriends > 0 then
                    for i = 1, numFriends do
                        if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
                            local okAcc, acc = pcall(C_BattleNet.GetFriendAccountInfo, i)
                            if okAcc and acc and acc.battleTag == tabInfo.target then
                                currentTarget = acc.bnetAccountID; break
                            end
                        end
                    end
                end
            end
            if currentTarget and _G["FCF_OpenTemporaryWindow"] then
                pcall(_G["FCF_OpenTemporaryWindow"], tabInfo.type, currentTarget, DEFAULT_CHAT_FRAME, false)
            end
        end
    end

    -- 2. Restore messages (Delay slightly to ensure ChatFrames are ready)
    if WT.DB.Internal.ChatLog then
        C_Timer.After(1.5, function()
            Module.isRestoringHistory = true
            local success, err = pcall(function()
                for fname, messages in pairs(WT.DB.Internal.ChatLog) do
                    if not WT.DB.Chat.HistoryIncludeGeneral and fname == "ChatFrame1" then
                        WT.DB.Internal.ChatLog[fname] = nil -- Free up old memory from DB
                    elseif type(messages) == "table" then
                        local cf = _G[fname]
                        if not cf and string.match(fname, "^TEMP_") then
                            local target = string.sub(fname, 6)
                            for j = 1, #CHAT_FRAMES do
                                local frameName = CHAT_FRAMES[j]
                                local tempCf = _G[frameName]
                                if tempCf and tempCf.isTemporary and tempCf.chatTarget then
                                    local cfTarget = Unsecret(tempCf.chatTarget)
                                    if cfTarget then
                                        if tempCf.chatType == "BN_WHISPER" then
                                            local bnetID = type(cfTarget) == "number" and cfTarget or
                                            SafeNum(tonumber(cfTarget))
                                            if type(bnetID) == "number" then
                                                if C_BattleNet and C_BattleNet.GetAccountInfoByID then
                                                    local s, acc = pcall(C_BattleNet.GetAccountInfoByID, bnetID)
                                                    if s and acc and acc.battleTag then cfTarget = acc.battleTag end
                                                end
                                            end
                                        end
                                        if string.upper(tostring(cfTarget)) == string.upper(tostring(target)) then
                                            cf = tempCf
                                            break
                                        end
                                    end
                                end
                            end
                        end

                        if cf and type(cf.AddMessage) == "function" then
                            local restoredCount = 0
                            for j = 1, #messages do
                                local line = messages[j]
                                local safeLine = Unsecret(line)
                                if safeLine then
                                    local pureLine = safeLine
                                    if string.find(pureLine, "|", 1, true) then
                                        pureLine = string.gsub(pureLine, "|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
                                        pureLine = string.gsub(pureLine, "|[Hh].-|[hH](.-)|[hH]", "%1"):gsub(
                                        "|[TtgG].-|[tT]", ""):gsub("|[aA].-|[aA]", "")
                                    end
                                    pureLine = string.gsub(pureLine, "%[HIST%]", "")
                                    if strtrim(pureLine) ~= "" then
                                        pcall(function() cf:AddMessage(safeLine) end)
                                        restoredCount = restoredCount + 1
                                    end
                                end
                            end
                        else
                            if string.match(fname, "^TEMP_") or string.match(fname, "^ChatFrame%d+$") then
                                WT.DB.Internal.ChatLog[fname] = nil
                            end
                        end
                    end
                end
            end)
            if not success and WT.Utils and WT.Utils.Logger then
                WT.Utils.Logger:Error(WT.L.MSG_CHAT_HISTORY_RESTORE_ERROR .. " " .. tostring(err))
            end
            Module.isRestoringHistory = false
        end)
    end

    -- Save temporary tabs on logout
    WT.Core.Events:Register("PLAYER_LOGOUT", function()
        if not WT.DB then return end
        if not WT.DB.Internal then WT.DB.Internal = {} end
        if WT.DB.Internal.TempTabs then wipe(WT.DB.Internal.TempTabs) else WT.DB.Internal.TempTabs = {} end
        for i = 1, #CHAT_FRAMES do
            local frameName = CHAT_FRAMES[i]
            local cf = _G[frameName]
            if cf and cf.isTemporary and cf.inUse and cf.chatType and cf.chatTarget then
                local rawTarget = Unsecret(cf.chatTarget)
                if rawTarget then
                    local targetToSave = rawTarget
                    if cf.chatType == "BN_WHISPER" then
                        local bnetID = type(rawTarget) == "number" and rawTarget or SafeNum(tonumber(rawTarget))
                        if type(bnetID) == "number" then
                            if C_BattleNet and C_BattleNet.GetAccountInfoByID then
                                local s, acc = pcall(C_BattleNet.GetAccountInfoByID, bnetID)
                                if s and acc and acc.battleTag then targetToSave = acc.battleTag end
                            end
                        end
                    end
                    table.insert(WT.DB.Internal.TempTabs, { type = cf.chatType, target = targetToSave })
                end
            end
        end
    end)
end

local histState = setmetatable({}, { __mode = "k" })
local hookedEditBoxes = setmetatable({}, { __mode = "k" })

local function GetChatEditBoxes()
    local boxes = {}
    local seen = {}
    local function AddEb(eb)
        if eb and not seen[eb] then
            seen[eb] = true
            table.insert(boxes, eb)
        end
    end

    for _, frameName in ipairs(CHAT_FRAMES or {}) do
        AddEb(_G[frameName .. "EditBox"])
        local cf = _G[frameName]
        if cf and cf.editBox then AddEb(cf.editBox) end
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        AddEb(_G["ChatFrame" .. i .. "EditBox"])
    end
    if _G["DEFAULT_CHAT_FRAME"] and _G["DEFAULT_CHAT_FRAME"].editBox then
        AddEb(_G["DEFAULT_CHAT_FRAME"].editBox)
    end
    return boxes
end

local function SaveInputHistoryLine(text, chatType)
    local safeText = Unsecret(text)
    if type(safeText) ~= "string" then return end
    safeText = strtrim(safeText)
    if safeText == "" then return end

    if not WT.DB or not WT.DB.Chat or not WT.DB.Chat.InputHistory then return end
    if not WT.DB.Internal then WT.DB.Internal = {} end
    if not WT.DB.Internal.InputLog then WT.DB.Internal.InputLog = {} end

    -- Reconstruct /me if the user used emote chatType and Blizzard stripped the prefix
    if chatType == "EMOTE" and string.sub(safeText, 1, 1) ~= "/" then
        safeText = "/me " .. safeText
    end

    local log = WT.DB.Internal.InputLog
    if log[#log] ~= safeText then
        table.insert(log, safeText)
        local rawMax = WT.DB.Chat.InputHistoryMaxLines
        local maxLines = type(rawMax) == "number" and rawMax or 50

        local over = #log - maxLines
        if over > 0 then
            for i = 1, maxLines do
                log[i] = log[i + over]
            end
            for i = maxLines + 1, #log do
                log[i] = nil
            end
        end
    end
end
Module.SaveInputHistoryLine = SaveInputHistoryLine

local function OnEditBoxSend(self)
    if not self then return end
    local hs = histState[self]
    local rawText = (hs and hs.preSendText and hs.preSendText ~= "") and hs.preSendText or self:GetText()
    local text = Unsecret(rawText)
    local chatType = self:GetAttribute("chatType")

    if hs then
        hs.index = 0
        hs.draft = nil
        hs.preSendText = nil
    end

    if text and text ~= "" then
        SaveInputHistoryLine(text, chatType)
        if Module.TrackOutgoingMessage then
            Module.TrackOutgoingMessage(text)
        end
    end
end
Module.OnEditBoxSend = OnEditBoxSend

local function HookEditBox(eb)
    if not eb or hookedEditBoxes[eb] then return end
    hookedEditBoxes[eb] = true

    eb:HookScript("OnTextChanged", function(self, isUserInput)
        local hs = histState[self]
        if not hs then
            hs = {}; histState[self] = hs
        end

        local safeText = Unsecret(self:GetText())
        if isUserInput then
            hs.index = 0
            hs.draft = nil
            hs.preSendText = safeText
        else
            if safeText and safeText ~= "" then
                hs.preSendText = safeText
            end
        end
    end)

    eb:HookScript("OnEscapePressed", function(self)
        local hs = histState[self]
        if hs then
            hs.index = 0
            hs.draft = nil
            hs.preSendText = nil
        end
    end)

    eb:HookScript("OnEditFocusLost", function(self)
        local hs = histState[self]
        if hs then
            hs.index = 0
            hs.draft = nil
            local safeText = Unsecret(self:GetText())
            if safeText and safeText ~= "" then
                hs.preSendText = nil
            end
        end
    end)

    eb:HookScript("OnHide", function(self)
        local hs = histState[self]
        if hs and hs.preSendText and hs.preSendText ~= "" then
            -- When sending a message or slash command, Blizzard calls self:SetText("") then self:Hide().
            -- If text is empty here, the message/command was submitted!
            local safeText = Unsecret(self:GetText())
            if safeText == "" then
                local sentText = hs.preSendText
                local chatType = self:GetAttribute("chatType")
                hs.preSendText = nil
                hs.index = 0
                hs.draft = nil
                SaveInputHistoryLine(sentText, chatType)
                if Module.TrackOutgoingMessage then
                    Module.TrackOutgoingMessage(sentText)
                end
            else
                hs.preSendText = nil
            end
        end
    end)

    eb:HookScript("OnArrowPressed", function(self, key)
        if not WT.DB or not WT.DB.Chat or not WT.DB.Chat.InputHistory then return end
        local log = WT.DB.Internal and WT.DB.Internal.InputLog
        if not log or #log == 0 then return end

        local requiresAlt = self:GetAltArrowKeyMode()
        if requiresAlt and not IsAltKeyDown() then return end
        if key ~= "UP" and key ~= "DOWN" then return end

        local hs = histState[self]
        if not hs then
            hs = {}; histState[self] = hs
        end
        local hIdx = hs.index or 0

        if key == "UP" then
            if hIdx == 0 then
                hs.draft = self:GetText() or ""
            end
            hIdx = hIdx + 1
            if hIdx > #log then hIdx = #log end
        elseif key == "DOWN" then
            hIdx = hIdx - 1
            if hIdx < 0 then hIdx = 0 end
        end

        hs.index = hIdx

        if hIdx == 0 then
            local draft = hs.draft or ""
            self:SetText(draft)
            self:SetCursorPosition(string.len(draft))
            hs.preSendText = draft
            hs.draft = nil
        else
            local entry = log[#log - hIdx + 1]
            if entry then
                pcall(function()
                    self:SetText(entry)
                    self:SetCursorPosition(string.len(entry))
                end)
                hs.preSendText = entry
            end
        end
    end)
end

function Module:UpdateInputHistoryHooks()
    if not self.inputHistoryGlobalHooked then
        self.inputHistoryGlobalHooked = true

        if EventRegistry and EventRegistry.RegisterCallback then
            EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", function(_, editBox)
                if not editBox then return end
                local hs = histState[editBox]
                local text = (hs and hs.preSendText and hs.preSendText ~= "") and hs.preSendText or editBox:GetText()
                local chatType = editBox:GetChatType()
                if hs then
                    hs.preSendText = nil
                    hs.index = 0
                    hs.draft = nil
                end
                if text and text ~= "" then
                    SaveInputHistoryLine(text, chatType)
                    if Module.TrackOutgoingMessage then
                        Module.TrackOutgoingMessage(text)
                    end
                end
            end)
        end
    end

    for _, eb in ipairs(GetChatEditBoxes()) do
        HookEditBox(eb)
    end
end

-- Function to clean saved input log (without touching native Blizzard history buffers to prevent taint)
function Module:RestoreInputHistory()
    if not WT.DB or not WT.DB.Chat or not WT.DB.Chat.InputHistory then return end
    local log = WT.DB.Internal and WT.DB.Internal.InputLog
    if not log or #log == 0 then return end

    local cleaned = {}
    for j = 1, #log do
        local entry = Unsecret(log[j])
        if type(entry) == "string" then
            entry = strtrim(entry)
            if entry ~= "" and entry ~= cleaned[#cleaned] then
                table.insert(cleaned, entry)
            end
        end
    end
    WT.DB.Internal.InputLog = cleaned
end

-- Function to restore and record previously typed messages
function Module:EnableInputHistory()
    if not WT.DB or not WT.DB.Chat or not WT.DB.Chat.InputHistory then return end

    if not WT.DB.Internal then WT.DB.Internal = {} end
    if not WT.DB.Internal.InputLog then WT.DB.Internal.InputLog = {} end

    self:UpdateInputHistoryHooks()
    self:RestoreInputHistory()
end

-- Load history slightly after the player has entered the world to prevent loading screen stutters
WT.Core.Events:Register("PLAYER_LOGIN", function()
    if not WT.DB.Modules.Chat then return end
    Module:EnableChatHistory()
    Module:EnableInputHistory()
end)
