local _, WT = ...

WT.Modules.Nameplates = {}
local Module = WT.Modules.Nameplates

-- Localize global functions (Upvaluing)
local InCombatLockdown = InCombatLockdown

function Module:UpdateNameplateStacking(enable, isSilent)
    if WT.Core.CombatQueue:Add("NameplateStacking", isSilent, self.UpdateNameplateStacking, self, enable, true) then return end

    if WT.Utils and WT.Utils.Flags then
        WT.Utils.Flags:SetCVar("nameplateMotion", enable and "1" or "0")
    else
        pcall(function() C_CVar.SetCVar("nameplateMotion", enable and "1" or "0") end)
    end
    if WT.DB.Nameplates.NameplateStacking and WT.DB.Nameplates.NameplateOverlapV then
        if WT.Utils and WT.Utils.Flags then
            WT.Utils.Flags:SetCVar("nameplateOverlapV", tostring(WT.DB.Nameplates.NameplateOverlapV))
        else
            pcall(function() C_CVar.SetCVar("nameplateOverlapV", tostring(WT.DB.Nameplates.NameplateOverlapV)) end)
        end
    end
end

function Module:UpdateSmartNameplates(enable, isSilent)
    if WT.Core.CombatQueue:Add("SmartNameplates", isSilent, self.UpdateSmartNameplates, self, enable, true) then return end

    local val = enable and "0" or "1"
    if WT.Utils and WT.Utils.Flags then WT.Utils.Flags:SetCVar("nameplateShowAll", val) else pcall(function() C_CVar
                .SetCVar("nameplateShowAll", val) end) end
end

function Module:UpdateNameplateResource(enable, isSilent)
    if WT.Core.CombatQueue:Add("NameplateResource", isSilent, self.UpdateNameplateResource, self, enable, true) then return end

    local val = enable and "1" or "0"
    if WT.Utils and WT.Utils.Flags then WT.Utils.Flags:SetCVar("nameplateResourceOnTarget", val) else pcall(function()
            C_CVar.SetCVar("nameplateResourceOnTarget", val) end) end
end

function Module:UpdateTargetScale(enable)
    local val = enable and tostring(WT.DB.Nameplates.TargetScale or 1.2) or "1.0"
    if WT.Utils and WT.Utils.Flags then
        WT.Utils.Flags:SetCVar("nameplateSelectedScale", val)
    else
        pcall(function() C_CVar.SetCVar("nameplateSelectedScale", val) end)
    end
end

local isPlayerTank = false
local cachedThreatColors = {}

local cachedPlayerFaction = nil
local questUpdateCount = 0

-- PERFORMANCE & TAINT: Safely evaluate variables that might be "secret number values" in WoW 12.0+
local SafeNum = WT.Utils.Safety.SafeNum
local Unsecret = WT.Utils.Safety.Unsecret
local IsSafeBoolean = WT.Utils.Safety.IsSafeBoolean

local SafeUnitGUID = WT.Utils.Units.SafeUnitGUID
local SafeUnitIsPlayer = WT.Utils.Units.SafeUnitIsPlayer
local SafeUnitFactionGroup = WT.Utils.Units.SafeUnitFactionGroup
local SafeUnitRace = WT.Utils.Units.SafeUnitRace
local SafeUnitIsEnemy = WT.Utils.Units.SafeUnitIsEnemy
local SafeUnitCanAttack = WT.Utils.Units.SafeUnitCanAttack
local SafeUnitClassification = WT.Utils.Units.SafeUnitClassification
local SafeUnitAffectingCombat = WT.Utils.Units.SafeUnitAffectingCombat
local SafeUnitClass = WT.Utils.Units.SafeUnitClass
local SafeUnitPowerType = WT.Utils.Units.SafeUnitPowerType

local function GetSafeThreat(unit)
    local okCall, raw = pcall(UnitThreatSituation, "player", unit)
    if not okCall then return nil, false end
    if scrub then raw = scrub(raw) end
    if raw == nil then return nil, true end
    if type(raw) ~= "number" then return nil, false end
    local ok = pcall(function() return raw == 0 end)
    if ok then return raw, true end
    return nil, false
end


local function UpdateTankStatus()
    isPlayerTank = false
    if GetSpecialization and GetSpecializationInfo then
        local okSpec, spec = pcall(GetSpecialization)
        if okSpec and spec then
            local okInfo, _, _, _, _, role = pcall(GetSpecializationInfo, spec)
            if okInfo and role == "TANK" then isPlayerTank = true end
        end
    end
    if not isPlayerTank and type(UnitGroupRolesAssigned) == "function" then
        local ok, rawRole = pcall(UnitGroupRolesAssigned, "player")
        local role = ok and Unsecret(rawRole) or nil
        isPlayerTank = (role == "TANK")
    end
end

local function UpdateThreatColorsCache()
    cachedThreatColors.sr, cachedThreatColors.sg, cachedThreatColors.sb = WT.Colors:GetRGB(
    WT.DB.Nameplates.ColThreatSafe, 0.2, 1, 0.2)
    cachedThreatColors.wr, cachedThreatColors.wg, cachedThreatColors.wb = WT.Colors:GetRGB(
    WT.DB.Nameplates.ColThreatWarn, 1, 0.5, 0)
    cachedThreatColors.dr, cachedThreatColors.dg, cachedThreatColors.db = WT.Colors:GetRGB(
    WT.DB.Nameplates.ColThreatDanger, 1, 0.2, 0.2)
end

-- Nameplate Taint Protection:
-- Never inject custom variables into Blizzard Nameplate tables. Use a weak table instead!
local npData = setmetatable({}, { __mode = "k" })
local questCache = {}

local function CalculateNameplateColors(specificUnit)
    if not WT.DB.Modules.Nameplates then return end

    local targetGUID = SafeUnitGUID("target")

    local function ProcessUnitFrame(unitFrame)
        if unitFrame and not unitFrame:IsForbidden() and unitFrame:IsVisible() then
            local unitRaw = unitFrame.unit or unitFrame.displayedUnit
            local unit = Unsecret(unitRaw)

            if not npData[unitFrame] then npData[unitFrame] = {} end
            local myData = npData[unitFrame]

            if unit and type(unit) == "string" and string.sub(unit, 1, 9) == "nameplate" then
                local guid = SafeUnitGUID(unit)
                local isSame = false
                if guid and myData.guid then
                    local ok, res = pcall(function() return myData.guid == guid end)
                    isSame = (ok and res)
                end

                if guid and not isSame then
                    myData.guid = guid
                    myData.isPlayer = SafeUnitIsPlayer(unit)
                    myData.class = nil
                    myData.isElite = nil
                    myData.isCaster = nil
                    myData.race = nil
                    myData.faction = nil
                    myData.isQuest = nil
                    myData.colorR, myData.colorG, myData.colorB = nil, nil, nil
                end

                -- 1. COLORS
                local r, g, b = nil, nil, nil
                local isPlayer = myData.isPlayer
                if isPlayer == nil then
                    isPlayer = SafeUnitIsPlayer(unit)
                    myData.isPlayer = isPlayer
                end

                if isPlayer then
                    ---@type string|nil
                    local class = myData.class
                    if not class then
                        _, class = SafeUnitClass(unit)
                        if class then myData.class = class end
                    end

                    if not class then
                        local retryGUID = guid or SafeUnitGUID(unit)
                        if retryGUID then
                            local okRetry, isSameRetry = pcall(function() return myData.lastRetryGUID == retryGUID end)
                            if not (okRetry and isSameRetry) then
                                myData.classRetry = 0
                                myData.lastRetryGUID = retryGUID
                            end
                            if myData.classRetry < 10 then
                                myData.classRetry = myData.classRetry + 1
                                C_Timer.After(0.2, function()
                                    local currentUnit = unitFrame.unit or unitFrame.displayedUnit
                                    local okG, isSameG = pcall(function() return SafeUnitGUID(currentUnit) == retryGUID end)
                                    if unitFrame and unitFrame:IsVisible() and currentUnit and okG and isSameG then
                                        CalculateNameplateColors(currentUnit)
                                    end
                                end)
                            end
                        end
                    else
                        myData.classRetry = 0
                        myData.lastRetryGUID = nil
                    end

                    if WT.DB.Nameplates.NameplateClassColors and class then
                        local isEnemyPlayer = SafeUnitIsEnemy("player", unit) or SafeUnitCanAttack("player", unit)

                        if not isEnemyPlayer then
                            local targetRace = myData.race
                            if not targetRace then
                                _, targetRace = SafeUnitRace(unit)
                                if targetRace then myData.race = targetRace end
                            end

                            local targetFac = myData.faction
                            if not targetFac then
                                targetFac = SafeUnitFactionGroup(unit)
                                if not targetFac and targetRace then
                                    targetFac = WT.Utils.Units.RACE_TO_FACTION[targetRace]
                                end
                                if targetFac then myData.faction = targetFac end
                            end

                            if not cachedPlayerFaction then
                                cachedPlayerFaction = SafeUnitFactionGroup("player")
                            end

                            if cachedPlayerFaction and targetFac and cachedPlayerFaction ~= targetFac then
                                isEnemyPlayer = true
                            end
                        end

                        if isEnemyPlayer then
                            local ok, color = pcall(function() return WT.DB.ClassColors and WT.DB.ClassColors[class] or
                                RAID_CLASS_COLORS[class] end)
                            if ok and color then r, g, b = color.r, color.g, color.b end
                        end
                    end
                end

                local isElite = myData.isElite
                local isCaster = myData.isCaster

                if not r and not isPlayer and SafeUnitCanAttack("player", unit) then
                    if WT.DB.Nameplates.NameplateElite then
                        if isElite == nil then
                            local classification = SafeUnitClassification(unit)
                            isElite = (classification == "elite" or classification == "rareelite" or classification == "worldboss")
                            myData.isElite = isElite
                        end
                        if isElite then
                            r, g, b = WT.Colors:GetRGB(WT.DB.Nameplates.ColElite, 1, 0.82, 0)
                        end
                    end

                    if not r and WT.DB.Nameplates.NameplateCaster then
                        if isCaster == nil then
                            isCaster = (SafeUnitPowerType(unit) == 0)
                            myData.isCaster = isCaster
                        end
                        if isCaster then
                            r, g, b = WT.Colors:GetRGB(WT.DB.Nameplates.ColCaster, 0, 1, 1)
                        end
                    end

                    if WT.DB.Nameplates.NameplateThreat then
                        -- The secret trick: UnitThreatSituation only returns the 0-3 tiers.
                        -- Taint Protection: We unpack it safely because 12.0+ nameplates can return secret numbers!
                        local status, isSafe = GetSafeThreat(unit)
                        local c = cachedThreatColors

                        if isSafe and (SafeUnitAffectingCombat(unit) or status) then
                            local override = WT.DB.Nameplates.NameplateThreatOverride
                            if isPlayerTank then
                                if status == 3 then
                                    if override or not (isElite or isCaster) then r, g, b = c.sr, c.sg, c.sb end
                                elseif status == 2 or status == 1 then
                                    r, g, b = c.wr, c.wg, c.wb
                                else
                                    r, g, b = c.dr, c.dg, c.db
                                end
                            else
                                if status == 3 then
                                    r, g, b = c.dr, c.dg, c.db
                                elseif status == 2 or status == 1 then
                                    r, g, b = c.wr, c.wg, c.wb
                                else
                                    if override or not (isElite or isCaster) then r, g, b = c.sr, c.sg, c.sb end
                                end
                            end
                        end
                    end
                end

                if r and g and b then
                    local hb = unitFrame.healthBar or unitFrame.HealthBar
                    if hb then
                        if not hb.wtHooked then
                            hb.wtHooked = true
                            local okC, nR, nG, nB = pcall(hb.GetStatusBarColor, hb)
                            if okC then myData.nativeR, myData.nativeG, myData.nativeB = nR, nG, nB end

                            hooksecurefunc(hb, "SetStatusBarColor", function(self, rT, gT, bT)
                                if self.wtIsUpdating then return end
                                local data = npData[unitFrame]
                                if data then
                                    data.nativeR, data.nativeG, data.nativeB = rT, gT, bT
                                end
                                if data and data.colorR then
                                    local currentUnit = unitFrame.unit or unitFrame.displayedUnit
                                    if currentUnit then
                                        local currentGuid = SafeUnitGUID(currentUnit)
                                        if currentGuid and currentGuid ~= data.guid then
                                            return
                                        end
                                    end
                                    self.wtIsUpdating = true
                                    self:SetStatusBarColor(data.colorR, data.colorG, data.colorB)
                                    self.wtIsUpdating = false
                                end
                            end)
                        end
                        myData.colorR, myData.colorG, myData.colorB = r, g, b
                        hb.wtIsUpdating = true
                        hb:SetStatusBarColor(r, g, b)
                        hb.wtIsUpdating = false
                    end
                else
                    local hb = unitFrame.healthBar or unitFrame.HealthBar
                    if hb and myData.colorR then
                        myData.colorR, myData.colorG, myData.colorB = nil, nil, nil
                        -- Silently restore native color without waking up Blizzard's update function
                        if myData.nativeR then
                            hb.wtIsUpdating = true
                            hb:SetStatusBarColor(myData.nativeR, myData.nativeG, myData.nativeB)
                            hb.wtIsUpdating = false
                        end
                    end
                end

                -- 2. TARGET GLOW
                local okT, isSameT = pcall(function() return guid == targetGUID end)
                if WT.DB.Nameplates.TargetGlowEnabled and (guid and okT and isSameT) then
                    local hb = unitFrame.healthBar or unitFrame.HealthBar
                    if hb then
                        if not myData.targetGlow then
                            myData.targetGlow = CreateFrame("Frame", nil, hb)
                            myData.targetGlow:SetFrameLevel(hb:GetFrameLevel() - 1)

                            myData.targetGlow.top = myData.targetGlow:CreateTexture(nil, "BACKGROUND")
                            myData.targetGlow.top:SetTexture("Interface\\Buttons\\WHITE8x8")
                            myData.targetGlow.bottom = myData.targetGlow:CreateTexture(nil, "BACKGROUND")
                            myData.targetGlow.bottom:SetTexture("Interface\\Buttons\\WHITE8x8")
                            myData.targetGlow.left = myData.targetGlow:CreateTexture(nil, "BACKGROUND")
                            myData.targetGlow.left:SetTexture("Interface\\Buttons\\WHITE8x8")
                            myData.targetGlow.right = myData.targetGlow:CreateTexture(nil, "BACKGROUND")
                            myData.targetGlow.right:SetTexture("Interface\\Buttons\\WHITE8x8")
                        end

                        local scale = WT.DB.Nameplates.TargetGlowScale or 1.0
                        local t = myData.targetGlow

                        t:SetFrameStrata(WT.DB.Nameplates.TargetGlowStrata or "BACKGROUND")

                        t.top:ClearAllPoints()
                        t.top:SetPoint("TOPLEFT", hb, "TOPLEFT", -scale, scale)
                        t.top:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", scale, 0)
                        t.bottom:ClearAllPoints()
                        t.bottom:SetPoint("TOPLEFT", hb, "BOTTOMLEFT", -scale, 0)
                        t.bottom:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", scale, -scale)
                        t.left:ClearAllPoints()
                        t.left:SetPoint("TOPLEFT", hb, "TOPLEFT", -scale, 0)
                        t.left:SetPoint("BOTTOMRIGHT", hb, "BOTTOMLEFT", 0, 0)
                        t.right:ClearAllPoints()
                        t.right:SetPoint("TOPLEFT", hb, "TOPRIGHT", 0, 0)
                        t.right:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", scale, 0)

                        local c = WT.DB.Nameplates.TargetGlowColor or { r = 1, g = 1, b = 1, a = 0.8 }
                        local blendMode = WT.DB.Nameplates.TargetGlowBlend and "ADD" or "BLEND"

                        t.top:SetVertexColor(c.r, c.g, c.b, c.a); t.top:SetBlendMode(blendMode)
                        t.bottom:SetVertexColor(c.r, c.g, c.b, c.a); t.bottom:SetBlendMode(blendMode)
                        t.left:SetVertexColor(c.r, c.g, c.b, c.a); t.left:SetBlendMode(blendMode)
                        t.right:SetVertexColor(c.r, c.g, c.b, c.a); t.right:SetBlendMode(blendMode)

                        myData.targetGlow:Show()
                    end
                else
                    if myData.targetGlow then
                        myData.targetGlow:Hide()
                    end
                end

                -- 3. QUEST INDICATOR
                if WT.DB.Nameplates.QuestIndicator then
                    local isQuest
                    local npcID = guid and select(6, strsplit("-", guid)) or nil

                    if myData.questUpdateCount == questUpdateCount or (InCombatLockdown() and myData.isQuest ~= nil) then
                        isQuest = myData.isQuest
                    elseif InCombatLockdown() and guid and questCache[guid] ~= nil then
                        isQuest = questCache[guid]
                        myData.isQuest = isQuest
                    elseif InCombatLockdown() and npcID and questCache["NPC_" .. npcID] ~= nil then
                        isQuest = questCache["NPC_" .. npcID]
                        myData.isQuest = isQuest
                    end

                    if isQuest == nil then
                        isQuest = false
                        local tooltipConfirmedActive = nil

                        -- Deep Scan for World Quests, untracked quests, and completion status
                        -- Massive Taint Source: We disable this entirely during combat!
                        if not InCombatLockdown() and C_TooltipInfo and C_TooltipInfo.GetUnit then
                            local okTT, tooltipData = pcall(C_TooltipInfo.GetUnit, unit)
                            if okTT and tooltipData and tooltipData.lines then
                                local hasActiveObjective = false
                                local hasAnyObjective = false
                                local hasQuestTitle = false

                                for _, line in ipairs(tooltipData.lines) do
                                    if line.type == Enum.TooltipDataLineType.QuestTitle then
                                        hasQuestTitle = true
                                    elseif line.type == Enum.TooltipDataLineType.QuestObjective then
                                        hasAnyObjective = true
                                        local isCompleted = false

                                        local safeText = Unsecret(line.leftText)
                                        if safeText then
                                            local v, max = string.match(safeText, "(%d+)%s*/%s*(%d+)")
                                            if v and max and tonumber(v) >= tonumber(max) then isCompleted = true end
                                        end
                                        if not isCompleted then hasActiveObjective = true end
                                    end
                                end

                                if hasAnyObjective then
                                    tooltipConfirmedActive = hasActiveObjective
                                elseif hasQuestTitle then
                                    tooltipConfirmedActive = true
                                end
                            end
                        end

                        if tooltipConfirmedActive ~= nil then
                            isQuest = tooltipConfirmedActive
                        elseif C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
                            local ok, res = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
                            if ok then
                                local ok2 = pcall(IsSafeBoolean, res)
                                isQuest = ok2 and res or false
                            end
                        end

                        myData.isQuest = isQuest
                        if guid then questCache[guid] = isQuest end
                        if npcID then questCache["NPC_" .. npcID] = isQuest end
                        myData.questUpdateCount = questUpdateCount
                    end

                    if isQuest then
                        local hb = unitFrame.healthBar or unitFrame.HealthBar
                        if hb then
                            if not myData.questIcon then
                                myData.questIcon = hb:CreateTexture(nil, "OVERLAY")
                                myData.questIcon:SetTexture("Interface\\TargetingFrame\\PortraitQuestBadge")
                            end
                            local size = 16 * (WT.DB.Nameplates.QuestIconScale or 1.0)
                            myData.questIcon:SetSize(size, size)

                            local pos = WT.DB.Nameplates.QuestIconPosition or "RIGHT"
                            local xOff = WT.DB.Nameplates.QuestIconX or 4
                            local yOff = WT.DB.Nameplates.QuestIconY or 0

                            myData.questIcon:ClearAllPoints()
                            if pos == "LEFT" then
                                myData.questIcon:SetPoint("RIGHT", hb, "LEFT", -xOff, yOff)
                            elseif pos == "RIGHT" then
                                myData.questIcon:SetPoint("LEFT", hb, "RIGHT", xOff, yOff)
                            elseif pos == "TOP" then
                                myData.questIcon:SetPoint("BOTTOM", hb, "TOP", xOff, yOff)
                            elseif pos == "BOTTOM" then
                                myData.questIcon:SetPoint("TOP", hb, "BOTTOM", xOff, -yOff)
                            end

                            myData.questIcon:Show()
                        end
                    else
                        if myData.questIcon then myData.questIcon:Hide() end
                    end
                else
                    if myData.questIcon then myData.questIcon:Hide() end
                end
            end
        end
    end

    if specificUnit then
        local ok, frame = pcall(C_NamePlate.GetNamePlateForUnit, specificUnit)
        if ok and frame and frame.UnitFrame then ProcessUnitFrame(frame.UnitFrame) end
    elseif C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and plates then
            for _, frame in ipairs(plates) do
                ProcessUnitFrame(frame.UnitFrame)
            end
        end
    end
end

function Module:SetupNameplateColors()
    if not self.npColorHooked then
        self.npColorHooked = true
        -- Removed unthrottled UNIT_HEALTH / UNIT_MAXHEALTH events.
        -- They were creating thousands of timers per second during AoE, causing massive hangs.
        -- The hook on 'CompactUnitFrame_UpdateHealthColor' in Initialize() handles this natively now.
    end

    CalculateNameplateColors()
end

local function ApplyCustomAuras(frame)
    if not frame or frame:IsForbidden() or not frame.isNamePlate then return end

    local container = frame.BuffFrame
    if not container then return end

    if not WT.DB.Nameplates.AurasEnabled then
        if container.wtAuraModified then
            pcall(function()
                container:SetScale(1.0)
                container:ClearAllPoints()
                container:SetPoint("BOTTOMLEFT", frame.healthBar, "TOPLEFT", 0, 4)
            end)
            container.wtAuraModified = false
        end
        return
    end

    container.wtAuraModified = true
    pcall(function()
        container:SetScale(WT.DB.Nameplates.AuraScale or 1.0)

        local yOff = WT.DB.Nameplates.AuraYOffset or 0
        container:ClearAllPoints()
        -- Center buffs automatically and apply the Y offset.
        container:SetPoint("BOTTOM", frame.healthBar, "TOP", 0, 4 + (yOff / (WT.DB.Nameplates.AuraScale or 1.0)))
    end)
end

function Module:SetupAuras()
    if not self.npAurasHooked then
        self.npAurasHooked = true
        WT.Core.Events:Register("UNIT_AURA", function(_, unit)
            if unit and string.match(unit, "^nameplate") then
                C_Timer.After(0, function()
                    local ok, frame = pcall(C_NamePlate.GetNamePlateForUnit, unit)
                    if ok and frame and frame.UnitFrame then ApplyCustomAuras(frame.UnitFrame) end
                end)
            end
        end)
    end
end

local function ApplyCustomName(frame)
    if not frame or frame:IsForbidden() or not frame.isNamePlate then return end
    if not frame.name then return end

    if not WT.DB.Nameplates.NameScaleEnabled then
        if frame.name.wtModified then
            pcall(function() frame.name:SetScale(1.0) end)
            frame.name.wtModified = false
        end
        return
    end

    frame.name.wtModified = true
    pcall(function() frame.name:SetScale(WT.DB.Nameplates.NameScale or 1.0) end)
end

function Module:SetupNameText()
    if not self.npNameHooked then
        self.npNameHooked = true
        WT.Core.Events:Register("UNIT_NAME_UPDATE", function(_, unit)
            if unit and string.match(unit, "^nameplate") then
                C_Timer.After(0, function()
                    local ok, frame = pcall(C_NamePlate.GetNamePlateForUnit, unit)
                    if ok and frame and frame.UnitFrame then ApplyCustomName(frame.UnitFrame) end
                end)
            end
        end)
    end
end

local isThreatUpdateQueued = false
local function DoThreatUpdate()
    isThreatUpdateQueued = false
    CalculateNameplateColors()
end

local function UpdateThreatOnPlates()
    if not WT.DB.Modules.Nameplates or not WT.DB.Nameplates.NameplateThreat then return end

    -- Performance: Threat events fire dozens of times per second in AoE.
    -- We throttle the visual update to max 25 times a second to prevent heavy CPU spikes.
    if not isThreatUpdateQueued then
        isThreatUpdateQueued = true
        C_Timer.After(0.04, DoThreatUpdate)
    end
end

local cpFrame = nil
local comboPoints = {}

local function UpdateCustomComboPoints()
    if not WT.DB.Nameplates.NameplateResourceOnTarget then
        if cpFrame then cpFrame:Hide() end
        return
    end

    local isDemo = WT.DB.Nameplates.NameplateCPDemo
    local vis = WT.DB.Nameplates.NameplateCPVisibility or "ALWAYS"
    if not isDemo and vis == "COMBAT" then
        if not SafeUnitAffectingCombat("player") then
            if cpFrame then cpFrame:Hide() end
            return
        end
    end

    if not cpFrame then
        cpFrame = CreateFrame("Frame", "WT_NameplateComboPoints", UIParent)
        cpFrame:SetSize(100, 15)
        cpFrame:Hide()

        local shape = WT.DB.Nameplates.NameplateCPShape or "RECT"
        local sizeX, sizeY = 14, 10
        if shape == "CIRCLE" then
            sizeX, sizeY = 12, 12
        elseif shape == "SQUARE" then
            sizeX, sizeY = 12, 12
        elseif shape == "LINE" then
            sizeX, sizeY = 14, 4
        end

        local style = WT.DB.Nameplates.NameplateCPColorStyle or "GRADIENT"
        local color = WT.DB.Nameplates.NameplateCPColor or { r = 1, g = 0.8, b = 0, a = 1 }
        local class = select(2, UnitClass("player"))
        local classCol = WT.DB.ClassColors and WT.DB.ClassColors[class] or { r = 1, g = 1, b = 1, a = 1 }

        local useBorder = WT.DB.Nameplates.NameplateCPBorder
        if useBorder == nil then useBorder = true end
        local bCol = WT.DB.Nameplates.NameplateCPBorderColor or { r = 0, g = 0, b = 0, a = 1 }

        for i = 1, 10 do
            local cp = CreateFrame("Frame", nil, cpFrame)
            cp:SetSize(sizeX, sizeY)

            local bg = cp:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            
            local innerBg = cp:CreateTexture(nil, "BORDER")

            local fg = cp:CreateTexture(nil, "ARTWORK")

            if useBorder then
                bg:SetColorTexture(bCol.r, bCol.g, bCol.b, bCol.a)
                innerBg:SetPoint("TOPLEFT", cp, "TOPLEFT", 1, -1)
                innerBg:SetPoint("BOTTOMRIGHT", cp, "BOTTOMRIGHT", -1, 1)
                innerBg:SetColorTexture(0, 0, 0, 0.8)
                fg:SetPoint("TOPLEFT", cp, "TOPLEFT", 1, -1)
                fg:SetPoint("BOTTOMRIGHT", cp, "BOTTOMRIGHT", -1, 1)
            else
                bg:SetColorTexture(0, 0, 0, 0)
                innerBg:SetPoint("TOPLEFT", cp, "TOPLEFT", 0, 0)
                innerBg:SetPoint("BOTTOMRIGHT", cp, "BOTTOMRIGHT", 0, 0)
                innerBg:SetColorTexture(0, 0, 0, 0.8)
                fg:SetPoint("TOPLEFT", cp, "TOPLEFT", 0, 0)
                fg:SetPoint("BOTTOMRIGHT", cp, "BOTTOMRIGHT", 0, 0)
            end

            if shape == "CIRCLE" and cp.CreateMaskTexture then
                local bgMask = cp:CreateMaskTexture()
                bgMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                bgMask:SetAllPoints(bg)
                bg:AddMaskTexture(bgMask)
                
                local innerMask = cp:CreateMaskTexture()
                innerMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                innerMask:SetAllPoints(innerBg)
                innerBg:AddMaskTexture(innerMask)

                local fgMask = cp:CreateMaskTexture()
                fgMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                fgMask:SetAllPoints(fg)
                fg:AddMaskTexture(fgMask)
            end

            if style == "FIXED" then
                fg:SetColorTexture(color.r, color.g, color.b, color.a)
            elseif style == "CLASS" then
                fg:SetColorTexture(classCol.r, classCol.g, classCol.b, classCol.a)
            else
                if i == 1 then
                    fg:SetColorTexture(0.9, 0.2, 0.2, 1)
                elseif i == 2 then
                    fg:SetColorTexture(0.9, 0.5, 0.1, 1)
                elseif i == 3 then
                    fg:SetColorTexture(0.9, 0.8, 0.1, 1)
                elseif i == 4 then
                    fg:SetColorTexture(0.5, 0.9, 0.1, 1)
                else
                    fg:SetColorTexture(0.1, 0.9, 0.1, 1)
                end
            end

            cp.fg = fg
            cp:Hide()
            comboPoints[i] = cp
        end
    end

    local scale = WT.DB.Nameplates.NameplateCPScale or 1.0
    cpFrame:SetScale(scale)

    local pt = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
    local cp = isDemo and 5 or UnitPower("player", pt)
    local maxCP = isDemo and 5 or UnitPowerMax("player", pt)
    if maxCP < 1 then maxCP = 5 end

    local shape = WT.DB.Nameplates.NameplateCPShape or "RECT"
    local sizeX = 14
    if shape == "CIRCLE" then
        sizeX = 12
    elseif shape == "SQUARE" then
        sizeX = 12
    elseif shape == "LINE" then
        sizeX = 14
    end

    if (cp > 0 or isDemo) and UnitExists("target") and not UnitIsDeadOrGhost("target") then
        local cpWidth = (sizeX * maxCP) + (2 * (maxCP - 1))
        cpFrame:SetWidth(cpWidth)

        for i = 1, 10 do
            comboPoints[i]:ClearAllPoints()
            if i <= maxCP then
                if i == 1 then
                    comboPoints[i]:SetPoint("LEFT", cpFrame, "LEFT", 0, 0)
                else
                    comboPoints[i]:SetPoint("LEFT", comboPoints[i - 1], "RIGHT", 2, 0)
                end

                comboPoints[i]:Show()
                if i <= cp then
                    comboPoints[i].fg:SetAlpha(1)
                else
                    comboPoints[i].fg:SetAlpha(0.2)
                end
            else
                comboPoints[i]:Hide()
            end
        end

        local ok, nameplate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
        if ok and nameplate then
            cpFrame:SetParent(UIParent)
            cpFrame:ClearAllPoints()
            local pos = WT.DB.Nameplates.NameplateCPPosition or "TOP"
            local x = WT.DB.Nameplates.NameplateCPX or 0
            local y = WT.DB.Nameplates.NameplateCPY or 5

            if pos == "BOTTOM" then
                cpFrame:SetPoint("TOP", nameplate, "BOTTOM", x, y)
            else
                cpFrame:SetPoint("BOTTOM", nameplate, "TOP", x, y)
            end
            cpFrame:Show()
        else
            cpFrame:Hide()
        end
    else
        cpFrame:Hide()
    end
end

function Module:Initialize()
    if not WT.DB.Modules.Nameplates then return end

    if WT.DB.Nameplates.NameplateClassColors or WT.DB.Nameplates.NameplateThreat or WT.DB.Nameplates.NameplateCaster or WT.DB.Nameplates.NameplateElite then
        UpdateTankStatus()
        UpdateThreatColorsCache()
        self:SetupNameplateColors()

        -- Prevent flickering by securely hooking Blizzard's color update
        if _G["CompactUnitFrame_UpdateHealthColor"] then
            hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
                if frame and frame.unit and not frame:IsForbidden() and frame.isNamePlate then
                    local safeUnit = Unsecret(frame.unit)
                    if safeUnit then CalculateNameplateColors(safeUnit) end
                end
            end)
        end
    end
    if WT.DB.Nameplates.NameplateStacking then
        self:UpdateNameplateStacking(true, true)
    end
    if WT.DB.Nameplates.SmartNameplates then
        self:UpdateSmartNameplates(true, true)
    end
    if WT.DB.Nameplates.NameplateResourceOnTarget then
        self:UpdateNameplateResource(true, true)
    end
    if WT.DB.Nameplates.TargetScaleEnabled then
        self:UpdateTargetScale(true)
    end
    if WT.DB.Nameplates.AurasEnabled then
        self:SetupAuras()
    end
    if WT.DB.Nameplates.NameScaleEnabled then
        self:SetupNameText()
    end

    WT.Core.Events:Register("PLAYER_TALENT_UPDATE", UpdateTankStatus)
    WT.Core.Events:Register("PLAYER_ROLES_ASSIGNED", UpdateTankStatus)

    WT.Core.Events:Register("NAME_PLATE_UNIT_ADDED", function(_, unit)
        local safeUnit = Unsecret(unit)
        if safeUnit then
            C_Timer.After(0, function()
                CalculateNameplateColors(safeUnit)
                local ok, frame = pcall(C_NamePlate.GetNamePlateForUnit, safeUnit)
                if ok and frame and frame.UnitFrame then
                    ApplyCustomAuras(frame.UnitFrame)
                    ApplyCustomName(frame.UnitFrame)
                end
                if UnitIsUnit(safeUnit, "target") then
                    UpdateCustomComboPoints()
                end
            end)
        end
    end)

    WT.Core.Events:Register("NAME_PLATE_UNIT_REMOVED", function(_, unit)
        if unit and UnitIsUnit(unit, "target") then
            if cpFrame then cpFrame:Hide() end
        end
    end)

    WT.Core.Events:Register("PLAYER_TARGET_CHANGED", function()
        CalculateNameplateColors()
        UpdateCustomComboPoints()
    end)
    WT.Core.Events:Register("UNIT_POWER_UPDATE", function(_, unit, powerType)
        if unit == "player" and (powerType == "COMBO_POINTS" or not powerType) then
            UpdateCustomComboPoints()
        end
    end)
    WT.Core.Events:Register("UNIT_MAXPOWER", function(_, unit, powerType)
        if unit == "player" and (powerType == "COMBO_POINTS" or not powerType) then
            UpdateCustomComboPoints()
        end
    end)
    WT.Core.Events:Register("PLAYER_REGEN_DISABLED", function()
        WT.DB.Nameplates.NameplateCPDemo = false
        UpdateCustomComboPoints()
    end)
    WT.Core.Events:Register("PLAYER_REGEN_ENABLED", UpdateCustomComboPoints)
    WT.Core.Events:Register("QUEST_LOG_UPDATE",
        function()
            questUpdateCount = questUpdateCount + 1; wipe(questCache); CalculateNameplateColors()
        end)
    WT.Core.Events:Register("UNIT_THREAT_SITUATION_UPDATE", UpdateThreatOnPlates)
    WT.Core.Events:Register("UNIT_THREAT_LIST_UPDATE", UpdateThreatOnPlates)
end

WT.Core.Events:Register("PLAYER_LOGIN", function() Module:Initialize() end)

WT.Core.Events:Register("PLAYER_ENTERING_WORLD", function()
    cachedPlayerFaction = SafeUnitFactionGroup("player")
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

    panel:CreateTitle(builder, WT.L.CATEGORY_NAMEPLATES)
    AddDescription(WT.L.OPT_DESC_GROUP_NAMEPLATES)

    local scaleInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_NP_TARGET_SCALE,
        WT.L.OPT_DESC_FRAMES_NP_TARGET_SCALE, "Nameplates", "TargetScaleEnabled",
        function(val) self:UpdateTargetScale(val) end)
    panel:CreateSlider(builder, WT.L.OPT_NP_TARGET_SCALE_VAL, WT.L.OPT_DESC_NP_TARGET_SCALE_VAL, "Nameplates",
        "TargetScale", 1.0, 2.0, 0.05, function() self:UpdateTargetScale(WT.DB.Nameplates.TargetScaleEnabled) end,
        scaleInit)

    local function ResetGlowAnchors()
        if C_NamePlate and C_NamePlate.GetNamePlates then
            for _, frame in ipairs(C_NamePlate.GetNamePlates()) do if frame.UnitFrame and npData[frame.UnitFrame] then npData[frame.UnitFrame].targetGlow = nil end end
        end
        CalculateNameplateColors()
    end

    local glowInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_NP_TARGET_GLOW,
        WT.L.OPT_DESC_FRAMES_NP_TARGET_GLOW, "Nameplates", "TargetGlowEnabled", ResetGlowAnchors)
    panel:CreateColorPicker(builder, WT.L.OPT_NP_TARGET_GLOW_COLOR, WT.L.OPT_DESC_NP_TARGET_GLOW_COLOR,
        "Nameplates", "TargetGlowColor", true, glowInit, ResetGlowAnchors)
    panel:CreateSlider(builder, WT.L.OPT_NP_TARGET_GLOW_SCALE, WT.L.OPT_DESC_NP_TARGET_GLOW_SCALE,
        "Nameplates", "TargetGlowScale", 0.5, 3.0, 0.1, ResetGlowAnchors, glowInit)
    panel:CreateCheckbox(builder, WT.L.OPT_NP_TARGET_GLOW_BLEND,
        WT.L.OPT_DESC_NP_TARGET_GLOW_BLEND, "Nameplates", "TargetGlowBlend", ResetGlowAnchors, glowInit)
    panel:CreateStrataDropdown(builder, WT.L.OPT_STRATA, WT.L.OPT_DESC_STRATA, "Nameplates", "TargetGlowStrata",
        ResetGlowAnchors, glowInit)

    local function UpdateAllNameplates()
        if C_NamePlate and C_NamePlate.GetNamePlates then
            for _, frame in ipairs(C_NamePlate.GetNamePlates()) do
                if frame.UnitFrame then
                    ApplyCustomAuras(frame.UnitFrame)
                    ApplyCustomName(frame.UnitFrame)
                end
            end
        end
    end

    local nameInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_NP_NAME_SCALE,
        WT.L.OPT_DESC_FRAMES_NP_NAME_SCALE, "Nameplates", "NameScaleEnabled",
        function()
            self:SetupNameText(); UpdateAllNameplates()
        end)
    panel:CreateSlider(builder, WT.L.OPT_NP_TARGET_SCALE_VAL, WT.L.OPT_DESC_NP_NAME_SCALE, "Nameplates",
        "NameScale", 0.5, 2.5, 0.1, UpdateAllNameplates, nameInit)

    local auraInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_NP_AURAS,
        WT.L.OPT_DESC_FRAMES_NP_AURAS, "Nameplates", "AurasEnabled",
        function()
            self:SetupAuras(); UpdateAllNameplates()
        end)
    panel:CreateSlider(builder, WT.L.OPT_NP_AURA_SCALE, WT.L.OPT_DESC_NP_AURA_SCALE, "Nameplates",
        "AuraScale", 0.5, 2.5, 0.1, UpdateAllNameplates, auraInit)
    panel:CreateSlider(builder, WT.L.OPT_NP_AURA_Y, WT.L.OPT_DESC_NP_AURA_Y, "Nameplates",
        "AuraYOffset", -30, 50, 1, UpdateAllNameplates, auraInit)

    local function ResetQuestAnchors()
        if C_NamePlate and C_NamePlate.GetNamePlates then
            for _, frame in ipairs(C_NamePlate.GetNamePlates()) do if frame.UnitFrame and npData[frame.UnitFrame] then npData[frame.UnitFrame].questIcon = nil end end
        end
        CalculateNameplateColors()
    end

    local questInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_NP_QUEST,
        WT.L.OPT_DESC_FRAMES_NP_QUEST, "Nameplates", "QuestIndicator", ResetQuestAnchors)

    local posOptions = { { value = "LEFT", label = WT.L.ANCHOR_LEFT }, { value = "RIGHT", label = WT.L.ANCHOR_RIGHT }, { value = "TOP", label = WT.L.ANCHOR_TOP }, { value = "BOTTOM", label = WT.L.ANCHOR_BOTTOM } }
    panel:CreateDropdown(builder, WT.L.OPT_TOOLTIP_CURSOR_ANCHOR_TYPE, WT.L.OPT_DESC_NP_QUEST_POSITION,
        "Nameplates", "QuestIconPosition", posOptions, ResetQuestAnchors, questInit)
    panel:CreateSlider(builder, WT.L.OPT_TOOLTIP_CURSOR_X, WT.L.OPT_DESC_NP_QUEST_X, "Nameplates",
        "QuestIconX", -30, 30, 1, ResetQuestAnchors, questInit)
    panel:CreateSlider(builder, WT.L.OPT_TOOLTIP_CURSOR_Y, WT.L.OPT_DESC_NP_QUEST_Y, "Nameplates",
        "QuestIconY", -30, 30, 1, ResetQuestAnchors, questInit)
    panel:CreateSlider(builder, WT.L.OPT_NP_QUEST_SCALE, WT.L.OPT_DESC_NP_QUEST_SCALE, "Nameplates",
        "QuestIconScale", 0.5, 2.5, 0.1, ResetQuestAnchors, questInit)

    panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_SMART_NAMEPLATES, WT.L.OPT_DESC_FRAMES_SMART_NAMEPLATES, "Nameplates",
        "SmartNameplates", function(value) self:UpdateSmartNameplates(value) end)
    local cpInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_NP_COMBO_POINTS, WT.L.OPT_DESC_FRAMES_NP_COMBO_POINTS,
        "Nameplates", "NameplateResourceOnTarget",
        function(value)
            self:UpdateNameplateResource(value); UpdateCustomComboPoints()
        end)
    
    local cpVisOptions = { { value = "ALWAYS", label = WT.L.OPT_NP_CP_VIS_ALWAYS }, { value = "COMBAT", label = WT.L.OPT_NP_CP_VIS_COMBAT } }
    panel:CreateDropdown(builder, WT.L.OPT_NP_CP_VISIBILITY, WT.L.OPT_DESC_NP_CP_VISIBILITY, "Nameplates",
        "NameplateCPVisibility", cpVisOptions, UpdateCustomComboPoints, cpInit)
        
    local cpShapeOptions = {
        { value = "RECT",    label = WT.L.OPT_NP_CP_SHAPE_RECT },
        { value = "CIRCLE",  label = WT.L.OPT_NP_CP_SHAPE_CIRCLE },
        { value = "SQUARE",  label = WT.L.OPT_NP_CP_SHAPE_SQUARE },
        { value = "LINE",    label = WT.L.OPT_NP_CP_SHAPE_LINE }
    }
    panel:CreateDropdown(builder, WT.L.OPT_NP_CP_SHAPE, WT.L.OPT_DESC_NP_CP_SHAPE, "Nameplates",
        "NameplateCPShape", cpShapeOptions,
        function()
            if cpFrame then cpFrame:Hide(); cpFrame = nil; end
            UpdateCustomComboPoints()
        end, cpInit)
        
    local cpColorOptions = { { value = "GRADIENT", label = WT.L.OPT_NP_CP_COLOR_GRADIENT }, { value = "CLASS", label = WT.L.OPT_NP_CP_COLOR_CLASS }, { value = "FIXED", label = WT.L.OPT_NP_CP_COLOR_FIXED } }
    local cpColorStyleInit
    cpColorStyleInit = panel:CreateDropdown(builder, WT.L.OPT_NP_CP_COLOR_STYLE,
        WT.L.OPT_DESC_NP_CP_COLOR_STYLE, "Nameplates", "NameplateCPColorStyle", cpColorOptions, function()
        if cpColorStyleInit and cpColorStyleInit.wtChildren then
            WT.Config.Builder:SetElementsState(WT.DB.Nameplates.NameplateCPColorStyle == "FIXED",
                unpack(cpColorStyleInit.wtChildren))
        end
        if cpFrame then cpFrame:Hide(); cpFrame = nil; end
        UpdateCustomComboPoints()
    end, cpInit)
    
    panel:CreateColorPicker(builder, WT.L.OPT_NP_CP_COLOR, "", "Nameplates", "NameplateCPColor", true,
        cpColorStyleInit, function()
        if cpFrame then cpFrame:Hide(); cpFrame = nil; end
        UpdateCustomComboPoints()
    end, true)
    
    if cpColorStyleInit and cpColorStyleInit.wtChildren then
        WT.Config.Builder:SetElementsState(WT.DB.Nameplates.NameplateCPColorStyle == "FIXED",
            unpack(cpColorStyleInit.wtChildren))
    end
    
    local cpBorderInit = panel:CreateCheckbox(builder, WT.L.OPT_NP_CP_BORDER, WT.L.OPT_DESC_NP_CP_BORDER,
        "Nameplates", "NameplateCPBorder",
        function()
            if cpFrame then cpFrame:Hide(); cpFrame = nil; end
            UpdateCustomComboPoints()
        end, cpInit)
    panel:CreateColorPicker(builder, WT.L.OPT_NP_CP_BORDER_COLOR, "", "Nameplates",
        "NameplateCPBorderColor", true, cpBorderInit,
        function()
            if cpFrame then cpFrame:Hide(); cpFrame = nil; end
            UpdateCustomComboPoints()
        end)
        
    local cpPosOptions = { { value = "TOP", label = WT.L.ANCHOR_TOP }, { value = "BOTTOM", label = WT.L.ANCHOR_BOTTOM } }
    panel:CreateDropdown(builder, WT.L.OPT_NP_CP_POSITION, WT.L.OPT_DESC_NP_CP_POSITION, "Nameplates",
        "NameplateCPPosition", cpPosOptions, UpdateCustomComboPoints, cpInit)
    panel:CreateSlider(builder, WT.L.OPT_NP_CP_SCALE, WT.L.OPT_DESC_NP_CP_SCALE, "Nameplates",
        "NameplateCPScale", 0.5, 2.5, 0.1, UpdateCustomComboPoints, cpInit)
    panel:CreateSlider(builder, WT.L.OPT_NP_CP_X, WT.L.OPT_DESC_NP_CP_X, "Nameplates", "NameplateCPX", -100,
        100, 1, UpdateCustomComboPoints, cpInit)
    panel:CreateSlider(builder, WT.L.OPT_NP_CP_Y, WT.L.OPT_DESC_NP_CP_Y, "Nameplates", "NameplateCPY", -100,
        100, 1, UpdateCustomComboPoints, cpInit)

    panel:CreateButton(builder, WT.L.OPT_NP_CP_DEMO_LBL, WT.L.OPT_NP_CP_DEMO, WT.L.OPT_DESC_NP_CP_DEMO, function()
        WT.DB.Nameplates.NameplateCPDemo = not WT.DB.Nameplates.NameplateCPDemo
        UpdateCustomComboPoints()
    end, cpInit)
    local colorInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_NP_CLASS_COLORS, WT.L
    .OPT_DESC_FRAMES_NP_CLASS_COLORS, "Nameplates", "NameplateClassColors", function() self:SetupNameplateColors() end)

    local casterInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_NP_CASTER, WT.L.OPT_DESC_FRAMES_NP_CASTER,
        "Nameplates", "NameplateCaster", function() self:SetupNameplateColors() end, colorInit)
    panel:CreateColorPicker(builder, WT.L.OPT_NP_CASTER_COL, WT.L.OPT_DESC_COLOR_VALUE, "Nameplates", "ColCaster", false,
        casterInit, function() self:SetupNameplateColors() end)

    local eliteInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_NP_ELITE, WT.L.OPT_DESC_FRAMES_NP_ELITE, "Nameplates",
        "NameplateElite", function() self:SetupNameplateColors() end, colorInit)
    panel:CreateColorPicker(builder, WT.L.OPT_NP_ELITE_COL, WT.L.OPT_DESC_COLOR_VALUE, "Nameplates", "ColElite", false,
        eliteInit, function() self:SetupNameplateColors() end)

    local threatInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_NP_THREAT, WT.L.OPT_DESC_FRAMES_NP_THREAT,
        "Nameplates", "NameplateThreat", function()
        UpdateThreatColorsCache(); self:SetupNameplateColors()
    end, colorInit)
    panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_NP_THREAT_OVERRIDE,
        WT.L.OPT_DESC_FRAMES_NP_THREAT_OVERRIDE, "Nameplates", "NameplateThreatOverride",
        function() self:SetupNameplateColors() end, threatInit)
    panel:CreateColorPicker(builder, WT.L.OPT_NP_THREAT_SAFE, WT.L.OPT_DESC_COLOR_VALUE, "Nameplates",
        "ColThreatSafe", false, threatInit, function()
        UpdateThreatColorsCache(); self:SetupNameplateColors()
    end)
    panel:CreateColorPicker(builder, WT.L.OPT_NP_THREAT_WARN, WT.L.OPT_DESC_COLOR_VALUE, "Nameplates",
        "ColThreatWarn", false, threatInit, function()
        UpdateThreatColorsCache(); self:SetupNameplateColors()
    end)
    panel:CreateColorPicker(builder, WT.L.OPT_NP_THREAT_DANGER, WT.L.OPT_DESC_COLOR_VALUE,
        "Nameplates", "ColThreatDanger", false, threatInit,
        function()
            UpdateThreatColorsCache(); self:SetupNameplateColors()
        end)

    local npInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_NP_STACKING, WT.L.OPT_DESC_FRAMES_NP_STACKING,
        "Nameplates", "NameplateStacking", function(value) self:UpdateNameplateStacking(value) end)
    panel:CreateSlider(builder, WT.L.OPT_NP_OVERLAP, WT.L.OPT_DESC_NP_OVERLAP, "Nameplates", "NameplateOverlapV", 0.5,
        2.5, 0.1, function() self:UpdateNameplateStacking(WT.DB.Nameplates.NameplateStacking) end, npInit)

    panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_NP_CLAMP, WT.L.OPT_DESC_FRAMES_NP_CLAMP,
        "Nameplates", "ClampNameplates", function(value) self:UpdateNameplateClamp(value) end)
end

function Module:UpdateNameplateClamp(enable)
    local val = enable and "0.08" or "-1"
    if WT.Utils and WT.Utils.Flags then
        WT.Utils.Flags:SetCVar("nameplateOtherTopInset", val)
        WT.Utils.Flags:SetCVar("nameplateOtherBottomInset", val)
    else
        pcall(function() C_CVar.SetCVar("nameplateOtherTopInset", val) end)
        pcall(function() C_CVar.SetCVar("nameplateOtherBottomInset", val) end)
    end
end
