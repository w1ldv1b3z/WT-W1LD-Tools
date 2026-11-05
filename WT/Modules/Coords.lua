local _, WT = ...

WT.Modules.Coords = {}
local Module = WT.Modules.Coords

local mapCoordsFrame

local C_Map_GetPlayerMapPosition = C_Map.GetPlayerMapPosition
local math_floor = math.floor
local string_format = string.format

local SafeNum = WT.Utils.Safety.SafeNum
local Unsecret = WT.Utils.Safety.Unsecret

local function UpdateMapCoordsVisibility()
    if not WT.DB.Coords.ShowMapCoords then 
        if mapCoordsFrame then mapCoordsFrame:Hide() end
        return 
    end
    if WorldMapFrame and WorldMapFrame:IsShown() then
        mapCoordsFrame:Show()
    else
        if mapCoordsFrame then mapCoordsFrame:Hide() end
    end
end

function Module:SetupMapCoords()
    if not WT.DB.Coords.ShowMapCoords then 
        UpdateMapCoordsVisibility()
        return 
    end
    
    if not mapCoordsFrame then
        mapCoordsFrame = CreateFrame("Frame", "WTMapCoords", _G["WT_UIContainer"], "BackdropTemplate")
        
        mapCoordsFrame.ignoreInLayout = true
        mapCoordsFrame.ignoreFramePositionManager = true
        if mapCoordsFrame.SetIsFramePositionManaged then pcall(function() mapCoordsFrame:SetIsFramePositionManaged(false) end) end
        
        WorldMapFrame:HookScript("OnShow", UpdateMapCoordsVisibility)
        WorldMapFrame:HookScript("OnHide", UpdateMapCoordsVisibility)
        
        mapCoordsFrame.text = mapCoordsFrame:CreateFontString(nil, "OVERLAY")
        mapCoordsFrame.text:SetPoint("LEFT", mapCoordsFrame, "LEFT", 10, 0)
        mapCoordsFrame.text:SetJustifyH("LEFT")
        
        mapCoordsFrame:RegisterForDrag("LeftButton")
        mapCoordsFrame:SetScript("OnDragStart", function(self)
            if WT.DB.Coords.Movable and IsAltKeyDown() then
                self:StartMoving()
            end
        end)
        
        mapCoordsFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            
            local left = self:GetLeft()
            local top = self:GetTop()
            if left and top then
                self:ClearAllPoints()
                self:SetPoint("TOPLEFT", _G["WT_UIContainer"], "BOTTOMLEFT", left, top)
            end
            
            local okP, rawP, _, rawRP, rawX, rawY = pcall(self.GetPoint, self)
            local p = okP and Unsecret(rawP) or "TOPLEFT"
            local rP = okP and Unsecret(rawRP) or "BOTTOMLEFT"
            local x, y = okP and SafeNum(rawX) or 0, okP and SafeNum(rawY) or 0
            if not WT.DB.Internal.Positions then WT.DB.Internal.Positions = {} end
            WT.DB.Internal.Positions["WTMapCoords"] = { point = p, relativeTo = "UIParent", relativePoint = rP, xOfs = x, yOfs = y }
        end)
        
        local lastText = ""
        local lastPx, lastPy, lastCx, lastCy, lastHover = -1, -1, -1, -1, false
        
        local strPlayer = tostring(WT.L.MAP_COORDS_PLAYER)
        if strPlayer ~= "" then strPlayer = strPlayer .. " " end
        local strCursor = tostring(WT.L.MAP_COORDS_CURSOR)
        if strCursor ~= "" then strCursor = strCursor .. " " end
        
        local sepStr = WT.DB.Coords.Separator or " | "
        local tc = WT.DB.Coords.TextColor or {r=1, g=0.82, b=0, a=1}
        if type(tc) == "string" then tc = {r=1, g=0.82, b=0, a=1} end
        local colT = string.format("|c%02x%02x%02x%02x", (tc.a or 1) * 255, (tc.r or 1) * 255, (tc.g or 1) * 255, (tc.b or 1) * 255)
        
        local vc = WT.DB.Coords.ValueColor or {r=1, g=1, b=1, a=1}
        if type(vc) == "string" then vc = {r=1, g=1, b=1, a=1} end
        local colV = string.format("|c%02x%02x%02x%02x", (vc.a or 1) * 255, (vc.r or 1) * 255, (vc.g or 1) * 255, (vc.b or 1) * 255)
        
        local sc = WT.DB.Coords.SeparatorColor or {r=0.5, g=0.5, b=0.5, a=1}
        if type(sc) == "string" then sc = {r=0.5, g=0.5, b=0.5, a=1} end
        local colS = string.format("|c%02x%02x%02x%02x", (sc.a or 1) * 255, (sc.r or 1) * 255, (sc.g or 1) * 255, (sc.b or 1) * 255)
        
        mapCoordsFrame:SetScript("OnUpdate", function(self, elapsed)
            self.timer = (self.timer or 0) + elapsed
            if self.timer > 0.05 then
                self.timer = 0
                local okMap, mapIDRaw = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
                local mapID = okMap and SafeNum(mapIDRaw) or nil
                if not mapID or type(mapID) ~= "number" or mapID ~= mapID or mapID <= 0 or mapID >= 2147483647 or math_floor(mapID) ~= mapID then 
                    if lastText ~= "N/A" then
                        mapCoordsFrame.text:SetText("N/A")
                        lastText = "N/A"
                    end
                    return 
                end
                
                local pX, pY = 0, 0
                local okPos, pos = pcall(C_Map_GetPlayerMapPosition, mapID, "player")
                if okPos and pos then pX, pY = SafeNum(pos.x) or 0, SafeNum(pos.y) or 0 end
                if pX ~= pX or pX == math.huge or pX == -math.huge then pX = 0 end
                if pY ~= pY or pY == math.huge or pY == -math.huge then pY = 0 end
                
                local isHovering = WorldMapFrame:IsMouseOver() or WorldMapFrame.ScrollContainer:IsMouseOver()
                local cX, cY = 0, 0
                local validCursor = false
                
                if isHovering then
                    local okCur, rawRX, rawRY = pcall(WorldMapFrame.ScrollContainer.GetNormalizedCursorPosition, WorldMapFrame.ScrollContainer)
                    if okCur and rawRX and rawRY then
                        local rx, ry = SafeNum(rawRX) or 0, SafeNum(rawRY) or 0
                        if rx ~= rx or rx == math.huge or rx == -math.huge then rx = 0 end
                        if ry ~= ry or ry == math.huge or ry == -math.huge then ry = 0 end
                        if rx >= 0 and rx <= 1 and ry >= 0 and ry <= 1 then
                            cX, cY = rx, ry
                            validCursor = true
                        end
                    end
                end
                
                -- PERFORMANCE: Fast numerical check to prevent string allocation spam
                local rPx = math_floor(pX * 1000 + 0.5)
                local rPy = math_floor(pY * 1000 + 0.5)
                local rCx = math_floor(cX * 1000 + 0.5)
                local rCy = math_floor(cY * 1000 + 0.5)
                
                if rPx ~= lastPx or rPy ~= lastPy or rCx ~= lastCx or rCy ~= lastCy or validCursor ~= lastHover then
                    lastPx, lastPy, lastCx, lastCy, lastHover = rPx, rPy, rCx, rCy, validCursor
                    
                    local newText = ""
                    if validCursor then
                        newText = string_format("%s%s|r%s%.1f, %.1f|r%s%s|r%s%s|r%s%.1f, %.1f|r", colT, strPlayer, colV, pX * 100, pY * 100, colS, sepStr, colT, strCursor, colV, cX * 100, cY * 100)
                    else
                        newText = string_format("%s%s|r%s%.1f, %.1f|r", colT, strPlayer, colV, pX * 100, pY * 100)
                    end
                    
                    if lastText ~= newText then
                        mapCoordsFrame.text:SetText(newText)
                        lastText = newText
                        
                        local newWidth = mapCoordsFrame.text:GetStringWidth() + 20
                        if not mapCoordsFrame.wtLastWidth or math.abs(mapCoordsFrame.wtLastWidth - newWidth) > 2 then
                            mapCoordsFrame:SetWidth(newWidth)
                            mapCoordsFrame.wtLastWidth = newWidth
                        end
                    end
                end
            end
        end)
    end
    
    local fontKey = WT.DB.Coords.Font or "Friz Quadrata TT"
    local fontPath = (WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", fontKey)) or "Fonts\\FRIZQT__.TTF"
    local size = WT.DB.Coords.FontSize or 10
    local outline = (WT.DB.Coords.FontOutline == "NONE") and "" or (WT.DB.Coords.FontOutline or "OUTLINE")
    mapCoordsFrame.text:SetFont(fontPath, size, outline)
    mapCoordsFrame:SetHeight(size + 14)
    
    local bg = WT.DB.Coords.BgColor or {r=WT.Colors.STD_BG_R, g=WT.Colors.STD_BG_G, b=WT.Colors.STD_BG_B, a=WT.Colors.STD_BG_A}
    local bc = WT.DB.Coords.BorderColor or {r=1, g=1, b=1, a=1}
    if type(bg) == "string" then bg = {r=WT.Colors.STD_BG_R, g=WT.Colors.STD_BG_G, b=WT.Colors.STD_BG_B, a=WT.Colors.STD_BG_A} end
    if type(bc) == "string" then bc = {r=1, g=1, b=1, a=1} end

    mapCoordsFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    mapCoordsFrame:SetBackdropColor(bg.r or WT.Colors.STD_BG_R, bg.g or WT.Colors.STD_BG_G, bg.b or WT.Colors.STD_BG_B, bg.a or WT.Colors.STD_BG_A)
    mapCoordsFrame:SetBackdropBorderColor(bc.r or 1, bc.g or 1, bc.b or 1, bc.a or 1)
    
    if WT.DB.Coords.Movable then
        mapCoordsFrame:SetParent(_G["WT_UIContainer"])
        mapCoordsFrame:SetFrameStrata(WT.DB.Coords.Strata or "DIALOG")
        mapCoordsFrame:SetMovable(true)
        mapCoordsFrame:EnableMouse(true)
        mapCoordsFrame:ClearAllPoints()
        
        if WT.DB.Internal.Positions and WT.DB.Internal.Positions["WTMapCoords"] then
            local pos = WT.DB.Internal.Positions["WTMapCoords"]
            mapCoordsFrame:SetPoint(pos.point, _G["WT_UIContainer"], pos.relativePoint, pos.xOfs, pos.yOfs)
        else
            mapCoordsFrame:SetPoint("TOPLEFT", _G["WT_UIContainer"], "TOP", -50, -50)
        end
    else
        mapCoordsFrame:SetParent(_G["WT_UIContainer"])
        if WorldMapFrame then mapCoordsFrame:SetFrameStrata(WorldMapFrame:GetFrameStrata()); mapCoordsFrame:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 10) else mapCoordsFrame:SetFrameStrata("HIGH") end
        mapCoordsFrame:SetMovable(false)
        mapCoordsFrame:EnableMouse(false)
        mapCoordsFrame:ClearAllPoints()
        mapCoordsFrame:SetPoint("TOP", WorldMapFrame, "BOTTOM", 0, -2)
    end
    
    UpdateMapCoordsVisibility()
end

function Module:Initialize()
    if not WT.DB.Modules.Maps then return end
    self:SetupMapCoords()
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
    
    panel:CreateTitle(builder, WT.L.GROUP_MAP_COORDS)
    AddDescription(WT.L.OPT_DESC_GROUP_MAP_COORDS)
    
    local showInit = panel:CreateCheckbox(builder, WT.L.OPT_COORDS_SHOW, WT.L.OPT_DESC_COORDS_SHOW, "Coords", "ShowMapCoords", function() self:SetupMapCoords() end)
    
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BG, WT.L.OPT_DESC_COLOR_BG, "Coords", "BgColor", true, showInit, function() self:SetupMapCoords() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BORDER, WT.L.OPT_DESC_COLOR_BORDER, "Coords", "BorderColor", true, showInit, function() self:SetupMapCoords() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LABEL, WT.L.OPT_DESC_COLOR_LABEL, "Coords", "TextColor", true, showInit, function() self:SetupMapCoords() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "Coords", "ValueColor", true, showInit, function() self:SetupMapCoords() end)
    
    local moveInit = panel:CreateCheckbox(builder, WT.L.OPT_COORDS_MOVABLE, WT.L.OPT_DESC_COORDS_MOVABLE, "Coords", "Movable", function() self:SetupMapCoords() end)
    panel:CreateStrataDropdown(builder, WT.L.OPT_STRATA, WT.L.OPT_DESC_STRATA, "Coords", "Strata", function() self:SetupMapCoords() end, showInit)
    
    if WT.Utils and WT.Utils.SharedMedia then
        panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "Coords", "Font", WT.Utils.SharedMedia:GetOptions("font"), function() self:SetupMapCoords() end, showInit)
    end
    panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "Coords", "FontSize", 8, 24, 1, function() self:SetupMapCoords() end, showInit)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "Coords", "FontOutline", function() self:SetupMapCoords() end, showInit)
    local sepInit = panel:CreateEditBox(builder, WT.L.OPT_SEPARATOR, WT.L.OPT_DESC_SEPARATOR, "Coords", "Separator", nil, function() self:SetupMapCoords() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_SEP, WT.L.OPT_DESC_COLOR_SEP, "Coords", "SeparatorColor", true, sepInit, function() self:SetupMapCoords() end)
end
