local _, WT = ...

WT.Modules.TimeWidget = {}
local Module = WT.Modules.TimeWidget

local timeFrame

local isPreviewMode = false

local GetGameTime = GetGameTime
local tonumber = tonumber
local date = date
local string_format = string.format
local type = type

local SafeNum = WT.Utils.Safety.SafeNum
local Unsecret = WT.Utils.Safety.Unsecret

local function UpdateTime()
    if not timeFrame or not timeFrame:IsShown() then return end
    
    local h, m = 0, 0
    if WT.DB.TimeWidget.UseServerTime then
        local ok, gH, gM = pcall(GetGameTime)
        h = ok and SafeNum(gH) or 0
        m = ok and SafeNum(gM) or 0
    else
        local okH, dH = pcall(date, "%H")
        h = okH and SafeNum(tonumber(dH)) or 0
        local okM, dM = pcall(date, "%M")
        m = okM and SafeNum(tonumber(dM)) or 0
    end
    
    local okS, dS = pcall(date, "%S")
    local s = okS and SafeNum(tonumber(dS)) or 0
    
    local ampm = ""
    if not WT.DB.TimeWidget.Format24h then
        if h >= 12 then
            ampm = " PM"
            if h > 12 then h = h - 12 end
        else
            ampm = " AM"
            if h == 0 then h = 12 end
        end
    end
    
    local timeStr
    if WT.DB.TimeWidget.ShowSeconds then
        timeStr = string_format("%02d:%02d:%02d%s", h, m, s, ampm)
    else
        timeStr = string_format("%02d:%02d%s", h, m, ampm)
    end
    
    if WT.DB.TimeWidget.SuffixUhr then
        timeStr = timeStr .. " " .. (WT.L.TW_SUFFIX_UHR_TEXT)
    end
    
    local dateStr = ""
    if WT.DB.TimeWidget.ShowDate then
        local okD, d = pcall(date, WT.DB.TimeWidget.DateFormat or "%d.%m.%Y")
        local safeD = okD and Unsecret(d) or ""
        if type(safeD) == "string" then dateStr = safeD end
    end
    
    local finalStr = timeStr
    if dateStr ~= "" then
        local sc = WT.Colors:GetHex(WT.DB.TimeWidget.SeparatorColor, 0.5, 0.5, 0.5)
        local sep = "|c" .. sc .. (WT.DB.TimeWidget.Separator or " - ") .. "|r"
        finalStr = dateStr .. sep .. timeStr
    end
    
    if timeFrame.wtLastText ~= finalStr then
        timeFrame.wtLastText = finalStr
        local tc = WT.Colors:GetHex(WT.DB.TimeWidget.TextColor, 1, 1, 1)
        timeFrame.text:SetText("|c" .. tc .. finalStr .. "|r")
        
        local newWidth = timeFrame.text:GetStringWidth() + 20
        if not timeFrame.wtLastWidth or math.abs(timeFrame.wtLastWidth - newWidth) > 2 then
            timeFrame:SetWidth(newWidth)
            timeFrame.wtLastWidth = newWidth
        end
    end
end

function Module:SetupWidget()
    if not WT.DB.TimeWidget.Show and not isPreviewMode then
        if timeFrame then timeFrame:Hide() end
        return
    end
    
    if not timeFrame then
        timeFrame = CreateFrame("Button", "WTTimeWidget", _G["WT_UIContainer"], "BackdropTemplate")
        timeFrame:SetSize(80, 24)
        
        timeFrame.ignoreInLayout = true
        timeFrame.ignoreFramePositionManager = true
        if timeFrame.SetIsFramePositionManaged then pcall(function() timeFrame:SetIsFramePositionManaged(false) end) end
        
        timeFrame.text = timeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        timeFrame.text:SetPoint("CENTER", timeFrame, "CENTER", 0, 0)
        
        timeFrame:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        
        timeFrame:RegisterForClicks("AnyUp")
        
        timeFrame:SetScript("OnClick", function(self, button)
            if self.wtIsMoving then return end
            if InCombatLockdown() then
                if WT.Utils and WT.Utils.Logger then WT.Utils.Logger:Warn(WT.L.MSG_COMBAT_BLOCK) end
                return
            end
            if button == "LeftButton" then
                C_Timer.After(0.01, function() if ToggleCalendar then pcall(ToggleCalendar) end end)
            elseif button == "RightButton" then
                C_Timer.After(0.01, function()
                    local loadFunc = (C_AddOns and C_AddOns.LoadAddOn) or _G["LoadAddOn"] or _G["UIParentLoadAddOn"]
                    if not TimeManager_Toggle and loadFunc then pcall(loadFunc, "Blizzard_TimeManager") end
                    if TimeManager_Toggle then pcall(TimeManager_Toggle) end
                end)
            end
        end)
        
        timeFrame:RegisterForDrag("LeftButton")
        timeFrame:SetScript("OnDragStart", function(self)
            local mod = WT.DB.TimeWidget.MoveModifier or "ALT"
            local canMove = (mod == "SHIFT" and IsShiftKeyDown()) or (mod == "CTRL" and IsControlKeyDown()) or (mod == "ALT" and IsAltKeyDown())
            if WT.DB.TimeWidget.Movable and canMove then self:StartMoving() end
        end)
        timeFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            
            local okL, rawLeft = pcall(self.GetLeft, self)
            local okT, rawTop = pcall(self.GetTop, self)
            local left = okL and SafeNum(rawLeft) or nil
            local top = okT and SafeNum(rawTop) or nil
            if left and top then
                self:ClearAllPoints()
                self:SetPoint("TOPLEFT", _G["WT_UIContainer"], "BOTTOMLEFT", left, top)
            end
            
            local okP, rawP, _, rawRP, x, y = pcall(self.GetPoint, self)
            if okP then
                if not WT.DB.Internal.Positions then WT.DB.Internal.Positions = {} end
                WT.DB.Internal.Positions["WTTimeWidget"] = { point = Unsecret(rawP) or "TOPLEFT", relativeTo = "UIParent", relativePoint = Unsecret(rawRP) or "BOTTOMLEFT", xOfs = SafeNum(x), yOfs = SafeNum(y) }
            end
        end)
    end
    
    timeFrame:SetFrameStrata(WT.DB.TimeWidget.Strata or "MEDIUM")
    timeFrame:SetMovable(WT.DB.TimeWidget.Movable)
    timeFrame:EnableMouse(WT.DB.TimeWidget.Movable)
    
    local fontKey = WT.DB.TimeWidget.Font or "Friz Quadrata TT"
    local fontPath = (WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", fontKey)) or "Fonts\\FRIZQT__.TTF"
    local size = WT.DB.TimeWidget.FontSize or 12
    local outline = (WT.DB.TimeWidget.FontOutline == "NONE") and "" or (WT.DB.TimeWidget.FontOutline or "OUTLINE")
    timeFrame.text:SetFont(fontPath, size, outline)
    timeFrame:SetHeight(size + 14)
    
    if WT.DB.TimeWidget.Background then
        local bg = WT.DB.TimeWidget.BgColor or {r=WT.Colors.STD_BG_R, g=WT.Colors.STD_BG_G, b=WT.Colors.STD_BG_B, a=WT.Colors.STD_BG_A}
        timeFrame:SetBackdropColor(bg.r or 0, bg.g or 0, bg.b or 0, bg.a or 0.8)
    else
        timeFrame:SetBackdropColor(0, 0, 0, 0)
    end
    
    if WT.DB.TimeWidget.Border then
        local bc = WT.DB.TimeWidget.BorderColor or {r=1, g=1, b=1, a=1}
        timeFrame:SetBackdropBorderColor(bc.r or 1, bc.g or 1, bc.b or 1, bc.a or 1)
    else
        timeFrame:SetBackdropBorderColor(0, 0, 0, 0)
    end
    
    if WT.DB.Internal.Positions and WT.DB.Internal.Positions["WTTimeWidget"] then
        local pos = WT.DB.Internal.Positions["WTTimeWidget"]
        timeFrame:ClearAllPoints()
        timeFrame:SetPoint(pos.point, _G["WT_UIContainer"], pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        timeFrame:ClearAllPoints()
        timeFrame:SetPoint("TOP", _G["WT_UIContainer"], "TOP", 0, -20)
    end
    
    WT.Core.Events:UnregisterOnUpdate(UpdateTime)
    local tickRate = WT.DB.TimeWidget.ShowSeconds and 0.2 or 1.0
    WT.Core.Events:RegisterOnUpdate(UpdateTime, tickRate, "TimeWidget")
    
    timeFrame:Show()
    UpdateTime()
end

function Module:PreviewWidget()
    if isPreviewMode then return end
    isPreviewMode = true
    self:SetupWidget()
    C_Timer.After(10, function()
        isPreviewMode = false
        self:SetupWidget()
    end)
end

function Module:Initialize()
    if not WT.DB.Modules.TimeWidget then return end
    local loadFunc = (C_AddOns and C_AddOns.LoadAddOn) or _G["LoadAddOn"] or _G["UIParentLoadAddOn"]
    if loadFunc then pcall(loadFunc, "Blizzard_TimeManager") end
    self:SetupWidget()
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

    panel:CreateTitle(builder, WT.L.CATEGORY_TIMEWIDGET)
    AddDescription(WT.L.OPT_DESC_MODULE_TIMEWIDGET)
    
    panel:CreateTitle(builder, WT.L.GROUP_TW_BEHAVIOR)
    AddDescription(WT.L.OPT_DESC_GROUP_TW_BEHAVIOR)
    
    local showInit = panel:CreateCheckbox(builder, WT.L.OPT_TW_SHOW, WT.L.OPT_DESC_TW_SHOW, "TimeWidget", "Show", function() self:SetupWidget() end)
    panel:CreateCheckbox(builder, WT.L.OPT_TW_USE_SERVER, WT.L.OPT_DESC_TW_USE_SERVER, "TimeWidget", "UseServerTime", function() UpdateTime() end, showInit)
    panel:CreateCheckbox(builder, WT.L.OPT_TW_FORMAT_24H, WT.L.OPT_DESC_TW_FORMAT_24H, "TimeWidget", "Format24h", function() UpdateTime() end, showInit)
    panel:CreateCheckbox(builder, WT.L.OPT_TW_SHOW_SECONDS, WT.L.OPT_DESC_TW_SHOW_SECONDS, "TimeWidget", "ShowSeconds", function() UpdateTime() end, showInit)
    panel:CreateCheckbox(builder, WT.L.OPT_TW_SUFFIX_UHR, WT.L.OPT_DESC_TW_SUFFIX_UHR, "TimeWidget", "SuffixUhr", function() UpdateTime() end, showInit)
    
    local dateInit = panel:CreateCheckbox(builder, WT.L.OPT_TW_SHOW_DATE, WT.L.OPT_DESC_TW_SHOW_DATE, "TimeWidget", "ShowDate", function() UpdateTime() end, showInit)
    local dfOptions = {
        { value = "%d.%m.%Y", label = "31.12.2026" },
        { value = "%Y-%m-%d", label = "2026-12-31" },
        { value = "%m/%d/%Y", label = "12/31/2026" },
        { value = "%d. %b", label = "31. Dec" }
    }
    panel:CreateDropdown(builder, WT.L.OPT_TW_DATE_FORMAT, WT.L.OPT_DESC_TW_DATE_FORMAT, "TimeWidget", "DateFormat", dfOptions, function() UpdateTime() end, dateInit)
    
    panel:CreateTitle(builder, WT.L.GROUP_TW_APPEARANCE)
    AddDescription(WT.L.OPT_DESC_GROUP_TW_APPEARANCE)
    
    panel:CreateButton(builder, WT.L.OPT_TW_TEST, WT.L.BTN_TEST, WT.L.OPT_DESC_TW_TEST, function()
        self:PreviewWidget()
    end)
    builder:AddSpace(10)
    
    local moveInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_MOVABLE, WT.L.OPT_DESC_SW_MOVABLE, "TimeWidget", "Movable", function() self:SetupWidget() end, showInit)
    local modOptions = { { value = "ALT", label = "ALT" }, { value = "CTRL", label = "CTRL" }, { value = "SHIFT", label = "SHIFT" } }
    panel:CreateDropdown(builder, WT.L.OPT_SW_MOVE_MODIFIER, WT.L.OPT_DESC_SW_MOVE_MODIFIER, "TimeWidget", "MoveModifier", modOptions, nil, moveInit)
    panel:CreateStrataDropdown(builder, WT.L.OPT_STRATA, WT.L.OPT_DESC_STRATA, "TimeWidget", "Strata", function() self:SetupWidget() end, showInit)
    
    if WT.Utils and WT.Utils.SharedMedia then
        panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "TimeWidget", "Font", WT.Utils.SharedMedia:GetOptions("font"), function() self:SetupWidget() end, showInit)
    end
    panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "TimeWidget", "FontSize", 8, 36, 1, function() self:SetupWidget() end, showInit)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "TimeWidget", "FontOutline", function() self:SetupWidget() end, showInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_TEXT, WT.L.OPT_DESC_COLOR_TEXT, "TimeWidget", "TextColor", true, showInit, function() UpdateTime() end)
    
    local sepInit = panel:CreateEditBox(builder, WT.L.OPT_SEPARATOR, WT.L.OPT_DESC_SEPARATOR, "TimeWidget", "Separator", showInit, function() UpdateTime() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_SEP, WT.L.OPT_DESC_COLOR_SEP, "TimeWidget", "SeparatorColor", true, sepInit, function() UpdateTime() end)
    
    local bgInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_BACKGROUND, WT.L.OPT_DESC_SW_BACKGROUND, "TimeWidget", "Background", function() self:SetupWidget() end, showInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BG, WT.L.OPT_DESC_COLOR_BG, "TimeWidget", "BgColor", true, bgInit, function() self:SetupWidget() end)
    
    local borderInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_BORDER, WT.L.OPT_DESC_SW_BORDER, "TimeWidget", "Border", function() self:SetupWidget() end, showInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BORDER, WT.L.OPT_DESC_COLOR_BORDER, "TimeWidget", "BorderColor", true, borderInit, function() self:SetupWidget() end)
end