local _, WT = ...

WT.Modules.ColorPicker = {}
local Module = WT.Modules.ColorPicker

local MAX_SAVED_COLORS = 13
local SWATCH_SIZE = 16
local SWATCH_SPACING = 6

function Module:HookColorPicker()
    if not ColorPickerFrame then return end
    if ColorPickerFrame.WT_Extended then return end
    ColorPickerFrame.WT_Extended = true

    -- We need more space for titles and the swatches
    local extraHeight = 95
    ColorPickerFrame:SetHeight(ColorPickerFrame:GetHeight() + extraHeight)

    local f = CreateFrame("Frame", "WT_ColorPickerPlus", ColorPickerFrame)
    f:SetPoint("BOTTOMLEFT", ColorPickerFrame, "BOTTOMLEFT", 10, 35)
    f:SetPoint("BOTTOMRIGHT", ColorPickerFrame, "BOTTOMRIGHT", -10, 35)
    f:SetHeight(85)
    
    -- Move the native HexBox UP so it sits above our new container.
    -- We must lock its SetPoint method because Blizzard's layout engine dynamically re-anchors it 
    -- depending on context (e.g., when the opacity slider is enabled), which pushes it down into our swatches.
    if ColorPickerFrame.Content and ColorPickerFrame.Content.HexBox then
        local hex = ColorPickerFrame.Content.HexBox
        hex:ClearAllPoints()
        hex:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -20, 10)
        
        if not hex.wtHooked then
            hex.wtHooked = true
            local orig = hex.SetPoint
            hex.SetPoint = function(self, ...)
                -- Ignore Blizzard's dynamic anchors and force it to stay above our custom swatches
                orig(self, "BOTTOMRIGHT", f, "TOPRIGHT", -20, 10)
            end
        end
    end
    f.savedSwatches = {}
    f.classSwatches = {}
    
    local function GetCurrentColor()
        local r, g, b, a
        if ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker and ColorPickerFrame.Content.ColorPicker.GetColorRGB then
            r, g, b = ColorPickerFrame.Content.ColorPicker:GetColorRGB()
        elseif ColorPickerFrame.GetColorAsRGB then
            local color = ColorPickerFrame:GetColorAsRGB()
            if type(color) == "table" and color.GetRGB then
                r, g, b = color:GetRGB()
            else
                -- Fallback if it's not a mixin
                r, g, b = ColorPickerFrame:GetColorAsRGB()
            end
        elseif ColorPickerFrame.GetColorRGB then
            r, g, b = ColorPickerFrame:GetColorRGB()
        end
        
        if ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker and ColorPickerFrame.Content.ColorPicker.GetColorAlpha then
            a = ColorPickerFrame.Content.ColorPicker:GetColorAlpha()
        elseif ColorPickerFrame.GetColorAlpha then
            a = ColorPickerFrame:GetColorAlpha()
        elseif _G["OpacitySliderFrame"] then
            a = _G["OpacitySliderFrame"]:GetValue()
        end
        
        -- Safeguard against table references slipping through
        if type(r) == "table" then r = 1 end
        if type(g) == "table" then g = 1 end
        if type(b) == "table" then b = 1 end
        
        return {r = r or 1, g = g or 1, b = b or 1, a = a or 1}
    end

    -- Helper to set current color to ColorPicker
    local function SetCurrentColor(c)
        if not c then return end
        
        if ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker and ColorPickerFrame.Content.ColorPicker.SetColorRGB then
            ColorPickerFrame.Content.ColorPicker:SetColorRGB(c.r, c.g, c.b)
        elseif ColorPickerFrame.SetColorRGB then
            ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
        end
        
        if ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker and ColorPickerFrame.Content.ColorPicker.SetColorAlpha then
            ColorPickerFrame.Content.ColorPicker:SetColorAlpha(c.a or 1)
        elseif ColorPickerFrame.SetColorAlpha then
            ColorPickerFrame:SetColorAlpha(c.a or 1)
        elseif _G["OpacitySliderFrame"] then
            _G["OpacitySliderFrame"]:SetValue(c.a or 1)
        end
    end

    local function UpdateSavedSwatches()
        for i = 1, MAX_SAVED_COLORS do
            local swatch = f.savedSwatches[i]
            local col = WT.DB.SavedColors[i]
            if col then
                swatch.tex:SetColorTexture(col.r, col.g, col.b, col.a or 1)
                swatch.isEmpty = false
                swatch.bg:SetColorTexture(1, 1, 1, 1)
            else
                swatch.tex:SetColorTexture(0.2, 0.2, 0.2, 0.8)
                swatch.isEmpty = true
                swatch.bg:SetColorTexture(0, 0, 0, 1)
            end
        end
    end
    
    local rowWidth = (MAX_SAVED_COLORS * SWATCH_SIZE) + ((MAX_SAVED_COLORS - 1) * SWATCH_SPACING)
    
    local swatchesContainer = CreateFrame("Frame", nil, f)
    swatchesContainer:SetSize(rowWidth, 75)
    swatchesContainer:SetPoint("TOP", f, "TOP", 0, 0)
    
    local function ShowTooltip(owner, title, desc)
        GameTooltip:SetOwner(owner, "ANCHOR_TOP", 0, 5)
        GameTooltip:AddLine(title, 1, 1, 1)
        if desc then
            GameTooltip:AddLine(desc, 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end
    
    -- TITLE 1: Saved Colors
    local savedTitle = swatchesContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    savedTitle:SetPoint("TOPLEFT", swatchesContainer, "TOPLEFT", 0, 0)
    savedTitle:SetText(WT.L.CP_SAVED_COLORS)
    savedTitle:SetTextColor(1, 0.82, 0) -- Goldish
    
    local row1Y = -15
    for i = 1, MAX_SAVED_COLORS do
        local btn = CreateFrame("Button", nil, swatchesContainer)
        btn:SetSize(SWATCH_SIZE, SWATCH_SIZE)
        btn:SetPoint("TOPLEFT", swatchesContainer, "TOPLEFT", (i - 1) * (SWATCH_SIZE + SWATCH_SPACING), row1Y)
        
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(1, 1, 1, 1)
        
        btn.tex = btn:CreateTexture(nil, "ARTWORK")
        btn.tex:SetPoint("TOPLEFT", 1, -1)
        btn.tex:SetPoint("BOTTOMRIGHT", -1, 1)
        
        btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.hl:SetColorTexture(1, 1, 1, 0.25)
        btn.hl:SetAllPoints(btn.tex)
        
        btn:SetScript("OnEnter", function(self)
            ShowTooltip(self, WT.L.CP_SAVED_COLORS, WT.L.CP_SAVE_HINT)
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        btn:RegisterForClicks("AnyUp")
        btn:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                if not self.isEmpty then
                    WT.DB.SavedColors[i] = nil
                    UpdateSavedSwatches()
                end
            elseif button == "LeftButton" then
                if IsShiftKeyDown() then
                    WT.DB.SavedColors[i] = GetCurrentColor()
                    UpdateSavedSwatches()
                elseif not self.isEmpty then
                    SetCurrentColor(WT.DB.SavedColors[i])
                end
            end
        end)
        
        f.savedSwatches[i] = btn
    end
    
    -- TITLE 2: Class Colors
    local row2Y = row1Y - SWATCH_SIZE - 20
    local classTitle = swatchesContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    classTitle:SetPoint("TOPLEFT", swatchesContainer, "TOPLEFT", 0, row2Y + 12)
    classTitle:SetText(WT.L.CP_CLASS_COLORS)
    classTitle:SetTextColor(1, 0.82, 0)
    
    local classes = { "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE", "MONK", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
    
    for i, classToken in ipairs(classes) do
        local btn = CreateFrame("Button", nil, swatchesContainer)
        btn:SetSize(SWATCH_SIZE, SWATCH_SIZE)
        btn:SetPoint("TOPLEFT", swatchesContainer, "TOPLEFT", (i - 1) * (SWATCH_SIZE + SWATCH_SPACING), row2Y - 3)
        
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(0, 0, 0, 1)
        
        btn.tex = btn:CreateTexture(nil, "ARTWORK")
        btn.tex:SetPoint("TOPLEFT", 1, -1)
        btn.tex:SetPoint("BOTTOMRIGHT", -1, 1)
        
        btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.hl:SetColorTexture(1, 1, 1, 0.25)
        btn.hl:SetAllPoints(btn.tex)
        
        btn:SetScript("OnEnter", function(self)
            ShowTooltip(self, LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classToken] or classToken, WT.L.CP_CLASS_COLORS)
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        btn:SetScript("OnClick", function()
            local c = WT.DB.ClassColors[classToken]
            if c then
                SetCurrentColor({r = c.r, g = c.g, b = c.b, a = 1})
            end
        end)
        
        f.classSwatches[classToken] = btn
    end
    
    ColorPickerFrame:HookScript("OnShow", function()
        WT.DB.SavedColors = WT.DB.SavedColors or {}
        
        for classToken, btn in pairs(f.classSwatches) do
            local c = WT.DB.ClassColors[classToken]
            if c then
                btn.tex:SetColorTexture(c.r, c.g, c.b, 1)
            end
        end
        
        UpdateSavedSwatches()
    end)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    if WT.DB and WT.DB.Modules and WT.DB.Modules.ColorPicker then
        Module:HookColorPicker()
    end
end)
