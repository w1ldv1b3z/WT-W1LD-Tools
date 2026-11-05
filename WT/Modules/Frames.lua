local _, WT = ...

WT.Modules.Frames = {}
local Module = WT.Modules.Frames

local SafeNum = WT.Utils.Safety.SafeNum
local Unsecret = WT.Utils.Safety.Unsecret

function Module:SetupAlertHooks()
    if not self.alertData then self.alertData = setmetatable({}, { __mode = "k" }) end
    local alertData = self.alertData

    self:SetupAlertAnchor()
    self:SetupBNetAlertAnchor()
    self:SetupErrorAnchor()
    self:SetupRaidBossEmoteAnchor()

    local function HookAlertFrame(frame, dbKey, anchorFrame, hookMethod, extraHook)
        if not frame then return end
        local data = alertData[frame]
        if not data then
            data = {}; alertData[frame] = data
        end

        if not data.wtIsHooked then
            data.wtIsHooked = true

            local function ForcePos(isManualToggle)
                if not WT.DB.Frames[dbKey] then
                    if frame.SetIsFramePositionManaged then
                        pcall(function() frame:SetIsFramePositionManaged(true) end)
                    else
                        frame.ignoreFramePositionManager = nil
                    end

                    if isManualToggle then
                        frame:ClearAllPoints()
                        if EditModeManagerFrame and EditModeManagerFrame.UpdateSystemFrames then
                            EditModeManagerFrame:UpdateSystemFrames()
                        elseif frame.UpdateAnchors then
                            frame:UpdateAnchors()
                        elseif frame == BNToastFrame and _G["BNToastFrame_UpdateAnchor"] then
                            _G["BNToastFrame_UpdateAnchor"](BNToastFrame)
                        end
                    end
                    return
                end

                if frame.SetIsFramePositionManaged then
                    pcall(function() frame:SetIsFramePositionManaged(false) end)
                else
                    frame.ignoreFramePositionManager = true
                end
                frame:ClearAllPoints()
                frame:SetPoint("BOTTOM", anchorFrame, "BOTTOM", 0, 0)
            end

            data.ForcePos = ForcePos

            if hookMethod then
                hooksecurefunc(frame, hookMethod, function(self)
                    if not self.wtIsUpdating then
                        self.wtIsUpdating = true
                        ForcePos()
                        self.wtIsUpdating = false
                    end
                end)
            end

            if extraHook and _G[extraHook] then
                hooksecurefunc(extraHook, function()
                    if not frame.wtIsUpdating then
                        frame.wtIsUpdating = true
                        ForcePos()
                        frame.wtIsUpdating = false
                    end
                end)
            end

            C_Timer.After(0, ForcePos)
        end
    end

    HookAlertFrame(AlertFrame, "CustomAlerts", _G["WT_AlertAnchor"], "UpdateAnchors", "AlertFrame_FixAnchors")
    HookAlertFrame(EventToastManagerFrame, "CustomAlerts", _G["WT_AlertAnchor"], "SetPoint")
    HookAlertFrame(BNToastFrame, "CustomBNetAlerts", _G["WT_BNetAlertAnchor"], "SetPoint")
    HookAlertFrame(_G["RaidBossEmoteFrame"], "CustomRaidBoss", _G["WT_RaidBossEmoteAnchor"], "SetPoint")
    HookAlertFrame(UIErrorsFrame, "CustomErrors", _G["WT_ErrorAnchor"], "SetPoint")
end

local sysWidget
function Module:UpdateSystemWidget()
    if not WT.DB.Frames.SystemWidgetShow then
        if sysWidget then sysWidget:Hide() end
        return
    end

    if not sysWidget then
        sysWidget = CreateFrame("Button", "WTSystemWidget", _G["WT_UIContainer"], "BackdropTemplate")
        sysWidget:SetSize(80, 24)

        if sysWidget.SetIsFramePositionManaged then
            pcall(function() sysWidget:SetIsFramePositionManaged(false) end)
        else
            sysWidget.ignoreInLayout = true
            sysWidget.ignoreFramePositionManager = true
        end

        sysWidget.text = sysWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        sysWidget.text:SetPoint("LEFT", sysWidget, "LEFT", 10, 0)
        sysWidget.text:SetJustifyH("LEFT")

        sysWidget:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })

        sysWidget:RegisterForDrag("LeftButton")
        sysWidget:SetScript("OnDragStart", function(self)
            local mod = WT.DB.Frames.MoveModifier or "ALT"
            local canMove = (mod == "SHIFT" and IsShiftKeyDown()) or (mod == "CTRL" and IsControlKeyDown()) or
                (mod == "ALT" and IsAltKeyDown())
            if WT.DB.Frames.SystemWidgetMovable and canMove then self:StartMoving() end
        end)
        sysWidget:SetScript("OnDragStop", function(self)
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
                WT.DB.Internal.Positions["WTSystemWidget"] = {
                    point = Unsecret(rawP) or "TOPLEFT",
                    relativeTo =
                    "UIParent",
                    relativePoint = Unsecret(rawRP) or "BOTTOMLEFT",
                    xOfs = SafeNum(x),
                    yOfs = SafeNum(y)
                }
            end
        end)

        sysWidget.timer = 0
    end

    local tc = WT.Colors:GetHex(WT.DB.Frames.SystemWidgetTextColor, 1, 1, 1)
    local vc = tc
    local sc = WT.Colors:GetHex(WT.DB.Frames.SystemWidgetSeparatorColor, 0.5, 0.5, 0.5)
    local cg = WT.Colors:GetHex(WT.DB.Frames.SystemWidgetColorGood, 0, 1, 0)
    local cn = WT.Colors:GetHex(WT.DB.Frames.SystemWidgetColorNeutral, 1, 1, 0)
    local cb = WT.Colors:GetHex(WT.DB.Frames.SystemWidgetColorBad, 1, 0, 0)
    local sepStr = WT.DB.Frames.SystemWidgetSeparator or " | "
    local sepFormat = "|c" .. sc .. sepStr .. "|r"

    local fpsLabel = WT.DB.Frames.SystemWidgetFpsLabel or "FPS"
    local pingLabel = WT.DB.Frames.SystemWidgetPingLabel or "ms"
    local memLabel = WT.DB.Frames.SystemWidgetMemoryLabel or "MB"

    local fpsStr = fpsLabel ~= "" and (" |c" .. tc .. fpsLabel .. "|r") or ""
    local pingStr = pingLabel ~= "" and (" |c" .. tc .. pingLabel .. "|r") or ""
    local memStr = memLabel ~= "" and (" |c" .. tc .. memLabel .. "|r") or ""

    local showPing = WT.DB.Frames.SystemWidgetShowPing
    local showMem = WT.DB.Frames.SystemWidgetShowMemory
    local doColor = WT.DB.Frames.SystemWidgetColorizeValues
    local order = WT.DB.Frames.SystemWidgetOrder or "FPM"

    sysWidget:SetScript("OnUpdate", function(self, elapsed)
        self.timer = (self.timer or 0) + (elapsed or 0)
        local updateRate = SafeNum(WT.DB.Frames.SystemWidgetUpdateRate) or 0.5
        if self.timer > updateRate then
            self.timer = 0

            -- Performance protection: Reduces CPU load during the initial login lag
            if GetTime() - (WT.Core.LoadTime or 0) < 5 then
                self.text:SetText("|c" .. tc .. "...|r")
                self:SetWidth(self.text:GetStringWidth() + 20)
                return
            end

            local okFPS, rawFPS = pcall(GetFramerate)
            local sFPS = (okFPS and SafeNum(rawFPS)) or 0
            if sFPS ~= sFPS or sFPS == math.huge or sFPS == -math.huge then sFPS = 0 end -- NaN / Infinity check
            local fps = math.floor(sFPS + 0.5)

            local colorFPS = doColor and (fps >= 60 and cg or (fps >= 30 and cn or cb)) or vc

            local ping, colorPing = 0, vc
            if showPing then
                local okNet, _, _, lHome, lWorld = pcall(GetNetStats)
                local sHome = (okNet and SafeNum(lHome)) or 0
                local sWorld = (okNet and SafeNum(lWorld)) or 0
                if sHome ~= sHome or sHome == math.huge then sHome = 0 end
                if sWorld ~= sWorld or sWorld == math.huge then sWorld = 0 end
                ping = sWorld > 0 and sWorld or sHome
                colorPing = doColor and (ping <= 50 and cg or (ping <= 150 and cn or cb)) or vc
            end

            local mem, colorMem = 0, vc
            if showMem then
                local okMem, m = pcall(collectgarbage, "count")
                local sMem = (okMem and SafeNum(m)) or 0
                if sMem ~= sMem or sMem == math.huge then sMem = 0 end
                mem = sMem / 1024
                colorMem = doColor and (mem <= 100 and cg or (mem <= 250 and cn or cb)) or vc
            end

            local currentParts = {}
            for i = 1, string.len(order) do
                local char = string.sub(order, i, i)
                if char == "F" then
                    table.insert(currentParts, string.format("|c%s%d|r%s", colorFPS, fps, fpsStr))
                elseif char == "P" and showPing then
                    table.insert(currentParts, string.format("|c%s%d|r%s", colorPing, ping, pingStr))
                elseif char == "M" and showMem then
                    table.insert(currentParts, string.format("|c%s%.1f|r%s", colorMem, mem, memStr))
                end
            end

            local finalStr = table.concat(currentParts, sepFormat)
            if self.wtLastText ~= finalStr then
                self.text:SetText(finalStr)
                self.wtLastText = finalStr
                local newWidth = self.text:GetStringWidth() + 20
                if not self.wtLastWidth or math.abs(self.wtLastWidth - newWidth) > 2 then
                    self:SetWidth(newWidth)
                    self.wtLastWidth = newWidth
                end
            end
        end
    end)

    local fontKey = WT.DB.Frames.SystemWidgetFont or "Friz Quadrata TT"
    local fontPath = (WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", fontKey)) or
        "Fonts\\FRIZQT__.TTF"
    local size = WT.DB.Frames.SystemWidgetFontSize or 10
    local outline = (WT.DB.Frames.SystemWidgetFontOutline == "NONE") and "" or
        (WT.DB.Frames.SystemWidgetFontOutline or "OUTLINE")
    sysWidget.text:SetFont(fontPath, size, outline)
    sysWidget:SetHeight(size + 14)

    if WT.DB.Frames.SystemWidgetBackground then
        local bg = WT.DB.Frames.SystemWidgetBgColor or
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
        sysWidget:SetBackdropColor(bg.r or WT.Colors.STD_BG_R, bg.g or WT.Colors.STD_BG_G, bg.b or WT.Colors.STD_BG_B,
            bg.a or WT.Colors.STD_BG_A)
    else
        sysWidget:SetBackdropColor(0, 0, 0, 0)
    end

    if WT.DB.Frames.SystemWidgetBorder then
        local bord = WT.DB.Frames.SystemWidgetBorderColor or { r = 1, g = 1, b = 1, a = 1 }
        if type(bord) == "string" then bord = { r = 1, g = 1, b = 1, a = 1 } end
        sysWidget:SetBackdropBorderColor(bord.r or 1, bord.g or 1, bord.b or 1, bord.a or 1)
    else
        sysWidget:SetBackdropBorderColor(0, 0, 0, 0)
    end

    sysWidget:SetFrameStrata(WT.DB.Frames.SystemWidgetStrata or "MEDIUM")
    sysWidget:SetMovable(WT.DB.Frames.SystemWidgetMovable)
    sysWidget:EnableMouse(WT.DB.Frames.SystemWidgetMovable)

    if WT.DB.Internal.Positions and WT.DB.Internal.Positions["WTSystemWidget"] then
        local pos = WT.DB.Internal.Positions["WTSystemWidget"]
        sysWidget:ClearAllPoints()
        sysWidget:SetPoint(pos.point, _G["WT_UIContainer"], pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        sysWidget:ClearAllPoints()
        sysWidget:SetPoint("TOPLEFT", _G["WT_UIContainer"], "TOP", -50, -20)
    end

    sysWidget:Show()
end

function Module:Initialize()
    if not WT.DB.Modules.Frames then return end

    if self.SetupAlertHooks then self:SetupAlertHooks() end
    self:SetupMovableFrames()

    if self.FixBlizzardBugs then self:FixBlizzardBugs() end

    -- Hook into EditMode to safely pause the fader when configuring HUD
    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function()
            if BagsBar then self:ForceShowAndEnableMouse(BagsBar) end
            if StatusTrackingBarManager then self:ForceShowAndEnableMouse(StatusTrackingBarManager) end
        end, self)
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            self:UpdateXPBar()
            self:UpdateBagsBar()
        end, self)
    end

    self:UpdateExtendedCameraZoom(WT.DB.Frames.ExtendedCameraZoom)
    if WT.DB.Frames.SharpeningFilter then
        self:UpdateSharpening(true)
    end
    if type(WT.DB.Frames.ShaderFix) == "boolean" then
        self:UpdateShaderFix(WT.DB.Frames.ShaderFix)
    end

    if WT.DB.Frames.CombatCursor then
        self:UpdateCombatCursor()
    end

    self:UpdateSystemWidget()

    self:UpdateXPBar()
    self:UpdateBagsBar()
    self:UpdateTalkingHead()
    self:UpdateRaidBossEmoteFont()
    self:UpdateErrorFilter()
    self:SetupErrorBackground()
    if WT.DB.Frames.DisableLowHealthFlash then
        self:UpdateLowHealthFlash(true)
    end
    if WT.DB.Frames.DisableGlow then
        self:UpdateGlow(true)
    end
    if self.InitUnitFrames then self:InitUnitFrames() end
end

function Module:UpdateRaidBossEmoteFont()
    if not _G["RaidBossEmoteFrame"] then return end

    local fontKey = WT.DB.Frames.RaidBossFont or "Friz Quadrata TT"
    local fontPath = (WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", fontKey)) or
        "Fonts\\FRIZQT__.TTF"

    if RaidBossEmoteFrame.slot1 then
        local _, s1, o1 = RaidBossEmoteFrame.slot1:GetFont()
        RaidBossEmoteFrame.slot1:SetFont(fontPath, s1 or 24, o1 or "OUTLINE")
    end
    if RaidBossEmoteFrame.slot2 then
        local _, s2, o2 = RaidBossEmoteFrame.slot2:GetFont()
        RaidBossEmoteFrame.slot2:SetFont(fontPath, s2 or 24, o2 or "OUTLINE")
    end
end

local raidBossEmoteHooked = false
function Module:SetupRaidBossFontHook()
    if not raidBossEmoteHooked and RaidNotice_AddMessage then
        raidBossEmoteHooked = true
        hooksecurefunc("RaidNotice_AddMessage", function(noticeFrame)
            if noticeFrame == RaidBossEmoteFrame and WT.DB.Frames.CustomRaidBoss then
                Module:UpdateRaidBossEmoteFont()
            end
        end)
    end
end

WT.Core.Events:Register("PLAYER_LOGIN", function()
    Module:Initialize()
    Module:SetupRaidBossFontHook()
end)

function Module:UpdateCombatCleaner(isSilent)
    if WT.Core.CombatQueue:Add("CombatCleaner", isSilent, self.UpdateCombatCleaner, self, true) then return end

    if WT.DB.Frames.CombatCleaner then
        if MinimapCluster then RegisterStateDriver(MinimapCluster, "visibility", "[combat] hide; show") end
        if ObjectiveTrackerFrame then RegisterStateDriver(ObjectiveTrackerFrame, "visibility", "[combat] hide; show") end
    else
        if MinimapCluster then
            UnregisterStateDriver(MinimapCluster, "visibility"); MinimapCluster:Show()
        end
        if ObjectiveTrackerFrame then
            UnregisterStateDriver(ObjectiveTrackerFrame, "visibility"); ObjectiveTrackerFrame:Show()
        end
    end
end

function Module:UpdateQuestTrackerState()
    if not WT.DB.Frames.AutoQuestTracker or not ObjectiveTrackerFrame or type(ObjectiveTrackerFrame.SetCollapsed) ~= "function" then return end
    if InCombatLockdown() then return end

    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "scenario" or instanceType == "arena" or instanceType == "pvp") then
        ObjectiveTrackerFrame:SetCollapsed(true)
    else
        ObjectiveTrackerFrame:SetCollapsed(false)
    end
end

local function UpdateCombatState(isCombat)
    if not WT.DB.Modules.Frames then return end

    if WT.DB.Frames.CombatCursor and WT.Modules.Frames.UpdateCombatCursor then
        WT.Modules.Frames:UpdateCombatCursor(isCombat)
    end
end

local function UpdateMapMovingState(isMoving)
    if not (WT.DB.Modules.Frames and WT.DB.Frames.SmartMapFade and WorldMapFrame) then return end
    if isMoving then
        if WorldMapFrame:IsShown() then WorldMapFrame:SetAlpha(WT.DB.Frames.MapFadeAlpha or 0.5) end
    else
        WorldMapFrame:SetAlpha(1.0)
    end
end

WT.Core.Events:Register("PLAYER_REGEN_DISABLED", function() UpdateCombatState(true) end)
WT.Core.Events:Register("PLAYER_REGEN_ENABLED", function() UpdateCombatState(false) end)
WT.Core.Events:Register("PLAYER_STARTED_MOVING", function() UpdateMapMovingState(true) end)
WT.Core.Events:Register("PLAYER_STOPPED_MOVING", function() UpdateMapMovingState(false) end)
WT.Core.Events:Register("ZONE_CHANGED_NEW_AREA", function() Module:UpdateQuestTrackerState() end)

WT.Core.Events:Register("PLAYER_ENTERING_WORLD", function()
    if WT.DB.Modules.Frames then
        Module:UpdateQuestTrackerState()
    end
end)

function Module:BuildOptions(builder, panel, part)
    -- "part" builds only one section when the module is spread over several options pages
    local function ShowPart(name) return part == nil or part == name end
    local function PromptReload()
        if WT.Config and WT.Config.OptionsPanel and WT.Config.OptionsPanel.ShowReloadPrompt then
            WT.Config.OptionsPanel:ShowReloadPrompt()
        end
    end

    local function AddDescription(text)
        if not text then return end
        local desc = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
        desc:SetWidth(550)
        desc:SetJustifyH("LEFT")
        desc:SetText(text)
        builder:AddSpace(desc:GetStringHeight() + 25)
    end

    if ShowPart("Windows") then
        -- 1. FRAME BEHAVIOR
        panel:CreateTitle(builder, WT.L.GROUP_FRAMES_BEHAVIOR)
        AddDescription(WT.L.OPT_DESC_GROUP_FRAMES_BEHAVIOR)

        local moveInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_MOVABLE, WT.L.OPT_DESC_FRAMES_MOVABLE, "Frames",
            "MovableFrames", PromptReload)
        local modOptions = { { value = "ALT", label = "ALT" }, { value = "CTRL", label = "CTRL" }, { value = "SHIFT", label = "SHIFT" } }
        panel:CreateDropdown(builder, WT.L.OPT_FRAMES_MOVE_MODIFIER, WT.L.OPT_DESC_FRAMES_MOVE_MODIFIER, "Frames",
            "MoveModifier", modOptions, nil, moveInit)
        panel:CreateDropdown(builder, WT.L.OPT_FRAMES_SCALE_MODIFIER, WT.L.OPT_DESC_FRAMES_SCALE_MODIFIER, "Frames",
            "ScaleModifier", modOptions, nil, moveInit)

        local moveHint = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        moveHint:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
        moveHint:SetWidth(550)
        moveHint:SetJustifyH("LEFT")
        moveHint:SetText(WT.L.OPT_DESC_FRAMES_MOVABLE_HINT)
        moveHint:SetTextColor(WT.Colors.SUBTEXT_R, WT.Colors.SUBTEXT_G, WT.Colors.SUBTEXT_B)
        local searchEntry = panel:IndexOption(WT.L.SEARCH_INDEX_TAINT, "Frames",
            builder.category, builder)
        if searchEntry then
            searchEntry.textObj = moveHint
            searchEntry.yPos = builder.cursorY
        end
        builder:AddSpace(moveHint:GetStringHeight() + 25)

        panel:CreateButton(builder, " ", WT.L.BTN_RESET_POS, WT.L.CMD_HELP_RESET_POS, function()
            if WT.DB.Internal.Positions then wipe(WT.DB.Internal.Positions) end
            ReloadUI()
        end, moveInit)

        panel:CreateButton(builder, " ", WT.L.BTN_RESET_SCALE, WT.L.CMD_HELP_RESET_SCALE, function()
            if WT.DB.Internal.Scales then wipe(WT.DB.Internal.Scales) end
            ReloadUI()
        end, moveInit)

    end
    if ShowPart("MapFade") then
        local mapFadeInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_MAP_FADE, WT.L.OPT_DESC_FRAMES_MAP_FADE, "Frames",
            "SmartMapFade")
        panel:CreateSlider(builder, WT.L.OPT_FRAMES_MAP_FADE_ALPHA, WT.L.OPT_DESC_FRAMES_MAP_FADE_ALPHA, "Frames",
            "MapFadeAlpha", 0.1, 1.0, 0.1, nil, mapFadeInit)
    end

    if ShowPart("Graphics") then
        -- 2. CAMERA & GRAPHICS
        panel:CreateTitle(builder, WT.L.GROUP_FRAMES_CAMERA)
        AddDescription(WT.L.OPT_DESC_GROUP_FRAMES_CAMERA)

        local zoomInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_EXTENDED_ZOOM, WT.L.OPT_DESC_FRAMES_EXTENDED_ZOOM,
            "Frames", "ExtendedCameraZoom", function(value) self:UpdateExtendedCameraZoom(value) end)
        panel:CreateSlider(builder, WT.L.OPT_FRAMES_ZOOM_SLIDER, WT.L.OPT_DESC_FRAMES_ZOOM_SLIDER, "Frames", "MaxZoom", 1.0,
            2.6, 0.1, function() self:UpdateExtendedCameraZoom(WT.DB.Frames.ExtendedCameraZoom) end, zoomInit)
        panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_SHARPENING, WT.L.OPT_DESC_FRAMES_SHARPENING, "Frames",
            "SharpeningFilter", function(value) self:UpdateSharpening(value) end)
        panel:CreateCheckbox(builder, WT.L.OPT_SHADER_FIX,
            WT.L.OPT_DESC_SHADER_FIX,
            "Frames",
            "ShaderFix", function(value) self:UpdateShaderFix(value) end)
        panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_LOW_HEALTH_FLASH, WT.L.OPT_DESC_FRAMES_LOW_HEALTH_FLASH, "Frames",
            "DisableLowHealthFlash", function(value) self:UpdateLowHealthFlash(value) end)
        panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_DISABLE_GLOW, WT.L.OPT_DESC_FRAMES_DISABLE_GLOW, "Frames",
            "DisableGlow", function(value) self:UpdateGlow(value) end)

        panel:CreateSlider(builder, WT.L.OPT_WEATHER_DENSITY, WT.L.OPT_DESC_WEATHER_DENSITY, "Frames",
            "WeatherDensity", 0, 3, 1, function() self:UpdateWeatherDensity(WT.DB.Frames.WeatherDensity) end)


        builder:AddSpace(20)
        panel:CreateTitle(builder, WT.L.GROUP_COMBAT_TEXT)
        local ctOptions = { { value = 1, label = WT.L.LBL_UP }, { value = 2, label = WT.L.LBL_DOWN }, { value = 3, label = WT.L.LBL_ARC } }
        panel:CreateDropdown(builder, WT.L.OPT_CT_MODE, WT.L.OPT_DESC_CT_MODE, "Frames",
            "CombatTextFloatMode", ctOptions, function() self:UpdateCombatTextMode() end)
        panel:CreateCheckbox(builder, WT.L.OPT_CT_DIRECTIONAL, WT.L.OPT_DESC_CT_DIRECTIONAL, "Frames",
            "CombatTextDirectional", function() self:UpdateCombatTextMode() end)
    end

    if ShowPart("Windows") then
        -- 3. TOASTS & ALERTS
        panel:CreateTitle(builder, WT.L.LBL_ALERT_ANCHOR)
        AddDescription(WT.L.OPT_DESC_GROUP_FRAMES_ALERTS)

        local alertInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_CUSTOM_ALERTS, WT.L.OPT_DESC_FRAMES_CUSTOM_ALERTS,
            "Frames", "CustomAlerts", function()
                if Module.alertData then
                    if AlertFrame and Module.alertData[AlertFrame] and Module.alertData[AlertFrame].ForcePos then
                        Module.alertData[AlertFrame].ForcePos(true)
                    end
                    if EventToastManagerFrame and Module.alertData[EventToastManagerFrame] and Module.alertData[EventToastManagerFrame].ForcePos then
                        Module.alertData[EventToastManagerFrame].ForcePos(true)
                    end
                end
            end)
        panel:CreateButton(builder, WT.L.OPT_FRAMES_UNLOCK_ALERTS, WT.L.BTN_UNLOCK, WT.L.DESC_UNLOCK_ALERTS, function()
            self:SetupAlertAnchor()
            local anchor = _G["WT_AlertAnchor"]
            if anchor then
                if anchor:IsShown() then anchor:Hide() else anchor:Show() end
            end
        end, alertInit)

        panel:CreateButton(builder, WT.L.OPT_FRAMES_TEST_ALERTS, WT.L.BTN_TEST,
            WT.L.DESC_TEST_ALERTS, function()
                local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI")) or
                    (_G["IsAddOnLoaded"] and _G["IsAddOnLoaded"]("Blizzard_AchievementUI"))
                if not isLoaded then
                    local loadFunc = (C_AddOns and C_AddOns.LoadAddOn) or _G["LoadAddOn"] or _G["UIParentLoadAddOn"]
                    if loadFunc then pcall(loadFunc, "Blizzard_AchievementUI") end
                end

                -- Ensure points nil comparison bug in Blizzard FrameXML is guarded
                if Module.GuardAchievementShield then
                    Module:GuardAchievementShield()
                end

                local testID = nil
                if GetAchievementInfo then
                    local candidates = { 6, 7, 8, 9, 10, 11, 12, 13, 1, 2144, 4807, 107 }
                    for _, id in ipairs(candidates) do
                        local ok, achID, _, points = pcall(GetAchievementInfo, id)
                        if ok and achID and type(points) == "number" then
                            testID = id
                            break
                        end
                    end
                    if not testID then
                        for id = 1, 200 do
                            local ok, achID, _, points = pcall(GetAchievementInfo, id)
                            if ok and achID and type(points) == "number" then
                                testID = id
                                break
                            end
                        end
                    end
                end

                local AchievementAlertSystem = _G["AchievementAlertSystem"]
                local MoneyWonAlertSystem = _G["MoneyWonAlertSystem"]
                local HonorAwardedAlertSystem = _G["HonorAwardedAlertSystem"]

                if testID and AchievementAlertSystem then
                    if type(AchievementAlertSystem.ShowAlert) == "function" then
                        AchievementAlertSystem:ShowAlert(testID)
                    elseif type(AchievementAlertSystem.AddAlert) == "function" then
                        AchievementAlertSystem:AddAlert(testID)
                    end
                elseif MoneyWonAlertSystem then
                    if type(MoneyWonAlertSystem.ShowAlert) == "function" then
                        MoneyWonAlertSystem:ShowAlert(10000)
                    elseif type(MoneyWonAlertSystem.AddAlert) == "function" then
                        MoneyWonAlertSystem:AddAlert(10000)
                    end
                elseif HonorAwardedAlertSystem then
                    if type(HonorAwardedAlertSystem.ShowAlert) == "function" then
                        HonorAwardedAlertSystem:ShowAlert(100)
                    elseif type(HonorAwardedAlertSystem.AddAlert) == "function" then
                        HonorAwardedAlertSystem:AddAlert(100)
                    end
                elseif AchievementAlertSystem and testID then
                    if type(AchievementAlertSystem.ShowAlert) == "function" then
                        AchievementAlertSystem:ShowAlert(testID)
                    elseif type(AchievementAlertSystem.AddAlert) == "function" then
                        AchievementAlertSystem:AddAlert(testID)
                    end
                end
            end)

        local bnetInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_CUSTOM_BNET_ALERTS,
            WT.L.OPT_DESC_FRAMES_CUSTOM_BNET_ALERTS, "Frames", "CustomBNetAlerts", function()
                if Module.alertData and BNToastFrame and Module.alertData[BNToastFrame] and Module.alertData[BNToastFrame].ForcePos then
                    Module.alertData[BNToastFrame].ForcePos(true)
                end
            end)
        panel:CreateButton(builder, WT.L.OPT_FRAMES_UNLOCK_BNET_ALERTS, WT.L.BTN_UNLOCK, WT.L.DESC_UNLOCK_BNET_ALERTS,
            function()
                self:SetupBNetAlertAnchor()
                local anchor = _G["WT_BNetAlertAnchor"]
                if anchor then
                    if anchor:IsShown() then anchor:Hide() else anchor:Show() end
                end
            end, bnetInit)

        panel:CreateButton(builder, WT.L.OPT_FRAMES_TEST_BNET_ALERTS, WT.L.BTN_TEST,
            WT.L.DESC_TEST_BNET_ALERTS, function()
                if BNToastFrame then
                    if BNToastFrame.TopLine then
                        BNToastFrame.TopLine:SetText("W1LD Tools"); BNToastFrame.TopLine:Show()
                    end
                    if BNToastFrame.MiddleLine then
                        BNToastFrame.MiddleLine:SetText(WT.L.OPT_FRAMES_TEST_BNET_ALERTS); BNToastFrame
                            .MiddleLine:Show()
                    end
                    if BNToastFrame.BottomLine then BNToastFrame.BottomLine:Hide() end
                    if BNToastFrame.DoubleLine then BNToastFrame.DoubleLine:Hide() end
                    if BNToastFrame.IconTexture then
                        BNToastFrame.IconTexture:SetTexture("Interface\\FriendsFrame\\UI-Toast-ToastIcons")
                        BNToastFrame.IconTexture:SetTexCoord(0.75, 1, 0, 0.5)
                    end
                    BNToastFrame:Show()
                    if BNToastFrame.animIn then BNToastFrame.animIn:Play() end
                    C_Timer.After(4,
                        function()
                            if BNToastFrame.waitAndAnimOut then
                                BNToastFrame.waitAndAnimOut:Play()
                            else
                                BNToastFrame
                                    :Hide()
                            end
                        end)
                end
            end)

        local raidbossInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_CUSTOM_RAIDBOSS,
            WT.L.OPT_DESC_FRAMES_CUSTOM_RAIDBOSS, "Frames", "CustomRaidBoss",
            function()
                if Module.alertData and _G["RaidBossEmoteFrame"] and Module.alertData[_G["RaidBossEmoteFrame"]] and Module.alertData[_G["RaidBossEmoteFrame"]].ForcePos then
                    Module.alertData[_G["RaidBossEmoteFrame"]].ForcePos(true)
                end
            end)
        panel:CreateButton(builder, WT.L.OPT_FRAMES_UNLOCK_RAIDBOSS, WT.L.BTN_UNLOCK,
            WT.L.DESC_UNLOCK_RAIDBOSS, function()
                self:SetupRaidBossEmoteAnchor()
                local anchor = _G["WT_RaidBossEmoteAnchor"]
                if anchor then
                    if anchor:IsShown() then anchor:Hide() else anchor:Show() end
                end
            end, raidbossInit)

        if WT.Utils and WT.Utils.SharedMedia then
            panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "Frames", "RaidBossFont",
                WT.Utils.SharedMedia:GetOptions("font"), function() self:UpdateRaidBossEmoteFont() end, raidbossInit)
        end

        panel:CreateButton(builder, WT.L.OPT_FRAMES_TEST_RAIDBOSS, WT.L.BTN_TEST,
            WT.L.DESC_TEST_RAIDBOSS, function()
                if RaidNotice_AddMessage then
                    local colorInfo = ChatTypeInfo and ChatTypeInfo["RAID_BOSS_EMOTE"] or { r = 1, g = 1, b = 0 }
                    RaidNotice_AddMessage(RaidBossEmoteFrame, WT.L.MSG_TEST_RAIDBOSS,
                        colorInfo)
                end
            end)

        -- 4. ERROR MESSAGES
        panel:CreateTitle(builder, WT.L.LBL_ERROR_ANCHOR)
        AddDescription(WT.L.OPT_DESC_GROUP_FRAMES_ERRORS)

        panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_HIDE_ERRORS, WT.L.OPT_DESC_FRAMES_HIDE_ERRORS, "Frames", "HideErrors",
            function()
                self:UpdateErrorFilter(); PromptReload()
            end)

        local errInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_CUSTOM_ERRORS, WT.L.OPT_DESC_FRAMES_CUSTOM_ERRORS,
            "Frames", "CustomErrors", function()
                if Module.alertData and UIErrorsFrame and Module.alertData[UIErrorsFrame] and Module.alertData[UIErrorsFrame].ForcePos then
                    Module.alertData[UIErrorsFrame].ForcePos(true)
                end
            end)
        panel:CreateButton(builder, WT.L.OPT_FRAMES_UNLOCK_ERRORS, WT.L.BTN_UNLOCK, WT.L.DESC_UNLOCK_ERRORS, function()
            self:SetupErrorAnchor()
            local anchor = _G["WT_ErrorAnchor"]
            if anchor then
                if anchor:IsShown() then anchor:Hide() else anchor:Show() end
            end
        end, errInit)

        local errBgInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_ERROR_BG, WT.L.OPT_DESC_FRAMES_ERROR_BG, "Frames",
            "ErrorBackground", function() self:SetupErrorBackground() end)
        panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BG, WT.L.OPT_DESC_COLOR_BG, "Frames", "ErrorBgColor", true, errBgInit,
            function() self:SetupErrorBackground() end)
        panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BORDER, WT.L.OPT_DESC_COLOR_BORDER, "Frames", "ErrorBorderColor",
            true, errBgInit, function() self:SetupErrorBackground() end)
        if WT.Utils and WT.Utils.SharedMedia then
            panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "Frames",
                "ErrorFont", WT.Utils.SharedMedia:GetOptions("font"), function() self:SetupErrorBackground() end, errBgInit)
        end
        panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "Frames", "ErrorFontSize", 8, 32, 1,
            function() self:SetupErrorBackground() end, errBgInit)
        panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "Frames", "ErrorFontOutline",
            function() self:SetupErrorBackground() end, errBgInit)

        panel:CreateButton(builder, WT.L.OPT_FRAMES_TEST_ERRORS, WT.L.BTN_TEST,
            WT.L.DESC_TEST_ERRORS, function()
                if UIErrorsFrame then
                    UIErrorsFrame:AddMessage(WT.L.MSG_TEST_ERROR, 1.0, 0.1, 0.1, 1.0)
                end
            end)

        -- 5. COMBAT CURSOR
    end
    if ShowPart("Graphics") then
        panel:CreateTitle(builder, WT.L.OPT_FRAMES_COMBAT_CURSOR)
        AddDescription(WT.L.OPT_DESC_GROUP_FRAMES_CURSOR)

        local ccInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_COMBAT_CURSOR, WT.L.OPT_DESC_FRAMES_COMBAT_CURSOR,
            "Frames", "CombatCursor", function() self:UpdateCombatCursor() end)
        panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_COMBAT_CURSOR_SHOW_OOC,
            WT.L.OPT_DESC_FRAMES_COMBAT_CURSOR_SHOW_OOC, "Frames", "CombatCursorShowOOC",
            function() self:UpdateCombatCursor() end, ccInit)

        local shapeOptions = {
            { value = "Interface\\Cooldown\\ping4",                        label = WT.L.OPT_CURSOR_RING },
            { value = "Interface\\Cooldown\\star4",                        label = WT.L.OPT_CURSOR_GLOW },
            { value = "Interface\\Cursor\\Crosshairs",                     label = WT.L.OPT_CURSOR_CROSS },
            { value = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", label = WT.L.OPT_CURSOR_SKULL }
        }
        panel:CreateDropdown(builder, WT.L.OPT_FRAMES_COMBAT_CURSOR_SHAPE,
            WT.L.OPT_DESC_FRAMES_COMBAT_CURSOR_SHAPE, "Frames", "CombatCursorShape", shapeOptions,
            function() self:UpdateCombatCursor() end, ccInit)
        panel:CreateColorPicker(builder, WT.L.OPT_FRAMES_COMBAT_CURSOR_COLOR,
            WT.L.OPT_DESC_FRAMES_COMBAT_CURSOR_COLOR, "Frames", "CombatCursorColor", true, ccInit,
            function() self:UpdateCombatCursor() end)
        panel:CreateSlider(builder, WT.L.OPT_FRAMES_COMBAT_CURSOR_SCALE,
            WT.L.OPT_DESC_FRAMES_COMBAT_CURSOR_SCALE, "Frames", "CombatCursorScale", 0.5, 3.0, 0.1,
            function() self:UpdateCombatCursor() end, ccInit)

        local animOptions = {
            { value = "NONE",         label = WT.L.OPT_ANIM_NONE },
            { value = "ROTATE_CW",    label = WT.L.OPT_ANIM_ROTATE_CW },
            { value = "ROTATE_CCW",   label = WT.L.OPT_ANIM_ROTATE_CCW },
            { value = "PULSE",        label = WT.L.OPT_ANIM_PULSE },
            { value = "ROT_PULSE",    label = WT.L.OPT_ANIM_ROT_PULSE },
            { value = "CHROMA",       label = WT.L.OPT_ANIM_CHROMA },
            { value = "CHROMA_PULSE", label = WT.L.OPT_ANIM_CHROMA_PULSE }
        }
        panel:CreateDropdown(builder, WT.L.OPT_FRAMES_COMBAT_CURSOR_ANIM,
            WT.L.OPT_DESC_FRAMES_COMBAT_CURSOR_ANIM, "Frames", "CombatCursorAnim", animOptions,
            function() self:UpdateCombatCursor() end, ccInit)

        panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_COMBAT_CURSOR_CLICKS,
            WT.L.OPT_DESC_FRAMES_COMBAT_CURSOR_CLICKS, "Frames", "CombatCursorClicks",
            function() self:UpdateCombatCursor() end, ccInit)

        local trailInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_COMBAT_CURSOR_TRAIL,
            WT.L.OPT_DESC_FRAMES_COMBAT_CURSOR_TRAIL, "Frames", "CombatCursorTrail", function() self:UpdateCombatCursor() end,
            ccInit)
        panel:CreateColorPicker(builder, WT.L.OPT_FRAMES_COMBAT_CURSOR_TRAIL_COLOR,
            WT.L.OPT_DESC_FRAMES_COMBAT_CURSOR_TRAIL_COLOR, "Frames", "CombatCursorTrailColor", true, trailInit,
            function() self:UpdateCombatCursor() end)
        panel:CreateSlider(builder, WT.L.OPT_FRAMES_COMBAT_CURSOR_TRAIL_DUR,
            WT.L.OPT_DESC_FRAMES_COMBAT_CURSOR_TRAIL_DUR, "Frames", "CombatCursorTrailDuration", 0.1, 1.5, 0.05,
            function() self:UpdateCombatCursor() end, trailInit)
        panel:CreateSlider(builder, WT.L.OPT_FRAMES_COMBAT_CURSOR_TRAIL_DIST,
            WT.L.OPT_DESC_FRAMES_COMBAT_CURSOR_TRAIL_DIST, "Frames", "CombatCursorTrailDistance", 1, 20, 1,
            function() self:UpdateCombatCursor() end, trailInit)
        panel:CreateSlider(builder, WT.L.OPT_FRAMES_COMBAT_CURSOR_TRAIL_ENDSCALE,
            WT.L.OPT_DESC_FRAMES_COMBAT_CURSOR_TRAIL_ENDSCALE, "Frames", "CombatCursorTrailEndScale", 0.0, 1.0, 0.05,
            function() self:UpdateCombatCursor() end, trailInit)

        panel:CreateButton(builder, WT.L.OPT_FRAMES_TEST_CURSOR, WT.L.BTN_TEST,
            WT.L.DESC_TEST_CURSOR, function()
                self.PreviewCombatCursor = true
                self:UpdateCombatCursor()
                C_Timer.After(5, function()
                    self.PreviewCombatCursor = false
                    self:UpdateCombatCursor()
                end)
            end)

        -- 6. HIDE ELEMENTS
    end
    if ShowPart("Windows") then
        panel:CreateTitle(builder, WT.L.GROUP_FRAMES_HIDER)
        AddDescription(WT.L.OPT_DESC_GROUP_FRAMES_HIDER)

        panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_HIDE_XP, WT.L.OPT_DESC_FRAMES_HIDE_XP, "Frames", "HideXPBar",
            function() self:UpdateXPBar() end)
        panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_HIDE_BAGS, WT.L.OPT_DESC_FRAMES_HIDE_BAGS, "Frames", "HideBagsBar",
            function() self:UpdateBagsBar() end)
        panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_HIDE_TALKINGHEAD, WT.L.OPT_DESC_FRAMES_HIDE_TALKINGHEAD, "Frames",
            "HideTalkingHead", function()
                self:UpdateTalkingHead(); PromptReload()
            end)

        panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_COMBAT_CLEANER, WT.L.OPT_DESC_FRAMES_COMBAT_CLEANER, "Frames",
            "CombatCleaner", function() self:UpdateCombatCleaner() end)
        panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_AUTO_QUEST, WT.L.OPT_DESC_FRAMES_AUTO_QUEST, "Frames",
            "AutoQuestTracker", function() self:UpdateQuestTrackerState() end)

        -- 7. SYSTEM WIDGET
    end
    if ShowPart("SystemWidget") then
        panel:CreateTitle(builder, WT.L.GROUP_FRAMES_SYSTEM)
        AddDescription(WT.L.OPT_DESC_GROUP_FRAMES_SYSTEM)

        local cpuHint = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        cpuHint:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
        cpuHint:SetWidth(550)
        cpuHint:SetJustifyH("LEFT")
        cpuHint:SetText(WT.L.OPT_DESC_SYS_CPU_HINT)
        cpuHint:SetTextColor(WT.Colors.SUBTEXT_R, WT.Colors.SUBTEXT_G, WT.Colors.SUBTEXT_B)
        builder:AddSpace(cpuHint:GetStringHeight() + 25)

        local sysInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_SYS_SHOW,
            WT.L.OPT_DESC_FRAMES_SYS_SHOW, "Frames", "SystemWidgetShow", function() self:UpdateSystemWidget() end)

        local orderOptions = {
            { value = "FPM", label = "FPS - Ping - Memory" },
            { value = "FMP", label = "FPS - Memory - Ping" },
            { value = "PFM", label = "Ping - FPS - Memory" },
            { value = "PMF", label = "Ping - Memory - FPS" },
            { value = "MFP", label = "Memory - FPS - Ping" },
            { value = "MPF", label = "Memory - Ping - FPS" }
        }
        panel:CreateDropdown(builder, WT.L.OPT_FRAMES_SYS_ORDER, WT.L.OPT_DESC_FRAMES_SYS_ORDER, "Frames",
            "SystemWidgetOrder", orderOptions, function() self:UpdateSystemWidget() end, sysInit)
        panel:CreateStrataDropdown(builder, WT.L.OPT_STRATA, WT.L.OPT_DESC_STRATA, "Frames", "SystemWidgetStrata",
            function() self:UpdateSystemWidget() end, sysInit)
        panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_SYS_MOVABLE, WT.L.OPT_DESC_FRAMES_SYS_MOVABLE,
            "Frames", "SystemWidgetMovable", function() self:UpdateSystemWidget() end, sysInit)
        panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_SYS_PING, WT.L.OPT_DESC_FRAMES_SYS_PING,
            "Frames", "SystemWidgetShowPing", function() self:UpdateSystemWidget() end, sysInit)
        panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_SYS_MEMORY, WT.L.OPT_DESC_FRAMES_SYS_MEMORY,
            "Frames", "SystemWidgetShowMemory", function() self:UpdateSystemWidget() end, sysInit)
        panel:CreateSlider(builder, WT.L.OPT_FRAMES_SYS_UPDATE_RATE,
            WT.L.OPT_DESC_FRAMES_SYS_UPDATE_RATE,
            "Frames", "SystemWidgetUpdateRate", 0.1, 2.0, 0.1, function() self:UpdateSystemWidget() end, sysInit)

        local colInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_SYS_COLORIZE,
            WT.L.OPT_DESC_FRAMES_SYS_COLORIZE, "Frames", "SystemWidgetColorizeValues",
            function() self:UpdateSystemWidget() end, sysInit)
        panel:CreateColorPicker(builder, WT.L.OPT_FRAMES_SYS_COLOR_GOOD, WT.L.OPT_DESC_COLOR_VALUE, "Frames",
            "SystemWidgetColorGood", true, colInit, function() self:UpdateSystemWidget() end)
        panel:CreateColorPicker(builder, WT.L.OPT_FRAMES_SYS_COLOR_NEUTRAL, WT.L.OPT_DESC_COLOR_VALUE,
            "Frames", "SystemWidgetColorNeutral", true, colInit, function() self:UpdateSystemWidget() end)
        panel:CreateColorPicker(builder, WT.L.OPT_FRAMES_SYS_COLOR_BAD, WT.L.OPT_DESC_COLOR_VALUE, "Frames",
            "SystemWidgetColorBad", true, colInit, function() self:UpdateSystemWidget() end)

        panel:CreateEditBox(builder, WT.L.OPT_FRAMES_SYS_FPS_LABEL, WT.L
            .OPT_DESC_FRAMES_SYS_FPS_LABEL, "Frames", "SystemWidgetFpsLabel", sysInit,
            function() self:UpdateSystemWidget() end)
        panel:CreateEditBox(builder, WT.L.OPT_FRAMES_SYS_PING_LABEL,
            WT.L.OPT_DESC_FRAMES_SYS_PING_LABEL, "Frames", "SystemWidgetPingLabel", sysInit,
            function() self:UpdateSystemWidget() end)
        panel:CreateEditBox(builder, WT.L.OPT_FRAMES_SYS_MEM_LABEL,
            WT.L.OPT_DESC_FRAMES_SYS_MEM_LABEL, "Frames", "SystemWidgetMemoryLabel", sysInit,
            function() self:UpdateSystemWidget() end)

        if WT.Utils and WT.Utils.SharedMedia then
            panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "Frames", "SystemWidgetFont",
                WT.Utils.SharedMedia:GetOptions("font"), function() self:UpdateSystemWidget() end, sysInit)
        end
        panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "Frames", "SystemWidgetFontSize", 8, 24, 1,
            function() self:UpdateSystemWidget() end, sysInit)
        panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "Frames",
            "SystemWidgetFontOutline", function() self:UpdateSystemWidget() end, sysInit)

        local bgInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_BACKGROUND, WT.L
            .OPT_DESC_SW_BACKGROUND, "Frames", "SystemWidgetBackground", function() self:UpdateSystemWidget() end, sysInit)
        panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BG, WT.L.OPT_DESC_COLOR_BG, "Frames", "SystemWidgetBgColor", true,
            bgInit, function() self:UpdateSystemWidget() end)
        local borderInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_BORDER, WT.L.OPT_DESC_SW_BORDER,
            "Frames", "SystemWidgetBorder", function() self:UpdateSystemWidget() end, sysInit)
        panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BORDER, WT.L.OPT_DESC_COLOR_BORDER, "Frames",
            "SystemWidgetBorderColor", true, borderInit, function() self:UpdateSystemWidget() end)

        panel:CreateColorPicker(builder, WT.L.OPT_COLOR_TEXT, WT.L.OPT_DESC_COLOR_TEXT, "Frames", "SystemWidgetTextColor",
            true, sysInit, function() self:UpdateSystemWidget() end)

        local sepInit = panel:CreateEditBox(builder, WT.L.OPT_SEPARATOR, WT.L.OPT_DESC_SEPARATOR, "Frames",
            "SystemWidgetSeparator", sysInit, function() self:UpdateSystemWidget() end)
        panel:CreateColorPicker(builder, WT.L.OPT_COLOR_SEP, WT.L.OPT_DESC_COLOR_VALUE, "Frames",
            "SystemWidgetSeparatorColor", true, sepInit, function() self:UpdateSystemWidget() end)



        -- Hook for custom configuration frames (Permanent Smart Watcher)
        local extConfigNames = { "ElvUIConfig", "ElvUIOptionsUI", "ElvUIOptionsGUI", "ElvUI_Config" }
        local ecWatcher = CreateFrame("Frame")
        ecWatcher.timer = 0
        ecWatcher:SetScript("OnUpdate", function(self, elapsed)
            if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ElvUI")) then -- API required string
                self:SetScript("OnUpdate", nil)
                self:Hide()
                return
            end
            self.timer = self.timer + elapsed
            if self.timer > 0.5 then
                self.timer = 0
                local f = nil
                for _, n in ipairs(extConfigNames) do
                    local gF = rawget(_G, n)
                    if gF and type(gF) == "table" and gF.IsObjectType and gF:IsObjectType("Frame") then
                        f = gF; break
                    end
                end
                if not f then
                    local ls = rawget(_G, "LibStub")
                    if ls then
                        local extDialog = ls("AceConfigDialog-3.0-ElvUI", true) or ls("AceConfigDialog-3.0", true)
                        if extDialog and extDialog.OpenFrames and extDialog.OpenFrames.ElvUI then
                            f = extDialog.OpenFrames
                                .ElvUI.frame
                        end
                    end
                end

                if f and not f.WTCustomConfigHooked then
                    f.WTCustomConfigHooked = true
                    self:SetScript("OnUpdate", nil); self:Hide()

                    local smartOverlay = CreateFrame("Frame", nil, f)
                    smartOverlay:SetAllPoints(f)
                    smartOverlay:SetFrameLevel(9000)

                    smartOverlay:SetScript("OnUpdate", function(thisOverlay)
                        thisOverlay:EnableMouseWheel(Module.IsModifierDown(WT.DB.Frames.ScaleModifier) and f:IsMouseOver())
                    end)

                    smartOverlay:SetScript("OnMouseWheel", function(_, delta)
                        local currentScale = f:GetScale() or 1.0
                        local newScale = currentScale + (delta * 0.05)
                        newScale = math.max(0.5, math.min(newScale, 2.5))
                        f:SetScale(newScale)
                        Module.ShowScaleIndicator(f, newScale)
                    end)
                end
            end
        end)
    end
end
