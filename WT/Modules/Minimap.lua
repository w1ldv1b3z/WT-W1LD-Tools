local addonName, WT = ...

WT.Modules.Minimap = {}
local Module = WT.Modules.Minimap

local minimapResetTimer
local targetMinimapZoom = 0
local isMinimapZooming = false
local zoomInBtn, zoomOutBtn

local C_Timer_After = C_Timer.After
local C_Timer_NewTimer = C_Timer.NewTimer

local SafeNum = WT.Utils.Safety.SafeNum

local function SmoothMinimapZoom()
    local okZ, cZ = pcall(Minimap.GetZoom, Minimap)
    local currentZoom = okZ and SafeNum(cZ) or 0
    if currentZoom == targetMinimapZoom then
        isMinimapZooming = false
        return
    end
    
    -- Performance: Avoid redundant API calls by calculating the new zoom directly
    local newZoom = currentZoom < targetMinimapZoom and (currentZoom + 1) or (currentZoom - 1)
    Minimap:SetZoom(newZoom)
    
    -- Caching: Look up global variables only once and store them for future ticks
    if not zoomInBtn then zoomInBtn = _G["MinimapZoomIn"] or (Minimap and Minimap["ZoomIn"]) end
    if not zoomOutBtn then zoomOutBtn = _G["MinimapZoomOut"] or (Minimap and Minimap["ZoomOut"]) end
    
    if zoomInBtn and zoomOutBtn then
        local okM, mZ = pcall(Minimap.GetZoomLevels, Minimap)
        local maxZoom = (okM and SafeNum(mZ) or 1) - 1
        if newZoom == maxZoom then zoomInBtn:Disable() else zoomInBtn:Enable() end
        if newZoom == 0 then zoomOutBtn:Disable() else zoomOutBtn:Enable() end
    end
    
    C_Timer_After(0.04, SmoothMinimapZoom)
end

local function ExecuteMinimapReset()
    targetMinimapZoom = 0
    if not isMinimapZooming then
        isMinimapZooming = true
        SmoothMinimapZoom()
    end
end

local customArrow

function Module:UpdatePlayerArrow()
    if not Minimap then return end
    
    local scale = WT.DB.Minimap.ArrowScale or 0.80
    local isFixed = WT.DB.Minimap.ArrowFix
    local customColorEnable = WT.DB.Minimap.ArrowCustomColor
    local color = WT.DB.Minimap.ArrowColor or {r=1, g=1, b=1}
    
    if not WT_MinimapArrowUpdater then
        WT_MinimapArrowUpdater = CreateFrame("Frame")
    end
    -- Clean up the temporary update loop from the failed native attempt
    if WT_MinimapArrowUpdater then
        WT_MinimapArrowUpdater:SetScript("OnUpdate", nil)
    end
    
    if isFixed then
        if not customArrow then
            customArrow = CreateFrame("Frame", "WT_CustomMinimapArrow", Minimap)
            customArrow:SetSize(40, 40)
            customArrow:SetPoint("CENTER", Minimap, "CENTER")
            customArrow:SetFrameStrata("TOOLTIP") -- Draw above HandyNotes!
            customArrow:SetFrameLevel(100)
            
            local base = customArrow:CreateTexture(nil, "BACKGROUND")
            base:SetAllPoints()
            base:SetAtlas("UI-HUD-Minimap-Arrow-Player", true)
            customArrow.base = base
            
            local tex = customArrow:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints()
            tex:SetAtlas("UI-HUD-Minimap-Arrow-Player", true)
            customArrow.texture = tex
            
            customArrow:SetScript("OnUpdate", function(self)
                local inRestrictedArea = false
                local rot = 0
                if GetCVar("rotateMinimap") ~= "1" then
                    local facing = GetPlayerFacing()
                    if facing then 
                        rot = facing 
                    else
                        inRestrictedArea = true
                    end
                end
                
                if inRestrictedArea then
                    self:SetAlpha(0)
                    if Minimap.SetPlayerTexture then
                        Minimap:SetPlayerTexture([[Interface\Minimap\MinimapArrow]])
                    end
                else
                    self:SetAlpha(1)
                    if Minimap.SetPlayerTexture then
                        Minimap:SetPlayerTexture([[Interface\Common\Spacer]])
                    end
                    self.base:SetRotation(rot)
                    self.texture:SetRotation(rot)
                end
            end)
        end
        
        customArrow:SetScale(scale)
        customArrow:Show()
        
        if customColorEnable then
            customArrow.base:SetDesaturated(false)
            customArrow.base:SetVertexColor(1, 1, 1, 1)
            customArrow.base:Show()
            
            customArrow.texture:SetDesaturated(true)
            customArrow.texture:SetVertexColor(color.r, color.g, color.b, color.a or 1)
            customArrow.texture:Show()
        else
            customArrow.base:Hide()
            
            customArrow.texture:SetDesaturated(false)
            customArrow.texture:SetVertexColor(1, 1, 1, 1)
            customArrow.texture:Show()
        end
    else
        if customArrow then customArrow:Hide() end
        if Minimap.SetPlayerTexture then
            Minimap:SetPlayerTexture([[Interface\Minimap\MinimapArrow]])
        end
    end
end

function Module:EnableMouseWheelZoom(enable)
    if enable then
        Minimap:EnableMouseWheel(true)
        if not self.wheelHooked then
            Minimap:HookScript("OnMouseWheel", function(minimap, delta)
                if not WT.DB.Minimap.MouseWheelZoom then return end
                
                local okM, mZ = pcall(minimap.GetZoomLevels, minimap)
                local maxZoom = (okM and SafeNum(mZ) or 1) - 1
                if not isMinimapZooming then
                    local okZ, cZ = pcall(minimap.GetZoom, minimap)
                    targetMinimapZoom = okZ and SafeNum(cZ) or 0
                end
                
                local oldTarget = targetMinimapZoom
                
                if delta > 0 and targetMinimapZoom < maxZoom then
                    targetMinimapZoom = targetMinimapZoom + 1
                elseif delta < 0 and targetMinimapZoom > 0 then
                    targetMinimapZoom = targetMinimapZoom - 1
                end
                
                if oldTarget ~= targetMinimapZoom and not isMinimapZooming then
                    isMinimapZooming = true
                    SmoothMinimapZoom()
                end
                
                if WT.DB.Minimap.MinimapAutoReset then
                    if minimapResetTimer then minimapResetTimer:Cancel() end
                    minimapResetTimer = C_Timer_NewTimer(WT.DB.Minimap.MinimapResetTime or 3, ExecuteMinimapReset)
                end
            end)
            self.wheelHooked = true
        end
    else
        Minimap:EnableMouseWheel(false)
        if minimapResetTimer then minimapResetTimer:Cancel() end
    end
end

function Module:Initialize()
    if not WT.DB.Modules.Maps then return end
    self:EnableMouseWheelZoom(WT.DB.Minimap.MouseWheelZoom)
    self:UpdatePlayerArrow()
end

WT.Core.Events:Register("PLAYER_LOGIN", function()
    Module:Initialize()
end)

WT.Core.Events:Register("PLAYER_ENTERING_WORLD", function()
    if WT.DB.Modules.Maps then
        Module:UpdatePlayerArrow()
    end
end)

-- Function to build the module's option panel
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
    
    panel:CreateTitle(builder, WT.L.GROUP_MINIMAP_NAVIGATION)
    AddDescription(WT.L.OPT_DESC_GROUP_MINIMAP_NAV)
    
    panel:CreateCheckbox(builder, WT.L.OPT_MINIMAP_MOUSEWHEEL, WT.L.OPT_DESC_MINIMAP_MOUSEWHEEL, "Minimap", "MouseWheelZoom", function(value) self:EnableMouseWheelZoom(value) end)
    local mmInit = panel:CreateCheckbox(builder, WT.L.OPT_MINIMAP_AUTORESET, WT.L.OPT_DESC_MINIMAP_AUTORESET, "Minimap", "MinimapAutoReset")
    panel:CreateSlider(builder, WT.L.OPT_MINIMAP_RESET_TIME, WT.L.OPT_DESC_MINIMAP_RESET_TIME, "Minimap", "MinimapResetTime", 1, 10, 1, nil, mmInit)
    
    builder:AddSpace(15)
    local arrowFix = panel:CreateCheckbox(builder, WT.L.OPT_MINIMAP_ARROW_FIX, WT.L.OPT_DESC_MINIMAP_ARROW_FIX, "Minimap", "ArrowFix", function() self:UpdatePlayerArrow() end)
    AddDescription(WT.L.OPT_MINIMAP_ARROW_INSTANCE_NOTICE)
    
    panel:CreateSlider(builder, WT.L.OPT_MINIMAP_ARROW_SCALE, WT.L.OPT_DESC_MINIMAP_ARROW_SCALE, "Minimap", "ArrowScale", 0.5, 3.0, 0.1, function() self:UpdatePlayerArrow() end, arrowFix)
    
    local ccb = panel:CreateCheckbox(builder, WT.L.OPT_MINIMAP_ARROW_COLOR_ENABLE, WT.L.OPT_DESC_MINIMAP_ARROW_COLOR_ENABLE, "Minimap", "ArrowCustomColor", function() self:UpdatePlayerArrow() end, arrowFix)
    panel:CreateColorPicker(builder, WT.L.OPT_MINIMAP_ARROW_COLOR, WT.L.OPT_DESC_MINIMAP_ARROW_COLOR, "Minimap", "ArrowColor", true, ccb, function() self:UpdatePlayerArrow() end, true)
end