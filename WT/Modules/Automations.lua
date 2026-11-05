local _, WT = ...

WT.Modules.Automations = {}
local Module = WT.Modules.Automations

local SafeBool = WT.Utils.Safety.SafeBool
local SafeNum = WT.Utils.Safety.SafeNum
local Unsecret = WT.Utils.Safety.Unsecret

-- Function to automatically summon a random favorite companion pet
function Module:CheckAndSummonPet()
    if WT.Core.CombatQueue:Add("AutoSummonPet", true, self.CheckAndSummonPet, self) then return end

    local okStealth, rawStealth = pcall(IsStealthed)
    local okVeh, rawVeh = pcall(UnitHasVehicleUI, "player")
    local isStealth = okStealth and SafeBool(rawStealth)
    local hasVeh = okVeh and SafeBool(rawVeh)

    -- Do not summon if stealthed, in a vehicle, or in a pet battle
    local inPetBattle = C_PetBattles and C_PetBattles.IsInBattle()
    if not WT.DB or not WT.DB.Automations then return end
    if WT.DB.Automations.AutoSummonPet and not (okStealth and isStealth) and not (okVeh and hasVeh) and not inPetBattle then
        if C_PetJournal and not C_PetJournal.GetSummonedPetGUID() then
            -- Abort immediately if the Pet Journal has no pets loaded
            if C_PetJournal.GetNumPets() == 0 then return end

            local specificName = WT.DB.Automations.AutoSummonPetName
            if specificName and strtrim(specificName) ~= "" then
                local petNames = {}
                for name in string.gmatch(specificName, "([^,;]+)") do
                    if strtrim(name) ~= "" then table.insert(petNames, strtrim(name)) end
                end

                local matchingPets = {}
                local numPets = C_PetJournal.GetNumPets()
                for i = 1, numPets do
                    local petID, speciesID, owned, customName, level, favorite, isRevoked, speciesName = C_PetJournal
                    .GetPetInfoByIndex(i)
                    if petID and owned then
                        for _, searchName in ipairs(petNames) do
                            local matchC = customName and
                            ((_G.strcmputf8i and _G.strcmputf8i(customName, searchName) == 0) or (string.lower(customName) == string.lower(searchName)))
                            local matchS = speciesName and
                            ((_G.strcmputf8i and _G.strcmputf8i(speciesName, searchName) == 0) or (string.lower(speciesName) == string.lower(searchName)))

                            if matchC or matchS then
                                table.insert(matchingPets, { id = petID, name = customName or speciesName })
                                break
                            end
                        end
                    end
                end

                if #matchingPets > 0 then
                    -- High-entropy index to ensure true randomness without the deprecated math.randomseed API
                    local seed = time() + math.floor(GetTime() * 1000)
                    local randomIndex = (seed % #matchingPets) + 1
                    local randomPet = matchingPets[randomIndex]
                    C_PetJournal.SummonPetByGUID(randomPet.id)
                    WT.Utils.Logger:Debug(WT.L.AUTOMATION_PET_SUMMONED .. " (" .. randomPet.name .. ")")
                    return
                end
            end

            -- Fallback to random favorite if field is empty or pet wasn't found
            C_PetJournal.SummonRandomPet(false)
            WT.Utils.Logger:Debug(WT.L.AUTOMATION_PET_SUMMONED)
        end
    end
end

-- Function to apply or revert the AutoDismount CVar
function Module:UpdateAutoDismount(enable, isSilent)
    if WT.Core.CombatQueue:Add("AutoDismount", isSilent, self.UpdateAutoDismount, self, enable, true) then return end
    if WT.Utils and WT.Utils.Flags then
        WT.Utils.Flags:SetCVar("autoDismount", enable and "1" or "0")
    else
        pcall(function() C_CVar.SetCVar("autoDismount", enable and "1" or "0") end)
    end
end

-- Function to apply or revert the AutoStand CVar
function Module:UpdateAutoStand(enable, isSilent)
    if WT.Core.CombatQueue:Add("AutoStand", isSilent, self.UpdateAutoStand, self, enable, true) then return end
    if WT.Utils and WT.Utils.Flags then
        WT.Utils.Flags:SetCVar("autoStand", enable and "1" or "0")
        WT.Utils.Flags:SetCVar("autoDismountFlying", enable and "1" or "0")
    else
        pcall(function() C_CVar.SetCVar("autoStand", enable and "1" or "0") end)
        pcall(function() C_CVar.SetCVar("autoDismountFlying", enable and "1" or "0") end)
    end
end

-- Function to apply or revert the LootUnderMouse CVar
function Module:UpdateLootUnderMouse(enable, isSilent)
    if WT.Core.CombatQueue:Add("LootUnderMouse", isSilent, self.UpdateLootUnderMouse, self, enable, true) then return end
    if WT.Utils and WT.Utils.Flags then
        WT.Utils.Flags:SetCVar("lootUnderMouse", enable and "1" or "0")
    else
        pcall(function() C_CVar.SetCVar("lootUnderMouse", enable and "1" or "0") end)
    end
end

-- ============================================================================
-- SETUP FUNCTIONS
-- ============================================================================

local function SetupCVarAutomations()
    Module:UpdateAutoDismount(WT.DB.Automations.AutoDismount)
    Module:UpdateAutoStand(WT.DB.Automations.AutoStand)
    Module:UpdateLootUnderMouse(WT.DB.Automations.LootUnderMouse)
end

local function SetupLootAutomations()
    -- FastLoot
    local lastLootTime = 0
    WT.Core.Events:Register("LOOT_READY", function(event, autoLoot)
        if not WT.DB or not WT.DB.Automations or not WT.DB.Automations.FastLoot then return end

        -- autoLoot is true if the client intends to autoloot (e.g. shift was held, or autoLoot is on by default and shift was NOT held).
        if autoLoot then
            -- Throttle to prevent multiple rapid firings from hanging the loot window, but keep it tight so we don't miss AoE loots
            local currentTime = GetTime()
            if currentTime == lastLootTime then return end
            lastLootTime = currentTime

            local numItems = GetNumLootItems()
            if numItems > 0 then
                for i = numItems, 1, -1 do
                    LootSlot(i)
                end
            end
        end
    end)

    -- Easy Delete Hook
    for i = 1, 4 do
        local popup = _G["StaticPopup" .. i]
        local editBox = _G["StaticPopup" .. i .. "EditBox"]
        if not editBox and popup then editBox = popup.editBox or popup.EditBox end
        local wideEditBox = _G["StaticPopup" .. i .. "WideEditBox"]
        if not wideEditBox and popup then wideEditBox = popup.wideEditBox or popup.WideEditBox end

        local function HookEB(eb)
            if eb then
                eb:HookScript("OnShow", function(self)
                    if not WT.DB or not WT.DB.Automations then return end
                    if WT.DB.Automations.EasyDelete then
                        local parent = self:GetParent()
                        if parent and type(parent.which) == "string" then
                            local which = parent.which
                            local text = parent.text and parent.text:GetText() or ""
                            if string.find(which, "DELETE") then
                                self:SetText(DELETE_ITEM_CONFIRM_STRING)
                            elseif string.find(which, "DESTROY") or string.find(text, "ZERSTÖREN") or string.find(text, "DESTROY") then
                                local destroyWord = GetLocale() == "deDE" and "ZERSTÖREN" or "DESTROY"
                                if string.find(text, "ZERSTÖREN") then destroyWord = "ZERSTÖREN" end
                                self:SetText(destroyWord)
                            end
                        end
                    end
                end)
            end
        end

        HookEB(editBox)
        HookEB(wideEditBox)
    end
end

local function SetupCombatAutomations()
    -- Combat Resurrection
    WT.Core.Events:Register("RESURRECT_REQUEST", function()
        if not WT.DB or not WT.DB.Automations then return end
        if WT.DB.Automations.CombatResAuto and InCombatLockdown() then
            local inInstance, instanceType = IsInInstance()
            if instanceType ~= "pvp" and instanceType ~= "arena" then
                C_Timer.After(0.15, function()
                    local clicked = false
                    local fnFind = _G["StaticPopup_FindVisible"]
                    if fnFind then
                        for _, popupName in ipairs({ "RESURRECT_NO_TIMER", "RESURRECT_NO_SICKNESS", "RESURRECT" }) do
                            local popup = fnFind(popupName)
                            if popup then
                                local btn = popup.button1 or popup.Button1
                                if btn and btn:IsVisible() and btn:IsEnabled() then
                                    pcall(function() btn:Click() end)
                                    clicked = true
                                    break
                                end
                            end
                        end
                    end
                    if not clicked then
                        local fnAccept = _G["AcceptResurrect"]
                        if fnAccept then pcall(fnAccept) end
                    end
                end)
            end
        end
    end)

    -- Auto Keystone insertion
    WT.Core.Events:Register("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN", function()
        if not WT.DB or not WT.DB.Automations then return end
        if WT.DB.Automations.AutoKeystone then
            C_Timer.After(0.1, function()
                if InCombatLockdown() then return end
                local fnGetNumSlots = C_Container.GetContainerNumSlots
                local fnGetItemInfo = C_Container.GetContainerItemInfo
                local fnUseItem = C_Container.UseContainerItem

                for bag = 0, 4 do
                    for slot = 1, fnGetNumSlots(bag) do
                        local info = fnGetItemInfo(bag, slot)
                        if info and info.itemID then
                            local link = Unsecret(info.hyperlink)
                            local isKeystone = link and string.match(string.lower(link), "keystone:")
                            if isKeystone then
                                pcall(fnUseItem, bag, slot)
                                if WT.Utils and WT.Utils.Logger then WT.Utils.Logger:Print(WT.L.MSG_KEYSTONE_INSERTED) end
                                return
                            end
                        end
                    end
                end
            end)
        end
    end)
end

local function SetupMiscAutomations()
    -- Auto Reputation Watcher
    WT.Core.Events:Register("CHAT_MSG_COMBAT_FACTION_CHANGE", function(event, arg1)
        if not WT.DB or not WT.DB.Automations then return end
        local safeArg = Unsecret(arg1)
        if WT.DB.Automations.AutoRepWatch and safeArg then
            local ok, factionName = pcall(function()
                local regexDE = "Ruf bei der Fraktion '([^']+)'"
                local regexEN = "Reputation with (.-) increased"
                return string.match(safeArg, regexDE) or string.match(safeArg, regexEN)
            end)

            if ok and factionName then
                pcall(function()
                    for i = 1, C_Reputation.GetNumFactions() do
                        local data = C_Reputation.GetFactionDataByIndex(i)
                        local dName = data and Unsecret(data.name) or nil
                        if dName and dName == factionName then
                            C_Reputation.SetWatchedFactionByIndex(i)
                            break
                        end
                    end
                end)
            end
        end
    end)
end

-- ============================================================================
-- ROGUE POISON REMINDER (Retail & WoW Forever)
-- ============================================================================

local RETAIL_LETHAL = {
    [2823]   = true, -- Deadly Poison
    [315584] = true, -- Instant Poison
    [8679]   = true, -- Wound Poison
    [381664] = true, -- Amplifying Poison
}

local RETAIL_NON_LETHAL = {
    [3408]   = true, -- Crippling Poison
    [381637] = true, -- Atrophic Poison
    [5760]   = true, -- Numbing Poison (Buff ID)
    [5761]   = true, -- Numbing Poison (Spell ID)
}

local function HasWeaponEquipped(slot)
    local itemID = GetInventoryItemID("player", slot)
    if not itemID then return false end
    if slot == 16 then return true end
    local fnGetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or rawget(_G, "GetItem" .. "InfoInstant")
    if fnGetItemInfoInstant then
        local ok, _, _, equipLoc, _, classID = pcall(fnGetItemInfoInstant, itemID)
        if ok and (equipLoc or classID) then
            if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then
                return false
            end
            if equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_2HWEAPON" then
                return true
            end
            if classID == 2 or (Enum and Enum.ItemClass and classID == Enum.ItemClass.Weapon) then
                return true
            end
        end
    end
    return true
end

local function IsSpellKnownCompat(spellID)
    if C_Spell and C_Spell.IsSpellKnown then
        return C_Spell.IsSpellKnown(spellID)
    end
    local fnKnown = rawget(_G, "IsSpell" .. "Known")
    if fnKnown then
        return fnKnown(spellID)
    end
    return false
end

local function GetRetailPoisonStatus()
    local lethalActive, lethalExp, lethalIcon, lethalName = false, 0, nil, nil
    local nonLethalActive, nonLethalExp, nonLethalIcon, nonLethalName = false, 0, nil, nil
    local now = GetTime()

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        -- WoW 11.0+ Secret Aura fix: Querying specific poison spellIDs directly bypasses secret/private auras
        -- and avoids "Auras cannot be accessed when secret while tainted" errors.
        for sID in pairs(RETAIL_LETHAL) do
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sID)
            if ok and aura then
                local exp = (aura.expirationTime and aura.expirationTime > 0) and (aura.expirationTime - now) or 3600
                if not lethalActive or exp < lethalExp then
                    lethalExp = exp
                    lethalIcon = aura.icon
                    lethalName = aura.name
                end
                lethalActive = true
            end
        end

        for sID in pairs(RETAIL_NON_LETHAL) do
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sID)
            if ok and aura then
                local exp = (aura.expirationTime and aura.expirationTime > 0) and (aura.expirationTime - now) or 3600
                if not nonLethalActive or exp < nonLethalExp then
                    nonLethalExp = exp
                    nonLethalIcon = aura.icon
                    nonLethalName = aura.name
                end
                nonLethalActive = true
            end
        end
    elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if ok and aura then
                local sID = aura.spellId
                if sID and RETAIL_LETHAL[sID] then
                    local exp = (aura.expirationTime and aura.expirationTime > 0) and (aura.expirationTime - now) or 3600
                    if not lethalActive or exp < lethalExp then
                        lethalExp = exp
                        lethalIcon = aura.icon
                        lethalName = aura.name
                    end
                    lethalActive = true
                elseif sID and RETAIL_NON_LETHAL[sID] then
                    local exp = (aura.expirationTime and aura.expirationTime > 0) and (aura.expirationTime - now) or 3600
                    if not nonLethalActive or exp < nonLethalExp then
                        nonLethalExp = exp
                        nonLethalIcon = aura.icon
                        nonLethalName = aura.name
                    end
                    nonLethalActive = true
                end
            elseif not ok then
                -- Secret aura encountered at this index; ignore and continue checking other indices
            else
                break
            end
        end
    else
        local fnUnitAura = rawget(_G, "UnitAura")
        if fnUnitAura then
            for i = 1, 40 do
                local ok, name, icon, _, _, _, expirationTime, _, _, _, spellId = pcall(fnUnitAura, "player", i, "HELPFUL")
                if ok and name then
                    if spellId and RETAIL_LETHAL[spellId] then
                        local exp = (expirationTime and expirationTime > 0) and (expirationTime - now) or 3600
                        if not lethalActive or exp < lethalExp then
                            lethalExp = exp
                            lethalIcon = icon
                            lethalName = name
                        end
                        lethalActive = true
                    elseif spellId and RETAIL_NON_LETHAL[spellId] then
                        local exp = (expirationTime and expirationTime > 0) and (expirationTime - now) or 3600
                        if not nonLethalActive or exp < nonLethalExp then
                            nonLethalExp = exp
                            nonLethalIcon = icon
                            nonLethalName = name
                        end
                        nonLethalActive = true
                    end
                elseif not ok then
                    -- Ignore protected aura error and continue
                else
                    break
                end
            end
        end
    end

    return lethalActive, lethalExp, lethalIcon, lethalName, nonLethalActive, nonLethalExp, nonLethalIcon, nonLethalName
end

local function FormatPoisonTime(seconds)
    if not seconds or seconds <= 0 then return "!" end
    if seconds >= 3600 then
        return string.format("%dh", math.floor(seconds / 3600))
    elseif seconds >= 60 then
        return string.format("%dm", math.floor(seconds / 60))
    else
        return string.format("%ds", math.floor(seconds))
    end
end

local function CreatePoisonReminderFrame()
    if Module.poisonFrame then return Module.poisonFrame end

    local f = CreateFrame("Frame", "WTRoguePoisonReminder", _G["WT_UIContainer"] or UIParent, "BackdropTemplate")
    f:SetSize(86, 46)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    f:SetBackdropColor(WT.Colors.STD_BG_R or 0.05, WT.Colors.STD_BG_G or 0.05, WT.Colors.STD_BG_B or 0.05, 0.88)
    f:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)

    local function GetCenterCoords()
        local okC, cX, cY = pcall(f.GetCenter, f)
        local okU, uX, uY = pcall(UIParent.GetCenter, UIParent)

        cX = (okC and cX) and SafeNum(cX) or 0
        cY = (okC and cY) and SafeNum(cY) or 0
        uX = (okU and uX) and SafeNum(uX) or 0
        uY = (okU and uY) and SafeNum(uY) or 0

        local s = f:GetEffectiveScale() or 1
        local u = UIParent:GetEffectiveScale() or 1
        if s > 0 and u > 0 then
            return ((cX * s) - (uX * u)) / s, ((cY * s) - (uY * u)) / s
        end
        return (cX - uX), (cY - uY)
    end

    local function SavePosition(overrideX, overrideY)
        if not WT.DB.Internal.Positions then WT.DB.Internal.Positions = {} end
        local x = overrideX
        local y = overrideY
        if not x or not y then
            x, y = GetCenterCoords()
        end
        WT.DB.Internal.Positions["WTRoguePoisonReminder"] = {
            point = "CENTER",
            relativeTo = "UIParent",
            relativePoint = "CENTER",
            xOfs = x,
            yOfs = y,
        }
    end

    local function UpdateCoordsDisplay()
        if not f.editOverlay or not f.editOverlay.coordText then return end
        local x, y = GetCenterCoords()
        f.editOverlay.coordText:SetText(string.format("X: %.0f | Y: %.0f", x, y))
    end
    f.UpdateCoordsDisplay = UpdateCoordsDisplay

    local function OnDragStart(self)
        if IsAltKeyDown() or f.isPreview then
            f.isMovingNow = true
            f:StartMoving()
        end
    end
    local function OnDragStop(self)
        f.isMovingNow = false
        f:StopMovingOrSizing()
        local curX, curY = GetCenterCoords()
        f:ClearAllPoints()
        f:SetPoint("CENTER", _G["WT_UIContainer"] or UIParent, "CENTER", curX, curY)
        SavePosition(curX, curY)
        UpdateCoordsDisplay()
    end
    local function OnMouseUp(self, button)
        if f.isPreview then
            if button == "RightButton" then
                Module:TogglePoisonReminderPreview()
            elseif button == "MiddleButton" then
                Module:ResetRoguePoisonPosition()
            end
        end
    end

    f:SetScript("OnDragStart", OnDragStart)
    f:SetScript("OnDragStop", OnDragStop)
    f:SetScript("OnMouseUp", OnMouseUp)

    local editOverlay = CreateFrame("Frame", "WTRoguePoisonEditOverlay", f, "BackdropTemplate")
    editOverlay:SetSize(260, 114)
    editOverlay:SetPoint("CENTER", f, "CENTER", 0, 0)
    editOverlay:SetFrameStrata("MEDIUM")
    editOverlay:SetFrameLevel(math.max(1, f:GetFrameLevel() - 1))
    editOverlay:EnableMouse(true)
    editOverlay:RegisterForDrag("LeftButton")
    editOverlay:SetScript("OnDragStart", OnDragStart)
    editOverlay:SetScript("OnDragStop", OnDragStop)
    editOverlay:SetScript("OnMouseUp", OnMouseUp)

    editOverlay:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    editOverlay:SetBackdropColor(WT.Colors.STD_BG_R or 0.05, WT.Colors.STD_BG_G or 0.05, WT.Colors.STD_BG_B or 0.05, WT.Colors.STD_BG_A or 0.9)
    editOverlay:SetBackdropBorderColor(WT.Colors.PRIMARY_R or 0, WT.Colors.PRIMARY_G or 1, WT.Colors.PRIMARY_B or 1, 0.8)

    local title = editOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", editOverlay, "TOP", 0, -8)
    title:SetText(WT.L.GROUP_ROGUE_POISONS)
    editOverlay.text = title

    local subText = editOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subText:SetPoint("TOP", editOverlay, "TOP", 0, -25)
    subText:SetTextColor(WT.Colors.PRIMARY_R or 0, WT.Colors.PRIMARY_G or 1, WT.Colors.PRIMARY_B or 1, 1)
    subText:SetText(WT.L.LBL_ALERT_HINT_CLOSE)
    editOverlay.subText = subText

    local coordText = editOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    coordText:SetPoint("BOTTOM", editOverlay, "BOTTOM", 0, 8)
    coordText:SetTextColor(1, 1, 1, 1)
    editOverlay.coordText = coordText

    local function CreateNudgeBtn(name, txt, point, relPoint, x, y, nudgeX, nudgeY)
        local btn = CreateFrame("Button", name, editOverlay, "BackdropTemplate")
        btn:SetSize(24, 24)
        btn:SetPoint(point, editOverlay, relPoint, x, y)
        btn:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        btn:SetBackdropColor(WT.Colors.STD_BG_R or 0.05, WT.Colors.STD_BG_G or 0.05, WT.Colors.STD_BG_B or 0.05, WT.Colors.STD_BG_A or 0.9)
        btn:SetBackdropBorderColor(WT.Colors.PRIMARY_R or 0, WT.Colors.PRIMARY_G or 1, WT.Colors.PRIMARY_B or 1, 0.8)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("CENTER", 1, -1)
        lbl:SetText(txt)

        btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 1, 1, 1) end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(WT.Colors.PRIMARY_R or 0, WT.Colors.PRIMARY_G or 1, WT.Colors.PRIMARY_B or 1, 0.8)
        end)

        btn:SetScript("OnClick", function()
            local step = IsShiftKeyDown() and 10 or 1
            local curX, curY = GetCenterCoords()
            local newX = curX + (nudgeX * step)
            local newY = curY + (nudgeY * step)

            f:ClearAllPoints()
            f:SetPoint("CENTER", _G["WT_UIContainer"] or UIParent, "CENTER", newX, newY)
            SavePosition(newX, newY)
            UpdateCoordsDisplay()
        end)
        return btn
    end

    CreateNudgeBtn("WTRoguePoison_NudgeUp", "^", "BOTTOM", "TOP", 0, 2, 0, 1)
    CreateNudgeBtn("WTRoguePoison_NudgeDown", "v", "TOP", "BOTTOM", 0, -2, 0, -1)
    CreateNudgeBtn("WTRoguePoison_NudgeLeft", "<", "RIGHT", "LEFT", -2, 0, -1, 0)
    CreateNudgeBtn("WTRoguePoison_NudgeRight", ">", "LEFT", "RIGHT", 2, 0, 1, 0)

    editOverlay:Hide()
    editOverlay:SetScript("OnShow", UpdateCoordsDisplay)
    f.editOverlay = editOverlay

    local function CreateSlot(index, xOffset)
        local slot = CreateFrame("Button", nil, f, "BackdropTemplate")
        slot:SetSize(34, 34)
        slot:SetPoint("TOPLEFT", f, "TOPLEFT", xOffset, -6)
        slot:EnableMouse(true)
        slot:RegisterForDrag("LeftButton")
        slot:RegisterForClicks("AnyUp")
        slot:SetScript("OnDragStart", OnDragStart)
        slot:SetScript("OnDragStop", OnDragStop)
        slot:SetScript("OnMouseUp", OnMouseUp)

        slot:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 10,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        slot:SetBackdropColor(0, 0, 0, 0.6)
        slot:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.8)

        local icon = slot:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", -2, 2)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slot.icon = icon

        local glow = slot:CreateTexture(nil, "OVERLAY")
        glow:SetAllPoints(icon)
        glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        glow:SetBlendMode("ADD")
        glow:Hide()
        slot.glow = glow

        local ag = glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local alpha = ag:CreateAnimation("Alpha")
        alpha:SetFromAlpha(0.25)
        alpha:SetToAlpha(1.0)
        alpha:SetDuration(0.55)
        slot.ag = ag

        local tag = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tag:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        tag:SetPoint("TOP", slot, "TOP", 0, -3)
        tag:SetTextColor(0.85, 0.85, 0.85, 0.9)
        slot.tag = tag

        local timeText = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timeText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        timeText:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -2, 2)
        timeText:SetTextColor(1, 1, 1)
        slot.timeText = timeText

        slot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            if f.isPreview then
                GameTooltip:AddLine("WT: " .. (WT.L.GROUP_ROGUE_POISONS),
                    WT.Colors.PRIMARY_R or 0, WT.Colors.PRIMARY_G or 1, WT.Colors.PRIMARY_B or 1)
                GameTooltip:AddLine(WT.L.BTN_DESC_POISON_PREVIEW, 1, 1, 1)
                GameTooltip:AddLine(WT.L.LBL_ALERT_HINT_CLOSE,
                    WT.Colors.PRIMARY_R or 0, WT.Colors.PRIMARY_G or 1, WT.Colors.PRIMARY_B or 1)
            else
                local title = self.poisonTitle or
                (index == 1 and (WT.L.LBL_ROGUE_POISON_LETHAL) or (WT.L.LBL_ROGUE_POISON_NON_LETHAL))
                GameTooltip:AddLine(title, 1, 1, 1)
                if self.isMissing then
                    GameTooltip:AddLine("|cFFFF2020" .. (WT.L.LBL_ROGUE_POISON_MISSING) .. "!|r")
                elseif self.isExpiring then
                    GameTooltip:AddLine("|cFFFFA500" ..
                    (WT.L.LBL_ROGUE_POISON_EXPIRING) .. " (" .. (self.formattedTime or "") .. ")|r")
                else
                    GameTooltip:AddLine("|cFF20FF20" ..
                    (WT.L.LBL_ROGUE_POISON_ACTIVE) .. " (" .. (self.formattedTime or "") .. ")|r")
                end
                GameTooltip:AddLine("|cFF777777" .. (WT.L.LBL_POISON_MOVE_HINT) .. "|r", 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        return slot
    end

    f.slot1 = CreateSlot(1, 6)
    f.slot2 = CreateSlot(2, 46)

    if WT.DB and WT.DB.Internal and WT.DB.Internal.Positions and WT.DB.Internal.Positions["WTRoguePoisonReminder"] then
        local p = WT.DB.Internal.Positions["WTRoguePoisonReminder"]
        f:ClearAllPoints()
        f:SetPoint(p.point, _G["WT_UIContainer"] or UIParent, p.relativePoint, p.xOfs, p.yOfs)
    else
        f:ClearAllPoints()
        f:SetPoint("CENTER", _G["WT_UIContainer"] or UIParent, "CENTER", 0, 0)
    end

    local scale = (WT.DB and WT.DB.Automations and WT.DB.Automations.RoguePoisonScale) or 1.0
    f:SetScale(scale)

    local updateTimer = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        if f.isPreview then
            if f.isMovingNow then
                UpdateCoordsDisplay()
            end
        else
            updateTimer = updateTimer + elapsed
            if updateTimer >= 1.0 then
                updateTimer = 0
                Module:UpdateRoguePoisonStatus()
            end
        end
    end)

    f:Hide()
    Module.poisonFrame = f
    return f
end

function Module:ApplyRoguePoisonScale(scale)
    if not self.poisonFrame then return end
    local s = scale or (WT.DB and WT.DB.Automations and WT.DB.Automations.RoguePoisonScale) or 1.0
    self.poisonFrame:SetScale(s)
end

function Module:ResetRoguePoisonPosition()
    if WT.DB and WT.DB.Internal and WT.DB.Internal.Positions then
        WT.DB.Internal.Positions["WTRoguePoisonReminder"] = nil
    end

    local f = self.poisonFrame
    if not f then
        f = CreatePoisonReminderFrame()
    end

    if f then
        f:ClearAllPoints()
        f:SetPoint("CENTER", _G["WT_UIContainer"] or UIParent, "CENTER", 0, 0)
    end

    if WT.Utils and WT.Utils.Logger then
        WT.Utils.Logger:Print(WT.L.MSG_ROGUE_POISONS_POS_RESET)
    end
end

local wasInWarningState = false
local lastZoneTransitionTime = 0
local lastKnownPoisonsActive = false
local pendingMissingAlertTimer = nil
local zoneTransitionTimer = nil

local function CheckAndPlayMissingAlert(forcePlay, requireMissingOnly)
    if not forcePlay and (not WT.DB or not WT.DB.Automations or not WT.DB.Automations.RoguePoisonReminder) then return end
    if not forcePlay and WT.DB.Automations.RoguePoisonInstanceOnly and not IsInInstance() then return end

    -- Suppress alerts during loading screens and zone transitions (aura/enchant tables take 2-3s to populate)
    if not forcePlay then
        local now = GetTime()
        local loadElapsed = now - (WT.Core.LoadTime or 0)
        local zoneElapsed = now - (lastZoneTransitionTime or 0)
        if loadElapsed < 3.0 or zoneElapsed < 3.0 then
            return
        end
    end

    local hasMissing = false
    local hasExpiring = false
    local isRetail = WT.Compat and WT.Compat.IsRetail
    local lvl = UnitLevel("player") or 1
    local threshold = (WT.DB.Automations.RoguePoisonThreshold or 5) * 60

    if isRetail then
        local reqLethal = (lvl >= 10)
        local reqNonLethal = (lvl >= 14)
        local lAct, lExp, _, _, nlAct, nlExp, _, _ = GetRetailPoisonStatus()
        if reqLethal then
            if not lAct then
                hasMissing = true
            elseif lExp <= threshold then
                hasExpiring = true
            end
        end
        if reqNonLethal then
            if not nlAct then
                hasMissing = true
            elseif nlExp <= threshold then
                hasExpiring = true
            end
        end
    else
        local knowsPoisons = IsSpellKnownCompat(2842) or (lvl >= 20)
        if knowsPoisons then
            local hasMHWeap = HasWeaponEquipped(16)
            local hasOHWeap = HasWeaponEquipped(17)
            local hasMH, mhExp, _, _, hasOH, ohExp, _, _ = GetWeaponEnchantInfo()
            local mhTime = hasMH and ((mhExp or 0) / 1000) or 0
            local ohTime = hasOH and ((ohExp or 0) / 1000) or 0
            if hasMHWeap then
                if not hasMH then
                    hasMissing = true
                elseif mhTime <= threshold then
                    hasExpiring = true
                end
            end
            if hasOHWeap then
                if not hasOH then
                    hasMissing = true
                elseif ohTime <= threshold then
                    hasExpiring = true
                end
            end
        end
    end

    -- When entering combat or on ready check, ONLY alert if poisons are completely MISSING!
    -- Expiring poisons are already visibly ticking down on the HUD and must not spam audio on every mob pull.
    if requireMissingOnly and not hasMissing then
        return
    end

    local anyWarning = hasMissing or hasExpiring
    if anyWarning or forcePlay then
        if WT.DB.Automations.RoguePoisonAudio ~= false then
            local sName = WT.DB.Automations.RoguePoisonSound or "W1LD - 05"
            local chan = WT.DB.Automations.RoguePoisonSoundChannel or "Master"
            if WT.Utils and WT.Utils.Audio then
                local cdKey = forcePlay and "PREVIEW" or "ROGUE_POISON"
                WT.Utils.Audio:Play(sName, cdKey, chan)
            end
        end
        if anyWarning and WT.DB.Automations.RoguePoisonChat then
            if WT.Utils and WT.Utils.Logger then
                local msgText, col
                if hasMissing and hasExpiring then
                    msgText = WT.L.MSG_ROGUE_POISONS_MISSING_EXPIRING
                    col = "|cFFFF2020"
                elseif hasMissing then
                    msgText = WT.L.MSG_ROGUE_POISONS_MISSING
                    col = "|cFFFF2020"
                elseif hasExpiring then
                    msgText = WT.L.MSG_ROGUE_POISONS_EXPIRING
                    col = "|cFFFF9900"
                end
                if msgText then
                    WT.Utils.Logger:Print(col .. msgText .. "|r")
                end
            end
        end
    end
end

local function UpdateSlotVisual(slot, isRequired, isActive, timeLeft, iconID, name, tagText, threshold)
    slot.poisonTitle = name
    slot.formattedTime = FormatPoisonTime(timeLeft)
    slot.tag:SetText(tagText)

    if not isRequired then
        slot:SetAlpha(0.25)
        slot.icon:SetTexture(iconID)
        slot.icon:SetDesaturated(true)
        slot.timeText:SetText("")
        slot.ag:Stop()
        slot.glow:Hide()
        slot:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.5)
        slot.isMissing = false
        slot.isExpiring = false
        return false
    end

    slot:SetAlpha(1.0)
    slot.icon:SetTexture(iconID)

    if not isActive then
        slot.isMissing = true
        slot.isExpiring = false
        slot.icon:SetDesaturated(true)
        slot.timeText:SetText("!")
        slot.timeText:SetTextColor(1.0, 0.2, 0.2)
        slot:SetBackdropBorderColor(1.0, 0.15, 0.15, 1.0)
        slot.glow:SetVertexColor(1.0, 0.1, 0.1, 0.85)
        slot.glow:Show()
        if not slot.ag:IsPlaying() then slot.ag:Play() end
        return true
    elseif timeLeft <= threshold then
        slot.isMissing = false
        slot.isExpiring = true
        slot.icon:SetDesaturated(false)
        slot.timeText:SetText(FormatPoisonTime(timeLeft))
        slot.timeText:SetTextColor(1.0, 0.75, 0.1)
        slot:SetBackdropBorderColor(1.0, 0.6, 0.0, 1.0)
        slot.glow:SetVertexColor(1.0, 0.65, 0.0, 0.75)
        slot.glow:Show()
        if not slot.ag:IsPlaying() then slot.ag:Play() end
        return true
    else
        slot.isMissing = false
        slot.isExpiring = false
        slot.icon:SetDesaturated(false)
        slot.timeText:SetText(FormatPoisonTime(timeLeft))
        slot.timeText:SetTextColor(0.25, 1.0, 0.25)
        slot:SetBackdropBorderColor(0.2, 0.5, 0.2, 0.8)
        slot.ag:Stop()
        slot.glow:Hide()
        return false
    end
end

function Module:UpdateRoguePoisonStatus()
    local f = self.poisonFrame
    if not f then return end

    if f.isPreview then
        f:Show()
        if f.editOverlay then
            f.editOverlay:Show()
            if f.UpdateCoordsDisplay then f.UpdateCoordsDisplay() end
        end
        f:SetBackdropBorderColor(0, 0, 0, 0)
        f:SetBackdropColor(0, 0, 0, 0)
        f.slot1:SetAlpha(1.0)
        f.slot1.icon:SetTexture(132273)
        f.slot1.icon:SetDesaturated(false)
        f.slot1.timeText:SetText("32m")
        f.slot1.timeText:SetTextColor(0.25, 1.0, 0.25)
        f.slot1.tag:SetText(WT.Compat and WT.Compat.IsRetail and "LETH" or "MH")
        f.slot1.glow:Hide()
        f.slot1.ag:Stop()
        f.slot1:SetBackdropBorderColor(0.2, 0.5, 0.2, 0.8)

        f.slot2:SetAlpha(1.0)
        f.slot2.icon:SetTexture(132275)
        f.slot2.icon:SetDesaturated(false)
        f.slot2.timeText:SetText("4m")
        f.slot2.timeText:SetTextColor(1.0, 0.75, 0.1)
        f.slot2.tag:SetText(WT.Compat and WT.Compat.IsRetail and "UTIL" or "OH")
        f.slot2.glow:SetVertexColor(1.0, 0.65, 0.0, 0.75)
        f.slot2.glow:Show()
        if not f.slot2.ag:IsPlaying() then f.slot2.ag:Play() end
        f.slot2:SetBackdropBorderColor(1.0, 0.6, 0.0, 1.0)
        return
    end

    if f.editOverlay then
        f.editOverlay:Hide()
    end
    f:SetBackdropColor(WT.Colors.STD_BG_R or 0.05, WT.Colors.STD_BG_G or 0.05, WT.Colors.STD_BG_B or 0.05, 0.88)

    if not WT.DB or not WT.DB.Automations or not WT.DB.Automations.RoguePoisonReminder then
        wasInWarningState = false
        f:Hide()
        return
    end

    -- Suppression checks
    if UnitIsDeadOrGhost("player") then
        f:Hide(); return
    end
    if UnitOnTaxi("player") then
        f:Hide(); return
    end
    local okVeh, rawVeh = pcall(UnitHasVehicleUI, "player")
    if okVeh and SafeBool(rawVeh) then
        f:Hide(); return
    end
    if C_PetBattles and C_PetBattles.IsInBattle() then
        f:Hide(); return
    end

    if WT.DB.Automations.RoguePoisonInstanceOnly then
        local inInstance = IsInInstance()
        if not inInstance then
            f:Hide(); return
        end
    end

    local isRetail = WT.Compat and WT.Compat.IsRetail
    local threshold = (WT.DB.Automations.RoguePoisonThreshold or 5) * 60
    local lvl = UnitLevel("player") or 1

    local req1, act1, time1, icon1, name1, tag1
    local req2, act2, time2, icon2, name2, tag2

    if isRetail then
        req1 = (lvl >= 10)
        req2 = (lvl >= 14)
        local lAct, lExp, lIcon, lName, nlAct, nlExp, nlIcon, nlName = GetRetailPoisonStatus()

        act1 = lAct
        time1 = lExp
        icon1 = lIcon or 132273
        name1 = lName or (WT.L.LBL_ROGUE_POISON_LETHAL)
        tag1 = "LETH"

        act2 = nlAct
        time2 = nlExp
        icon2 = nlIcon or 132275
        name2 = nlName or (WT.L.LBL_ROGUE_POISON_NON_LETHAL)
        tag2 = "UTIL"
    else
        local knowsPoisons = IsSpellKnownCompat(2842) or (lvl >= 20)
        local hasMHWeap = HasWeaponEquipped(16)
        local hasOHWeap = HasWeaponEquipped(17)
        local hasMH, mhExp, _, _, hasOH, ohExp, _, _ = GetWeaponEnchantInfo()

        req1 = knowsPoisons and hasMHWeap
        act1 = hasMH
        time1 = hasMH and ((mhExp or 0) / 1000) or 0
        icon1 = 132273
        name1 = WT.L.LBL_ROGUE_POISON_MH
        tag1 = "MH"

        req2 = knowsPoisons and hasOHWeap
        act2 = hasOH
        time2 = hasOH and ((ohExp or 0) / 1000) or 0
        icon2 = 132275
        name2 = WT.L.LBL_ROGUE_POISON_OH
        tag2 = "OH"
    end

    local warn1 = UpdateSlotVisual(f.slot1, req1, act1, time1, icon1, name1, tag1, threshold)
    local warn2 = UpdateSlotVisual(f.slot2, req2, act2, time2, icon2, name2, tag2, threshold)

    local isAnyMissing = (f.slot1.isMissing or f.slot2.isMissing)
    local isAnyExpiring = (f.slot1.isExpiring or f.slot2.isExpiring)
    local anyWarn = warn1 or warn2

    if anyWarn then
        local now = GetTime()
        local inTransition = (now - (WT.Core.LoadTime or 0) < 3.0) or (now - lastZoneTransitionTime < 3.0)

        -- If poisons were fully active right before this zone transition and now appear missing during zoning,
        -- suppress the transient drop while the client re-synchronizes the player's aura/enchant tables.
        if inTransition and lastKnownPoisonsActive and isAnyMissing and not isAnyExpiring and not f.isPreview then
            return
        end

        f:Show()
        if isAnyMissing then
            f:SetBackdropBorderColor(1.0, 0.15, 0.15, 0.95)
        else
            f:SetBackdropBorderColor(1.0, 0.6, 0.0, 0.95)
        end

        local currentWarningType
        if isAnyMissing and isAnyExpiring then
            currentWarningType = "MISSING_AND_EXPIRING"
        elseif isAnyMissing then
            currentWarningType = "MISSING"
        elseif isAnyExpiring then
            currentWarningType = "EXPIRING"
        end

        if wasInWarningState ~= currentWarningType and not f.isPreview then
            if wasInWarningState == false and currentWarningType == "MISSING" then
                -- Debounce sudden drop from fully active to missing (prevents 1-frame zone boundary drops)
                if pendingMissingAlertTimer then pendingMissingAlertTimer:Cancel() end
                pendingMissingAlertTimer = C_Timer.NewTimer(1.2, function()
                    pendingMissingAlertTimer = nil
                    if Module.UpdateRoguePoisonStatus then
                        wasInWarningState = currentWarningType
                        CheckAndPlayMissingAlert()
                    end
                end)
            else
                if pendingMissingAlertTimer then
                    pendingMissingAlertTimer:Cancel()
                    pendingMissingAlertTimer = nil
                end
                wasInWarningState = currentWarningType
                CheckAndPlayMissingAlert()
            end
        end
    else
        if pendingMissingAlertTimer then
            pendingMissingAlertTimer:Cancel()
            pendingMissingAlertTimer = nil
        end
        wasInWarningState = false
        lastKnownPoisonsActive = true
        f:Hide()
        local nextCheck = 300
        if req1 and act1 and time1 > threshold then nextCheck = math.min(nextCheck, time1 - threshold + 1) end
        if req2 and act2 and time2 > threshold then nextCheck = math.min(nextCheck, time2 - threshold + 1) end
        C_Timer.After(math.max(1, nextCheck), function()
            if Module.UpdateRoguePoisonStatus then Module:UpdateRoguePoisonStatus() end
        end)
    end
end

function Module:TogglePoisonReminderPreview()
    if not self.poisonFrame then
        CreatePoisonReminderFrame()
    end
    if not self.poisonFrame then return end
    self.poisonFrame.isPreview = not self.poisonFrame.isPreview
    if self.poisonFrame.isPreview then
        CheckAndPlayMissingAlert(true)
    end
    self:UpdateRoguePoisonStatus()
end

local function SetupRoguePoisonReminder()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "ROGUE" then return end

    CreatePoisonReminderFrame()

    WT.Core.Events:Register("UNIT_AURA", function(event, unit)
        if unit == "player" then Module:UpdateRoguePoisonStatus() end
    end)
    WT.Core.Events:Register("UNIT_INVENTORY_CHANGED", function(event, unit)
        if unit == "player" then Module:UpdateRoguePoisonStatus() end
    end)
    WT.Core.Events:Register("PLAYER_EQUIPMENT_CHANGED", function()
        Module:UpdateRoguePoisonStatus()
    end)
    local function OnZoneTransition()
        lastZoneTransitionTime = GetTime()
        if zoneTransitionTimer then
            zoneTransitionTimer:Cancel()
            zoneTransitionTimer = nil
        end
        zoneTransitionTimer = C_Timer.NewTimer(2.5, function()
            zoneTransitionTimer = nil
            if Module.UpdateRoguePoisonStatus then
                Module:UpdateRoguePoisonStatus()
            end
        end)
    end

    WT.Core.Events:Register("ZONE_CHANGED_NEW_AREA", OnZoneTransition)
    WT.Core.Events:Register("ZONE_CHANGED", OnZoneTransition)
    WT.Core.Events:Register("PLAYER_ENTERING_WORLD", function()
        OnZoneTransition()
    end)
    WT.Core.Events:Register("PLAYER_REGEN_DISABLED", function()
        CheckAndPlayMissingAlert(false, true)
    end)
    WT.Core.Events:Register("READY_CHECK", function()
        CheckAndPlayMissingAlert(false, true)
    end)

    pcall(function()
        WT.Core.Events:Register("WEAPON_ENCHANT_CHANGED", function()
            Module:UpdateRoguePoisonStatus()
        end)
    end)

    C_Timer.After(2.5, function() Module:UpdateRoguePoisonStatus() end)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function Module:Initialize()
    if not WT.DB.Modules.Automations then return end

    WT.Utils.Logger:Debug(WT.L.MODULE_AUTOMATIONS_INITIALIZED)

    SetupCVarAutomations()
    SetupLootAutomations()
    SetupCombatAutomations()
    SetupMiscAutomations()
    SetupRoguePoisonReminder()
end

WT.Core.Events:Register("PLAYER_LOGIN", function()
    Module:Initialize()

    -- Triggers ONLY on login, reload, and zone changes to save resources (delayed to avoid 'must be standing' errors)
    WT.Core.Events:Register("PLAYER_ENTERING_WORLD",
        function() C_Timer.After(12, function() Module:CheckAndSummonPet() end) end)
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

    panel:CreateTitle(builder, WT.L.GROUP_CHARACTER)
    AddDescription(WT.L.OPT_DESC_GROUP_CHARACTER)

    panel:CreateCheckbox(builder, WT.L.OPT_AUTO_DISMOUNT, WT.L.OPT_DESC_AUTO_DISMOUNT, "Automations", "AutoDismount",
        function(value) self:UpdateAutoDismount(value) end)
    panel:CreateCheckbox(builder, WT.L.OPT_AUTO_STAND, WT.L.OPT_DESC_AUTO_STAND, "Automations", "AutoStand",
        function(value) self:UpdateAutoStand(value) end)

    local petInit = panel:CreateCheckbox(builder, WT.L.OPT_AUTO_SUMMON_PET, WT.L.OPT_DESC_AUTO_SUMMON_PET, "Automations",
        "AutoSummonPet")
    panel:CreateEditBox(builder, WT.L.OPT_AUTO_SUMMON_PET_NAME, WT.L.OPT_DESC_AUTO_SUMMON_PET_NAME, "Automations",
        "AutoSummonPetName", petInit)

    panel:CreateTitle(builder, WT.L.GROUP_ROGUE_POISONS)
    local _, playerClass = UnitClass("player")
    local isRogue = (playerClass == "ROGUE")
    local classSuffix = not isRogue and (" |cFF888888" .. (WT.L.LBL_ROGUE_ONLY) .. "|r") or ""
    AddDescription((WT.L.OPT_DESC_GROUP_ROGUE_POISONS) ..
    classSuffix)

    local poisonInit = panel:CreateCheckbox(builder, WT.L.OPT_ROGUE_POISON_REMINDER, WT.L.OPT_DESC_ROGUE_POISON_REMINDER,
        "Automations", "RoguePoisonReminder", function(value)
        if self.UpdateRoguePoisonStatus then self:UpdateRoguePoisonStatus() end
    end)
    panel:CreateSlider(builder, WT.L.OPT_ROGUE_POISON_THRESHOLD, WT.L.OPT_DESC_ROGUE_POISON_THRESHOLD, "Automations",
        "RoguePoisonThreshold", 1, 30, 1, function(value)
        if self.UpdateRoguePoisonStatus then self:UpdateRoguePoisonStatus() end
    end, poisonInit)
    panel:CreateSlider(builder, WT.L.OPT_ROGUE_POISON_SCALE, WT.L.OPT_DESC_ROGUE_POISON_SCALE, "Automations",
        "RoguePoisonScale", 0.5, 2.0, 0.05, function(val)
        if self.ApplyRoguePoisonScale then self:ApplyRoguePoisonScale(val) end
    end, poisonInit)
    local audioInit = panel:CreateCheckbox(builder, WT.L.OPT_ROGUE_POISON_AUDIO, WT.L.OPT_DESC_ROGUE_POISON_AUDIO,
        "Automations", "RoguePoisonAudio", nil, poisonInit)
    panel:CreateSoundDropdown(builder, WT.L.OPT_ROGUE_POISON_SOUND, WT.L.OPT_DESC_ROGUE_POISON_SOUND, "Automations",
        "RoguePoisonSound", audioInit)
    panel:CreateCheckbox(builder, WT.L.OPT_ROGUE_POISON_CHAT, WT.L.OPT_DESC_ROGUE_POISON_CHAT, "Automations",
        "RoguePoisonChat", nil, poisonInit)
    panel:CreateCheckbox(builder, WT.L.OPT_ROGUE_POISON_INSTANCE_ONLY, WT.L.OPT_DESC_ROGUE_POISON_INSTANCE_ONLY,
        "Automations", "RoguePoisonInstanceOnly", function(value)
        if self.UpdateRoguePoisonStatus then self:UpdateRoguePoisonStatus() end
    end, poisonInit)
    panel:CreateButton(builder, "", WT.L.BTN_POISON_PREVIEW,
        WT.L.BTN_DESC_POISON_PREVIEW, function()
        if self.TogglePoisonReminderPreview then self:TogglePoisonReminderPreview() end
    end, poisonInit)
    panel:CreateButton(builder, "", WT.L.BTN_RESET_POISON_POS,
        WT.L.DESC_RESET_POISON_POS, function()
        if self.ResetRoguePoisonPosition then self:ResetRoguePoisonPosition() end
    end, poisonInit)

    panel:CreateTitle(builder, WT.L.GROUP_AUTO_MISC)
    AddDescription(WT.L.OPT_DESC_GROUP_AUTO_MISC)

    panel:CreateCheckbox(builder, WT.L.OPT_AUTO_KEYSTONE, WT.L.OPT_DESC_AUTO_KEYSTONE, "Automations", "AutoKeystone")
    panel:CreateCheckbox(builder, WT.L.OPT_AUTO_COMBATRES, WT.L.OPT_DESC_AUTO_COMBATRES, "Automations", "CombatResAuto")
    panel:CreateCheckbox(builder, WT.L.OPT_AUTO_REPWATCH, WT.L.OPT_DESC_AUTO_REPWATCH, "Automations", "AutoRepWatch")

    panel:CreateTitle(builder, WT.L.GROUP_LOOTING)
    AddDescription(WT.L.OPT_DESC_GROUP_LOOTING)

    panel:CreateCheckbox(builder, WT.L.OPT_AUTO_FAST_LOOT, WT.L.OPT_DESC_AUTO_FAST_LOOT, "Automations", "FastLoot")
    panel:CreateCheckbox(builder, WT.L.OPT_AUTO_LOOT_MOUSE, WT.L.OPT_DESC_AUTO_LOOT_MOUSE, "Automations",
        "LootUnderMouse", function(value) self:UpdateLootUnderMouse(value) end)
    panel:CreateCheckbox(builder, WT.L.OPT_AUTO_EASY_DELETE, WT.L.OPT_DESC_AUTO_EASY_DELETE, "Automations", "EasyDelete")
end
