local _, WT = ...

-- ============================================================================
-- TIME WIDGET
-- ============================================================================
-- A small on-screen clock (optionally with date). Opt-in: nothing is created until
-- "Show" is enabled, and turning it off hides the widget and stops its ticker.
-- 24h format and local/realm time follow Blizzard's own clock settings
-- (CVars timeMgrUseMilitaryTime / timeMgrUseLocalTime, right-click the widget to change them).
-- Left-click opens the calendar, right-click Blizzard's clock settings.

local Module = WT:NewModule("TimeWidget")

local date = date
local string_format = string.format
local GetGameTime = GetGameTime

local POSITION_KEY = "WTTimeWidget"
local CVAR_MILITARY = "timeMgrUseMilitaryTime"
local CVAR_LOCAL = "timeMgrUseLocalTime"

local timeFrame
local isPreview = false

local function IsWanted()
    return WT.DB.TimeWidget.Show or isPreview
end

local function GetCurrentTime()
    if GetCVarBool(CVAR_LOCAL) then
        local now = date("*t")
        return now.hour, now.min, now.sec
    end
    local hour, minute = GetGameTime()
    return hour, minute, tonumber(date("%S")) or 0
end

local function FormatTime()
    local db = WT.DB.TimeWidget
    local hour, minute, second = GetCurrentTime()

    local suffix = ""
    if not GetCVarBool(CVAR_MILITARY) then
        suffix = " " .. ((hour >= 12) and TIMEMANAGER_PM or TIMEMANAGER_AM)
        hour = hour % 12
        if hour == 0 then hour = 12 end
    end

    local text
    if db.ShowSeconds then
        text = string_format("%02d:%02d:%02d%s", hour, minute, second, suffix)
    else
        text = string_format("%02d:%02d%s", hour, minute, suffix)
    end
    if db.SuffixUhr then
        text = text .. " " .. WT.L.TW_SUFFIX_UHR_TEXT
    end

    if db.ShowDate then
        local dateText = date(db.DateFormat or "%d.%m.%Y")
        if type(dateText) == "string" and dateText ~= "" then
            local separator = "|c" .. WT.Colors:GetHex(db.SeparatorColor, 0.5, 0.5, 0.5) .. (db.Separator or " - ") .. "|r"
            text = dateText .. separator .. text
        end
    end
    return "|c" .. WT.Colors:GetHex(db.TextColor, 1, 1, 1) .. text .. "|r"
end

local function UpdateTime()
    if not timeFrame or not timeFrame:IsShown() then return end
    local text = FormatTime()
    if timeFrame.lastText == text then return end
    timeFrame.lastText = text

    timeFrame.text:SetText(text)
    local width = timeFrame.text:GetStringWidth() + 20
    if not timeFrame.lastWidth or math.abs(timeFrame.lastWidth - width) > 2 then
        timeFrame:SetWidth(width)
        timeFrame.lastWidth = width
    end
end

local function IsMoveModifierDown()
    local modifier = WT.DB.TimeWidget.MoveModifier or "ALT"
    return (modifier == "SHIFT" and IsShiftKeyDown()) or (modifier == "CTRL" and IsControlKeyDown())
        or (modifier == "ALT" and IsAltKeyDown())
end

local function SavePosition(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", _G["WT_UIContainer"], "BOTTOMLEFT", left, top)
    WT.DB.Internal.Positions = WT.DB.Internal.Positions or {}
    WT.DB.Internal.Positions[POSITION_KEY] = {
        point = "TOPLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", xOfs = left, yOfs = top,
    }
end

local function OnClick(self, button)
    if self.isMoving then return end
    -- Opening Blizzard panels from addon code is not allowed in combat
    if InCombatLockdown() then
        WT.Utils.Logger:Warn(WT.L.MSG_COMBAT_BLOCK)
        return
    end
    if button == "LeftButton" then
        if ToggleCalendar then ToggleCalendar() end
    elseif button == "RightButton" then
        if ToggleTimeManager then
            -- Retail: always available (bootstrap file of the load-on-demand Blizzard_TimeManager)
            ToggleTimeManager()
        elseif C_AddOns and C_AddOns.LoadAddOn then
            -- Clients without the bootstrap (e.g. WoW Forever)
            C_AddOns.LoadAddOn("Blizzard_TimeManager")
            if TimeManager_Toggle then TimeManager_Toggle() end
        end
    end
end

local function CreateWidget()
    local frame = CreateFrame("Button", "WTTimeWidget", _G["WT_UIContainer"], "BackdropTemplate")
    frame:SetSize(80, 24)
    frame.ignoreInLayout = true
    frame.ignoreFramePositionManager = true

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)

    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })

    frame:RegisterForClicks("AnyUp")
    frame:SetScript("OnClick", OnClick)

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if WT.DB.TimeWidget.Movable and IsMoveModifierDown() then
            self.isMoving = true
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
        -- Let the click that ends the drag pass before clicks work again
        C_Timer.After(0, function() self.isMoving = nil end)
    end)
    return frame
end

local function ApplyStyle()
    local db = WT.DB.TimeWidget
    local container = _G["WT_UIContainer"]

    timeFrame:SetFrameStrata(db.Strata or "MEDIUM")
    timeFrame:SetMovable(db.Movable and true or false)
    -- Mouse is always enabled so the calendar / clock settings can be opened by clicking
    timeFrame:EnableMouse(true)

    local fontPath = (WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", db.Font)) or "Fonts\\FRIZQT__.TTF"
    local size = db.FontSize or 12
    local outline = (db.FontOutline == "NONE") and "" or (db.FontOutline or "OUTLINE")
    timeFrame.text:SetFont(fontPath, size, outline)
    timeFrame:SetHeight(size + 14)

    if db.Background then
        local bg = type(db.BgColor) == "table" and db.BgColor or {}
        timeFrame:SetBackdropColor(bg.r or 0, bg.g or 0, bg.b or 0, bg.a or 0.8)
    else
        timeFrame:SetBackdropColor(0, 0, 0, 0)
    end
    if db.Border then
        local bc = type(db.BorderColor) == "table" and db.BorderColor or {}
        timeFrame:SetBackdropBorderColor(bc.r or 1, bc.g or 1, bc.b or 1, bc.a or 1)
    else
        timeFrame:SetBackdropBorderColor(0, 0, 0, 0)
    end

    timeFrame:ClearAllPoints()
    local pos = WT.DB.Internal.Positions and WT.DB.Internal.Positions[POSITION_KEY]
    if pos then
        timeFrame:SetPoint(pos.point, container, pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        timeFrame:SetPoint("TOP", container, "TOP", 0, -20)
    end
end

--- Applies the current settings. Called on login and whenever an option changes.
function Module:Refresh()
    if not IsWanted() then
        if timeFrame then timeFrame:Hide() end
        self:UnregisterOnUpdate(UpdateTime)
        return
    end

    timeFrame = timeFrame or CreateWidget()
    ApplyStyle()
    timeFrame.lastText = nil
    timeFrame:Show()
    -- Re-registering only updates the interval
    self:RegisterOnUpdate(UpdateTime, WT.DB.TimeWidget.ShowSeconds and 0.2 or 1.0)
    UpdateTime()
end

function Module:Preview()
    if isPreview then return end
    isPreview = true
    self:Refresh()
    C_Timer.After(10, function()
        isPreview = false
        self:Refresh()
    end)
end

function Module:OnEnable()
    self:Refresh()
    -- Follow changes made in Blizzard's clock settings
    self:RegisterEvent("CVAR_UPDATE", function(_, cvar)
        if cvar == CVAR_MILITARY or cvar == CVAR_LOCAL then
            if timeFrame then timeFrame.lastText = nil end
            UpdateTime()
        end
    end)
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
    local function Refresh() self:Refresh() end

    panel:CreateTitle(builder, WT.L.CATEGORY_TIMEWIDGET)
    AddDescription(WT.L.OPT_DESC_MODULE_TIMEWIDGET)

    panel:CreateTitle(builder, WT.L.GROUP_TW_BEHAVIOR)
    AddDescription(WT.L.OPT_DESC_GROUP_TW_BEHAVIOR)

    local showInit = panel:CreateCheckbox(builder, WT.L.OPT_TW_SHOW, WT.L.OPT_DESC_TW_SHOW, "TimeWidget", "Show", Refresh)
    panel:CreateCheckbox(builder, WT.L.OPT_TW_SHOW_SECONDS, WT.L.OPT_DESC_TW_SHOW_SECONDS, "TimeWidget", "ShowSeconds", Refresh, showInit)
    panel:CreateCheckbox(builder, WT.L.OPT_TW_SUFFIX_UHR, WT.L.OPT_DESC_TW_SUFFIX_UHR, "TimeWidget", "SuffixUhr", Refresh, showInit)

    local dateInit = panel:CreateCheckbox(builder, WT.L.OPT_TW_SHOW_DATE, WT.L.OPT_DESC_TW_SHOW_DATE, "TimeWidget", "ShowDate", Refresh, showInit)
    -- Labels are example dates, not translatable text
    local dateFormats = {
        { value = "%d.%m.%Y", label = "31.12.2026" },
        { value = "%Y-%m-%d", label = "2026-12-31" },
        { value = "%m/%d/%Y", label = "12/31/2026" },
        { value = "%d. %b", label = "31. Dec" },
    }
    panel:CreateDropdown(builder, WT.L.OPT_TW_DATE_FORMAT, WT.L.OPT_DESC_TW_DATE_FORMAT, "TimeWidget", "DateFormat", dateFormats, Refresh, dateInit)

    panel:CreateTitle(builder, WT.L.GROUP_TW_APPEARANCE)
    AddDescription(WT.L.OPT_DESC_GROUP_TW_APPEARANCE)

    panel:CreateButton(builder, WT.L.OPT_TW_TEST, WT.L.BTN_TEST, WT.L.OPT_DESC_TW_TEST, function() self:Preview() end)
    builder:AddSpace(10)

    local moveInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_MOVABLE, WT.L.OPT_DESC_SW_MOVABLE, "TimeWidget", "Movable", Refresh, showInit)
    local modifiers = { { value = "ALT", label = "ALT" }, { value = "CTRL", label = "CTRL" }, { value = "SHIFT", label = "SHIFT" } }
    panel:CreateDropdown(builder, WT.L.OPT_SW_MOVE_MODIFIER, WT.L.OPT_DESC_SW_MOVE_MODIFIER, "TimeWidget", "MoveModifier", modifiers, nil, moveInit)
    panel:CreateStrataDropdown(builder, WT.L.OPT_STRATA, WT.L.OPT_DESC_STRATA, "TimeWidget", "Strata", Refresh, showInit)

    if WT.Utils.SharedMedia then
        panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "TimeWidget", "Font", WT.Utils.SharedMedia:GetOptions("font"), Refresh, showInit)
    end
    panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "TimeWidget", "FontSize", 8, 36, 1, Refresh, showInit)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "TimeWidget", "FontOutline", Refresh, showInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_TEXT, WT.L.OPT_DESC_COLOR_TEXT, "TimeWidget", "TextColor", true, showInit, Refresh)

    local sepInit = panel:CreateEditBox(builder, WT.L.OPT_SEPARATOR, WT.L.OPT_DESC_SEPARATOR, "TimeWidget", "Separator", showInit, Refresh)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_SEP, WT.L.OPT_DESC_COLOR_SEP, "TimeWidget", "SeparatorColor", true, sepInit, Refresh)

    local bgInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_BACKGROUND, WT.L.OPT_DESC_SW_BACKGROUND, "TimeWidget", "Background", Refresh, showInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BG, WT.L.OPT_DESC_COLOR_BG, "TimeWidget", "BgColor", true, bgInit, Refresh)

    local borderInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_BORDER, WT.L.OPT_DESC_SW_BORDER, "TimeWidget", "Border", Refresh, showInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BORDER, WT.L.OPT_DESC_COLOR_BORDER, "TimeWidget", "BorderColor", true, borderInit, Refresh)
end
