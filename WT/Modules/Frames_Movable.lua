local _, WT = ...
local Module = WT.Modules.Frames

local hookedFrames = {}

local moveBlacklist = {
    ["EditModeManagerFrame"] = true,
    ["UIErrorsFrame"] = true,
    ["ObjectiveTrackerFrame"] = true,
    ["GameTooltip"] = true,
    ["HouseEditor"] = true,
    ["HouseList"] = true,
    ["HouseListFrame"] = true,
    ["HouseEditorFrame"] = true,
    ["Housing"] = true,
    ["CooldownViewer"] = true,
    ["CooldownViewerSettings"] = true,
    ["KeyBindingFrame"] = true,
    ["FriendsFrame"] = true,
    ["HelpFrame"] = true,
    ["CommunitiesFrame"] = true,
    ["GuildBankFrame"] = true,
    ["GuildFrame"] = true,
    ["ClubFinderCommunityAndGuildFinderFrame"] = true,
}

local moveWhitelist = {
    -- Add frames here that should always be movable,
    -- even if they would normally be blocked by the blacklist.
    -- ["MyCustomFrame"] = true,
    ["HousingModelPreviewFrame"] = true,
    ["HousingDashboardFrame"] = true,
    ["HousingBulletinBoardFrame"] = true,
    ["HousingBlueprintContentListFrame"] = true,
    ["DelvesCompanionConfigurationFrame"] = true,
    ["DelvesCompanionAbilityListFrame"] = true,
}

-- Taint Protection: Weak table for frame states
local moveData = setmetatable({}, { __mode = "k" })

local SafeNum = WT.Utils.Safety.SafeNum
local Unsecret = WT.Utils.Safety.Unsecret

local function SaveFramePosition(frameName, frame)
    if not WT.DB.Internal.Positions then WT.DB.Internal.Positions = {} end
    -- Use absolute coordinates to prevent anchoring issues on reload
    local fLeft = frame:GetLeft()
    local fTop = frame:GetTop()

    if type(fLeft) == "number" and type(fTop) == "number" then
        local s = frame:GetEffectiveScale() or 1
        local u = UIParent:GetEffectiveScale() or 1
        local uLeft = UIParent:GetLeft() or 0
        local uBottom = UIParent:GetBottom() or 0
        if type(s) == "number" and type(u) == "number" and type(uLeft) == "number" and type(uBottom) == "number" then
            local xOfs = ((fLeft * s) - (uLeft * u)) / s
            local yOfs = ((fTop * s) - (uBottom * u)) / s
            WT.DB.Internal.Positions[frameName] = {
                point = "TOPLEFT",
                relativeTo = "UIParent",
                relativePoint = "BOTTOMLEFT",
                xOfs = xOfs,
                yOfs = yOfs
            }
            return
        end
    end
    local ok, point, relativeTo, relativePoint, xOfs, yOfs = pcall(frame.GetPoint, frame)
    if not ok then return end

    local relName = "UIParent"
    if relativeTo then
        if type(relativeTo) == "table" and relativeTo.GetName then
            local okN, n = pcall(relativeTo.GetName, relativeTo)
            if okN and n then relName = n end
        elseif type(relativeTo) == "string" then
            relName = relativeTo
        end
    end

    WT.DB.Internal.Positions[frameName] = {
        point = Unsecret(point) or "CENTER",
        relativeTo = Unsecret(relName) or "UIParent",
        relativePoint = Unsecret(relativePoint) or "CENTER",
        xOfs = SafeNum(xOfs),
        yOfs = SafeNum(yOfs)
    }
end

function Module.IsModifierDown(mod)
    mod = mod or "ALT"
    if mod == "ALT" then return IsAltKeyDown() end
    if mod == "CTRL" then return IsControlKeyDown() end
    if mod == "SHIFT" then return IsShiftKeyDown() end
    return false
end

-- ==========================================
-- SCALE INDICATOR UI
-- ==========================================
local scaleIndicator

function Module.ShowScaleIndicator(frame, scale)
    if not scaleIndicator then
        scaleIndicator = CreateFrame("Frame", "WTScaleIndicator", _G["WT_UIContainer"], "BackdropTemplate")
        if scaleIndicator.SetIsFramePositionManaged then
            pcall(function() scaleIndicator:SetIsFramePositionManaged(false) end)
        else
            scaleIndicator.ignoreInLayout = true
            scaleIndicator.ignoreFramePositionManager = true
        end
        scaleIndicator:SetSize(60, 30)
        scaleIndicator:SetFrameStrata("TOOLTIP")
        scaleIndicator:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        scaleIndicator:SetBackdropColor(WT.Colors.STD_BG_R, WT.Colors.STD_BG_G, WT.Colors.STD_BG_B, WT.Colors.STD_BG_A)
        scaleIndicator:SetBackdropBorderColor(1, 1, 1, 0.8)
        scaleIndicator:SetFrameLevel(9999)
        scaleIndicator.text = scaleIndicator:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        scaleIndicator.text:SetPoint("TOPLEFT", scaleIndicator, "TOPLEFT", 3, -3)
        scaleIndicator.text:SetPoint("BOTTOMRIGHT", scaleIndicator, "BOTTOMRIGHT", -3, 3)
        scaleIndicator.text:SetJustifyH("CENTER")
        scaleIndicator.text:SetJustifyV("MIDDLE")
        scaleIndicator.text:SetTextColor(1, 1, 1)

        scaleIndicator.anim = scaleIndicator:CreateAnimationGroup()
        local fade = scaleIndicator.anim:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetDuration(0.5)
        fade:SetStartDelay(1.0)
        scaleIndicator.anim:SetScript("OnFinished", function() scaleIndicator:Hide() end)

        scaleIndicator:SetScript("OnUpdate", function(self)
            local x, y = GetCursorPosition()
            local uiScale = UIParent:GetEffectiveScale()
            self:ClearAllPoints()
            self:SetPoint("BOTTOM", _G["WT_UIContainer"], "BOTTOMLEFT", x / uiScale, (y / uiScale) + 10)
        end)
    end

    scaleIndicator.text:SetText(string.format("%.0f%%", scale * 100))
    scaleIndicator:Show()
    scaleIndicator:SetAlpha(1)
    scaleIndicator.anim:Stop()
    scaleIndicator.anim:Play()
end

-- ==========================================
-- CORE MOVEMENT LOGIC
-- ==========================================
local function DetachFromBlizzardLayout(f)
    if not f then return end
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    
    if f.SetIsFramePositionManaged then
        pcall(function() f:SetIsFramePositionManaged(false) end)
    else
        f.ignoreInLayout = true
        f.ignoreFramePositionManager = true
    end
end

local function ReattachToBlizzardLayout(f)
    if not f then return end
    
    if f.SetIsFramePositionManaged then
        pcall(function() f:SetIsFramePositionManaged(true) end)
    else
        f.ignoreInLayout = false
        f.ignoreFramePositionManager = false
    end
end

local function HookFrameForMove(f)
    if type(f) == "string" then f = _G[f] end
    if not f or type(f) ~= "table" then return end

    local frameName = Unsecret(f:GetName())
    if not frameName or hookedFrames[frameName] or f:IsForbidden() then return end

    local isWhitelisted = moveWhitelist and moveWhitelist[frameName]

    if not isWhitelisted then
        local isBlacklisted = false
        for blacklistedName, _ in pairs(moveBlacklist) do
            if frameName == blacklistedName or string.find(frameName, blacklistedName, 1, true) then
                isBlacklisted = true
                break
            end
        end

        local lName = string.lower(frameName)
        if string.find(lName, "house") and not string.find(lName, "auctionhouse") then
            isBlacklisted = true
        end
        if string.find(lName, "home") or string.find(lName, "property") or string.find(lName, "estate") or string.find(lName, "plot") or string.find(lName, "visit") or string.find(lName, "neighborhood") or string.find(lName, "roost") or string.find(lName, "residence") or string.find(lName, "hearth") or string.find(lName, "dwelling") or string.find(lName, "mansion") then
            isBlacklisted = true
        end
        if string.find(lName, "communit") or string.find(lName, "guild") or string.find(lName, "club") then
            isBlacklisted = true
        end

        if isBlacklisted then
            hookedFrames[frameName] = true
            return
        end
    end

    local dragFrames = {}
    if f.TitleContainer then table.insert(dragFrames, f.TitleContainer) end
    if _G[frameName .. "TitleContainer"] then table.insert(dragFrames, _G[frameName .. "TitleContainer"]) end
    if f.BorderFrame and f.BorderFrame.TitleContainer then table.insert(dragFrames, f.BorderFrame.TitleContainer) end
    if _G[frameName .. "Header"] then table.insert(dragFrames, _G[frameName .. "Header"]) end
    if f.Header then table.insert(dragFrames, f.Header) end
    if f.TitleBar then table.insert(dragFrames, f.TitleBar) end
    if _G[frameName .. "TitleBar"] then table.insert(dragFrames, _G[frameName .. "TitleBar"]) end

    if #dragFrames == 0 then
        -- Fallback: Use the frame itself instead of creating an invisible block
        -- that covers search boxes in external addons like Baganator
        table.insert(dragFrames, f)
    end

    -- Workaround: Ensure CloseButton is always drawn above the drag areas
    local closeBtn = f.CloseButton or _G[frameName .. "CloseButton"]
    if closeBtn and type(closeBtn) == "table" and closeBtn.SetFrameLevel then
        -- Elevate it relative to its OWN current level.
        -- (My previous fix used f:GetFrameLevel(), which accidentally dropped it behind TitleContainer)
        closeBtn:SetFrameLevel(closeBtn:GetFrameLevel() + 20)
    end

    local fData = moveData[f]
    if not fData then
        fData = {}; moveData[f] = fData

        -- Save default anchors for ALT+RightClick restoration
        if f.GetNumPoints then
            fData.defaultAnchors = {}
            for i = 1, f:GetNumPoints() do
                local point, relativeTo, relativePoint, xOfs, yOfs = f:GetPoint(i)
                table.insert(fData.defaultAnchors, {
                    point = point, relativeTo = relativeTo, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs
                })
            end
        end
    end

    local isDraggable = false
    for _, dragFrame in ipairs(dragFrames) do
        local dData = moveData[dragFrame]
        if not dData then
            dData = {}; moveData[dragFrame] = dData
        end

        if type(dragFrame) == "table" and not dData.WTDragHooked then
            dData.WTDragHooked = true
            isDraggable = true

            if not dragFrame:IsProtected() then
                if not dragFrame:IsMouseEnabled() then dragFrame:EnableMouse(true) end
                if not dragFrame:IsMouseWheelEnabled() then dragFrame:EnableMouseWheel(true) end
            end

            dragFrame:HookScript("OnMouseUp", function(_, button)
                if button == "LeftButton" and fData.isWTDragging then
                    f:StopMovingOrSizing()
                    fData.isWTDragging = false
                    if f.SetUserPlaced then pcall(function() f:SetUserPlaced(true) end) end
                    SaveFramePosition(frameName, f)
                end
            end)

            dragFrame:HookScript("OnMouseWheel", function(_, delta)
                if Module.IsModifierDown(WT.DB.Frames.ScaleModifier) then
                    if InCombatLockdown() and f:IsProtected() then return end

                    local okS, currentScale = pcall(f.GetScale, f)
                    currentScale = (okS and currentScale) and SafeNum(currentScale) or 1.0
                    if currentScale == 0 then currentScale = 1.0 end
                    local newScale = currentScale + (delta * 0.05)
                    newScale = math.max(0.5, math.min(newScale, 2.5))

                    local fLeft = f:GetLeft()
                    local fTop = f:GetTop()
                    local effScale = f:GetEffectiveScale() or 1

                    f:SetScale(newScale)

                    if fLeft and fTop then
                        local screenX = fLeft * effScale
                        local screenY = fTop * effScale
                        local newEffScale = f:GetEffectiveScale() or 1
                        local u = UIParent:GetEffectiveScale() or 1
                        local uLeft = UIParent:GetLeft() or 0
                        local uBottom = UIParent:GetBottom() or 0
                        local xOfs = (screenX - (uLeft * u)) / newEffScale
                        local yOfs = (screenY - (uBottom * u)) / newEffScale

                        fData.isWTSettingPoint = true
                        f:ClearAllPoints()
                        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", xOfs, yOfs)
                        fData.isWTSettingPoint = false

                        SaveFramePosition(frameName, f)
                    end

                    if not WT.DB.Internal.Scales then WT.DB.Internal.Scales = {} end
                    WT.DB.Internal.Scales[frameName] = newScale
                    Module.ShowScaleIndicator(f, newScale)
                end
            end)

            dragFrame:HookScript("OnMouseDown", function(_, button)
                if button == "LeftButton" and Module.IsModifierDown(WT.DB.Frames.MoveModifier) then
                    if InCombatLockdown() and f:IsProtected() then return end
                    fData.isWTDragging = true
                    DetachFromBlizzardLayout(f)
                    f:StartMoving()
                    if f.SetUserPlaced then pcall(function() f:SetUserPlaced(true) end) end
                elseif button == "RightButton" and Module.IsModifierDown(WT.DB.Frames.MoveModifier) then
                    if InCombatLockdown() then
                        WT.Utils.Logger:Warn(WT.L.MSG_COMBAT_BLOCK)
                        return
                    end

                    f:SetScale(1.0)
                    if WT.DB.Internal.Scales then WT.DB.Internal.Scales[frameName] = nil end
                    Module.ShowScaleIndicator(f, 1.0)

                    if WT.DB.Internal.Positions then WT.DB.Internal.Positions[frameName] = nil end

                    fData.isWTSettingPoint = true
                    f:ClearAllPoints()

                    if fData.defaultAnchors then
                        for _, anchor in ipairs(fData.defaultAnchors) do
                            f:SetPoint(anchor.point, anchor.relativeTo, anchor.relativePoint, anchor.xOfs, anchor.yOfs)
                        end
                    end

                    fData.isWTSettingPoint = false
                    if f.SetUserPlaced then pcall(function() f:SetUserPlaced(false) end) end
                    ReattachToBlizzardLayout(f)

                    if not InCombatLockdown() and UpdateUIPanelPositions then UpdateUIPanelPositions() end
                    if EditModeManagerFrame and EditModeManagerFrame.UpdateSystemLayouts then
                        pcall(function() EditModeManagerFrame:UpdateSystemLayouts() end)
                    end
                    WT.Utils.Logger:Print(string.format(WT.L.MSG_WINDOW_RESET, frameName))
                elseif button == "MiddleButton" and Module.IsModifierDown(WT.DB.Frames.ScaleModifier) then
                    if InCombatLockdown() then
                        WT.Utils.Logger:Warn(WT.L.MSG_COMBAT_BLOCK)
                        return
                    end

                    f:SetScale(1.0)
                    if WT.DB.Internal.Scales then WT.DB.Internal.Scales[frameName] = nil end
                    Module.ShowScaleIndicator(f, 1.0)
                end
            end)
        end
    end

    if isDraggable and not fData.WTShowHooked then
        fData.WTShowHooked = true

        local function ApplySavedLayout(self)
            local selfData = moveData[self]
            if not selfData then
                selfData = {}; moveData[self] = selfData
            end
            if selfData.isWTSettingPoint then return end

            if InCombatLockdown() and self:IsProtected() then return end

            if WT.DB.Internal.Scales and WT.DB.Internal.Scales[frameName] then
                self:SetScale(WT.DB.Internal.Scales[frameName])
            end

            if WT.DB.Internal.Positions and WT.DB.Internal.Positions[frameName] then
                DetachFromBlizzardLayout(self)

                local pos = WT.DB.Internal.Positions[frameName]

                selfData.isWTSettingPoint = true
                self:ClearAllPoints()
                self:SetPoint(pos.point, pos.relativeTo, pos.relativePoint, pos.xOfs, pos.yOfs)
                if self.SetUserPlaced then pcall(function() self:SetUserPlaced(true) end) end
                selfData.isWTSettingPoint = false
            end
        end

        f:HookScript("OnShow", ApplySavedLayout)
        hooksecurefunc(f, "SetPoint", ApplySavedLayout)

        if f:IsVisible() then ApplySavedLayout(f) end
    end

    hookedFrames[frameName] = true
end

function Module:HookFrameForMove(f)
    HookFrameForMove(f)
end

local function CreateDraggableAnchor(anchorName, labelText, width, height)
    if _G[anchorName] then return end

    local w = width or 250
    local h = height or 60
    local anchor = CreateFrame("Frame", anchorName, _G["WT_UIContainer"], "BackdropTemplate")
    anchor.wtIsActive = false
    anchor:SetSize(w, h)
    anchor:SetFrameStrata("DIALOG")
    anchor:SetFrameLevel(9000)

    if anchor.SetIsFramePositionManaged then
        pcall(function() anchor:SetIsFramePositionManaged(false) end)
    else
        anchor.ignoreInLayout = true
        anchor.ignoreFramePositionManager = true
    end

    local function GetCenterCoords()
        local okC, cX, cY = pcall(anchor.GetCenter, anchor)
        local okU, uX, uY = pcall(UIParent.GetCenter, UIParent)

        cX = (okC and cX) and SafeNum(cX) or 0
        cY = (okC and cY) and SafeNum(cY) or 0
        uX = (okU and uX) and SafeNum(uX) or 0
        uY = (okU and uY) and SafeNum(uY) or 0

        return (cX - uX), (cY - uY)
    end

    local function SavePosition(overrideX, overrideY)
        if not WT.DB.Internal.Positions then WT.DB.Internal.Positions = {} end
        if overrideX and overrideY then
            WT.DB.Internal.Positions[anchorName] = {
                point = "CENTER",
                relativePoint = "CENTER",
                xOfs = overrideX,
                yOfs =
                    overrideY
            }
            return
        end
        local fLeft = anchor:GetLeft()
        local fTop = anchor:GetTop()
        if type(fLeft) == "number" and type(fTop) == "number" then
            local s = anchor:GetEffectiveScale() or 1
            local u = UIParent:GetEffectiveScale() or 1
            if type(s) == "number" and type(u) == "number" then
                local uLeft = UIParent:GetLeft() or 0
                local uBottom = UIParent:GetBottom() or 0
                if type(uLeft) == "number" and type(uBottom) == "number" then
                    local xOfs = ((fLeft * s) - (uLeft * u)) / s
                    local yOfs = ((fTop * s) - (uBottom * u)) / s
                    WT.DB.Internal.Positions[anchorName] = {
                        point = "TOPLEFT",
                        relativeTo = "WT_UIContainer",
                        relativePoint =
                        "BOTTOMLEFT",
                        xOfs = xOfs,
                        yOfs = yOfs
                    }
                    return
                end
            end
        end
        local x, y = GetCenterCoords()
        WT.DB.Internal.Positions[anchorName] = { point = "CENTER", relativePoint = "CENTER", xOfs = x, yOfs = y }
    end

    local function UpdateCoordsDisplay()
        local x, y = GetCenterCoords()
        anchor.coordText:SetText(string.format("X: %.0f | Y: %.0f", x, y))
    end

    -- Load position or center it
    if WT.DB.Internal.Positions and WT.DB.Internal.Positions[anchorName] then
        local p = WT.DB.Internal.Positions[anchorName]
        anchor:ClearAllPoints()
        anchor:SetPoint(p.point, _G["WT_UIContainer"], p.relativePoint, p.xOfs, p.yOfs)
    else
        anchor:SetPoint("TOP", _G["WT_UIContainer"], "TOP", 0, -150)
    end

    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self) self:StartMoving() end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
        UpdateCoordsDisplay()
    end)

    anchor:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            self:Hide()
            self.wtIsActive = false
        elseif button == "MiddleButton" then
            if WT.DB.Internal.Positions then WT.DB.Internal.Positions[anchorName] = nil end
            self.wtIsActive = false
            self:Hide()
            WT.Utils.Logger:Print(WT.L.MSG_TOASTS_RESET)
            ReloadUI()
        end
    end)

    anchor:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    anchor:SetBackdropColor(WT.Colors.STD_BG_R, WT.Colors.STD_BG_G, WT.Colors.STD_BG_B, WT.Colors.STD_BG_A)
    anchor:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.8)

    anchor.text = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    anchor.text:SetPoint("TOP", anchor, "TOP", 0, -8)
    anchor.text:SetText(labelText)

    anchor.subText = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    anchor.subText:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    anchor.subText:SetTextColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 1)
    anchor.subText:SetText(WT.L.LBL_ALERT_HINT_CLOSE)
    anchor.subText:SetWidth(w - 20)
    anchor.subText:SetWordWrap(false)

    anchor.coordText = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    anchor.coordText:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 8)
    anchor.coordText:SetTextColor(1, 1, 1, 1)

    local function CreateNudgeBtn(name, txt, point, relPoint, x, y, nudgeX, nudgeY)
        local btn = CreateFrame("Button", name, anchor, "BackdropTemplate")
        btn:SetSize(24, 24)
        btn:SetPoint(point, anchor, relPoint, x, y)
        btn:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        btn:SetBackdropColor(WT.Colors.STD_BG_R, WT.Colors.STD_BG_G, WT.Colors.STD_BG_B, WT.Colors.STD_BG_A)
        btn:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.8)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("CENTER", 1, -1)
        lbl:SetText(txt)

        btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 1, 1, 1) end)
        btn:SetScript("OnLeave",
            function(self) self:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.8) end)

        btn:SetScript("OnClick", function()
            local step = IsShiftKeyDown() and 10 or 1
            local curX, curY = GetCenterCoords()
            local newX = curX + (nudgeX * step)
            local newY = curY + (nudgeY * step)

            anchor:ClearAllPoints()
            anchor:SetPoint("CENTER", _G["WT_UIContainer"], "CENTER", newX, newY)
            SavePosition(newX, newY)
            anchor.coordText:SetText(string.format("X: %.0f | Y: %.0f", newX, newY))
        end)
        return btn
    end

    CreateNudgeBtn(anchorName .. "_NudgeUp", "^", "BOTTOM", "TOP", 0, 2, 0, 1)
    CreateNudgeBtn(anchorName .. "_NudgeDown", "v", "TOP", "BOTTOM", 0, -2, 0, -1)
    CreateNudgeBtn(anchorName .. "_NudgeLeft", "<", "RIGHT", "LEFT", -2, 0, -1, 0)
    CreateNudgeBtn(anchorName .. "_NudgeRight", ">", "LEFT", "RIGHT", 2, 0, 1, 0)

    anchor:Hide()
    anchor:SetScript("OnShow", UpdateCoordsDisplay)
    anchor:SetScript("OnUpdate", function(self)
        if self:IsDragging() then UpdateCoordsDisplay() end
    end)
end

function Module:SetupAlertAnchor()
    CreateDraggableAnchor("WT_AlertAnchor", WT.L.LBL_ALERT_ANCHOR, 300, 70)
end

function Module:SetupBNetAlertAnchor()
    CreateDraggableAnchor("WT_BNetAlertAnchor", WT.L.LBL_BNET_ALERT_ANCHOR, 250, 50)
end

function Module:SetupRaidBossEmoteAnchor()
    CreateDraggableAnchor("WT_RaidBossEmoteAnchor", WT.L.LBL_RAIDBOSS_ANCHOR, 400, 60)
end

function Module:SetupErrorAnchor()
    CreateDraggableAnchor("WT_ErrorAnchor", WT.L.LBL_ERROR_ANCHOR, 512, 90)
end

function Module:ResetSpecificWindow(targetName)
    local found = false
    for fn, _ in pairs(hookedFrames) do
        if string.lower(fn) == string.lower(targetName) then
            local f = _G[fn]
            if f then
                if InCombatLockdown() and f:IsProtected() then
                    if WT.Utils and WT.Utils.Logger then
                        WT.Utils.Logger:Warn(WT.L.MSG_COMBAT_BLOCK)
                    end
                    return
                end

                local fData = moveData[f]
                if not fData then
                    fData = {}; moveData[f] = fData
                end

                f:SetScale(1.0)
                if WT.DB.Internal.Scales then WT.DB.Internal.Scales[fn] = nil end
                if WT.DB.Internal.Positions then WT.DB.Internal.Positions[fn] = nil end

                fData.isWTSettingPoint = true
                f:ClearAllPoints()
                fData.isWTSettingPoint = false
                if f.SetUserPlaced then pcall(function() f:SetUserPlaced(false) end) end
                ReattachToBlizzardLayout(f)

                if not InCombatLockdown() and UpdateUIPanelPositions then UpdateUIPanelPositions() end

                if WT.Utils.Logger then WT.Utils.Logger:Print(string.format(WT.L.MSG_WINDOW_RESET, fn)) end
                found = true
                break
            end
        end
    end
    if not found then
        if WT.Utils.Logger then WT.Utils.Logger:Print(string.format(WT.L.MSG_WINDOW_NOT_FOUND, targetName)) end
    end
end

function Module:SetupMovableFrames()
    if not WT.DB.Frames.MovableFrames then return end

    if UIPanelWindows then
        for fn, _ in pairs(UIPanelWindows) do HookFrameForMove(fn) end
    end

    for fn, active in pairs(moveWhitelist) do
        if active and _G[fn] then HookFrameForMove(fn) end
    end

    local baseFrames = {
        "CharacterFrame", "BankFrame",
        "TimeManagerFrame", "TradeFrame"
    }
    for _, fn in ipairs(baseFrames) do HookFrameForMove(fn) end

    WT.Core.Events:Register("ADDON_LOADED", function(event, addonNameLoaded)
        if UIPanelWindows then
            for fn, _ in pairs(UIPanelWindows) do
                if _G[fn] and not hookedFrames[fn] then HookFrameForMove(fn) end
            end
        end
        if addonNameLoaded == "Blizzard_Collections" and CollectionsJournal then HookFrameForMove(CollectionsJournal) end
        if addonNameLoaded == "Blizzard_EncounterJournal" and EncounterJournal then HookFrameForMove(EncounterJournal) end
        if addonNameLoaded == "Blizzard_AchievementUI" and AchievementFrame then HookFrameForMove(AchievementFrame) end
        if addonNameLoaded == "Blizzard_MacroUI" and MacroFrame then HookFrameForMove(MacroFrame) end
        if addonNameLoaded == "Blizzard_AuctionHouseUI" and AuctionHouseFrame then HookFrameForMove(AuctionHouseFrame) end
        if addonNameLoaded == "Blizzard_PlayerSpells" and PlayerSpellsFrame then HookFrameForMove(PlayerSpellsFrame) end
        if addonNameLoaded == "Blizzard_Professions" and ProfessionsFrame then HookFrameForMove(ProfessionsFrame) end
    end)
end
