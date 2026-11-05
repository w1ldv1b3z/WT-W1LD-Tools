local _, WT = ...

-- ============================================================================
-- MINIMAP
-- ============================================================================
-- Opt-in minimap tweaks:
--   * Mouse wheel zoom (only on clients without Blizzard's native wheel zoom)
--   * Automatic zoom reset a few seconds after zooming with the mouse wheel
--   * Fixed / recolorable player arrow
-- With all options disabled the minimap is left completely untouched. Turning an
-- option off restores the Blizzard state immediately.

local Module = WT:NewModule("Minimap")

local SafeNum = WT.Utils.Safety.SafeNum

local ZOOM_STEP_DELAY = 0.04
local BLIZZARD_PLAYER_TEXTURE = [[Interface\Minimap\MinimapArrow]]
local HIDDEN_PLAYER_TEXTURE = [[Interface\Common\Spacer]]

function Module:IsSupported()
    return Minimap ~= nil
end

-- ----------------------------------------------------------------------------
-- Zoom
-- ----------------------------------------------------------------------------
local targetZoom = 0
local isZooming = false
local resetTimer
local wheelHooked = false
local nativeWheelZoom      -- does Blizzard's minimap zoom with the mouse wheel on its own?
local blizzardWheelEnabled -- mouse wheel state before WT changed anything

-- Retail's minimap has a native OnMouseWheel handler (MinimapMixin:OnMouseWheel).
-- Determined once, before WT hooks the script.
local function HasNativeWheelZoom()
    if nativeWheelZoom == nil then
        nativeWheelZoom = Minimap:GetScript("OnMouseWheel") ~= nil
        blizzardWheelEnabled = Minimap:IsMouseWheelEnabled()
    end
    return nativeWheelZoom
end

local function GetZoomButtons()
    return _G["MinimapZoomIn"] or Minimap["ZoomIn"], _G["MinimapZoomOut"] or Minimap["ZoomOut"]
end

local function GetMaxZoom()
    return (SafeNum(Minimap:GetZoomLevels()) or 1) - 1
end

local function StepTowardsTargetZoom()
    local current = SafeNum(Minimap:GetZoom()) or 0
    if current == targetZoom then
        isZooming = false
        return
    end

    local newZoom = current < targetZoom and (current + 1) or (current - 1)
    Minimap:SetZoom(newZoom)

    local zoomIn, zoomOut = GetZoomButtons()
    if zoomIn and zoomOut then
        zoomIn:SetEnabled(newZoom < GetMaxZoom())
        zoomOut:SetEnabled(newZoom > 0)
    end

    C_Timer.After(ZOOM_STEP_DELAY, StepTowardsTargetZoom)
end

local function ZoomTo(level)
    targetZoom = level
    if not isZooming then
        isZooming = true
        StepTowardsTargetZoom()
    end
end

local function CancelResetTimer()
    if resetTimer then
        resetTimer:Cancel()
        resetTimer = nil
    end
end

local function OnMouseWheel(_, delta)
    local db = WT.DB.Minimap

    -- Own wheel zoom only where the game has none; otherwise Blizzard already zoomed.
    if db.MouseWheelZoom and not HasNativeWheelZoom() then
        if not isZooming then targetZoom = SafeNum(Minimap:GetZoom()) or 0 end
        local maxZoom = GetMaxZoom()
        if delta > 0 and targetZoom < maxZoom then
            ZoomTo(targetZoom + 1)
        elseif delta < 0 and targetZoom > 0 then
            ZoomTo(targetZoom - 1)
        end
    end

    if db.MinimapAutoReset then
        CancelResetTimer()
        resetTimer = C_Timer.NewTimer(db.MinimapResetTime or 3, function() ZoomTo(0) end)
    end
end

function Module:UpdateZoom()
    local db = WT.DB.Minimap
    local ownWheelZoom = db.MouseWheelZoom and not HasNativeWheelZoom()

    if ownWheelZoom or db.MinimapAutoReset then
        -- Hooks cannot be removed; OnMouseWheel checks the options itself.
        if not wheelHooked then
            Minimap:HookScript("OnMouseWheel", OnMouseWheel)
            wheelHooked = true
        end
    end

    if ownWheelZoom then
        Minimap:EnableMouseWheel(true)
    elseif wheelHooked and Minimap:IsMouseWheelEnabled() ~= blizzardWheelEnabled then
        Minimap:EnableMouseWheel(blizzardWheelEnabled)
    end

    if not db.MinimapAutoReset then CancelResetTimer() end
end

-- ----------------------------------------------------------------------------
-- Player arrow
-- ----------------------------------------------------------------------------
local customArrow
local playerTextureHidden = false  -- true while WT has replaced Blizzard's arrow texture

local function SetBlizzardArrowHidden(hidden)
    if hidden == playerTextureHidden or not Minimap.SetPlayerTexture then return end
    Minimap:SetPlayerTexture(hidden and HIDDEN_PLAYER_TEXTURE or BLIZZARD_PLAYER_TEXTURE)
    playerTextureHidden = hidden
end

local function UpdateArrowRotation(self)
    local facing = 0
    if GetCVar("rotateMinimap") ~= "1" then
        facing = SafeNum(GetPlayerFacing())
    end

    if facing then
        self:SetAlpha(1)
        SetBlizzardArrowHidden(true)
        self.base:SetRotation(facing)
        self.texture:SetRotation(facing)
    else
        -- The game hides the facing inside instances; fall back to Blizzard's rotating arrow
        self:SetAlpha(0)
        SetBlizzardArrowHidden(false)
    end
end

local function CreateCustomArrow()
    local arrow = CreateFrame("Frame", "WT_CustomMinimapArrow", Minimap)
    arrow:SetSize(40, 40)
    arrow:SetPoint("CENTER", Minimap, "CENTER")
    arrow:SetFrameStrata("TOOLTIP") -- draw above map pins (e.g. HandyNotes)
    arrow:SetFrameLevel(100)

    arrow.base = arrow:CreateTexture(nil, "BACKGROUND")
    arrow.base:SetAllPoints()
    arrow.base:SetAtlas("UI-HUD-Minimap-Arrow-Player", true)

    arrow.texture = arrow:CreateTexture(nil, "OVERLAY")
    arrow.texture:SetAllPoints()
    arrow.texture:SetAtlas("UI-HUD-Minimap-Arrow-Player", true)

    arrow:SetScript("OnUpdate", UpdateArrowRotation)
    return arrow
end

function Module:UpdatePlayerArrow()
    local db = WT.DB.Minimap

    if not db.ArrowFix then
        if customArrow then customArrow:Hide() end
        SetBlizzardArrowHidden(false)
        return
    end

    customArrow = customArrow or CreateCustomArrow()
    customArrow:SetScale(db.ArrowScale or 1)
    customArrow:Show()

    if db.ArrowCustomColor then
        local c = db.ArrowColor or {}
        customArrow.base:SetDesaturated(false)
        customArrow.base:SetVertexColor(1, 1, 1, 1)
        customArrow.base:Show()
        customArrow.texture:SetDesaturated(true)
        customArrow.texture:SetVertexColor(c.r or 1, c.g or 1, c.b or 1, c.a or 1)
    else
        customArrow.base:Hide()
        customArrow.texture:SetDesaturated(false)
        customArrow.texture:SetVertexColor(1, 1, 1, 1)
    end
    customArrow.texture:Show()
end

-- ----------------------------------------------------------------------------
-- Module
-- ----------------------------------------------------------------------------
function Module:OnEnable()
    HasNativeWheelZoom() -- capture Blizzard's state before anything is hooked
    self:UpdateZoom()
    self:UpdatePlayerArrow()

    -- Loading screens can reset the minimap player texture
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        if WT.DB.Minimap.ArrowFix then
            playerTextureHidden = false
            self:UpdatePlayerArrow()
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
    local function UpdateZoom() self:UpdateZoom() end
    local function UpdateArrow() self:UpdatePlayerArrow() end

    panel:CreateTitle(builder, WT.L.GROUP_MINIMAP_NAVIGATION)
    AddDescription(WT.L.OPT_DESC_GROUP_MINIMAP_NAV)

    -- Blizzard's own wheel zoom makes this option unnecessary on Retail
    if not HasNativeWheelZoom() then
        panel:CreateCheckbox(builder, WT.L.OPT_MINIMAP_MOUSEWHEEL, WT.L.OPT_DESC_MINIMAP_MOUSEWHEEL, "Minimap", "MouseWheelZoom", UpdateZoom)
    end
    local mmInit = panel:CreateCheckbox(builder, WT.L.OPT_MINIMAP_AUTORESET, WT.L.OPT_DESC_MINIMAP_AUTORESET, "Minimap", "MinimapAutoReset", UpdateZoom)
    panel:CreateSlider(builder, WT.L.OPT_MINIMAP_RESET_TIME, WT.L.OPT_DESC_MINIMAP_RESET_TIME, "Minimap", "MinimapResetTime", 1, 10, 1, nil, mmInit)

    builder:AddSpace(15)
    local arrowFix = panel:CreateCheckbox(builder, WT.L.OPT_MINIMAP_ARROW_FIX, WT.L.OPT_DESC_MINIMAP_ARROW_FIX, "Minimap", "ArrowFix", UpdateArrow)
    AddDescription(WT.L.OPT_MINIMAP_ARROW_INSTANCE_NOTICE)

    panel:CreateSlider(builder, WT.L.OPT_MINIMAP_ARROW_SCALE, WT.L.OPT_DESC_MINIMAP_ARROW_SCALE, "Minimap", "ArrowScale", 0.5, 3.0, 0.1, UpdateArrow, arrowFix)

    local ccb = panel:CreateCheckbox(builder, WT.L.OPT_MINIMAP_ARROW_COLOR_ENABLE, WT.L.OPT_DESC_MINIMAP_ARROW_COLOR_ENABLE, "Minimap", "ArrowCustomColor", UpdateArrow, arrowFix)
    panel:CreateColorPicker(builder, WT.L.OPT_MINIMAP_ARROW_COLOR, WT.L.OPT_DESC_MINIMAP_ARROW_COLOR, "Minimap", "ArrowColor", true, ccb, UpdateArrow, true)
end
