local _, WT = ...

WT.Config.Profiles = {}
local Profiles = WT.Config.Profiles

local Unsecret = WT.Utils.Safety.Unsecret

function Profiles:BuildOptions(builder, panel)
    local function AddDescription(text)
        if not text then return end
        local desc = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
        desc:SetWidth(550)
        desc:SetJustifyH("LEFT")
        desc:SetText(text)
        builder:AddSpace(desc:GetStringHeight() + 25)
    end
    
    panel:CreateTitle(builder, WT.L.CATEGORY_PROFILES)
    AddDescription(WT.L.DESC_PROFILES)
    
    local editBoxBg = CreateFrame("Frame", nil, builder.content, "BackdropTemplate")
    editBoxBg:SetSize(540, 150)
    editBoxBg:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
    editBoxBg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    editBoxBg:SetBackdropColor(WT.Colors.STD_BG_R, WT.Colors.STD_BG_G, WT.Colors.STD_BG_B, WT.Colors.STD_BG_A)
    editBoxBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    
    local sf = CreateFrame("ScrollFrame", nil, editBoxBg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -26, 6)
    
    local editBox = CreateFrame("EditBox", nil, sf)
    editBox:SetWidth(500)
    editBox:SetFontObject("GameFontHighlight")
    editBox:SetAutoFocus(false)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(0) -- Allows extremely long Base64 codes
    editBox:EnableMouse(true)
    editBox.wtCursorOffset = 0
    editBox.wtCursorHeight = 0
    editBox:SetScript("OnCursorChanged", function(self, x, y, w, h)
        self.wtCursorOffset = y
        self.wtCursorHeight = h
        self.wtHandleCursorChange = true
    end)
    editBox:SetScript("OnUpdate", function(self, elapsed)
        if self.wtHandleCursorChange then
            self.wtHandleCursorChange = false
            local scrollFrame = self:GetParent()
            if not scrollFrame then return end
            local height = scrollFrame:GetHeight()
            local range = scrollFrame:GetVerticalScrollRange()
            local scroll = scrollFrame:GetVerticalScroll()
            local cursorOffset = -(self.wtCursorOffset or 0)
            local cursorHeight = self.wtCursorHeight or 0
            if math.floor(height) <= 0 or math.floor(range) <= 0 then return end
            if cursorOffset < scroll then
                scrollFrame:SetVerticalScroll(cursorOffset)
            elseif cursorOffset + cursorHeight > scroll + height then
                scrollFrame:SetVerticalScroll(cursorOffset + cursorHeight - height)
            end
        end
    end)
    editBox:SetScript("OnTextChanged", function(self)
        local scrollFrame = self:GetParent()
        if scrollFrame and scrollFrame.UpdateScrollChildRect then scrollFrame:UpdateScrollChildRect() end
    end)
    editBox:SetScript("OnMouseDown", function(self) self:SetFocus() end)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    
    editBoxBg:EnableMouse(true)
    editBoxBg:SetScript("OnMouseDown", function() editBox:SetFocus() end)
    
    editBox:HookScript("OnEditFocusGained", function() editBoxBg:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 1) end)
    editBox:HookScript("OnEditFocusLost", function() editBoxBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8) end)
    editBoxBg:SetScript("OnEnter", function() if not editBox:HasFocus() then editBoxBg:SetBackdropBorderColor(0.6, 0.6, 0.6, 1) end end)
    editBoxBg:SetScript("OnLeave", function() if not editBox:HasFocus() then editBoxBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8) end end)

    sf:SetScrollChild(editBox)
    
    builder:AddSpace(160)
    
    local exportBtn = CreateFrame("Button", nil, builder.content, "UIPanelButtonTemplate")
    exportBtn:SetSize(150, 30)
    exportBtn:SetNormalFontObject("GameFontNormalSmall")
    exportBtn:SetHighlightFontObject("GameFontHighlightSmall")
    exportBtn:SetDisabledFontObject("GameFontDisableSmall")
    exportBtn:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
    exportBtn:SetText(WT.L.BTN_EXPORT)
    WT.Config.Builder:StyleButton(exportBtn)
    
    local importBtn = CreateFrame("Button", nil, builder.content, "UIPanelButtonTemplate")
    importBtn:SetSize(150, 30)
    importBtn:SetNormalFontObject("GameFontNormalSmall")
    importBtn:SetHighlightFontObject("GameFontHighlightSmall")
    importBtn:SetDisabledFontObject("GameFontDisableSmall")
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 15, 0)
    importBtn:SetText(WT.L.BTN_IMPORT)
    WT.Config.Builder:StyleButton(importBtn)
    
    exportBtn:SetScript("OnClick", function()
        local code = WT.Utils.DataTransfer:ExportProfile(WT.DB)
        editBox:SetText(code)
        editBox:HighlightText()
        editBox:SetFocus()
        if WT.Utils.Logger then WT.Utils.Logger:Print(WT.L.MSG_EXPORT_SUCCESS) end
    end)
    
    importBtn:SetScript("OnClick", function()
        local code = Unsecret(editBox:GetText())
        local success = WT.Utils.DataTransfer:ImportProfile(code, WT.DB)
        if success then
            if WT.Utils.Logger then WT.Utils.Logger:Print(WT.L.MSG_IMPORT_SUCCESS) end
            ReloadUI()
        else
            if WT.Utils.Logger then WT.Utils.Logger:Warn(WT.L.MSG_IMPORT_ERROR) end
        end
    end)
    
    builder:AddSpace(35)
    builder:UpdateHeight()
end