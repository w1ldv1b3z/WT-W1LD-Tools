local _, WT = ...

WT.Modules.Fader = {}
local Module = WT.Modules.Fader

-- Localize global functions (Upvaluing)
local InCombatLockdown = InCombatLockdown
local GetCursorPosition = GetCursorPosition

----------------------------------------------------------------------
-- FRAME FADER & SCALER (Actionbars, Bags, MicroMenu, etc.)
----------------------------------------------------------------------
local faderFrames = {}
local faderGroupActive = {}
local hoverCache = {}

local faderData = setmetatable({}, { __mode = "k" })

local function SafeMouseIsOver(f)
    local ok, res = pcall(f.IsMouseOver, f)
    return ok and res
end

local function CheckRectIntersection(f, cx, cy, pad)
    local l, b, w, h = f:GetRect()
    if type(l) ~= "number" or type(b) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then return false end
    -- Math operations trigger a taint error if the numbers are secret, cleanly caught by pcall
    return cx >= l - pad and cx <= (l + w) + pad and cy >= b - pad and cy <= (b + h) + pad
end

local Unsecret = WT.Utils.Safety.Unsecret

-- Coordinate math
local cachedActionButtons = nil
local function IsMouseOverFrame(frame, padding, x, y)
    if not frame or not frame:IsVisible() then return false end
    
    -- PERFORMANCE & TAINT: Native C++ check first (pcall protected)
    if SafeMouseIsOver(frame) then return true end
    
    padding = padding or 15
    if not x or not y then x, y = GetCursorPosition() end
    
    -- Fix for MainActionBar: Calculate against the 12 ActionButtons
    if Unsecret(frame:GetName()) == "MainActionBar" then
        if not cachedActionButtons then
            cachedActionButtons = {}; for i = 1, 12 do cachedActionButtons[i] = _G["ActionButton"..i] end
        end
        local scale = frame:GetEffectiveScale()
        if type(scale) ~= "number" then scale = 1 end
        local cx, cy = x / scale, y / scale
        for i = 1, 12 do
            local btn = cachedActionButtons[i]
            if btn and btn:IsVisible() then
                local ok, isInside = pcall(CheckRectIntersection, btn, cx, cy, padding)
                if ok then
                    if isInside then return true end
                elseif SafeMouseIsOver(btn) then
                    return true
                end
            end
        end
        return false
    end
    
    -- Standard exact coordinate calculation for all other frames
    local scale = frame:GetEffectiveScale()
    if type(scale) ~= "number" then scale = 1 end
    local cx, cy = x / scale, y / scale
    local ok, isInside = pcall(CheckRectIntersection, frame, cx, cy, padding)
    if ok then return isInside end
        
    return SafeMouseIsOver(frame)
end

local inCombatState = false

local function FaderOnUpdate(_, elapsed)
    local isCombat = inCombatState
    local isEditMode = EditModeManagerFrame and EditModeManagerFrame:IsShown()
    
    local fadeSpeedIn = WT.DB.Fader.FaderSpeedIn or 8
    local fadeSpeedOut = WT.DB.Fader.FaderSpeedOut or 3
    local baseAlpha = WT.DB.Fader.FaderBaseAlpha or 0
        
    local curX, curY = GetCursorPosition()

    wipe(faderGroupActive)
    wipe(hoverCache)

        -- UX Boost: Show HUD immediately when the player holds an item/spell on the cursor or a menu is open
        local hasCursorItem = GetCursorInfo() ~= nil
        local isFlyoutOpen = SpellFlyout and SpellFlyout:IsShown()
        local forceShow = (isCombat and WT.DB.Fader.FaderShowInCombat) or hasCursorItem or isFlyoutOpen
        
    if not isEditMode then
        for name, frame in pairs(faderFrames) do
            if frame:IsVisible() then
                if not forceShow then
                    hoverCache[name] = IsMouseOverFrame(frame, 15, curX, curY)
                    local mData = faderData[frame]
                    if mData and mData.group and hoverCache[name] then faderGroupActive[mData.group] = true end
                end
            end
        end
    end

    for name, frame in pairs(faderFrames) do
        local mData = faderData[frame]
        if not mData then mData = {}; faderData[frame] = mData end
        
        if isEditMode then
            frame:SetAlpha(1)
            mData.currentAlpha = 1
        elseif frame:IsVisible() then
            local isHovered = hoverCache[name]
            local isGroupHovered = mData.group and faderGroupActive[mData.group]
            
            if isHovered or isGroupHovered or forceShow then
                mData.targetAlpha = 1
            else
                mData.targetAlpha = baseAlpha
            end
            
            local curAlpha = mData.currentAlpha or 1
            if math.abs(curAlpha - mData.targetAlpha) > 0.01 then
                local speed = (mData.targetAlpha > curAlpha) and fadeSpeedIn or fadeSpeedOut
                mData.currentAlpha = curAlpha + (mData.targetAlpha - curAlpha) * (elapsed * speed)
                frame:SetAlpha(mData.currentAlpha)
            else
                if curAlpha ~= mData.targetAlpha then
                    mData.currentAlpha = mData.targetAlpha
                    frame:SetAlpha(mData.targetAlpha)
                end
            end
        end
    end
end

function Module:ApplyFrameFaderAndScaleTweaks()
    if not WT.DB.Modules.Frames then return end
    
    if InCombatLockdown() then
        if WT.Core and WT.Core.CombatQueue then
            WT.Core.CombatQueue:Add("FaderTweaks", true, function() Module:ApplyFrameFaderAndScaleTweaks() end)
        end
        return
    end
    
    -- Granular breakdown of action bars and other HUD elements
    local elements = {
        { name = "MainActionBar",               dbKey = "Bar1",         group = WT.DB.Fader.LinkBar123 and "G123" or (WT.DB.Fader.LinkBar12 and "G12" or nil) },
        { name = "MultiBarBottomLeft",          dbKey = "Bar2",         group = WT.DB.Fader.LinkBar123 and "G123" or (WT.DB.Fader.LinkBar12 and "G12" or nil) },
        { name = "MultiBarBottomRight",         dbKey = "Bar3",         group = WT.DB.Fader.LinkBar123 and "G123" or nil },
        { name = "MultiBarRight",               dbKey = "Bar4",         group = WT.DB.Fader.LinkBar45 and "G45" or nil },
        { name = "MultiBarLeft",                dbKey = "Bar5",         group = WT.DB.Fader.LinkBar45 and "G45" or nil },
        { name = "MultiBar5",                   dbKey = "Bar6",         group = WT.DB.Fader.LinkBar67 and "G67" or nil },
        { name = "MultiBar6",                   dbKey = "Bar7",         group = WT.DB.Fader.LinkBar67 and "G67" or nil },
        { name = "MultiBar7",                   dbKey = "Bar8",         group = nil },
        { name = "StanceBar",                   dbKey = "StanceBar",    group = nil },
        { name = "PetActionBar",                dbKey = "PetBar",       group = nil },
        { name = "BagsBar",                     dbKey = "BagsBar",      group = nil },
        { name = "MicroMenuContainer",          dbKey = "MicroMenu",    group = nil },
        { name = "StatusTrackingBarManager",    dbKey = "StatusBars",   group = nil },
        { name = "MainMenuBarVehicleLeaveButton", dbKey = "VehicleLeave", group = nil },
        { name = "ExtraAbilityContainer",       dbKey = "ExtraAbility", group = nil }
    }

    local baseAlpha = WT.DB.Fader.FaderBaseAlpha or 0
    
    -- Reset registry and clear old settings
    faderFrames = {}
    
    for _, el in ipairs(elements) do
        local frame = _G[el.name]
        if frame then
            local mData = faderData[frame]
            if not mData then mData = {}; faderData[frame] = mData end
            mData.faderKey = el.dbKey
            mData.group = el.group
            
            -- 1. Apply independent scaling
            local scaleVal = WT.DB.Fader["Scale" .. el.dbKey]
            if scaleVal and type(scaleVal) == "number" and scaleVal ~= 1.0 then
                if not InCombatLockdown() then 
                    mData.scaleApplied = true
                    frame:SetScale(scaleVal)
                end
            else
                if mData.scaleApplied and not InCombatLockdown() then
                    mData.scaleApplied = false
                    frame:SetScale(1.0)
                end
            end
            
            -- 2. Register for Fader
            if WT.DB.Fader["Fade" .. el.dbKey] then
                faderFrames[el.name] = frame
                mData.targetAlpha = baseAlpha
                mData.currentAlpha = baseAlpha
                if not InCombatLockdown() then frame:SetAlpha(baseAlpha) end
                mData.faderApplied = true
            else
                if mData.faderApplied then
                    if not InCombatLockdown() then frame:SetAlpha(1) end
                    mData.faderApplied = false
                end
            end
        end
    end

    -- 3. Start or stop the Proximity Watcher
    local hasFaders = false
    for _ in pairs(faderFrames) do hasFaders = true; break end

    if hasFaders then
        if not Module.faderRegistered then 
            WT.Core.Events:RegisterOnUpdate(FaderOnUpdate, 0.03, "Fader")
            Module.faderRegistered = true 
        end
    else
        if Module.faderRegistered then 
            WT.Core.Events:UnregisterOnUpdate(FaderOnUpdate)
            Module.faderRegistered = false 
        end
    end
end

function Module:Initialize()
    if not WT.DB.Modules.Frames then return end
    
    -- Fix: Initialize combat status directly (prevents invisible bars on /rl in combat)
    inCombatState = InCombatLockdown()
    
    WT.Core.Events:Register("PLAYER_REGEN_DISABLED", function() inCombatState = true end)
    WT.Core.Events:Register("PLAYER_REGEN_ENABLED", function() inCombatState = false end)
    
    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function()
            self:ApplyFrameFaderAndScaleTweaks()
        end, self)
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            self:ApplyFrameFaderAndScaleTweaks()
        end, self)
    end
end

WT.Core.Events:Register("PLAYER_LOGIN", function()
    Module:Initialize()
end)

WT.Core.Events:Register("PLAYER_ENTERING_WORLD", function()
    if WT.DB.Modules.Frames then
        Module:ApplyFrameFaderAndScaleTweaks()
    end
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
    
    panel:CreateTitle(builder, WT.L.GROUP_HUD_FADER)
    AddDescription(WT.L.OPT_DESC_MODULE_FADER)
    
    local function HudCb() self:ApplyFrameFaderAndScaleTweaks() end
    
    panel:CreateCheckbox(builder, WT.L.OPT_FADER_COMBAT, WT.L.OPT_DESC_FADER_COMBAT, "Fader", "FaderShowInCombat", HudCb)
    panel:CreateSlider(builder, WT.L.OPT_FADER_ALPHA, WT.L.OPT_DESC_FADER_ALPHA, "Fader", "FaderBaseAlpha", 0, 1.0, 0.1, HudCb)
    panel:CreateSlider(builder, WT.L.OPT_FADER_SPEED_IN, WT.L.OPT_DESC_FADER_SPEED_IN, "Fader", "FaderSpeedIn", 1, 20, 1, HudCb)
    panel:CreateSlider(builder, WT.L.OPT_FADER_SPEED_OUT, WT.L.OPT_DESC_FADER_SPEED_OUT, "Fader", "FaderSpeedOut", 1, 20, 1, HudCb)
    
    panel:CreateTitle(builder, WT.L.GROUP_HUD_LINKS)
    AddDescription(WT.L.OPT_DESC_GROUP_HUD_LINKS)
    panel:CreateCheckbox(builder, WT.L.OPT_LINK_12, WT.L.OPT_DESC_LINK_12, "Fader", "LinkBar12", HudCb)
    panel:CreateCheckbox(builder, WT.L.OPT_LINK_123, WT.L.OPT_DESC_LINK_123, "Fader", "LinkBar123", HudCb)
    panel:CreateCheckbox(builder, WT.L.OPT_LINK_45, WT.L.OPT_DESC_LINK_45, "Fader", "LinkBar45", HudCb)
    panel:CreateCheckbox(builder, WT.L.OPT_LINK_67, WT.L.OPT_DESC_LINK_67, "Fader", "LinkBar67", HudCb)
    
    panel:CreateTitle(builder, WT.L.GROUP_HUD_ELEMENTS)
    AddDescription(WT.L.OPT_DESC_GROUP_HUD_ELEMENTS)
    panel:CreateScaleFadeRow(builder, WT.L.LBL_BAR1, WT.L.OPT_DESC_SCALE_FADE, "Fader", "ScaleBar1", "FadeBar1", 1.0, HudCb)
    panel:CreateScaleFadeRow(builder, WT.L.LBL_BAR2, WT.L.OPT_DESC_SCALE_FADE, "Fader", "ScaleBar2", "FadeBar2", 1.0, HudCb)
    panel:CreateScaleFadeRow(builder, WT.L.LBL_BAR3, WT.L.OPT_DESC_SCALE_FADE, "Fader", "ScaleBar3", "FadeBar3", 1.0, HudCb)
    panel:CreateScaleFadeRow(builder, WT.L.LBL_BAR4, WT.L.OPT_DESC_SCALE_FADE, "Fader", "ScaleBar4", "FadeBar4", 1.0, HudCb)
    panel:CreateScaleFadeRow(builder, WT.L.LBL_BAR5, WT.L.OPT_DESC_SCALE_FADE, "Fader", "ScaleBar5", "FadeBar5", 1.0, HudCb)
    panel:CreateScaleFadeRow(builder, WT.L.LBL_BAR6, WT.L.OPT_DESC_SCALE_FADE, "Fader", "ScaleBar6", "FadeBar6", 1.0, HudCb)
    panel:CreateScaleFadeRow(builder, WT.L.LBL_BAR7, WT.L.OPT_DESC_SCALE_FADE, "Fader", "ScaleBar7", "FadeBar7", 1.0, HudCb)
    panel:CreateScaleFadeRow(builder, WT.L.LBL_BAR8, WT.L.OPT_DESC_SCALE_FADE, "Fader", "ScaleBar8", "FadeBar8", 1.0, HudCb)
    panel:CreateScaleFadeRow(builder, WT.L.LBL_PETBAR, WT.L.OPT_DESC_SCALE_FADE, "Fader", "ScalePetBar", "FadePetBar", 1.0, HudCb)
    panel:CreateScaleFadeRow(builder, WT.L.LBL_STANCEBAR, WT.L.OPT_DESC_SCALE_FADE, "Fader", "ScaleStanceBar", "FadeStanceBar", 1.0, HudCb)
    panel:CreateScaleFadeRow(builder, WT.L.LBL_BAGSBAR, WT.L.OPT_DESC_SCALE_FADE, "Fader", "ScaleBagsBar", "FadeBagsBar", 1.0, HudCb)
    panel:CreateScaleFadeRow(builder, WT.L.LBL_MICROMENU, WT.L.OPT_DESC_SCALE_FADE, "Fader", "ScaleMicroMenu", "FadeMicroMenu", 1.0, HudCb)
    panel:CreateScaleFadeRow(builder, WT.L.LBL_STATUSBARS, WT.L.OPT_DESC_SCALE_FADE, "Fader", "ScaleStatusBars", "FadeStatusBars", 1.0, HudCb)
    panel:CreateScaleFadeRow(builder, WT.L.LBL_VEHICLELEAVE, WT.L.OPT_DESC_SCALE_FADE, "Fader", "ScaleVehicleLeave", "FadeVehicleLeave", 1.0, HudCb)
    panel:CreateScaleFadeRow(builder, WT.L.LBL_EXTRA_ABILITY, WT.L.OPT_DESC_SCALE_FADE, "Fader", "ScaleExtraAbility", "FadeExtraAbility", 1.0, HudCb)
end