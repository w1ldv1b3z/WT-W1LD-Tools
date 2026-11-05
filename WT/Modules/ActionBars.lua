local _, WT = ...

WT.Modules.ActionBars = {}
local Module = WT.Modules.ActionBars

-- Localize global functions (Upvaluing)
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown

local HasActionRange = C_ActionBar and C_ActionBar.HasActionRange or _G["ActionHasRange"]
local IsActionInRange = C_ActionBar and C_ActionBar.IsActionInRange or _G["IsAction".."InRange"]
local IsUsableAction = C_ActionBar and C_ActionBar.IsUsableAction or _G["IsUsable".."Action"]
local GetActionInfo = _G["GetActionInfo"]
local GetMacroSpell = _G["GetMacroSpell"]
local GetMacroItem = _G["GetMacroItem"]
local GetPetActionCooldown = _G["GetPetActionCooldown"]
local GetPetActionInfo = _G["GetPetActionInfo"]

local hotkeyCache = {}
local cachedHotkeyColor = { r = 1, g = 1, b = 1 }

local actionCache = {}
local petActionCache = {}

local function UpdateActionCache()
    if InCombatLockdown() then return end
    for i = 1, 200 do
        local aType, id = GetActionInfo(i)
        if aType then actionCache[i] = { type = aType, id = id }
        else actionCache[i] = nil end
    end
    for i = 1, 10 do
        local _, _, _, _, _, _, spellID = GetPetActionInfo(i)
        petActionCache[i] = spellID
    end
end

-- Taint Protection: Use weak tables instead of modifying Blizzard buttons
local abData = setmetatable({}, { __mode = "k" })

local Unsecret = WT.Utils.Safety.Unsecret
local SafeNum = WT.Utils.Safety.SafeNum

local function CleanHotkeyText(text)
    if not text or text == "" then return text end
    
    if hotkeyCache[text] then return hotkeyCache[text] end
    
    local origText = text
    text = string.gsub(text, "(s%-)", "S-")
    text = string.gsub(text, "(a%-)", "A-")
    text = string.gsub(text, "(c%-)", "C-")
    text = string.gsub(text, "Mouse Button ", "M")
    text = string.gsub(text, "Middle Mouse", "M3")
    text = string.gsub(text, "Num Pad ", "N")
    text = string.gsub(text, "Page Up", "PU")
    text = string.gsub(text, "Page Down", "PD")
    text = string.gsub(text, "Spacebar", "Spc")
    text = string.gsub(text, "Insert", "Ins")
    text = string.gsub(text, "Home", "Hm")
    text = string.gsub(text, "Delete", "Del")
    text = string.gsub(text, "Num Lock", "NL")
    
    -- German localization fixes for keybinds
    if GetLocale() == "deDE" then
        text = string.gsub(text, "Mittlere Maustaste", "M3")
        text = string.gsub(text, "Maustaste ", "M")
        text = string.gsub(text, "Bild auf", "PU")
        text = string.gsub(text, "Bild ab", "PD")
        text = string.gsub(text, "Leertaste", "Spc")
        text = string.gsub(text, "Einfügen", "Ins")
        text = string.gsub(text, "Pos1", "Hm")
        text = string.gsub(text, "Entfernen", "Del")
        text = string.gsub(text, "Nummernblock ", "N")
    end
    
    hotkeyCache[origText] = text
    return text
end

local function ShouldUpdateFont(fontObj, font, size, outline)
    local currentFont, currentSize, currentFlags = fontObj:GetFont()
    if currentFont ~= font or currentSize ~= size then return true end
    
    local cFlags = currentFlags and string.upper(currentFlags) or ""
    local oFlags = outline and string.upper(outline) or ""
    if cFlags == oFlags then return false end
    
    -- WoW sometimes formats strings internally (e.g., "MONOCHROME, OUTLINE")
    local m1 = string.find(cFlags, "MONOCHROME") and true or false
    local m2 = string.find(oFlags, "MONOCHROME") and true or false
    local to1 = string.find(cFlags, "THICKOUTLINE") and true or false
    local to2 = string.find(oFlags, "THICKOUTLINE") and true or false
    local o1 = string.find(string.gsub(cFlags, "THICKOUTLINE", ""), "OUTLINE") and true or false
    local o2 = string.find(string.gsub(oFlags, "THICKOUTLINE", ""), "OUTLINE") and true or false
    
    if m1 == m2 and to1 == to2 and o1 == o2 then return false end
    return true
end

local function FormatCooldownTime(remain)
    if remain > 86400 then return string.format("%dd", math.ceil(remain / 86400))
    elseif remain > 3600 then return string.format("%dh", math.ceil(remain / 3600))
    elseif remain > 60 then return string.format("%dm", math.ceil(remain / 60))
    elseif remain >= 3 then return tostring(math.ceil(remain))
    elseif remain > 0 then return string.format("%.1f", remain)
    else return "" end
end

    local function ApplyCooldownSettings(cd)
        if not cd then return end
        cd:SetDrawEdge(WT.DB.ActionBars.CustomCooldown and WT.DB.ActionBars.CooldownEdge)
        cd:SetHideCountdownNumbers(WT.DB.ActionBars.CustomCooldownText or WT.DB.ActionBars.HideCooldownNumbers)
        
        if WT.DB.ActionBars.CustomCooldown then
            if cd.SetSwipeTexture then cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8") end
            if cd.SetUseCircularEdge then cd:SetUseCircularEdge(false) end
            
            local sCol = WT.DB.ActionBars.CooldownSwipeColor or {r=0, g=0, b=0, a=0.8}
            local cr, cg, cb, ca = 0, 0, 0, 0.8
            if type(sCol) == "table" then cr, cg, cb, ca = sCol.r or 0, sCol.g or 0, sCol.b or 0, sCol.a or 0.8
            elseif type(sCol) == "string" then cr, cg, cb = WT.Colors:HexToRGB(sCol); ca = 0.8 end
            
            cd:SetSwipeColor(cr, cg, cb, ca)
        else
            if cd.SetSwipeTexture then cd:SetSwipeTexture(130838) end
            cd:SetSwipeColor(0, 0, 0, 0.8)
        end
    end

local function UpdateCooldownAnim(button)
    if not button or not button.cooldown then return end
    
    ApplyCooldownSettings(button.cooldown)
    ApplyCooldownSettings(button.chargeCooldown)
    
    local mData = abData[button]
    if not mData then mData = {}; abData[button] = mData end
    
    if WT.DB.ActionBars.CustomCooldownText then
        if not mData.cooldownFrame then
            mData.cooldownFrame = CreateFrame("Frame", nil, button)
            mData.cooldownFrame:SetAllPoints(button)
            mData.cooldownText = mData.cooldownFrame:CreateFontString(nil, "OVERLAY")
            mData.cooldownText:SetPoint("CENTER", mData.cooldownFrame, "CENTER", 1, 0)
        end
        local targetLevel = button.cooldown:GetFrameLevel()
        if button.chargeCooldown and button.chargeCooldown:GetFrameLevel() > targetLevel then
            targetLevel = button.chargeCooldown:GetFrameLevel()
        end
        mData.cooldownFrame:SetFrameLevel(targetLevel + 5)
        
        local fontKey = WT.DB.ActionBars.CooldownFont or "Friz Quadrata TT"
        local font = WT.Utils.SharedMedia:Fetch("font", fontKey) or "Fonts\\FRIZQT__.TTF"
        local size = WT.DB.ActionBars.CooldownFontSize or 14
        local outline = (WT.DB.ActionBars.CooldownFontOutline == "NONE") and "" or (WT.DB.ActionBars.CooldownFontOutline or "OUTLINE")
        if ShouldUpdateFont(mData.cooldownText, font, size, outline) then mData.cooldownText:SetFont(font, size, outline) end
        
        local cCol = WT.DB.ActionBars.CooldownTextColor or "FFFF00"
        local r, g, b = 1, 1, 0
        if type(cCol) == "table" then r, g, b = cCol.r or 1, cCol.g or 1, cCol.b or 1 else r, g, b = WT.Colors:HexToRGB(cCol) end
        mData.cooldownText:SetTextColor(r, g, b)
        mData.cooldownText:Show()
    else
        if mData.cooldownText then mData.cooldownText:Hide() end
    end
end

local function GetSafeActionState(action)
    if not action or type(action) ~= "number" then return false, false, false end
    
    local outOfRange, isUsable, notEnoughMana = false, false, false
    
    -- In WoW 11.0+ (The War Within), IsActionInRange returns false if an action has NO range.
    -- We must explicitly check HasActionRange first to avoid incorrectly tinting melee abilities red!
    local hasRange = false
    if HasActionRange then
        local okH, hR = pcall(HasActionRange, action)
        if okH and hR then hasRange = true end
    else
        local okH, irH = pcall(IsActionInRange, action)
        if okH and irH ~= nil then hasRange = true end
    end
    
    if hasRange then
        local ok1, ir = pcall(IsActionInRange, action)
        if ok1 then
            if type(ir) == "boolean" then outOfRange = (ir == false)
            else outOfRange = ((SafeNum(ir) or 0) == 0) end
        end
    end
    
    local ok2, iu, nm = pcall(IsUsableAction, action)
    if ok2 then
        if type(iu) == "boolean" then isUsable = (iu == true)
        else isUsable = ((SafeNum(iu) or 0) == 1) end
        
        if type(nm) == "boolean" then notEnoughMana = (nm == true)
        else notEnoughMana = ((SafeNum(nm) or 0) == 1) end
    end
    
    return isUsable, notEnoughMana, outOfRange
end

local function ApplyActionColor(btn)
    local icon = btn.icon or btn.Icon
    if not icon or type(btn.action) ~= "number" then return end
    
    local mData = abData[btn]
    if not mData then mData = {}; abData[btn] = mData end
    
    local isUsable, notEnoughMana, outOfRange = GetSafeActionState(btn.action)
    
    local tr, tg, tb
    if WT.DB.ActionBars.OutofRangeTint then
        if outOfRange then tr, tg, tb = 0.8, 0.1, 0.1
        elseif isUsable then tr, tg, tb = 1.0, 1.0, 1.0
        elseif notEnoughMana then tr, tg, tb = 0.5, 0.5, 1.0
        else tr, tg, tb = 0.4, 0.4, 0.4 end
    else
        if isUsable then tr, tg, tb = 1.0, 1.0, 1.0
        elseif notEnoughMana then tr, tg, tb = 0.5, 0.5, 1.0
        else tr, tg, tb = 0.4, 0.4, 0.4 end
    end
    
    if mData.lastIconR ~= tr or mData.lastIconG ~= tg or mData.lastIconB ~= tb then
        icon:SetVertexColor(tr, tg, tb)
        mData.lastIconR, mData.lastIconG, mData.lastIconB = tr, tg, tb
    end
end

local function UpdateButton(button)
    if not button then return end

    local mData = abData[button]
    if not mData then mData = {}; abData[button] = mData end

    -- PRE-CACHE: Save original texts to restore them immediately upon disabling
    if button.Name and not mData.origNameCaptured then
        local ok, txt = pcall(button.Name.GetText, button.Name)
        if ok and txt then
            local safeTxt = Unsecret(txt)
            if safeTxt then mData.origName = safeTxt end
        end
        mData.origNameCaptured = true
    end
    if button.HotKey and not mData.origHotkeyCaptured then
        local ok, txt = pcall(button.HotKey.GetText, button.HotKey)
        if ok and txt then
            local safeTxt = Unsecret(txt)
            if safeTxt then mData.origHotkey = safeTxt end
        end
        mData.origHotkeyCaptured = true
    end

    -- 1. Handle Macro Text
    if button.Name then
        if WT.DB.ActionBars.HideMacroText then
            if mData.lastNameAlpha ~= 0 then button.Name:SetAlpha(0); mData.lastNameAlpha = 0 end
        elseif WT.DB.ActionBars.CustomMacroText then
            if mData.lastNameAlpha ~= 1 then button.Name:SetAlpha(1); mData.lastNameAlpha = 1 end
            
            local fontKey = WT.DB.ActionBars.MacroFont or "PT Sans Narrow"
            local font = WT.Utils.SharedMedia:Fetch("font", fontKey) or "Fonts\\FRIZQT__.TTF"
            local size = WT.DB.ActionBars.MacroSize or 10
            local outline = (WT.DB.ActionBars.MacroOutline == "NONE") and "" or (WT.DB.ActionBars.MacroOutline or "OUTLINE")
            
            if ShouldUpdateFont(button.Name, font, size, outline) then
                button.Name:SetFont(font, size, outline)
            end
            
            local mCol = WT.DB.ActionBars.MacroColor or "FFFFFF"
            local r, g, b = 1, 1, 1
            if type(mCol) == "table" then r, g, b = mCol.r or 1, mCol.g or 1, mCol.b or 1 else r, g, b = WT.Colors:HexToRGB(mCol) end
            
            local curR, curG, curB = button.Name:GetTextColor()
            if math.abs((curR or 0) - r) > 0.01 or math.abs((curG or 0) - g) > 0.01 or math.abs((curB or 0) - b) > 0.01 then
                button.Name:SetTextColor(r, g, b)
            end
            
            if mData.origName and mData.lastNameText ~= mData.origName then
                button.Name:SetText(mData.origName)
                mData.lastNameText = mData.origName
            end
        else
            if mData.lastNameAlpha ~= 1 then button.Name:SetAlpha(1); mData.lastNameAlpha = 1 end
            local f, s, o = GameFontHighlightSmallOutline:GetFont()
            if f then button.Name:SetFont(f, s, o) end
            button.Name:SetFontObject("GameFontHighlightSmallOutline")
            
            local curR, curG, curB = button.Name:GetTextColor()
            if math.abs((curR or 0) - 1) > 0.01 or math.abs((curG or 0) - 1) > 0.01 or math.abs((curB or 0) - 1) > 0.01 then
                button.Name:SetTextColor(1, 1, 1)
            end
            
            if mData.origName and mData.lastNameText ~= mData.origName then
                button.Name:SetText(mData.origName)
                mData.lastNameText = mData.origName
            end
        end
    end

    -- 2. Handle Hotkey Text
    if button.HotKey then
        if WT.DB.ActionBars.HideHotkeyText then
            if mData.lastHotkeyAlpha ~= 0 then button.HotKey:SetAlpha(0); mData.lastHotkeyAlpha = 0 end
        elseif WT.DB.ActionBars.CustomHotkeyText then
            if mData.lastHotkeyAlpha ~= 1 then button.HotKey:SetAlpha(1); mData.lastHotkeyAlpha = 1 end
            local rawHotkey = nil
            local okHK, hk = pcall(button.HotKey.GetText, button.HotKey)
            if okHK and hk then rawHotkey = Unsecret(hk) end
            local baseText = mData.origHotkey or rawHotkey
            local targetText = baseText
            if WT.DB.ActionBars.CleanHotkeys then
                if baseText and baseText ~= "" and baseText ~= RANGE_INDICATOR then
                    local ok, cleanText = pcall(CleanHotkeyText, baseText)
                    if ok and cleanText then
                        targetText = cleanText
                    end
                end
            end
            
            if mData.lastHotkeyText ~= targetText then
                button.HotKey:SetText(targetText)
                mData.lastHotkeyText = targetText
            end
            
            local fontKey = WT.DB.ActionBars.HotkeyFont or "PT Sans Narrow"
            local font = WT.Utils.SharedMedia:Fetch("font", fontKey) or "Fonts\\FRIZQT__.TTF"
            local size = WT.DB.ActionBars.HotkeySize or 14
            local outline = (WT.DB.ActionBars.HotkeyOutline == "NONE") and "" or (WT.DB.ActionBars.HotkeyOutline or "OUTLINE")
            
            if ShouldUpdateFont(button.HotKey, font, size, outline) then
                button.HotKey:SetFont(font, size, outline)
            end
            
            local curR, curG, curB = button.HotKey:GetTextColor()
            if math.abs((curR or 0) - cachedHotkeyColor.r) > 0.01 or math.abs((curG or 0) - cachedHotkeyColor.g) > 0.01 or math.abs((curB or 0) - cachedHotkeyColor.b) > 0.01 then
                button.HotKey:SetTextColor(cachedHotkeyColor.r, cachedHotkeyColor.g, cachedHotkeyColor.b)
            end
        else
            if mData.lastHotkeyAlpha ~= 1 then button.HotKey:SetAlpha(1); mData.lastHotkeyAlpha = 1 end
            local f, s, o = NumberFontNormalSmallGray:GetFont()
            if f then button.HotKey:SetFont(f, s, o) end
            button.HotKey:SetFontObject("NumberFontNormalSmallGray")
            
            local curR, curG, curB = button.HotKey:GetTextColor()
            if math.abs((curR or 0) - 0.6) > 0.01 or math.abs((curG or 0) - 0.6) > 0.01 or math.abs((curB or 0) - 0.6) > 0.01 then
                button.HotKey:SetTextColor(0.6, 0.6, 0.6)
            end
            
            if mData.origHotkey and mData.lastHotkeyText ~= mData.origHotkey then
                button.HotKey:SetText(mData.origHotkey)
                mData.lastHotkeyText = mData.origHotkey
            end
        end
    end

    -- 3. Handle Count/Charges Text
    if button.Count then
        if WT.DB.ActionBars.HideCountText then
            if mData.lastCountAlpha ~= 0 then button.Count:SetAlpha(0); mData.lastCountAlpha = 0 end
        elseif WT.DB.ActionBars.CustomCountText then
            if mData.lastCountAlpha ~= 1 then button.Count:SetAlpha(1); mData.lastCountAlpha = 1 end
            
            local fontKey = WT.DB.ActionBars.CountFont or "Friz Quadrata TT"
            local font = WT.Utils.SharedMedia:Fetch("font", fontKey) or "Fonts\\FRIZQT__.TTF"
            local size = WT.DB.ActionBars.CountSize or 14
            local outline = (WT.DB.ActionBars.CountOutline == "NONE") and "" or (WT.DB.ActionBars.CountOutline or "OUTLINE")
            
            if ShouldUpdateFont(button.Count, font, size, outline) then
                button.Count:SetFont(font, size, outline)
            end
            
            local cCol = WT.DB.ActionBars.CountColor or "FFFFFF"
            local r, g, b = 1, 1, 1
            if type(cCol) == "table" then r, g, b = cCol.r or 1, cCol.g or 1, cCol.b or 1 else r, g, b = WT.Colors:HexToRGB(cCol) end
            
            local curR, curG, curB = button.Count:GetTextColor()
            if math.abs((curR or 0) - r) > 0.01 or math.abs((curG or 0) - g) > 0.01 or math.abs((curB or 0) - b) > 0.01 then
                button.Count:SetTextColor(r, g, b)
            end
        else
            if mData.lastCountAlpha ~= 1 then button.Count:SetAlpha(1); mData.lastCountAlpha = 1 end
            local f, s, o = NumberFontNormal:GetFont()
            if f then button.Count:SetFont(f, s, o) end
            button.Count:SetFontObject("NumberFontNormal")
            
            local curR, curG, curB = button.Count:GetTextColor()
            if math.abs((curR or 0) - 1) > 0.01 or math.abs((curG or 0) - 1) > 0.01 or math.abs((curB or 0) - 1) > 0.01 then
                button.Count:SetTextColor(1, 1, 1)
            end
        end
    end
    
    UpdateCooldownAnim(button)
    
    -- Reset desaturation if feature is disabled
    if not WT.DB.ActionBars.DesaturateCooldown then
        if mData.isDesaturated then
            mData.isDesaturated = false
            local icon = button.icon or button.Icon
            if icon then icon:SetDesaturated(false) end
        end
    end
    
    -- Apply or reset Out of Range Tint immediately (bypasses WoW's native state caching)
    ApplyActionColor(button)
end

local function CooldownTick()
    if not WT.DB or not WT.DB.ActionBars then return end
    
    local doText = WT.DB.ActionBars.CustomCooldownText
    local doDesat = WT.DB.ActionBars.DesaturateCooldown
    if not (doText or doDesat) or not Module.TrackedButtons then return end
    
    local now = GetTime()
    local threshold = WT.DB.ActionBars.CooldownMinDuration or 1.5
    local tracked = Module.TrackedButtons
    
    for i = 1, #tracked do
        local btn = tracked[i].frame
        local bType = tracked[i].type
        
        local mData = abData[btn]
        if not mData then mData = {}; abData[btn] = mData end
        
        if btn:IsVisible() then
            local cd = btn.cooldown
            local ccd = btn.chargeCooldown
            local hasCooldown = cd and cd:IsShown()
            local hasCharge = ccd and ccd:IsShown()
            
            local isDesaturated = false
            local newText = ""
            
            if hasCooldown or hasCharge then
                local s1, d1 = 0, 0
                local s2, d2 = 0, 0
                
                if bType == "action" and type(btn.action) == "number" then
                    local actionType, id
                    if InCombatLockdown() then
                        local cached = actionCache[btn.action]
                        if cached then actionType, id = cached.type, cached.id end
                    else
                        actionType, id = GetActionInfo(btn.action)
                    end
                    
                    if actionType == "spell" and type(id) == "number" then
                        if C_Spell and C_Spell.GetSpellCooldown then
                            local cdInfo = C_Spell.GetSpellCooldown(id)
                            if cdInfo then s1, d1 = SafeNum(cdInfo.startTime) or 0, SafeNum(cdInfo.duration) or 0 end
                        end
                        if C_Spell and C_Spell.GetSpellCharges then
                            local chInfo = C_Spell.GetSpellCharges(id)
                            if chInfo then
                                pcall(function() 
                                    local curr = SafeNum(chInfo.currentCharges) or 0
                                    local maxC = SafeNum(chInfo.maxCharges) or 0
                                    if curr < maxC then 
                                        s2 = SafeNum(chInfo.cooldownStartTime) or 0
                                        d2 = SafeNum(chInfo.cooldownDuration) or 0
                                    end 
                                end)
                            end
                        end
                    elseif actionType == "item" and type(id) == "number" then
                        if C_Container and C_Container.GetItemCooldown then
                            local s, d = C_Container.GetItemCooldown(id)
                            s1, d1 = SafeNum(s) or 0, SafeNum(d) or 0
                        end
                    elseif actionType == "macro" and type(id) == "number" then
                        if InCombatLockdown() then
                            -- Skip macros in combat to prevent dynamic evaluation taints
                        else
                        local spellID = GetMacroSpell(id)
                        if spellID and spellID > 0 then
                            if C_Spell and C_Spell.GetSpellCooldown then
                                local cdInfo = C_Spell.GetSpellCooldown(spellID)
                                    if cdInfo then s1, d1 = SafeNum(cdInfo.startTime) or 0, SafeNum(cdInfo.duration) or 0 end
                            end
                            if C_Spell and C_Spell.GetSpellCharges then
                                local chInfo = C_Spell.GetSpellCharges(spellID)
                                    if chInfo then
                                        pcall(function() 
                                            local curr = SafeNum(chInfo.currentCharges) or 0
                                            local maxC = SafeNum(chInfo.maxCharges) or 0
                                            if curr < maxC then 
                                                s2 = SafeNum(chInfo.cooldownStartTime) or 0
                                                d2 = SafeNum(chInfo.cooldownDuration) or 0
                                            end 
                                        end)
                                    end
                            end
                        else
                                local itemName, itemLink = GetMacroItem(id)
                                local itemID = nil
                                if type(itemLink) == "string" then
                                    itemID = tonumber(string.match(itemLink, "item:(%d+)"))
                                elseif type(itemName) == "string" then
                                    itemID = tonumber(string.match(itemName, "item:(%d+)"))
                                end
                            if type(itemID) == "number" and C_Container and C_Container.GetItemCooldown then
                                local s, d = C_Container.GetItemCooldown(itemID)
                                s1, d1 = SafeNum(s) or 0, SafeNum(d) or 0
                            end
                        end
                        end
                    end
                elseif bType == "pet" then
                    local spellID
                    if InCombatLockdown() then
                        spellID = petActionCache[btn:GetID()]
                    else
                        _, _, _, _, _, _, spellID = GetPetActionInfo(btn:GetID())
                    end
                    if type(spellID) == "number" and C_Spell and C_Spell.GetSpellCooldown then
                        local cdInfo = C_Spell.GetSpellCooldown(spellID)
                        if cdInfo then s1, d1 = SafeNum(cdInfo.startTime) or 0, SafeNum(cdInfo.duration) or 0 end
                    elseif not btn:IsProtected() then
                        local cStart, cDur = GetPetActionCooldown(btn:GetID())
                        s1, d1 = SafeNum(cStart) or 0, SafeNum(cDur) or 0
                    end
                else
                    if hasCooldown and not btn:IsProtected() and not InCombatLockdown() then
                        local okC, cs, cdur = pcall(cd.GetCooldownTimes, cd)
                        if okC then
                            s1 = (SafeNum(cs) or 0) / 1000
                            d1 = (SafeNum(cdur) or 0) / 1000
                        end
                    end
                    if hasCharge and not btn:IsProtected() and not InCombatLockdown() then
                        local okC, cs, cdur = pcall(ccd.GetCooldownTimes, ccd)
                        if okC then
                            s2 = (SafeNum(cs) or 0) / 1000
                            d2 = (SafeNum(cdur) or 0) / 1000
                        end
                    end
                end
                
                local r1, r2 = 0, 0
                pcall(function() r1 = (d1 > threshold) and ((s1 + d1) - now) or 0 end)
                pcall(function() r2 = (d2 > threshold) and ((s2 + d2) - now) or 0 end)
                local remain = math.max(r1, r2)
                
                if remain > 0 then
                    isDesaturated = true
                    local displayVal = (remain >= 3) and math.ceil(remain) or (math.floor(remain * 10) / 10)
                    if mData.lastDisplayVal ~= displayVal then
                        mData.lastDisplayVal = displayVal
                        newText = FormatCooldownTime(remain)
                    else
                        newText = mData.lastCooldownText or ""
                    end
                else
                    mData.lastDisplayVal = nil
                end
            end
            
            if doText and mData.cooldownText then
                if mData.lastCooldownText ~= newText then
                    mData.cooldownText:SetText(newText)
                    mData.lastCooldownText = newText
                end
            end
            
            if doDesat then
                if mData.isDesaturated ~= isDesaturated then
                    mData.isDesaturated = isDesaturated
                    local icon = btn.icon or btn.Icon
                    if icon then icon:SetDesaturated(isDesaturated) end
                end
            else
                if mData.isDesaturated then
                    mData.isDesaturated = false
                    local icon = btn.icon or btn.Icon
                    if icon then icon:SetDesaturated(false) end
                end
            end
        else
            if doText and mData.cooldownText and mData.lastCooldownText ~= "" then
                mData.cooldownText:SetText("")
                mData.lastCooldownText = ""
            end
            if mData.isDesaturated then
                mData.isDesaturated = false
                local icon = btn.icon or btn.Icon
                if icon then icon:SetDesaturated(false) end
            end
        end
    end
end

function Module:UpdateAllBars()
    if WT.DB.ActionBars.CustomHotkeyText then
        local hCol = WT.DB.ActionBars.HotkeyColor
        if type(hCol) == "table" then
            cachedHotkeyColor.r, cachedHotkeyColor.g, cachedHotkeyColor.b = hCol.r or 1, hCol.g or 1, hCol.b or 1
        else
            cachedHotkeyColor.r, cachedHotkeyColor.g, cachedHotkeyColor.b = WT.Colors:HexToRGB(hCol)
        end
    end
    
    if not Module.TrackedButtons then Module.TrackedButtons = {} else wipe(Module.TrackedButtons) end
    local bars = {
        "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", 
        "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", 
        "MultiBar6Button", "MultiBar7Button", "PetActionButton", "StanceButton"
    }
    for _, prefix in ipairs(bars) do
        for i = 1, 12 do
            local btn = _G[prefix..i]
            if btn then 
                local bType = "action"
                if prefix == "PetActionButton" then bType = "pet"
                elseif prefix == "StanceButton" then bType = "stance"
                elseif type(btn.action) ~= "number" then bType = "custom" end
                table.insert(Module.TrackedButtons, { frame = btn, type = bType })
                UpdateButton(btn) 
            end
        end
    end
    
    -- Add special Encounter, Zone, and Vehicle buttons (Taint-protected)
    local specialBtns = { _G["ExtraActionButton1"], _G["ZoneAbilityFrame"] and _G["ZoneAbilityFrame"].SpellButton }
    for i = 1, 6 do table.insert(specialBtns, _G["OverrideActionBarButton"..i]) end
    
    for _, sBtn in ipairs(specialBtns) do
        if sBtn then 
            table.insert(Module.TrackedButtons, { frame = sBtn, type = "action" })
            UpdateButton(sBtn) 
        end
    end
end

function Module:ProtectVehicleButton()
    local vBtn = _G["MainMenuBarVehicleLeaveButton"] or _G["OverrideActionBarLeaveFrameLeaveButton"]
    if not vBtn then return end
    
    local hasSkinEngine = _G["Masque"] or (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Masque"))
    
    local vData = abData[vBtn]
    if not vData then vData = {}; abData[vBtn] = vData end
    
    if hasSkinEngine then
        if not vData.wtIcon then
            vData.wtIcon = vBtn:CreateTexture(nil, "ARTWORK")
            vData.wtIcon:SetAllPoints(vBtn)
        end
        
        local vIcon = vData.wtIcon
        
        -- Safely determine the native graphic (from .icon, .Icon, or NormalTexture)
        local nativeAtlas, nativeTex
        local nativeIconReg = vBtn.icon or vBtn.Icon
        if nativeIconReg then
            nativeAtlas = type(nativeIconReg.GetAtlas) == "function" and nativeIconReg:GetAtlas() or nil
            nativeTex = type(nativeIconReg.GetTexture) == "function" and nativeIconReg:GetTexture() or nil
        end
        
        local nTex = type(vBtn.GetNormalTexture) == "function" and vBtn:GetNormalTexture() or nil
        if not nativeAtlas and not nativeTex and nTex then
            nativeAtlas = type(nTex.GetAtlas) == "function" and nTex:GetAtlas() or nil
            nativeTex = type(nTex.GetTexture) == "function" and nTex:GetTexture() or nil
        end
        
        -- If Blizzard recently added a native .icon (e.g., in Patch 11.0), Masque will try to skin it and mess it up.
        -- We hide the native icon so Masque just skins the background, and our wtIcon stays safely on top.
        if vBtn.icon then
            vBtn.icon:SetAlpha(0)
            if not vData.iconHooked then
                vData.iconHooked = true
                hooksecurefunc(vBtn.icon, "SetAlpha", function(self, a) if a > 0 then self:SetAlpha(0) end end)
            end
        elseif vBtn.Icon then
            vBtn.Icon:SetAlpha(0)
            if not vData.IconHooked then
                vData.IconHooked = true
                hooksecurefunc(vBtn.Icon, "SetAlpha", function(self, a) if a > 0 then self:SetAlpha(0) end end)
            end
        end

        if vIcon then
            if nativeAtlas then
                vIcon:SetAtlas(nativeAtlas)
                vData.useAtlas = nativeAtlas
            elseif nativeTex then
                vIcon:SetTexture(nativeTex)
                vData.useTex = nativeTex
            else
                -- Fallback to modern atlas or old texture
                if type(vIcon.SetAtlas) == "function" then
                    vIcon:SetAtlas("UI-HUD-Vehicle-Exit-Up")
                    vData.useAtlas = "UI-HUD-Vehicle-Exit-Up"
                else
                    vIcon:SetTexture("Interface\\Vehicles\\UI-Vehicles-Button-Exit-Up")
                    vData.useTex = "Interface\\Vehicles\\UI-Vehicles-Button-Exit-Up"
                end
            end
            
            vIcon:SetDrawLayer("OVERLAY", 7)
            vIcon:SetAlpha(1)
            vIcon:Show()
            
            if not vData.protected then
                vData.protected = true
                vData.isFixing = false
                
                local fixFunc = function(self)
                    if vData.isFixing then return end
                    vData.isFixing = true
                    if vData.useAtlas then
                        self:SetAtlas(vData.useAtlas)
                    elseif vData.useTex then
                        self:SetTexture(vData.useTex)
                    end
                    vData.isFixing = false
                    self:SetDrawLayer("OVERLAY", 7)
                end
                
                hooksecurefunc(vIcon, "SetTexture", function(self, tex)
                    local isSecret = type(tex) == "string" and not pcall(string.match, tex, "")
                    if not isSecret and (not tex or tex == "" or tex == 0 or tex == "0") then
                        fixFunc(self)
                    end
                end)
                
                if type(vIcon.SetAtlas) == "function" then
                    hooksecurefunc(vIcon, "SetAtlas", function(self, atlas)
                        if not atlas or atlas == "" then
                            fixFunc(self)
                        end
                    end)
                end
            end
        end
    else
        -- Safely determine the native graphic
        local nativeAtlas, nativeTex
        local nativeIconReg = vBtn.icon or vBtn.Icon
        if nativeIconReg then
            nativeAtlas = type(nativeIconReg.GetAtlas) == "function" and nativeIconReg:GetAtlas() or nil
            nativeTex = type(nativeIconReg.GetTexture) == "function" and nativeIconReg:GetTexture() or nil
        end
        
        local nTex = type(vBtn.GetNormalTexture) == "function" and vBtn:GetNormalTexture() or nil
        if not nativeAtlas and not nativeTex and nTex then
            nativeAtlas = type(nTex.GetAtlas) == "function" and nTex:GetAtlas() or nil
            nativeTex = type(nTex.GetTexture) == "function" and nTex:GetTexture() or nil
        end
        
        local useAtlas = nativeAtlas or nil
        local useTex = nativeTex or nil
        
        if not useAtlas and not useTex then
            if type(vBtn.SetNormalAtlas) == "function" then
                vBtn:SetNormalAtlas("UI-HUD-Vehicle-Exit-Up")
                useAtlas = "UI-HUD-Vehicle-Exit-Up"
            else
                vBtn:SetNormalTexture("Interface\\Vehicles\\UI-Vehicles-Button-Exit-Up")
                useTex = "Interface\\Vehicles\\UI-Vehicles-Button-Exit-Up"
            end
        end
        
        nTex = type(vBtn.GetNormalTexture) == "function" and vBtn:GetNormalTexture() or nil
        if nTex then 
            nTex:SetAlpha(1)
            nTex:Show()
            nTex:SetDrawLayer("OVERLAY", 7)
        end
        
        if not vData.protected then
            vData.protected = true
            vData.isFixing = false
            
            local fixFunc = function(self)
                if vData.isFixing then return end
                vData.isFixing = true
                if useAtlas and type(self.SetNormalAtlas) == "function" then
                    self:SetNormalAtlas(useAtlas)
                elseif useTex then
                    self:SetNormalTexture(useTex)
                end
                vData.isFixing = false
            end
            
            hooksecurefunc(vBtn, "SetNormalTexture", function(self, tex)
                local isSecret = type(tex) == "string" and not pcall(string.match, tex, "")
                if not isSecret and (not tex or tex == "" or tex == 0 or tex == "0") then
                    fixFunc(self)
                end
            end)
            if type(vBtn.SetNormalAtlas) == "function" then
                hooksecurefunc(vBtn, "SetNormalAtlas", function(self, atlas)
                    if not atlas or atlas == "" then
                        fixFunc(self)
                    end
                end)
            end
            
            if nTex then
                hooksecurefunc(nTex, "SetAlpha", function(self, a)
                    if not InCombatLockdown() and a == 0 and vBtn:IsShown() then self:SetAlpha(1) end
                end)
            end
        end
    end
end

local skinEngineApplied = false
function Module:ApplySkinEngineSupport()
    if skinEngineApplied or not WT.DB.ActionBars.MasqueSupport then return end
    skinEngineApplied = true
    
    local SE = LibStub and LibStub("Masque", true)
    if not SE then return end
    
    local grpActionBars = SE:Group("WT (W1LD Tools)", "ActionBars")
    local grpBags = SE:Group("WT (W1LD Tools)", "BagsBar")
    local grpExtra = SE:Group("WT (W1LD Tools)", "Extra Abilities")
    local grpMisc = SE:Group("WT (W1LD Tools)", "Misc")
    
    local bars = {
        "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", 
        "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", 
        "MultiBar6Button", "MultiBar7Button", "PetActionButton", "StanceButton"
    }
    for _, prefix in ipairs(bars) do
        local maxBtns = (prefix == "PetActionButton" or prefix == "StanceButton") and 10 or 12
        for i = 1, maxBtns do
            local btn = _G[prefix..i]
            if btn then grpActionBars:AddButton(btn) end
        end
    end

    local bags = {
        "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", 
        "CharacterBag2Slot", "CharacterBag3Slot", "CharacterReagentBag0Slot"
    }
    for _, bName in ipairs(bags) do
        local btn = _G[bName]
        if btn then grpBags:AddButton(btn) end
    end

    local extraBtn = _G["ExtraActionButton1"]
    if extraBtn then 
        grpExtra:AddButton(extraBtn) 
    end

    local vBtn = _G["MainMenuBarVehicleLeaveButton"]
    if vBtn then
        grpMisc:AddButton(vBtn)
    end
end

function Module:Initialize()
    if not WT.DB.Modules.ActionBars then return end
    
    if not InCombatLockdown() then
        if WT.DB.ActionBars.KeyDown ~= nil then
            if WT.Utils and WT.Utils.Flags then WT.Utils.Flags:SetCVar("ActionButtonUseKeyDown", WT.DB.ActionBars.KeyDown and "1" or "0")
            else pcall(function() C_CVar.SetCVar("ActionButtonUseKeyDown", WT.DB.ActionBars.KeyDown and "1" or "0") end) end
        end
        if WT.DB.ActionBars.AutoPushSpellToActionBar ~= nil then
            if WT.Utils and WT.Utils.Flags then WT.Utils.Flags:SetCVar("AutoPushSpellToActionBar", WT.DB.ActionBars.AutoPushSpellToActionBar and "1" or "0")
            else pcall(function() C_CVar.SetCVar("AutoPushSpellToActionBar", WT.DB.ActionBars.AutoPushSpellToActionBar and "1" or "0") end) end
        end
        if WT.DB.ActionBars.SpellQueueWindow ~= nil then
            if WT.Utils and WT.Utils.Flags then WT.Utils.Flags:SetCVar("SpellQueueWindow", tostring(WT.DB.ActionBars.SpellQueueWindow))
            else pcall(function() C_CVar.SetCVar("SpellQueueWindow", tostring(WT.DB.ActionBars.SpellQueueWindow)) end) end
        end
    end
    
    if WT.DB.ActionBars.ProtectVehicleButton then
        self:ProtectVehicleButton()
    end
    
    local abMixin = _G["ActionButtonMixin"]
    if abMixin then
        if type(abMixin.Update) == "function" then 
            hooksecurefunc(abMixin, "Update", function(btn) 
                local mData = abData[btn]; if not mData then mData = {}; abData[btn] = mData end
                if btn.Name then 
                    local ok, txt = pcall(btn.Name.GetText, btn.Name)
                    if ok and txt then
                        local safeTxt = Unsecret(txt)
                        if safeTxt then mData.origName = safeTxt; mData.origNameCaptured = true end
                    end
                end
                UpdateButton(btn) 
            end) 
        end
        if type(abMixin.UpdateHotkeys) == "function" then 
            hooksecurefunc(abMixin, "UpdateHotkeys", function(btn) 
                local mData = abData[btn]; if not mData then mData = {}; abData[btn] = mData end
                if btn.HotKey then 
                    local ok, txt = pcall(btn.HotKey.GetText, btn.HotKey)
                    if ok and txt then
                        local safeTxt = Unsecret(txt)
                        if safeTxt then mData.origHotkey = safeTxt; mData.origHotkeyCaptured = true end
                    end
                end
                UpdateButton(btn) 
            end) 
        end
        
        if type(abMixin.UpdateCount) == "function" then
            hooksecurefunc(abMixin, "UpdateCount", function(btn)
                UpdateButton(btn)
            end)
        end
        
        if type(abMixin.UpdateCooldown) == "function" then
            hooksecurefunc(abMixin, "UpdateCooldown", function(btn) UpdateCooldownAnim(btn) end)
        end
        
        -- Fix: WoW engine natively resets hotkey colors to grey when a target comes back into range
        if type(abMixin.UpdateRangeIndicator) == "function" then
            hooksecurefunc(abMixin, "UpdateRangeIndicator", function(btn)
                if WT.DB.ActionBars.CustomHotkeyText and btn.HotKey then
                    local r, g, b = btn.HotKey:GetVertexColor()
                    local sr, sg, sb = SafeNum(r), SafeNum(g), SafeNum(b)
                    -- If WoW just reset the color to standard grey, re-apply our custom color!
                    if sr and sg and sb and sr > 0.59 and sr < 0.61 and sg > 0.59 and sg < 0.61 then
                        btn.HotKey:SetVertexColor(cachedHotkeyColor.r, cachedHotkeyColor.g, cachedHotkeyColor.b)
                    end
                end
                
                if WT.DB.ActionBars.OutofRangeTint then
                    ApplyActionColor(btn)
                end
            end)
        end
        
        if type(abMixin.UpdateUsable) == "function" then
            hooksecurefunc(abMixin, "UpdateUsable", function(btn)
                if WT.DB.ActionBars.OutofRangeTint then
                    ApplyActionColor(btn)
                end
                
                if btn.cooldown then ApplyCooldownSettings(btn.cooldown) end
                if btn.chargeCooldown then ApplyCooldownSettings(btn.chargeCooldown) end
            end)
        end
    end
    
    local petBar = _G["PetActionBar"]
    if petBar and type(petBar.Update) == "function" then
        hooksecurefunc(petBar, "Update", function()
            for i = 1, 10 do
                local btn = _G["PetActionButton"..i]
                if btn then UpdateButton(btn) end
            end
        end)
    end
    
    self:UpdateAllBars()
    
    -- Smooth 0.05s loop (20 FPS) for millisecond updates under 3 seconds
    WT.Core.Events:RegisterOnUpdate(CooldownTick, 0.05, "ActionBars_Cooldowns")
    
    UpdateActionCache()
    WT.Core.Events:Register("PLAYER_REGEN_ENABLED", UpdateActionCache)
    WT.Core.Events:Register("ACTIONBAR_SLOT_CHANGED", UpdateActionCache)
    WT.Core.Events:Register("PET_BAR_UPDATE", UpdateActionCache)
end

WT.Core.Events:Register("PLAYER_LOGIN", function()
    Module:Initialize()
end)

WT.Core.Events:Register("PLAYER_ENTERING_WORLD", function()
    if WT.DB.Modules.ActionBars then
        Module:ApplySkinEngineSupport()
    end
end)

function Module:BuildOptions(builder, panel)
    local function PromptReload() if WT.Config and WT.Config.OptionsPanel and WT.Config.OptionsPanel.ShowReloadPrompt then WT.Config.OptionsPanel:ShowReloadPrompt() end end
    
    local function AddDescription(text)
        if not text then return end
        local desc = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
        desc:SetWidth(550)
        desc:SetJustifyH("LEFT")
        desc:SetText(text)
        builder:AddSpace(desc:GetStringHeight() + 25)
    end
    
    panel:CreateTitle(builder, WT.L.GROUP_ACTIONBARS_BEHAVIOR)
    AddDescription(WT.L.OPT_DESC_GROUP_ACTIONBARS_BEHAVIOR)
    
    panel:CreateCheckbox(builder, WT.L.OPT_ACTIONBARS_KEYDOWN, WT.L.OPT_DESC_ACTIONBARS_KEYDOWN, "ActionBars", "KeyDown", function() 
        if WT.Utils and WT.Utils.Flags then WT.Utils.Flags:SetCVar("ActionButtonUseKeyDown", WT.DB.ActionBars.KeyDown and "1" or "0") 
        else pcall(function() C_CVar.SetCVar("ActionButtonUseKeyDown", WT.DB.ActionBars.KeyDown and "1" or "0") end) end 
    end)
    panel:CreateCheckbox(builder, WT.L.OPT_ACTIONBARS_AUTOPUSH, WT.L.OPT_DESC_ACTIONBARS_AUTOPUSH, "ActionBars", "AutoPushSpellToActionBar", function() 
        if WT.Utils and WT.Utils.Flags then WT.Utils.Flags:SetCVar("AutoPushSpellToActionBar", WT.DB.ActionBars.AutoPushSpellToActionBar and "1" or "0") 
        else pcall(function() C_CVar.SetCVar("AutoPushSpellToActionBar", WT.DB.ActionBars.AutoPushSpellToActionBar and "1" or "0") end) end 
    end)
    panel:CreateSlider(builder, WT.L.OPT_ACTIONBARS_SQW, WT.L.OPT_DESC_ACTIONBARS_SQW, "ActionBars", "SpellQueueWindow", 0, 400, 10, function()
        if WT.Utils and WT.Utils.Flags then WT.Utils.Flags:SetCVar("SpellQueueWindow", tostring(WT.DB.ActionBars.SpellQueueWindow))
        else pcall(function() C_CVar.SetCVar("SpellQueueWindow", tostring(WT.DB.ActionBars.SpellQueueWindow)) end) end
    end)
    
    panel:CreateCheckbox(builder, WT.L.OPT_AB_MASQUE_SUPPORT, WT.L.OPT_DESC_AB_MASQUE_SUPPORT, "ActionBars", "MasqueSupport", PromptReload)
    panel:CreateCheckbox(builder, WT.L.OPT_AB_PROTECT_VEHICLE, WT.L.OPT_DESC_AB_PROTECT_VEHICLE, "ActionBars", "ProtectVehicleButton", PromptReload)
    panel:CreateCheckbox(builder, WT.L.OPT_AB_OOR_TINT, WT.L.OPT_DESC_AB_OOR_TINT, "ActionBars", "OutofRangeTint", function() self:UpdateAllBars() end)
    
    panel:CreateTitle(builder, WT.L.GROUP_ACTIONBARS_TEXT)
    AddDescription(WT.L.OPT_DESC_GROUP_ACTIONBARS_TEXT)
    
    local fontOptions = WT.Utils.SharedMedia:GetOptions("font")
    
    local cmInit = panel:CreateCheckbox(builder, WT.L.OPT_AB_CUSTOM_MACRO, WT.L.OPT_DESC_AB_CUSTOM_MACRO, "ActionBars", "CustomMacroText", function() self:UpdateAllBars() end)
    panel:CreateCheckbox(builder, WT.L.OPT_AB_HIDE_MACRO, WT.L.OPT_DESC_AB_HIDE_MACRO, "ActionBars", "HideMacroText", function() self:UpdateAllBars() end)
    panel:CreateDropdown(builder, WT.L.OPT_AB_MACRO_FONT, WT.L.OPT_DESC_AB_MACRO_FONT, "ActionBars", "MacroFont", fontOptions, function() self:UpdateAllBars() end, cmInit)
    panel:CreateSlider(builder, WT.L.OPT_AB_MACRO_SIZE, WT.L.OPT_DESC_AB_MACRO_SIZE, "ActionBars", "MacroSize", 8, 24, 1, function() self:UpdateAllBars() end, cmInit)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "ActionBars", "MacroOutline", function() self:UpdateAllBars() end, cmInit)
    panel:CreateColorPicker(builder, WT.L.OPT_AB_MACRO_COLOR, WT.L.OPT_DESC_AB_MACRO_COLOR, "ActionBars", "MacroColor", false, cmInit, function() self:UpdateAllBars() end)
    
    local chInit = panel:CreateCheckbox(builder, WT.L.OPT_AB_CUSTOM_HOTKEY, WT.L.OPT_DESC_AB_CUSTOM_HOTKEY, "ActionBars", "CustomHotkeyText", function() self:UpdateAllBars() end)
    panel:CreateCheckbox(builder, WT.L.OPT_AB_HIDE_HOTKEY, WT.L.OPT_DESC_AB_HIDE_HOTKEY, "ActionBars", "HideHotkeyText", function() self:UpdateAllBars() end)
    panel:CreateCheckbox(builder, WT.L.OPT_AB_CLEAN_HOTKEYS, WT.L.OPT_DESC_AB_CLEAN_HOTKEYS, "ActionBars", "CleanHotkeys", function() self:UpdateAllBars() end)
    panel:CreateDropdown(builder, WT.L.OPT_AB_HOTKEY_FONT, WT.L.OPT_DESC_AB_HOTKEY_FONT, "ActionBars", "HotkeyFont", fontOptions, function() self:UpdateAllBars() end, chInit)
    panel:CreateSlider(builder, WT.L.OPT_AB_HOTKEY_SIZE, WT.L.OPT_DESC_AB_HOTKEY_SIZE, "ActionBars", "HotkeySize", 8, 24, 1, function() self:UpdateAllBars() end, chInit)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "ActionBars", "HotkeyOutline", function() self:UpdateAllBars() end, chInit)
    panel:CreateColorPicker(builder, WT.L.OPT_AB_HOTKEY_COLOR, WT.L.OPT_DESC_AB_HOTKEY_COLOR, "ActionBars", "HotkeyColor", false, chInit, function() self:UpdateAllBars() end)
    
    local ccInit = panel:CreateCheckbox(builder, WT.L.OPT_AB_CUSTOM_COUNT, WT.L.OPT_DESC_AB_CUSTOM_COUNT, "ActionBars", "CustomCountText", function() self:UpdateAllBars() end)
    panel:CreateCheckbox(builder, WT.L.OPT_AB_HIDE_COUNT, WT.L.OPT_DESC_AB_HIDE_COUNT, "ActionBars", "HideCountText", function() self:UpdateAllBars() end)
    panel:CreateDropdown(builder, WT.L.OPT_AB_COUNT_FONT, WT.L.OPT_DESC_FONT, "ActionBars", "CountFont", fontOptions, function() self:UpdateAllBars() end, ccInit)
    panel:CreateSlider(builder, WT.L.OPT_AB_COUNT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "ActionBars", "CountSize", 8, 24, 1, function() self:UpdateAllBars() end, ccInit)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "ActionBars", "CountOutline", function() self:UpdateAllBars() end, ccInit)
    panel:CreateColorPicker(builder, WT.L.OPT_AB_COUNT_COLOR, WT.L.OPT_DESC_COLOR_VALUE, "ActionBars", "CountColor", false, ccInit, function() self:UpdateAllBars() end)
    
    panel:CreateTitle(builder, WT.L.GROUP_ACTIONBARS_COOLDOWN)
    AddDescription(WT.L.OPT_DESC_GROUP_ACTIONBARS_COOLDOWN)
    
    panel:CreateCheckbox(builder, WT.L.OPT_AB_DESATURATE_COOLDOWN, WT.L.OPT_DESC_AB_DESATURATE_COOLDOWN, "ActionBars", "DesaturateCooldown", function() self:UpdateAllBars() end)
    local cdtInit = panel:CreateCheckbox(builder, WT.L.OPT_AB_CUSTOM_COOLDOWN_TEXT, WT.L.OPT_DESC_AB_CUSTOM_COOLDOWN_TEXT, "ActionBars", "CustomCooldownText", function() self:UpdateAllBars() end)
    panel:CreateDropdown(builder, WT.L.OPT_AB_CD_FONT, WT.L.OPT_DESC_FONT, "ActionBars", "CooldownFont", fontOptions, function() self:UpdateAllBars() end, cdtInit)
    panel:CreateSlider(builder, WT.L.OPT_AB_CD_SIZE, WT.L.OPT_DESC_FONT_SIZE, "ActionBars", "CooldownFontSize", 10, 36, 1, function() self:UpdateAllBars() end, cdtInit)
    panel:CreateSlider(builder, WT.L.OPT_AB_CD_MIN_DURATION, WT.L.OPT_DESC_AB_CD_MIN_DURATION, "ActionBars", "CooldownMinDuration", 0, 5, 0.1, function() self:UpdateAllBars() end, cdtInit)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "ActionBars", "CooldownFontOutline", function() self:UpdateAllBars() end, cdtInit)
    panel:CreateColorPicker(builder, WT.L.OPT_AB_CD_COLOR, WT.L.OPT_DESC_COLOR_VALUE, "ActionBars", "CooldownTextColor", false, cdtInit, function() self:UpdateAllBars() end)

    local cdInit = panel:CreateCheckbox(builder, WT.L.OPT_AB_CUSTOM_COOLDOWN, WT.L.OPT_DESC_AB_CUSTOM_COOLDOWN, "ActionBars", "CustomCooldown", function() self:UpdateAllBars(); PromptReload() end)
    panel:CreateColorPicker(builder, WT.L.OPT_AB_COOLDOWN_SWIPE, WT.L.OPT_DESC_AB_COOLDOWN_SWIPE, "ActionBars", "CooldownSwipeColor", true, cdInit, function() self:UpdateAllBars() end)
    panel:CreateCheckbox(builder, WT.L.OPT_AB_COOLDOWN_EDGE, WT.L.OPT_DESC_AB_COOLDOWN_EDGE, "ActionBars", "CooldownEdge", function() self:UpdateAllBars() end, cdInit)
    panel:CreateCheckbox(builder, WT.L.OPT_AB_HIDE_COOLDOWN_NUMBERS, WT.L.OPT_DESC_AB_HIDE_COOLDOWN_NUMBERS, "ActionBars", "HideCooldownNumbers", function() self:UpdateAllBars() end)
end