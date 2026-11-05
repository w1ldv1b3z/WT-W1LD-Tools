local _, WT = ...

WT.Modules.ChatCopy = {}
local Module = WT.Modules.ChatCopy

local copyFrame

local function StripTags(text, keepColors)
    if not text then return "" end
    -- Remove |T...|t (Textures)
    text = string.gsub(text, "|T.-|t", "")
    -- Remove |A...|a (Atlas Textures)
    text = string.gsub(text, "|A.-|a", "")
    
    if not keepColors then
        -- Remove |H...|h (Hyperlinks), keep the visible text inside
        text = string.gsub(text, "|H.-|h(.-)|h", "%1")
        -- Remove |c........ (Color codes)
        text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
        -- Remove |r (Color resets)
        text = string.gsub(text, "|[rR]", "")
    end
    
    return text
end

local function IsSafeString(str)
    if not str then return false end
    -- Secret strings (WoW 11.0+) return "string" for type(), but throw a taint error when compared.
    -- The only safe way to detect them without crashing the UI is using pcall.
    local ok = pcall(function() return str == "" end)
    return ok
end

local function GetChatLines(chatFrame, keepColors)
    local lines = {}
    if type(chatFrame.GetNumMessages) == "function" then
        for i = 1, chatFrame:GetNumMessages() do
            local text, r, g, b = chatFrame:GetMessageInfo(i)
            if IsSafeString(text) and text ~= "" then
                text = StripTags(text, keepColors)
                if keepColors and r and g and b then
                    local hex = string.format("|cff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
                    -- We do NOT replace |r with hex here anymore because doing so doubles the |c tags
                    -- and hits the 100-tag limit twice as fast. Chat_Filter already handles history colors.
                    text = hex .. text .. "|r"
                end
                table.insert(lines, text)
            end
        end
    end
    return lines
end

local function BuildCopyFrame()
    if copyFrame then return copyFrame end
    
    copyFrame = CreateFrame("Frame", "WTChatCopyFrame", UIParent, "BackdropTemplate")
    copyFrame:SetSize(700, 500)
    copyFrame:SetPoint("CENTER", UIParent, "CENTER")
    copyFrame:SetFrameStrata("DIALOG")
    copyFrame:EnableMouse(true)
    copyFrame:SetMovable(true)
    
    local function StartDrag(self, button)
        if button == "LeftButton" and IsAltKeyDown() then
            copyFrame:StartMoving()
            copyFrame.isMoving = true
        end
    end
    
    local function StopDrag(self, button)
        if copyFrame.isMoving then
            copyFrame:StopMovingOrSizing()
            copyFrame:SetUserPlaced(true)
            copyFrame.isMoving = false
            if copyFrame.resetBtn then copyFrame.resetBtn:Show() end
        end
    end

    copyFrame:SetScript("OnMouseDown", StartDrag)
    copyFrame:SetScript("OnMouseUp", StopDrag)
    copyFrame:Hide()
    
    copyFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    copyFrame:SetBackdropColor(WT.Colors.BG_R, WT.Colors.BG_G, WT.Colors.BG_B, WT.Colors.BG_A or 0.9)
    copyFrame:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 1)
    
    -- Tab Container
    copyFrame.tabContainer = CreateFrame("Frame", nil, copyFrame)
    copyFrame.tabContainer:SetPoint("TOPLEFT", copyFrame, "TOPLEFT", 15, -10)
    copyFrame.tabContainer:SetPoint("TOPRIGHT", copyFrame, "TOPRIGHT", -15, -10)
    copyFrame.tabContainer:SetHeight(24)
    copyFrame.tabs = {}
    
    -- ScrollFrame
    local sf = CreateFrame("ScrollFrame", "WTChatCopyScrollFrame", copyFrame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", copyFrame, "TOPLEFT", 15, -35)
    sf:SetPoint("BOTTOMRIGHT", copyFrame, "BOTTOMRIGHT", -35, 45)
    
    if WT.Config and WT.Config.Builder and type(WT.Config.Builder.StyleScrollFrame) == "function" then
        WT.Config.Builder:StyleScrollFrame(sf)
    end
    
    -- Single EditBox (Colored Text, Interactive)
    local eb = CreateFrame("EditBox", "WTChatCopyEditBox", sf)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(99999)
    eb:EnableMouse(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(620)
    
    sf:SetScrollChild(eb)
    copyFrame.editBox = eb
    copyFrame.scrollFrame = sf
    
    eb:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
    
    if ScrollingEdit_OnCursorChanged then
        eb:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        eb:SetScript("OnUpdate", function(self, elapsed)
            ScrollingEdit_OnUpdate(self, elapsed, self:GetParent())
        end)
    end
    
    -- Close Button
    local closeBtn = CreateFrame("Button", nil, copyFrame, "UIPanelButtonTemplate")
    closeBtn:SetSize(120, 24)
    closeBtn:SetPoint("BOTTOM", copyFrame, "BOTTOM", 0, 10)
    closeBtn:SetText(CLOSE or "Close")
    closeBtn:SetScript("OnClick", function() copyFrame:Hide() end)
    
    -- Reset Position Button (Subtle)
    local resetBtn = CreateFrame("Button", nil, copyFrame)
    resetBtn:SetSize(120, 20)
    resetBtn:SetPoint("BOTTOMRIGHT", copyFrame, "BOTTOMRIGHT", -25, 12)
    
    local resetText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetText:SetPoint("CENTER")
    resetText:SetText(WT.L.OPT_CHAT_COPY_RESET)
    resetText:SetTextColor(0.5, 0.5, 0.5)
    
    resetBtn:SetScript("OnEnter", function() resetText:SetTextColor(1, 1, 1) end)
    resetBtn:SetScript("OnLeave", function() resetText:SetTextColor(0.5, 0.5, 0.5) end)
    resetBtn:SetScript("OnClick", function() 
        copyFrame:ClearAllPoints()
        copyFrame:SetPoint("CENTER", UIParent, "CENTER")
        copyFrame:SetUserPlaced(false)
        resetBtn:Hide()
    end)
    
    copyFrame.resetBtn = resetBtn
    
    if WT.Config and WT.Config.Builder and type(WT.Config.Builder.StyleButton) == "function" then
        WT.Config.Builder:StyleButton(closeBtn)
    end
    
    return copyFrame
end

function Module:UpdateTabs(activeChatFrame)
    -- Hide all existing tabs first
    for _, tab in ipairs(copyFrame.tabs) do
        tab:Hide()
    end
    
    local tabIndex = 1
    local previousTab = nil
    
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        local chatTab = _G["ChatFrame" .. i .. "Tab"]
        
        if chatFrame and chatFrame ~= ChatFrame2 and chatTab and chatTab:IsShown() then
            local tabName = chatTab:GetText()
            if tabName and tabName ~= "" then
                local tab = copyFrame.tabs[tabIndex]
                if not tab then
                    tab = CreateFrame("Button", nil, copyFrame.tabContainer)
                    tab:SetHeight(20)
                    
                    local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    text:SetPoint("CENTER", 0, 0)
                    tab.text = text
                    
                    tab:SetScript("OnClick", function()
                        Module:ShowCopyFrame(tab.chatFrameTarget)
                    end)
                    
                    copyFrame.tabs[tabIndex] = tab
                end
                
                tab.chatFrameTarget = chatFrame
                tab.text:SetText(tabName)
                local textWidth = tab.text:GetStringWidth()
                tab:SetWidth(textWidth + 20)
                
                if previousTab then
                    tab:SetPoint("LEFT", previousTab, "RIGHT", 5, 0)
                else
                    tab:SetPoint("LEFT", copyFrame.tabContainer, "LEFT", 0, 0)
                end
                
                -- Highlight logic
                if chatFrame == activeChatFrame then
                    tab.text:SetTextColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B)
                else
                    tab.text:SetTextColor(0.5, 0.5, 0.5)
                end
                
                tab:Show()
                previousTab = tab
                tabIndex = tabIndex + 1
            end
        end
    end
end

function Module:ShowCopyFrame(chatFrame)
    local cf = BuildCopyFrame()
    cf.activeChatFrame = chatFrame
    
    -- Get lines array WITHOUT colors
    local lines = GetChatLines(chatFrame, false)   
    
    -- Sync Font Settings 1:1 with the ChatFrame
    local font, size, flags = chatFrame:GetFont()
    if font then
        cf.editBox:SetFont(font, size, flags)
    end
    
    -- Sync Background Color 1:1 with the ChatFrame
    if chatFrame:GetID() then
        local _, _, r, g, b, a = FCF_GetChatWindowInfo(chatFrame:GetID())
        if r and g and b then
            cf:SetBackdropColor(r, g, b, a or 0.9)
        end
    end
    
    -- Crucial workaround for the WoW Engine's EditBox format tag limit:
    -- Using SetText() with a massive string hits the C++ 100-tag limit instantly.
    -- Using Insert() sequentially forces the Engine to create separate internal string blocks, bypassing the limit entirely!
    cf.editBox:SetText("")
    for i, line in ipairs(lines) do
        if i == 1 then
            cf.editBox:Insert(line)
        else
            cf.editBox:Insert("\n" .. line)
        end
    end
    
    -- Show frame FIRST so internal calculations happen correctly
    cf:Show()
    
    -- EditBoxes don't have GetStringHeight(), so we use a hidden dummy FontString to calculate the exact height needed for the Scrollbar
    if not cf.dummyFS then
        cf.dummyFS = cf:CreateFontString(nil, "BACKGROUND")
        cf.dummyFS:SetWidth(620)
        cf.dummyFS:Hide()
    end
    if font then cf.dummyFS:SetFont(font, size, flags) end
    cf.dummyFS:SetText(table.concat(lines, "\n"))
    
    local textHeight = cf.dummyFS:GetStringHeight()
    if not textHeight or textHeight < 30 then
        textHeight = 30
    end
    cf.editBox:SetHeight(textHeight + 50)
    
    -- Force ScrollFrame to update its boundaries and snap to the bottom!
    cf.scrollFrame:UpdateScrollChildRect()
    cf.scrollFrame:SetVerticalScroll(cf.scrollFrame:GetVerticalScrollRange())
    
    Module:UpdateTabs(chatFrame)
    
    if cf:IsUserPlaced() then
        cf.resetBtn:Show()
    else
        cf.resetBtn:Hide()
    end
    
    cf.editBox:SetFocus()
end

function Module:Initialize()
    if not WT.DB.Modules.Chat or not WT.DB.Chat.ChatCopy then return end
    
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame and chatFrame ~= ChatFrame2 then
            local btn = CreateFrame("Button", nil, chatFrame, "BackdropTemplate")
            btn:SetSize(22, 22)
            btn:SetPoint("TOPRIGHT", chatFrame, "TOPRIGHT", -5, -5)
            
            btn:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            btn:SetBackdropColor(WT.Colors.BG_R, WT.Colors.BG_G, WT.Colors.BG_B, 0.5)
            btn:SetBackdropBorderColor(0, 0, 0, 1)
            
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
            icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
            icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
            
            btn:SetAlpha(0.15)
            icon:SetDesaturated(true)
            icon:SetVertexColor(0.7, 0.7, 0.7)
            
            btn:SetScript("OnEnter", function(self) 
                self:SetAlpha(1)
                self:SetBackdropColor(WT.Colors.BG_R, WT.Colors.BG_G, WT.Colors.BG_B, 0.9)
                self:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 1)
                icon:SetDesaturated(false)
                icon:SetVertexColor(1, 1, 1)
                
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(WT.L.OPT_CHAT_COPY, 1, 1, 1, 1)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self) 
                self:SetAlpha(0.15) 
                self:SetBackdropColor(WT.Colors.BG_R, WT.Colors.BG_G, WT.Colors.BG_B, 0.5)
                self:SetBackdropBorderColor(0, 0, 0, 1)
                icon:SetDesaturated(true)
                icon:SetVertexColor(0.7, 0.7, 0.7)
                GameTooltip:Hide()
            end)
            
            btn:SetScript("OnClick", function()
                Module:ShowCopyFrame(chatFrame)
            end)
        end
    end
end

WT.Core.Events:Register("PLAYER_LOGIN", function()
    C_Timer.After(1, function() Module:Initialize() end)
end)
