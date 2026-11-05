local _, WT = ...

WT.Modules.SocialWidget = {}
local Module = WT.Modules.SocialWidget

local widgetFrame
local widgetParts = {}

local isPreviewMode = false

local tostring = tostring
local string_format = string.format
local table_insert = table.insert
local table_concat = table.concat
local wipe = wipe

local SafeNum = WT.Utils.Safety.SafeNum

local GetNumGuildMembers = GetNumGuildMembers or (C_GuildInfo and C_GuildInfo.GetNumGuildMembers) or
    function() return 0 end

local function GetBNetFriendCount()
    if C_BattleNet and C_BattleNet.GetFriendCount then return C_BattleNet.GetFriendCount() end
    if BNGetNumFriends then return BNGetNumFriends() end
    return 0
end

local function UpdateWidgetText()
    if not widgetFrame or not WT.DB.Modules.SocialWidget then return end
    if not WT.DB.SocialWidget then return end

    if InCombatLockdown() then
        WT.Core.CombatQueue:Add("SocialWidgetUpdate", true, UpdateWidgetText)
        return
    end

    wipe(widgetParts)

    local style = WT.DB.SocialWidget.DisplayStyle or "TEXT"
    local strGuild = tostring(WT.L.SW_GUILD)
    local strFriends = tostring(WT.L.SW_FRIENDS)

    if style == "ICON" then
        strGuild = "|TInterface\\Icons\\INV_Shirt_GuildTabard_01:14:14:0:-1|t"
        strFriends = "|TInterface\\FriendsFrame\\PlusManz-BattleNet:14:14:0:-1|t"
    elseif style == "SHORT" then
        strGuild = tostring(WT.L.SW_GUILD_SHORT)
        strFriends = tostring(WT.L.SW_FRIENDS_SHORT)
    end

    local colT = "|c" .. WT.Colors:GetHex(WT.DB.SocialWidget.TextColor, 1, 1, 1)
    local colV = "|c" .. WT.Colors:GetHex(WT.DB.SocialWidget.ValueColor, 1, 0.82, 0)
    local colS = "|c" .. WT.Colors:GetHex(WT.DB.SocialWidget.SeparatorColor, 0.5, 0.5, 0.5)

    if WT.DB.SocialWidget.ShowGuild or isPreviewMode then
        local okG, numGuildRaw, numGuildOnlineRaw = pcall(GetNumGuildMembers)
        local numGuild = okG and SafeNum(numGuildRaw) or 0
        local numGuildOnline = okG and SafeNum(numGuildOnlineRaw) or 0
        if isPreviewMode then
            numGuild = 100; numGuildOnline = 14
        end
        if numGuild > 0 then
            table_insert(widgetParts, colT .. strGuild .. "|r " .. colV .. numGuildOnline .. "|r")
        else
            table_insert(widgetParts,
                colT .. strGuild .. "|r " .. colV .. tostring(WT.L.SW_NO_GUILD) .. "|r")
        end
    end

    if WT.DB.SocialWidget.ShowBNet or isPreviewMode then
        local bnetOnline = 0
        local okBN, rawBNet = pcall(GetBNetFriendCount)
        local numBNet = okBN and SafeNum(rawBNet) or 0
        if numBNet > 0 then
            for i = 1, numBNet do
                local okB, accountInfo = false, nil
                if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
                    okB, accountInfo = pcall(C_BattleNet.GetFriendAccountInfo, i)
                end
                if okB and accountInfo then
                    local isOnline = accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline
                    if isOnline then
                        bnetOnline = bnetOnline + 1
                    end
                elseif _G["BNGetFriendInfo"] then
                    local okBNInfo, _, _, _, _, _, _, isOnline = pcall(_G["BNGetFriendInfo"], i)
                    if okBNInfo and isOnline then
                        bnetOnline = bnetOnline + 1
                    end
                end
            end
        end

        local wowOnline = 0
        local okF, numFriendsRaw = pcall(C_FriendList.GetNumFriends)
        local numFriends = okF and SafeNum(numFriendsRaw) or 0
        if numFriends > 0 then
            for i = 1, numFriends do
                local okI, friendInfo = pcall(C_FriendList.GetFriendInfoByIndex, i)
                if okI and friendInfo and friendInfo.connected then
                    wowOnline = wowOnline + 1
                end
            end
        end

        local totalFriends = bnetOnline + wowOnline
        if isPreviewMode then totalFriends = 5 end
        table_insert(widgetParts, colT .. strFriends .. "|r " .. colV .. totalFriends .. "|r")
    end

    if #widgetParts > 0 then
        local sep = WT.DB.SocialWidget.Vertical and "\n" or ("  " .. colS .. "|||r  ")
        local finalStr = table_concat(widgetParts, sep)

        if widgetFrame.wtLastText ~= finalStr then
            widgetFrame.text:SetText(finalStr)
            widgetFrame.wtLastText = finalStr

            local newWidth = widgetFrame.text:GetStringWidth() + 24
            local newHeight = widgetFrame.text:GetStringHeight() + 10
            if not widgetFrame.wtLastWidth or math.abs(widgetFrame.wtLastWidth - newWidth) > 2 or not widgetFrame.wtLastHeight or math.abs(widgetFrame.wtLastHeight - newHeight) > 2 then
                widgetFrame:SetWidth(newWidth)
                widgetFrame:SetHeight(newHeight)
                widgetFrame.wtLastWidth = newWidth
                widgetFrame.wtLastHeight = newHeight
            end
        end
        widgetFrame:Show()
    else
        widgetFrame:Hide()
    end
end

function Module:SetupWidget()
    if not widgetFrame then
        widgetFrame = CreateFrame("Button", "WTSocialWidget", _G["WT_UIContainer"], "BackdropTemplate")
        widgetFrame:SetFrameStrata(WT.DB.SocialWidget.Strata or "MEDIUM")

        widgetFrame.ignoreInLayout = true
        widgetFrame.ignoreFramePositionManager = true
        if widgetFrame.SetIsFramePositionManaged then pcall(function() widgetFrame:SetIsFramePositionManaged(false) end) end

        widgetFrame:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })

        widgetFrame.text = widgetFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        widgetFrame.text:SetPoint("LEFT", widgetFrame, "LEFT", 12, 0)
        widgetFrame.text:SetJustifyH("LEFT")

        widgetFrame:RegisterForClicks("AnyUp")

        widgetFrame:SetScript("OnClick", function(self, button)
            if self.wtIsMoving then return end
            if InCombatLockdown() then
                if WT.Utils and WT.Utils.Logger then
                    WT.Utils.Logger:Warn(WT.L.MSG_COMBAT_BLOCK)
                end
                return
            end
            if button == "LeftButton" then
                if _G["ToggleFriendsFrame"] then _G["ToggleFriendsFrame"](1) end
            elseif button == "RightButton" and IsInGuild() then
                if _G["ToggleGuildFrame"] then
                    _G["ToggleGuildFrame"]()
                elseif _G["ToggleFriendsFrame"] then
                    _G["ToggleFriendsFrame"](3)
                end
            end
        end)

        widgetFrame:SetScript("OnEnter", function(self)
            Module:ShowDetailedTooltip(self)
        end)

        widgetFrame:SetScript("OnLeave", function(self)
            if _G["WTSocialTooltip"] then _G["WTSocialTooltip"]:Hide() end
        end)

        widgetFrame:RegisterForDrag("LeftButton")
        widgetFrame:SetScript("OnDragStart", function(self)
            if InCombatLockdown() then return end
            local mod = WT.DB.SocialWidget.MoveModifier or "ALT"
            local canMove = false
            if mod == "SHIFT" then
                canMove = IsShiftKeyDown()
            elseif mod == "CTRL" then
                canMove = IsControlKeyDown()
            elseif mod == "ALT" then
                canMove = IsAltKeyDown()
            end
            if WT.DB.SocialWidget.Movable and canMove then
                if _G["WTSocialTooltip"] then _G["WTSocialTooltip"]:Hide() end; self:StartMoving()
            end
        end)
        widgetFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()

            local left = self:GetLeft()
            local top = self:GetTop()
            if left and top then
                self:ClearAllPoints()
                self:SetPoint("TOPLEFT", _G["WT_UIContainer"], "BOTTOMLEFT", left, top)
            end

            local p, _, rP, x, y = self:GetPoint()
            if not WT.DB.Internal.Positions then WT.DB.Internal.Positions = {} end
            WT.DB.Internal.Positions["WTSocialWidget"] = {
                point = p,
                relativeTo = "UIParent",
                relativePoint = rP,
                xOfs =
                    x,
                yOfs = y
            }
        end)

        local updateTimer
        local function DebounceUpdate()
            if updateTimer then updateTimer:Cancel() end
            updateTimer = C_Timer.NewTimer(0.5, UpdateWidgetText)
        end

        WT.Core.Events:Register("BN_FRIEND_INFO_CHANGED", DebounceUpdate)
        WT.Core.Events:Register("BN_FRIEND_ACCOUNT_ONLINE", DebounceUpdate)
        WT.Core.Events:Register("BN_FRIEND_ACCOUNT_OFFLINE", DebounceUpdate)
        WT.Core.Events:Register("BN_CONNECTED", DebounceUpdate)
        WT.Core.Events:Register("BN_DISCONNECTED", DebounceUpdate)
        WT.Core.Events:Register("FRIENDLIST_UPDATE", DebounceUpdate)
        WT.Core.Events:Register("GUILD_ROSTER_UPDATE", DebounceUpdate)
        WT.Core.Events:Register("PLAYER_GUILD_UPDATE", DebounceUpdate)

        WT.Core.Events:Register("PLAYER_ENTERING_WORLD", function()
            C_Timer.After(3, function()
                if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
                if C_FriendList and C_FriendList.ShowFriends then C_FriendList.ShowFriends() end
                UpdateWidgetText()
            end)
        end)

        WT.Core.Events:Register("MODIFIER_STATE_CHANGED", function()
            if widgetFrame and widgetFrame:IsMouseOver() then
                Module:ShowDetailedTooltip(widgetFrame)
            end
        end)

        -- Fallback polling timer (WoW's social events are notorious for failing to fire without manual updates)
        C_Timer.NewTicker(30, function()
            if not WT.DB.SocialWidget or not widgetFrame then return end
            if WT.DB.SocialWidget.ShowGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
                C_GuildInfo.GuildRoster()
            end
            if WT.DB.SocialWidget.ShowBNet and C_FriendList and C_FriendList.ShowFriends then
                C_FriendList.ShowFriends()
            end
            UpdateWidgetText()
        end)
    end

    widgetFrame:SetFrameStrata(WT.DB.SocialWidget.Strata or "MEDIUM")
    widgetFrame:SetMovable(WT.DB.SocialWidget.Movable)
    widgetFrame:SetScale(WT.DB.SocialWidget.Scale or 1.0)

    local fontKey = WT.DB.SocialWidget.Font or "Friz Quadrata TT"
    local fontPath = (WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", fontKey)) or
        "Fonts\\FRIZQT__.TTF"
    local size = WT.DB.SocialWidget.FontSize or 10
    local outline = (WT.DB.SocialWidget.FontOutline == "NONE") and "" or (WT.DB.SocialWidget.FontOutline or "OUTLINE")
    widgetFrame.text:SetFont(fontPath, size, outline)

    if WT.DB.SocialWidget.Background then
        local bg = WT.DB.SocialWidget.BgColor or
            { r = WT.Colors.STD_BG_R, g = WT.Colors.STD_BG_G, b = WT.Colors.STD_BG_B, a = WT.Colors.STD_BG_A }
        if type(bg) == "string" then
            bg = {
                r = WT.Colors.STD_BG_R,
                g = WT.Colors.STD_BG_G,
                b = WT.Colors.STD_BG_B,
                a =
                    WT.Colors.STD_BG_A
            }
        end
        widgetFrame:SetBackdropColor(bg.r or WT.Colors.STD_BG_R, bg.g or WT.Colors.STD_BG_G, bg.b or WT.Colors.STD_BG_B,
            bg.a or WT.Colors.STD_BG_A)
    else
        widgetFrame:SetBackdropColor(0, 0, 0, 0)
    end

    if WT.DB.SocialWidget.Border then
        local bord = WT.DB.SocialWidget.BorderColor or { r = 1, g = 1, b = 1, a = 1 }
        if type(bord) == "string" then bord = { r = 1, g = 1, b = 1, a = 1 } end
        widgetFrame:SetBackdropBorderColor(bord.r or 1, bord.g or 1, bord.b or 1, bord.a or 1)
    else
        widgetFrame:SetBackdropBorderColor(0, 0, 0, 0)
    end

    if WT.DB.Internal.Positions and WT.DB.Internal.Positions["WTSocialWidget"] then
        local pos = WT.DB.Internal.Positions["WTSocialWidget"]
        widgetFrame:ClearAllPoints()
        widgetFrame:SetPoint(pos.point, _G["WT_UIContainer"], pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        widgetFrame:ClearAllPoints()
        widgetFrame:SetPoint("TOPLEFT", _G["WT_UIContainer"], "TOP", -50, -25)
    end

    UpdateWidgetText()
end

function Module:PreviewWidget()
    if isPreviewMode then return end
    isPreviewMode = true
    UpdateWidgetText()
    C_Timer.After(10, function()
        isPreviewMode = false
        UpdateWidgetText()
    end)
end

function Module:Initialize()
    if not WT.DB.Modules.SocialWidget then
        if widgetFrame then widgetFrame:Hide() end
        return
    end
    self:SetupWidget()
end

WT.Core.Events:Register("PLAYER_LOGIN", function()
    Module:Initialize()
end)

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

    panel:CreateTitle(builder, WT.L.CATEGORY_SOCIALWIDGET)
    AddDescription(WT.L.OPT_DESC_MODULE_SOCIALWIDGET)

    panel:CreateTitle(builder, WT.L.GROUP_SOCIALWIDGET_DISPLAY)
    AddDescription(WT.L.OPT_DESC_GROUP_SW_DISPLAY)

    panel:CreateButton(builder, WT.L.OPT_SW_TEST, WT.L.BTN_TEST, WT.L.OPT_DESC_SW_TEST,
        function()
            self:PreviewWidget()
        end)
    builder:AddSpace(10)

    panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_GUILD, WT.L.OPT_DESC_SW_SHOW_GUILD, "SocialWidget", "ShowGuild",
        function() UpdateWidgetText() end)
    panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_BNET, WT.L.OPT_DESC_SW_SHOW_BNET, "SocialWidget", "ShowBNet",
        function() UpdateWidgetText() end)

    local moveInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_MOVABLE, WT.L.OPT_DESC_SW_MOVABLE, "SocialWidget",
        "Movable", function() self:SetupWidget() end)
    local modOptions = { { value = "ALT", label = "ALT" }, { value = "CTRL", label = "CTRL" }, { value = "SHIFT", label = "SHIFT" } }
    panel:CreateDropdown(builder, WT.L.OPT_SW_MOVE_MODIFIER, WT.L.OPT_DESC_SW_MOVE_MODIFIER, "SocialWidget",
        "MoveModifier", modOptions, nil, moveInit)

    local styleOptions = {
        { value = "TEXT",  label = WT.L.SW_STYLE_TEXT },
        { value = "SHORT", label = WT.L.SW_STYLE_SHORT },
        { value = "ICON",  label = WT.L.SW_STYLE_ICON }
    }
    panel:CreateDropdown(builder, WT.L.OPT_SW_DISPLAY_STYLE, WT.L.OPT_DESC_SW_DISPLAY_STYLE, "SocialWidget",
        "DisplayStyle", styleOptions, function() UpdateWidgetText() end)

    panel:CreateStrataDropdown(builder, WT.L.OPT_STRATA, WT.L.OPT_DESC_STRATA, "SocialWidget", "Strata",
        function() self:SetupWidget() end)
    local vertInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_VERTICAL, WT.L.OPT_DESC_SW_VERTICAL, "SocialWidget",
        "Vertical", function() UpdateWidgetText() end)
    if WT.Utils and WT.Utils.SharedMedia then
        panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "SocialWidget", "Font",
            WT.Utils.SharedMedia:GetOptions("font"), function() self:SetupWidget() end)
    end
    panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "SocialWidget", "FontSize", 8, 24, 1,
        function() self:SetupWidget() end)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "SocialWidget", "FontOutline",
        function() self:SetupWidget() end)

    local bgInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_BACKGROUND, WT.L.OPT_DESC_SW_BACKGROUND, "SocialWidget",
        "Background", function() self:SetupWidget() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BG, WT.L.OPT_DESC_COLOR_BG, "SocialWidget", "BgColor", true, bgInit,
        function() self:SetupWidget() end)
    local borderInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_BORDER, WT.L.OPT_DESC_SW_BORDER, "SocialWidget",
        "Border", function() self:SetupWidget() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BORDER, WT.L.OPT_DESC_COLOR_BORDER, "SocialWidget", "BorderColor",
        true, borderInit, function() self:SetupWidget() end)

    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_TEXT, WT.L.OPT_DESC_COLOR_TEXT, "SocialWidget", "TextColor", true,
        nil, function() UpdateWidgetText() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_SEP, WT.L.OPT_DESC_COLOR_SEP, "SocialWidget", "SeparatorColor", true,
        nil, function() UpdateWidgetText() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ValueColor", true,
        nil, function() UpdateWidgetText() end)

    panel:CreateSlider(builder, WT.L.OPT_SW_SCALE, WT.L.OPT_DESC_SW_SCALE, "SocialWidget", "Scale", 0.5, 2.0, 0.1,
        function() self:SetupWidget() end)

    panel:CreateTitle(builder, WT.L.GROUP_SOCIALWIDGET_TOOLTIP)
    AddDescription(WT.L.OPT_DESC_GROUP_SW_TOOLTIP)

    local lvlInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_LEVEL, WT.L.OPT_DESC_SW_SHOW_LEVEL, "SocialWidget",
        "ShowLevel")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColLevel", true,
        lvlInit)
    local rInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_RACE, WT.L.OPT_DESC_SW_SHOW_RACE, "SocialWidget",
        "ShowRace")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_RACE, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColRace", true,
        rInit)
    local genderInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_GENDER, WT.L.OPT_DESC_SW_SHOW_GENDER,
        "SocialWidget", "ShowGender")
    panel:CreateColorPicker(builder, WT.L.TT_COLOR_MALE, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColMale", false,
        genderInit)
    panel:CreateColorPicker(builder, WT.L.TT_COLOR_FEMALE, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColFemale", false,
        genderInit)
    panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_FACTION, WT.L.OPT_DESC_SW_SHOW_FACTION, "SocialWidget", "ShowFaction")
    local locInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_LOCATION, WT.L.OPT_DESC_SW_SHOW_LOCATION,
        "SocialWidget", "ShowLocation")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LOC, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColLocation", true,
        locInit)

    local realmInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_REALM, WT.L.OPT_DESC_SW_SHOW_REALM, "SocialWidget",
        "ShowRealm")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_REALM, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColRealm", true,
        realmInit)

    local statusInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_STATUS, WT.L.OPT_DESC_SW_SHOW_STATUS,
        "SocialWidget", "ShowStatus")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_AFK, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColAFK", true,
        statusInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_DND, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColDND", true,
        statusInit)

    local noteInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_SHOW_NOTE, WT.L.OPT_DESC_SW_SHOW_NOTE, "SocialWidget",
        "ShowNote")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_NOTE, WT.L.OPT_DESC_COLOR_VALUE, "SocialWidget", "ColNote", true,
        noteInit)

    local ttModOptions = { { value = "NONE", label = WT.L.DD_ALWAYS }, { value = "ALT", label = "ALT" }, { value = "CTRL", label = "CTRL" }, { value = "SHIFT", label = "SHIFT" } }
    panel:CreateDropdown(builder, WT.L.OPT_SW_TT_MODIFIER, WT.L.OPT_DESC_SW_TT_MODIFIER, "SocialWidget",
        "TooltipModifier", ttModOptions)
    panel:CreateCheckbox(builder, WT.L.OPT_SW_HIDE_TOOLTIP_COMBAT, WT.L.OPT_DESC_SW_HIDE_TOOLTIP_COMBAT, "SocialWidget",
        "HideTooltipCombat")
end
