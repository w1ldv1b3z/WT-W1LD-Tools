local _, WT = ...

local unpack = unpack or rawget(table, "unpack")

WT.Config.Builder = {}
local Builder = WT.Config.Builder

Builder.Registry = { Checkboxes = {}, Sliders = {}, Dropdowns = {}, EditBoxes = {}, ColorPickers = {} }

-- Every nesting level (option -> sub option -> sub sub option) is indented by this many pixels
local INDENT_STEP = 30

--- Nesting depth of a widget created below parentWidget (0 = top level).
---@param parentWidget table|nil
---@return number
function Builder:GetDepth(parentWidget)
    if not parentWidget then return 0 end
    return (parentWidget.wtDepth or 0) + 1
end

-- ==============================================================
-- CUSTOM CANVAS BUILDER (Masque-like hybrid approach)
-- ==============================================================

local Unsecret = WT.Utils.Safety.Unsecret

local function SafeSetGradient(tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    C_Timer.After(0, function()
        if tex and tex.SetGradient then
            tex:SetGradient(orientation, {r=r1, g=g1, b=b1, a=a1}, {r=r2, g=g2, b=b2, a=a2})
        elseif tex and tex.SetGradientAlpha then
            tex:SetGradientAlpha(orientation, r1, g1, b1, a1, r2, g2, b2, a2)
        end
    end)
end

local function ParseColor(c)
    if type(c) == "table" then return c end
    if type(c) == "string" then
        local hex = string.gsub(c, "^#", "")
        if #hex == 8 then
            return {
                a = (tonumber(string.sub(hex, 1, 2), 16) or 255) / 255,
                r = (tonumber(string.sub(hex, 3, 4), 16) or 255) / 255,
                g = (tonumber(string.sub(hex, 5, 6), 16) or 255) / 255,
                b = (tonumber(string.sub(hex, 7, 8), 16) or 255) / 255
            }
        elseif #hex >= 6 then
            return {
                a = 1,
                r = (tonumber(string.sub(hex, 1, 2), 16) or 255) / 255,
                g = (tonumber(string.sub(hex, 3, 4), 16) or 255) / 255,
                b = (tonumber(string.sub(hex, 5, 6), 16) or 255) / 255
            }
        end
    end
    return {r=1, g=1, b=1, a=1}
end

function Builder:AddTooltip(frame, title, text)
    if not title and not text then return end
    
    local function ShowTooltip(self)
        local tt = _G["WTCustomTooltip"]
        if not tt then
            tt = CreateFrame("GameTooltip", "WTCustomTooltip", _G["WT_UIContainer"] or UIParent, "GameTooltipTemplate")
            tt.ignoreInLayout = true
            tt.ignoreFramePositionManager = true
            if tt.SetIsFramePositionManaged then pcall(function() tt:SetIsFramePositionManaged(false) end) end
        end
        if tt:IsForbidden() then return end
        tt:SetOwner(self, "ANCHOR_TOPLEFT", 16, 0)
        
        if title and title ~= "" then
            tt:AddLine(title, 1, 0.82, 0, true) -- WoW Gold for the title
        end
        
        if text and text ~= "" then
            tt:AddLine(text, 1, 1, 1, true) -- White with text wrap for the description
        end
        
        -- Appends dynamic additional information to the end of the tooltip
        if frame.wtTooltipAppender then
            local extraText = frame.wtTooltipAppender()
            if extraText and extraText ~= "" then
                tt:AddLine(" ")
                tt:AddLine(extraText, 1, 1, 1, true)
            end
        end
        
        tt:Show()
    end
    
    frame.wtShowTooltip = ShowTooltip
    local function HideTooltip() if _G["WTCustomTooltip"] then _G["WTCustomTooltip"]:Hide() end end
    
    if frame.HookScript then
        frame:HookScript("OnEnter", ShowTooltip)
        frame:HookScript("OnLeave", HideTooltip)
        frame:HookScript("OnHide", HideTooltip)
    else
        frame:SetScript("OnEnter", ShowTooltip)
        frame:SetScript("OnLeave", HideTooltip)
        frame:SetScript("OnHide", HideTooltip)
    end
end

function Builder:SetElementsState(enabled, ...)
    for i = 1, select("#", ...) do
        local el = select(i, ...)
        if type(el) == "table" and not el.wtIsFlavorDisabled then
            if el.SetEnabled then el:SetEnabled(enabled) end
            if el.EnableMouse then el:EnableMouse(enabled) end
                if el.GetObjectType then
                    local oType = el:GetObjectType()
                    if oType == "EditBox" and not enabled then 
                        el:ClearFocus() 
                    end
                end
            if type(el.SetAlpha) == "function" then el:SetAlpha(enabled and 1.0 or 0.4) end
            if el.Color and type(el.Color.SetVertexColor) == "function" then
                local r, g, b = el.Color:GetVertexColor()
                el.Color:SetVertexColor(r or 1, g or 1, b or 1, enabled and 1.0 or 0.4)
            end
        end
    end
end

function Builder:StyleSlider(slider)
    local thumb = slider:GetThumbTexture()
    if thumb then
        -- Colorize thumb
        thumb:SetVertexColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B)
        
        -- Glowing progress bar left of the thumb
        local fill = slider:CreateTexture(nil, "ARTWORK", nil, -1)
        fill:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        fill:SetVertexColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.4)
        fill:SetPoint("LEFT", slider, "LEFT", 5, 0)
        fill:SetPoint("RIGHT", thumb, "CENTER", 0, 0)
        fill:SetHeight(4)
        fill:SetBlendMode("ADD")
    end
end

function Builder:StyleCheckbox(cb)
    local chk = cb:GetCheckedTexture()
    if chk then
        chk:SetDesaturated(true)
        chk:SetVertexColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B)
        chk:SetBlendMode("ADD")
    end
    local hl = cb:GetHighlightTexture()
    if hl then
        hl:SetDesaturated(true)
        hl:SetVertexColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.25)
        hl:SetBlendMode("ADD")
    end
end

function Builder:StyleDropdown(dd)
    local hl = dd:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    hl:SetVertexColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.1)
    hl:SetPoint("TOPLEFT", dd, "TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", -3, 3)
    hl:SetBlendMode("ADD")
    
    local glow = dd:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    glow:SetVertexColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.2)
    glow:SetPoint("TOPLEFT", dd, "TOPLEFT", 3, -3)
    glow:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", -3, 3)
    glow:SetBlendMode("ADD")
    glow:Hide()
    
    dd:HookScript("OnMouseDown", function() glow:Show() end)
    dd:HookScript("OnMouseUp", function() glow:Hide() end)
    dd:HookScript("OnHide", function() glow:Hide() end)
    
    local textObj = dd.Text or dd.ButtonText or (dd.GetFontString and dd:GetFontString())
    if textObj then
        textObj:SetTextColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B)
        hooksecurefunc(textObj, "SetTextColor", function(self, r, g, b)
            if self.wtLockColor then return end
            self.wtLockColor = true
            self:SetTextColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B)
            self.wtLockColor = false
        end)
    end
end

function Builder:StyleButton(btn)
    if not btn then return end
    
    if btn.GetNormalTexture and btn:GetNormalTexture() then btn:GetNormalTexture():SetAlpha(0) end
    if btn.GetPushedTexture and btn:GetPushedTexture() then btn:GetPushedTexture():SetAlpha(0) end
    if btn.GetDisabledTexture and btn:GetDisabledTexture() then btn:GetDisabledTexture():SetAlpha(0) end
    
    if btn.Left then btn.Left:SetAlpha(0) end
    if btn.Middle then btn.Middle:SetAlpha(0) end
    if btn.Right then btn.Right:SetAlpha(0) end
    if btn.NineSlice then btn.NineSlice:SetAlpha(0) end
    
    local regions = {btn:GetRegions()}
    for _, r in ipairs(regions) do
        local rName = Unsecret(r:GetName())
        if r:GetObjectType() == "Texture" and rName and (string.find(rName, "Left") or string.find(rName, "Middle") or string.find(rName, "Right")) then
            r:SetAlpha(0)
        end
    end
    
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    SafeSetGradient(bg, "VERTICAL", 0.05, 0.05, 0.05, 0.8, 0.15, 0.15, 0.15, 0.8)
    
    local edgeR, edgeG, edgeB, edgeA = 0.3, 0.3, 0.3, 0.8
    local t = btn:CreateTexture(nil, "BORDER")
    t:SetPoint("TOPLEFT", 0, 0); t:SetPoint("TOPRIGHT", 0, 0); t:SetHeight(1)
    t:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); t:SetVertexColor(edgeR, edgeG, edgeB, edgeA)
    local b = btn:CreateTexture(nil, "BORDER")
    b:SetPoint("BOTTOMLEFT", 0, 0); b:SetPoint("BOTTOMRIGHT", 0, 0); b:SetHeight(1)
    b:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); b:SetVertexColor(edgeR, edgeG, edgeB, edgeA)
    local l = btn:CreateTexture(nil, "BORDER")
    l:SetPoint("TOPLEFT", 0, 0); l:SetPoint("BOTTOMLEFT", 0, 0); l:SetWidth(1)
    l:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); l:SetVertexColor(edgeR, edgeG, edgeB, edgeA)
    local r = btn:CreateTexture(nil, "BORDER")
    r:SetPoint("TOPRIGHT", 0, 0); r:SetPoint("BOTTOMRIGHT", 0, 0); r:SetWidth(1)
    r:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); r:SetVertexColor(edgeR, edgeG, edgeB, edgeA)
    
    local function SetBorderColor(cr, cg, cb, ca)
        t:SetVertexColor(cr, cg, cb, ca); b:SetVertexColor(cr, cg, cb, ca)
        l:SetVertexColor(cr, cg, cb, ca); r:SetVertexColor(cr, cg, cb, ca)
    end
    
    local hl = btn:GetHighlightTexture()
    if hl then
        hl:SetColorTexture(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.2)
        hl:SetBlendMode("ADD")
        hl:ClearAllPoints()
        hl:SetPoint("TOPLEFT", 1, -1)
        hl:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    
    local lastState = "NONE"
    
    local function TriggerUpdate()
        local newState = "NORMAL"
        if not btn:IsEnabled() then newState = "DISABLED"
        elseif btn:GetButtonState() == "PUSHED" then newState = "PUSHED"
        elseif btn:IsMouseOver() then newState = "HOVER" end
        
        if lastState ~= newState then
            lastState = newState
            if newState == "DISABLED" then
                SetBorderColor(0.15, 0.15, 0.15, 0.8)
                SafeSetGradient(bg, "VERTICAL", 0.02, 0.02, 0.02, 0.8, 0.05, 0.05, 0.05, 0.8)
            elseif newState == "PUSHED" then
                SetBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 1)
                SafeSetGradient(bg, "VERTICAL", WT.Colors.PRIMARY_R*0.2, WT.Colors.PRIMARY_G*0.2, WT.Colors.PRIMARY_B*0.2, 0.9, WT.Colors.PRIMARY_R*0.4, WT.Colors.PRIMARY_G*0.4, WT.Colors.PRIMARY_B*0.4, 0.9)
            elseif newState == "HOVER" then
                SetBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.8)
                SafeSetGradient(bg, "VERTICAL", WT.Colors.PRIMARY_R*0.1, WT.Colors.PRIMARY_G*0.1, WT.Colors.PRIMARY_B*0.1, 0.8, WT.Colors.PRIMARY_R*0.25, WT.Colors.PRIMARY_G*0.25, WT.Colors.PRIMARY_B*0.25, 0.8)
            else
                SetBorderColor(0.3, 0.3, 0.3, 0.8)
                SafeSetGradient(bg, "VERTICAL", 0.05, 0.05, 0.05, 0.8, 0.15, 0.15, 0.15, 0.8)
            end
        end
    end
    
    btn:HookScript("OnEnter", TriggerUpdate)
    btn:HookScript("OnLeave", TriggerUpdate)
    btn:HookScript("OnMouseDown", TriggerUpdate)
    btn:HookScript("OnMouseUp", TriggerUpdate)
    btn:HookScript("OnShow", function() lastState = "NONE"; TriggerUpdate() end)
    btn:HookScript("OnHide", function() lastState = "NONE"; TriggerUpdate() end)
    btn:HookScript("OnEnable", function() lastState = "NONE"; TriggerUpdate() end)
    btn:HookScript("OnDisable", function() lastState = "NONE"; TriggerUpdate() end)
    
    TriggerUpdate()
end

function Builder:StyleEditBox(eb)
    if eb.Left then eb.Left:SetAlpha(0) end
    if eb.Middle then eb.Middle:SetAlpha(0) end
    if eb.Right then eb.Right:SetAlpha(0) end
    if eb.NineSlice then eb.NineSlice:SetAlpha(0) end
    local regions = {eb:GetRegions()}
    for _, r in ipairs(regions) do
        local rName = Unsecret(r:GetName())
        if r:GetObjectType() == "Texture" and rName and (string.find(rName, "Left") or string.find(rName, "Middle") or string.find(rName, "Right") or string.find(rName, "FocusGlow")) then r:SetAlpha(0) end
    end
    
    local bgFrame = CreateFrame("Frame", nil, eb:GetParent())
    bgFrame:SetFrameStrata(eb:GetFrameStrata())
    bgFrame:SetFrameLevel(math.max(0, eb:GetFrameLevel() - 1))
    bgFrame:SetAllPoints(eb)
    if not eb:IsShown() then bgFrame:Hide() end
    
    eb:HookScript("OnShow", function() bgFrame:Show() end)
    eb:HookScript("OnHide", function() bgFrame:Hide() end)
    
    local bg = bgFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -5, -2); bg:SetPoint("BOTTOMRIGHT", 5, 2)
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); bg:SetVertexColor(0, 0, 0, 0.5)
    
    local edgeR, edgeG, edgeB, edgeA = 0.3, 0.3, 0.3, 0.8
    local t = bgFrame:CreateTexture(nil, "BORDER")
    t:SetPoint("TOPLEFT", -5, -2); t:SetPoint("TOPRIGHT", 5, -2); t:SetHeight(1)
    t:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); t:SetVertexColor(edgeR, edgeG, edgeB, edgeA)
    local b = bgFrame:CreateTexture(nil, "BORDER")
    b:SetPoint("BOTTOMLEFT", -5, 2); b:SetPoint("BOTTOMRIGHT", 5, 2); b:SetHeight(1)
    b:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); b:SetVertexColor(edgeR, edgeG, edgeB, edgeA)
    local l = bgFrame:CreateTexture(nil, "BORDER")
    l:SetPoint("TOPLEFT", -5, -2); l:SetPoint("BOTTOMLEFT", -5, 2); l:SetWidth(1)
    l:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); l:SetVertexColor(edgeR, edgeG, edgeB, edgeA)
    local r = bgFrame:CreateTexture(nil, "BORDER")
    r:SetPoint("TOPRIGHT", 5, -2); r:SetPoint("BOTTOMRIGHT", 5, 2); r:SetWidth(1)
    r:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); r:SetVertexColor(edgeR, edgeG, edgeB, edgeA)
    
    local function SetBorderColor(cr, cg, cb, ca)
        t:SetVertexColor(cr, cg, cb, ca); b:SetVertexColor(cr, cg, cb, ca)
        l:SetVertexColor(cr, cg, cb, ca); r:SetVertexColor(cr, cg, cb, ca)
    end

    eb:HookScript("OnEditFocusGained", function() SetBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 1); bg:SetVertexColor(0.1, 0.1, 0.1, 0.8) end)
    eb:HookScript("OnEditFocusLost", function() SetBorderColor(0.3, 0.3, 0.3, 0.8); bg:SetVertexColor(0, 0, 0, 0.5) end)
    eb:HookScript("OnEnter", function() if not eb:HasFocus() then SetBorderColor(0.6, 0.6, 0.6, 1) end end)
    eb:HookScript("OnLeave", function() if not eb:HasFocus() then SetBorderColor(0.3, 0.3, 0.3, 0.8) end end)
end

function Builder:RegisterParent(parent, ...)
    if not parent then return end
    if not parent.wtChildren then
        parent.wtChildren = {}
        if parent:GetObjectType() == "CheckButton" then
            parent:HookScript("OnClick", function(self)
                        local isEnabled = self:GetChecked() and (self:IsEnabled() ~= false)
                        WT.Config.Builder:SetElementsState(isEnabled, unpack(self.wtChildren))
            end)
            hooksecurefunc(parent, "SetChecked", function(self, checked)
                        local isEnabled = checked and (self:IsEnabled() ~= false)
                        WT.Config.Builder:SetElementsState(isEnabled, unpack(self.wtChildren))
                    end)
                    hooksecurefunc(parent, "SetEnabled", function(self, enabled)
                        local isEnabled = enabled and self:GetChecked()
                        WT.Config.Builder:SetElementsState(isEnabled, unpack(self.wtChildren))
            end)
        end
    end
    for i = 1, select("#", ...) do
        local el = select(i, ...)
        if el then table.insert(parent.wtChildren, el) end
    end
    local isEnabled = true
            if parent:GetObjectType() == "CheckButton" then isEnabled = parent:GetChecked() and (parent:IsEnabled() ~= false) end
    self:SetElementsState(isEnabled, ...)
end

function Builder:SetFlavor(widget, flavor, customNote)
    if not widget or not flavor then return widget end

    local isForever = WT.Compat and WT.Compat.IsForever
    local isRetail = WT.Compat and WT.Compat.IsRetail

    local isApplicable = true
    local tag = ""
    local note = ""

    if flavor == "RETAIL" then
        if not isRetail then
            isApplicable = false
            tag = WT.L.FLAVOR_TAG_RETAIL
            note = customNote or WT.L.FLAVOR_NOTE_RETAIL
        end
    elseif flavor == "FOREVER" then
        if not isForever then
            isApplicable = false
            tag = WT.L.FLAVOR_TAG_FOREVER
            note = customNote or WT.L.FLAVOR_NOTE_FOREVER
        end
    end

    if not isApplicable then
        widget.wtIsFlavorDisabled = true

        local labelObj = widget.Text or widget.wtLabel or (widget.GetFontString and widget:GetFontString())
        if labelObj and labelObj.GetText and labelObj.SetText then
            local currentText = labelObj:GetText() or ""
            if not string.find(currentText, "%[") then
                labelObj:SetText(currentText .. "|cFF888888" .. tag .. "|r")
            end
            if labelObj.SetTextColor then
                labelObj:SetTextColor(0.55, 0.55, 0.55)
            end
        end

        if widget.Disable then widget:Disable() end
        if type(widget.SetAlpha) == "function" then widget:SetAlpha(0.45) end

        if widget.GetObjectType and widget:GetObjectType() == "CheckButton" then
            widget:HookScript("OnClick", function(self)
                if self.wtIsFlavorDisabled then
                    self:SetChecked(false)
                end
            end)
        end

        if widget.wtChildren then
            for _, child in ipairs(widget.wtChildren) do
                if type(child) == "table" then
                    child.wtIsFlavorDisabled = true
                end
            end
            self:SetElementsState(false, unpack(widget.wtChildren))
        end

        local origAppender = widget.wtTooltipAppender
        widget.wtTooltipAppender = function()
            local prev = origAppender and origAppender() or ""
            local hint = "|cFFFFCC00" .. (WT.L.LBL_NOTE) .. "|r " .. note
            if prev ~= "" then
                return prev .. "\n\n" .. hint
            else
                return hint
            end
        end
    end

    return widget
end

function Builder:CreateCategory(rootCategory, titleText)
    local canvas = CreateFrame("Frame")
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)
    
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    
    scrollFrame:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(width)
    end)

    local category
    if rootCategory then
        category = Settings.RegisterCanvasLayoutSubcategory(rootCategory, canvas, titleText)
    else
        category = Settings.RegisterCanvasLayoutCategory(canvas, titleText)
    end
    self.LastCreatedCategory = category

    local builder = {
        content = content,
        scrollFrame = scrollFrame,
        category = category,
        name = titleText,
        cursorY = -15,
        lastTitle = nil,
        lastSubTitle = nil,
        AddSpace = function(self, amount) self.cursorY = self.cursorY - amount end,
        UpdateHeight = function(self) self.content:SetHeight(math.abs(self.cursorY) + 20) end
    }
    return builder
end

function Builder:IndexOption(labelText, dbCategory, targetCategory, builder, isTitle, isSubTitle)
    if not labelText or labelText == "" or not dbCategory then return end
    self.SearchIndex = self.SearchIndex or {}
    local entry = { 
        label = labelText, 
        module = dbCategory, 
        targetCategory = targetCategory, 
        builder = builder, 
        title = (not isTitle) and builder and builder.lastTitle or nil, 
        subTitle = (not isTitle and not isSubTitle) and builder and builder.lastSubTitle or nil 
    }
    table.insert(self.SearchIndex, entry)
    return entry
end

function Builder:ShowHighlight(widget)
    if not widget then return end
    if not self.highlightFrame then
        local hl = CreateFrame("Frame", nil, _G["WT_UIContainer"])
            hl.ignoreInLayout = true
            hl.ignoreFramePositionManager = true
            if hl.SetIsFramePositionManaged then pcall(function() hl:SetIsFramePositionManaged(false) end) end
        hl:SetFrameStrata("TOOLTIP")
        hl:SetFrameLevel(9999)
        
        local glow = hl:CreateTexture(nil, "OVERLAY")
        glow:SetTexture("Interface\\QUESTFRAME\\UI-QuestLogTitleHighlight")
        glow:SetVertexColor(1, 0.82, 0, 0.4)
        glow:SetBlendMode("ADD")
        hl.glow = glow
        
        local fs = hl:CreateFontString(nil, "OVERLAY")
        fs:SetTextColor(1, 0.82, 0)
        hl.fs = fs
        
        local ag = hl:CreateAnimationGroup()
        local a1 = ag:CreateAnimation("Alpha")
        a1:SetOrder(1); a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.2); a1:SetSmoothing("OUT")
        local a2 = ag:CreateAnimation("Alpha")
        a2:SetOrder(2); a2:SetFromAlpha(1); a2:SetToAlpha(0.2); a2:SetDuration(0.3); a2:SetSmoothing("IN_OUT")
        local a3 = ag:CreateAnimation("Alpha")
        a3:SetOrder(3); a3:SetFromAlpha(0.2); a3:SetToAlpha(1); a3:SetDuration(0.3); a3:SetSmoothing("IN_OUT")
        local a4 = ag:CreateAnimation("Alpha")
        a4:SetOrder(4); a4:SetFromAlpha(1); a4:SetToAlpha(0); a4:SetDuration(1.0); a4:SetSmoothing("IN")
        ag:SetScript("OnFinished", function() hl:Hide() end)
        hl.ag = ag; self.highlightFrame = hl
    end
    
    local hl = self.highlightFrame
    if widget:GetObjectType() == "FontString" then
        hl:SetParent(widget:GetParent() or UIParent)
        hl:ClearAllPoints()
        hl:SetAllPoints(widget)
        
        local f, s, o = widget:GetFont()
        hl.fs:SetFont(f, s, o)
        hl.fs:SetJustifyH(widget:GetJustifyH())
        hl.fs:SetJustifyV(widget:GetJustifyV())
        hl.fs:SetText(widget:GetText())
        hl.fs:Show()
        
        hl.fs:ClearAllPoints()
        hl.fs:SetAllPoints(widget)
        
        hl.glow:ClearAllPoints()
        hl.glow:SetPoint("TOPLEFT", widget, "TOPLEFT", -25, 8)
        hl.glow:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 25, -8)
        hl.glow:Show()
    else
        hl:SetParent(widget)
        hl:ClearAllPoints()
        hl:SetAllPoints(widget)
        hl.fs:Hide()
        
        hl.glow:ClearAllPoints()
        hl.glow:SetPoint("TOPLEFT", widget, "TOPLEFT", -15, 12)
        hl.glow:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 15, -12)
        hl.glow:Show()
    end
    
    hl:Show()
    hl.ag:Stop()
    hl.ag:Play()
end

function Builder:CreateTitle(builder, titleText)
    if builder.cursorY < -20 then builder:AddSpace(15) end
    
    builder.lastTitle = titleText
    builder.lastSubTitle = nil
    
    local title = builder.content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
    title:SetText(titleText)
    title:SetTextColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B)
    
    local searchEntry = self:IndexOption(titleText, builder.moduleName or builder.name or "Category", builder.category, builder, true, false)
    if searchEntry then searchEntry.textObj = title; searchEntry.yPos = builder.cursorY end

    local divider = builder.content:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    SafeSetGradient(divider, "HORIZONTAL", WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.5, WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0)
    divider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -4)
    divider:SetSize(540, 2)
    divider:SetBlendMode("ADD")
    
    builder:AddSpace(30)
    return title
end

function Builder:CreateSubTitle(builder, titleText)
    if builder.cursorY < -65 then builder:AddSpace(15) end
    
    builder.lastSubTitle = titleText
    
    local title = builder.content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
    title:SetText(titleText)
    title:SetTextColor(1, 1, 1)
    
    local searchEntry = self:IndexOption(titleText, builder.moduleName or builder.name or "Category", builder.category, builder, false, true)
    if searchEntry then searchEntry.textObj = title; searchEntry.yPos = builder.cursorY end

    local divider = builder.content:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    SafeSetGradient(divider, "HORIZONTAL", 1, 1, 1, 0.2, 1, 1, 1, 0)
    divider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -4)
    divider:SetSize(400, 2)
    divider:SetBlendMode("ADD")
    
    builder:AddSpace(22)
    return title
end

function Builder:CreateModuleToggle(builder, labelText, tooltipText, dbKey, iconTexture, isRightColumn)
    local yPos = isRightColumn and (builder.cursorY + 38) or builder.cursorY
    local searchEntry = self:IndexOption(labelText, "Modules", builder.category, builder)

    local bg = CreateFrame("Button", nil, builder.content, "BackdropTemplate")
    local xOffset = isRightColumn and 285 or 25
    bg:SetPoint("TOPLEFT", builder.content, "TOPLEFT", xOffset, yPos + 6)
    bg:SetSize(250, 34)
    bg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    
    local cb = CreateFrame("CheckButton", nil, bg, "ChatConfigCheckButtonTemplate")
    cb:SetPoint("LEFT", bg, "LEFT", 4, 0)
    cb:EnableMouse(false)
    self:StyleCheckbox(cb)
    
    local icon
    if iconTexture then
        icon = bg:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        icon:SetTexture(iconTexture)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- Crops the default borders of WoW icons
        
        cb.Text:ClearAllPoints()
        cb.Text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    end
    
    cb.Text:SetText(labelText)
    cb.Text:SetFontObject("GameFontHighlight")
    
    cb.Text:SetWidth(160)
    cb.Text:SetWordWrap(false)
    
    if searchEntry then searchEntry.widget = bg; searchEntry.yPos = yPos; searchEntry.textObj = cb.Text end

    cb:SetChecked(WT.DB.Modules[dbKey])
    self:AddTooltip(bg, labelText, tooltipText)
    
    local cfgBtn = CreateFrame("Button", nil, bg)
    cfgBtn:SetSize(16, 16)
    cfgBtn:SetPoint("RIGHT", bg, "RIGHT", -8, 0)
    cfgBtn:SetFrameLevel(cb:GetFrameLevel() + 2)
    cfgBtn:SetHitRectInsets(-6, -6, -6, -6)
    cfgBtn:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    cfgBtn:SetHighlightTexture("Interface\\Buttons\\UI-OptionsButton")
    cfgBtn:GetHighlightTexture():SetBlendMode("ADD")
    self:AddTooltip(cfgBtn, WT.L.BTN_CONFIGURE, WT.L.TT_CONFIGURE_DESC)
    
    cfgBtn:SetScript("OnClick", function()
        local function OpenSub()
            local targetCat = (WT.Config.OptionsPanel and WT.Config.OptionsPanel.ModuleToCategory) and WT.Config.OptionsPanel.ModuleToCategory[dbKey] or dbKey
            if WT.Config.OptionsPanel and WT.Config.OptionsPanel.SubCategories and WT.Config.OptionsPanel.SubCategories[targetCat] then
                Settings.OpenToCategory(WT.Config.OptionsPanel.SubCategories[targetCat]:GetID())
            end
        end
        if WT.Core.CombatQueue:Add("OpenOptions", true, OpenSub) then
            if WT.Utils and WT.Utils.Logger then WT.Utils.Logger:Warn(WT.L.MSG_OPTIONS_QUEUED) end
            return
        end
        OpenSub()
    end)
    
    local function UpdateBg(isHovered)
        local isChecked = cb:GetChecked()
        if icon then icon:SetDesaturated(not isChecked) end
        cfgBtn:SetShown(isChecked)
        
        if isChecked then
            cb.Text:SetTextColor(1, 1, 1)
        else
            cb.Text:SetTextColor(0.4, 0.4, 0.4)
        end
        
        if isHovered then
            bg:SetBackdropColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.1); bg:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.8)
            if icon and not isChecked then icon:SetDesaturated(false) end
            if not isChecked then cb.Text:SetTextColor(0.8, 0.8, 0.8) end
        else
            bg:SetBackdropColor(WT.Colors.BG_R, WT.Colors.BG_G, WT.Colors.BG_B, WT.Colors.BG_A)
            if isChecked then bg:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.5) else bg:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.7) end
        end
    end
    
    bg:HookScript("OnEnter", function() UpdateBg(true) end)
    bg:HookScript("OnLeave", function() if not cfgBtn:IsMouseOver() then UpdateBg(false) end end)
    bg:HookScript("OnHide", function() UpdateBg(false) end)
    
    cfgBtn:HookScript("OnEnter", function() UpdateBg(true) end)
    cfgBtn:HookScript("OnLeave", function() if not bg:IsMouseOver() then UpdateBg(false) end end)
    cfgBtn:HookScript("OnHide", function() UpdateBg(false) end)
    
    bg:RegisterForClicks("LeftButtonUp")
    bg:SetScript("OnClick", function()
        cb:SetChecked(not cb:GetChecked())
        WT.DB.Modules[dbKey] = cb:GetChecked()
        -- WT-internal event, payload: module key, new state
        WT.Core.Events:Fire("WT_MODULE_TOGGLED", dbKey, WT.DB.Modules[dbKey])
        UpdateBg(bg:IsMouseOver() or cfgBtn:IsMouseOver())
        if WT.Config.OptionsPanel and WT.Config.OptionsPanel.ShowReloadPrompt then
            WT.Config.OptionsPanel:ShowReloadPrompt()
        end
    end)
    UpdateBg(false)
    
    if not isRightColumn then
        builder:AddSpace(38)
    end
    self.Registry.Checkboxes["Modules"] = self.Registry.Checkboxes["Modules"] or {}
    self.Registry.Checkboxes["Modules"][dbKey] = cb
    return cb
end

function Builder:CreateCheckbox(builder, labelText, tooltipText, dbCategory, dbKey, callback, parentWidget)
    if type(callback) == "table" and not parentWidget then
        parentWidget = callback
        callback = nil
    end

    local searchEntry = self:IndexOption(labelText, dbCategory, builder.category, builder)
    local cb = CreateFrame("CheckButton", nil, builder.content, "ChatConfigCheckButtonTemplate")
    -- 12/42 instead of 16/46 to compensate for 4px invisible texture padding on the left
    local depth = self:GetDepth(parentWidget)
    local indent = 12 + depth * INDENT_STEP
    cb.wtIndent = indent
    cb.wtDepth = depth
    cb:SetPoint("TOPLEFT", builder.content, "TOPLEFT", indent, builder.cursorY)
    if searchEntry then searchEntry.widget = cb; searchEntry.yPos = builder.cursorY; searchEntry.textObj = cb.Text end
    self:StyleCheckbox(cb)
    cb.Text:SetText(labelText)
    
    local textWidth = cb.Text:GetStringWidth()
    cb.Text:SetWidth(textWidth + 20)
    cb:SetHitRectInsets(0, -math.floor(textWidth + 15), 0, 0)
    
    cb:SetChecked(WT.DB[dbCategory][dbKey])
    self:AddTooltip(cb, labelText, tooltipText)
    cb:SetScript("OnClick", function(self)
        WT.DB[dbCategory][dbKey] = self:GetChecked()
        if type(callback) == "function" then callback(self:GetChecked()) end
    end)
    builder:AddSpace(26)
    self.Registry.Checkboxes[dbCategory] = self.Registry.Checkboxes[dbCategory] or {}
    self.Registry.Checkboxes[dbCategory][dbKey] = cb
    if parentWidget then self:RegisterParent(parentWidget, cb, cb.Text) end
    return cb
end

function Builder:CreateColorPicker(builder, labelText, tooltipText, dbCategory, dbKey, hasAlpha, parentWidget, callback, isIndented)
    local searchEntry = self:IndexOption(labelText, dbCategory, builder.category, builder)
    local btn = CreateFrame("Button", nil, builder.content, "ColorSwatchTemplate")
    btn:SetSize(22, 22)
    btn:SetFrameLevel(builder.content:GetFrameLevel() + 10)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if searchEntry then searchEntry.widget = btn; searchEntry.yPos = builder.cursorY end
    
    if not btn.Color then
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.2, 0.2, 0.2, 1)
        btn.Color = btn:CreateTexture(nil, "ARTWORK")
        btn.Color:SetPoint("TOPLEFT", 1, -1)
        btn.Color:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    

    local function UpdateTex()
        local col = ParseColor(WT.DB[dbCategory][dbKey] or WT.Config.Defaults[dbCategory][dbKey])
        if btn.Color.SetVertexColor then
            btn.Color:SetVertexColor(col.r, col.g, col.b, hasAlpha and col.a or 1)
        elseif btn.Color.SetColorTexture then
            btn.Color:SetColorTexture(col.r, col.g, col.b, hasAlpha and col.a or 1)
        end
    end

    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            WT.DB[dbCategory][dbKey] = nil
            UpdateTex()
            if callback then callback() end
            return
        end
        
        local col = ParseColor(WT.DB[dbCategory][dbKey] or WT.Config.Defaults[dbCategory][dbKey])
        local info = {
            r = col.r, g = col.g, b = col.b, opacity = col.a, hasOpacity = hasAlpha,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = ColorPickerFrame:GetColorAlpha() or 1
                WT.DB[dbCategory][dbKey] = {r=r, g=g, b=b, a=a}
                UpdateTex()
                if callback then callback() end
            end,
            cancelFunc = function()
                WT.DB[dbCategory][dbKey] = col
                UpdateTex()
                if callback then callback() end
            end
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)
    
    local fullTooltip = (tooltipText and tooltipText ~= "" and tooltipText .. "\n\n" or "") .. "|cFF00FF00" .. (WT.L.COLOR_CHANGE) .. "|r\n|cFFFF0000" .. (WT.L.COLOR_RESET) .. "|r"
    self:AddTooltip(btn, labelText, fullTooltip)
    UpdateTex()

    local txt
    if parentWidget and not isIndented then
        if not parentWidget.swatchCount then parentWidget.swatchCount = 0 end
        local offsetX
        if parentWidget:GetObjectType() == "EditBox" then
            offsetX = parentWidget:GetWidth() + 25 + (parentWidget.swatchCount * 30)
        else
            local parentX = parentWidget.wtIndent or 12
            offsetX = 280 - parentX + (parentWidget.swatchCount * 30)
        end
        btn:SetPoint("LEFT", parentWidget, "LEFT", offsetX, 0)
        parentWidget.swatchCount = parentWidget.swatchCount + 1
    else
        local indent = 16 + (isIndented and math.max(1, self:GetDepth(parentWidget)) or 0) * INDENT_STEP
        txt = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        txt:SetPoint("LEFT", builder.content, "TOPLEFT", indent, builder.cursorY - 12)
        txt:SetText(labelText)
        if searchEntry then searchEntry.textObj = txt end
        btn:SetPoint("LEFT", builder.content, "TOPLEFT", 280, builder.cursorY - 12)
        builder:AddSpace(26)
    end
    self.Registry.ColorPickers[dbCategory] = self.Registry.ColorPickers[dbCategory] or {}
    self.Registry.ColorPickers[dbCategory][dbKey] = btn
    if parentWidget then 
        if isIndented then
            self:RegisterParent(parentWidget, btn, txt)
        else
            self:RegisterParent(parentWidget, btn)
        end
    end
    return btn
end

function Builder:CreateScaleFadeRow(builder, labelText, tooltipText, dbCategory, dbScale, dbFade, defaultScale, callback)
    local searchEntry = self:IndexOption(labelText, dbCategory, builder.category, builder)
    builder.rowCount = (builder.rowCount or 0) + 1
    local isEven = (builder.rowCount % 2 == 0)
    
    if isEven then
        local bg = builder.content:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 14, builder.cursorY + 4)
        bg:SetSize(560, 28)
        bg:SetColorTexture(1, 1, 1, 0.03)
    end
    
    local lbl = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lbl:SetPoint("LEFT", builder.content, "TOPLEFT", 16, builder.cursorY - 12)
    lbl:SetText(labelText)
    lbl:SetWidth(165)
    lbl:SetJustifyH("LEFT")

    local cb = CreateFrame("CheckButton", nil, builder.content, "ChatConfigCheckButtonTemplate")
    cb:SetPoint("LEFT", builder.content, "TOPLEFT", 190, builder.cursorY - 12)
    if searchEntry then searchEntry.widget = cb; searchEntry.yPos = builder.cursorY; searchEntry.textObj = lbl end
    self:StyleCheckbox(cb)
    cb.Text:SetText(WT.L.OPT_FADE)
    cb:SetHitRectInsets(0, -cb.Text:GetStringWidth() - 5, 0, 0)
    cb:SetChecked(WT.DB[dbCategory][dbFade])
    self:AddTooltip(cb, WT.L.OPT_FADE, tooltipText)
    cb:SetScript("OnClick", function(self) WT.DB[dbCategory][dbFade] = self:GetChecked(); if callback then callback() end end)

    local sliderName = "WT_ScaleFadeSlider_" .. dbCategory .. "_" .. dbScale
    local slider = CreateFrame("Slider", sliderName, builder.content, "OptionsSliderTemplate")
    slider:SetPoint("LEFT", builder.content, "TOPLEFT", 280, builder.cursorY - 12)
    slider:SetMinMaxValues(0.5, 2.5)
    slider:SetValueStep(0.05)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(160)
    slider:SetValue(WT.DB[dbCategory][dbScale] or defaultScale)
    
    if _G[slider:GetName().."Low"] then _G[slider:GetName().."Low"]:Hide() end
    if _G[slider:GetName().."High"] then _G[slider:GetName().."High"]:Hide() end
    if _G[slider:GetName().."Text"] then _G[slider:GetName().."Text"]:Hide() end

    local valLbl = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valLbl:SetPoint("LEFT", slider, "RIGHT", 12, 0)
    valLbl:SetWidth(45)
    valLbl:SetJustifyH("RIGHT")
    valLbl:SetTextColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B)
    valLbl:SetText(string.format("%.0f%%", slider:GetValue() * 100))
    slider:SetScript("OnValueChanged", function(self, val) valLbl:SetText(string.format("%.0f%%", val * 100)); WT.DB[dbCategory][dbScale] = val; if callback then callback() end end)
    
    self:AddTooltip(slider, labelText, tooltipText)
    self:StyleSlider(slider)

    local btnReset = CreateFrame("Button", nil, builder.content)
    btnReset:SetSize(16, 16); btnReset:SetPoint("LEFT", valLbl, "RIGHT", 8, 0)
    btnReset:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton"); btnReset:SetPushedTexture("Interface\\Buttons\\UI-RefreshButton")
    btnReset:SetScript("OnClick", function() slider:SetValue(defaultScale); WT.DB[dbCategory][dbScale] = defaultScale; if callback then callback() end end)
    self:AddTooltip(btnReset, WT.L.BTN_RESET_DEFAULT, "")

    builder:AddSpace(32)
    self.Registry.Checkboxes[dbCategory] = self.Registry.Checkboxes[dbCategory] or {}
    self.Registry.Checkboxes[dbCategory][dbFade] = cb
    self.Registry.Sliders[dbCategory] = self.Registry.Sliders[dbCategory] or {}
    self.Registry.Sliders[dbCategory][dbScale] = slider
    return cb, slider
end

function Builder:CreateSlider(builder, labelText, tooltipText, dbCategory, dbKey, minValue, maxValue, step, callback, parentWidget)
    local searchEntry = self:IndexOption(labelText, dbCategory, builder.category, builder)
    local sliderName = "WT_Slider_" .. dbCategory .. "_" .. dbKey
    local slider = CreateFrame("Slider", sliderName, builder.content, "OptionsSliderTemplate")
    local depth = self:GetDepth(parentWidget)
    local indent = 16 + depth * INDENT_STEP
    
    local lbl = builder.content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lbl:SetPoint("LEFT", builder.content, "TOPLEFT", indent, builder.cursorY - 12)
    lbl:SetText(labelText)
    slider.wtLabel = lbl
    if searchEntry then searchEntry.widget = slider; searchEntry.yPos = builder.cursorY; searchEntry.textObj = lbl end
    
    slider:SetPoint("LEFT", builder.content, "TOPLEFT", 280, builder.cursorY - 12)
    slider:SetWidth(160)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(WT.DB[dbCategory][dbKey] or minValue)
    
    _G[sliderName.."Text"]:SetText("")
    _G[sliderName.."Low"]:SetText(minValue)
    _G[sliderName.."Low"]:SetTextColor(0.5, 0.5, 0.5)
    _G[sliderName.."High"]:SetText(maxValue)
    _G[sliderName.."High"]:SetTextColor(0.5, 0.5, 0.5)
    
    local valText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valText:SetPoint("LEFT", slider, "RIGHT", 12, 0)
    valText:SetWidth(45)
    valText:SetJustifyH("RIGHT")
    valText:SetTextColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B)
    local function FormatVal(v)
        if step >= 1 then return tostring(math.floor(v)) else return string.format("%.2f", v) end
    end
    valText:SetText(FormatVal(slider:GetValue()))
    
    slider:SetScript("OnValueChanged", function(self, val)
        valText:SetText(FormatVal(val))
        WT.DB[dbCategory][dbKey] = val
        if callback then callback(val) end
    end)
    
    local btnReset = CreateFrame("Button", nil, builder.content)
    btnReset:SetSize(16, 16)
    btnReset:SetPoint("LEFT", valText, "RIGHT", 8, 0)
    btnReset:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    btnReset:SetPushedTexture("Interface\\Buttons\\UI-RefreshButton")
    local defVal = WT.Config.Defaults[dbCategory] and WT.Config.Defaults[dbCategory][dbKey] or minValue
    btnReset:SetScript("OnClick", function() 
        slider:SetValue(defVal)
        WT.DB[dbCategory][dbKey] = defVal
        if callback then callback(defVal) end
    end)
    self:AddTooltip(btnReset, WT.L.BTN_RESET_DEFAULT, "")
    
    self:AddTooltip(slider, labelText, tooltipText)
    self:StyleSlider(slider)
    
    builder:AddSpace(34)
    self.Registry.Sliders[dbCategory] = self.Registry.Sliders[dbCategory] or {}
    self.Registry.Sliders[dbCategory][dbKey] = slider
    if parentWidget then self:RegisterParent(parentWidget, slider, lbl, valText, btnReset, _G[sliderName.."Low"], _G[sliderName.."High"]) end
    slider.wtDepth = depth
    return slider
end

local customDropdownMenu = nil

local function GetOrCreateDropdownMenu()
    if customDropdownMenu then return customDropdownMenu end

    local frame = CreateFrame("Frame", "WT_CustomDropdownFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(WT.Colors.STD_BG_R or 0.08, WT.Colors.STD_BG_G or 0.08, WT.Colors.STD_BG_B or 0.08, 0.96)
    frame:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    -- ScrollFrame to contain long option lists
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Custom slim scrollbar
    local scrollBar = CreateFrame("Slider", nil, frame)
    scrollBar:SetWidth(6)
    scrollBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -6)
    scrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 6)

    local barBg = scrollBar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    if barBg.SetColorTexture then
        barBg:SetColorTexture(0, 0, 0, 0.5)
    else
        barBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        barBg:SetVertexColor(0, 0, 0, 0.5)
    end

    scrollBar:SetThumbTexture("Interface\\ChatFrame\\ChatFrameBackground")
    local thumb = scrollBar:GetThumbTexture()
    if thumb then
        thumb:SetSize(6, 24)
        if thumb.SetColorTexture then
            thumb:SetColorTexture(WT.Colors.PRIMARY_R or 0, WT.Colors.PRIMARY_G or 1, WT.Colors.PRIMARY_B or 1, 0.8)
        else
            thumb:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
            thumb:SetVertexColor(WT.Colors.PRIMARY_R or 0, WT.Colors.PRIMARY_G or 1, WT.Colors.PRIMARY_B or 1, 0.8)
        end
    end

    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValue(0)

    scrollBar:SetScript("OnValueChanged", function(self, val)
        scrollFrame:SetVerticalScroll(val)
    end)

    local function OnMouseWheel(_, delta)
        if not scrollBar:IsShown() then return end
        local current = scrollBar:GetValue()
        local minVal, maxVal = scrollBar:GetMinMaxValues()
        local step = 36
        local newVal = math.max(minVal, math.min(maxVal, current - (delta * step)))
        scrollBar:SetValue(newVal)
    end

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", OnMouseWheel)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", OnMouseWheel)

    frame.scrollFrame = scrollFrame
    frame.scrollChild = scrollChild
    frame.scrollBar = scrollBar
    frame.buttons = {}
    frame.OnMouseWheel = OnMouseWheel

    frame:SetScript("OnHide", function(self) self.activeDropdown = nil end)

    -- Close when clicking outside
    local closeHandler = CreateFrame("Frame", nil, UIParent)
    closeHandler:SetAllPoints()
    closeHandler:SetFrameStrata("FULLSCREEN_DIALOG")
    closeHandler:EnableMouse(true)
    closeHandler:SetScript("OnMouseDown", function() frame:Hide() end)
    closeHandler:Hide()

    frame:SetScript("OnShow", function() closeHandler:Show() end)
    frame:HookScript("OnHide", function() closeHandler:Hide() end)

    customDropdownMenu = frame
    _G["WT_CustomDropdownFrame"] = frame
    return frame
end

function Builder:OpenDropdownMenu(anchorButton, dbCategory, dbKey, options, onSelect)
    local frame = GetOrCreateDropdownMenu()
    if frame:IsShown() and frame.activeDropdown == anchorButton then
        frame:Hide()
        return
    end

    frame.activeDropdown = anchorButton

    for _, b in ipairs(frame.buttons) do b:Hide() end

    local currentVal = (WT.DB and WT.DB[dbCategory] and WT.DB[dbCategory][dbKey])
    if currentVal == nil and options[1] then currentVal = options[1].value end

    local yOffset = -3
    local anchorW = anchorButton:GetWidth() or 140
    local maxWidth = math.max(140, anchorW - 16)
    local selectedIndex = nil

    for i, opt in ipairs(options) do
        local btn = frame.buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, frame.scrollChild)
            btn:SetHeight(20)
            btn:SetNormalFontObject("GameFontHighlightSmall")
            btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            if btn:GetHighlightTexture() then
                btn:GetHighlightTexture():SetBlendMode("ADD")
            end

            local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btnText:SetPoint("LEFT", btn, "LEFT", 14, 0)
            btnText:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            btnText:SetJustifyH("LEFT")
            btnText:SetWordWrap(false)
            btn.Text = btnText

            local check = btn:CreateTexture(nil, "OVERLAY")
            check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            check:SetSize(16, 16)
            check:SetPoint("LEFT", btn, "LEFT", -2, 0)
            btn.Check = check

            btn:EnableMouseWheel(true)
            btn:SetScript("OnMouseWheel", frame.OnMouseWheel)

            frame.buttons[i] = btn
        end

        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", frame.scrollChild, "TOPLEFT", 4, yOffset)
        btn:SetPoint("TOPRIGHT", frame.scrollChild, "TOPRIGHT", -4, yOffset)

        if opt.value == "WT_SEPARATOR" then
            btn.Text:SetText(WT.Colors.PRIMARY .. opt.label .. "|r")
            btn.Check:Hide()
            btn:Disable()
        else
            btn.Text:SetText(opt.label)
            if currentVal == opt.value then
                btn.Check:Show()
                selectedIndex = i
            else
                btn.Check:Hide()
            end
            btn:Enable()

            btn:SetScript("OnClick", function()
                if WT.DB and WT.DB[dbCategory] then
                    WT.DB[dbCategory][dbKey] = opt.value
                end
                if onSelect then onSelect(opt.value) end
                frame:Hide()
            end)
        end

        local stringWidth = btn.Text:GetStringWidth() + 32
        if stringWidth > maxWidth then maxWidth = stringWidth end

        btn:Show()
        yOffset = yOffset - 20
    end

    maxWidth = math.min(maxWidth, 360)

    local totalContentHeight = math.abs(yOffset) + 3
    local maxVisibleHeight = 260
    local hasScroll = totalContentHeight > maxVisibleHeight
    local visibleHeight = hasScroll and maxVisibleHeight or totalContentHeight

    local scrollWidth = hasScroll and (maxWidth + 14) or maxWidth
    local frameWidth = hasScroll and (scrollWidth + 18) or (scrollWidth + 10)

    frame.scrollChild:SetSize(scrollWidth, totalContentHeight)
    if frame.scrollFrame.UpdateScrollChildRect then
        frame.scrollFrame:UpdateScrollChildRect()
    end

    if hasScroll then
        frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 4)
        frame.scrollBar:Show()
        frame.scrollBar:SetMinMaxValues(0, math.max(0, totalContentHeight - visibleHeight))
        frame.scrollBar:SetValue(0)
    else
        frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
        frame.scrollBar:Hide()
        frame.scrollBar:SetMinMaxValues(0, 0)
        frame.scrollBar:SetValue(0)
    end
    frame.scrollFrame:SetVerticalScroll(0)

    frame:SetSize(frameWidth, visibleHeight + 8)

    local ddBottom = anchorButton:GetBottom() or 0
    local frameHeight = visibleHeight + 8
    frame:ClearAllPoints()

    local openUp = (ddBottom < frameHeight + 10)
    local screenWidth = (UIParent and UIParent:GetWidth()) or 1024
    local anchorLeft = anchorButton:GetLeft() or 0

    if anchorLeft + frameWidth > screenWidth - 10 then
        if openUp then
            frame:SetPoint("BOTTOMRIGHT", anchorButton, "TOPRIGHT", 0, 2)
        else
            frame:SetPoint("TOPRIGHT", anchorButton, "BOTTOMRIGHT", 0, -2)
        end
    else
        if openUp then
            frame:SetPoint("BOTTOMLEFT", anchorButton, "TOPLEFT", 0, 2)
        else
            frame:SetPoint("TOPLEFT", anchorButton, "BOTTOMLEFT", 0, -2)
        end
    end

    frame:Show()

    if hasScroll and selectedIndex and selectedIndex > 4 then
        local targetVal = math.min(totalContentHeight - visibleHeight, math.max(0, (selectedIndex - 4) * 20))
        frame.scrollBar:SetValue(targetVal)
    end
end

function Builder:CreateDropdown(builder, labelText, tooltipText, dbCategory, dbKey, options, callback, parentWidget)
    local searchEntry = self:IndexOption(labelText, dbCategory, builder.category, builder)
    local ddLabel = builder.content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    local depth = self:GetDepth(parentWidget)
    local indent = 16 + depth * INDENT_STEP
    ddLabel:SetPoint("LEFT", builder.content, "TOPLEFT", indent, builder.cursorY - 12)
    ddLabel:SetText(labelText)
    
    -- WOW 11.0 TAINT FIX: Do NOT use WowStyle1DropdownTemplate as it taints Menu.lua's shared pools when created insecurely!
    local dd = CreateFrame("Button", nil, builder.content, "UIMenuButtonStretchTemplate")
    dd.wtLabel = ddLabel
    dd:SetPoint("LEFT", builder.content, "TOPLEFT", 280, builder.cursorY - 12)
    dd:SetWidth(160)
    dd:SetHeight(26)
    if searchEntry then searchEntry.widget = dd; searchEntry.yPos = builder.cursorY; searchEntry.textObj = ddLabel end
    self:StyleDropdown(dd)
    
    local text = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", dd, "LEFT", 10, 0)
    text:SetPoint("RIGHT", dd, "RIGHT", -20, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    dd.Text = text
    
    local arrow = dd:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(16, 16)
    arrow:SetPoint("RIGHT", dd, "RIGHT", -2, 0)
    
    local function UpdateText()
        local currentVal = WT.DB[dbCategory][dbKey]
        if currentVal == nil and options[1] then currentVal = options[1].value end
        for _, opt in ipairs(options) do
            if opt.value == currentVal then
                dd.Text:SetText(opt.label)
                return
            end
        end
        dd.Text:SetText("Select...")
    end
    UpdateText()
    
    dd:SetScript("OnClick", function()
        self:OpenDropdownMenu(dd, dbCategory, dbKey, options, function(val)
            UpdateText()
            if callback then callback(val) end
        end)
    end)
    
    self:AddTooltip(dd, labelText, tooltipText)
    builder:AddSpace(34)
    self.Registry.Dropdowns[dbCategory] = self.Registry.Dropdowns[dbCategory] or {}
    self.Registry.Dropdowns[dbCategory][dbKey] = dd
    if parentWidget then self:RegisterParent(parentWidget, dd, ddLabel) end
    dd.wtDepth = depth
    return dd
end

local STRATA_OPTIONS = {
    { value = "BACKGROUND", label = WT.L.STRATA_BACKGROUND },
    { value = "LOW", label = WT.L.STRATA_LOW },
    { value = "MEDIUM", label = WT.L.STRATA_MEDIUM },
    { value = "HIGH", label = WT.L.STRATA_HIGH },
    { value = "DIALOG", label = WT.L.STRATA_DIALOG },
    { value = "FULLSCREEN", label = WT.L.STRATA_FULLSCREEN },
    { value = "FULLSCREEN_DIALOG", label = (WT.L.STRATA_FULLSCREEN) .. " Dialog" },
    { value = "TOOLTIP", label = WT.L.STRATA_TOOLTIP }
}
function Builder:CreateStrataDropdown(builder, labelText, tooltipText, dbCategory, dbKey, callback, parentWidget)
    return self:CreateDropdown(builder, labelText, tooltipText, dbCategory, dbKey, STRATA_OPTIONS, callback, parentWidget)
end

local OUTLINE_OPTIONS = {
    { value = "NONE", label = WT.L.OUTLINE_NONE },
    { value = "OUTLINE", label = WT.L.OUTLINE_THIN },
    { value = "THICKOUTLINE", label = WT.L.OUTLINE_THICK },
    { value = "MONOCHROME", label = WT.L.OUTLINE_MONOCHROME },
    { value = "OUTLINE, MONOCHROME", label = WT.L.OUTLINE_MONOCHROME_THIN }
}
function Builder:CreateOutlineDropdown(builder, labelText, tooltipText, dbCategory, dbKey, callback, parentWidget)
    return self:CreateDropdown(builder, labelText, tooltipText, dbCategory, dbKey, OUTLINE_OPTIONS, callback, parentWidget)
end

local AUDIO_CHANNEL_OPTIONS = {
    { value = "Master", label = "Master" },
    { value = "Dialog", label = "Dialog" },
    { value = "SFX", label = "SFX" },
    { value = "Music", label = "Music" },
    { value = "Ambience", label = "Ambience" }
}
function Builder:CreateSoundDropdown(builder, labelText, tooltipText, dbCategory, dbKey, parentWidget, callback)
    local options = WT.Utils.SharedMedia:GetOptions("sound")
    local channelKey = dbKey .. "Channel"
    
    local dd = self:CreateDropdown(builder, labelText, tooltipText, dbCategory, dbKey, options, function(val) 
        local playChannel = WT.DB[dbCategory][channelKey] or "Master"
        WT.Utils.Audio:Play(val, "PREVIEW", playChannel) 
        if callback then callback(val) end 
    end, parentWidget)
    
    local playBtn = CreateFrame("Button", nil, builder.content, "BackdropTemplate")
    playBtn:SetSize(22, 22)
    playBtn:SetPoint("LEFT", dd, "RIGHT", 5, 0)
    
    playBtn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    playBtn:SetBackdropColor(WT.Colors.STD_BG_R, WT.Colors.STD_BG_G, WT.Colors.STD_BG_B, WT.Colors.STD_BG_A)
    playBtn:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.8)
    
    local nt = playBtn:CreateTexture(nil, "ARTWORK")
    nt:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    nt:SetPoint("TOPLEFT", 2, -2); nt:SetPoint("BOTTOMRIGHT", -2, 2)
    nt:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    playBtn:SetNormalTexture(nt)
    
    local pt = playBtn:CreateTexture(nil, "ARTWORK")
    pt:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    pt:SetPoint("TOPLEFT", 2, -2); pt:SetPoint("BOTTOMRIGHT", -2, 2)
    pt:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    playBtn:SetPushedTexture(pt)
    
    local ht = playBtn:CreateTexture(nil, "HIGHLIGHT")
    ht:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    ht:SetPoint("TOPLEFT", 2, -2); ht:SetPoint("BOTTOMRIGHT", -2, 2)
    ht:SetBlendMode("ADD")
    playBtn:SetHighlightTexture(ht)
    
    playBtn:SetScript("OnClick", function()
        local val = WT.DB[dbCategory][dbKey]
        local playChannel = WT.DB[dbCategory][channelKey] or "Master"
        if val then WT.Utils.Audio:Play(val, "PREVIEW", playChannel) end
    end)
    self:AddTooltip(playBtn, WT.L.BTN_PLAY_SOUND, "")
    
    playBtn:HookScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 1, 1, 1) end)
    playBtn:HookScript("OnLeave", function(self) self:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.8) end)
    
    -- WOW 11.0 TAINT FIX: Avoid WowStyle1DropdownTemplate!
    local chanDd = CreateFrame("Button", nil, builder.content, "UIMenuButtonStretchTemplate")
    chanDd:SetPoint("LEFT", playBtn, "RIGHT", 10, 0)
    chanDd:SetWidth(90)
    chanDd:SetHeight(26)
    self:StyleDropdown(chanDd)
    
    local chanText = chanDd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chanText:SetPoint("LEFT", chanDd, "LEFT", 10, 0)
    chanText:SetPoint("RIGHT", chanDd, "RIGHT", -20, 0)
    chanText:SetJustifyH("LEFT")
    chanText:SetWordWrap(false)
    chanDd.Text = chanText
    
    local chanArrow = chanDd:CreateTexture(nil, "OVERLAY")
    chanArrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    chanArrow:SetSize(16, 16)
    chanArrow:SetPoint("RIGHT", chanDd, "RIGHT", -2, 0)
    
    local function UpdateChanText()
        local currentVal = WT.DB[dbCategory][channelKey] or "Master"
        for _, opt in ipairs(AUDIO_CHANNEL_OPTIONS) do
            if opt.value == currentVal then chanDd.Text:SetText(opt.label); return end
        end
        chanDd.Text:SetText("Master")
    end
    UpdateChanText()
    
    chanDd:SetScript("OnClick", function()
        self:OpenDropdownMenu(chanDd, dbCategory, channelKey, AUDIO_CHANNEL_OPTIONS, function(optVal)
            UpdateChanText()
            local sVal = WT.DB[dbCategory][dbKey]
            if sVal then WT.Utils.Audio:Play(sVal, "PREVIEW", optVal) end
        end)
    end)
    self:AddTooltip(chanDd, WT.L.OPT_AUDIO_CHANNEL, WT.L.OPT_DESC_AUDIO_CHANNEL)

    if parentWidget then self:RegisterParent(parentWidget, playBtn, chanDd) end
    return dd
end

function Builder:CreateEditBox(builder, labelText, tooltipText, dbCategory, dbKey, parentWidget, callback)
    local searchEntry = self:IndexOption(labelText, dbCategory, builder.category, builder)
    local ebLabel = builder.content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    local depth = self:GetDepth(parentWidget)
    local indent = 16 + depth * INDENT_STEP
    ebLabel:SetPoint("LEFT", builder.content, "TOPLEFT", indent, builder.cursorY - 12)
    ebLabel:SetText(labelText)
    
    local eb = CreateFrame("EditBox", nil, builder.content, "InputBoxTemplate")
    eb:SetSize(150, 22) -- 150px width + 10px texture overlap = 160px visual width
    eb:SetPoint("LEFT", builder.content, "TOPLEFT", 285, builder.cursorY - 12) -- 285 - 5px left texture = 280 visual edge
    if searchEntry then searchEntry.widget = eb; searchEntry.yPos = builder.cursorY; searchEntry.textObj = ebLabel end
    eb:SetFontObject("ChatFontNormal")
    eb:SetAutoFocus(false)
    eb:SetText(WT.DB[dbCategory][dbKey] or "")
    eb:SetCursorPosition(0)
    
    self:StyleEditBox(eb)

    eb:SetScript("OnTextChanged", function(self, isUserInput)
        if isUserInput then 
            WT.DB[dbCategory][dbKey] = self:GetText() 
            if callback then callback(self:GetText()) end
        end
    end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    
    local btnReset = CreateFrame("Button", nil, builder.content)
    btnReset:SetSize(16, 16)
    btnReset:SetPoint("LEFT", eb, "RIGHT", 4, 0)
    btnReset:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    btnReset:SetPushedTexture("Interface\\Buttons\\UI-RefreshButton")
    local defVal = WT.Config.Defaults[dbCategory] and WT.Config.Defaults[dbCategory][dbKey] or ""
    btnReset:SetScript("OnClick", function() 
        eb:SetText(defVal)
        WT.DB[dbCategory][dbKey] = defVal
        if callback then callback(defVal) end
    end)
    self:AddTooltip(btnReset, WT.L.BTN_RESET_DEFAULT, "")
    
    self:AddTooltip(eb, labelText, tooltipText)
    builder:AddSpace(34)
    self.Registry.EditBoxes[dbCategory] = self.Registry.EditBoxes[dbCategory] or {}
    self.Registry.EditBoxes[dbCategory][dbKey] = eb
    if parentWidget then self:RegisterParent(parentWidget, eb, ebLabel, btnReset) end
    eb.wtDepth = depth
    return eb
end

function Builder:CreateMultiLineEditBox(builder, labelText, tooltipText, dbCategory, dbKey, boxHeight, callback)
    local searchEntry = self:IndexOption(labelText, dbCategory, builder.category, builder)
    local lbl = builder.content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY - 5)
    lbl:SetText(labelText)

    local bg = CreateFrame("Frame", nil, builder.content, "BackdropTemplate")
    bg:SetSize(540, boxHeight or 100)
    if searchEntry then searchEntry.widget = bg; searchEntry.yPos = builder.cursorY; searchEntry.textObj = lbl end
    bg:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY - 25)
    bg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    bg:SetBackdropColor(WT.Colors.STD_BG_R, WT.Colors.STD_BG_G, WT.Colors.STD_BG_B, WT.Colors.STD_BG_A)
    bg:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    local sf = CreateFrame("ScrollFrame", nil, bg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -26, 6)

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetWidth(490)
    eb:SetMultiLine(true)
    eb:SetFontObject("ChatFontNormal")
    eb:SetAutoFocus(false)
    eb:SetText(WT.DB[dbCategory][dbKey] or "")
    eb:SetCursorPosition(0)
    
    eb.wtCursorOffset = 0
    eb.wtCursorHeight = 0
    eb:SetScript("OnCursorChanged", function(self, x, y, w, h)
        self.wtCursorOffset = y
        self.wtCursorHeight = h
        self.wtHandleCursorChange = true
    end)
    eb:SetScript("OnUpdate", function(self, elapsed)
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
    eb:SetScript("OnTextChanged", function(self, isUserInput) 
        local scrollFrame = self:GetParent()
        if scrollFrame and scrollFrame.UpdateScrollChildRect then scrollFrame:UpdateScrollChildRect() end
        if isUserInput then 
            WT.DB[dbCategory][dbKey] = self:GetText()
            if callback then callback(self:GetText()) end 
        end 
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    
    bg:EnableMouse(true)
    bg:SetScript("OnMouseDown", function() eb:SetFocus() end)
    
    eb:HookScript("OnEditFocusGained", function() bg:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 1) end)
    eb:HookScript("OnEditFocusLost", function() bg:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8) end)
    bg:SetScript("OnEnter", function() if not eb:HasFocus() then bg:SetBackdropBorderColor(0.6, 0.6, 0.6, 1) end end)
    bg:SetScript("OnLeave", function() if not eb:HasFocus() then bg:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8) end end)
    
    sf:SetScrollChild(eb)
    self:AddTooltip(bg, labelText, tooltipText)
    builder:AddSpace((boxHeight or 100) + 30)
    self.Registry.EditBoxes[dbCategory] = self.Registry.EditBoxes[dbCategory] or {}
    self.Registry.EditBoxes[dbCategory][dbKey] = eb
    return eb
end

function Builder:CreateButton(builder, labelText, buttonText, tooltipText, callback, parentWidget)
    local searchEntry = self:IndexOption(labelText or buttonText, builder.moduleName or "Category", builder.category, builder)
    local btn = CreateFrame("Button", nil, builder.content, "UIPanelButtonTemplate")
    btn:SetSize(160, 26)
    btn:SetNormalFontObject("GameFontNormalSmall")
    btn:SetHighlightFontObject("GameFontHighlightSmall")
    btn:SetDisabledFontObject("GameFontDisableSmall")
    local depth = self:GetDepth(parentWidget)
    local indent = 16 + depth * INDENT_STEP
    
    local lbl
    if labelText and labelText ~= "" then
        lbl = builder.content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        lbl:SetPoint("LEFT", builder.content, "TOPLEFT", indent, builder.cursorY - 12)
        lbl:SetText(labelText)
        btn:SetPoint("LEFT", builder.content, "TOPLEFT", 280, builder.cursorY - 12)
        btn.wtLabel = lbl
        if searchEntry then searchEntry.textObj = lbl end
    else
        btn:SetPoint("TOPLEFT", builder.content, "TOPLEFT", indent, builder.cursorY - 8)
    end
    if searchEntry then searchEntry.widget = btn; searchEntry.yPos = builder.cursorY end
    
    btn:SetText(buttonText)
    btn:SetScript("OnClick", function()
        if callback then callback() end
    end)
    self:StyleButton(btn)
    
    self:AddTooltip(btn, buttonText, tooltipText)
    builder:AddSpace(34)
    if parentWidget then self:RegisterParent(parentWidget, btn, lbl) end
    btn.wtDepth = depth
    return btn
end

function Builder:CreateKeybindButton(builder, labelText, tooltipText, bindingID, parentWidget)
    local searchEntry = self:IndexOption(labelText, builder.moduleName or "Category", builder.category, builder)
    local lbl = builder.content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    local depth = self:GetDepth(parentWidget)
    local indent = 16 + depth * INDENT_STEP
    lbl:SetPoint("LEFT", builder.content, "TOPLEFT", indent, builder.cursorY - 12)
    lbl:SetText(labelText)
    
    local btn = CreateFrame("Button", nil, builder.content, "UIPanelButtonTemplate")
    btn:SetSize(160, 26)
    btn:SetPoint("LEFT", builder.content, "TOPLEFT", 280, builder.cursorY - 12)
    self:StyleButton(btn)
    
    if searchEntry then searchEntry.widget = btn; searchEntry.yPos = builder.cursorY; searchEntry.textObj = lbl end

    local function UpdateText()
        local keys = {GetBindingKey(bindingID)}
        if #keys > 0 then
            btn:SetText(table.concat(keys, ", "))
            btn:SetNormalFontObject("GameFontHighlightSmall")
        else
            btn:SetText(WT.L.BTN_UNBOUND)
            btn:SetNormalFontObject("GameFontDisableSmall")
        end
    end
    
    UpdateText()
    
    local isListening = false
    
    btn:SetScript("OnClick", function(self, button)
        if isListening then return end
        if button == "RightButton" then
            local keys = {GetBindingKey(bindingID)}
            for _, k in ipairs(keys) do SetBinding(k, nil) end
            SaveBindings(GetCurrentBindingSet())
            UpdateText()
            return
        end
        
        isListening = true
        self:SetText(WT.L.BTN_PRESS_KEY)
        self:EnableKeyboard(true)
    end)
    
    local function BindKey(key)
        isListening = false
        btn:EnableKeyboard(false)
        if key == "ESCAPE" then UpdateText(); return end
        
        local mod = ""
        if IsAltKeyDown() then mod = mod .. "ALT-" end
        if IsControlKeyDown() then mod = mod .. "CTRL-" end
        if IsShiftKeyDown() then mod = mod .. "SHIFT-" end
        if IsMetaKeyDown and IsMetaKeyDown() then mod = mod .. "META-" end
        
        local finalKey = mod .. key
        
        -- 1. Explicitly unbind old WoW actions to prevent ghost bindings
        local oldAction = GetBindingAction(finalKey)
        if oldAction and oldAction ~= "" and oldAction ~= bindingID then
            local actionName = GetBindingName(oldAction) or oldAction
            if WT.Utils and WT.Utils.Logger then
                WT.Utils.Logger:Print(string.format(WT.L.MSG_KEY_UNBOUND, "|cFFFFFF00" .. actionName .. "|r", "|cFF00FFFF" .. finalKey .. "|r"))
            end
            SetBinding(finalKey, nil)
        end
        
        -- 2. Clear all old keys that were previously bound to our WT action
        local oldKeys = {GetBindingKey(bindingID)}
        for _, k in ipairs(oldKeys) do SetBinding(k, nil) end
        
        -- 3. Register the new key and permanently save it to the WoW account
        SetBinding(finalKey, bindingID)
        SaveBindings(GetCurrentBindingSet())
        UpdateText()
    end
    
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnHide", function(self) isListening = false; self:EnableKeyboard(false); UpdateText() end)
    btn:HookScript("OnShow", function(self) UpdateText() end)
    
    btn:RegisterEvent("UPDATE_BINDINGS")
    btn:HookScript("OnEvent", function(self, event)
        if event == "UPDATE_BINDINGS" then
            UpdateText()
        end
    end)
    
    btn:SetScript("OnKeyDown", function(self, key)
        if not isListening then
            self:SetPropagateKeyboardInput(true)
            return
        end
        self:SetPropagateKeyboardInput(false)
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" or key == "UNKNOWN" then return end
        BindKey(key)
    end)
    btn:EnableKeyboard(false)
    btn:SetScript("OnMouseDown", function(self, button) if isListening and button ~= "LeftButton" and button ~= "RightButton" then BindKey(button == "MiddleButton" and "BUTTON3" or string.upper(button)) end end)
    btn:SetScript("OnMouseWheel", function(self, delta) if isListening then BindKey(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end end)
    
    local ttAdd = "\n\n|cFF00FF00" .. (WT.L.BTN_BIND_LEFT) .. "|r\n|cFFFF0000" .. (WT.L.BTN_BIND_RIGHT) .. "|r"
    self:AddTooltip(btn, labelText, (tooltipText and tooltipText ~= "" and tooltipText or "") .. ttAdd)
    
    builder:AddSpace(34)
    if parentWidget then self:RegisterParent(parentWidget, btn, lbl) end
    btn.wtDepth = depth
    return btn
end