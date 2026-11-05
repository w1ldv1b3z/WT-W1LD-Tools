local _, WT = ...

-- ============================================================================
-- COMBAT TRACKER
-- ============================================================================
-- Small on-screen display for the distance to the target and the combat / encounter duration.
-- Opt-in: nothing is created, registered or requested from the server until "Show Range" or
-- "Show Combat Time" is enabled. Turning both off hides the display and removes all its events.

local Module = WT:NewModule("CombatTracker")

local POSITION_KEY = "WTCombatTracker"

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

local SafeNum = WT.Utils.Safety.SafeNum

-- ============================================================================
-- RANGE CHECKING
-- ============================================================================
-- Distances come from LibRangeCheck-3.0 (Libs/), the community standard for this: it combines
-- interact distances, items and the player's own spells (which also work in combat) and keeps
-- up with Blizzard's API changes. It only provides ranges in steps, e.g. "between 20 and 25 yards".
local RangeCheck = LibStub and LibStub("LibRangeCheck-3.0", true)

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
    if not RangeCheck or not UnitExists("target") then return nil end

    local maxLimit = cachedCTLabels.maxRange or 45
    local rawMin, rawMax = RangeCheck:GetRange("target")
    local minR, maxR = SafeNum(rawMin), SafeNum(rawMax)
    if not minR then
        -- No estimate possible (e.g. no suitable spell or item in combat)
        if InCombatLockdown() then return WT.L.CT_INFIGHT, nil, nil, nil end
        return nil
    end

    -- Beyond the configured maximum: show "> max"
    if minR >= maxLimit or (maxR and maxR > maxLimit) then maxR = nil end
    local str, distVal = GetRangeString(minR, maxR, maxLimit)
    return str, minR, maxR, distVal
end

local function IsRangeShown()
    local db = WT.DB.CombatTracker
    return db.ShowRange and (isPreviewMode or UnitExists("target") or db.AlwaysShowRange)
end

-- "Hide out of combat" only applies to the combat time, never to the range display
local function IsTimeShown()
    local db = WT.DB.CombatTracker
    if not db.ShowCombatTime then return false end
    if isPreviewMode or inCombat or inEncounter then return true end
    if db.HideOutOfCombat then return false end
    return db.AlwaysShowTimer or (db.KeepLastTime and lastCombatDuration > 0)
end

local function UpdateCTVisibility()
    if not ctFrame then return end

    if isPreviewMode or IsRangeShown() or IsTimeShown() then
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
    
    local diff
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
    
    if IsTimeShown() then
        local timeStr = FormatTime(diff)
        -- Optional highlight once a boss fight runs longer than the chosen time (e.g. enrage timer)
        local db = WT.DB.CombatTracker
        local valueColor = cachedCTLabels.vc
        if db.BossTimeWarn and (inEncounter or isPreviewMode) and diff >= (db.BossTimeWarnSeconds or 300) then
            valueColor = cachedCTLabels.warnColor
        end
        local cacheKey = timeStr .. valueColor
        if db.ShowMilliseconds or lastTimeStrCache ~= cacheKey then
            lastTimeStrCache = cacheKey
            lastTimePartCache = (cachedCTLabels.timeLabel == "") and string.format("|c%s%s|r", valueColor, timeStr) or string.format("|c%s%s|r |c%s%s|r", cachedCTLabels.tc, cachedCTLabels.timeLabel, valueColor, timeStr)
        end
        timePart = lastTimePartCache
    end
    
    if IsRangeShown() then
        
        if isPreviewMode or UnitExists("target") then
            local rangeStr, _, _, distVal = GetTargetRange()
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

    -- Placeholder so the empty display can still be grabbed and moved
    if finalStr == "" and WT.DB.CombatTracker.Movable then finalStr = string.format("|c%s[%s]|r", cachedCTLabels.tc, WT.L.CATEGORY_COMBATTRACKER) end
    
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

local function BuildLabels()
    local db = WT.DB.CombatTracker

    -- A label consisting only of spaces hides the label; an empty one uses the default text
    local function ResolveLabel(value, default)
        if value and string_match(value, "^%s+$") then return "" end
        local label = (value and value ~= "") and value or default
        if string_match(label, "%S") and not string_match(label, ":%s*$") then label = label .. ":" end
        return label
    end
    cachedCTLabels.timeLabel = ResolveLabel(db.TimeLabel, WT.L.CT_TIME)
    cachedCTLabels.rangeLabel = ResolveLabel(db.RangeLabel, WT.L.CT_RANGE)

    cachedCTLabels.unitStr = db.RangeUnit or "m"
    cachedCTLabels.tc = WT.Colors:GetHex(db.TextColor, 1, 1, 1)
    cachedCTLabels.vc = WT.Colors:GetHex(db.ValueColor, 1, 0.82, 0)
    cachedCTLabels.warnColor = WT.Colors:GetHex(db.BossTimeWarnColor, 1, 0.2, 0.2)
    cachedCTLabels.sepFormat = "|c" .. WT.Colors:GetHex(db.SeparatorColor, 0.5, 0.5, 0.5) .. (db.Separator or " | ") .. "|r"

    local maxRange = SafeNum(db.MaxRange)
    cachedCTLabels.maxRange = (maxRange and maxRange > 5 and maxRange < math.huge) and maxRange or 45

    wipe(rColCache)
    wipe(rangePartCache)
    lastTimeStrCache = ""
end

local function SavePosition(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", _G["WT_UIContainer"], "BOTTOMLEFT", left, top)
    WT.DB.Internal.Positions = WT.DB.Internal.Positions or {}
    WT.DB.Internal.Positions[POSITION_KEY] = {
        point = "TOPLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", xOfs = left, yOfs = top,
    }
end

local function IsMoveModifierDown()
    local modifier = WT.DB.CombatTracker.MoveModifier or "ALT"
    return (modifier == "SHIFT" and IsShiftKeyDown()) or (modifier == "CTRL" and IsControlKeyDown())
        or (modifier == "ALT" and IsAltKeyDown())
end

local function CreateTrackerFrame()
    local frame = CreateFrame("Frame", "WTCombatTracker", _G["WT_UIContainer"])
    frame.ignoreInLayout = true
    frame.ignoreFramePositionManager = true

    local function Edge(...)
        local tex = frame:CreateTexture(nil, "BORDER")
        tex:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        for i = 1, select("#", ...), 2 do
            local point = select(i, ...)
            tex:SetPoint(point, 0, 0)
            tex:SetPoint(select(i + 1, ...), 0, 0)
        end
        return tex
    end

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetPoint("TOPLEFT", 1, -1)
    frame.bg:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    frame.top = Edge("TOPLEFT", "TOPRIGHT"); frame.top:SetHeight(1)
    frame.bot = Edge("BOTTOMLEFT", "BOTTOMRIGHT"); frame.bot:SetHeight(1)
    frame.left = Edge("TOPLEFT", "BOTTOMLEFT"); frame.left:SetWidth(1)
    frame.right = Edge("TOPRIGHT", "BOTTOMRIGHT"); frame.right:SetWidth(1)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("LEFT", frame, "LEFT", 10, 0)
    frame.text:SetJustifyH("LEFT")

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if WT.DB.CombatTracker.Movable and IsMoveModifierDown() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    return frame
end

local function ApplyStyle()
    local db = WT.DB.CombatTracker
    local container = _G["WT_UIContainer"]

    local fontPath = (WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", db.Font)) or "Fonts\\FRIZQT__.TTF"
    local size = SafeNum(db.FontSize) or 10
    if size <= 0 then size = 10 end
    local outline = (db.FontOutline == "NONE") and "" or (db.FontOutline or "OUTLINE")
    ctFrame.text:SetFont(fontPath, size, outline)
    ctFrame:SetHeight(size + 14)
    ctFrame:SetFrameStrata(db.Strata or "MEDIUM")

    if db.Background then
        local bg = type(db.BgColor) == "table" and db.BgColor or {}
        ctFrame.bg:SetVertexColor(bg.r or WT.Colors.STD_BG_R, bg.g or WT.Colors.STD_BG_G, bg.b or WT.Colors.STD_BG_B, bg.a or WT.Colors.STD_BG_A)
    else
        ctFrame.bg:SetVertexColor(0, 0, 0, 0)
    end

    local r, g, b, a = 0, 0, 0, 0
    if db.Border then
        local bc = type(db.BorderColor) == "table" and db.BorderColor or {}
        r, g, b, a = bc.r or 1, bc.g or 1, bc.b or 1, bc.a or 1
    end
    for _, edge in ipairs({ ctFrame.top, ctFrame.bot, ctFrame.left, ctFrame.right }) do
        edge:SetVertexColor(r, g, b, a)
    end

    ctFrame:SetMovable(db.Movable and true or false)
    ctFrame:EnableMouse(db.Movable and true or false)

    ctFrame:ClearAllPoints()
    local pos = WT.DB.Internal.Positions and WT.DB.Internal.Positions[POSITION_KEY]
    if pos then
        ctFrame:SetPoint(pos.point, container, pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        ctFrame:SetPoint("LEFT", container, "CENTER", 0, -150)
    end
end

-- Duration as mm:ss for chat output (independent of the display formatting and its caches)
local function FormatDuration(seconds)
    seconds = math_floor(math.max(0, seconds))
    return string.format("%02d:%02d", math_floor(seconds / 60), seconds % 60)
end

local MIN_PRINT_DURATION = 3     -- ignore tiny fights (e.g. a single critter)
local encounterEnded = false     -- a boss fight ended during the current combat

local function OnCombatEnd()
    -- Shown with /wt debug: helps to find out why a fight was (not) printed
    WT.Utils.Logger:Debug(string.format(WT.L.MSG_DEBUG_CT_COMBAT_END, GetTime() - combatStartTime,
        tostring(WT.DB.CombatTracker.PrintCombatTime), tostring(encounterEnded)))

    -- After a boss fight the boss duration is kept (as shown during the encounter)
    if not encounterEnded then
        local duration = GetTime() - combatStartTime
        lastCombatDuration = duration
        if WT.DB.CombatTracker.PrintCombatTime and duration >= MIN_PRINT_DURATION then
            WT.Utils.Logger:Print(string.format(WT.L.MSG_CT_COMBAT_TIME, FormatDuration(duration)))
        end
    end
    encounterEnded = false
end

-- Payload of ENCOUNTER_END: encounterID, encounterName, difficultyID, groupSize, success
local function OnEncounterEnd(_, _, encounterName, _, _, success)
    local duration = GetTime() - encounterStartTime
    lastCombatDuration = duration
    encounterEnded = true
    if WT.DB.CombatTracker.PrintCombatTime and duration >= MIN_PRINT_DURATION then
        local name = WT.Utils.Safety.Unsecret(encounterName) or ""
        local message = (success == 1) and WT.L.MSG_CT_ENCOUNTER_KILL or WT.L.MSG_CT_ENCOUNTER_WIPE
        WT.Utils.Logger:Print(string.format(message, name, FormatDuration(duration)))
    end
end

local eventsRegistered = false
local function RegisterTrackerEvents(module)
    if eventsRegistered then return end
    eventsRegistered = true

    -- The tracker may be enabled in the middle of a fight
    inCombat = InCombatLockdown()
    if inCombat then combatStartTime = GetTime() end

    module:RegisterEvent("PLAYER_REGEN_DISABLED", function() inCombat = true; combatStartTime = GetTime(); UpdateCTVisibility() end)
    module:RegisterEvent("PLAYER_REGEN_ENABLED", function() inCombat = false; OnCombatEnd(); UpdateCTVisibility() end)
    module:RegisterEvent("ENCOUNTER_START", function() inEncounter = true; encounterStartTime = GetTime(); UpdateCTVisibility() end)
    module:RegisterEvent("ENCOUNTER_END", function(...) inEncounter = false; OnEncounterEnd(...); UpdateCTVisibility() end)
    module:RegisterEvent("PLAYER_TARGET_CHANGED", UpdateCTVisibility)
    module:RegisterEvent("MODIFIER_STATE_CHANGED", UpdateCTVisibility)
end

--- Applies the current settings. Called on login and whenever an option changes.
function Module:Refresh()
    local db = WT.DB.CombatTracker
    local showDisplay = db.ShowRange or db.ShowCombatTime or isPreviewMode
    if not showDisplay then
        if ctFrame then ctFrame:Hide() end
        self:UnregisterOnUpdate(UpdateCTText)
    end
    if not showDisplay and not db.PrintCombatTime then
        -- Removes every event and the update ticker of this module
        WT.Core.Events:UnregisterAll(self.name)
        eventsRegistered = false
        return
    end

    -- The chat output alone only needs the combat events
    RegisterTrackerEvents(self)
    if not showDisplay then return end

    BuildLabels()
    ctFrame = ctFrame or CreateTrackerFrame()
    ApplyStyle()
    self:RegisterOnUpdate(UpdateCTText, db.ShowMilliseconds and 0.02 or 0.04)

    ctFrame.wtLastText = nil
    UpdateCTVisibility()
    UpdateCTText()
end

function Module:PreviewTracker()
    if isPreviewMode then return end
    isPreviewMode = true
    previewStartTime = GetTime()
    self:Refresh()
    C_Timer.After(10, function()
        isPreviewMode = false
        self:Refresh()
    end)
end

function Module:OnEnable()
    self:Refresh()
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

    panel:CreateTitle(builder, WT.L.CATEGORY_COMBATTRACKER)
    AddDescription(WT.L.OPT_DESC_MODULE_COMBATTRACKER)
    
    panel:CreateTitle(builder, WT.L.GROUP_CT_BEHAVIOR)
    AddDescription(WT.L.OPT_DESC_GROUP_CT_BEHAVIOR)
    
    local orderOptions = { { value = "RANGE_TIME", label = WT.L.OPT_CT_ORDER_RT }, { value = "TIME_RANGE", label = WT.L.OPT_CT_ORDER_TR } }
    panel:CreateDropdown(builder, WT.L.OPT_CT_ORDER, WT.L.OPT_DESC_CT_ORDER, "CombatTracker", "DisplayOrder", orderOptions, function() self:Refresh() end)

    local rangeInit = panel:CreateCheckbox(builder, WT.L.OPT_CT_SHOW_RANGE, WT.L.OPT_DESC_CT_SHOW_RANGE, "CombatTracker", "ShowRange", function() self:Refresh() end)
    panel:CreateCheckbox(builder, WT.L.OPT_CT_ALWAYS_RANGE, WT.L.OPT_DESC_CT_ALWAYS_RANGE, "CombatTracker", "AlwaysShowRange", function() self:Refresh() end, rangeInit)
    panel:CreateCheckbox(builder, WT.L.OPT_CT_COLORIZE_RANGE, WT.L.OPT_DESC_CT_COLORIZE_RANGE, "CombatTracker", "ColorizeRange", function() self:Refresh() end, rangeInit)
    local unitOptions = { { value = "m", label = WT.L.OPT_CT_UNIT_METER }, { value = "yd", label = WT.L.OPT_CT_UNIT_YARDS }, { value = "NONE", label = WT.L.OPT_CT_RANGE_NONE } }
    panel:CreateDropdown(builder, WT.L.OPT_CT_RANGE_UNIT, WT.L.OPT_DESC_CT_RANGE_UNIT, "CombatTracker", "RangeUnit", unitOptions, function() self:Refresh() end, rangeInit)
    panel:CreateSlider(builder, WT.L.OPT_CT_MAX_RANGE, WT.L.OPT_DESC_CT_MAX_RANGE, "CombatTracker", "MaxRange", 45, 100, 5, function() self:Refresh() end, rangeInit)
    panel:CreateEditBox(builder, WT.L.OPT_CT_RANGE_LABEL, WT.L.OPT_DESC_CT_RANGE_LABEL, "CombatTracker", "RangeLabel", rangeInit, function() self:Refresh() end)
    
    local timeInit = panel:CreateCheckbox(builder, WT.L.OPT_CT_SHOW_TIME, WT.L.OPT_DESC_CT_SHOW_TIME, "CombatTracker", "ShowCombatTime", function() self:Refresh() end)
    panel:CreateCheckbox(builder, WT.L.OPT_CT_ALWAYS_TIME, WT.L.OPT_DESC_CT_ALWAYS_TIME, "CombatTracker", "AlwaysShowTimer", function() self:Refresh() end, timeInit)
    panel:CreateCheckbox(builder, WT.L.OPT_CT_KEEP_LAST_TIME, WT.L.OPT_DESC_CT_KEEP_LAST_TIME, "CombatTracker", "KeepLastTime", function() self:Refresh() end, timeInit)
    panel:CreateCheckbox(builder, WT.L.OPT_CT_SHOW_MS, WT.L.OPT_DESC_CT_SHOW_MS, "CombatTracker", "ShowMilliseconds", function() self:Refresh() end, timeInit)
    panel:CreateEditBox(builder, WT.L.OPT_CT_TIME_LABEL, WT.L.OPT_DESC_CT_TIME_LABEL, "CombatTracker", "TimeLabel", timeInit, function() self:Refresh() end)
    panel:CreateCheckbox(builder, WT.L.OPT_CT_HIDE_OOC, WT.L.OPT_DESC_CT_HIDE_OOC, "CombatTracker", "HideOutOfCombat", function() self:Refresh() end, timeInit)
    local warnInit = panel:CreateCheckbox(builder, WT.L.OPT_CT_BOSS_WARN, WT.L.OPT_DESC_CT_BOSS_WARN, "CombatTracker", "BossTimeWarn", function() self:Refresh() end, timeInit)
    panel:CreateSlider(builder, WT.L.OPT_CT_BOSS_WARN_SECONDS, WT.L.OPT_DESC_CT_BOSS_WARN_SECONDS, "CombatTracker", "BossTimeWarnSeconds", 30, 900, 15, function() self:Refresh() end, warnInit)
    panel:CreateColorPicker(builder, WT.L.OPT_CT_BOSS_WARN_COLOR, WT.L.OPT_DESC_CT_BOSS_WARN_COLOR, "CombatTracker", "BossTimeWarnColor", false, warnInit, function() self:Refresh() end)
    -- Independent of the display: also works with range and combat time hidden
    panel:CreateCheckbox(builder, WT.L.OPT_CT_PRINT_TIME, WT.L.OPT_DESC_CT_PRINT_TIME, "CombatTracker", "PrintCombatTime", function() self:Refresh() end)
    
    panel:CreateTitle(builder, WT.L.GROUP_CT_APPEARANCE)
    AddDescription(WT.L.OPT_DESC_GROUP_CT_APPEARANCE)
    
    panel:CreateButton(builder, WT.L.OPT_CT_TEST, WT.L.BTN_TEST, WT.L.OPT_DESC_CT_TEST, function()
        self:PreviewTracker()
    end)
    builder:AddSpace(10)
    
    local moveInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_MOVABLE, WT.L.OPT_DESC_SW_MOVABLE, "CombatTracker", "Movable", function() self:Refresh() end)
    local modOptions = { { value = "ALT", label = "ALT" }, { value = "CTRL", label = "CTRL" }, { value = "SHIFT", label = "SHIFT" } }
    panel:CreateDropdown(builder, WT.L.OPT_SW_MOVE_MODIFIER, WT.L.OPT_DESC_SW_MOVE_MODIFIER, "CombatTracker", "MoveModifier", modOptions, nil, moveInit)
    panel:CreateStrataDropdown(builder, WT.L.OPT_STRATA, WT.L.OPT_DESC_STRATA, "CombatTracker", "Strata", function() self:Refresh() end)
    
    if WT.Utils and WT.Utils.SharedMedia then
        panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "CombatTracker", "Font", WT.Utils.SharedMedia:GetOptions("font"), function() self:Refresh() end)
    end
    panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "CombatTracker", "FontSize", 8, 36, 1, function() self:Refresh() end)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "CombatTracker", "FontOutline", function() self:Refresh() end)
    
    local bgInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_BACKGROUND, WT.L.OPT_DESC_SW_BACKGROUND, "CombatTracker", "Background", function() self:Refresh() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BG, WT.L.OPT_DESC_COLOR_BG, "CombatTracker", "BgColor", true, bgInit, function() self:Refresh() end)
    local borderInit = panel:CreateCheckbox(builder, WT.L.OPT_SW_BORDER, WT.L.OPT_DESC_SW_BORDER, "CombatTracker", "Border", function() self:Refresh() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BORDER, WT.L.OPT_DESC_COLOR_BORDER, "CombatTracker", "BorderColor", true, borderInit, function() self:Refresh() end)
    
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_TEXT, WT.L.OPT_DESC_COLOR_TEXT, "CombatTracker", "TextColor", true, nil, function() self:Refresh() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "CombatTracker", "ValueColor", true, nil, function() self:Refresh() end)
    
    local sepInit = panel:CreateEditBox(builder, WT.L.OPT_SEPARATOR, WT.L.OPT_DESC_SEPARATOR, "CombatTracker", "Separator", nil, function() self:Refresh() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_SEP, WT.L.OPT_DESC_COLOR_SEP, "CombatTracker", "SeparatorColor", true, sepInit, function() self:Refresh() end)
end