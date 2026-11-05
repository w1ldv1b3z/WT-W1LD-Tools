local _, WT = ...

-- ============================================================================
-- SOCIAL WIDGET
-- ============================================================================
-- A small on-screen counter for online guild members and friends, with a detailed
-- hover tooltip (see SocialWidget_Tooltip.lua). Opt-in: nothing is created, registered
-- or requested until "Show Guild" or "Show Friends" is enabled. Turning both off hides
-- the widget and stops all events and roster requests.
-- Left-click opens the friends list, right-click the guild window.

local Module = WT:NewModule("SocialWidget")

local tostring = tostring
local table_concat = table.concat
local wipe = wipe

local SafeNum = WT.Utils.Safety.SafeNum

local POSITION_KEY = "WTSocialWidget"
local ROSTER_POLL_INTERVAL = 30 -- seconds; the guild roster only refreshes when requested
local UPDATE_DELAY = 0.5        -- social events often fire in bursts
local PREVIEW_DURATION = 10

-- Events that change one of the counters
local UPDATE_EVENTS = {
    "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
    "BN_CONNECTED", "BN_DISCONNECTED", "FRIENDLIST_UPDATE",
    "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE",
}

local widgetFrame
local widgetParts = {}
local isPreview = false
local updateTimer

local function IsWanted()
    local db = WT.DB.SocialWidget
    return db.ShowGuild or db.ShowBNet or isPreview
end

--- Online guild members, or nil when the player has no guild.
local function GetGuildOnline()
    if not IsInGuild() or not GetNumGuildMembers then return nil end
    local _, online = GetNumGuildMembers()
    return SafeNum(online) or 0
end

--- Online Battle.net friends (any game or the app) plus online character friends.
local function GetFriendsOnline()
    local count = 0
    if BNGetNumFriends then
        local _, bnetOnline = BNGetNumFriends()
        count = count + (SafeNum(bnetOnline) or 0)
    end
    if C_FriendList and C_FriendList.GetNumOnlineFriends then
        count = count + (SafeNum(C_FriendList.GetNumOnlineFriends()) or 0)
    end
    return count
end

local function GetLabels(style)
    if style == "ICON" then
        return "|TInterface\\Icons\\INV_Shirt_GuildTabard_01:14:14:0:-1|t",
            "|TInterface\\FriendsFrame\\PlusManz-BattleNet:14:14:0:-1|t"
    elseif style == "SHORT" then
        return tostring(WT.L.SW_GUILD_SHORT), tostring(WT.L.SW_FRIENDS_SHORT)
    end
    return tostring(WT.L.SW_GUILD), tostring(WT.L.SW_FRIENDS)
end

local function UpdateText()
    if not widgetFrame or not widgetFrame:IsShown() then return end
    local db = WT.DB.SocialWidget

    local labelGuild, labelFriends = GetLabels(db.DisplayStyle)
    local colText = "|c" .. WT.Colors:GetHex(db.TextColor, 1, 1, 1)
    local colValue = "|c" .. WT.Colors:GetHex(db.ValueColor, 1, 0.82, 0)

    wipe(widgetParts)
    if db.ShowGuild or isPreview then
        local online = isPreview and 14 or GetGuildOnline()
        local value = online and tostring(online) or tostring(WT.L.SW_NO_GUILD)
        widgetParts[#widgetParts + 1] = colText .. labelGuild .. "|r " .. colValue .. value .. "|r"
    end
    if db.ShowBNet or isPreview then
        local online = isPreview and 5 or GetFriendsOnline()
        widgetParts[#widgetParts + 1] = colText .. labelFriends .. "|r " .. colValue .. online .. "|r"
    end

    local separator = db.Vertical and "\n"
        or ("  |c" .. WT.Colors:GetHex(db.SeparatorColor, 0.5, 0.5, 0.5) .. "|||r  ")
    local text = table_concat(widgetParts, separator)
    if widgetFrame.lastText == text then return end
    widgetFrame.lastText = text

    widgetFrame.text:SetText(text)
    local width = widgetFrame.text:GetStringWidth() + 24
    local height = widgetFrame.text:GetStringHeight() + 10
    if not widgetFrame.lastWidth or math.abs(widgetFrame.lastWidth - width) > 2
        or not widgetFrame.lastHeight or math.abs(widgetFrame.lastHeight - height) > 2 then
        widgetFrame:SetSize(width, height)
        widgetFrame.lastWidth, widgetFrame.lastHeight = width, height
    end
end

local function ScheduleUpdate()
    if updateTimer then updateTimer:Cancel() end
    updateTimer = C_Timer.NewTimer(UPDATE_DELAY, function()
        updateTimer = nil
        UpdateText()
    end)
end

--- Asks the server for fresh guild / friend data. The answer arrives as
--- GUILD_ROSTER_UPDATE / FRIENDLIST_UPDATE and updates the widget.
local function RequestData()
    local db = WT.DB.SocialWidget
    if db.ShowGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
    if db.ShowBNet and C_FriendList and C_FriendList.ShowFriends then
        C_FriendList.ShowFriends()
    end
end

local function PollGuildRoster()
    if WT.DB.SocialWidget.ShowGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
end

local function OnEnteringWorld()
    C_Timer.After(3, function()
        if not IsWanted() then return end
        RequestData()
        UpdateText()
    end)
end

-- Re-evaluates the modifier key requirement of the tooltip while hovering
local function OnModifierChanged()
    if widgetFrame and widgetFrame:IsMouseOver() then
        Module:ShowDetailedTooltip(widgetFrame)
    end
end

local function HideTooltip()
    local tooltip = _G["WTSocialTooltip"]
    if tooltip and tooltip:GetOwner() == widgetFrame then tooltip:Hide() end
end

local function IsMoveModifierDown()
    local modifier = WT.DB.SocialWidget.MoveModifier or "ALT"
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
    local toggleFriends = _G["ToggleFriendsFrame"]
    if button == "LeftButton" then
        if toggleFriends then toggleFriends(1) end
    elseif button == "RightButton" and IsInGuild() then
        if ToggleGuildFrame then
            ToggleGuildFrame()
        elseif toggleFriends then
            toggleFriends(3)
        end
    end
end

local function CreateWidget()
    local frame = CreateFrame("Button", "WTSocialWidget", _G["WT_UIContainer"], "BackdropTemplate")
    frame:SetSize(100, 24)
    frame.ignoreInLayout = true
    frame.ignoreFramePositionManager = true

    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.text:SetPoint("LEFT", frame, "LEFT", 12, 0)
    frame.text:SetJustifyH("LEFT")

    frame:RegisterForClicks("AnyUp")
    frame:SetScript("OnClick", OnClick)

    frame:SetScript("OnEnter", function(self)
        Module:RegisterEvent("MODIFIER_STATE_CHANGED", OnModifierChanged)
        Module:ShowDetailedTooltip(self)
    end)
    frame:SetScript("OnLeave", function(self)
        Module:UnregisterEvent("MODIFIER_STATE_CHANGED", OnModifierChanged)
        Module:ReleaseTooltip(self)
    end)

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if WT.DB.SocialWidget.Movable and IsMoveModifierDown() then
            HideTooltip()
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
    local db = WT.DB.SocialWidget
    local container = _G["WT_UIContainer"]

    widgetFrame:SetFrameStrata(db.Strata or "MEDIUM")
    widgetFrame:SetMovable(db.Movable and true or false)
    widgetFrame:SetScale(db.Scale or 1.0)

    local fontPath = (WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", db.Font)) or "Fonts\\FRIZQT__.TTF"
    local outline = (db.FontOutline == "NONE") and "" or (db.FontOutline or "OUTLINE")
    widgetFrame.text:SetFont(fontPath, db.FontSize or 10, outline)

    if db.Background then
        local bg = type(db.BgColor) == "table" and db.BgColor or {}
        widgetFrame:SetBackdropColor(bg.r or WT.Colors.STD_BG_R, bg.g or WT.Colors.STD_BG_G,
            bg.b or WT.Colors.STD_BG_B, bg.a or WT.Colors.STD_BG_A)
    else
        widgetFrame:SetBackdropColor(0, 0, 0, 0)
    end
    if db.Border then
        local bc = type(db.BorderColor) == "table" and db.BorderColor or {}
        widgetFrame:SetBackdropBorderColor(bc.r or 1, bc.g or 1, bc.b or 1, bc.a or 1)
    else
        widgetFrame:SetBackdropBorderColor(0, 0, 0, 0)
    end

    widgetFrame:ClearAllPoints()
    local pos = WT.DB.Internal.Positions and WT.DB.Internal.Positions[POSITION_KEY]
    if pos then
        widgetFrame:SetPoint(pos.point, container, pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        widgetFrame:SetPoint("TOPLEFT", container, "TOP", -50, -25)
    end
end

local function RegisterDataEvents(enable)
    for _, event in ipairs(UPDATE_EVENTS) do
        if enable then
            Module:RegisterEvent(event, ScheduleUpdate)
        else
            Module:UnregisterEvent(event, ScheduleUpdate)
        end
    end
    if enable then
        Module:RegisterEvent("PLAYER_ENTERING_WORLD", OnEnteringWorld)
    else
        Module:UnregisterEvent("PLAYER_ENTERING_WORLD", OnEnteringWorld)
    end
end

--- Applies the current settings. Called on login and whenever an option changes.
function Module:Refresh()
    if not IsWanted() then
        if widgetFrame then widgetFrame:Hide() end
        HideTooltip()
        RegisterDataEvents(false)
        self:UnregisterEvent("MODIFIER_STATE_CHANGED", OnModifierChanged)
        self:UnregisterOnUpdate(PollGuildRoster)
        if updateTimer then updateTimer:Cancel(); updateTimer = nil end
        return
    end

    local wasShown = widgetFrame and widgetFrame:IsShown()
    widgetFrame = widgetFrame or CreateWidget()
    ApplyStyle()
    widgetFrame.lastText = nil
    widgetFrame:Show()

    RegisterDataEvents(true)
    if WT.DB.SocialWidget.ShowGuild then
        self:RegisterOnUpdate(PollGuildRoster, ROSTER_POLL_INTERVAL)
    else
        self:UnregisterOnUpdate(PollGuildRoster)
    end
    -- Fresh data when the widget appears (login, or an option was just turned on)
    if not wasShown then RequestData() end
    UpdateText()
end

function Module:Preview()
    if isPreview then return end
    isPreview = true
    self:Refresh()
    C_Timer.After(PREVIEW_DURATION, function()
        isPreview = false
        self:Refresh()
    end)
end

function Module:OnEnable()
    self:Refresh()
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

    panel:CreateTitle(builder, WT.L.CATEGORY_SOCIALWIDGET)
    AddDescription(WT.L.OPT_DESC_MODULE_SOCIALWIDGET)

    panel:CreateTitle(builder, WT.L.GROUP_SOCIALWIDGET_DISPLAY)
    AddDescription(WT.L.OPT_DESC_GROUP_SW_DISPLAY)

    panel:CreateButton(builder, WT.L.OPT_SW_TEST, WT.L.BTN_TEST, WT.L.OPT_DESC_SW_TEST, function() self:Preview() end)
    builder:AddSpace(10)

    panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_GUILD, WT.L.OPT_DESC_SW_SHOW_GUILD, "SocialWidget", "ShowGuild", Refresh)
    panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_BNET, WT.L.OPT_DESC_SW_SHOW_BNET, "SocialWidget", "ShowBNet", Refresh)

    local moveInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_MOVABLE, WT.L.OPT_DESC_SW_MOVABLE, "SocialWidget", "Movable", Refresh)
    local modifiers = { { value = "ALT", label = "ALT" }, { value = "CTRL", label = "CTRL" }, { value = "SHIFT", label = "SHIFT" } }
    panel:CreateDropdown(builder, WT.L.OPT_SW_MOVE_MODIFIER, WT.L.OPT_DESC_SW_MOVE_MODIFIER, "SocialWidget", "MoveModifier", modifiers, nil, moveInit)

    local styleOptions = {
        { value = "TEXT",  label = WT.L.SW_STYLE_TEXT },
        { value = "SHORT", label = WT.L.SW_STYLE_SHORT },
        { value = "ICON",  label = WT.L.SW_STYLE_ICON },
    }
    panel:CreateDropdown(builder, WT.L.OPT_SW_DISPLAY_STYLE, WT.L.OPT_DESC_SW_DISPLAY_STYLE, "SocialWidget", "DisplayStyle", styleOptions, Refresh)
    panel:CreateStrataDropdown(builder, WT.L.OPT_STRATA, WT.L.OPT_DESC_STRATA, "SocialWidget", "Strata", Refresh)
    panel:CreateCheckbox(builder, WT.L.OPT_SW_VERTICAL, WT.L.OPT_DESC_SW_VERTICAL, "SocialWidget", "Vertical", Refresh)

    if WT.Utils.SharedMedia then
        panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "SocialWidget", "Font", WT.Utils.SharedMedia:GetOptions("font"), Refresh)
    end
    panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "SocialWidget", "FontSize", 8, 24, 1, Refresh)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "SocialWidget", "FontOutline", Refresh)

    local bgInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_BACKGROUND, WT.L.OPT_DESC_SW_BACKGROUND, "SocialWidget", "Background", Refresh)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BG, WT.L.OPT_DESC_COLOR_BG, "SocialWidget", "BgColor", true, bgInit, Refresh)
    local borderInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_BORDER, WT.L.OPT_DESC_SW_BORDER, "SocialWidget", "Border", Refresh)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BORDER, WT.L.OPT_DESC_COLOR_BORDER, "SocialWidget", "BorderColor", true, borderInit, Refresh)

    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_TEXT, WT.L.OPT_DESC_COLOR_TEXT, "SocialWidget", "TextColor", true, nil, Refresh)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_SEP, WT.L.OPT_DESC_COLOR_SEP, "SocialWidget", "SeparatorColor", true, nil, Refresh)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ValueColor", true, nil, Refresh)

    panel:CreateSlider(builder, WT.L.OPT_SW_SCALE, WT.L.OPT_DESC_SW_SCALE, "SocialWidget", "Scale", 0.5, 2.0, 0.1, Refresh)

    panel:CreateTitle(builder, WT.L.GROUP_SOCIALWIDGET_TOOLTIP_BEHAVIOR)
    AddDescription(WT.L.OPT_DESC_GROUP_SW_TOOLTIP_BEHAVIOR)

    local tooltipModifiers = {
        { value = "NONE", label = WT.L.DD_ALWAYS }, { value = "ALT", label = "ALT" },
        { value = "CTRL", label = "CTRL" }, { value = "SHIFT", label = "SHIFT" },
    }
    panel:CreateDropdown(builder, WT.L.OPT_SW_TT_MODIFIER, WT.L.OPT_DESC_SW_TT_MODIFIER, "SocialWidget", "TooltipModifier", tooltipModifiers)
    panel:CreateCheckbox(builder, WT.L.OPT_SW_HIDE_TOOLTIP_COMBAT, WT.L.OPT_DESC_SW_HIDE_TOOLTIP_COMBAT, "SocialWidget", "HideTooltipCombat")
    panel:CreateCheckbox(builder, WT.L.OPT_SW_CLICK_WHISPER, WT.L.OPT_DESC_SW_CLICK_WHISPER, "SocialWidget", "ClickToWhisper")

    local sortOptions = {
        { value = "NAME",  label = WT.L.SW_SORT_NAME },
        { value = "LEVEL", label = WT.L.SW_SORT_LEVEL },
        { value = "ZONE",  label = WT.L.SW_SORT_ZONE },
    }
    panel:CreateDropdown(builder, WT.L.OPT_SW_SORT, WT.L.OPT_DESC_SW_SORT, "SocialWidget", "SortBy", sortOptions)
    panel:CreateSlider(builder, WT.L.OPT_SW_MAX_ENTRIES, WT.L.OPT_DESC_SW_MAX_ENTRIES, "SocialWidget", "MaxEntries", 0, 50, 5)

    panel:CreateTitle(builder, WT.L.GROUP_SOCIALWIDGET_TOOLTIP)
    AddDescription(WT.L.OPT_DESC_GROUP_SW_TOOLTIP)
    local levelInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_LEVEL, WT.L.OPT_DESC_SW_SHOW_LEVEL, "SocialWidget", "ShowLevel")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LEVEL, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColLevel", true, levelInit)
    local raceInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_RACE, WT.L.OPT_DESC_SW_SHOW_RACE, "SocialWidget", "ShowRace")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_RACE, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColRace", true, raceInit)
    local genderInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_GENDER, WT.L.OPT_DESC_SW_SHOW_GENDER, "SocialWidget", "ShowGender")
    panel:CreateColorPicker(builder, WT.L.TT_COLOR_MALE, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColMale", false, genderInit)
    panel:CreateColorPicker(builder, WT.L.TT_COLOR_FEMALE, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColFemale", false, genderInit)
    panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_FACTION, WT.L.OPT_DESC_SW_SHOW_FACTION, "SocialWidget", "ShowFaction")
    local locationInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_LOCATION, WT.L.OPT_DESC_SW_SHOW_LOCATION, "SocialWidget", "ShowLocation")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LOC, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColLocation", true, locationInit)
    local realmInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_REALM, WT.L.OPT_DESC_SW_SHOW_REALM, "SocialWidget", "ShowRealm")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_REALM, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColRealm", true, realmInit)
    local statusInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_STATUS, WT.L.OPT_DESC_SW_SHOW_STATUS, "SocialWidget", "ShowStatus")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_AFK, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColAFK", true, statusInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_DND, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColDND", true, statusInit)
    local noteInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_NOTE, WT.L.OPT_DESC_SW_SHOW_NOTE, "SocialWidget", "ShowNote")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_NOTE, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColNote", true, noteInit)
    panel:CreateCheckbox(builder, WT.L.OPT_SW_MARK_GROUP, WT.L.OPT_DESC_SW_MARK_GROUP, "SocialWidget", "MarkGroupMembers")
    panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_MOBILE, WT.L.OPT_DESC_SW_SHOW_MOBILE, "SocialWidget", "ShowMobile")
end
