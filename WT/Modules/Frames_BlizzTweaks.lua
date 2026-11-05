local _, WT = ...
local Module = WT.Modules.Frames

local SafeNum = WT.Utils.Safety.SafeNum
local Unsecret = WT.Utils.Safety.Unsecret

function Module:UpdateExtendedCameraZoom(enable)
    local zoom = enable and (WT.DB.Frames.MaxZoom or 1.9) or 1.9
    if WT.Utils and WT.Utils.Flags then
        WT.Utils.Flags:SetCVar("cameraDistanceMaxZoomFactor", tostring(zoom))
    else
        pcall(function() C_CVar.SetCVar("cameraDistanceMaxZoomFactor", tostring(zoom)) end)
    end
end

function Module:UpdateSharpening(enable)
    if WT.Utils and WT.Utils.Flags then
        WT.Utils.Flags:SetCVar("ResampleAlwaysSharpen", enable and "1" or "0")
    else
        pcall(function() C_CVar.SetCVar("ResampleAlwaysSharpen", enable and "1" or "0") end)
    end
end

function Module:UpdateShaderFix(enable)
    if WT.Utils and WT.Utils.Flags then
        WT.Utils.Flags:SetCVar("GxAllowCachelessShaderMode", enable and "0" or "1")
    else
        pcall(function() C_CVar.SetCVar("GxAllowCachelessShaderMode", enable and "0" or "1") end)
    end
end

function Module:UpdateLowHealthFlash(disable)
    if WT.Utils and WT.Utils.Flags then
        WT.Utils.Flags:SetCVar("screenEdgeFlash", disable and "0" or "1")
    else
        pcall(function() C_CVar.SetCVar("screenEdgeFlash", disable and "0" or "1") end)
    end
end

function Module:UpdateGlow(disable)
    if WT.Utils and WT.Utils.Flags then
        WT.Utils.Flags:SetCVar("ffxDeath", disable and "0" or "1")
        WT.Utils.Flags:SetCVar("ffxGlow", disable and "0" or "1")
    else
        pcall(function() C_CVar.SetCVar("ffxDeath", disable and "0" or "1") end)
        pcall(function() C_CVar.SetCVar("ffxGlow", disable and "0" or "1") end)
    end
end

function Module:UpdateWeatherDensity(value)
    if WT.Utils and WT.Utils.Flags then WT.Utils.Flags:SetCVar("weatherDensity", tostring(value or 3)) else pcall(function() C_CVar.SetCVar("weatherDensity", tostring(value or 3)) end) end
end


function Module:UpdateCombatTextMode()
    local mode = tostring(WT.DB.Frames.CombatTextFloatMode or 3)
    local directional = WT.DB.Frames.CombatTextDirectional and "1" or "0"
    if WT.Utils and WT.Utils.Flags then
        WT.Utils.Flags:SetCVar("floatingCombatTextFloatMode", mode)
        WT.Utils.Flags:SetCVar("floatingCombatTextCombatDamageDirectionalScale", directional)
    else
        pcall(function() C_CVar.SetCVar("floatingCombatTextFloatMode", mode) end)
        pcall(function() C_CVar.SetCVar("floatingCombatTextCombatDamageDirectionalScale", directional) end)
    end
end

local function WT_IsEditMode()
    return EditModeManagerFrame and EditModeManagerFrame:IsShown()
end

function Module:ForceHideAndDisableMouse(frame)
    if not frame then return end
    
    if frame:IsProtected() then
        frame:SetAlpha(0)
        return
    end
    
    frame:SetAlpha(0)
    frame:Hide()
end

function Module:ForceShowAndEnableMouse(frame)
    if not frame then return end
    if frame:IsProtected() then
        frame:SetAlpha(1)
        return
    end
    
    frame:SetAlpha(1)
    frame:Show()
end

function Module:UpdateXPBar()
    if not self.tweakData then self.tweakData = setmetatable({}, { __mode = "k" }) end
    local tweakData = self.tweakData
    if WT.DB.Frames.HideXPBar then
        if StatusTrackingBarManager then
            if not WT_IsEditMode() then self:ForceHideAndDisableMouse(StatusTrackingBarManager) end
            local mData = tweakData[StatusTrackingBarManager]
            if not mData then mData = {}; tweakData[StatusTrackingBarManager] = mData end
            
            if not mData.wtHooked then
                StatusTrackingBarManager:HookScript("OnShow", function(frame)
                    if WT.DB.Frames.HideXPBar and not WT_IsEditMode() then self:ForceHideAndDisableMouse(frame) end
                end)
                local watcher = CreateFrame("Frame")
                watcher:RegisterEvent("PLAYER_XP_UPDATE")
                watcher:RegisterEvent("UPDATE_FACTION")
                watcher:RegisterEvent("HONOR_XP_UPDATE")
                watcher:SetScript("OnEvent", function()
                    if WT.DB.Frames.HideXPBar and not WT_IsEditMode() then self:ForceHideAndDisableMouse(StatusTrackingBarManager) end
                end)
                mData.wtHooked = true
            end
            mData.wtHiddenByUs = true
        end
    else
        if StatusTrackingBarManager then
            local mData = tweakData[StatusTrackingBarManager]
            if mData and mData.wtHiddenByUs and not WT_IsEditMode() then 
                self:ForceShowAndEnableMouse(StatusTrackingBarManager)
                mData.wtHiddenByUs = false 
            end
        end
    end
end

function Module:UpdateBagsBar()
    if not self.tweakData then self.tweakData = setmetatable({}, { __mode = "k" }) end
    local tweakData = self.tweakData
    if WT.DB.Frames.HideBagsBar then
        if BagsBar then
            if not WT_IsEditMode() then self:ForceHideAndDisableMouse(BagsBar) end
            local mData = tweakData[BagsBar]
            if not mData then mData = {}; tweakData[BagsBar] = mData end
            
            if not mData.wtHooked then
                BagsBar:HookScript("OnShow", function(frame)
                    if WT.DB.Frames.HideBagsBar and not WT_IsEditMode() then self:ForceHideAndDisableMouse(frame) end
                end)
                local watcher = CreateFrame("Frame")
                watcher:RegisterEvent("BAG_UPDATE")
                watcher:SetScript("OnEvent", function()
                    if WT.DB.Frames.HideBagsBar and not WT_IsEditMode() then self:ForceHideAndDisableMouse(BagsBar) end
                end)
                mData.wtHooked = true
            end
            mData.wtHiddenByUs = true
        end
    else
        if BagsBar then
            local mData = tweakData[BagsBar]
            if mData and mData.wtHiddenByUs and not WT_IsEditMode() then 
                self:ForceShowAndEnableMouse(BagsBar)
                mData.wtHiddenByUs = false 
            end
        end
    end
end

function Module:UpdateTalkingHead()
    local function disableTalkingHead()
        if TalkingHeadFrame then
            TalkingHeadFrame:UnregisterAllEvents()
            TalkingHeadFrame:Hide()
        end
    end
    
    if WT.DB.Frames.HideTalkingHead then
        if TalkingHeadFrame then disableTalkingHead() end
        WT.Core.Events:Register("ADDON_LOADED", function(event, addon)
            if addon == "Blizzard_TalkingHeadUI" and WT.DB.Frames.HideTalkingHead then
                disableTalkingHead()
            end
        end)
    end
end

local activeErrors = {}
local MAX_ERRORS = 3
local ERROR_DURATION = 2.5
local errorBgFrame
local annoyingErrorIDs = {} -- Cache for seen ErrorTypes

function Module:UpdateErrorFilter()
    if not self.errorFilterHooked and UIErrorsFrame then
        self.errorFilterHooked = true
        
        local orig_AddMessage = UIErrorsFrame.AddMessage
        UIErrorsFrame.AddMessage = function(self, text, ...)
            if WT.Modules.Vendor and WT.Modules.Vendor.SuppressUntil and GetTime() < WT.Modules.Vendor.SuppressUntil then
                if text == ERR_VENDOR_DOESNT_BUY then return end
            end
            
            if WT.DB.Frames.HideErrors then
                local isAnnoying = false
                if type(text) == "string" then
                    isAnnoying = (text == ERR_ABILITY_COOLDOWN or text == ERR_SPELL_COOLDOWN or 
                        text == ERR_SPELL_FAILED_ANOTHER_IN_PROGRESS or text == ERR_OUT_OF_ENERGY or 
                        text == ERR_OUT_OF_FOCUS or text == ERR_OUT_OF_RAGE or 
                        text == ERR_OUT_OF_MANA or text == ERR_SPELL_OUT_OF_RANGE or 
                        text == ERR_BADATTACKFACING or text == ERR_BADATTACKPOS or 
                        text == SPELL_FAILED_NOT_READY)
                end
                if isAnnoying then return end
            end
            
            if WT.DB.Frames.ErrorBackground and errorBgFrame then
                if type(text) ~= "string" or text == "" then
                    return orig_AddMessage(self, text, ...)
                end
                
                local r, g, b = ...
                if type(r) ~= "number" then r = 1.0 end
                if type(g) ~= "number" then g = 0.1 end
                if type(b) ~= "number" then b = 0.1 end
                
                local now = GetTime()
                local isDuplicate = false
                if #activeErrors > 0 and activeErrors[#activeErrors].text == text then
                    isDuplicate = true
                    activeErrors[#activeErrors].count = (activeErrors[#activeErrors].count or 1) + 1
                    activeErrors[#activeErrors].expireTime = now + ERROR_DURATION
                end
                
                if not isDuplicate then
                    table.insert(activeErrors, {text = text, r = r, g = g, b = b, count = 1, expireTime = now + ERROR_DURATION})
                    if #activeErrors > MAX_ERRORS then
                        table.remove(activeErrors, 1)
                    end
                end
                
                errorBgFrame:UpdateErrors()
            else
                return orig_AddMessage(self, text, ...)
            end
        end
        
        if type(UIErrorsFrame.Clear) == "function" then
            local orig_Clear = UIErrorsFrame.Clear
            UIErrorsFrame.Clear = function(self)
                if WT.DB.Frames.ErrorBackground and errorBgFrame then
                    wipe(activeErrors)
                    errorBgFrame:UpdateErrors()
                end
                return orig_Clear(self)
            end
        end
    end
end

function Module:SetupErrorBackground()
    if not UIErrorsFrame then return end
    if not errorBgFrame then
        errorBgFrame = CreateFrame("Frame", "WTErrorBackground", _G["WT_UIContainer"])
        errorBgFrame.ignoreInLayout = true
        errorBgFrame.ignoreFramePositionManager = true
        if errorBgFrame.SetIsFramePositionManaged then pcall(function() errorBgFrame:SetIsFramePositionManaged(false) end) end
        errorBgFrame:SetSize(350, 40)
        errorBgFrame:SetFrameStrata("DIALOG")
        local targetLevel = UIErrorsFrame:GetFrameLevel() - 1
        errorBgFrame:SetFrameLevel(targetLevel > 0 and targetLevel or 0)
        
        errorBgFrame:SetPoint("CENTER", UIErrorsFrame, "CENTER", 0, 0)
        
        errorBgFrame.text = errorBgFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        errorBgFrame.text:SetPoint("CENTER", 0, 0)
        errorBgFrame.text:SetWordWrap(true)
        local fontPath = (WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", "Friz Quadrata TT")) or "Fonts\\FRIZQT__.TTF"
        errorBgFrame.text:SetFont(fontPath, 14, "OUTLINE")
        errorBgFrame.text:SetJustifyH("CENTER")
        
        local bgCenter = errorBgFrame:CreateTexture(nil, "BACKGROUND")
        bgCenter:SetPoint("TOP", 0, 0)
        bgCenter:SetPoint("BOTTOM", 0, 0)
        bgCenter:SetWidth(350)
        bgCenter:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        errorBgFrame.bgCenter = bgCenter

        local bgLeft = errorBgFrame:CreateTexture(nil, "BACKGROUND")
        bgLeft:SetPoint("TOPLEFT", 0, 0)
        bgLeft:SetPoint("BOTTOMRIGHT", bgCenter, "BOTTOMLEFT", 0, 0)
        bgLeft:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        errorBgFrame.bgLeft = bgLeft

        local bgRight = errorBgFrame:CreateTexture(nil, "BACKGROUND")
        bgRight:SetPoint("TOPLEFT", bgCenter, "TOPRIGHT", 0, 0)
        bgRight:SetPoint("BOTTOMRIGHT", 0, 0)
        bgRight:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        errorBgFrame.bgRight = bgRight
        
        local topCenter = errorBgFrame:CreateTexture(nil, "BORDER")
        topCenter:SetPoint("TOP", 0, 0)
        topCenter:SetSize(350, 1)
        topCenter:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        errorBgFrame.topCenter = topCenter

        local topLineL = errorBgFrame:CreateTexture(nil, "BORDER")
        topLineL:SetPoint("TOPLEFT", 0, 0)
        topLineL:SetPoint("BOTTOMRIGHT", topCenter, "BOTTOMLEFT", 0, 0)
        topLineL:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        errorBgFrame.topLineL = topLineL
        
        local topLineR = errorBgFrame:CreateTexture(nil, "BORDER")
        topLineR:SetPoint("TOPLEFT", topCenter, "TOPRIGHT", 0, 0)
        topLineR:SetPoint("BOTTOMRIGHT", errorBgFrame, "TOPRIGHT", 0, -1)
        topLineR:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        errorBgFrame.topLineR = topLineR
        
        local botCenter = errorBgFrame:CreateTexture(nil, "BORDER")
        botCenter:SetPoint("BOTTOM", 0, 0)
        botCenter:SetSize(350, 1)
        botCenter:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        errorBgFrame.botCenter = botCenter

        local botLineL = errorBgFrame:CreateTexture(nil, "BORDER")
        botLineL:SetPoint("BOTTOMLEFT", 0, 0)
        botLineL:SetPoint("TOPRIGHT", botCenter, "TOPLEFT", 0, 0)
        botLineL:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        errorBgFrame.botLineL = botLineL
        
        local botLineR = errorBgFrame:CreateTexture(nil, "BORDER")
        botLineR:SetPoint("BOTTOMLEFT", botCenter, "BOTTOMRIGHT", 0, 0)
        botLineR:SetPoint("TOPRIGHT", errorBgFrame, "BOTTOMRIGHT", 0, 1)
        botLineR:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        errorBgFrame.botLineR = botLineR
        
        errorBgFrame:SetAlpha(0)
        errorBgFrame:Hide()
        
        UIErrorsFrame:SetClipsChildren(false)
        
        errorBgFrame.timer = 0
        
        function errorBgFrame:UpdateErrors()
            local lines = {}
            for _, err in ipairs(activeErrors) do
                local hex = WT.Colors:GetHex({r=err.r, g=err.g, b=err.b, a=1})
                local str = "|c" .. hex .. err.text .. "|r"
                if err.count > 1 then
                    str = str .. " |cFF888888(" .. err.count .. ")|r"
                end
                table.insert(lines, str)
            end
            
            if #lines > 0 then
                self.text:SetWidth(0) -- Resets the width limit for calculation
                self.text:SetText(table.concat(lines, "\n"))
                
                local textWidth = type(self.text.GetUnboundedStringWidth) == "function" and self.text:GetUnboundedStringWidth() or self.text:GetStringWidth()
                local maxAllowedWidth = 800
                
                if textWidth > maxAllowedWidth then
                    self.text:SetWidth(maxAllowedWidth)
                    textWidth = maxAllowedWidth
                end
                
                self.timer = ERROR_DURATION
                self:SetAlpha(1)
                self:Show()
                
                local cWidth = math.max(350, textWidth + 60)
                self:SetWidth(cWidth)
                
                local targetHeight = math.max(26, self.text:GetStringHeight() + 16)
                self:SetHeight(targetHeight)
                
                self.bgCenter:SetWidth(cWidth)
                self.topCenter:SetWidth(cWidth)
                self.botCenter:SetWidth(cWidth)
            else
                self:Hide()
            end
        end
        
        errorBgFrame:SetScript("OnUpdate", function(self, elapsed)
            if not WT.DB.Frames.ErrorBackground then
                self:SetAlpha(0)
                self:Hide()
                return
            end
            
            if #activeErrors > 0 then
                local now = GetTime()
                local changed = false
                
                for i = #activeErrors, 1, -1 do
                    local expTime = activeErrors[i].expireTime or 0
                    if now >= expTime then
                        table.remove(activeErrors, i)
                        changed = true
                    end
                end
                
                if changed then
                    self:UpdateErrors()
                end
                
                if #activeErrors > 0 then
                    local maxTimeLeft = 0
                    for _, err in ipairs(activeErrors) do
                        local timeLeft = (err.expireTime or 0) - now
                        if timeLeft > maxTimeLeft then maxTimeLeft = timeLeft end
                    end
                    
                    if maxTimeLeft <= 0.5 then
                        self:SetAlpha(math.max(0, maxTimeLeft * 2))
                    else
                        self:SetAlpha(1)
                    end
                else
                    self:SetAlpha(0)
                    self:Hide()
                end
            else
                self:SetAlpha(0)
                self:Hide()
            end
        end)
    end
    
    if errorBgFrame then
        local fontPath = (WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", WT.DB.Frames.ErrorFont or "Friz Quadrata TT")) or "Fonts\\FRIZQT__.TTF"
        local size = WT.DB.Frames.ErrorFontSize or 14
        local outline = (WT.DB.Frames.ErrorFontOutline == "NONE") and "" or (WT.DB.Frames.ErrorFontOutline or "OUTLINE")
        errorBgFrame.text:SetFont(fontPath, size, outline)
        
        local function SetSafeGradient(tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
            C_Timer.After(0, function()
                if tex and tex.SetGradient then
                    tex:SetGradient(orientation, {r=r1, g=g1, b=b1, a=a1}, {r=r2, g=g2, b=b2, a=a2})
                elseif tex and type(tex.SetGradientAlpha) == "function" then
                    tex:SetGradientAlpha(orientation, r1, g1, b1, a1, r2, g2, b2, a2)
                end
            end)
        end

        local bg = WT.DB.Frames.ErrorBgColor
        if type(bg) ~= "table" then bg = {r=0.02, g=0.02, b=0.02, a=1} end
        local br, bg_g, bb, ba = (type(bg.r) == "number" and bg.r or tonumber(tostring(bg.r))) or 0.02, (type(bg.g) == "number" and bg.g or tonumber(tostring(bg.g))) or 0.02, (type(bg.b) == "number" and bg.b or tonumber(tostring(bg.b))) or 0.02, (type(bg.a) == "number" and bg.a or tonumber(tostring(bg.a))) or 1

        errorBgFrame.bgCenter:SetVertexColor(br, bg_g, bb, ba)
        SetSafeGradient(errorBgFrame.bgLeft, "HORIZONTAL", br, bg_g, bb, 0, br, bg_g, bb, ba)
        SetSafeGradient(errorBgFrame.bgRight, "HORIZONTAL", br, bg_g, bb, ba, br, bg_g, bb, 0)

        local bc = WT.DB.Frames.ErrorBorderColor
        if type(bc) ~= "table" then bc = {r=0.8, g=0.1, b=0.1, a=0.8} end
        local bcr, bcg, bcb, bca = (type(bc.r) == "number" and bc.r or tonumber(tostring(bc.r))) or 0.8, (type(bc.g) == "number" and bc.g or tonumber(tostring(bc.g))) or 0.1, (type(bc.b) == "number" and bc.b or tonumber(tostring(bc.b))) or 0.1, (type(bc.a) == "number" and bc.a or tonumber(tostring(bc.a))) or 0.8

        errorBgFrame.topCenter:SetVertexColor(bcr, bcg, bcb, bca)
        errorBgFrame.botCenter:SetVertexColor(bcr, bcg, bcb, bca)
        SetSafeGradient(errorBgFrame.topLineL, "HORIZONTAL", bcr, bcg, bcb, 0, bcr, bcg, bcb, bca)
        SetSafeGradient(errorBgFrame.topLineR, "HORIZONTAL", bcr, bcg, bcb, bca, bcr, bcg, bcb, 0)
        SetSafeGradient(errorBgFrame.botLineL, "HORIZONTAL", bcr, bcg, bcb, 0, bcr, bcg, bcb, bca)
        SetSafeGradient(errorBgFrame.botLineR, "HORIZONTAL", bcr, bcg, bcb, bca, bcr, bcg, bcb, 0)
    end
end

local cursorFrame
function Module:UpdateCombatCursor(forceShow)
    if WT.DB.Frames.CombatCursor then
        if not cursorFrame then
            cursorFrame = CreateFrame("Frame", nil, _G["WT_UIContainer"])
            cursorFrame.ignoreInLayout = true
            cursorFrame.ignoreFramePositionManager = true
            if cursorFrame.SetIsFramePositionManaged then pcall(function() cursorFrame:SetIsFramePositionManaged(false) end) end
            cursorFrame:SetFrameStrata("TOOLTIP")
            cursorFrame:SetFrameLevel(9999)
            cursorFrame:SetSize(48, 48)
            cursorFrame.texture = cursorFrame:CreateTexture(nil, "OVERLAY")
            cursorFrame.texture:SetAllPoints()
            cursorFrame.texture:SetBlendMode("ADD")
            
            cursorFrame.agRot = cursorFrame.texture:CreateAnimationGroup()
            local rotA = cursorFrame.agRot:CreateAnimation("Rotation")
            rotA:SetDuration(3)
            cursorFrame.agRot:SetLooping("REPEAT")
            cursorFrame.rotAnim = rotA
            
            cursorFrame.agPulse = cursorFrame.texture:CreateAnimationGroup()
            local p1 = cursorFrame.agPulse:CreateAnimation("Alpha")
            p1:SetFromAlpha(1)
            p1:SetToAlpha(0.2)
            p1:SetDuration(0.6)
            p1:SetOrder(1)
            p1:SetSmoothing("IN_OUT")
            local p2 = cursorFrame.agPulse:CreateAnimation("Alpha")
            p2:SetFromAlpha(0.2)
            p2:SetToAlpha(1)
            p2:SetDuration(0.6)
            p2:SetOrder(2)
            p2:SetSmoothing("IN_OUT")
            cursorFrame.agPulse:SetLooping("REPEAT")
            
            cursorFrame:SetScript("OnUpdate", function(self)
                local x, y = GetCursorPosition()
                local scale = UIParent:GetEffectiveScale()
                local cx, cy = x / scale, y / scale
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
                
                if self.isChroma then
                    local t = GetTime() * 3
                    local r = (math.sin(t) + 1) / 2
                    local g = (math.sin(t + 2.094) + 1) / 2
                    local b = (math.sin(t + 4.188) + 1) / 2
                    local a = WT.DB.Frames.CombatCursorColor and WT.DB.Frames.CombatCursorColor.a or 0.8
                    self.texture:SetVertexColor(r, g, b, a)
                end
                
                if WT.DB.Frames.CombatCursorClicks then
                    local lDown = IsMouseButtonDown("LeftButton")
                    local rDown = IsMouseButtonDown("RightButton")
                    
                    if (lDown and not self.wasLDown) or (rDown and not self.wasRDown) then
                        if not self.ripples then self.ripples = {} end
                        local rTex = nil
                        for i = 1, #self.ripples do
                            if not self.ripples[i].active then rTex = self.ripples[i]; break end
                        end
                        if not rTex then
                            rTex = self:CreateTexture(nil, "BACKGROUND")
                            rTex:SetTexture("Interface\\Cooldown\\ping4")
                            rTex:SetBlendMode("ADD")
                            table.insert(self.ripples, rTex)
                        end
                        rTex.active = true
                        rTex.t = GetTime()
                        rTex.x = cx
                        rTex.y = cy
                        local vr, vg, vb = self.texture:GetVertexColor()
                        rTex.cR, rTex.cG, rTex.cB = vr, vg, vb
                    end
                    self.wasLDown = lDown
                    self.wasRDown = rDown
                    
                    if self.ripples then
                        local nowTime = GetTime()
                        local baseSize = 48 * (WT.DB.Frames.CombatCursorScale or 1.0)
                        for i = 1, #self.ripples do
                            local r = self.ripples[i]
                            if r.active then
                                local age = nowTime - r.t
                                if age > 0.4 then
                                    r.active = false
                                    r:Hide()
                                else
                                    local pct = age / 0.4
                                    local size = baseSize * (1 + pct * 1.5)
                                    r:ClearAllPoints()
                                    r:SetPoint("CENTER", UIParent, "BOTTOMLEFT", r.x, r.y)
                                    r:SetSize(size, size)
                                    r:SetVertexColor(r.cR, r.cG, r.cB, 1 - pct)
                                    r:Show()
                                end
                            end
                        end
                    end
                else
                    if self.ripples then
                        for i = 1, #self.ripples do self.ripples[i]:Hide(); self.ripples[i].active = false end
                    end
                end
                
                if WT.DB.Frames.CombatCursorTrail then
                    if not self.trailTextures then
                        self.trailTextures = {}
                        self.history = {}
                        self.historyPool = {}
                    end
                    
                    local now = GetTime()
                    local maxAge = WT.DB.Frames.CombatCursorTrailDuration or 0.35
                    local minDist = WT.DB.Frames.CombatCursorTrailDistance or 3
                    local endScale = WT.DB.Frames.CombatCursorTrailEndScale or 0.4
                    local endCol = WT.DB.Frames.CombatCursorTrailColor or {r=1, g=0, b=1, a=0.8}
                    local er, eg, eb = endCol.r or 1, endCol.g or 0, endCol.b or 1
                    local MAX_DRAW = 64
                    local lastPos = self.history[#self.history]
                    
                    if not lastPos then
                        local n = table.remove(self.historyPool) or {}
                        n.x, n.y, n.t = cx, cy, now
                        table.insert(self.history, n)
                    else
                        local dx = cx - lastPos.x
                        local dy = cy - lastPos.y
                        local distSq = dx*dx + dy*dy
                        if distSq > (minDist * minDist) then
                            local dist = math.sqrt(distSq)
                            local steps = math.min(30, math.max(1, math.floor(dist / math.max(1, minDist))))
                            for s = 1, steps do
                                local n = table.remove(self.historyPool) or {}
                                n.x = lastPos.x + (dx * (s / steps))
                                n.y = lastPos.y + (dy * (s / steps))
                                n.t = lastPos.t + ((now - lastPos.t) * (s / steps))
                                table.insert(self.history, n)
                            end
                        end
                    end
                    
                    -- Efficient cleanup: cap history size to MAX_DRAW and remove expired
                    while #self.history > MAX_DRAW do
                        local pos = table.remove(self.history, 1)
                        table.insert(self.historyPool, pos)
                    end
                    while #self.history > 0 do
                        if (now - self.history[1].t) > maxAge then
                            local pos = table.remove(self.history, 1)
                            table.insert(self.historyPool, pos)
                        else
                            break
                        end
                    end
                    
                    local texPath = self.texture:GetTexture()
                    local vr, vg, vb, va = self.texture:GetVertexColor()
                    local baseSize = self:GetWidth()
                    
                    local drawCount = 0
                    for i = #self.history, 1, -1 do
                        drawCount = drawCount + 1
                        local pos = self.history[i]
                        local age = now - pos.t
                        
                        if not self.trailTextures[drawCount] then
                            local t = self:CreateTexture(nil, "BACKGROUND")
                            t:SetBlendMode("ADD")
                            self.trailTextures[drawCount] = t
                        end
                        
                        local tex = self.trailTextures[drawCount]
                        local pct = age / maxAge
                        local scaleFactor = 1 - (pct * (1 - endScale))
                        
                        -- Linear color interpolation (Start -> End)
                        local cr = vr + (er - vr) * pct
                        local cg = vg + (eg - vg) * pct
                        local cb = vb + (eb - vb) * pct
                        
                        tex:ClearAllPoints()
                        tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x, pos.y)
                        tex:SetTexture(texPath)
                        tex:SetVertexColor(cr, cg, cb, va * (1 - pct))
                        tex:SetSize(baseSize * scaleFactor, baseSize * scaleFactor)
                        tex:Show()
                    end
                    
                    for i = drawCount + 1, #self.trailTextures do
                        self.trailTextures[i]:Hide()
                    end
                else
                    if self.trailTextures then
                        for i = 1, #self.trailTextures do self.trailTextures[i]:Hide() end
                    end
                    if self.history then wipe(self.history) end
                end
            end)
        end
        
        local tex = WT.DB.Frames.CombatCursorShape or "Interface\\Cooldown\\ping4"
        cursorFrame.texture:SetTexture(tex)
        
        local scale = WT.DB.Frames.CombatCursorScale or 1.0
        cursorFrame:SetSize(48 * scale, 48 * scale)
        
        cursorFrame.agRot:Stop()
        cursorFrame.agPulse:Stop()
        cursorFrame.texture:SetRotation(0)
        cursorFrame.texture:SetAlpha(1)
        cursorFrame.isChroma = false
        
        local animType = WT.DB.Frames.CombatCursorAnim or "NONE"
        if animType == "ROTATE_CW" then
            cursorFrame.rotAnim:SetDegrees(-360)
            cursorFrame.agRot:Play()
        elseif animType == "ROTATE_CCW" then
            cursorFrame.rotAnim:SetDegrees(360)
            cursorFrame.agRot:Play()
        elseif animType == "PULSE" then
            cursorFrame.agPulse:Play()
        elseif animType == "ROT_PULSE" then
            cursorFrame.rotAnim:SetDegrees(-360)
            cursorFrame.agRot:Play()
            cursorFrame.agPulse:Play()
        elseif animType == "CHROMA" then
            cursorFrame.rotAnim:SetDegrees(-360)
            cursorFrame.agRot:Play()
            cursorFrame.isChroma = true
        elseif animType == "CHROMA_PULSE" then
            cursorFrame.rotAnim:SetDegrees(-360)
            cursorFrame.agRot:Play()
            cursorFrame.agPulse:Play()
            cursorFrame.isChroma = true
        end
        
        if not cursorFrame.isChroma then
            local c = WT.DB.Frames.CombatCursorColor or {r=0, g=1, b=1, a=0.8}
            if type(c) == "string" then c = {r=0, g=1, b=1, a=0.8} end
            cursorFrame.texture:SetVertexColor(c.r or 0, c.g or 1, c.b or 1, c.a or 0.8)
        end
        
        local isCombat = forceShow
        if isCombat == nil then isCombat = InCombatLockdown() end
        
        if isCombat or WT.DB.Frames.CombatCursorShowOOC or self.PreviewCombatCursor then cursorFrame:Show() else cursorFrame:Hide() end
    else
        if cursorFrame then cursorFrame:Hide() end
    end
end

local ourAchievementShieldWrapper

function Module:GuardAchievementShield()
    local current = _G["AchievementShield_SetPoints"]
    if current and current ~= ourAchievementShieldWrapper then
        local origShield = current
        ourAchievementShieldWrapper = function(points, pointString, normalFont, smallFont)
            return origShield(points or 0, pointString, normalFont, smallFont)
        end
        rawset(_G, "AchievementShield_SetPoints", ourAchievementShieldWrapper)
    elseif not current then
        ourAchievementShieldWrapper = function(points, pointString, normalFont, smallFont)
            points = points or 0
            if not pointString then return end
            if points == 0 then
                pointString:Hide()
            else
                pointString:Show()
                pointString:SetText(points)
                if normalFont and smallFont and pointString.SetFontObject then
                    if points > 999 then
                        pointString:SetFontObject(smallFont)
                    else
                        pointString:SetFontObject(normalFont)
                    end
                end
            end
        end
        rawset(_G, "AchievementShield_SetPoints", ourAchievementShieldWrapper)
    end
end

function Module:FixBlizzardBugs()
    self:GuardAchievementShield()

    WT.Core.Events:Register("ADDON_LOADED", function(event, addon)
        -- Native Blizzard Bug Fix: Prevents Lua error in Talent UI when closing the window while searching
        if addon == "Blizzard_PlayerSpells" then
            if PlayerSpellsFrame and type(PlayerSpellsFrame.Hide) == "function" then
                hooksecurefunc(PlayerSpellsFrame, "Hide", function(self)
                    if self.SpellBookFrame and self.SpellBookFrame.SearchBox and self.SpellBookFrame.SearchBox:HasFocus() then
                        self.SpellBookFrame.SearchBox:ClearFocus()
                    end
                end)
            end
        elseif addon == "Blizzard_AchievementUI" then
            self:GuardAchievementShield()
        end
    end)
end
