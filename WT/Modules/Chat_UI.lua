local _, WT = ...
WT.Modules.ChatUI = {}
local Module = WT.Modules.ChatUI

---@class WTChatTexture : Texture
---@field isWT boolean|nil

local chatData = setmetatable({}, { __mode = "k" })

local Unsecret = WT.Utils.Safety.Unsecret

local function SafeSetGradient(tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    C_Timer.After(0, function()
        if tex and tex.SetGradient then
            tex:SetGradient(orientation, {r=r1, g=g1, b=b1, a=a1}, {r=r2, g=g2, b=b2, a=a2})
        elseif tex and type(tex.SetGradientAlpha) == "function" then
            tex:SetGradientAlpha(orientation, r1, g1, b1, a1, r2, g2, b2, a2)
        end
    end)
end

-- ============================================================================
-- Fix for Blizzard Bug in WoW 12.0+ (Midnight / The War Within)
-- In combat, C_Club queries return secret values (<secret string>) to protect social data.
-- However, Blizzard's ChatFrameUtil.TruncateToMaxLength calls strlenutf8(text) directly,
-- which throws "Usage: strlenutf8(string)" on secret strings. Furthermore,
-- ChatFrameUtil.GetCommunityAndStreamName concatenates strings using '..', which also fails
-- on secret values. We cache club & stream names out-of-combat and provide safe fallbacks.
-- ============================================================================

local clubNameCache = {}
local streamNameCache = {}

local function CacheClubsAndStreams()
    if InCombatLockdown() then return end
    if not C_Club or not C_Club.GetSubscribedClubs then return end

    local ok, clubs = pcall(C_Club.GetSubscribedClubs)
    if not ok or type(clubs) ~= "table" then return end

    for _, club in ipairs(clubs) do
        if club and club.clubId then
            local cId = tostring(club.clubId)
            local name = Unsecret(club.shortName or club.name)
            if name and name ~= "" then
                clubNameCache[cId] = name
                clubNameCache[club.clubId] = name
            end
            if C_Club.GetClubStreams then
                local okStreams, streams = pcall(C_Club.GetClubStreams, club.clubId)
                if okStreams and type(streams) == "table" then
                    for _, stream in ipairs(streams) do
                        if stream and stream.streamId and stream.name then
                            local sName = Unsecret(stream.name)
                            if sName and sName ~= "" then
                                streamNameCache[cId .. ":" .. tostring(stream.streamId)] = sName
                            end
                        end
                    end
                end
            end
        end
    end
end

local ChatFrameUtil = _G["ChatFrameUtil"]
if ChatFrameUtil then
    if ChatFrameUtil.TruncateToMaxLength then
        local orig_TruncateToMaxLength = ChatFrameUtil.TruncateToMaxLength
        ChatFrameUtil.TruncateToMaxLength = function(text, maxLength)
            if not text then return "" end
            local safeText = Unsecret(text)
            if not safeText or type(safeText) ~= "string" then
                -- Cannot measure or slice secret strings or non-strings without crashing strlenutf8
                return (type(text) == "string" and text) or ""
            end
            local utf8Len = _G["strlenutf8"]
            local ok, length = pcall(utf8Len or string.len, safeText)
            if not ok or type(length) ~= "number" then
                length = #safeText
            end
            if length > (maxLength or 12) then
                local okSub, sub = pcall(string.sub, safeText, 1, math.max(1, (maxLength or 12) - 2))
                if okSub and sub then
                    return sub .. "..."
                end
            end
            return safeText
        end
    end

    if ChatFrameUtil.GetCommunityAndStreamName then
        local orig_GetCommunityAndStreamName = ChatFrameUtil.GetCommunityAndStreamName
        ChatFrameUtil.GetCommunityAndStreamName = function(clubId, streamId)
            if not clubId then return "" end
            local cKey = tostring(clubId)
            local sKey = streamId and (cKey .. ":" .. tostring(streamId)) or nil

            local streamName = nil
            local streamType = nil
            if streamId and C_Club and C_Club.GetStreamInfo then
                local ok, streamInfo = pcall(C_Club.GetStreamInfo, clubId, streamId)
                if ok and streamInfo then
                    streamType = streamInfo.streamType
                    local sName = Unsecret(streamInfo.name)
                    if sName and sName ~= "" then
                        streamName = sName
                        if not InCombatLockdown() and sKey then
                            streamNameCache[sKey] = sName
                        end
                    end
                end
            end
            if not streamName and sKey then
                streamName = streamNameCache[sKey]
            end

            local clubName = nil
            if C_Club and C_Club.GetClubInfo then
                local ok, clubInfo = pcall(C_Club.GetClubInfo, clubId)
                if ok and clubInfo then
                    local cName = Unsecret(clubInfo.shortName or clubInfo.name)
                    if cName and cName ~= "" then
                        clubName = cName
                        if not InCombatLockdown() then
                            clubNameCache[cKey] = cName
                            clubNameCache[clubId] = cName
                        end
                    end
                end
            end
            if not clubName then
                clubName = clubNameCache[cKey] or clubNameCache[clubId] or "Community"
            end

            local ClubStreamType = Enum and Enum.ClubStreamType
            local discordStream = ClubStreamType and rawget(ClubStreamType, "Discord")
            if streamType and ClubStreamType and (streamType == ClubStreamType.Guild or streamType == ClubStreamType.Officer or (discordStream and streamType == discordStream)) then
                if streamName and streamName ~= "" then
                    return streamName
                end
            end

            local cConstants = _G["ChatFrameConstants"] or (_G["Constants"] and _G["Constants"].ChatFrameConstants)
            local isGeneral = streamType and ClubStreamType and (streamType == ClubStreamType.General)
            local maxLenComm = isGeneral
                and (cConstants and cConstants.TruncatedCommunityNameWithoutChannelLength or 16)
                or (cConstants and cConstants.TruncatedCommunityNameLength or 12)
            local maxLenStream = (cConstants and cConstants.TruncatedCommunityNameLength or 12)

            local commTrunc = ChatFrameUtil.TruncateToMaxLength and ChatFrameUtil.TruncateToMaxLength(clubName, maxLenComm) or clubName
            if isGeneral or not streamName or streamName == "" then
                return commTrunc
            end

            local streamTrunc = ChatFrameUtil.TruncateToMaxLength and ChatFrameUtil.TruncateToMaxLength(streamName, maxLenStream) or streamName
            return commTrunc .. " - " .. streamTrunc
        end
    end

    local clubEventsWatcher = CreateFrame("Frame")
    clubEventsWatcher:RegisterEvent("PLAYER_LOGIN")
    clubEventsWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    clubEventsWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    pcall(function()
        clubEventsWatcher:RegisterEvent("INITIAL_CLUBS_LOADED")
        clubEventsWatcher:RegisterEvent("CLUB_STREAMS_LOADED")
        clubEventsWatcher:RegisterEvent("CLUB_STREAM_SUBSCRIBED")
        clubEventsWatcher:RegisterEvent("CLUB_ADDED")
        clubEventsWatcher:RegisterEvent("CLUB_UPDATED")
    end)
    clubEventsWatcher:SetScript("OnEvent", function(self, event)
        CacheClubsAndStreams()
    end)
end

function Module:ApplyHooksToNewFrames()
    if self.UpdateArrowKeys then self:UpdateArrowKeys(WT.DB.Chat.FreeArrowKeys) end
    if self.UpdateChatFading then self:UpdateChatFading(not WT.DB.Chat.DisableChatFading) end
    if self.UpdateCleanEditBox then self:UpdateCleanEditBox() end
    if self.UpdateEditBoxPosition then self:UpdateEditBoxPosition() end
    if self.UpdateCleanTabs then self:UpdateCleanTabs() end
    if self.UpdateTabVisibility then self:UpdateTabVisibility() end
    if self.UpdateCharacterCount then self:UpdateCharacterCount() end
    if self.UpdateChatButtonsVisibility then self:UpdateChatButtonsVisibility() end
    if self.EnableMouseWheel then self:EnableMouseWheel() end
    if self.UnclampChatFrames then self:UnclampChatFrames(WT.DB.Chat.UnclampChatFrames) end
    if self.UpdateChatFont then self:UpdateChatFont() end
    if self.UpdateChatBackground then self:UpdateChatBackground() end
end

-- Function to hide the cluttered buttons on the side of the chat frame
function Module:UpdateChatButtonsVisibility()
    local hide = WT.DB.Chat.HideButtons
    
    for _, frameName in ipairs(CHAT_FRAMES) do
        local btnFrame = _G[frameName .. "ButtonFrame"]
        if btnFrame then
            local bData = chatData[btnFrame]; if not bData then bData = {}; chatData[btnFrame] = bData end
            if not bData.wtHiddenHook then
                bData.wtHiddenHook = true
                btnFrame:HookScript("OnShow", function(self) if WT.DB.Chat.HideButtons then self:Hide() end end)
            end
            if hide then btnFrame:Hide() else btnFrame:Show() end
        end
    end
    
    local function SafeHideBtn(btn)
        if btn then
            local bData = chatData[btn]; if not bData then bData = {}; chatData[btn] = bData end
            if not bData.wtHiddenHook then
                bData.wtHiddenHook = true
                btn:HookScript("OnShow", function(self) if WT.DB.Chat.HideButtons then self:Hide() end end)
            end
            if hide then btn:Hide() else btn:Show() end
        end
    end
    
    SafeHideBtn(ChatFrameChannelButton)
    SafeHideBtn(ChatFrameToggleVoiceDeafenButton)
    SafeHideBtn(ChatFrameToggleVoiceMuteButton)
    SafeHideBtn(ChatFrameMenuButton)
    SafeHideBtn(TextToSpeechButton)
end

-- Function to enable or disable chat fading for all chat windows globally
function Module:UpdateChatFading(enable)
    for _, frameName in ipairs(CHAT_FRAMES) do
        local chatFrame = _G[frameName]
        if chatFrame then chatFrame:SetFading(enable) end
    end
end

-- Function to free up arrow keys (disables the ALT requirement to move cursor)
function Module:UpdateArrowKeys(enable)
    for _, frameName in ipairs(CHAT_FRAMES) do
        local eb = _G[frameName.."EditBox"]
        if eb then eb:SetAltArrowKeyMode(not enable) end
    end
end

-- Function to handle faster mouse wheel scrolling and shift-to-top/bottom
function Module:EnableMouseWheel()
    for _, frameName in ipairs(CHAT_FRAMES) do
        local chatFrame = _G[frameName]
        if chatFrame then
            local cData = chatData[chatFrame]
            if not cData then cData = {}; chatData[chatFrame] = cData end
            
            if not cData.wtWheelHooked then
                cData.wtWheelHooked = true
                chatFrame:EnableMouseWheel(true)
                chatFrame:SetScript("OnMouseWheel", function(self, delta)
                    if not WT.DB.Chat.MouseWheelScroll then
                        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
                        return
                    end
                    if delta > 0 then
                        if IsShiftKeyDown() then self:ScrollToTop() else self:ScrollUp(); self:ScrollUp(); self:ScrollUp() end
                    elseif delta < 0 then
                        if IsShiftKeyDown() then self:ScrollToBottom() else self:ScrollDown(); self:ScrollDown(); self:ScrollDown() end
                    end
                end)
            end
        end
    end
end

local editBoxPosPending = false
local function ApplyEditBoxPos(chatFrame)
    if not chatFrame then return end
    if InCombatLockdown() then
        editBoxPosPending = true
        return
    end
    local fName = Unsecret(chatFrame.GetName and chatFrame:GetName())
    if not fName or not string.match(fName, "^ChatFrame%d+$") then return end
    
    local editBox = chatFrame and chatFrame.editBox
    if not editBox then return end
    
    local eData = chatData[editBox]; if not eData then eData = {}; chatData[editBox] = eData end
    if eData.wtChangingPos then return end
    eData.wtChangingPos = true
    
    local isTop = WT.DB.Chat.EditBoxTop
    local isClean = WT.DB.Chat.CleanEditBox
    local style = WT.DB.Chat.EditBoxStyle or "CLASSIC"
    local offset = isClean and (style == "MODERN" and -5 or 0) or 0
    local rightOffset = isClean and (style == "MODERN" and 5 or 0) or 0
    
    local rightAnchorFrame = chatFrame.Background or _G[chatFrame:GetName().."Background"] or chatFrame
    
    editBox:ClearAllPoints()
    if isTop then
        local yOffset = 65
        local tabFrame = _G[chatFrame:GetName().."Tab"]
        if tabFrame then
            local tabTop = tabFrame:GetTop()
            local chatTop = chatFrame:GetTop()
            if tabTop and chatTop and tabTop >= chatTop then
                yOffset = (tabTop - chatTop) + 2
            end
        end
        editBox:SetPoint("BOTTOMLEFT", chatFrame, "TOPLEFT", offset, yOffset)
        editBox:SetPoint("BOTTOMRIGHT", rightAnchorFrame, "TOPRIGHT", rightOffset, yOffset)
    else
        editBox:SetPoint("TOPLEFT", chatFrame, "BOTTOMLEFT", offset, -2)
        editBox:SetPoint("TOPRIGHT", rightAnchorFrame, "BOTTOMRIGHT", rightOffset, -2)
    end
    
    if eData.wtCharCountFrame then
        eData.wtCharCountFrame:ClearAllPoints()
        local isCharTop = WT.DB.Chat.CharCountPos == "TOP"
        local cRight = WT.DB.Chat.CleanEditBox and (WT.DB.Chat.EditBoxStyle == "MODERN" and -5 or 2) or -10
        if isCharTop then
            local cY = WT.DB.Chat.CleanEditBox and (WT.DB.Chat.EditBoxStyle == "MODERN" and -7 or -5) or -2
            eData.wtCharCountFrame:SetPoint("BOTTOMRIGHT", editBox, "TOPRIGHT", cRight, cY)
        else
            local cY = WT.DB.Chat.CleanEditBox and (WT.DB.Chat.EditBoxStyle == "MODERN" and 7 or 5) or 2
            eData.wtCharCountFrame:SetPoint("TOPRIGHT", editBox, "BOTTOMRIGHT", cRight, cY)
        end
    end
    eData.wtChangingPos = false
end

-- Function to move the chat edit box to the top or bottom of the chat frame
function Module:UpdateEditBoxPosition()
    if not WT.DB.Chat.EditBoxTop and not WT.DB.Chat.CleanEditBox then return end
    
    if not Module.editBoxPosHooked then
        Module.editBoxPosHooked = true
        
        if _G["FCF_UpdateEditBoxPosition"] then
            hooksecurefunc("FCF_UpdateEditBoxPosition", ApplyEditBoxPos)
        end
        if _G["ChatEdit_UpdateHeader"] then
            hooksecurefunc("ChatEdit_UpdateHeader", function(editBox)
                if editBox then ApplyEditBoxPos(editBox.chatFrame or editBox:GetParent()) end
            end)
        end
        if _G["ChatEdit_SetLastActiveWindow"] then
            hooksecurefunc("ChatEdit_SetLastActiveWindow", function(editBox, chatFrame)
                if chatFrame then ApplyEditBoxPos(chatFrame) end
            end)
        end
        if _G["ChatEdit_ActivateChat"] then
            hooksecurefunc("ChatEdit_ActivateChat", function(editBox)
                if editBox then ApplyEditBoxPos(editBox.chatFrame or editBox:GetParent()) end
            end)
        end
    end

    for _, frameName in ipairs(CHAT_FRAMES) do
        local chatFrame = _G[frameName]
        if chatFrame then
            if _G["FCF_UpdateEditBoxPosition"] then
                _G["FCF_UpdateEditBoxPosition"](chatFrame)
            elseif chatFrame.editBox then
                ApplyEditBoxPos(chatFrame)
            end
        end
    end

    if QuickJoinToastButton then
        local function ApplyQJPos()
            local qData = chatData[QuickJoinToastButton]; if not qData then qData = {}; chatData[QuickJoinToastButton] = qData end
            if InCombatLockdown() or qData.wtChangingPos then return end
            
            if not qData.isQueued then
                qData.isQueued = true
                C_Timer.After(0, function()
                    qData.isQueued = false
                    if InCombatLockdown() then return end
                    local isHidden = WT.DB.Chat.HideQuickJoin
                    local topMode = WT.DB.Chat.EditBoxTop
                    
                    qData.wtChangingPos = true
                    QuickJoinToastButton:ClearAllPoints()
                    if isHidden then
                        QuickJoinToastButton:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 9999, -9999)
                    else
                        QuickJoinToastButton:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", -2, topMode and 68 or 25)
                    end
                    qData.wtChangingPos = false
                end)
            end
        end
        
        Module.ApplyQJPos = ApplyQJPos
        if not InCombatLockdown() then ApplyQJPos() end
        
        if not Module.qjPosHooked then
            Module.qjPosHooked = true
            if _G["QuickJoinToastButton_UpdatePosition"] then
                hooksecurefunc("QuickJoinToastButton_UpdatePosition", ApplyQJPos)
            end
        end
    end
end

-- Function to remove bulky native borders and apply a clean, dark backdrop to the edit box
function Module:UpdateCleanEditBox()

    for _, frameName in ipairs(CHAT_FRAMES) do
        local eb = _G[frameName.."EditBox"]
        if eb then
            local enable = WT.DB.Chat.CleanEditBox
            if eb.NineSlice then eb.NineSlice:SetAlpha(enable and 0 or 1) end
            local regions = {eb:GetRegions()}
            for _, region in ipairs(regions) do
                local rName = Unsecret(region:GetName())
                if region:GetObjectType() == "Texture" and rName then
                    if string.find(rName, "Left") or string.find(rName, "Mid") or string.find(rName, "Right") or string.find(rName, "FocusGlow") then
                        region:SetAlpha(enable and 0 or 1)
                    end
                end
            end
            
            local eData = chatData[eb]
            if enable then
                if not eData then eData = {}; chatData[eb] = eData end
                
                local style = WT.DB.Chat.EditBoxStyle or "CLASSIC"
                
                if not eData.wtBg then
                    ---@type WTChatTexture
                    eData.wtBg = eb:CreateTexture(nil, "BACKGROUND", nil, -5)
                    eData.wtBg.isWT = true
                    eData.wtBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                    
                    ---@type WTChatTexture
                    eData.wtTop = eb:CreateTexture(nil, "BACKGROUND", nil, -4)
                    eData.wtTop.isWT = true
                    eData.wtTop:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                    eData.wtTop:SetHeight(1)
                    
                    ---@type WTChatTexture
                    eData.wtBottom = eb:CreateTexture(nil, "BACKGROUND", nil, -4)
                    eData.wtBottom.isWT = true
                    eData.wtBottom:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                    eData.wtBottom:SetHeight(1)
                    
                    ---@type WTChatTexture
                    eData.wtLeft = eb:CreateTexture(nil, "BACKGROUND", nil, -4)
                    eData.wtLeft.isWT = true
                    eData.wtLeft:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                    eData.wtLeft:SetWidth(1)
                    
                    ---@type WTChatTexture
                    eData.wtRight = eb:CreateTexture(nil, "BACKGROUND", nil, -4)
                    eData.wtRight.isWT = true
                    eData.wtRight:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                    eData.wtRight:SetWidth(1)
                end
                
                if style == "MODERN" then
                    if eData.wtBackdrop then eData.wtBackdrop:Hide() end
                    local isTop = WT.DB.Chat.EditBoxTop
                    
                    eData.wtBg:ClearAllPoints()
                    eData.wtBg:SetPoint("TOPLEFT", eb, "TOPLEFT", 5, -6)
                    eData.wtBg:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", -5, 6)
                    
                    eData.wtTop:ClearAllPoints()
                    eData.wtTop:SetPoint("TOPLEFT", eData.wtBg, "TOPLEFT", 0, 0)
                    eData.wtTop:SetPoint("TOPRIGHT", eData.wtBg, "TOPRIGHT", 0, 0)
                    
                    eData.wtBottom:ClearAllPoints()
                    eData.wtBottom:SetPoint("BOTTOMLEFT", eData.wtBg, "BOTTOMLEFT", 0, 0)
                    eData.wtBottom:SetPoint("BOTTOMRIGHT", eData.wtBg, "BOTTOMRIGHT", 0, 0)
                    
                    eData.wtLeft:ClearAllPoints()
                    eData.wtLeft:SetPoint("TOPLEFT", eData.wtBg, "TOPLEFT", 0, isTop and 0 or -1)
                    eData.wtLeft:SetPoint("BOTTOMLEFT", eData.wtBg, "BOTTOMLEFT", 0, isTop and 1 or 0)
                    
                    eData.wtRight:ClearAllPoints()
                    eData.wtRight:SetPoint("TOPRIGHT", eData.wtBg, "TOPRIGHT", 0, isTop and 0 or -1)
                    eData.wtRight:SetPoint("BOTTOMRIGHT", eData.wtBg, "BOTTOMRIGHT", 0, isTop and 1 or 0)
                else
                    if eData.wtBackdrop then eData.wtBackdrop:Hide() end
                    
                    eData.wtBg:ClearAllPoints()
                    eData.wtBg:SetPoint("TOPLEFT", eb, "TOPLEFT", -1, -5)
                    eData.wtBg:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", 1, 5)
                    
                    eData.wtTop:ClearAllPoints()
                    eData.wtTop:SetPoint("TOPLEFT", eb, "TOPLEFT", -2, -4)
                    eData.wtTop:SetPoint("TOPRIGHT", eb, "TOPRIGHT", 2, -4)
                    
                    eData.wtBottom:ClearAllPoints()
                    eData.wtBottom:SetPoint("BOTTOMLEFT", eb, "BOTTOMLEFT", -2, 4)
                    eData.wtBottom:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", 2, 4)
                    
                    eData.wtLeft:ClearAllPoints()
                    eData.wtLeft:SetPoint("TOPLEFT", eb, "TOPLEFT", -2, -4)
                    eData.wtLeft:SetPoint("BOTTOMLEFT", eb, "BOTTOMLEFT", -2, 4)
                    
                    eData.wtRight:ClearAllPoints()
                    eData.wtRight:SetPoint("TOPRIGHT", eb, "TOPRIGHT", 2, -4)
                    eData.wtRight:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", 2, 4)
                end
                
                local function ToggleVisibility()
                    if eb:HasFocus() then
                        eData.wtBg:Show(); eData.wtTop:Show(); eData.wtBottom:Show(); eData.wtLeft:Show(); eData.wtRight:Show()
                        if eData.wtCharCountFrame then eData.wtCharCountFrame:Show() end
                    else
                        eData.wtBg:Hide(); eData.wtTop:Hide(); eData.wtBottom:Hide(); eData.wtLeft:Hide(); eData.wtRight:Hide()
                        if eData.wtCharCountFrame then eData.wtCharCountFrame:Hide() end
                    end
                end
                
                ToggleVisibility()
                
                if not eData.wtHooksAdded then
                    local function UpdateFocusColors()
                        if not WT.DB.Chat.CleanEditBox then return end
                        local bgCol = WT.DB.Chat.EditBoxBgColor or {r=WT.Colors.STD_BG_R, g=WT.Colors.STD_BG_G, b=WT.Colors.STD_BG_B, a=WT.Colors.STD_BG_A}
                        local bdCol = WT.DB.Chat.EditBoxBorderColor or {r=0.3, g=0.3, b=0.3, a=0.8}
                        
                        if type(bgCol) == "string" then bgCol = {r=WT.Colors.STD_BG_R, g=WT.Colors.STD_BG_G, b=WT.Colors.STD_BG_B, a=WT.Colors.STD_BG_A} end
                        if type(bdCol) == "string" then bdCol = {r=0.3, g=0.3, b=0.3, a=0.8} end
                        
                        if eb:HasFocus() then
                            local hlCol = WT.DB.Chat.EditBoxHighlightColor or {r=0.2, g=0.6, b=1.0, a=0.8}
                            if type(hlCol) == "string" then hlCol = {r=0.2, g=0.6, b=1.0, a=0.8} end
                            bdCol = hlCol
                            bgCol = {r = math.min(1, bgCol.r + 0.1), g = math.min(1, bgCol.g + 0.1), b = math.min(1, bgCol.b + 0.1), a = bgCol.a}
                        end
                        
                        local currStyle = WT.DB.Chat.EditBoxStyle or "CLASSIC"
                        if currStyle == "MODERN" then
                            local isTop = WT.DB.Chat.EditBoxTop
                            if eData.wtBg and eData.wtBg.SetGradient then
                                if isTop then
                                    SafeSetGradient(eData.wtBg, "VERTICAL", bgCol.r, bgCol.g, bgCol.b, 0, bgCol.r, bgCol.g, bgCol.b, bgCol.a)
                                    SafeSetGradient(eData.wtLeft, "VERTICAL", bdCol.r, bdCol.g, bdCol.b, 0, bdCol.r, bdCol.g, bdCol.b, bdCol.a)
                                    SafeSetGradient(eData.wtRight, "VERTICAL", bdCol.r, bdCol.g, bdCol.b, 0, bdCol.r, bdCol.g, bdCol.b, bdCol.a)
                                    eData.wtTop:SetVertexColor(bdCol.r, bdCol.g, bdCol.b, bdCol.a)
                                    eData.wtBottom:SetVertexColor(bdCol.r, bdCol.g, bdCol.b, 0)
                                else
                                    SafeSetGradient(eData.wtBg, "VERTICAL", bgCol.r, bgCol.g, bgCol.b, bgCol.a, bgCol.r, bgCol.g, bgCol.b, 0)
                                    SafeSetGradient(eData.wtLeft, "VERTICAL", bdCol.r, bdCol.g, bdCol.b, bdCol.a, bdCol.r, bdCol.g, bdCol.b, 0)
                                    SafeSetGradient(eData.wtRight, "VERTICAL", bdCol.r, bdCol.g, bdCol.b, 0, bdCol.r, bdCol.g, bdCol.b, 0)
                                    eData.wtTop:SetVertexColor(bdCol.r, bdCol.g, bdCol.b, 0)
                                    eData.wtBottom:SetVertexColor(bdCol.r, bdCol.g, bdCol.b, bdCol.a)
                                end
                            elseif eData.wtBg then
                                eData.wtBg:SetVertexColor(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
                                eData.wtTop:SetVertexColor(bdCol.r, bdCol.g, bdCol.b, bdCol.a)
                                eData.wtBottom:SetVertexColor(bdCol.r, bdCol.g, bdCol.b, bdCol.a)
                                eData.wtLeft:SetVertexColor(bdCol.r, bdCol.g, bdCol.b, bdCol.a)
                                eData.wtRight:SetVertexColor(bdCol.r, bdCol.g, bdCol.b, bdCol.a)
                            end
                        else
                            if eData.wtBg then
                                eData.wtBg:SetVertexColor(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
                                eData.wtTop:SetVertexColor(bdCol.r, bdCol.g, bdCol.b, bdCol.a)
                                eData.wtBottom:SetVertexColor(bdCol.r, bdCol.g, bdCol.b, bdCol.a)
                                eData.wtLeft:SetVertexColor(bdCol.r, bdCol.g, bdCol.b, bdCol.a)
                                eData.wtRight:SetVertexColor(bdCol.r, bdCol.g, bdCol.b, bdCol.a)
                            end
                        end
                        
                        if eData.wtCharCountFrame then
                            if eData.wtCharCountBg then
                                eData.wtCharCountBg:SetVertexColor(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
                                eData.wtCharCountTop:SetVertexColor(bdCol.r, bdCol.g, bdCol.b, bdCol.a)
                                eData.wtCharCountBot:SetVertexColor(bdCol.r, bdCol.g, bdCol.b, bdCol.a)
                                eData.wtCharCountLeft:SetVertexColor(bdCol.r, bdCol.g, bdCol.b, bdCol.a)
                                eData.wtCharCountRight:SetVertexColor(bdCol.r, bdCol.g, bdCol.b, bdCol.a)
                            end
                        end
                    end
                    
                    eData.UpdateFocusColors = UpdateFocusColors
                    eb:HookScript("OnEditFocusGained", function() ToggleVisibility(); UpdateFocusColors() end)
                    eb:HookScript("OnEditFocusLost", function() ToggleVisibility(); UpdateFocusColors() end)
                    eData.wtHooksAdded = true
                end
                
                if eData.UpdateFocusColors then
                    eData.UpdateFocusColors()
                end
                
                local hlCol2 = WT.DB.Chat.EditBoxHighlightColor or {r=0.2, g=0.6, b=1.0, a=0.5}
                if type(hlCol2) == "string" then hlCol2 = {r=0.2, g=0.6, b=1.0, a=0.5} end
                eb:SetHighlightColor(hlCol2.r, hlCol2.g, hlCol2.b, hlCol2.a)
                
            elseif eData then
                if eData.wtBg then eData.wtBg:Hide(); eData.wtTop:Hide(); eData.wtBottom:Hide(); eData.wtLeft:Hide(); eData.wtRight:Hide() end
            end
            
            if WT.DB.Chat.CustomEditBoxFont then
                local fontPath = ChatFontNormal and ChatFontNormal:GetFont() or STANDARD_TEXT_FONT
                if WT.DB.Chat.EditBoxFont and WT.DB.Chat.EditBoxFont ~= "" then
                    local fetchedFont = WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", WT.DB.Chat.EditBoxFont)
                    if type(fetchedFont) == "string" and fetchedFont ~= "" then fontPath = fetchedFont else fontPath = WT.DB.Chat.EditBoxFont end
                end
                local fontSize = type(WT.DB.Chat.EditBoxFontSize) == "number" and WT.DB.Chat.EditBoxFontSize or tonumber(tostring(WT.DB.Chat.EditBoxFontSize)) or 10
            -- WoW Engine Bug: Applying an outline to an EditBox breaks mouse selection/highlighting!
            local outline = ""
                eb:SetFont(fontPath, fontSize, outline)
                if eb.header then eb.header:SetFont(fontPath, fontSize, outline) end
                if eb.headerSuffix then eb.headerSuffix:SetFont(fontPath, fontSize, outline) end
                
                eb:SetHeight(math.max(32, fontSize + 18))
            else
                local fontPath, fontSize, outline = ChatFontNormal:GetFont()
                if not fontPath then fontPath = STANDARD_TEXT_FONT; fontSize = 10; outline = "" end
                eb:SetFont(fontPath, fontSize, outline)
                if eb.header then eb.header:SetFont(fontPath, fontSize, outline) end
                if eb.headerSuffix then eb.headerSuffix:SetFont(fontPath, fontSize, outline) end
                
                eb:SetHeight(math.max(32, (fontSize or 10) + 18))
            end
            
            if _G["FCF_UpdateEditBoxPosition"] then
                _G["FCF_UpdateEditBoxPosition"](_G[frameName])
            end
        end
    end
end

local tabsHooked = false
function Module:UpdateCleanTabs()
    local enable = WT.DB.Chat.CleanTabs
    local customFont = WT.DB.Chat.CustomTabFont
        
    if (enable or customFont) and not tabsHooked then
        tabsHooked = true
        if _G["FCFTab_UpdateColors"] then
            hooksecurefunc("FCFTab_UpdateColors", function(tab, selected)
                local tData = chatData[tab]
                
                if WT.DB.Chat.CleanTabs then
                    if tab.NineSlice then tab.NineSlice:SetAlpha(0) end
                    local regions = {tab:GetRegions()}
                    for _, r in ipairs(regions) do
                        local rName = Unsecret(r:GetName())
                        if r:GetObjectType() == "Texture" and rName then
                            if string.find(rName, "Left") or string.find(rName, "Middle") or string.find(rName, "Right") or string.find(rName, "Mid") or string.find(rName, "Active") or string.find(rName, "Highlight") or string.find(rName, "Selected") then
                                if not string.find(rName, "Text") and not string.find(rName, "Icon") and not string.find(rName, "Glow") then
                                    r:SetAlpha(0)
                                    r:SetTexture("")
                                end
                            end
                        end
                    end
                end
                
                if WT.DB.Chat.CleanTabs and tData and tData.wtBg then
                    if selected then
                        local actBg = WT.DB.Chat.TabActiveBgColor or {r=0.1, g=0.1, b=0.1, a=0.8}
                        local actBd = WT.DB.Chat.TabActiveBorderColor or {r=0, g=1, b=1, a=1}
                        if type(actBg) == "string" then actBg = {r=0.1, g=0.1, b=0.1, a=0.8} end
                        if type(actBd) == "string" then actBd = {r=0, g=1, b=1, a=1} end
                        
                        tData.wtBg:SetVertexColor(actBg.r, actBg.g, actBg.b, actBg.a)
                        tData.wtTop:SetVertexColor(actBd.r, actBd.g, actBd.b, actBd.a)
                        if tData.wtLeft.SetGradient then
                            SafeSetGradient(tData.wtLeft, "VERTICAL", actBd.r, actBd.g, actBd.b, 0, actBd.r, actBd.g, actBd.b, actBd.a)
                            SafeSetGradient(tData.wtRight, "VERTICAL", actBd.r, actBd.g, actBd.b, 0, actBd.r, actBd.g, actBd.b, actBd.a)
                        else
                            tData.wtLeft:SetVertexColor(actBd.r, actBd.g, actBd.b, actBd.a)
                            tData.wtRight:SetVertexColor(actBd.r, actBd.g, actBd.b, actBd.a)
                        end
                    else
                        local inactBg = WT.DB.Chat.TabInactiveBgColor or {r=0, g=0, b=0, a=0.8}
                        local inactBd = WT.DB.Chat.TabInactiveBorderColor or {r=0.3, g=0.3, b=0.3, a=0.8}
                        if type(inactBg) == "string" then inactBg = {r=0, g=0, b=0, a=0.8} end
                        if type(inactBd) == "string" then inactBd = {r=0.3, g=0.3, b=0.3, a=0.8} end
                        
                        tData.wtBg:SetVertexColor(inactBg.r, inactBg.g, inactBg.b, inactBg.a)
                        tData.wtTop:SetVertexColor(inactBd.r, inactBd.g, inactBd.b, inactBd.a)
                        if tData.wtLeft.SetGradient then
                            SafeSetGradient(tData.wtLeft, "VERTICAL", inactBd.r, inactBd.g, inactBd.b, 0, inactBd.r, inactBd.g, inactBd.b, inactBd.a)
                            SafeSetGradient(tData.wtRight, "VERTICAL", inactBd.r, inactBd.g, inactBd.b, 0, inactBd.r, inactBd.g, inactBd.b, inactBd.a)
                        else
                            tData.wtLeft:SetVertexColor(inactBd.r, inactBd.g, inactBd.b, inactBd.a)
                            tData.wtRight:SetVertexColor(inactBd.r, inactBd.g, inactBd.b, inactBd.a)
                        end
                    end
                end
                
                if WT.DB.Chat.CustomTabFont then
                    if selected then
                        local actTxt = WT.DB.Chat.TabActiveTextColor or {r=1, g=1, b=1, a=1}
                        if type(actTxt) == "string" then actTxt = {r=1, g=1, b=1, a=1} end
                        tab:GetFontString():SetTextColor(actTxt.r, actTxt.g, actTxt.b, actTxt.a)
                    else
                        local inactTxt = WT.DB.Chat.TabInactiveTextColor or {r=0.6, g=0.6, b=0.6, a=1}
                        if type(inactTxt) == "string" then inactTxt = {r=0.6, g=0.6, b=0.6, a=1} end
                        tab:GetFontString():SetTextColor(inactTxt.r, inactTxt.g, inactTxt.b, inactTxt.a)
                    end
                end
            end)
        end
    end
    
    for _, frameName in ipairs(CHAT_FRAMES) do
        local tab = _G[frameName.."Tab"]
        if tab then
            if tab.NineSlice then tab.NineSlice:SetAlpha(enable and 0 or 1) end
            local regions = {tab:GetRegions()}
            for _, r in ipairs(regions) do
                if r:GetObjectType() == "Texture" and not r.isWT then
                    local rName = Unsecret(r:GetName()) or ""
                    if not string.find(rName, "Text") and not string.find(rName, "Icon") and not string.find(rName, "Glow") then
                        r:SetAlpha(enable and 0 or 1)
                    end
                end
            end
            
            local tData = chatData[tab]
            if not tData then tData = {}; chatData[tab] = tData end
            if tData.wtBackdrop then tData.wtBackdrop:Hide() end
            
            if enable then
                if not tData.wtBg then
                    ---@type WTChatTexture
                    tData.wtBg = tab:CreateTexture(nil, "BACKGROUND")
                    tData.wtBg.isWT = true
                    tData.wtBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                    
                    ---@type WTChatTexture
                    tData.wtTop = tab:CreateTexture(nil, "BORDER")
                    tData.wtTop.isWT = true
                    tData.wtTop:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                    tData.wtTop:SetHeight(1)
                    
                    ---@type WTChatTexture
                    tData.wtLeft = tab:CreateTexture(nil, "BORDER")
                    tData.wtLeft.isWT = true
                    tData.wtLeft:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                    tData.wtLeft:SetWidth(1)
                    
                    ---@type WTChatTexture
                    tData.wtRight = tab:CreateTexture(nil, "BORDER")
                    tData.wtRight.isWT = true
                    tData.wtRight:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                    tData.wtRight:SetWidth(1)
                    
                    tab:HookScript("OnEnter", function(self)
                        local td = chatData[self]
                        if td and td.wtBg and WT.DB.Chat.CleanTabs then
                            local isSelected = SELECTED_CHAT_FRAME and (self:GetID() == SELECTED_CHAT_FRAME:GetID())
                            if not isSelected then
                                td.wtTop:SetVertexColor(0.6, 0.6, 0.6, 1)
                                if td.wtLeft.SetGradient then
                                    SafeSetGradient(td.wtLeft, "VERTICAL", 0.6, 0.6, 0.6, 0, 0.6, 0.6, 0.6, 1)
                                    SafeSetGradient(td.wtRight, "VERTICAL", 0.6, 0.6, 0.6, 0, 0.6, 0.6, 0.6, 1)
                                else
                                    td.wtLeft:SetVertexColor(0.6, 0.6, 0.6, 1)
                                    td.wtRight:SetVertexColor(0.6, 0.6, 0.6, 1)
                                end
                            end
                        end
                    end)
                    
                    tab:HookScript("OnLeave", function(self)
                        local td = chatData[self]
                        if td and td.wtBg and WT.DB.Chat.CleanTabs then
                            local isSelected = SELECTED_CHAT_FRAME and (self:GetID() == SELECTED_CHAT_FRAME:GetID())
                            if not isSelected then
                                local inactBd = WT.DB.Chat.TabInactiveBorderColor or {r=0.3, g=0.3, b=0.3, a=0.8}
                                if type(inactBd) == "string" then inactBd = {r=0.3, g=0.3, b=0.3, a=0.8} end
                                td.wtTop:SetVertexColor(inactBd.r, inactBd.g, inactBd.b, inactBd.a)
                                if td.wtLeft.SetGradient then
                                    SafeSetGradient(td.wtLeft, "VERTICAL", inactBd.r, inactBd.g, inactBd.b, 0, inactBd.r, inactBd.g, inactBd.b, inactBd.a)
                                    SafeSetGradient(td.wtRight, "VERTICAL", inactBd.r, inactBd.g, inactBd.b, 0, inactBd.r, inactBd.g, inactBd.b, inactBd.a)
                                else
                                    td.wtLeft:SetVertexColor(inactBd.r, inactBd.g, inactBd.b, inactBd.a)
                                    td.wtRight:SetVertexColor(inactBd.r, inactBd.g, inactBd.b, inactBd.a)
                                end
                            end
                        end
                    end)
                end
                
                tData.wtBg:ClearAllPoints()
                tData.wtBg:SetPoint("TOPLEFT", tab, "TOPLEFT", 5, -11)
                tData.wtBg:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -5, 0)
                
                tData.wtTop:ClearAllPoints()
                tData.wtTop:SetPoint("TOPLEFT", tData.wtBg, "TOPLEFT", 0, 0)
                tData.wtTop:SetPoint("TOPRIGHT", tData.wtBg, "TOPRIGHT", 0, 0)
                
                tData.wtLeft:ClearAllPoints()
                tData.wtLeft:SetPoint("TOPLEFT", tData.wtBg, "TOPLEFT", 0, 0)
                tData.wtLeft:SetPoint("BOTTOMLEFT", tData.wtBg, "BOTTOMLEFT", 0, 1) -- 1px offset to not hit chat bg
                
                tData.wtRight:ClearAllPoints()
                tData.wtRight:SetPoint("TOPRIGHT", tData.wtBg, "TOPRIGHT", 0, 0)
                tData.wtRight:SetPoint("BOTTOMRIGHT", tData.wtBg, "BOTTOMRIGHT", 0, 1) -- 1px offset to not hit chat bg
                
                tData.wtBg:Show(); tData.wtTop:Show(); tData.wtLeft:Show(); tData.wtRight:Show()
            elseif tData and tData.wtBg then
                tData.wtBg:Hide(); tData.wtTop:Hide(); tData.wtLeft:Hide(); tData.wtRight:Hide()
            end
            
            local fs = tab:GetFontString()
            if fs and customFont then
                local fontPath = (WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", WT.DB.Chat.TabFont)) or "Fonts\\FRIZQT__.TTF"
                local fontSize = WT.DB.Chat.TabFontSize or 12
                local outline = (WT.DB.Chat.TabFontOutline == "NONE") and "" or (WT.DB.Chat.TabFontOutline or "OUTLINE")
                fs:SetFont(fontPath, fontSize, outline)
            end
            
            if _G["FCFTab_UpdateColors"] then
                local isSelected = SELECTED_CHAT_FRAME and (tab:GetID() == SELECTED_CHAT_FRAME:GetID())
                _G["FCFTab_UpdateColors"](tab, isSelected)
            end
        end
    end
end

function Module:UpdateTabVisibility()
    local enable = WT.DB.Chat.HideTabs
    
    if not self.tabAlphaHooked then
        self.tabAlphaHooked = true
        hooksecurefunc("FCFTab_UpdateAlpha", function(chatFrame)
            local tab = _G[chatFrame:GetName().."Tab"]
            if tab and WT.DB.Chat.HideTabs then
                if not tab:IsMouseOver() then
                    UIFrameFadeRemoveFrame(tab)
                    tab:SetAlpha(0)
                else
                    UIFrameFadeRemoveFrame(tab)
                    tab:SetAlpha(1)
                end
            end
        end)
    end
    
    for _, frameName in ipairs(CHAT_FRAMES) do
        local chatFrame = _G[frameName]
        local tab = _G[frameName.."Tab"]
        
        if chatFrame and FCFTab_UpdateAlpha then
            FCFTab_UpdateAlpha(chatFrame)
        end
        
        if tab then
            local tData = chatData[tab]
            if not tData then tData = {}; chatData[tab] = tData end
            
            if not tData.wtHoverVisHooked then
                tData.wtHoverVisHooked = true
                tab:HookScript("OnEnter", function(self)
                    if WT.DB.Chat.HideTabs then
                        UIFrameFadeRemoveFrame(self)
                        UIFrameFadeIn(self, 0.1, self:GetAlpha(), 1.0)
                    end
                end)
                tab:HookScript("OnLeave", function(self)
                    if WT.DB.Chat.HideTabs then
                        UIFrameFadeRemoveFrame(self)
                        UIFrameFadeOut(self, 0.2, self:GetAlpha(), 0.0)
                    end
                end)
            end
            
            if enable and not tab:IsMouseOver() then
                UIFrameFadeRemoveFrame(tab)
                tab:SetAlpha(0)
            elseif not enable then
                UIFrameFadeRemoveFrame(tab)
                local isSelected = SELECTED_CHAT_FRAME and (tab:GetID() == SELECTED_CHAT_FRAME:GetID())
                tab:SetAlpha(isSelected and 1.0 or 0.2)
            end
        end
    end
end

-- Function to apply a custom font to the chat frames
function Module:UpdateChatFont()
    if not Module.chatFontHooked then
        Module.chatFontHooked = true
        hooksecurefunc("FCF_SetChatWindowFontSize", function(self, chatFrame, fontSize)
            if WT.DB.Chat.CustomChatFont then
                -- Delay slightly to let Blizzard finish setting the font size, then re-apply our custom settings
                C_Timer.After(0.01, function()
                    if Module.UpdateChatFont then Module:UpdateChatFont() end
                end)
            end
        end)
    end

    local defaultFont = ChatFontNormal and ChatFontNormal:GetFont() or STANDARD_TEXT_FONT
    for _, frameName in ipairs(CHAT_FRAMES) do
        local cf = _G[frameName]
        if cf then
            if WT.DB.Chat.CustomChatFont then
                local fontKey = WT.DB.Chat.ChatFont or "Friz Quadrata TT"
                local fontPath = (WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", fontKey)) or defaultFont
                local size = WT.DB.Chat.ChatFontSize or 14
                local outline = (WT.DB.Chat.ChatFontOutline == "NONE") and "" or (WT.DB.Chat.ChatFontOutline or "")
                cf:SetFont(fontPath, size, outline)
            else
                -- Restore Blizzard default
                local _, size = FCF_GetChatWindowInfo(cf:GetID())
                if not size or size == 0 then size = 14 end
                cf:SetFont(defaultFont, size, "")
            end
        end
    end
end

-- Function to globally override the chat background colors
function Module:UpdateChatBackground()
    if not Module.chatBgHooked then
        Module.chatBgHooked = true
        hooksecurefunc("FCF_SetWindowColor", function(frame, r, g, b)
            if WT.DB.Chat.CustomChatBg and not Module.isSettingChatBg then
                C_Timer.After(0.01, function() if Module.UpdateChatBackground then Module:UpdateChatBackground() end end)
            end
        end)
        hooksecurefunc("FCF_SetWindowAlpha", function(frame, alpha)
            if WT.DB.Chat.CustomChatBg and not Module.isSettingChatBg then
                C_Timer.After(0.01, function() if Module.UpdateChatBackground then Module:UpdateChatBackground() end end)
            end
        end)
    end

    if WT.DB.Chat.CustomChatBg then
        Module.isSettingChatBg = true
        local bgCol = WT.DB.Chat.ChatBgColor or {r=0, g=0, b=0, a=0.5}
        for _, frameName in ipairs(CHAT_FRAMES) do
            local cf = _G[frameName]
            if cf then
                FCF_SetWindowColor(cf, bgCol.r, bgCol.g, bgCol.b)
                FCF_SetWindowAlpha(cf, bgCol.a)
            end
        end
        Module.isSettingChatBg = false
    end
end

local function UpdateCharCountDisplay(eb)
    local sData = chatData[eb]
    if not sData or not sData.wtCharCount or not WT.DB.Chat.CharCount then return end
    
    local rawText = eb:GetText()
    local text = Unsecret(rawText) or ""
    local cleanText = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    cleanText = string.gsub(cleanText, "|r", "")
    cleanText = string.gsub(cleanText, "|H.-|h(.-)|h", "%1")
    cleanText = string.gsub(cleanText, "|T.-|t", "")
    
    local ok, len = pcall(_G.strlenutf8, cleanText)
    if not ok or type(len) ~= "number" then
        len = string.len(cleanText)
    end
    local maxLen = eb:GetMaxLetters()
    if maxLen <= 0 then maxLen = 255 end
    
    if sData.wtCharCountFrame.lastMaxLen ~= maxLen then
        sData.wtCharCount:SetText(maxLen .. "/" .. maxLen)
        sData.wtCharCountFrame:SetWidth(math.ceil(sData.wtCharCount:GetStringWidth()) + 12)
        sData.wtCharCountFrame.lastMaxLen = maxLen
    end
    
    sData.wtCharCount:SetText(len .. "/" .. maxLen)
    if len >= (maxLen - 15) then sData.wtCharCount:SetTextColor(1, 0, 0, 1)
    elseif len >= (maxLen - 55) then sData.wtCharCount:SetTextColor(1, 0.5, 0, 1)
    elseif len >= (maxLen - 105) then sData.wtCharCount:SetTextColor(1, 1, 0, 1)
    elseif len > 0 then sData.wtCharCount:SetTextColor(1, 1, 1, 1)
    else sData.wtCharCount:SetTextColor(0.5, 0.5, 0.5, 1) end
end

-- Function to dynamically display a character count in the edit box while typing
function Module:UpdateCharacterCount()
    for _, frameName in ipairs(CHAT_FRAMES) do
        local eb = _G[frameName.."EditBox"]
        if eb then
            local eData = chatData[eb]; if not eData then eData = {}; chatData[eb] = eData end
            
            if not eData.wtCharCountFrame then
                eData.wtCharCountFrame = CreateFrame("Frame", nil, eb)
                eData.wtCharCountFrame.ignoreInLayout = true
                eData.wtCharCountFrame.ignoreFramePositionManager = true
                if eData.wtCharCountFrame.SetIsFramePositionManaged then pcall(function() eData.wtCharCountFrame:SetIsFramePositionManaged(false) end) end
                eData.wtCharCountFrame:SetHeight(16)
                eData.wtCharCountFrame:SetFrameStrata(eb:GetFrameStrata())
                eData.wtCharCountFrame:SetFrameLevel(eb:GetFrameLevel() + 5)
                
                eData.wtCharCountBg = eData.wtCharCountFrame:CreateTexture(nil, "BACKGROUND")
                eData.wtCharCountBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
                eData.wtCharCountBg:SetPoint("TOPLEFT", 1, -1); eData.wtCharCountBg:SetPoint("BOTTOMRIGHT", -1, 1)
                eData.wtCharCountBg:SetVertexColor(0, 0, 0, 0.8)
                
                eData.wtCharCountTop = eData.wtCharCountFrame:CreateTexture(nil, "BORDER")
                eData.wtCharCountTop:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); eData.wtCharCountTop:SetHeight(1)
                eData.wtCharCountTop:SetPoint("TOPLEFT", 0, 0); eData.wtCharCountTop:SetPoint("TOPRIGHT", 0, 0)
                eData.wtCharCountBot = eData.wtCharCountFrame:CreateTexture(nil, "BORDER")
                eData.wtCharCountBot:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); eData.wtCharCountBot:SetHeight(1)
                eData.wtCharCountBot:SetPoint("BOTTOMLEFT", 0, 0); eData.wtCharCountBot:SetPoint("BOTTOMRIGHT", 0, 0)
                eData.wtCharCountLeft = eData.wtCharCountFrame:CreateTexture(nil, "BORDER")
                eData.wtCharCountLeft:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); eData.wtCharCountLeft:SetWidth(1)
                eData.wtCharCountLeft:SetPoint("TOPLEFT", 0, 0); eData.wtCharCountLeft:SetPoint("BOTTOMLEFT", 0, 0)
                eData.wtCharCountRight = eData.wtCharCountFrame:CreateTexture(nil, "BORDER")
                eData.wtCharCountRight:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); eData.wtCharCountRight:SetWidth(1)
                eData.wtCharCountRight:SetPoint("TOPRIGHT", 0, 0); eData.wtCharCountRight:SetPoint("BOTTOMRIGHT", 0, 0)
                
                eData.wtCharCountTop:SetVertexColor(0.3, 0.3, 0.3, 0.8)
                eData.wtCharCountBot:SetVertexColor(0.3, 0.3, 0.3, 0.8)
                eData.wtCharCountLeft:SetVertexColor(0.3, 0.3, 0.3, 0.8)
                eData.wtCharCountRight:SetVertexColor(0.3, 0.3, 0.3, 0.8)
                
                eData.wtCharCount = eData.wtCharCountFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                eData.wtCharCount:SetPoint("CENTER", eData.wtCharCountFrame, "CENTER", 0, 0)
                eData.wtCharCount:SetJustifyH("CENTER")
                eData.wtCharCount:SetJustifyV("MIDDLE")
                
                eb:HookScript("OnTextChanged", function(self)
                    UpdateCharCountDisplay(self)
                end)
            end
            
            if WT.DB.Chat.CharCount then
                local fontPath = ChatFontNormal and ChatFontNormal:GetFont() or STANDARD_TEXT_FONT
                local fontSize = type(WT.DB.Chat.CharCountFontSize) == "number" and WT.DB.Chat.CharCountFontSize or tonumber(tostring(WT.DB.Chat.CharCountFontSize)) or 10
                if WT.DB.Chat.CharCountFont and WT.DB.Chat.CharCountFont ~= "" then
                    local fetchedFont = WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", WT.DB.Chat.CharCountFont)
                    if type(fetchedFont) == "string" and fetchedFont ~= "" then fontPath = fetchedFont else fontPath = WT.DB.Chat.CharCountFont end
                end
                local outline = (WT.DB.Chat.CharCountFontOutline == "NONE") and "" or (WT.DB.Chat.CharCountFontOutline or "OUTLINE")
                eData.wtCharCount:SetFont(fontPath, fontSize, outline)
                
                eData.wtCharCountFrame:SetHeight(math.max(16, fontSize + 6))
                eData.wtCharCountFrame.lastMaxLen = nil
                
                local isCharTop = WT.DB.Chat.CharCountPos == "TOP"
                local cRight = WT.DB.Chat.CleanEditBox and (WT.DB.Chat.EditBoxStyle == "MODERN" and -5 or 2) or -10
                eData.wtCharCountFrame:ClearAllPoints()
                if isCharTop then
                    local cY = WT.DB.Chat.CleanEditBox and (WT.DB.Chat.EditBoxStyle == "MODERN" and -7 or -5) or -2
                    eData.wtCharCountFrame:SetPoint("BOTTOMRIGHT", eb, "TOPRIGHT", cRight, cY)
                else
                    local cY = WT.DB.Chat.CleanEditBox and (WT.DB.Chat.EditBoxStyle == "MODERN" and 7 or 5) or 2
                    eData.wtCharCountFrame:SetPoint("TOPRIGHT", eb, "BOTTOMRIGHT", cRight, cY)
                end
                
                if eb:HasFocus() then
                    eData.wtCharCountFrame:Show()
                else
                    eData.wtCharCountFrame:Hide()
                end
                
                if eData.UpdateFocusColors then eData.UpdateFocusColors() end
                
                local left, right, top, bottom = eb:GetTextInsets()
                if right == 55 then
                    eb:SetTextInsets(left, 15, top, bottom)
                end
            else
                eData.wtCharCountFrame:Hide()
                
                local left, right, top, bottom = eb:GetTextInsets()
                if right == 55 then
                    eb:SetTextInsets(left, 15, top, bottom)
                end
            end
            UpdateCharCountDisplay(eb)
        end
    end
end

function Module:UnclampChatFrames(unclamp)
    for _, frameName in ipairs(CHAT_FRAMES) do
        local chatFrame = _G[frameName]
        if chatFrame then
            if unclamp then
                chatFrame:SetClampRectInsets(0, 0, 0, 0)
                chatFrame:SetClampedToScreen(false)
            else
                chatFrame:SetClampedToScreen(true)
            end
        end
    end
end

function Module:UpdateQuickJoin(hide)
    if not QuickJoinToastButton then return end
    if hide then QuickJoinToastButton:SetAlpha(0)
    else QuickJoinToastButton:SetAlpha(1) end
    
    if self.ApplyQJPos and not InCombatLockdown() then self:ApplyQJPos() end
end

local function ShowURLPopup(url)
    if url then
    local f = _G["WT_UrlBox"]
    if not f then
        f = CreateFrame("Frame", "WT_UrlBox", _G["WT_UIContainer"], "BackdropTemplate")
        f:SetSize(350, 70); f:SetFrameStrata("DIALOG")
        
        f.ignoreInLayout = true
        f.ignoreFramePositionManager = true
        if f.SetIsFramePositionManaged then pcall(function() f:SetIsFramePositionManaged(false) end) end
        
        f:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        f:SetBackdropColor(WT.Colors.STD_BG_R, WT.Colors.STD_BG_G, WT.Colors.STD_BG_B, WT.Colors.STD_BG_A)
        f:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.8)
        
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            if WT.DB and WT.DB.Internal then
                if not WT.DB.Internal.Positions then WT.DB.Internal.Positions = {} end
                local p, _, rP, x, y = self:GetPoint()
                WT.DB.Internal.Positions["WT_UrlBox"] = {point=p, relativeTo="WT_UIContainer", relativePoint=rP, xOfs=x, yOfs=y}
            end
        end)
        
        local txt = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        txt:SetPoint("TOP", f, "TOP", 12, -10)
        txt:SetText(WT.L.URL_COPY_HINT)
        
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("RIGHT", txt, "LEFT", -6, 0)
        icon:SetTexture("Interface\\Icons\\INV_Misc_Orb_02") -- Platzhalter: Blaue Weltkugel
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        e:SetSize(300, 20)
        e:SetPoint("BOTTOM", f, "BOTTOM", 0, 15)
        e:SetAutoFocus(true)
        e:SetFontObject("ChatFontNormal")
        e:SetScript("OnEscapePressed", function() f:Hide() end)
        f.e = e
        
        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
        closeBtn:SetFrameLevel(f:GetFrameLevel() + 10)
        closeBtn:SetScript("OnClick", function() f:Hide() end)
        
        table.insert(UISpecialFrames, "WT_UrlBox")
    end
    
    if WT.DB and WT.DB.Internal and WT.DB.Internal.Positions and WT.DB.Internal.Positions["WT_UrlBox"] then
        local p = WT.DB.Internal.Positions["WT_UrlBox"]
        f:ClearAllPoints()
        f:SetPoint(p.point, _G["WT_UIContainer"], p.relativePoint, p.xOfs, p.yOfs)
    else
        f:ClearAllPoints()
        f:SetPoint("CENTER")
    end
    
    f.e:SetText(url)
    f.e:HighlightText()
    f:Show()
        return true
    end
    return false
end

function Module:EnableClickableLinks()
    hooksecurefunc("SetItemRef", function(link, text, button, chatFrame)
        if string.match(link, "^wturl:") then
            local url = string.match(link, "^wturl:(.+)")
            if url then
                if (string.match(url, "wowhead%.com") or string.match(url, "raider%.io")) and WT.Modules.Wowhead and type(WT.Modules.Wowhead.ShowPopup) == "function" then
                    C_Timer.After(0.01, function() WT.Modules.Wowhead.ShowPopup(url) end)
                else
                    C_Timer.After(0.01, function() ShowURLPopup(url) end)
                end
            end
            return
        elseif string.match(link, "^wtwowhead:") then
            local whLink = string.match(link, "^wtwowhead:(.+)")
            if whLink and WT.Modules.Wowhead and type(WT.Modules.Wowhead.ProcessWowheadLink) == "function" then
                C_Timer.After(0.01, function() WT.Modules.Wowhead.ProcessWowheadLink(whLink) end)
            end
            return
        elseif string.match(link, "^wtignore:") then
            local target = string.match(link, "^wtignore:(.+)")
            if target and target ~= "" then
                C_Timer.After(0.01, function()
                    C_FriendList.AddIgnore(target)
                    if WT.Utils and WT.Utils.Logger then
                        WT.Utils.Logger:Print(string.format(WT.L.MSG_IGNORE_ADDED, "|cFF00FFFF"..target.."|r"))
                    end
                end)
            end
            return
        elseif string.match(link, "^wtwhitelist:") then
            local target = string.match(link, "^wtwhitelist:(.+)")
            if target and target ~= "" then
                C_Timer.After(0.01, function()
                    local currentList = WT.DB.Chat.WhitelistPlayers or ""
                    if currentList == "" then
                        WT.DB.Chat.WhitelistPlayers = target
                    elseif not string.find(string.lower(currentList), string.lower(target), 1, true) then
                        WT.DB.Chat.WhitelistPlayers = currentList .. ", " .. target
                    end
                    WT.Modules.Chat:UpdateChatFilters()
                    if WT.Utils and WT.Utils.Logger then
                        WT.Utils.Logger:Print(string.format(WT.L.MSG_WHITELIST_ADDED, "|cFF00FFFF"..target.."|r"))
                    end
                end)
            end
            return
        elseif string.match(link, "^wtblock:") then
            local id = string.match(link, "^wtblock:(.+)")
            if id and WT.Modules.Chat.blockedMessages and WT.Modules.Chat.blockedMessages[id] then
                local target = WT.Modules.Chat.blockedMessages[id].sender
                if button == "RightButton" and chatFrame then
                    C_Timer.After(0.01, function()
                        local msgData = WT.Modules.Chat.blockedMessages[id]
                        WT.Modules.Chat.isRestoringBlockedMsg = true
                        local textToRestore = msgData.originalText
                        if msgData.timestamp and msgData.timestamp ~= "" and not string.match(textToRestore, "^|cFF%x%x%x%x%x%x%d%d?[:%.]%d%d") then
                            textToRestore = msgData.timestamp .. textToRestore
                        end
                        chatFrame:AddMessage(textToRestore)
                        WT.Modules.Chat.isRestoringBlockedMsg = false
                    end)
                elseif button == "LeftButton" and target then
                    if IsShiftKeyDown() then
                        C_Timer.After(0.01, function()
                            C_FriendList.AddIgnore(target)
                            if WT.Utils and WT.Utils.Logger then
                                WT.Utils.Logger:Print(string.format(WT.L.MSG_IGNORE_ADDED, "|cFF00FFFF"..target.."|r"))
                            end
                        end)
                    elseif IsControlKeyDown() then
                        C_Timer.After(0.01, function()
                            local currentList = WT.DB.Chat.WhitelistPlayers or ""
                            if currentList == "" then
                                WT.DB.Chat.WhitelistPlayers = target
                            elseif not string.find(string.lower(currentList), string.lower(target), 1, true) then
                                WT.DB.Chat.WhitelistPlayers = currentList .. ", " .. target
                            end
                            WT.Modules.Chat:UpdateChatFilters()
                            if WT.Utils and WT.Utils.Logger then
                                WT.Utils.Logger:Print(string.format(WT.L.MSG_WHITELIST_ADDED, "|cFF00FFFF"..target.."|r"))
                            end
                        end)
                    end
                end
            end
            return
        end
    end)
    
    for _, frameName in ipairs(CHAT_FRAMES) do
        local cf = _G[frameName]
        if cf then
            local cData = chatData[cf]
            if not cData then cData = {}; chatData[cf] = cData end
            
            if not cData.wtHoverHooked then
                cData.wtHoverHooked = true
                cf:HookScript("OnHyperlinkEnter", function(self, link)
                    if link and string.match(link, "^wtblock:") then
                        local id = string.match(link, "^wtblock:(.+)")
                        if id and WT.Modules.Chat.blockedMessages and WT.Modules.Chat.blockedMessages[id] then
                            local tt = _G["WTCustomTooltip"]
                            if not tt then
                                tt = CreateFrame("GameTooltip", "WTCustomTooltip", UIParent, "GameTooltipTemplate")
                            end
                            tt:SetOwner(self, "ANCHOR_CURSOR")
                            tt:ClearLines()
                            tt:AddLine(WT.L.TT_BLOCKED_MSG, 1, 0, 0)
                            tt:AddLine(WT.Modules.Chat.blockedMessages[id].tooltipText, 1, 1, 1, true)
                            tt:AddLine(" ")
                            tt:AddLine(WT.L.TT_HINT_RESTORE, 1, 1, 1)
                            if WT.Modules.Chat.blockedMessages[id].sender then
                                tt:AddLine(WT.L.TT_HINT_IGNORE, 1, 1, 1)
                                tt:AddLine(WT.L.TT_HINT_WHITELIST, 1, 1, 1)
                            end
                            tt:Show()
                        end
                    end
                end)
                cf:HookScript("OnHyperlinkLeave", function(self)
                    if _G["WTCustomTooltip"] then _G["WTCustomTooltip"]:Hide() end
                end)
                cf:HookScript("OnLeave", function(self)
                    if _G["WTCustomTooltip"] then _G["WTCustomTooltip"]:Hide() end
                end)
            end
        end
    end
end

local cvarTimestampHooked = false
function Module:UpdateTimestamps()
    if not WT.DB.Chat then return end
    if WT.DB.Chat.Timestamps then
        _G.CHAT_TIMESTAMP_FORMAT = nil
    else
        local wowFormat = C_CVar.GetCVar("showTimestamps")
        if wowFormat and wowFormat ~= "none" and wowFormat ~= "0" then
            _G.CHAT_TIMESTAMP_FORMAT = wowFormat
        else
            _G.CHAT_TIMESTAMP_FORMAT = nil
        end
    end

    if not cvarTimestampHooked then
        cvarTimestampHooked = true
        WT.Core.Events:Register("CVAR_UPDATE", function(event, cvarName)
            if cvarName == "showTimestamps" then
                C_Timer.After(0.1, function() if Module.UpdateTimestamps then Module:UpdateTimestamps() end end)
            end
        end)
    end
end

function Module:GetTimestampString()
    if not WT.DB.Chat.Timestamps then return "" end
    local formatStr = WT.DB.Chat.TimestampFormat or "%H:%M"
    
    local tCol = WT.DB.Chat.TimestampColor or "888888"
    if type(tCol) == "table" then tCol = WT.Colors:GetHex(tCol) end
    local colorStr = string.gsub(tCol, "^#", "")
    if #colorStr < 8 then colorStr = "FF" .. colorStr end
    
    local bColRaw = WT.DB.Chat.TimestampBracketColor or "888888"
    if type(bColRaw) == "table" then bColRaw = WT.Colors:GetHex(bColRaw) end
    local bCol = string.gsub(bColRaw, "^#", "")
    if #bCol < 8 then bCol = "FF" .. bCol end
    
    local style = WT.DB.Chat.TimestampStyle or 1
    local b1, b2 = "", ""
    if style == 1 then b1, b2 = "(", ")"
    elseif style == 2 then b1, b2 = "[", "]"
    elseif style == 3 then b1, b2 = "", " |" end
    
    local tsString = ""
    if b1 ~= "" then tsString = tsString .. "|c" .. bCol .. b1 .. "|r" end
    tsString = tsString .. "|c" .. colorStr .. date(formatStr) .. "|r"
    if b2 ~= "" then tsString = tsString .. "|c" .. bCol .. b2 .. "|r" end
    return tsString .. " "
end

function Module:BuildOptions(builder, panel, part)
    -- "part" builds only one section when the module is spread over several options pages
    local function ShowPart(name) return part == nil or part == name end
    local function AddDescription(text)
        if not text then return end
        local desc = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
        desc:SetWidth(550)
        desc:SetJustifyH("LEFT")
        desc:SetText(text)
        builder:AddSpace(desc:GetStringHeight() + 25)
    end
    
    if ShowPart("Display") then
        panel:CreateTitle(builder, WT.L.GROUP_CHAT_APPEARANCE)
        AddDescription(WT.L.OPT_DESC_GROUP_CHAT_APPEARANCE)
    
        panel:CreateCheckbox(builder, WT.L.OPT_CHAT_CLASS_COLORS, WT.L.OPT_DESC_CHAT_CLASS_COLORS, "Chat", "ClassColors", function(value) if WT.Modules.Chat and type(WT.Modules.Chat.UpdateClassColors) == "function" then WT.Modules.Chat:UpdateClassColors(value) end end)
        panel:CreateCheckbox(builder, WT.L.OPT_CHAT_COPY, WT.L.OPT_DESC_CHAT_COPY, "Chat", "ChatCopy")
        panel:CreateCheckbox(builder, WT.L.OPT_CHAT_HIDE_SERVER, WT.L.OPT_DESC_CHAT_HIDE_SERVER, "Chat", "HideServerNames")
        panel:CreateCheckbox(builder, WT.L.OPT_CHAT_SHOW_LEVELS, WT.L.OPT_DESC_CHAT_SHOW_LEVELS, "Chat", "ShowPlayerLevels", function() if WT.Modules.Chat and type(WT.Modules.Chat.UpdatePlayerLevelCache) == "function" then WT.Modules.Chat:UpdatePlayerLevelCache() end end)
    
        panel:CreateCheckbox(builder, WT.L.OPT_CHAT_HIDE_BUTTONS, WT.L.OPT_DESC_CHAT_HIDE_BUTTONS, "Chat", "HideButtons", function() self:UpdateChatButtonsVisibility() end)
        panel:CreateCheckbox(builder, WT.L.OPT_CHAT_HIDE_QUICKJOIN, WT.L.OPT_DESC_CHAT_HIDE_QUICKJOIN, "Chat", "HideQuickJoin", function(value) self:UpdateQuickJoin(value) end)
        panel:CreateCheckbox(builder, WT.L.OPT_CHAT_DISABLE_FADING, WT.L.OPT_DESC_CHAT_DISABLE_FADING, "Chat", "DisableChatFading", function(value) self:UpdateChatFading(not value) end)
        panel:CreateCheckbox(builder, WT.L.OPT_CHAT_SHORT_CHANNELS, WT.L.OPT_DESC_CHAT_SHORT_CHANNELS, "Chat", "ShortChannelNames")
        panel:CreateCheckbox(builder, WT.L.OPT_CHAT_EDITBOX_TOP, WT.L.OPT_DESC_CHAT_EDITBOX_TOP, "Chat", "EditBoxTop", function() self:UpdateEditBoxPosition() end)
        local ceInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_CLEAN_EDITBOX, WT.L.OPT_DESC_CHAT_CLEAN_EDITBOX, "Chat", "CleanEditBox", function() self:UpdateCleanEditBox() end)
    
        local ebStyleOptions = {
            { value = "CLASSIC", label = WT.L.OPT_CHAT_EB_STYLE_CLASSIC },
            { value = "MODERN", label = WT.L.OPT_CHAT_EB_STYLE_MODERN }
        }
        panel:CreateDropdown(builder, WT.L.OPT_CHAT_EB_STYLE, WT.L.OPT_DESC_CHAT_EB_STYLE, "Chat", "EditBoxStyle", ebStyleOptions, function() self:UpdateCleanEditBox() end, ceInit)
    
        local ctInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_CLEAN_TABS, WT.L.OPT_DESC_CHAT_CLEAN_TABS, "Chat", "CleanTabs", function() self:UpdateCleanTabs() end)
        panel:CreateColorPicker(builder, WT.L.OPT_CHAT_TAB_ACTIVE_BG, WT.L.OPT_DESC_COLOR_BG, "Chat", "TabActiveBgColor", true, ctInit, function() self:UpdateCleanTabs() end)
        panel:CreateColorPicker(builder, WT.L.OPT_CHAT_TAB_ACTIVE_BORDER, WT.L.OPT_DESC_COLOR_BORDER, "Chat", "TabActiveBorderColor", true, ctInit, function() self:UpdateCleanTabs() end)
        panel:CreateColorPicker(builder, WT.L.OPT_CHAT_TAB_INACTIVE_BG, WT.L.OPT_DESC_COLOR_BG, "Chat", "TabInactiveBgColor", true, ctInit, function() self:UpdateCleanTabs() end)
        panel:CreateColorPicker(builder, WT.L.OPT_CHAT_TAB_INACTIVE_BORDER, WT.L.OPT_DESC_COLOR_BORDER, "Chat", "TabInactiveBorderColor", true, ctInit, function() self:UpdateCleanTabs() end)
    
        local tFontInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_TAB_CUSTOM_FONT, WT.L.OPT_DESC_CHAT_TAB_CUSTOM_FONT, "Chat", "CustomTabFont", function() self:UpdateCleanTabs() end)
        if WT.Utils and WT.Utils.SharedMedia then
            panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "Chat", "TabFont", WT.Utils.SharedMedia:GetOptions("font"), function() self:UpdateCleanTabs() end, tFontInit)
        end
        panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "Chat", "TabFontSize", 8, 24, 1, function() self:UpdateCleanTabs() end, tFontInit)
        panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "Chat", "TabFontOutline", function() self:UpdateCleanTabs() end, tFontInit)
        panel:CreateColorPicker(builder, WT.L.OPT_CHAT_TAB_ACTIVE_TEXT, WT.L.OPT_DESC_COLOR_VALUE, "Chat", "TabActiveTextColor", true, tFontInit, function() self:UpdateCleanTabs() end)
        panel:CreateColorPicker(builder, WT.L.OPT_CHAT_TAB_INACTIVE_TEXT, WT.L.OPT_DESC_COLOR_VALUE, "Chat", "TabInactiveTextColor", true, tFontInit, function() self:UpdateCleanTabs() end)
        panel:CreateCheckbox(builder, WT.L.OPT_CHAT_HIDE_TABS, WT.L.OPT_DESC_CHAT_HIDE_TABS, "Chat", "HideTabs", function() self:UpdateTabVisibility() end)
    
        local ebFontInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_EB_CUSTOM_FONT, WT.L.OPT_DESC_CHAT_EB_CUSTOM_FONT, "Chat", "CustomEditBoxFont", function() self:UpdateCleanEditBox() end)
        if WT.Utils and WT.Utils.SharedMedia then
            panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "Chat", "EditBoxFont", WT.Utils.SharedMedia:GetOptions("font"), function() self:UpdateCleanEditBox() end, ebFontInit)
        end
        panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "Chat", "EditBoxFontSize", 8, 24, 1, function() self:UpdateCleanEditBox() end, ebFontInit)

        local chatFontInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_CUSTOM_FONT, WT.L.OPT_DESC_CHAT_CUSTOM_FONT, "Chat", "CustomChatFont", function() self:UpdateChatFont() end)
        if WT.Utils and WT.Utils.SharedMedia then
            panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "Chat", "ChatFont", WT.Utils.SharedMedia:GetOptions("font"), function() self:UpdateChatFont() end, chatFontInit)
        end
        panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "Chat", "ChatFontSize", 8, 24, 1, function() self:UpdateChatFont() end, chatFontInit)
        panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "Chat", "ChatFontOutline", function() self:UpdateChatFont() end, chatFontInit)

        local chatBgInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_CUSTOM_BG, WT.L.OPT_DESC_CHAT_CUSTOM_BG, "Chat", "CustomChatBg", function() self:UpdateChatBackground() end)
        panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BG, WT.L.OPT_DESC_COLOR_BG, "Chat", "ChatBgColor", true, chatBgInit, function() self:UpdateChatBackground() end)

        local tsInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_TIMESTAMPS, WT.L.OPT_DESC_CHAT_TIMESTAMPS, "Chat", "Timestamps", function() self:UpdateTimestamps() end)
        local tsFormatOptions = {
            { value = "%H:%M", label = "15:30 (24h)" },
            { value = "%H:%M:%S", label = "15:30:45 (24h)" },
            { value = "%I:%M %p", label = "03:30 PM (12h)" },
            { value = "%I:%M:%S %p", label = "03:30:45 PM (12h)" }
        }
        panel:CreateDropdown(builder, WT.L.OPT_CHAT_TIMESTAMP_FORMAT, WT.L.OPT_DESC_CHAT_TIMESTAMP_FORMAT, "Chat", "TimestampFormat", tsFormatOptions, function() self:UpdateTimestamps() end, tsInit)
        panel:CreateColorPicker(builder, WT.L.OPT_CHAT_TIMESTAMP_COLOR, WT.L.OPT_DESC_CHAT_TIMESTAMP_COLOR, "Chat", "TimestampColor", false, tsInit, function() self:UpdateTimestamps() end)
        local tsStyleOptions = {
            { value = 1, label = "(15:30)" },
            { value = 2, label = "[15:30]" },
            { value = 3, label = "15:30 |" }
        }
        panel:CreateDropdown(builder, WT.L.OPT_CHAT_TIMESTAMP_STYLE, WT.L.OPT_DESC_CHAT_TIMESTAMP_STYLE, "Chat", "TimestampStyle", tsStyleOptions, function() self:UpdateTimestamps() end, tsInit)
        panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BRACKET, WT.L.OPT_DESC_COLOR_BRACKET, "Chat", "TimestampBracketColor", false, tsInit, function() self:UpdateTimestamps() end)
    
    end
    if ShowPart("Functions") then
        panel:CreateTitle(builder, WT.L.GROUP_CHAT_FUNCTIONALITY)
        AddDescription(WT.L.OPT_DESC_GROUP_CHAT_FUNCTIONALITY)
    
        panel:CreateCheckbox(builder, WT.L.OPT_CHAT_FREE_ARROW, WT.L.OPT_DESC_CHAT_FREE_ARROW, "Chat", "FreeArrowKeys", function(value) self:UpdateArrowKeys(value) end)
        panel:CreateCheckbox(builder, WT.L.OPT_CHAT_CLICKABLE_LINKS, WT.L.OPT_DESC_CHAT_CLICKABLE_LINKS, "Chat", "ClickableLinks")
        panel:CreateCheckbox(builder, WT.L.OPT_CHAT_UNCLAMP, WT.L.OPT_DESC_CHAT_UNCLAMP, "Chat", "UnclampChatFrames", function(value) self:UnclampChatFrames(value) end)
    
        local ccInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_CHAR_COUNT, WT.L.OPT_DESC_CHAT_CHAR_COUNT, "Chat", "CharCount", function() self:UpdateCharacterCount() end)
    
        local posOptions = {
            { value = "TOP", label = WT.L.OPT_POS_TOP },
            { value = "BOTTOM", label = WT.L.OPT_POS_BOTTOM }
        }
        panel:CreateDropdown(builder, WT.L.OPT_CHAT_CHAR_COUNT_POS, WT.L.OPT_DESC_CHAT_CHAR_COUNT_POS, "Chat", "CharCountPos", posOptions, function() self:UpdateCharacterCount() end, ccInit)
    
        if WT.Utils and WT.Utils.SharedMedia then
            panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "Chat", "CharCountFont", WT.Utils.SharedMedia:GetOptions("font"), function() self:UpdateCharacterCount() end, ccInit)
        end
        panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "Chat", "CharCountFontSize", 8, 24, 1, function() self:UpdateCharacterCount() end, ccInit)
        panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "Chat", "CharCountFontOutline", function() self:UpdateCharacterCount() end, ccInit)

        panel:CreateCheckbox(builder, WT.L.OPT_CHAT_MOUSEWHEEL, WT.L.OPT_DESC_CHAT_MOUSEWHEEL, "Chat", "MouseWheelScroll")
    end
end

function Module:Initialize()
    if not WT.DB.Modules.Chat then return end
    
    self:UpdateChatButtonsVisibility()
    self:UpdateChatFading(not WT.DB.Chat.DisableChatFading)
    self:UpdateEditBoxPosition()
    self:UpdateCleanEditBox()
    self:UpdateCleanTabs()
    if self.UpdateTabVisibility then self:UpdateTabVisibility() end
    self:UpdateCharacterCount()
    self:UpdateArrowKeys(WT.DB.Chat.FreeArrowKeys)
    self:EnableMouseWheel()
    self:EnableClickableLinks()
    self:UnclampChatFrames(WT.DB.Chat.UnclampChatFrames)
    self:UpdateTimestamps()
    self:UpdateQuickJoin(WT.DB.Chat.HideQuickJoin)
    self:UpdateChatFont()
    self:UpdateChatBackground()
    
    if _G["FCF_OpenTemporaryWindow"] then
        hooksecurefunc("FCF_OpenTemporaryWindow", function() self:ApplyHooksToNewFrames() end)
    end
    if _G["FCF_OpenNewWindow"] then
        hooksecurefunc("FCF_OpenNewWindow", function() self:ApplyHooksToNewFrames() end)
    end
end

WT.Core.Events:Register("PLAYER_LOGIN", function()
    Module:Initialize()
end)

WT.Core.Events:Register("PLAYER_REGEN_ENABLED", function()
    if editBoxPosPending then
        editBoxPosPending = false
        if Module.UpdateEditBoxPosition then
            Module:UpdateEditBoxPosition()
        end
    end
end)