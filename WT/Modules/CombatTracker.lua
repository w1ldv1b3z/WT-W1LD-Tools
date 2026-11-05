local _, WT = ...

WT.Modules.CombatTracker = {}
local Module = WT.Modules.CombatTracker

-- Localize global functions (Upvaluing)
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local string_match = string.match
local math_floor = math.floor

local ctFrame
local inCombat = false
local combatStartTime = 0
local inEncounter = false
local encounterStartTime = 0
local cachedCTLabels = {}
local lastCombatDuration = 0

local isPreviewMode = false
local previewStartTime = 0

local fnIsItemInRange = (C_Item and C_Item.IsItemInRange) or _G["IsItem".."InRange"]
local fnGetItemCount = (C_Item and C_Item.GetItemCount) or _G["GetItem".."Count"]
local hasItemInRangeFunc = type(fnIsItemInRange) == "function"

local SafeNum = WT.Utils.Safety.SafeNum

-- ============================================================================
-- RANGE CHECKING DATABASE
-- ============================================================================
-- We use items instead of spells for range checking because IsItemInRange 
-- is 100% taint-free. Checking spells in combat can lead to "Action Blocked" UI errors.
-- 
-- Rules for adding new items:
-- 1. The item must have a fixed, known maximum range.
-- 2. The item must be usable on the respective target type (Enemy vs. Friend).
-- 3. The lists MUST remain sorted by 'range' in ascending order!
local ranges = {
    { range = 5,  item = 37727 }, -- Ruby Acorn
    { range = 8,  item = 34368 }, -- Attuned Crystal Cores
    { range = 10, interact = 3 }, -- Duel (9.9)
    { range = 11, interact = 2 }, -- Trade (11.11)
    { range = 15, item = 33069 }, -- Starkenet
    { range = 20, item = 10645 }, -- Gnomish Death Ray
    { range = 25, item = 24268 }, -- Netherweave Net
    { range = 28, interact = 4 }, -- Follow (28)
    { range = 30, item = 835   }, -- Large Rope Net
    { range = 35, item = 24269 }, -- Heavy Netherweave Net
    { range = 40, item = 28767 }, -- The Decapitator
    { range = 45, item = 32698 }, -- Wrangling Rope
}

local friendRanges = {
    { range = 5,  item = 37727 }, -- Ruby Acorn
    { range = 8,  item = 34368 }, -- Attuned Crystal Cores
    { range = 10, interact = 3 },
    { range = 11, interact = 2 },
    { range = 15, item = 1251  }, -- Linen Bandage
    { range = 20, item = 21519 }, -- Mistletoe
    { range = 25, item = 31463 }, -- Zeth'gor Must Burn!
    { range = 28, interact = 4 },
    { range = 30, item = 1180  }, -- Scroll of Stamina
    { range = 35, item = 18904 }, -- Zorbin's Water Resistant Hat
    { range = 40, item = 34471 }, -- Vial of the Sunwell
    { range = 45, item = 32698 }, -- Wrangling Rope
}

local playerHasItem = {}
local function UpdateItemCache()
    if not fnGetItemCount then return end
    for _, data in ipairs(ranges) do
        if data.item then
            local ok, count = pcall(fnGetItemCount, data.item)
            playerHasItem[data.item] = (ok and SafeNum(count) > 0)
        end
    end
    for _, data in ipairs(friendRanges) do
        if data.item then
            local ok, count = pcall(fnGetItemCount, data.item)
            playerHasItem[data.item] = (ok and SafeNum(count) > 0)
        end
    end
end

local rangeStrCache = {}
local function GetRangeString(minR, maxR, maxLimit)
    if maxR then
        if maxR <= 5 then return "0 - 5", maxR end
        local key = minR .. "_" .. maxR
        if not rangeStrCache[key] then
            if minR > 0 then rangeStrCache[key] = minR .. " - " .. maxR
            else rangeStrCache[key] = "0 - " .. maxR end
        end
        return rangeStrCache[key], maxR
    else
        local key = "MAX_" .. maxLimit
        if not rangeStrCache[key] then rangeStrCache[key] = "> " .. maxLimit end
        return rangeStrCache[key], maxLimit + 5
    end
end

local function GetTargetRange()
    if isPreviewMode then
        return "15 - 20", 15, 20, 20
    end
    
    -- PERFORMANCE: "target" is a literal string, so we can completely bypass pcall to save CPU overhead
    if not UnitExists("target") then return nil end
    
    local minR, maxR = 0, nil
    local isEnemy = UnitCanAttack("player", "target")
    local isDead = UnitIsDead("target")
    local rangeTable = isEnemy and ranges or friendRanges
    local maxLimit = cachedCTLabels.maxRange or 45
    
    local checksPerformed = 0
    local inCombat = InCombatLockdown()
    
    for _, data in ipairs(rangeTable) do
        if data.range > maxLimit then break end
        local inRange = nil
        if data.interact then
            if not inCombat and not isDead then
                inRange = CheckInteractDistance("target", data.interact)
            end
        elseif data.item then
            if not inCombat or playerHasItem[data.item] then
                        if hasItemInRangeFunc then
                    local okR, resR = pcall(fnIsItemInRange, data.item, "target")
                    if okR and type(resR) == "boolean" then inRange = resR end
                end
            end
        end
        
        if inRange ~= nil then
            checksPerformed = checksPerformed + 1
            if inRange then
                maxR = data.range
                break
            else
                minR = data.range
            end
        end
    end
    
    if checksPerformed == 0 and inCombat then
        return WT.L.CT_INFIGHT, nil, nil, nil
    end
    
    if maxR and minR >= maxR then minR = 0 end
    
    local str, distVal = GetRangeString(minR, maxR, maxLimit)
    return str, minR, maxR, distVal
end

local function UpdateCTVisibility()
    if not ctFrame or not WT.DB.Modules.CombatTracker then return end
    
    if isPreviewMode then
        ctFrame:Show()
        return
    end
    
    local hasTarget = WT.DB.CombatTracker.ShowRange and (UnitExists("target") or WT.DB.CombatTracker.AlwaysShowRange)
    local isTiming = WT.DB.CombatTracker.ShowCombatTime and (inCombat or inEncounter or WT.DB.CombatTracker.AlwaysShowTimer or (WT.DB.CombatTracker.KeepLastTime and lastCombatDuration > 0))
    
    if (hasTarget or isTiming) and not (WT.DB.CombatTracker.HideOutOfCombat and not inCombat and not inEncounter) then
        ctFrame:Show()
    else
        local mod = WT.DB.CombatTracker.MoveModifier or "ALT"
        local canMove = false
        if mod == "SHIFT" then canMove = IsShiftKeyDown()
        elseif mod == "CTRL" then canMove = IsControlKeyDown()
        elseif mod == "ALT" then canMove = IsAltKeyDown() end
        
        if WT.DB.CombatTracker.Movable and canMove then ctFrame:Show() else ctFrame:Hide() end
    end
end

local lastTimeSec = -1
local lastTimeStr = ""
local function FormatTime(seconds)
    if seconds ~= seconds or seconds == math.huge or seconds == -math.huge then seconds = 0 end
    
    if WT.DB.CombatTracker.ShowMilliseconds then
        local m = math_floor(seconds / 60)
        local s = math_floor(seconds % 60)
        local ms = math_floor((seconds - math_floor(seconds)) * 100)
        return string.format("%02d:%02d.%02d", m, s, ms)
    else
        local sec = math_floor(seconds)
        if sec ~= lastTimeSec then
            lastTimeSec = sec
            lastTimeStr = string.format("%02d:%02d", math_floor(sec / 60), sec % 60)
        end
        return lastTimeStr
    end
end
local rColCache = {}
local rangePartCache = {}
local lastTimeStrCache = ""
local lastTimePartCache = ""

local function UpdateCTText()
    if not ctFrame or not ctFrame:IsVisible() then return end
    
    local timePart, rangePart
    
    local diff = 0
    if isPreviewMode then
        diff = (GetTime() - previewStartTime) + 84 -- start at 01:24
    elseif inCombat or inEncounter then
        local startTime = inEncounter and encounterStartTime or combatStartTime
        diff = math.max(0, GetTime() - startTime)
        lastCombatDuration = diff
    else
        diff = (WT.DB.CombatTracker.KeepLastTime and lastCombatDuration) or 0
    end
    if diff ~= diff or diff == math.huge or diff == -math.huge then diff = 0 end
    
    local showTime = WT.DB.CombatTracker.ShowCombatTime and (isPreviewMode or inCombat or inEncounter or WT.DB.CombatTracker.AlwaysShowTimer or (WT.DB.CombatTracker.KeepLastTime and lastCombatDuration > 0))
    if showTime then
        local timeStr = FormatTime(diff)
        if WT.DB.CombatTracker.ShowMilliseconds then
            timePart = (cachedCTLabels.timeLabel == "") and string.format("|c%s%s|r", cachedCTLabels.vc, timeStr) or string.format("|c%s%s|r |c%s%s|r", cachedCTLabels.tc, cachedCTLabels.timeLabel, cachedCTLabels.vc, timeStr)
        else
            if lastTimeStrCache ~= timeStr then
                lastTimeStrCache = timeStr
                lastTimePartCache = (cachedCTLabels.timeLabel == "") and string.format("|c%s%s|r", cachedCTLabels.vc, timeStr) or string.format("|c%s%s|r |c%s%s|r", cachedCTLabels.tc, cachedCTLabels.timeLabel, cachedCTLabels.vc, timeStr)
            end
            timePart = lastTimePartCache
        end
    end
    
    local showRange = WT.DB.CombatTracker.ShowRange and (isPreviewMode or UnitExists("target") or WT.DB.CombatTracker.AlwaysShowRange)
    if showRange then
        
        if isPreviewMode or UnitExists("target") then
            local rangeStr, minR, maxR, distVal = GetTargetRange()
            if rangeStr then
                local rCol = cachedCTLabels.vc
                if WT.DB.CombatTracker.ColorizeRange then
                    if distVal then
                        local maxLimit = cachedCTLabels.maxRange or 45
                        if not rColCache[distVal] then
                            local divisor = maxLimit - 5
                            local pct = divisor > 0 and ((distVal - 5) / divisor) or 1
                        if pct ~= pct or pct == math.huge or pct == -math.huge then pct = 1 end
                            pct = math.max(0, math.min(1, pct))
                            local r, g, b
                            if pct < 0.5 then r = pct * 2; g = 1; b = 0
                            else r = 1; g = 1 - ((pct - 0.5) * 2); b = 0 end
                            if distVal >= maxLimit then r = 1; g = 0; b = 0 end
                            rColCache[distVal] = string.format("ff%02x%02x%02x", r*255, g*255, b*255)
                        end
                        rCol = rColCache[distVal]
                    elseif rangeStr == (WT.L.CT_INFIGHT) then
                        rCol = "ffff0000"
                    end
                end
                local unitSuffix = cachedCTLabels.unitStr == "NONE" and "" or (" " .. cachedCTLabels.unitStr)
                if rangeStr == (WT.L.CT_INFIGHT) then unitSuffix = "" end
                
                local rKey = rangeStr .. "_" .. tostring(rCol) .. "_" .. unitSuffix
                if not rangePartCache[rKey] then
                    if cachedCTLabels.rangeLabel == "" then
                        rangePartCache[rKey] = string.format("|c%s%s%s|r", rCol, rangeStr, unitSuffix)
                    else
                        rangePartCache[rKey] = string.format("|c%s%s|r |c%s%s%s|r", cachedCTLabels.tc, cachedCTLabels.rangeLabel, rCol, rangeStr, unitSuffix)
                    end
                end
                rangePart = rangePartCache[rKey]
            end
        else
            if not rangePartCache["_EMPTY_"] then
                rangePartCache["_EMPTY_"] = (cachedCTLabels.rangeLabel == "") and string.format("|c%s-|r", cachedCTLabels.vc) or string.format("|c%s%s|r |c%s-|r", cachedCTLabels.tc, cachedCTLabels.rangeLabel, cachedCTLabels.vc)
            end
            rangePart = rangePartCache["_EMPTY_"]
        end
    end
    
    local finalStr = ""
    
    local order = WT.DB.CombatTracker.DisplayOrder or "RANGE_TIME"
    if order == "TIME_RANGE" then
        if timePart and rangePart then finalStr = timePart .. cachedCTLabels.sepFormat .. rangePart elseif timePart then finalStr = timePart elseif rangePart then finalStr = rangePart end
    else
        if rangePart and timePart then finalStr = rangePart .. cachedCTLabels.sepFormat .. timePart elseif rangePart then finalStr = rangePart elseif timePart then finalStr = timePart end
    end

    if finalStr == "" and WT.DB.CombatTracker.Movable then finalStr = string.format("|c%s[Combat Tracker]|r", cachedCTLabels.tc) end
    
    if ctFrame.wtLastText ~= finalStr then
        ctFrame.text:SetText(finalStr)
        ctFrame.wtLastText = finalStr
        
        -- Fast-Path: Prevent constant background resizing (which triggers expensive layout passes)
        local newWidth = ctFrame.text:GetStringWidth() + 20
        if not ctFrame.wtLastWidth or math.abs(ctFrame.wtLastWidth - newWidth) > 2 then
            ctFrame:SetWidth(newWidth)
            ctFrame.wtLastWidth = newWidth
        end
    end
end

function Module:SetupTracker()
    if not WT.DB.Modules.CombatTracker then 
        if ctFrame then ctFrame:Hide() end; return 
    end
    
    local tLbl = WT.DB.CombatTracker.TimeLabel
    if tLbl and string_match(tLbl, "^%s+$") then
        cachedCTLabels.timeLabel = ""
    else
        cachedCTLabels.timeLabel = (tLbl and tLbl ~= "") and tLbl or (WT.L.CT_TIME)
        if string_match(cachedCTLabels.timeLabel, "%S") and not string_match(cachedCTLabels.timeLabel, ":%s*$") then cachedCTLabels.timeLabel = cachedCTLabels.timeLabel .. ":" end
    end
    
    local rLbl = WT.DB.CombatTracker.RangeLabel
    if rLbl and string_match(rLbl, "^%s+$") then
        cachedCTLabels.rangeLabel = ""
    else
        cachedCTLabels.rangeLabel = (rLbl and rLbl ~= "") and rLbl or (WT.L.CT_RANGE)
        if string_match(cachedCTLabels.rangeLabel, "%S") and not string_match(cachedCTLabels.rangeLabel, ":%s*$") then cachedCTLabels.rangeLabel = cachedCTLabels.rangeLabel .. ":" end
    end
    
    cachedCTLabels.unitStr = WT.DB.CombatTracker.RangeUnit or "m"
    cachedCTLabels.tc = WT.Colors:GetHex(WT.DB.CombatTracker.TextColor, 1, 1, 1)
    cachedCTLabels.vc = WT.Colors:GetHex(WT.DB.CombatTracker.ValueColor, 1, 0.82, 0)
    
    local mRange = SafeNum(WT.DB.CombatTracker.MaxRange)
    if mRange ~= mRange or mRange == math.huge or mRange == -math.huge then mRange = 45 end
    cachedCTLabels.maxRange = (mRange and mRange > 5) and mRange or 45
    
    wipe(rColCache)
    wipe(rangePartCache)
    lastTimeStrCache = ""
    
    local sc = WT.Colors:GetHex(WT.DB.CombatTracker.SeparatorColor, 0.5, 0.5, 0.5)
    cachedCTLabels.sepFormat = "|c" .. sc .. (WT.DB.CombatTracker.Separator or " | ") .. "|r"

    if not ctFrame then
        ctFrame = CreateFrame("Frame", "WTCombatTracker", _G["WT_UIContainer"])
        ctFrame:SetFrameStrata(WT.DB.CombatTracker.Strata or "MEDIUM")
        
        ctFrame.ignoreInLayout = true
        ctFrame.ignoreFramePositionManager = true
        if ctFrame.SetIsFramePositionManaged then pcall(function() ctFrame:SetIsFramePositionManaged(false) end) end
        
        ctFrame.bg = ctFrame:CreateTexture(nil, "BACKGROUND")
        ctFrame.bg:SetPoint("TOPLEFT", 1, -1)
        ctFrame.bg:SetPoint("BOTTOMRIGHT", -1, 1)
        ctFrame.bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        
        ctFrame.top = ctFrame:CreateTexture(nil, "BORDER")
        ctFrame.top:SetPoint("TOPLEFT", 0, 0); ctFrame.top:SetPoint("TOPRIGHT", 0, 0); ctFrame.top:SetHeight(1)
        ctFrame.top:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        ctFrame.bot = ctFrame:CreateTexture(nil, "BORDER")
        ctFrame.bot:SetPoint("BOTTOMLEFT", 0, 0); ctFrame.bot:SetPoint("BOTTOMRIGHT", 0, 0); ctFrame.bot:SetHeight(1)
        ctFrame.bot:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        ctFrame.left = ctFrame:CreateTexture(nil, "BORDER")
        ctFrame.left:SetPoint("TOPLEFT", 0, 0); ctFrame.left:SetPoint("BOTTOMLEFT", 0, 0); ctFrame.left:SetWidth(1)
        ctFrame.left:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        ctFrame.right = ctFrame:CreateTexture(nil, "BORDER")
        ctFrame.right:SetPoint("TOPRIGHT", 0, 0); ctFrame.right:SetPoint("BOTTOMRIGHT", 0, 0); ctFrame.right:SetWidth(1)
        ctFrame.right:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        
        ctFrame.text = ctFrame:CreateFontString(nil, "OVERLAY")
        ctFrame.text:SetPoint("LEFT", ctFrame, "LEFT", 10, 0)
        ctFrame.text:SetJustifyH("LEFT")
        
        ctFrame:RegisterForDrag("LeftButton")
        ctFrame:SetScript("OnDragStart", function(self)
            local mod = WT.DB.CombatTracker.MoveModifier or "ALT"
            local canMove = (mod == "SHIFT" and IsShiftKeyDown()) or (mod == "CTRL" and IsControlKeyDown()) or (mod == "ALT" and IsAltKeyDown())
            if WT.DB.CombatTracker.Movable and canMove then self:StartMoving() end
        end)
        
        ctFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            
            local left = self:GetLeft()
            local top = self:GetTop()
            if left and top then
                self:ClearAllPoints()
                self:SetPoint("TOPLEFT", _G["WT_UIContainer"], "BOTTOMLEFT", left, top)
            end
            
            local p, _, rP, x, y = self:GetPoint()
            if not WT.DB.Internal.Positions then WT.DB.Internal.Positions = {} end
            WT.DB.Internal.Positions["WTCombatTracker"] = { point = p, relativeTo = "UIParent", relativePoint = rP, xOfs = x, yOfs = y }
        end)
        
        WT.Core.Events:Register("PLAYER_REGEN_DISABLED", function() inCombat = true; combatStartTime = GetTime(); UpdateCTVisibility() end)
        WT.Core.Events:Register("PLAYER_REGEN_ENABLED", function() inCombat = false; UpdateCTVisibility() end)
        WT.Core.Events:Register("ENCOUNTER_START", function() inEncounter = true; encounterStartTime = GetTime(); UpdateCTVisibility() end)
        WT.Core.Events:Register("ENCOUNTER_END", function() inEncounter = false; UpdateCTVisibility() end)
        WT.Core.Events:Register("PLAYER_TARGET_CHANGED", function() UpdateCTVisibility() end)
        WT.Core.Events:Register("MODIFIER_STATE_CHANGED", function() UpdateCTVisibility() end)
    end
    
    WT.Core.Events:UnregisterOnUpdate(UpdateCTText)
    local updateRate = WT.DB.CombatTracker.ShowMilliseconds and 0.02 or 0.04
    WT.Core.Events:RegisterOnUpdate(UpdateCTText, updateRate, "CombatTracker")
    
    local fontKey = WT.DB.CombatTracker.Font or "Friz Quadrata TT"
    local fontPath = (WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", fontKey)) or "Fonts\\FRIZQT__.TTF"
    local size = SafeNum(WT.DB.CombatTracker.FontSize) or 0
    if size == 0 then size = 10 end
    local outline = (WT.DB.CombatTracker.FontOutline == "NONE") and "" or (WT.DB.CombatTracker.FontOutline or "OUTLINE")
    ctFrame.text:SetFont(fontPath, size, outline)
    ctFrame:SetHeight(size + 14)
    
    ctFrame:SetFrameStrata(WT.DB.CombatTracker.Strata or "MEDIUM")
    
    if WT.DB.CombatTracker.Background then
        local bg = WT.DB.CombatTracker.BgColor or {r=WT.Colors.STD_BG_R, g=WT.Colors.STD_BG_G, b=WT.Colors.STD_BG_B, a=WT.Colors.STD_BG_A}
        if type(bg) == "string" then bg = {r=WT.Colors.STD_BG_R, g=WT.Colors.STD_BG_G, b=WT.Colors.STD_BG_B, a=WT.Colors.STD_BG_A} end
        ctFrame.bg:SetVertexColor(bg.r or WT.Colors.STD_BG_R, bg.g or WT.Colors.STD_BG_G, bg.b or WT.Colors.STD_BG_B, bg.a or WT.Colors.STD_BG_A)
    else
        ctFrame.bg:SetVertexColor(0, 0, 0, 0)
    end
    
    if WT.DB.CombatTracker.Border then
        local bc = WT.DB.CombatTracker.BorderColor or {r=1, g=1, b=1, a=1}
        if type(bc) == "string" then bc = {r=1, g=1, b=1, a=1} end
        ctFrame.top:SetVertexColor(bc.r or 1, bc.g or 1, bc.b or 1, bc.a or 1)
        ctFrame.bot:SetVertexColor(bc.r or 1, bc.g or 1, bc.b or 1, bc.a or 1)
        ctFrame.left:SetVertexColor(bc.r or 1, bc.g or 1, bc.b or 1, bc.a or 1)
        ctFrame.right:SetVertexColor(bc.r or 1, bc.g or 1, bc.b or 1, bc.a or 1)
    else
        ctFrame.top:SetVertexColor(0, 0, 0, 0)
        ctFrame.bot:SetVertexColor(0, 0, 0, 0)
        ctFrame.left:SetVertexColor(0, 0, 0, 0)
        ctFrame.right:SetVertexColor(0, 0, 0, 0)
    end
    
    ctFrame:SetMovable(WT.DB.CombatTracker.Movable)
    ctFrame:EnableMouse(WT.DB.CombatTracker.Movable)
    
    if WT.DB.Internal.Positions and WT.DB.Internal.Positions["WTCombatTracker"] then
        local pos = WT.DB.Internal.Positions["WTCombatTracker"]
        ctFrame:ClearAllPoints(); ctFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        ctFrame:ClearAllPoints(); ctFrame:SetPoint("LEFT", UIParent, "CENTER", 0, -150)
    end
    
    UpdateCTVisibility(); UpdateCTText()
end

function Module:PreviewTracker()
    if isPreviewMode then return end
    isPreviewMode = true
    previewStartTime = GetTime()
    UpdateCTVisibility()
    UpdateCTText()
    C_Timer.After(10, function()
        isPreviewMode = false
        UpdateCTVisibility()
        UpdateCTText()
    end)
end

function Module:Initialize()
    if not WT.DB.Modules.CombatTracker then return end
    
    -- PRE-CACHE: The Item API often returns 'nil' if the items haven't been loaded in the client yet.
    -- We force a one-time fetch here so the real-time distance runs buttery smooth immediately!
    local function PreCacheItem(itemID)
        if type(itemID) ~= "number" then return end
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID)
        elseif C_Item and C_Item.GetItemInfo then C_Item.GetItemInfo(itemID)
        elseif _G["GetItem".."Info"] then _G["GetItem".."Info"](itemID) end
    end
    for _, data in ipairs(ranges) do PreCacheItem(data.item) end
    for _, data in ipairs(friendRanges) do PreCacheItem(data.item) end
    
    UpdateItemCache()
    WT.Core.Events:Register("BAG_UPDATE_DELAYED", UpdateItemCache)
    
    self:SetupTracker()
end

WT.Core.Events:Register("PLAYER_LOGIN", function() Module:Initialize() end)

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

    panel:CreateTitle(builder, WT.L.CATEGORY_COMBATTRACKER)
    AddDescription(WT.L.OPT_DESC_MODULE_COMBATTRACKER)
    
    panel:CreateTitle(builder, WT.L.GROUP_CT_BEHAVIOR)
    AddDescription(WT.L.OPT_DESC_GROUP_CT_BEHAVIOR)
    
    local orderOptions = { { value = "RANGE_TIME", label = WT.L.OPT_CT_ORDER_RT }, { value = "TIME_RANGE", label = WT.L.OPT_CT_ORDER_TR } }
    panel:CreateDropdown(builder, WT.L.OPT_CT_ORDER, WT.L.OPT_DESC_CT_ORDER, "CombatTracker", "DisplayOrder", orderOptions, function() self:SetupTracker() end)

    local rangeInit = panel:CreateCheckbox(builder, WT.L.OPT_CT_SHOW_RANGE, WT.L.OPT_DESC_CT_SHOW_RANGE, "CombatTracker", "ShowRange", function() self:SetupTracker() end)
    panel:CreateCheckbox(builder, WT.L.OPT_CT_ALWAYS_RANGE, WT.L.OPT_DESC_CT_ALWAYS_RANGE, "CombatTracker", "AlwaysShowRange", function() self:SetupTracker() end, rangeInit)
    panel:CreateCheckbox(builder, WT.L.OPT_CT_COLORIZE_RANGE, WT.L.OPT_DESC_CT_COLORIZE_RANGE, "CombatTracker", "ColorizeRange", function() self:SetupTracker() end, rangeInit)
    local unitOptions = { { value = "m", label = "Meter (m)" }, { value = "yd", label = "Yards (yd)" }, { value = "NONE", label = WT.L.OPT_CT_RANGE_NONE } }
    panel:CreateDropdown(builder, WT.L.OPT_CT_RANGE_UNIT, WT.L.OPT_DESC_CT_RANGE_UNIT, "CombatTracker", "RangeUnit", unitOptions, function() self:SetupTracker() end, rangeInit)
    panel:CreateSlider(builder, WT.L.OPT_CT_MAX_RANGE, WT.L.OPT_DESC_CT_MAX_RANGE, "CombatTracker", "MaxRange", 45, 100, 5, function() self:SetupTracker() end, rangeInit)
    panel:CreateEditBox(builder, WT.L.OPT_CT_RANGE_LABEL, WT.L.OPT_DESC_CT_RANGE_LABEL, "CombatTracker", "RangeLabel", rangeInit, function() self:SetupTracker() end)
    
    local timeInit = panel:CreateCheckbox(builder, WT.L.OPT_CT_SHOW_TIME, WT.L.OPT_DESC_CT_SHOW_TIME, "CombatTracker", "ShowCombatTime", function() self:SetupTracker() end)
    panel:CreateCheckbox(builder, WT.L.OPT_CT_ALWAYS_TIME, WT.L.OPT_DESC_CT_ALWAYS_TIME, "CombatTracker", "AlwaysShowTimer", function() self:SetupTracker() end, timeInit)
    panel:CreateCheckbox(builder, WT.L.OPT_CT_KEEP_LAST_TIME, WT.L.OPT_DESC_CT_KEEP_LAST_TIME, "CombatTracker", "KeepLastTime", function() self:SetupTracker() end, timeInit)
    panel:CreateCheckbox(builder, WT.L.OPT_CT_SHOW_MS, WT.L.OPT_DESC_CT_SHOW_MS, "CombatTracker", "ShowMilliseconds", function() self:SetupTracker() end, timeInit)
    panel:CreateEditBox(builder, WT.L.OPT_CT_TIME_LABEL, WT.L.OPT_DESC_CT_TIME_LABEL, "CombatTracker", "TimeLabel", timeInit, function() self:SetupTracker() end)
    panel:CreateCheckbox(builder, WT.L.OPT_CT_HIDE_OOC, WT.L.OPT_DESC_CT_HIDE_OOC, "CombatTracker", "HideOutOfCombat", function() self:SetupTracker() end)
    
    panel:CreateTitle(builder, WT.L.GROUP_CT_APPEARANCE)
    AddDescription(WT.L.OPT_DESC_GROUP_CT_APPEARANCE)
    
    panel:CreateButton(builder, WT.L.OPT_CT_TEST, WT.L.BTN_TEST, WT.L.OPT_DESC_CT_TEST, function()
        self:PreviewTracker()
    end)
    builder:AddSpace(10)
    
    local moveInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_MOVABLE, WT.L.OPT_DESC_SW_MOVABLE, "CombatTracker", "Movable", function() self:SetupTracker() end)
    local modOptions = { { value = "ALT", label = "ALT" }, { value = "CTRL", label = "CTRL" }, { value = "SHIFT", label = "SHIFT" } }
    panel:CreateDropdown(builder, WT.L.OPT_SW_MOVE_MODIFIER, WT.L.OPT_DESC_SW_MOVE_MODIFIER, "CombatTracker", "MoveModifier", modOptions, nil, moveInit)
    panel:CreateStrataDropdown(builder, WT.L.OPT_STRATA, WT.L.OPT_DESC_STRATA, "CombatTracker", "Strata", function() self:SetupTracker() end)
    
    if WT.Utils and WT.Utils.SharedMedia then
        panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "CombatTracker", "Font", WT.Utils.SharedMedia:GetOptions("font"), function() self:SetupTracker() end)
    end
    panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "CombatTracker", "FontSize", 8, 36, 1, function() self:SetupTracker() end)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "CombatTracker", "FontOutline", function() self:SetupTracker() end)
    
    local bgInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_BACKGROUND, WT.L.OPT_DESC_SW_BACKGROUND, "CombatTracker", "Background", function() self:SetupTracker() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BG, WT.L.OPT_DESC_COLOR_BG, "CombatTracker", "BgColor", true, bgInit, function() self:SetupTracker() end)
    local borderInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_BORDER, WT.L.OPT_DESC_SW_BORDER, "CombatTracker", "Border", function() self:SetupTracker() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BORDER, WT.L.OPT_DESC_COLOR_BORDER, "CombatTracker", "BorderColor", true, borderInit, function() self:SetupTracker() end)
    
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_TEXT, WT.L.OPT_DESC_COLOR_TEXT, "CombatTracker", "TextColor", true, nil, function() self:SetupTracker() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "CombatTracker", "ValueColor", true, nil, function() self:SetupTracker() end)
    
    local sepInit = panel:CreateEditBox(builder, WT.L.OPT_SEPARATOR, WT.L.OPT_DESC_SEPARATOR, "CombatTracker", "Separator", nil, function() self:SetupTracker() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_SEP, WT.L.OPT_DESC_COLOR_SEP, "CombatTracker", "SeparatorColor", true, sepInit, function() self:SetupTracker() end)
end