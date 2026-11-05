local _, WT = ...
local Module = WT.Modules.Frames


local hookedBars = setmetatable({}, { __mode = "k" })
local isSettingColor = setmetatable({}, { __mode = "k" })
local isSettingTexture = setmetatable({}, { __mode = "k" })
local frameBorders = setmetatable({}, { __mode = "k" })
local portraitFixed = setmetatable({}, { __mode = "k" })
local fallbackMask = setmetatable({}, { __mode = "k" })
local portraitBg = setmetatable({}, { __mode = "k" })

local ClassColors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS

local function GetUnitColor(unit)
    if not UnitIsPlayer(unit) then return nil end
    local _, class, classID = UnitClass(unit)

    if classID and GetClassInfo then
        local _, safeClass = GetClassInfo(classID)
        if safeClass then
            class = safeClass
        end
    end

    if class then
        local success, color = pcall(function() return ClassColors[class] end)
        if success and color then
            return color.r, color.g, color.b
        end
    end
    return nil
end

-- Text formatting functions removed based on user request.



local function GetRealHealthBar(frame)
    if not frame then return nil end
    if frame.PlayerFrameContent and frame.PlayerFrameContent.PlayerFrameContentMain then
        local main = frame.PlayerFrameContent.PlayerFrameContentMain
        if main.HealthBarArea and main.HealthBarArea.HealthBar then return main.HealthBarArea.HealthBar end
        if main.HealthBarsContainer and main.HealthBarsContainer.HealthBar then
            return main.HealthBarsContainer
                .HealthBar
        end
    end
    if frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain then
        local main = frame.TargetFrameContent.TargetFrameContentMain
        if main.HealthBarArea and main.HealthBarArea.HealthBar then return main.HealthBarArea.HealthBar end
        if main.HealthBarsContainer and main.HealthBarsContainer.HealthBar then
            return main.HealthBarsContainer
                .HealthBar
        end
    end
    return frame.healthbar
end

local function GetRealPowerBar(frame)
    if not frame then return nil end
    if frame.PlayerFrameContent and frame.PlayerFrameContent.PlayerFrameContentMain then
        local main = frame.PlayerFrameContent.PlayerFrameContentMain
        if main.ManaBarArea and main.ManaBarArea.ManaBar then return main.ManaBarArea.ManaBar end
    end
    if frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain then
        local main = frame.TargetFrameContent.TargetFrameContentMain
        if main.ManaBar then return main.ManaBar end
    end
    return frame.manabar
end




local function UpdateTextStyles(frame)
    if not frame then return end

    local mainFrame = frame
    if frame == PlayerFrameContentMain or (PlayerFrame and frame == PlayerFrame.healthbar) then mainFrame = PlayerFrame end
    if frame == TargetFrameContentMain or (TargetFrame and frame == TargetFrame.healthbar) then mainFrame = TargetFrame end

    local hBar = (mainFrame.PlayerFrameContent and mainFrame.PlayerFrameContent.PlayerFrameContentMain and mainFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer and mainFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar) or
        mainFrame.healthbar
    local pBar = (mainFrame.PlayerFrameContent and mainFrame.PlayerFrameContent.PlayerFrameContentMain and mainFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea and mainFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar) or
        mainFrame.manabar

    local function GetFontPath(key)
        if WT.DB.Frames.UnitFramesCustom and WT.Utils and WT.Utils.SharedMedia then
            return WT.Utils.SharedMedia:Fetch("font", key or "Friz Quadrata TT")
        end
        return nil
    end

    local hFont = GetFontPath(WT.DB.Frames.UnitFramesHealthFont)
    local hSize = WT.DB.Frames.UnitFramesCustom and WT.DB.Frames.UnitFramesHealthFontSize or 10
    local hOut = WT.DB.Frames.UnitFramesCustom and WT.DB.Frames.UnitFramesHealthFontOutline or "OUTLINE"
    if hOut == "NONE" then hOut = "" end

    local pFont = GetFontPath(WT.DB.Frames.UnitFramesPowerFont)
    local pSize = WT.DB.Frames.UnitFramesCustom and WT.DB.Frames.UnitFramesPowerFontSize or 10
    local pOut = WT.DB.Frames.UnitFramesCustom and WT.DB.Frames.UnitFramesPowerFontOutline or "OUTLINE"
    if pOut == "NONE" then pOut = "" end

    local function ApplyStyle(text, colorType, customColor, fPath, fSize, fOut)
        if text and text.SetTextColor then
            if not WT.DB.Frames.UnitFramesCustom or colorType == "DEFAULT" then
                text:SetTextColor(1, 1, 1, 1)
            elseif colorType == "CUSTOM_COLOR" and customColor then
                text:SetTextColor(customColor.r, customColor.g, customColor.b, customColor.a)
            end

            if WT.DB.Frames.UnitFramesCustom and fPath then
                text:SetFont(fPath, fSize, fOut)
            end

            if text.GetText and text:GetText() then
                local t = text:GetText()
                text:SetText("")
                text:SetText(t)
            end
        end
    end

    local function ApplyStyleToBarTexts(bar, colorType, customColor, fPath, fSize, fOut)
        if not bar then return end
        local parent = bar:GetParent()
        if parent then
            if parent.LeftText then ApplyStyle(parent.LeftText, colorType, customColor, fPath, fSize, fOut) end
            if parent.RightText then ApplyStyle(parent.RightText, colorType, customColor, fPath, fSize, fOut) end
            if parent.TextString then ApplyStyle(parent.TextString, colorType, customColor, fPath, fSize, fOut) end
            if parent.textFrames then
                for _, f in ipairs(parent.textFrames) do ApplyStyle(f, colorType, customColor, fPath, fSize, fOut) end
            end
        end
        if bar.LeftText then ApplyStyle(bar.LeftText, colorType, customColor, fPath, fSize, fOut) end
        if bar.RightText then ApplyStyle(bar.RightText, colorType, customColor, fPath, fSize, fOut) end
        if bar.TextString then ApplyStyle(bar.TextString, colorType, customColor, fPath, fSize, fOut) end
        if bar.textFrames then
            for _, f in ipairs(bar.textFrames) do ApplyStyle(f, colorType, customColor, fPath, fSize, fOut) end
        end
    end

    ApplyStyleToBarTexts(hBar, WT.DB.Frames.UnitFramesHealthTextColorType, WT.DB.Frames.UnitFramesHealthTextCustomColor,
        hFont, hSize, hOut)
    ApplyStyleToBarTexts(pBar, WT.DB.Frames.UnitFramesPowerTextColorType, WT.DB.Frames.UnitFramesPowerTextCustomColor,
        pFont, pSize, pOut)
end


local function ToggleElement(element, hide)
    if not element then return end
    if hide and WT.DB.Frames.UnitFramesCustom then
        element:SetAlpha(0)
    else
        element:SetAlpha(1)
    end
end

local function ApplyFlatBorder(frame, enable)
    if not frame then return end
    if not frameBorders[frame] then
        frameBorders[frame] = CreateFrame("Frame", nil, frame)
        frameBorders[frame]:SetAllPoints(frame)
        frameBorders[frame]:SetFrameLevel(frame:GetFrameLevel() + 5)

        local t = frameBorders[frame]:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0, 0, 0, 1)
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
        t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 1)
        t:SetHeight(1)

        local b = frameBorders[frame]:CreateTexture(nil, "BORDER")
        b:SetColorTexture(0, 0, 0, 1)
        b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -1, -1)
        b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
        b:SetHeight(1)

        local l = frameBorders[frame]:CreateTexture(nil, "BORDER")
        l:SetColorTexture(0, 0, 0, 1)
        l:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
        l:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -1, -1)
        l:SetWidth(1)

        local r = frameBorders[frame]:CreateTexture(nil, "BORDER")
        r:SetColorTexture(0, 0, 0, 1)
        r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 1)
        r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
        r:SetWidth(1)
    end
    if enable then frameBorders[frame]:Show() else frameBorders[frame]:Hide() end
end

function Module:UpdateUnitPortrait(frame, unit)
    if not frame.portrait then return end

    local portraitType = WT.DB.Frames.UnitFramesPortrait or "DEFAULT"
    if not WT.DB.Frames.UnitFramesCustom then portraitType = "DEFAULT" end

    -- Fix the 1 pixel gap by slightly enlarging the portrait texture if we haven't already
    if not portraitFixed[frame] then
        portraitFixed[frame] = true
        if frame == PlayerFrame then
            frame.portrait:SetSize(frame.portrait:GetWidth() + 2, frame.portrait:GetHeight() + 2)
        end
    end

    if portraitType ~= "DEFAULT" then
        -- This is the crucial trick: We call SetPortraitTexture to force the WoW engine
        -- to apply its native, perfectly-fitted circular mask to the portrait texture.
        SetPortraitTexture(frame.portrait, unit)
    end

    if not portraitBg[frame] then
        portraitBg[frame] = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
        portraitBg[frame]:SetAllPoints(frame.portrait)
    end

    -- Always re-apply masks from frame.portrait to portraitBg to ensure the native mask is used
    if frame.portrait.GetNumMaskTextures and frame.portrait:GetNumMaskTextures() > 0 then
        -- Clear masks if the API supports it, though for textures AddMaskTexture is a set operation in WoW
        for i = 1, frame.portrait:GetNumMaskTextures() do
            portraitBg[frame]:AddMaskTexture(frame.portrait:GetMaskTexture(i))
        end
    end

    if portraitType == "HIDDEN" then
        frame.portrait:Hide()
        if frame.TargetFrameContainer and frame.TargetFrameContainer.Portrait then
            frame.TargetFrameContainer.Portrait:Hide()
        end
        portraitBg[frame]:SetTexture("Interface\\Buttons\\WHITE8x8")
        portraitBg[frame]:SetTexCoord(0, 1, 0, 1)
        portraitBg[frame]:SetVertexColor(0, 0, 0, 0.85)
        portraitBg[frame]:Show()
    elseif portraitType == "FACTION" then
        local factionGroup = UnitFactionGroup(unit)
        local cAlli, cHorde, cSword, cShield, cScroll

        -- =========================================================================
        -- HOW TO SHIFT THE FACTION ICONS (TexCoord = { Left, Right, Top, Bottom })
        -- =========================================================================
        -- If you want to move the icon slightly, change these numbers:
        -- 1. To move the image LEFT: Increase both Left and Right (e.g. from -0.034 to 0.000)
        -- 2. To move the image RIGHT: Decrease both Left and Right (e.g. from -0.034 to -0.060)
        -- 3. To move the image UP: Increase both Top and Bottom (e.g. from 0.00 to 0.05)
        -- 4. To move the image DOWN: Decrease both Top and Bottom (e.g. from 0.00 to -0.05)
        --
        -- To flip the image horizontally (mirror), simply swap the Left and Right numbers!
        -- (Notice how TargetFrame swaps the first two numbers compared to PlayerFrame)
        -- =========================================================================
        if frame == PlayerFrame then
            -- >>> PLAYER FRAME <<<
            cAlli  = { -0.010, 1.020, 0.000, 1.000 }
            cHorde = { -0.010, 1.020, 0.000, 1.000 }
        else
            -- >>> TARGET FRAME (and others like Focus) <<<
            cAlli  = { 1.020, -0.010, 0.000, 1.000 }
            cHorde = { 1.020, -0.010, 0.000, 1.000 }
        end
        cSword  = { 0.268, 0.512, 0.256, 0.512 }
        cShield = { 0.010, 0.246, 0.264, 0.506 }
        cScroll = { 0.000, 1.000, 0.000, 1.000 }

        if factionGroup == "Alliance" then
            frame.portrait:SetTexture("Interface\\Timer\\Alliance-Logo")
            frame.portrait:SetTexCoord(unpack(cAlli))
            portraitBg[frame]:SetTexture("Interface\\Buttons\\WHITE8x8")
            portraitBg[frame]:SetVertexColor(0, 0, 0, 1) -- Black background
            portraitBg[frame]:Show()
        elseif factionGroup == "Horde" then
            frame.portrait:SetTexture("Interface\\Timer\\Horde-Logo")
            frame.portrait:SetTexCoord(unpack(cHorde))
            portraitBg[frame]:SetTexture("Interface\\Buttons\\WHITE8x8")
            portraitBg[frame]:SetVertexColor(0, 0, 0, 1) -- Black background
            portraitBg[frame]:Show()
        else
            if portraitBg[frame] then portraitBg[frame]:Hide() end
            if UnitIsEnemy("player", unit) then
                frame.portrait:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
                frame.portrait:SetTexCoord(unpack(cSword))
            elseif UnitIsFriend("player", unit) then
                frame.portrait:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
                frame.portrait:SetTexCoord(unpack(cShield))
            else
                frame.portrait:SetTexture("Interface\\Minimap\\Tracking\\Townsfolk")
                frame.portrait:SetTexCoord(unpack(cScroll))
            end
        end

        frame.portrait:Show()
        if frame.TargetFrameContainer and frame.TargetFrameContainer.Portrait then
            frame.TargetFrameContainer.Portrait:Show()
        end
    elseif portraitType == "CLASS_ICON" and UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        if class then
            if GetClassAtlas then
                frame.portrait:SetTexture(nil)
                frame.portrait:SetAtlas(GetClassAtlas(class))
            else
                frame.portrait:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
                local coords = CLASS_ICON_TCOORDS[class]
                if coords then
                    local left, right, top, bottom = unpack(coords)
                    if frame == PlayerFrame then
                        frame.portrait:SetTexCoord(left, right, top, bottom)
                    else
                        frame.portrait:SetTexCoord(left, right, top, bottom)
                    end
                end
            end
            frame.portrait:Show()
            if frame.TargetFrameContainer and frame.TargetFrameContainer.Portrait then
                frame.TargetFrameContainer.Portrait:Show()
            end

            if not portraitBg[frame] then
                portraitBg[frame] = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
                portraitBg[frame]:SetAllPoints(frame.portrait)
                if frame.portrait.GetNumMaskTextures and frame.portrait:GetNumMaskTextures() > 0 then
                    for i = 1, frame.portrait:GetNumMaskTextures() do
                        portraitBg[frame]:AddMaskTexture(frame.portrait:GetMaskTexture(i))
                    end
                end
            end
            portraitBg[frame]:SetTexture("Interface\\Buttons\\WHITE8x8")
            portraitBg[frame]:SetTexCoord(0, 1, 0, 1)
            portraitBg[frame]:SetVertexColor(0.08, 0.08, 0.08, 0.95)
            portraitBg[frame]:Show()
        else
            frame.portrait:Show()
            if frame.TargetFrameContainer and frame.TargetFrameContainer.Portrait then
                frame.TargetFrameContainer.Portrait:Show()
            end
        end
    elseif portraitType == "DEFAULT" then
        if portraitBg[frame] then portraitBg[frame]:Hide() end

        -- Restore native portrait texture
        SetPortraitTexture(frame.portrait, unit)

        -- Restore default TexCoords (TargetFrame is flipped by default in WoW)
        if frame == PlayerFrame then
            frame.portrait:SetTexCoord(0, 1, 0, 1)
        else
            frame.portrait:SetTexCoord(1, 0, 0, 1)
        end

        frame.portrait:Show()
        if frame.TargetFrameContainer and frame.TargetFrameContainer.Portrait then
            frame.TargetFrameContainer.Portrait:Show()
        end

        -- Force a native portrait update so 3D portraits reappear if enabled
        -- Use a guard to prevent infinite recursion from our own hook!
        if UnitFramePortrait_Update and not frame.WTPortraitUpdating then
            frame.WTPortraitUpdating = true
            UnitFramePortrait_Update(frame)
            frame.WTPortraitUpdating = false
        end
    else
        frame.portrait:Show()
        if frame.TargetFrameContainer and frame.TargetFrameContainer.Portrait then
            frame.TargetFrameContainer.Portrait:Show()
        end
    end
end

function Module:ApplyHealthBarHook(bar, unit)
    if not bar then return end

    local function UpdateTexture()
        if isSettingTexture[bar] then return end
        isSettingTexture[bar] = true

        if WT.DB.Frames.UnitFramesCustom and WT.DB.Frames.UnitFramesTexture ~= "Blizzard" then
            local texKey = WT.DB.Frames.UnitFramesTexture or "Smooth"
            local texPath = (WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("statusbar", texKey)) or
                "Interface\\TargetingFrame\\UI-StatusBar"

            local function ApplyTex(b)
                if not b then return end
                if b.SetStatusBarTexture then
                    b:SetStatusBarTexture(texPath)
                    local t = b:GetStatusBarTexture()
                    if t then

                        t:SetTexture(texPath)
                    end
                elseif type(b) == "table" and b.SetTexture then

                    b:SetTexture(texPath)
                end
            end

            ApplyTex(bar)
            ApplyTex(bar.AnimatedLossBar)
            ApplyTex(bar.MyHealPredictionBar)
            ApplyTex(bar.OtherHealPredictionBar)
            ApplyTex(bar.TotalAbsorbBar)

            if bar.OverAbsorbGlow then

                bar.OverAbsorbGlow:SetTexture(texPath)
            end
            if bar.OverHealAbsorbGlow then

                bar.OverHealAbsorbGlow:SetTexture(texPath)
            end

            if bar.Background then bar.Background:SetAlpha(0) end
            if bar.FeedbackFrame then bar.FeedbackFrame:SetAlpha(0) end
            if bar.ManaFeedbackFrame then bar.ManaFeedbackFrame:SetAlpha(0) end
            if bar.Flash then bar.Flash:SetAlpha(0) end
        else
            if bar.WTOriginalAtlas then
                if bar.SetStatusBarAtlas then bar:SetStatusBarAtlas(bar.WTOriginalAtlas) end
                local t = bar:GetStatusBarTexture()
                if t and t.SetAtlas then t:SetAtlas(bar.WTOriginalAtlas) end
            elseif bar.WTOriginalTexture then
                bar:SetStatusBarTexture(bar.WTOriginalTexture)
            else
                bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            end

            if bar.Background then bar.Background:SetAlpha(1) end
            if bar.FeedbackFrame then bar.FeedbackFrame:SetAlpha(1) end
            if bar.ManaFeedbackFrame then bar.ManaFeedbackFrame:SetAlpha(1) end
            if bar.Flash then bar.Flash:SetAlpha(1) end
        end
        isSettingTexture[bar] = false
    end

    local function UpdateColor()
        if isSettingColor[bar] then return end
        if not WT.DB.Frames.UnitFramesCustom then return end

        isSettingColor[bar] = true
        local typeStr = WT.DB.Frames.UnitFramesHealthBarColorType
        if typeStr == "CLASS_COLOR" then
            if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(true) end
            local cr, cg, cb = GetUnitColor(bar.unit or unit)
            if cr then
                bar:SetStatusBarColor(cr, cg, cb)
            else
                bar:SetStatusBarColor(0, 1, 0)
            end
        elseif typeStr == "CUSTOM_COLOR" then
            if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(true) end
            local c = WT.DB.Frames.UnitFramesHealthBarCustomColor
            if c then
                bar:SetStatusBarColor(c.r, c.g, c.b, c.a or 1)
            end
        else
            if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(false) end
            bar:SetStatusBarColor(0, 1, 0)
        end
        isSettingColor[bar] = false
    end

    if not hookedBars[bar] then
        hookedBars[bar] = true

        local t = bar:GetStatusBarTexture()
        if t then
            if t.GetAtlas then bar.WTOriginalAtlas = t:GetAtlas() end
            bar.WTOriginalTexture = t:GetTexture()
        end

        hooksecurefunc(bar, "SetStatusBarColor", UpdateColor)
        if bar.SetStatusBarAtlas then
            hooksecurefunc(bar, "SetStatusBarAtlas", function()
                if isSettingTexture[bar] then return end
                UpdateTexture()
                UpdateColor()
            end)
        end
        hooksecurefunc(bar, "SetStatusBarTexture", function()
            if isSettingTexture[bar] then return end
            UpdateTexture()
        end)
        hooksecurefunc(bar, "SetValue", UpdateColor)
    end

    UpdateTexture()
    UpdateColor()
end

function Module:ApplyPowerBarHook(bar, unit)
    if not bar then return end

    local function UpdateTexture()
        if isSettingTexture[bar] then return end
        isSettingTexture[bar] = true

        if WT.DB.Frames.UnitFramesCustom and WT.DB.Frames.UnitFramesTexture ~= "Blizzard" then
            local texKey = WT.DB.Frames.UnitFramesTexture or "Smooth"
            local texPath = (WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("statusbar", texKey)) or
                "Interface\\TargetingFrame\\UI-StatusBar"

            local function ApplyTex(b)
                if not b then return end
                if b.SetStatusBarTexture then
                    b:SetStatusBarTexture(texPath)
                    local t = b:GetStatusBarTexture()
                    if t then

                        t:SetTexture(texPath)
                    end
                elseif type(b) == "table" and b.SetTexture then

                    b:SetTexture(texPath)
                end
            end

            ApplyTex(bar)
            ApplyTex(bar.AnimatedLossBar)

            if bar.Background then bar.Background:SetAlpha(0) end
            if bar.FeedbackFrame then bar.FeedbackFrame:SetAlpha(0) end
            if bar.ManaFeedbackFrame then bar.ManaFeedbackFrame:SetAlpha(0) end
            if bar.Flash then bar.Flash:SetAlpha(0) end
        else
            if bar.WTOriginalAtlas then
                if bar.SetStatusBarAtlas then bar:SetStatusBarAtlas(bar.WTOriginalAtlas) end
                local t = bar:GetStatusBarTexture()
                if t and t.SetAtlas then t:SetAtlas(bar.WTOriginalAtlas) end
            elseif bar.WTOriginalTexture then
                bar:SetStatusBarTexture(bar.WTOriginalTexture)
            else
                bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            end
            if bar.Background then bar.Background:SetAlpha(1) end
            if bar.FeedbackFrame then bar.FeedbackFrame:SetAlpha(1) end
            if bar.ManaFeedbackFrame then bar.ManaFeedbackFrame:SetAlpha(1) end
            if bar.Flash then bar.Flash:SetAlpha(1) end
        end
        isSettingTexture[bar] = false
    end

    local function UpdateColor()
        if isSettingColor[bar] then return end
        if not WT.DB.Frames.UnitFramesCustom then return end

        isSettingColor[bar] = true
        local typeStr = WT.DB.Frames.UnitFramesPowerBarColorType
        if typeStr == "CLASS_COLOR" then
            if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(true) end
            local cr, cg, cb = GetUnitColor(bar.unit or unit)
            if cr then
                bar:SetStatusBarColor(cr, cg, cb)
            end
        elseif typeStr == "CUSTOM_COLOR" then
            if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(true) end
            local c = WT.DB.Frames.UnitFramesPowerBarCustomColor
            if c then
                bar:SetStatusBarColor(c.r, c.g, c.b, c.a or 1)
            end
        else
            if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(false) end
            if PowerBarColor and bar.powerType then
                local color = PowerBarColor[bar.powerType]
                if color then bar:SetStatusBarColor(color.r, color.g, color.b) end
            end
        end
        isSettingColor[bar] = false
    end

    if not hookedBars[bar] then
        hookedBars[bar] = true

        local t = bar:GetStatusBarTexture()
        if t then
            if t.GetAtlas then bar.WTOriginalAtlas = t:GetAtlas() end
            bar.WTOriginalTexture = t:GetTexture()
        end

        hooksecurefunc(bar, "SetStatusBarColor", UpdateColor)
        if bar.SetStatusBarAtlas then
            hooksecurefunc(bar, "SetStatusBarAtlas", function()
                if isSettingTexture[bar] then return end
                UpdateTexture()
                UpdateColor()
            end)
        end
        hooksecurefunc(bar, "SetStatusBarTexture", function()
            if isSettingTexture[bar] then return end
            UpdateTexture()
        end)
        hooksecurefunc(bar, "SetValue", UpdateColor)
    end

    UpdateTexture()
    UpdateColor()
end

local function round(v) return math.floor(v * 100 + 0.5) / 100 end

local function GetDarkModeColorForUnit(unit)
    if WT.DB.Frames.UnitFramesDarkModeClassColor and unit then
        local r, g, b = GetUnitColor(unit)
        if r then
            return r, g, b, true
        end
    end
    if WT.DB.Frames.UnitFramesDarkModeColorEnabled and WT.DB.Frames.UnitFramesDarkModeColor then
        local c = WT.DB.Frames.UnitFramesDarkModeColor
        return c.r, c.g, c.b, true
    end
    return 62 / 255, 62 / 255, 62 / 255, true
end

local function HookDarkModeTexture(tex, configKey, unit)
    configKey = configKey or "UnitFramesDarkMode"
    if not tex or tex.WTDarkModeHooked then return end
    tex.WTDarkModeHooked = true

    local function ApplyDarkMode(self)
        if WT.DB.Frames[configKey] then
            local dr, dg, db, shouldDesaturate = GetDarkModeColorForUnit(unit)

            C_Timer.After(0, function()
                if not self or not self.SetVertexColor then return end
                self.WTIgnoreColorChange = true
                local success = pcall(self.SetVertexColor, self, dr, dg, db, self:GetAlpha() or 1)
                if not success and CreateColor then
                    pcall(self.SetVertexColor, self, CreateColor(dr, dg, db, self:GetAlpha() or 1))
                end
                self.WTIgnoreColorChange = false

                if self.SetDesaturated then
                    self.WTIgnoreDesaturateChange = true
                    pcall(self.SetDesaturated, self, shouldDesaturate)
                    self.WTIgnoreDesaturateChange = false
                end
            end)
        end
    end

    hooksecurefunc(tex, "SetVertexColor", function(self, r, g, b, a)
        if self.WTIgnoreColorChange then return end
        if WT.DB.Frames[configKey] then
            local dr, dg, db, _ = GetDarkModeColorForUnit(unit)

            if round(r) ~= round(dr) or round(g) ~= round(dg) or round(b) ~= round(db) then
                C_Timer.After(0, function()
                    if not self or not self.SetVertexColor then return end
                    self.WTIgnoreColorChange = true
                    local success = pcall(self.SetVertexColor, self, dr, dg, db, a)
                    if not success and CreateColor then pcall(self.SetVertexColor, self, CreateColor(dr, dg, db, a or 1)) end
                    self.WTIgnoreColorChange = false
                end)
            end
        end
    end)

    if tex.SetDesaturated then
        hooksecurefunc(tex, "SetDesaturated", function(self, desaturated)
            if self.WTIgnoreDesaturateChange then return end
            if WT.DB.Frames[configKey] then
                local _, _, _, shouldDesaturate = GetDarkModeColorForUnit(unit)
                if desaturated ~= shouldDesaturate then
                    C_Timer.After(0, function()
                        if not self or not self.SetDesaturated then return end
                        self.WTIgnoreDesaturateChange = true
                        pcall(self.SetDesaturated, self, shouldDesaturate)
                        self.WTIgnoreDesaturateChange = false
                    end)
                end
            end
        end)
    end

    if tex.SetAtlas then
        hooksecurefunc(tex, "SetAtlas", ApplyDarkMode)
    end
    if tex.SetTexture then
        hooksecurefunc(tex, "SetTexture", ApplyDarkMode)
    end
end

function Module:DeclutterUnitFrame(frame, unit)
    if unit == "player" then
        local pCont = PlayerFrame.PlayerFrameContent
        local pCtx = pCont and pCont.PlayerFrameContentContextual
        local pMain = pCont and pCont.PlayerFrameContentMain

        if pCtx then
            pCtx:SetFrameLevel(PlayerFrame:GetFrameLevel() + 20)
        end

        ToggleElement(PlayerRestIcon, WT.DB.Frames.UnitFramesHideResting)
        if pCtx then ToggleElement(pCtx.PlayerRestLoop, WT.DB.Frames.UnitFramesHideResting) end

        ToggleElement(PlayerAttackIcon, WT.DB.Frames.UnitFramesHideCombat)
        if pCtx then ToggleElement(pCtx.AttackIcon, WT.DB.Frames.UnitFramesHideCombat) end

        ToggleElement(PlayerLevelText, WT.DB.Frames.UnitFramesHideLevel)
        if pMain then ToggleElement(pMain.LevelText, WT.DB.Frames.UnitFramesHideLevel) end

        ToggleElement(PlayerLeaderIcon, WT.DB.Frames.UnitFramesHideGroupLeader)
        if pCtx then ToggleElement(pCtx.LeaderIcon, WT.DB.Frames.UnitFramesHideGroupLeader) end
        if pCtx then ToggleElement(pCtx.GuideIcon, WT.DB.Frames.UnitFramesHideGroupLeader) end

        -- Dark Mode Borders
        local frameScale = 1 -- Set to 1 to fix the gap where the game background shines through
        local r, g, b, desaturate = GetDarkModeColorForUnit(unit)

        if PlayerFrameTexture then
            HookDarkModeTexture(PlayerFrameTexture, nil, unit)
            PlayerFrameTexture:SetScale(frameScale)
            PlayerFrameTexture:SetAlpha(1)
            if WT.DB.Frames.UnitFramesDarkMode then
                PlayerFrameTexture.WTIgnoreDesaturateChange = true
                if PlayerFrameTexture.SetDesaturated then PlayerFrameTexture:SetDesaturated(desaturate) end
                PlayerFrameTexture.WTIgnoreDesaturateChange = false
                PlayerFrameTexture.WTIgnoreColorChange = true
                PlayerFrameTexture:SetVertexColor(r, g, b)
                PlayerFrameTexture.WTIgnoreColorChange = false
            else
                PlayerFrameTexture.WTIgnoreDesaturateChange = true
                if PlayerFrameTexture.SetDesaturated then PlayerFrameTexture:SetDesaturated(false) end
                PlayerFrameTexture.WTIgnoreDesaturateChange = false
                PlayerFrameTexture.WTIgnoreColorChange = true
                PlayerFrameTexture:SetVertexColor(1, 1, 1)
                PlayerFrameTexture.WTIgnoreColorChange = false
            end
        end
        if PlayerFrameBackground then
            HookDarkModeTexture(PlayerFrameBackground, nil, unit)
            PlayerFrameBackground:SetAlpha(1)
            if WT.DB.Frames.UnitFramesDarkMode then
                PlayerFrameBackground.WTIgnoreColorChange = true
                PlayerFrameBackground:SetVertexColor(0, 0, 0)
                PlayerFrameBackground.WTIgnoreColorChange = false
            else
                PlayerFrameBackground.WTIgnoreColorChange = true
                PlayerFrameBackground:SetVertexColor(1, 1, 1)
                PlayerFrameBackground.WTIgnoreColorChange = false
            end
        end
        if PlayerFrame.PlayerFrameContainer and PlayerFrame.PlayerFrameContainer.FrameTexture then
            local tex = PlayerFrame.PlayerFrameContainer.FrameTexture
            HookDarkModeTexture(tex, nil, unit)
            tex:SetScale(frameScale)
            tex:SetAlpha(1)
            if WT.DB.Frames.UnitFramesDarkMode then
                tex.WTIgnoreDesaturateChange = true
                if tex.SetDesaturated then tex:SetDesaturated(desaturate) end
                tex.WTIgnoreDesaturateChange = false
                tex.WTIgnoreColorChange = true
                tex:SetVertexColor(r, g, b)
                tex.WTIgnoreColorChange = false
            else
                tex.WTIgnoreDesaturateChange = true
                if tex.SetDesaturated then tex:SetDesaturated(false) end
                tex.WTIgnoreDesaturateChange = false
                tex.WTIgnoreColorChange = true
                tex:SetVertexColor(1, 1, 1)
                tex.WTIgnoreColorChange = false
            end
        end

        if TargetFrameTextureFrameTexture then
            HookDarkModeTexture(TargetFrameTextureFrameTexture)
        end

        -- Casting Bar Dark Mode & Scaling
        self:UpdateCastBars()

        -- Corner Icon Color
        local cornerColor = WT.DB.Frames.UnitFramesCornerIconColor
        local pIcons = {
            PlayerPortraitCornerIcon,
            PlayerFrame.PlayerFrameContainer and PlayerFrame.PlayerFrameContainer.PlayerPortraitCornerIcon,
            PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual and
            PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PlayerPortraitCornerIcon,
            PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual and
            PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.CornerIcon,
            PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain and
            PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.CornerIcon,
            PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain and
            PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.RoleIcon,
            PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual and
            PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.RoleIcon
        }
        for _, icon in pairs(pIcons) do
            if icon and type(icon) == "table" and icon.SetVertexColor then
                -- Check if it's NOT the default WoW gold/yellow
                if cornerColor and not (cornerColor.r == 1 and cornerColor.g == 0.82 and cornerColor.b == 0) then
                    if icon.SetDesaturated then icon:SetDesaturated(true) end
                    icon:SetVertexColor(cornerColor.r, cornerColor.g, cornerColor.b, cornerColor.a)
                else
                    if icon.SetDesaturated then icon:SetDesaturated(false) end
                    icon:SetVertexColor(1, 1, 1, 1)
                end
            end
        end
    elseif unit == "target" then
        local tCont = TargetFrame.TargetFrameContent
        local tCtx = tCont and tCont.TargetFrameContentContextual
        local tMain = tCont and tCont.TargetFrameContentMain

        if tCtx then
            tCtx:SetFrameLevel(TargetFrame:GetFrameLevel() + 20)
        end

        ToggleElement(TargetFrameTextureFrameLevelText, WT.DB.Frames.UnitFramesHideLevel)
        if tMain then ToggleElement(tMain.LevelText, WT.DB.Frames.UnitFramesHideLevel) end

        -- Dark Mode Borders
        local frameScale = 1 -- Set to 1 to fix the gap where the game background shines through
        local r, g, b, desaturate = GetDarkModeColorForUnit(unit)

        if TargetFrameTextureFrameTexture then
            HookDarkModeTexture(TargetFrameTextureFrameTexture, nil, unit)
            TargetFrameTextureFrameTexture:SetScale(frameScale)
            TargetFrameTextureFrameTexture:SetAlpha(1)
            if WT.DB.Frames.UnitFramesDarkMode then
                TargetFrameTextureFrameTexture.WTIgnoreDesaturateChange = true
                if TargetFrameTextureFrameTexture.SetDesaturated then
                    TargetFrameTextureFrameTexture:SetDesaturated(
                        desaturate)
                end
                TargetFrameTextureFrameTexture.WTIgnoreDesaturateChange = false
                TargetFrameTextureFrameTexture.WTIgnoreColorChange = true
                TargetFrameTextureFrameTexture:SetVertexColor(r, g, b)
                TargetFrameTextureFrameTexture.WTIgnoreColorChange = false
            else
                TargetFrameTextureFrameTexture.WTIgnoreDesaturateChange = true
                if TargetFrameTextureFrameTexture.SetDesaturated then TargetFrameTextureFrameTexture:SetDesaturated(false) end
                TargetFrameTextureFrameTexture.WTIgnoreDesaturateChange = false
                TargetFrameTextureFrameTexture.WTIgnoreColorChange = true
                TargetFrameTextureFrameTexture:SetVertexColor(1, 1, 1)
                TargetFrameTextureFrameTexture.WTIgnoreColorChange = false
            end
        end
        if TargetFrameBackground then
            HookDarkModeTexture(TargetFrameBackground, nil, unit)
            TargetFrameBackground:SetAlpha(1)
            if WT.DB.Frames.UnitFramesDarkMode then
                TargetFrameBackground.WTIgnoreColorChange = true
                TargetFrameBackground:SetVertexColor(0, 0, 0)
                TargetFrameBackground.WTIgnoreColorChange = false
            else
                TargetFrameBackground.WTIgnoreColorChange = true
                TargetFrameBackground:SetVertexColor(1, 1, 1)
                TargetFrameBackground.WTIgnoreColorChange = false
            end
        end
        if TargetFrame.TargetFrameContainer and TargetFrame.TargetFrameContainer.FrameTexture then
            local tex = TargetFrame.TargetFrameContainer.FrameTexture
            HookDarkModeTexture(tex, nil, unit)
            tex:SetScale(frameScale)
            tex:SetAlpha(1)
            if WT.DB.Frames.UnitFramesDarkMode then
                tex.WTIgnoreDesaturateChange = true
                if tex.SetDesaturated then tex:SetDesaturated(desaturate) end
                tex.WTIgnoreDesaturateChange = false
                tex.WTIgnoreColorChange = true
                tex:SetVertexColor(r, g, b)
                tex.WTIgnoreColorChange = false
            else
                tex.WTIgnoreDesaturateChange = true
                if tex.SetDesaturated then tex:SetDesaturated(false) end
                tex.WTIgnoreDesaturateChange = false
                tex.WTIgnoreColorChange = true
                tex:SetVertexColor(1, 1, 1)
                tex.WTIgnoreColorChange = false
            end
        end

        -- Corner Icon Color
        local cornerColor = WT.DB.Frames.UnitFramesCornerIconColor
        local tIcons = {
            TargetFramePortraitCornerIcon,
            TargetFrame.TargetFrameContainer and TargetFrame.TargetFrameContainer.PlayerPortraitCornerIcon,
            TargetFrame.TargetFrameContent and TargetFrame.TargetFrameContent.TargetFrameContentContextual and
            TargetFrame.TargetFrameContent.TargetFrameContentContextual.PlayerPortraitCornerIcon,
            TargetFrame.TargetFrameContent and TargetFrame.TargetFrameContent.TargetFrameContentContextual and
            TargetFrame.TargetFrameContent.TargetFrameContentContextual.PrestigePortrait,
            TargetFrame.TargetFrameContent and TargetFrame.TargetFrameContent.TargetFrameContentContextual and
            TargetFrame.TargetFrameContent.TargetFrameContentContextual.CornerIcon,
            TargetFrame.TargetFrameContent and TargetFrame.TargetFrameContent.TargetFrameContentMain and
            TargetFrame.TargetFrameContent.TargetFrameContentMain.CornerIcon,
            TargetFrame.TargetFrameContent and TargetFrame.TargetFrameContent.TargetFrameContentMain and
            TargetFrame.TargetFrameContent.TargetFrameContentMain.RoleIcon,
            TargetFrame.TargetFrameContent and TargetFrame.TargetFrameContent.TargetFrameContentContextual and
            TargetFrame.TargetFrameContent.TargetFrameContentContextual.RoleIcon
        }
        for _, icon in pairs(tIcons) do
            if icon and type(icon) == "table" and icon.SetVertexColor then
                -- Check if it's NOT the default WoW gold/yellow
                if cornerColor and not (cornerColor.r == 1 and cornerColor.g == 0.82 and cornerColor.b == 0) then
                    if icon.SetDesaturated then icon:SetDesaturated(true) end
                    icon:SetVertexColor(cornerColor.r, cornerColor.g, cornerColor.b, cornerColor.a)
                else
                    if icon.SetDesaturated then icon:SetDesaturated(false) end
                    icon:SetVertexColor(1, 1, 1, 1)
                end
                if icon.WTBgUpdater then
                    icon.WTBgUpdater:SetScript("OnUpdate", nil)
                    icon.WTBgUpdater:Hide()
                end
                if icon.WTBg then
                    icon.WTBg:Hide()
                end
            end
        end
    end
end

-- Glow customisation: rest glow, combat glow and threat flash.
-- Blizzard only sets colour and visibility of these textures inside the global functions
-- PlayerFrame_UpdateStatus and UnitFrame_UpdateThreatIndicator, so we post-hook those
-- functions and restyle right afterwards. We deliberately do NOT hook methods on the
-- textures themselves (e.g. hooksecurefunc(tex, "SetAlpha", ...)): instance method hooks
-- on Blizzard textures break PlayerFrame_OnUpdate ("attempt to call a nil value") as soon
-- as taint logging is enabled.
-- "HIDDEN" simply hides the texture. PlayerFrame_OnUpdate only animates the rest/combat
-- pulse while the texture is shown, so no per-frame alpha fight is needed.

local BLIZZ_REST_COLOR = { r = 1.0, g = 0.88, b = 0.25, a = 1.0 } -- see PlayerFrame_UpdateStatus
local BLIZZ_COMBAT_COLOR = { r = 1.0, g = 0.0, b = 0.0, a = 1.0 }
local DARK_REST_COLOR = { r = 1.0, g = 0.82, b = 0.0, a = 1.0 }
local DARK_COMBAT_COLOR = { r = 1.0, g = 0.0, b = 0.0, a = 1.0 }

local function GetPlayerStatusTexture()
    local content = PlayerFrame and PlayerFrame.PlayerFrameContent
    local main = content and content.PlayerFrameContentMain
    if main and main.StatusTexture then return main.StatusTexture end

    -- Legacy player frame layout (WoW Forever)
    local legacy = _G["PlayerStatusTexture"]
    if legacy and legacy.GetObjectType and legacy:GetObjectType() == "Texture" then return legacy end
    return nil
end

local function GetPlayerFlashTexture()
    local container = PlayerFrame and PlayerFrame.PlayerFrameContainer
    return (container and container.FrameFlash) or _G["PlayerFrameFlash"]
end

local function GetTargetFlashTexture()
    local container = TargetFrame and TargetFrame.TargetFrameContainer
    return (container and container.FrameFlash) or _G["TargetFrameFlash"]
end

-- Applies a glow setting ("DEFAULT", "HIDDEN" or "CUSTOM_COLOR") to a glow texture.
-- blizzColor is restored for "DEFAULT" without dark mode (nil = keep Blizzard's current colour).
local function StyleGlow(tex, setting, customColor, darkColor, blizzColor)
    if not tex then return end

    if setting == "HIDDEN" then
        tex:Hide()
        return
    end

    if setting == "CUSTOM_COLOR" and customColor then
        tex:SetVertexColor(customColor.r, customColor.g, customColor.b, customColor.a or 1)
    elseif WT.DB.Frames.UnitFramesDarkMode then
        if tex.SetDesaturated then tex:SetDesaturated(true) end
        tex:SetVertexColor(darkColor.r, darkColor.g, darkColor.b, darkColor.a)
    else
        if tex.SetDesaturated then tex:SetDesaturated(false) end
        if blizzColor then tex:SetVertexColor(blizzColor.r, blizzColor.g, blizzColor.b, blizzColor.a) end
    end
end

local function UpdateThreatFlash(tex)
    if not tex or not tex:IsShown() then return end
    local db = WT.DB.Frames
    StyleGlow(tex, db.UnitFramesAggroGlow, db.UnitFramesAggroGlowColor, DARK_COMBAT_COLOR, nil)
end

local threatHookInstalled = false
local function InstallThreatHook()
    if threatHookInstalled or not UnitFrame_UpdateThreatIndicator then return end
    threatHookInstalled = true

    hooksecurefunc("UnitFrame_UpdateThreatIndicator", function(indicator)
        if not WT.DB.Frames.UnitFramesCustom then return end
        if indicator and (indicator == GetPlayerFlashTexture() or indicator == GetTargetFlashTexture()) then
            UpdateThreatFlash(indicator)
        end
    end)
end

function Module:UpdateGlows()
    if not WT.DB.Frames.UnitFramesCustom then return end
    InstallThreatHook()

    local db = WT.DB.Frames
    local statusTexture = GetPlayerStatusTexture()
    if statusTexture then
        -- Blizzard shows the status texture exactly while resting or in combat.
        -- Re-show it here so that switching away from "HIDDEN" takes effect immediately.
        if IsResting() then
            statusTexture:Show()
            StyleGlow(statusTexture, db.UnitFramesRestGlow, db.UnitFramesRestGlowColor, DARK_REST_COLOR,
                BLIZZ_REST_COLOR)
        elseif PlayerFrame and PlayerFrame.inCombat then
            statusTexture:Show()
            StyleGlow(statusTexture, db.UnitFramesAggroGlow, db.UnitFramesAggroGlowColor, DARK_COMBAT_COLOR,
                BLIZZ_COMBAT_COLOR)
        end
    end

    UpdateThreatFlash(GetPlayerFlashTexture())
    UpdateThreatFlash(GetTargetFlashTexture())
end

function Module:UpdatePlayerFrame()
    local custom = WT.DB.Frames.UnitFramesCustom

    self:UpdateUnitPortrait(PlayerFrame, "player")
    self:DeclutterUnitFrame(PlayerFrame, "player")
    self:UpdateGlows()

    local hBar = GetRealHealthBar(PlayerFrame)
    local pBar = GetRealPowerBar(PlayerFrame)

    if custom then
        if hBar then self:ApplyHealthBarHook(hBar, "player") end
        if pBar then self:ApplyPowerBarHook(pBar, "player") end
        if WT.DB.Frames.UnitFramesScale and not InCombatLockdown() then
            PlayerFrame:SetScale(WT.DB.Frames
                .UnitFramesScale)
        end
    else
        if not InCombatLockdown() then PlayerFrame:SetScale(1.0) end
    end


    UpdateTextStyles(PlayerFrame)
end

function Module:UpdateTargetFrame()
    if not UnitExists("target") then return end
    local custom = WT.DB.Frames.UnitFramesCustom

    self:UpdateUnitPortrait(TargetFrame, "target")
    self:DeclutterUnitFrame(TargetFrame, "target")

    local hBar = GetRealHealthBar(TargetFrame)
    local pBar = GetRealPowerBar(TargetFrame)

    if custom then
        if hBar then self:ApplyHealthBarHook(hBar, "target") end
        if pBar then self:ApplyPowerBarHook(pBar, "target") end
        if WT.DB.Frames.UnitFramesScale and not InCombatLockdown() then
            TargetFrame:SetScale(WT.DB.Frames
                .UnitFramesScale)
        end
    else
        if not InCombatLockdown() then TargetFrame:SetScale(1.0) end
    end


    UpdateTextStyles(TargetFrame)
end

local function ApplyCastBarCustomTexture(cb)
    if not cb then return end
    if WT.DB.Frames.UnitFramesCastbarTexture and WT.DB.Frames.UnitFramesCastbarTexture ~= "Blizzard" then
        if WT.Utils and WT.Utils.SharedMedia then
            local p = WT.Utils.SharedMedia:Fetch("statusbar", WT.DB.Frames.UnitFramesCastbarTexture)
            if p then
                cb:SetStatusBarTexture(p)
                if cb.Background and cb.Background.SetTexture then
                    cb.Background:SetTexture(p)
                    cb.Background:SetVertexColor(0.2, 0.2, 0.2, 0.8)
                end
            end
        end
    end
end

local hookedCastBars = setmetatable({}, { __mode = "k" })

function Module:UpdateCastBars()
    local castBars = {}
    if PlayerCastingBarFrame then table.insert(castBars, PlayerCastingBarFrame) end
    if CastingBarFrame then table.insert(castBars, CastingBarFrame) end
    local frameScale = WT.DB.Frames.UnitFramesCastbarScale or 1.0
    for _, cb in ipairs(castBars) do
        if cb then
            -- Blizzard resets the fill texture via self:UpdateBarFillTexture() on every cast start/stop.
            -- The method is copied onto the frame by the XML mixin, so it must be hooked on the frame
            -- itself; a hook on CastingBarMixin would never fire for already created cast bars.
            if not hookedCastBars[cb] and cb.UpdateBarFillTexture then
                hookedCastBars[cb] = true
                hooksecurefunc(cb, "UpdateBarFillTexture", ApplyCastBarCustomTexture)
            end

            if cb.SetScale then
                pcall(cb.SetScale, cb, frameScale)
            end

            ApplyCastBarCustomTexture(cb)

            local borders = { cb.Border, cb.BorderShield }
            for _, b in ipairs(borders) do
                if b then
                    HookDarkModeTexture(b, "UnitFramesCastbarDarkMode")

                    local isDark = WT.DB.Frames.UnitFramesCastbarDarkMode
                    local desaturate = false
                    local r, g, b_color = 0, 0, 0
                    if isDark and WT.DB.Frames.UnitFramesDarkModeColorEnabled and WT.DB.Frames.UnitFramesDarkModeColor then
                        local c = WT.DB.Frames.UnitFramesDarkModeColor
                        r, g, b_color = c.r, c.g, c.b
                        desaturate = true
                    end

                    if isDark then
                        b.WTIgnoreDesaturateChange = true
                        if b.SetDesaturated then pcall(b.SetDesaturated, b, desaturate) end
                        b.WTIgnoreDesaturateChange = false
                        b.WTIgnoreColorChange = true
                        if b.GetObjectType and b:GetObjectType() == "Texture" then
                            local success = pcall(b.SetVertexColor, b, r, g, b_color)
                            if not success and CreateColor then pcall(b.SetVertexColor, b, CreateColor(r, g, b_color, 1)) end
                        end
                        b.WTIgnoreColorChange = false
                    else
                        b.WTIgnoreDesaturateChange = true
                        if b.SetDesaturated then pcall(b.SetDesaturated, b, false) end
                        b.WTIgnoreDesaturateChange = false
                        b.WTIgnoreColorChange = true
                        if b.GetObjectType and b:GetObjectType() == "Texture" then
                            local success = pcall(b.SetVertexColor, b, 1, 1, 1)
                            if not success and CreateColor then pcall(b.SetVertexColor, b, CreateColor(1, 1, 1, 1)) end
                        end
                        b.WTIgnoreColorChange = false
                    end
                end
            end
        end
    end
end

function Module:InitUnitFrames()
    self:UpdateCastBars()
    -- Apply Hooks once if not hooked
    local phBar = GetRealHealthBar(PlayerFrame)
    local ppBar = GetRealPowerBar(PlayerFrame)
    local thBar = GetRealHealthBar(TargetFrame)
    local tpBar = GetRealPowerBar(TargetFrame)

    if phBar then self:ApplyHealthBarHook(phBar, "player") end
    if ppBar then self:ApplyPowerBarHook(ppBar, "player") end
    if thBar then self:ApplyHealthBarHook(thBar, "target") end
    if tpBar then self:ApplyPowerBarHook(tpBar, "target") end

    -- Persistent Hooks to prevent Blizzard from resetting decluttering
    if PlayerFrame_UpdateStatus then
        hooksecurefunc("PlayerFrame_UpdateStatus", function()
            Module:DeclutterUnitFrame(PlayerFrame, "player")
            Module:UpdateGlows()
        end)
    end
    if PlayerFrame_Update then
        hooksecurefunc("PlayerFrame_Update", function()
            Module:UpdatePlayerFrame()
        end)
    end
    if UnitFramePortrait_Update then
        hooksecurefunc("UnitFramePortrait_Update", function(frame)
            if frame == PlayerFrame then
                Module:UpdateUnitPortrait(PlayerFrame, "player")
            elseif frame == TargetFrame then
                Module:UpdateUnitPortrait(TargetFrame, "target")
            end
        end)
    end
    if TargetFrame_Update then
        hooksecurefunc("TargetFrame_Update", function()
            Module:UpdateTargetFrame()
        end)
    end

    WT.Core.Events:Register("PLAYER_ENTERING_WORLD", function()
        Module:UpdatePlayerFrame()
    end)

    WT.Core.Events:Register("PLAYER_TARGET_CHANGED", function()
        Module:UpdateTargetFrame()
    end)

    WT.Core.Events:Register("PLAYER_REGEN_DISABLED", function()
        Module:UpdatePlayerFrame()
        if UnitExists("target") then Module:UpdateTargetFrame() end
    end)
    WT.Core.Events:Register("PLAYER_REGEN_ENABLED", function()
        if not InCombatLockdown() then
            Module:UpdatePlayerFrame()
            if UnitExists("target") then Module:UpdateTargetFrame() end
        end
    end)

    local function OnUnitCombat(self, event, unit, action, indicator, damage, damageType)
        if not WT.DB.Frames.UnitFramesCustom then return end
        if self.unit ~= unit then return end

        local hideDamage = WT.DB.Frames.UnitFramesHideDamageText
        local hideState = WT.DB.Frames.UnitFramesHideCombatStateText

        local isState = (action == "BLOCK" or action == "PARRY" or action == "DODGE" or action == "EVADE" or action == "IMMUNE" or action == "DEFLECT" or action == "ABSORB" or action == "REFLECT" or action == "RESIST")

        if (hideDamage and not isState) or (hideState and isState) then
            local hi = self.HitIndicator
            if not hi and self.PlayerFrameContent and self.PlayerFrameContent.PlayerFrameContentMain then
                hi = self.PlayerFrameContent.PlayerFrameContentMain.HitIndicator
            end
            if not hi and self.TargetFrameContent and self.TargetFrameContent.TargetFrameContentMain then
                hi = self.TargetFrameContent.TargetFrameContentMain.HitIndicator
            end

            if hi then
                if hi.SetText then hi:SetText("") end
                if hi.HitText and hi.HitText.SetText then hi.HitText:SetText("") end
                if hi.GetRegions then
                    for _, region in ipairs({ hi:GetRegions() }) do
                        if region.GetObjectType and region:GetObjectType() == "FontString" then
                            region:SetText("")
                        end
                    end
                end
                hi:SetAlpha(0)
            end
        else
            local hi = self.HitIndicator
            if not hi and self.PlayerFrameContent and self.PlayerFrameContent.PlayerFrameContentMain then
                hi = self.PlayerFrameContent.PlayerFrameContentMain.HitIndicator
            end
            if not hi and self.TargetFrameContent and self.TargetFrameContent.TargetFrameContentMain then
                hi = self.TargetFrameContent.TargetFrameContentMain.HitIndicator
            end
            if hi then hi:SetAlpha(1) end
        end
    end

    WT.Core.Events:Register("UNIT_COMBAT", function(event, unit, ...)
        if unit == "player" then
            OnUnitCombat(PlayerFrame, event, unit, ...)
        elseif unit == "target" then
            OnUnitCombat(TargetFrame, event, unit, ...)
        end
    end)

    -- Initial update
    self:UpdatePlayerFrame()
    if UnitExists("target") then
        self:UpdateTargetFrame()
    end
end

WT.Modules.UnitFramesOptions = {}

function WT.Modules.UnitFramesOptions:BuildOptions(ufBuilder, panel)
    local function PromptReload()
        if WT.Config and WT.Config.OptionsPanel and WT.Config.OptionsPanel.ShowReloadPrompt then
            WT.Config.OptionsPanel:ShowReloadPrompt()
        end
    end

    panel:CreateTitle(ufBuilder, WT.L.OPT_FRAMES_UF_TITLE)
    local desc = ufBuilder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", ufBuilder.content, "TOPLEFT", 16, ufBuilder.cursorY)
    desc:SetWidth(550)
    desc:SetJustifyH("LEFT")
    desc:SetText(WT.L.OPT_FRAMES_UF_DESC)
    ufBuilder:AddSpace(desc:GetStringHeight() + 25)

    local ufInit = panel:CreateCheckbox(ufBuilder, WT.L.OPT_FRAMES_UF_ENABLE, WT.L.OPT_FRAMES_UF_ENABLE_DESC, "Frames",
        "UnitFramesCustom", PromptReload)

    local function refreshUF()
        if Module.UpdatePlayerFrame then Module:UpdatePlayerFrame() end
        if Module.UpdateTargetFrame and UnitExists("target") then Module:UpdateTargetFrame() end
    end

    local ufUpdate = refreshUF

    panel:CreateSlider(ufBuilder, WT.L.OPT_SCALE,
        WT.L.OPT_DESC_SCALE, "Frames", "UnitFramesScale", 0.5, 2.0, 0.05,
        ufUpdate, ufInit)

    local barColorOptions = {
        { value = "DEFAULT",      label = WT.L.OPT_FRAMES_UF_BAR_COLOR_OPT1 },
        { value = "CLASS_COLOR",  label = WT.L.OPT_FRAMES_UF_BAR_COLOR_OPT2 },
        { value = "CUSTOM_COLOR", label = WT.L.OPT_FRAMES_UF_BAR_COLOR_OPT3 }
    }
    local textColorOptions = {
        { value = "DEFAULT",      label = WT.L.OPT_FRAMES_UF_TEXT_COLOR_OPT1 },
        { value = "CUSTOM_COLOR", label = WT.L.OPT_FRAMES_UF_TEXT_COLOR_OPT2 }
    }

    panel:CreateTitle(ufBuilder, WT.L.OPT_FRAMES_UF_HEALTH_TITLE)
    panel:CreateDropdown(ufBuilder, WT.L.OPT_FRAMES_UF_HEALTH_BAR_COLOR, WT.L.OPT_FRAMES_UF_HEALTH_BAR_COLOR_DESC,
        "Frames", "UnitFramesHealthBarColorType", barColorOptions, refreshUF, ufInit)
    panel:CreateColorPicker(ufBuilder, WT.L.OPT_FRAMES_UF_HEALTH_BAR_COLOR, WT.L.OPT_FRAMES_UF_HEALTH_BAR_COLOR_DESC,
        "Frames", "UnitFramesHealthBarCustomColor", true, ufInit, refreshUF, true)

    panel:CreateDropdown(ufBuilder, WT.L.OPT_FRAMES_UF_HEALTH_TEXT_COLOR, WT.L.OPT_FRAMES_UF_HEALTH_TEXT_COLOR_DESC,
        "Frames", "UnitFramesHealthTextColorType", textColorOptions, refreshUF, ufInit)
    panel:CreateColorPicker(ufBuilder, WT.L.OPT_FRAMES_UF_HEALTH_TEXT_COLOR, WT.L.OPT_FRAMES_UF_HEALTH_TEXT_COLOR_DESC,
        "Frames", "UnitFramesHealthTextCustomColor", true, ufInit, refreshUF, true)

    if WT.Utils and WT.Utils.SharedMedia then
        panel:CreateDropdown(ufBuilder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "Frames", "UnitFramesHealthFont",
            WT.Utils.SharedMedia:GetOptions("font"), refreshUF, ufInit)
    end
    panel:CreateSlider(ufBuilder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "Frames", "UnitFramesHealthFontSize", 8,
        24, 1, refreshUF, ufInit)
    panel:CreateOutlineDropdown(ufBuilder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "Frames",
        "UnitFramesHealthFontOutline", refreshUF, ufInit)

    panel:CreateTitle(ufBuilder, WT.L.OPT_FRAMES_UF_POWER_TITLE)
    panel:CreateDropdown(ufBuilder, WT.L.OPT_FRAMES_UF_POWER_BAR_COLOR, WT.L.OPT_FRAMES_UF_POWER_BAR_COLOR_DESC, "Frames",
        "UnitFramesPowerBarColorType", barColorOptions, refreshUF, ufInit)
    panel:CreateColorPicker(ufBuilder, WT.L.OPT_FRAMES_UF_POWER_BAR_COLOR, WT.L.OPT_FRAMES_UF_POWER_BAR_COLOR_DESC,
        "Frames", "UnitFramesPowerBarCustomColor", true, ufInit, refreshUF, true)

    panel:CreateDropdown(ufBuilder, WT.L.OPT_FRAMES_UF_POWER_TEXT_COLOR, WT.L.OPT_FRAMES_UF_POWER_TEXT_COLOR_DESC,
        "Frames", "UnitFramesPowerTextColorType", textColorOptions, refreshUF, ufInit)
    panel:CreateColorPicker(ufBuilder, WT.L.OPT_FRAMES_UF_POWER_TEXT_COLOR, WT.L.OPT_FRAMES_UF_POWER_TEXT_COLOR_DESC,
        "Frames", "UnitFramesPowerTextCustomColor", true, ufInit, refreshUF, true)

    if WT.Utils and WT.Utils.SharedMedia then
        panel:CreateDropdown(ufBuilder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "Frames", "UnitFramesPowerFont",
            WT.Utils.SharedMedia:GetOptions("font"), refreshUF, ufInit)
    end
    panel:CreateSlider(ufBuilder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "Frames", "UnitFramesPowerFontSize", 8, 24,
        1, refreshUF, ufInit)
    panel:CreateOutlineDropdown(ufBuilder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "Frames",
        "UnitFramesPowerFontOutline", refreshUF, ufInit)

    panel:CreateTitle(ufBuilder, WT.L.OPT_FRAMES_UF_STYLE_TITLE)
    if WT.Utils and WT.Utils.SharedMedia then
        panel:CreateDropdown(ufBuilder, WT.L.OPT_FRAMES_UF_TEXTURE, WT.L.OPT_FRAMES_UF_TEXTURE_DESC, "Frames",
            "UnitFramesTexture", WT.Utils.SharedMedia:GetOptions("statusbar"), refreshUF, ufInit)
    end
    local darkModeCb = panel:CreateCheckbox(ufBuilder, WT.L.OPT_FRAMES_UF_DARKMODE, WT.L.OPT_FRAMES_UF_DARKMODE_DESC,
        "Frames",
        "UnitFramesDarkMode", refreshUF, ufInit)

    local darkModeColorCb = panel:CreateCheckbox(ufBuilder, WT.L.OPT_FRAMES_UF_DARKMODE_COLOR_ENABLED,
        WT.L.OPT_FRAMES_UF_DARKMODE_COLOR_ENABLED_DESC, "Frames",
        "UnitFramesDarkModeColorEnabled", refreshUF, darkModeCb)

    local point, relativeTo, relativePoint, xOffset, yOffset = darkModeColorCb:GetPoint()
    darkModeColorCb:SetPoint(point, relativeTo, relativePoint, 72, yOffset)
    darkModeColorCb.wtIndent = 72

    local classColorCb = panel:CreateCheckbox(ufBuilder, WT.L.OPT_FRAMES_UF_DARKMODE_CLASSCOLOR,
        WT.L.OPT_FRAMES_UF_DARKMODE_CLASSCOLOR_DESC, "Frames",
        "UnitFramesDarkModeClassColor", refreshUF, darkModeCb)
    classColorCb:SetPoint(point, relativeTo, relativePoint, 72, yOffset - 30)
    classColorCb.wtIndent = 72

    panel:CreateColorPicker(ufBuilder, WT.L.OPT_FRAMES_UF_DARKMODE_COLOR, WT.L.OPT_FRAMES_UF_DARKMODE_COLOR_DESC,
        "Frames", "UnitFramesDarkModeColor", false, darkModeColorCb, refreshUF, false)

    local portraitOptions = {
        { value = "DEFAULT",    label = WT.L.OPT_FRAMES_UF_PORTRAIT_OPT1 },
        { value = "CLASS_ICON", label = WT.L.OPT_FRAMES_UF_PORTRAIT_OPT2 },
        { value = "FACTION",    label = WT.L.OPT_FRAMES_UF_PORTRAIT_OPT4 }
    }
    panel:CreateDropdown(ufBuilder, WT.L.OPT_FRAMES_UF_PORTRAIT, WT.L.OPT_FRAMES_UF_PORTRAIT_DESC, "Frames",
        "UnitFramesPortrait", portraitOptions, refreshUF, ufInit)

    panel:CreateTitle(ufBuilder, WT.L.OPT_FRAMES_UF_CASTBAR_TITLE)
    panel:CreateSlider(ufBuilder, WT.L.OPT_FRAMES_UF_CASTBAR_SCALE, WT.L.OPT_FRAMES_UF_CASTBAR_SCALE_DESC, "Frames",
        "UnitFramesCastbarScale", 0.5, 2.0, 0.05, refreshUF)
    if WT.Utils and WT.Utils.SharedMedia then
        panel:CreateDropdown(ufBuilder, WT.L.OPT_FRAMES_UF_CASTBAR_TEXTURE, WT.L.OPT_FRAMES_UF_CASTBAR_TEXTURE_DESC, "Frames",
            "UnitFramesCastbarTexture", WT.Utils.SharedMedia:GetOptions("statusbar"), refreshUF, ufInit)
    end
    panel:CreateCheckbox(ufBuilder, WT.L.OPT_FRAMES_UF_CASTBAR_DARKMODE,
        WT.L.OPT_FRAMES_UF_CASTBAR_DARKMODE_DESC, "Frames",
        "UnitFramesCastbarDarkMode", refreshUF, ufInit)
    panel:CreateButton(ufBuilder, WT.L.OPT_FRAMES_UF_CASTBAR_TEST, WT.L.BTN_TEST,
        WT.L.OPT_FRAMES_UF_CASTBAR_TEST_DESC, function()
            local castBars = {}
            if PlayerCastingBarFrame then table.insert(castBars, PlayerCastingBarFrame) end
            if CastingBarFrame then table.insert(castBars, CastingBarFrame) end
            for _, cb in ipairs(castBars) do
                if cb then
                    cb:SetAlpha(1)
                    cb:Show()
                    cb.casting = true
                    cb.channeling = false
                    cb.holdTime = 0
                    cb.value = 0
                    cb.maxValue = 10
                    cb.startTime = GetTime()
                    cb.endTime = GetTime() + 10
                    cb:SetMinMaxValues(0, 10)
                    cb:SetValue(5)
                    if cb.Text then cb.Text:SetText("Test Castbar") end
                    if cb.Icon then
                        cb.Icon:SetTexture(136243)
                        cb.Icon:Show()
                    end
                    if cb.Spark then cb.Spark:Show() end
                end
            end
        end)

    panel:CreateTitle(ufBuilder, WT.L.OPT_FRAMES_UF_GLOW_TITLE)
    local glowOptions = {
        { value = "DEFAULT",      label = WT.L.OPT_FRAMES_UF_GLOW_OPT1 },
        { value = "HIDDEN",       label = WT.L.OPT_FRAMES_UF_GLOW_OPT2 },
        { value = "CUSTOM_COLOR", label = WT.L.OPT_FRAMES_UF_GLOW_OPT3 }
    }

    panel:CreateDropdown(ufBuilder, WT.L.OPT_FRAMES_UF_REST_GLOW, WT.L.OPT_FRAMES_UF_REST_GLOW_DESC, "Frames",
        "UnitFramesRestGlow", glowOptions, function()
            if Module.UpdatePlayerFrame then Module:UpdatePlayerFrame() end
        end, ufInit)
    panel:CreateColorPicker(ufBuilder, WT.L.OPT_FRAMES_UF_REST_GLOW_COLOR, WT.L.OPT_FRAMES_UF_REST_GLOW_COLOR_DESC,
        "Frames", "UnitFramesRestGlowColor", true, ufInit, function()
            if Module.UpdatePlayerFrame then Module:UpdatePlayerFrame() end
        end, true)

    panel:CreateDropdown(ufBuilder, WT.L.OPT_FRAMES_UF_AGGRO_GLOW, WT.L.OPT_FRAMES_UF_AGGRO_GLOW_DESC, "Frames",
        "UnitFramesAggroGlow", glowOptions, function()
            if Module.UpdatePlayerFrame then Module:UpdatePlayerFrame() end
        end, ufInit)
    panel:CreateColorPicker(ufBuilder, WT.L.OPT_FRAMES_UF_AGGRO_GLOW_COLOR, WT.L.OPT_FRAMES_UF_AGGRO_GLOW_COLOR_DESC,
        "Frames", "UnitFramesAggroGlowColor", true, ufInit, function()
            if Module.UpdatePlayerFrame then Module:UpdatePlayerFrame() end
        end, true)
    panel:CreateColorPicker(ufBuilder, WT.L.OPT_FRAMES_UF_CORNER_COLOR, WT.L.OPT_FRAMES_UF_CORNER_COLOR_DESC, "Frames",
        "UnitFramesCornerIconColor", true, ufInit, ufUpdate, true)

    panel:CreateTitle(ufBuilder, WT.L.OPT_FRAMES_UF_VISIBILITY_TITLE)
    panel:CreateCheckbox(ufBuilder, WT.L.OPT_FRAMES_UF_HIDE_RESTING, WT.L.OPT_FRAMES_UF_HIDE_RESTING_DESC, "Frames",
        "UnitFramesHideResting", ufUpdate, ufInit)
    panel:CreateCheckbox(ufBuilder, WT.L.OPT_FRAMES_UF_HIDE_COMBAT, WT.L.OPT_FRAMES_UF_HIDE_COMBAT_DESC, "Frames",
        "UnitFramesHideCombat", ufUpdate, ufInit)
    panel:CreateCheckbox(ufBuilder, WT.L.OPT_FRAMES_UF_HIDE_LEVEL, WT.L.OPT_FRAMES_UF_HIDE_LEVEL_DESC, "Frames",
        "UnitFramesHideLevel", ufUpdate, ufInit)
    panel:CreateCheckbox(ufBuilder, WT.L.OPT_FRAMES_UF_HIDE_LEADER, WT.L.OPT_FRAMES_UF_HIDE_LEADER_DESC, "Frames",
        "UnitFramesHideGroupLeader", ufUpdate, ufInit)
    panel:CreateCheckbox(ufBuilder, WT.L.OPT_FRAMES_UF_HIDE_DAMAGE, WT.L.OPT_FRAMES_UF_HIDE_DAMAGE_DESC, "Frames",
        "UnitFramesHideDamageText", ufUpdate, ufInit)
    panel:CreateCheckbox(ufBuilder, WT.L.OPT_FRAMES_UF_HIDE_COMBAT_STATE, WT.L.OPT_FRAMES_UF_HIDE_COMBAT_STATE_DESC,
        "Frames", "UnitFramesHideCombatStateText", ufUpdate, ufInit)
end
