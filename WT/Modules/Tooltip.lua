local _, WT = ...

WT.Modules.Tooltip = {}
local Module = WT.Modules.Tooltip

local sbHooked = setmetatable({}, { __mode = "k" })
local sbColoring = setmetatable({}, { __mode = "k" })
Module.TooltipClassCache = setmetatable({}, { __mode = "k" })
local styleHooked = setmetatable({}, { __mode = "k" })
local isStyling = setmetatable({}, { __mode = "k" })

local strtrim = strtrim or string.trim or function(s) return s and string.match(s, "^%s*(.-)%s*$") or "" end

local ALL_TOOLTIPS = {
    "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
    "GameSmallTooltip", "NamePlateTooltip", "QuickKeybindTooltip",
    "BattlePetTooltip", "PetBattlePrimaryUnitTooltip", "PetBattlePrimaryAbilityTooltip",
    "FloatingBattlePetTooltip", "FloatingGarrisonPetTooltip", "FloatingPetBattleAbilityTooltip",
    "ReputationParagonTooltip", "LibDBIconTooltip", "DatatextTooltip", "WTSocialTooltip", "WTCustomTooltip"
}

local SafeNum = WT.Utils.Safety.SafeNum
local Unsecret = WT.Utils.Safety.Unsecret

local function IsHouseFrame(frame)
    if type(frame) ~= "table" then return false end
    
    -- SECURITY FIX: Dynamically generated list elements (like HouseListButtons)
    -- are often anonymous and lack "House" in their names. We reliably detect
    -- them by checking for the existence of the specific data provider fields.
    if rawget(frame, "houseInfo") then return true end

    local current = frame
    for i = 1, 10 do
        if not current then break end
        if current == _G["HouseListFrame"] or current == _G["HouseEditorFrame"] then return true end
        if type(current.GetName) == "function" then
            local ok, nameRaw = pcall(current.GetName, current)
            if ok and nameRaw then
                local name = WT.Utils.Safety.Unsecret(nameRaw)
                if name and (string.match(name, "House") or string.match(name, "Housing")) then return true end
            end
        end
        if type(current.GetParent) == "function" then
            local ok, parent = pcall(current.GetParent, current)
            if ok and parent then current = parent else break end
        else break end
    end
    return false
end

local function GetSafeString(str)
    if type(str) ~= "string" then return nil end
    return Unsecret(str)
end

function Module:HookHealthBar(bar)
    if not bar or sbHooked[bar] then return end
    sbHooked[bar] = true
    
    hooksecurefunc(bar, "SetStatusBarColor", function(self)
        if not WT.DB.Tooltip or not WT.DB.Tooltip.HealthBar or sbColoring[self] then return end
        local tooltip = self:GetParent()
        if not tooltip or tooltip:IsForbidden() then return end
        local r, g, b
        local style = WT.DB.Tooltip.HealthBarColorStyle or "CLASS_UNIT"
        if style == "CLASS_UNIT" then
            local class = Module.TooltipClassCache[tooltip]
            local color = class and (WT.DB.ClassColors and WT.DB.ClassColors[class] or RAID_CLASS_COLORS[class])
            if color then 
                r, g, b = color.r, color.g, color.b 
            elseif WT.DB.Tooltip.HealthBarForceFallback then
                local hc = WT.DB.Tooltip.HealthBarColor or {r=0, g=1, b=0, a=1}
                r, g, b = hc.r or 0, hc.g or 1, hc.b or 0
            end
        elseif style == "CLASS_PLAYER" then
            local _, class = UnitClass("player")
            local color = class and (WT.DB.ClassColors and WT.DB.ClassColors[class] or RAID_CLASS_COLORS[class])
            if color then r, g, b = color.r, color.g, color.b end
        else
            local hc = WT.DB.Tooltip.HealthBarColor or {r=0, g=1, b=0, a=1}
            r, g, b = hc.r or 0, hc.g or 1, hc.b or 0
        end
        if r and g and b then
            local okC, curR, curG, curB = pcall(self.GetStatusBarColor, self)
            local sR, sG, sB = okC and SafeNum(curR) or 0, okC and SafeNum(curG) or 0, okC and SafeNum(curB) or 0
            if sR and math.abs(sR - r) < 0.01 and math.abs(sG - g) < 0.01 and math.abs(sB - b) < 0.01 then
                return
            end
            sbColoring[self] = true
            self:SetStatusBarColor(r, g, b)
            sbColoring[self] = false
        end
    end)
    
    bar:HookScript("OnShow", function(self)
        if not WT.DB.Tooltip then return end
        if WT.DB.Tooltip.HideHealthBar then
            self:SetAlpha(0)
        else
            self:SetAlpha(1)
            if WT.DB.Tooltip.HealthBarHeight then
                self:SetHeight(WT.DB.Tooltip.HealthBarHeight)
            end
        end
    end)
end

local function SetupHealthBar()
    if _G["GameTooltipStatusBar"] then Module:HookHealthBar(_G["GameTooltipStatusBar"]) end
    if GameTooltip["healthBar"] and GameTooltip["healthBar"] ~= _G["GameTooltipStatusBar"] then Module:HookHealthBar(GameTooltip["healthBar"]) end
    if GameTooltip["HealthBar"] and GameTooltip["HealthBar"] ~= _G["GameTooltipStatusBar"] then Module:HookHealthBar(GameTooltip["HealthBar"]) end
    if GameTooltip["statusBar"] and GameTooltip["statusBar"] ~= _G["GameTooltipStatusBar"] then Module:HookHealthBar(GameTooltip["statusBar"]) end
    if GameTooltip["StatusBar"] and GameTooltip["StatusBar"] ~= _G["GameTooltipStatusBar"] then Module:HookHealthBar(GameTooltip["StatusBar"]) end
end

local function UpdateTooltipPosition(self)
    if self.wtCursorAnchor and WT.DB.Tooltip and WT.DB.Tooltip.CursorAnchor then
        local owner = self:GetOwner()
        if owner and not IsHouseFrame(owner) then
            local x, y = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            if scale and scale > 0 then
                x = x / scale
                y = y / scale
                
                local offsetX = WT.DB.Tooltip.CursorAnchorX or 0
                local offsetY = WT.DB.Tooltip.CursorAnchorY or 0
                local anchorType = WT.DB.Tooltip.CursorAnchorType or "ANCHOR_CURSOR_RIGHT"
                
                self:ClearAllPoints()
                if anchorType == "ANCHOR_CURSOR_RIGHT" then
                    self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + 15 + offsetX, y - 15 + offsetY)
                elseif anchorType == "ANCHOR_CURSOR_LEFT" then
                    self:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x - 15 + offsetX, y - 15 + offsetY)
                else
                    self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x + offsetX, y + offsetY)
                end
            end
        end
    end
end

local function SetupCursorAnchor()
    if not Module.cursorHooked then
        Module.cursorHooked = true
        hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
            if WT.DB.Tooltip and WT.DB.Tooltip.CursorAnchor then
                if IsHouseFrame(parent) then 
                    tooltip.wtCursorAnchor = false
                    return 
                end
                
                -- We use a manual OnUpdate script to track the cursor.
                -- This bypasses the native ANCHOR_CURSOR C++ bugs that cause flickering
                -- and inconsistency on UnitFrames (like PlayerFrame) that update frequently.
                if not tooltip.wtCursorHooked then
                    tooltip.wtCursorHooked = true
                    tooltip:HookScript("OnUpdate", function(self)
                        UpdateTooltipPosition(self)
                    end)
                    tooltip:HookScript("OnTooltipCleared", function(self)
                        self.wtCursorAnchor = false
                    end)
                end
                
                tooltip.wtCursorAnchor = true
                UpdateTooltipPosition(tooltip)
            else
                tooltip.wtCursorAnchor = false
            end
        end)
    end
end

local function SetupSpellTooltip()
    if not TooltipDataProcessor then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
        if tooltip:IsForbidden() then return end
        if type(tooltip.AddDoubleLine) ~= "function" then return end
        if not WT.DB.Modules.Tooltip then return end
        local safeId = data and SafeNum(data.id)
        if WT.DB.Tooltip and WT.DB.Tooltip.NerdIDs and WT.DB.Tooltip.NerdIDsSpells ~= false and safeId then
            local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColNerdL, 0.5, 0.5, 0.5)
            local vr, vg, vb = WT.Colors:GetRGB(WT.DB.Tooltip.ColNerdV, 1, 1, 1)
            tooltip:AddDoubleLine(tostring(WT.L.TT_SPELL_ID), tostring(safeId), lr, lg, lb, vr, vg, vb)
        end
    end)
end

local function SetupMiscTooltips()
    if not TooltipDataProcessor then return end

    if Enum.TooltipDataType.Quest then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Quest, function(tooltip, data)
            if tooltip:IsForbidden() then return end
            if type(tooltip.AddDoubleLine) ~= "function" then return end
            if not WT.DB.Modules.Tooltip then return end
            local safeId = data and SafeNum(data.id)
            if WT.DB.Tooltip and WT.DB.Tooltip.NerdIDs and WT.DB.Tooltip.NerdIDsQuests ~= false and safeId then
                local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColNerdL, 0.5, 0.5, 0.5)
                local vr, vg, vb = WT.Colors:GetRGB(WT.DB.Tooltip.ColNerdV, 1, 1, 1)
                tooltip:AddDoubleLine(tostring(WT.L.TT_QUEST_ID), tostring(safeId), lr, lg, lb, vr, vg, vb)
            end
        end)
    end

    if Enum.TooltipDataType.UnitAura then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, function(tooltip, data)
            if tooltip:IsForbidden() then return end
            if type(tooltip.AddDoubleLine) ~= "function" then return end
            if not WT.DB.Modules.Tooltip then return end
            local safeId = data and SafeNum(data.id)
            if WT.DB.Tooltip and WT.DB.Tooltip.NerdIDs and WT.DB.Tooltip.NerdIDsSpells ~= false and safeId then
                local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColNerdL, 0.5, 0.5, 0.5)
                local vr, vg, vb = WT.Colors:GetRGB(WT.DB.Tooltip.ColNerdV, 1, 1, 1)
                tooltip:AddDoubleLine(tostring(WT.L.TT_SPELL_ID), tostring(safeId), lr, lg, lb, vr, vg, vb)
            end
        end)
    end
    
    if Enum.TooltipDataType.Currency then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Currency, function(tooltip, data)
            if tooltip:IsForbidden() then return end
            if type(tooltip.AddDoubleLine) ~= "function" then return end
            if not WT.DB.Modules.Tooltip then return end
            local safeId = data and SafeNum(data.id)
            if WT.DB.Tooltip and WT.DB.Tooltip.NerdIDs and WT.DB.Tooltip.NerdIDsCurrency ~= false and safeId then
                local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColNerdL, 0.5, 0.5, 0.5)
                local vr, vg, vb = WT.Colors:GetRGB(WT.DB.Tooltip.ColNerdV, 1, 1, 1)
                tooltip:AddDoubleLine(tostring(WT.L.TT_CURRENCY_ID), tostring(safeId), lr, lg, lb, vr, vg, vb)
            end
        end)
    end
    
    if Enum.TooltipDataType.Mount then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Mount, function(tooltip, data)
            if tooltip:IsForbidden() then return end
            if type(tooltip.AddDoubleLine) ~= "function" then return end
            if not WT.DB.Modules.Tooltip then return end
            local safeId = data and SafeNum(data.id)
            if WT.DB.Tooltip and WT.DB.Tooltip.NerdIDs and WT.DB.Tooltip.NerdIDsMounts ~= false and safeId then
                local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColNerdL, 0.5, 0.5, 0.5)
                local vr, vg, vb = WT.Colors:GetRGB(WT.DB.Tooltip.ColNerdV, 1, 1, 1)
                tooltip:AddDoubleLine(tostring(WT.L.TT_MOUNT_ID), tostring(safeId), lr, lg, lb, vr, vg, vb)
            end
        end)
    end
end

function Module:UpdateTooltipStrata()
    if not WT.DB.Tooltip then return end
    local strata = WT.DB.Tooltip.Strata or "TOOLTIP"
    for _, name in ipairs(ALL_TOOLTIPS) do
        local tt = _G[name]
        if tt and not tt:IsForbidden() and tt:GetFrameStrata() ~= strata then tt:SetFrameStrata(strata) end
    end
end

function Module:ApplyStyle(tooltip)
    local owner = type(tooltip.GetOwner) == "function" and tooltip:GetOwner() or nil
    if IsHouseFrame(owner) then return end

    local nineSlice = tooltip["NineSlice"] or tooltip.NineSlice
    if not nineSlice then return end

    if WT.DB.Tooltip.SolidBackground then
        pcall(function()
            if tooltip.TopOverlay then tooltip.TopOverlay:SetAlpha(0) end
            if tooltip.BottomOverlay then tooltip.BottomOverlay:SetAlpha(0) end
            if tooltip.CenterOverlay then tooltip.CenterOverlay:SetAlpha(0) end
        end)
        
        if nineSlice["Center"] then nineSlice["Center"]:SetTexture("Interface\\ChatFrame\\ChatFrameBackground") end
        local c = WT.DB.Tooltip.BgColor or {r=0, g=0, b=0, a=0.8}
        nineSlice:SetCenterColor(c.r or 0, c.g or 0, c.b or 0, c.a or 0.8)
    else
        pcall(function()
            if tooltip.TopOverlay then tooltip.TopOverlay:SetAlpha(1) end
            if tooltip.BottomOverlay then tooltip.BottomOverlay:SetAlpha(1) end
            if tooltip.CenterOverlay then tooltip.CenterOverlay:SetAlpha(1) end
        end)
    end

    local r, g, b, a = WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 1
    
    if WT.DB.Tooltip.CustomBorderColor and WT.DB.Tooltip.BorderColor then
        local bc = WT.DB.Tooltip.BorderColor
        r, g, b, a = bc.r or 1, bc.g or 1, bc.b or 1, bc.a or 1
    end
    
    if WT.DB.Tooltip.ClassColorBorderUnit then
        local class = Module.TooltipClassCache[tooltip]
        if class then
            local color = WT.DB.ClassColors and WT.DB.ClassColors[class] or RAID_CLASS_COLORS[class]
            if color then
                r, g, b = color.r, color.g, color.b
            end
        end
    end
    
    nineSlice:SetBorderColor(r, g, b, a)
end

function Module:UpdateTooltipStyle(tooltip)
    if not tooltip or not WT.DB.Tooltip then return end
    if tooltip:IsForbidden() then return end
    
    local owner = type(tooltip.GetOwner) == "function" and tooltip:GetOwner() or nil
    if IsHouseFrame(owner) then return end
    
    local nineSlice = tooltip["NineSlice"] or tooltip.NineSlice
    if not nineSlice then return end
    
    if not styleHooked[tooltip] then
        styleHooked[tooltip] = true
        if type(nineSlice.SetCenterColor) == "function" then
            hooksecurefunc(nineSlice, "SetCenterColor", function()
                if isStyling[tooltip] then return end
                isStyling[tooltip] = true
                Module:ApplyStyle(tooltip)
                isStyling[tooltip] = false
            end)
        end
        if type(nineSlice.SetBorderColor) == "function" then
            hooksecurefunc(nineSlice, "SetBorderColor", function()
                if isStyling[tooltip] then return end
                isStyling[tooltip] = true
                Module:ApplyStyle(tooltip)
                isStyling[tooltip] = false
            end)
        end
    end
    
    isStyling[tooltip] = true
    self:ApplyStyle(tooltip)
    isStyling[tooltip] = false
end

function Module:UpdateAllTooltipStyles()
    for _, name in ipairs(ALL_TOOLTIPS) do
        if _G[name] then self:UpdateTooltipStyle(_G[name]) end
    end
end

function Module:UpdateTooltipAlpha()
    local alpha = WT.DB.Tooltip and WT.DB.Tooltip.Alpha or 1.0
    local hideInCombat = WT.DB.Tooltip and WT.DB.Tooltip.HideInCombat and InCombatLockdown()
    
    for _, name in ipairs(ALL_TOOLTIPS) do
        local tt = _G[name]
        if tt and tt:IsShown() and not tt:IsForbidden() then
            local isUnit = false
            if tt.GetTooltipData then
                local ttData = tt:GetTooltipData()
                if ttData and ttData.type == Enum.TooltipDataType.Unit then isUnit = true end
            end
            if not isUnit and tt.GetUnit then if tt:GetUnit() then isUnit = true end end
            
            local isActionBar = false
            local owner = type(tt.GetOwner) == "function" and tt:GetOwner() or nil
            if owner and (owner.action or type(owner.GetAction) == "function") then isActionBar = true end
            
            if WT.DB.Tooltip.AlwaysShowActionBars and isActionBar then
                tt:SetAlpha(1.0)
                if not tt:IsShown() then tt:Show() end
            else
                if hideInCombat and isUnit then 
                    tt:SetAlpha(0)
                    tt:Hide() 
                else 
                    tt:SetAlpha(alpha) 
                end
            end
        end
    end
end

local function OnTooltipShow(selfTT)
    if selfTT:IsForbidden() then return end
    
    local owner = type(selfTT.GetOwner) == "function" and selfTT:GetOwner() or nil
    if IsHouseFrame(owner) then return end

    local isActionBar = false
    if owner and (owner.action or type(owner.GetAction) == "function") then isActionBar = true end
    
    if WT.DB.Tooltip.AlwaysShowActionBars and isActionBar then
        selfTT:SetAlpha(1.0)
    else
        -- Restore visibility if the tooltip was hidden during combat, applying user alpha
        local targetAlpha = WT.DB.Tooltip.Alpha or 1.0
        selfTT:SetAlpha(targetAlpha)
        
        if WT.DB.Tooltip.HideInCombat and InCombatLockdown() then
            local isUnit = false
            if selfTT.GetTooltipData then
                local ttData = selfTT:GetTooltipData()
                if ttData and ttData.type == Enum.TooltipDataType.Unit then
                    isUnit = true
                end
            end
            if not isUnit and selfTT.GetUnit then
                if selfTT:GetUnit() then isUnit = true end
            end
            if isUnit then
                selfTT:SetAlpha(0)
                selfTT:Hide()
                return
            end
        end
    end
    
    if WT.Modules.Tooltip.FormatUnitTooltip then
        local data = nil
        if selfTT.GetTooltipData then
            local td = selfTT:GetTooltipData()
            if td then data = td end
        end
        WT.Modules.Tooltip.FormatUnitTooltip(selfTT, data)
    end
    
    if selfTT == GameTooltip then Module:UpdateTooltipStrata() end
    Module:UpdateTooltipStyle(selfTT)
end

local function OnTooltipCleared(selfTT)
    if selfTT:IsForbidden() then return end
    
    if Module.TooltipClassCache then Module.TooltipClassCache[selfTT] = nil end
    
    if selfTT.SetMinimumWidth then pcall(function() selfTT:SetMinimumWidth(0) end) end
end

function Module:Initialize()
    if not WT.DB.Modules.Tooltip then return end
    
    SetupHealthBar()
    SetupCursorAnchor()
    self:SetupItemTooltip()
    SetupSpellTooltip()
    SetupMiscTooltips()
    self:SetupUnitTooltip()
    
    self:UpdateTooltipStrata()
    if not Module.StrataHooked then
        Module.StrataHooked = true

        for _, name in ipairs(ALL_TOOLTIPS) do
            local tt = _G[name]
            if tt then
                tt.wtHookedByWT = true
                if tt.HasScript and tt:HasScript("OnShow") then
                    tt:HookScript("OnShow", OnTooltipShow)
                else
                    hooksecurefunc(tt, "Show", OnTooltipShow)
                end
                if tt.HasScript and tt:HasScript("OnTooltipCleared") then
                    tt:HookScript("OnTooltipCleared", OnTooltipCleared)
                end
            end
        end
    end
    self:UpdateAllTooltipStyles()
    
    if TooltipDataProcessor then
        local function IsLineToSkip(tooltip, text, lineType, ttType, isTrailing, leftLine, r, g, b)
            if not WT.DB.Tooltip.HideUnitHint and not WT.DB.Tooltip.ExtFactionIcon then return false end
            
            -- TAINT PROTECTION: Skip line scanning for tooltips owned by protected frames
            local owner = type(tooltip.GetOwner) == "function" and tooltip:GetOwner() or nil
            if owner then
                -- Logic fix: We previously blocked ALL protected frames (incl. UIParent and TargetFrame), 
                -- which caused unit hints to never be hidden. We now only specifically block action bars!
                if owner.action or type(owner.GetAction) == "function" then return false end
                if type(owner.unitToken) == "string" and string.match(owner.unitToken, "^nameplate") then return false end
                if type(owner.unit) == "string" and string.match(owner.unit, "^nameplate") then return false end
            end

            if WT.DB.Tooltip and WT.DB.Tooltip.HideUnitHint and Enum.TooltipDataLineType then
                local instrKey = "Instruction"
                if Enum.TooltipDataLineType[instrKey] and lineType == Enum.TooltipDataLineType[instrKey] then return true end
            end

            if type(text) ~= "string" then
                return false
            end
            
        local safeText = GetSafeString(text)
            if not safeText then
            -- It's a secret string, we cannot parse it safely and it's definitely not a hint
            return false
        end
        
        local okFind = pcall(string.find, safeText, "<", 1, true)
        if not okFind then return false end
            
            -- Fast-Path: We only need to allocate memory for string cleaning if it could actually be a hint or faction!
            if not string.find(safeText, "<", 1, true) and not string.find(safeText, "&lt;", 1, true) and not string.find(safeText, "(", 1, true) and not string.find(safeText, FACTION_HORDE or "Horde", 1, true) and not string.find(safeText, FACTION_ALLIANCE or "Alliance", 1, true) then
                return false
            end

            local clean = safeText
            if string.find(clean, "|", 1, true) then
                clean = string.gsub(clean, "|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[cC][nN][%w_]+:", ""):gsub("|[rR]", ""):gsub("|[aA].-|[aA]", ""):gsub("|[tT].-|[tT]", "")
            end
            
            clean = strtrim(clean)
            if clean == "" then return false end
            
            if WT.DB.Tooltip and WT.DB.Tooltip.HideUnitHint then
                if Enum.TooltipDataLineType then
                    local instrKey = "Instruction"
                    if Enum.TooltipDataLineType[instrKey] and lineType == Enum.TooltipDataLineType[instrKey] then return true end
                end
                
                -- Fallback: Interaction hints are often enclosed in < > or ( ) and are green or light blue.
                if string.match(clean, "^<.*>$") or string.match(clean, "^&lt;.*&gt;$") or string.match(clean, "^%(.*%)$") then
                    local isHintColor = false
                    
                    -- 1. Check if RGB colors were explicitly provided
                    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                        if (r < 0.1 and g > 0.9 and b < 0.1) or (r < 0.1 and g > 0.9 and b > 0.9) then isHintColor = true end
                    end
                    
                    -- 2. Check if a color code exists as a string in the text
                    if not isHintColor and (string.match(text, "|[cC][fF][fF]00[fF][fF]00") or string.match(text, "|[cC][fF][fF]00[fF][fF][fF][fF]")) then
                        isHintColor = true
                    end
                    
                    -- 3. Check the actual pixel color value of the text from the engine
                    if not isHintColor and leftLine and type(leftLine.GetTextColor) == "function" then
                        local lr, lg, lb = leftLine:GetTextColor()
                        if lr and lg and lb then
                            if (lr < 0.1 and lg > 0.9 and lb < 0.1) or (lr < 0.1 and lg > 0.9 and lb > 0.9) then isHintColor = true end
                        end
                    end
                    
                    if isHintColor then
                        return true
                    end
                end
            end
            
            if WT.DB.Tooltip and WT.DB.Tooltip.ExtFactionIcon then
                if ttType == Enum.TooltipDataType.Unit then
                    if clean == (FACTION_HORDE or "Horde") or clean == (FACTION_ALLIANCE or "Alliance") then
                        return true
                    end
                end
            end
            
            return false
        end

        local function OnTooltipPostCall(tooltip, data)
            if not WT.DB.Modules.Tooltip then return end
            if tooltip:IsForbidden() then return end
            
            local owner = type(tooltip.GetOwner) == "function" and tooltip:GetOwner() or nil
            if IsHouseFrame(owner) then return end
            
            -- Hide unwanted lines visually instead of mutating the restricted data pool
            if data and data.lines and (WT.DB.Tooltip.HideUnitHint or WT.DB.Tooltip.ExtFactionIcon) then
                local tooltipName = tooltip.GetName and tooltip:GetName()
                if tooltipName then
                    for i = 1, #data.lines do
                        local lineData = data.lines[i]
                        local txt = lineData.leftText
                        local r, g, b
                        local leftLine = _G[tooltipName .. "TextLeft" .. i]
                        
                        -- BATTLE-SAFE: lineData.leftColor is a restricted table in 11.0+.
                        -- Indexing its fields causes an execution taint. 
                        -- We rely on leftLine:GetTextColor() inside IsLineToSkip instead.
                        
                        if IsLineToSkip(tooltip, txt, lineData.type, data.type, false, leftLine, r, g, b) then
                            if leftLine then
                                leftLine:SetText("")
                                leftLine:Hide()
                            end
                            local rightLine = _G[tooltipName .. "TextRight" .. i]
                            if rightLine then
                                rightLine:SetText("")
                                rightLine:Hide()
                            end
                            
                            if i > 1 then
                                local prevLine = _G[tooltipName .. "TextLeft" .. (i - 1)]
                                if prevLine then
                                    local prevTxt = prevLine:GetText()
                                    if prevTxt == " " or prevTxt == "" then
                                        prevLine:SetText("")
                                        prevLine:Hide()
                                    end
                                end
                            end
                        end
                    end
                end
            end
            
            -- BATTLE-SAFE: Enforce Alpha reliably on EVERY data update!
            if WT.DB.Tooltip then
                local targetAlpha = WT.DB.Tooltip.Alpha or 1.0
                local hideInCombat = WT.DB.Tooltip.HideInCombat and InCombatLockdown()
                
                local isActionBar = false
                if owner then
                    if type(owner) == "table" and owner.IsForbidden and owner:IsForbidden() then
                        isActionBar = true
                    else
                        isActionBar = (owner.action or type(owner.GetAction) == "function")
                    end
                end
                
                if WT.DB.Tooltip.AlwaysShowActionBars and isActionBar then
                    if tooltip:GetAlpha() ~= 1.0 then tooltip:SetAlpha(1.0) end
                    if not tooltip:IsShown() then tooltip:Show() end
                    return
                end
                
                local isHiddenUnit = false
                if hideInCombat then
                    local isUnit = (data and data.type == Enum.TooltipDataType.Unit)
                    if not isUnit and tooltip.GetUnit and tooltip:GetUnit() then isUnit = true end
                    if isUnit then isHiddenUnit = true end
                end
                
                if isHiddenUnit then
                    tooltip:Hide()
                    return
                else
                    if tooltip:GetAlpha() ~= targetAlpha then tooltip:SetAlpha(targetAlpha) end
                end
            end
        end
        
        for _, dataType in pairs(Enum.TooltipDataType) do
            TooltipDataProcessor.AddTooltipPostCall(dataType, OnTooltipPostCall)
        end
        
        local legacyHooked = setmetatable({}, { __mode = "k" })
        local legacyTTs = { _G["GameTooltip"], _G["ItemRefTooltip"], _G["GameSmallTooltip"], _G["ShoppingTooltip1"], _G["ShoppingTooltip2"], _G["NamePlateTooltip"] }
        for _, tt in ipairs(legacyTTs) do
            if tt and type(tt.AddLine) == "function" and not legacyHooked[tt] then
                legacyHooked[tt] = true
                hooksecurefunc(tt, "AddLine", function(self, text, r, g, b, ...)
                    local owner = type(self.GetOwner) == "function" and self:GetOwner() or nil
                    if IsHouseFrame(owner) then return end
                    if WT.DB.Modules.Tooltip and type(text) == "string" then
                        if IsLineToSkip(self, text, nil, nil, true, nil, r, g, b) then
                            local numLines = self:NumLines()
                            if numLines > 0 then
                                local currentLine = _G[self:GetName() .. "TextLeft" .. numLines]
                                if currentLine then
                                    currentLine:SetText("")
                                    currentLine:Hide()
                                end
                                
                                if numLines > 1 then
                                    local prevLine = _G[self:GetName() .. "TextLeft" .. (numLines - 1)]
                                    if prevLine then
                                        local prevText = prevLine:GetText()
                                        local safePrev = GetSafeString(prevText)
                                        if type(prevText) == "string" and safePrev == nil then
                                            -- Secret string, ignore
                                        elseif safePrev and safePrev ~= "" then
                                            local clean = safePrev
                                            if string.find(clean, "|", 1, true) then
                                                clean = string.gsub(clean, "|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", ""):gsub("|[TtgG].-|[tT]", ""):gsub("|[aA].-|[aA]", "")
                                            end
                                            if strtrim(clean) == "" then
                                                prevLine:SetText("")
                                                prevLine:Hide()
                                            end
                                        end
                                    end
                                end
                                
                            end
                        end
                    end
                end)
                
                hooksecurefunc(tt, "AddDoubleLine", function(self, left, right, rL, gL, bL, ...)
                    local owner = type(self.GetOwner) == "function" and self:GetOwner() or nil
                    if IsHouseFrame(owner) then return end
                    if WT.DB.Modules.Tooltip and type(left) == "string" and IsLineToSkip(self, left, nil, nil, true, nil, rL, gL, bL) then
                        local numLines = self:NumLines()
                        if numLines > 0 then
                            local currentLeft = _G[self:GetName() .. "TextLeft" .. numLines]
                            local currentRight = _G[self:GetName() .. "TextRight" .. numLines]
                            if currentLeft then
                                currentLeft:SetText("")
                                currentLeft:Hide()
                            end
                            if currentRight then
                                currentRight:SetText("")
                                currentRight:Hide()
                            end
                            
                            if numLines > 1 then
                                local prevLine = _G[self:GetName() .. "TextLeft" .. (numLines - 1)]
                                if prevLine then
                                    local prevText = prevLine:GetText()
                                    local safePrev = GetSafeString(prevText)
                                    if type(prevText) == "string" and safePrev == nil then
                                        -- Secret string, ignore
                                    elseif safePrev and safePrev ~= "" then
                                        local clean = safePrev
                                        if string.find(clean, "|", 1, true) then
                                            clean = string.gsub(clean, "|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", ""):gsub("|[TtgG].-|[tT]", ""):gsub("|[aA].-|[aA]", "")
                                        end
                                        if strtrim(clean) == "" then
                                            prevLine:SetText("")
                                            prevLine:Hide()
                                        end
                                    end
                                end
                                
                            end
                        end
                    end
                end)
            end
        end
        
        if _G["SharedTooltip_SetBackdropStyle"] and not Module.backdropHooked then
            Module.backdropHooked = true
            hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tt)
                if WT.DB.Modules.Tooltip and tt and not tt:IsForbidden() then
                    local owner = type(tt.GetOwner) == "function" and tt:GetOwner() or nil
                    if IsHouseFrame(owner) then return end
                    Module:UpdateTooltipStyle(tt)
                    
                    -- Dynamically catch dynamically created 3rd party tooltips (e.g. LibDBIconTooltip)
                    if not legacyHooked[tt] then
                        legacyHooked[tt] = true
                        if tt.HasScript and tt:HasScript("OnShow") then
                            tt:HookScript("OnShow", OnTooltipShow)
                        end
                        if tt.HasScript and tt:HasScript("OnTooltipCleared") then
                            tt:HookScript("OnTooltipCleared", OnTooltipCleared)
                        end
                    end
                end
            end)
        end
    end
    
    WT.Core.Events:Register("PLAYER_REGEN_DISABLED", function() Module:UpdateTooltipAlpha() end)
    WT.Core.Events:Register("PLAYER_REGEN_ENABLED", function() Module:UpdateTooltipAlpha() end)
end

WT.Core.Events:Register("PLAYER_LOGIN", function()
    Module:Initialize()
end)

-- Function to build the module's option panel
function Module:BuildOptions(builder, panel)
    local function UpdateHPBar()
        local bar = GameTooltip["healthBar"] or _G["GameTooltipStatusBar"]
        if bar then
            if WT.DB.Tooltip.HideHealthBar then
                bar:SetAlpha(0)
            else
                bar:SetAlpha(1)
                if WT.DB.Tooltip.HealthBarHeight then
                    bar:SetHeight(WT.DB.Tooltip.HealthBarHeight)
                end
            end
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
    
    panel:CreateTitle(builder, WT.L.GROUP_TOOLTIP_POSITION)
    AddDescription(WT.L.OPT_DESC_GROUP_TOOLTIP_POSITION)

    local cursorInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_CURSOR_ANCHOR, WT.L.OPT_DESC_TOOLTIP_CURSOR_ANCHOR, "Tooltip", "CursorAnchor")
    local anchorOptions = {
        { value = "ANCHOR_CURSOR_LEFT", label = WT.L.ANCHOR_LEFT },
        { value = "ANCHOR_CURSOR", label = WT.L.ANCHOR_CENTER },
        { value = "ANCHOR_CURSOR_RIGHT", label = WT.L.ANCHOR_RIGHT }
    }
    panel:CreateDropdown(builder, WT.L.OPT_TOOLTIP_CURSOR_ANCHOR_TYPE, WT.L.OPT_DESC_TOOLTIP_CURSOR_ANCHOR_TYPE, "Tooltip", "CursorAnchorType", anchorOptions, nil, cursorInit)
    panel:CreateSlider(builder, WT.L.OPT_TOOLTIP_CURSOR_X, WT.L.OPT_DESC_TOOLTIP_CURSOR_X, "Tooltip", "CursorAnchorX", -200, 200, 5, nil, cursorInit)
    panel:CreateSlider(builder, WT.L.OPT_TOOLTIP_CURSOR_Y, WT.L.OPT_DESC_TOOLTIP_CURSOR_Y, "Tooltip", "CursorAnchorY", -200, 200, 5, nil, cursorInit)
    
    panel:CreateTitle(builder, WT.L.GROUP_TOOLTIP_VISIBILITY)
    AddDescription(WT.L.OPT_DESC_GROUP_TOOLTIP_VISIBILITY)
    
    panel:CreateStrataDropdown(builder, WT.L.OPT_STRATA, WT.L.OPT_DESC_STRATA, "Tooltip", "Strata", function() self:UpdateTooltipStrata() end)
    panel:CreateSlider(builder, WT.L.OPT_TOOLTIP_ALPHA, WT.L.OPT_DESC_TOOLTIP_ALPHA, "Tooltip", "Alpha", 0.1, 1.0, 0.05, function() self:UpdateTooltipAlpha() end)
    
    local tbgInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_SOLID_BG, WT.L.OPT_DESC_TOOLTIP_SOLID_BG, "Tooltip", "SolidBackground", function() self:UpdateAllTooltipStyles() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BG, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "BgColor", true, tbgInit, function() self:UpdateAllTooltipStyles() end)
    
    local bordOverrideInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_CUSTOM_BORDER, WT.L.OPT_DESC_TOOLTIP_CUSTOM_BORDER, "Tooltip", "CustomBorderColor", function() self:UpdateAllTooltipStyles() end)
    panel:CreateColorPicker(builder, WT.L.OPT_TOOLTIP_BORDER_COLOR, WT.L.OPT_DESC_TOOLTIP_BORDER_COLOR, "Tooltip", "BorderColor", true, bordOverrideInit, function() self:UpdateAllTooltipStyles() end)
    
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_CLASS_BORDER_UNIT, WT.L.OPT_DESC_TOOLTIP_CLASS_BORDER_UNIT, "Tooltip", "ClassColorBorderUnit", function() self:UpdateAllTooltipStyles() end)
    
    local combatInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_HIDE_COMBAT, WT.L.OPT_DESC_TOOLTIP_HIDE_COMBAT, "Tooltip", "HideInCombat")
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_ALWAYS_ACTIONBAR, WT.L.OPT_DESC_TOOLTIP_ALWAYS_ACTIONBAR, "Tooltip", "AlwaysShowActionBars", nil, combatInit)
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_HIDE_HINT, WT.L.OPT_DESC_TOOLTIP_HIDE_HINT, "Tooltip", "HideUnitHint")
    
    panel:CreateTitle(builder, WT.L.GROUP_TOOLTIP_INFO)
    AddDescription(WT.L.OPT_DESC_GROUP_TOOLTIP_INFO)
    
    local lvlInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_EXT_LEVEL, WT.L.OPT_DESC_TOOLTIP_EXT_LEVEL, "Tooltip", "ExtLevel")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "ColLevelV", false, lvlInit)
    
    local classInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_CLASS_COLOR, WT.L.OPT_DESC_TOOLTIP_CLASS_COLOR, "Tooltip", "ClassColor")
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_EXT_CLASS, WT.L.OPT_DESC_TOOLTIP_EXT_CLASS, "Tooltip", "ExtClass")

    local genderInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_GENDER, WT.L.OPT_DESC_TOOLTIP_GENDER, "Tooltip", "Gender")
    panel:CreateColorPicker(builder, WT.L.TT_COLOR_MALE, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "ColMale", false, genderInit)
    panel:CreateColorPicker(builder, WT.L.TT_COLOR_FEMALE, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "ColFemale", false, genderInit)
    
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_EXT_FAC_ICO, WT.L.OPT_DESC_TOOLTIP_EXT_FAC_ICO, "Tooltip", "ExtFactionIcon")
    
    local gInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_EXT_GUILD, WT.L.OPT_DESC_TOOLTIP_EXT_GUILD, "Tooltip", "ExtGuild")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "ColGuildV", false, gInit)
    
    local grInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_GUILD_RANK, WT.L.OPT_DESC_TOOLTIP_GUILD_RANK, "Tooltip", "GuildRank", nil, gInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "ColGuildRankV", false, grInit)
    
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_GUILD_BRO, WT.L.OPT_DESC_TOOLTIP_GUILD_BRO, "Tooltip", "GuildBro", nil, gInit)

    local playerStyleOptions = {
        { value = "DEFAULT", label = WT.L.OPT_PLAYER_STYLE_DEFAULT },
        { value = "HIDE", label = WT.L.OPT_PLAYER_STYLE_HIDE },
        { value = "COLOR", label = WT.L.OPT_PLAYER_STYLE_COLOR }
    }
    
    local psInit = panel:CreateDropdown(builder, WT.L.OPT_TOOLTIP_PLAYER_STYLE, WT.L.OPT_DESC_TOOLTIP_PLAYER_STYLE, "Tooltip", "PlayerStyle", playerStyleOptions)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "ColPlayerV", false, psInit)

    local gsInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_GEARSCORE, WT.L.OPT_DESC_TOOLTIP_GEARSCORE, "Tooltip", "GearScore")
    panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_ILVL_COLOR, WT.L.OPT_DESC_FRAMES_ILVL_COLOR, "Tooltip", "GearScoreColorize", nil, gsInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LABEL, WT.L.OPT_DESC_COLOR_LABEL, "Tooltip", "ColGsL", false, gsInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "ColGsV", false, gsInit)
    
    local mpInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_MYTHIC_PLUS, WT.L.OPT_DESC_TOOLTIP_MYTHIC_PLUS, "Tooltip", "MythicPlus")
    panel:SetFlavor(mpInit, "RETAIL")
    local colMplusL = panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LABEL, WT.L.OPT_DESC_COLOR_LABEL, "Tooltip", "ColMplusL", false, mpInit)
    panel:SetFlavor(colMplusL, "RETAIL")
    
    local mpbInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_MPLUS_BEST, WT.L.OPT_DESC_TOOLTIP_MPLUS_BEST, "Tooltip", "MythicPlusBest", nil, mpInit)
    panel:SetFlavor(mpbInit, "RETAIL")
    local colMplusBestL = panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LABEL, WT.L.OPT_DESC_COLOR_LABEL, "Tooltip", "ColMplusBestL", false, mpbInit)
    panel:SetFlavor(colMplusBestL, "RETAIL")
    local colMplusBestV = panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "ColMplusBestV", false, mpbInit)
    panel:SetFlavor(colMplusBestV, "RETAIL")
    
    local pvpInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_PVP_RATING, WT.L.OPT_DESC_TOOLTIP_PVP_RATING, "Tooltip", "PvPRating")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LABEL, WT.L.OPT_DESC_COLOR_LABEL, "Tooltip", "ColPvpL", false, pvpInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "ColPvpV", false, pvpInit)
    
    local rfInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_REALM_FLAG, WT.L.OPT_DESC_TOOLTIP_REALM_FLAG, "Tooltip", "RealmFlag")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LABEL, WT.L.OPT_DESC_COLOR_LABEL, "Tooltip", "ColRealmL", false, rfInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "ColRealmV", false, rfInit)
    
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_SHOW_REALM, WT.L.OPT_DESC_TOOLTIP_SHOW_REALM, "Tooltip", "ShowRealm")
    
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_TARGET_COUNT, WT.L.OPT_DESC_TOOLTIP_TARGET_COUNT, "Tooltip", "TargetCount")
    
    local totInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_TARGET_OF_TARGET, WT.L.OPT_DESC_TOOLTIP_TARGET_OF_TARGET, "Tooltip", "TargetOfTarget")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LABEL, WT.L.OPT_DESC_COLOR_LABEL, "Tooltip", "ColTotL", false, totInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "ColTotV", false, totInit)
    
    local mountInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_MOUNT, WT.L.OPT_DESC_TOOLTIP_MOUNT, "Tooltip", "Mount")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LABEL, WT.L.OPT_DESC_COLOR_LABEL, "Tooltip", "ColMountL", false, mountInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "ColMountV", false, mountInit)
    
    local hbInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_HEALTHBAR, WT.L.OPT_DESC_TOOLTIP_HEALTHBAR, "Tooltip", "HealthBar")
    local hbStyleOptions = {
        { value = "CUSTOM", label = WT.L.OPT_CUSTOM_COLOR },
        { value = "CLASS_PLAYER", label = WT.L.OPT_CLASS_COLOR_PLAYER },
        { value = "CLASS_UNIT", label = WT.L.OPT_CLASS_COLOR_UNIT }
    }
    panel:CreateDropdown(builder, WT.L.OPT_TOOLTIP_HB_STYLE, WT.L.OPT_DESC_TOOLTIP_HB_STYLE, "Tooltip", "HealthBarColorStyle", hbStyleOptions, nil, hbInit)
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_HB_FORCE, WT.L.OPT_DESC_TOOLTIP_HB_FORCE, "Tooltip", "HealthBarForceFallback", nil, hbInit)
    panel:CreateColorPicker(builder, WT.L.OPT_CUSTOM_COLOR, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "HealthBarColor", false, hbInit)
    
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_HIDE_HEALTHBAR, WT.L.OPT_DESC_TOOLTIP_HIDE_HEALTHBAR, "Tooltip", "HideHealthBar", UpdateHPBar)
    panel:CreateSlider(builder, WT.L.OPT_TOOLTIP_HB_HEIGHT, WT.L.OPT_DESC_TOOLTIP_HB_HEIGHT, "Tooltip", "HealthBarHeight", 4, 30, 1, UpdateHPBar)
    
    panel:CreateTitle(builder, WT.L.GROUP_TOOLTIP_ITEM)
    AddDescription(WT.L.OPT_DESC_GROUP_TOOLTIP_ITEM)
    
    local expInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_EXPANSION, WT.L.OPT_DESC_TOOLTIP_EXPANSION, "Tooltip", "Expansion")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LABEL, WT.L.OPT_DESC_COLOR_LABEL, "Tooltip", "ColExpL", false, expInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "ColExpV", false, expInit)
    local learnedInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_LEARNED, WT.L.OPT_DESC_TOOLTIP_LEARNED, "Tooltip", "Learned")
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_KNOWN_TOYS, WT.L.OPT_DESC_TOOLTIP_KNOWN_TOYS, "Tooltip", "KnownToys", nil, learnedInit)
    
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_DURABILITY, WT.L.OPT_DESC_TOOLTIP_DURABILITY, "Durability", "ShowTooltip")
    
    local matInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_MAT_TRACKER, WT.L.OPT_DESC_TOOLTIP_MAT_TRACKER, "Tooltip", "MaterialTracker")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LABEL, WT.L.OPT_DESC_COLOR_LABEL, "Tooltip", "ColMatL", false, matInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "ColMatV", false, matInit)
    
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_QUEST_WARN, WT.L.OPT_DESC_TOOLTIP_QUEST_WARN, "Tooltip", "QuestWarn")
    
    local nerdInit = panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_NERD_IDS, WT.L.OPT_DESC_TOOLTIP_NERD_IDS, "Tooltip", "NerdIDs")
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LABEL, WT.L.OPT_DESC_COLOR_LABEL, "Tooltip", "ColNerdL", false, nerdInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "Tooltip", "ColNerdV", false, nerdInit)
    
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_NERD_ITEMS, "", "Tooltip", "NerdIDsItems", nil, nerdInit)
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_NERD_SPELLS, "", "Tooltip", "NerdIDsSpells", nil, nerdInit)
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_NERD_NPCS, "", "Tooltip", "NerdIDsNPCs", nil, nerdInit)
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_NERD_QUESTS, "", "Tooltip", "NerdIDsQuests", nil, nerdInit)
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_NERD_MOUNTS, "", "Tooltip", "NerdIDsMounts", nil, nerdInit)
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_NERD_CURRENCY, "", "Tooltip", "NerdIDsCurrency", nil, nerdInit)
end