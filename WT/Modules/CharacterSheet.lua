local _, WT = ...

WT.Modules.CharacterSheet = {}
local Module = WT.Modules.CharacterSheet

local GetInventoryItemDurability = _G["GetInventoryItemDurability"]
local GetInventoryItemLink = _G["GetInventoryItemLink"]

local ilvlSlots = {
    [1] = "Head",
    [2] = "Neck",
    [3] = "Shoulder",
    [5] = "Chest",
    [6] = "Waist",
    [7] = "Legs",
    [8] = "Feet",
    [9] = "Wrist",
    [10] = "Hands",
    [11] = "Finger0",
    [12] = "Finger1",
    [13] = "Trinket0",
    [14] = "Trinket1",
    [15] = "Back",
    [16] = "MainHand",
    [17] = "SecondaryHand",
    [18] = "Ranged"
}

local slotSides = {
    [1] = "LEFT",
    [2] = "LEFT",
    [3] = "LEFT",
    [5] = "LEFT",
    [9] = "LEFT",
    [15] = "LEFT",
    [6] = "RIGHT",
    [7] = "RIGHT",
    [8] = "RIGHT",
    [10] = "RIGHT",
    [11] = "RIGHT",
    [12] = "RIGHT",
    [13] = "RIGHT",
    [14] = "RIGHT",
    [16] = "TOP",
    [17] = "TOP",
    [18] = "TOP"
}

local duraSlots = {
    [1] = "CharacterHeadSlot",
    [3] = "CharacterShoulderSlot",
    [5] = "CharacterChestSlot",
    [6] = "CharacterWaistSlot",
    [7] = "CharacterLegsSlot",
    [8] = "CharacterFeetSlot",
    [9] = "CharacterWristSlot",
    [10] = "CharacterHandsSlot",
    [16] = "CharacterMainHandSlot",
    [17] = "CharacterSecondaryHandSlot",
    [18] = "CharacterRangedSlot"
}

local ilvlStrings, missingStrings, inspectStrings, inspectMissingStrings = {}, {}, {}, {}
local duraStrings = {}

local Unsecret = WT.Utils.Safety.Unsecret
local SafeNum = WT.Utils.Safety.SafeNum
local SafeUnitGUID = WT.Utils.Units.SafeUnitGUID

local ICON_ENCHANT = "|T136244:14:14:0:0:64:64:4:60:4:60:255:50:50|t"
local ICON_ENCHANT_OK = "|T136244:14:14:0:0:64:64:4:60:4:60:150:255:150|t"
local ICON_SOCKET = "|TInterface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic:14|t"

local function GetGemIcon(gem)
    if gem and gem ~= "" and gem ~= "0" then
        local tex = C_Item.GetItemIconByID(gem)
        if tex then
            return "|T" .. tex .. ":14:14:0:0:64:64:4:60:4:60|t"
        else
            return "|T134139:14:14:0:0:64:64:4:60:4:60|t"
        end
    end
    return nil
end

local function IsSlotEnchantable(slotID, itemEquipLoc)
    if not slotID then return false end

    if WT.Compat and WT.Compat.IsForever then
        -- WoW Forever / Classic (1.60 / 1.12):
        -- Enchantable: Head (1), Shoulder (3), Chest (5), Legs (7), Feet (8), Wrist (9),
        -- Hands (10), Back (15), MainHand (16), OffHand/Shield (17), Ranged (18)
        if slotID == 1 or slotID == 3 or slotID == 5 or slotID == 7 or slotID == 8 or
            slotID == 9 or slotID == 10 or slotID == 15 or slotID == 16 or slotID == 18 then
            return true
        end
        if slotID == 17 and itemEquipLoc ~= "INVTYPE_HOLDABLE" then
            return true
        end
        return false
    end

    -- Retail 12.1+ (Midnight) vs Retail 11.x (The War Within / Dragonflight)
    local isMidnight = (WT.Compat and WT.Compat.IsMidnight)
    if isMidnight == nil then
        local toc = (WT.Compat and WT.Compat.TocVersion) or select(4, GetBuildInfo()) or 0
        local ver = (WT.Compat and WT.Compat.ClientVersion) or select(1, GetBuildInfo()) or ""
        isMidnight = (tonumber(toc) or 0) >= 120000 or (type(ver) == "string" and string.match(ver, "^12%."))
    end

    if isMidnight then
        -- WoW Retail 12.1+ (Midnight):
        -- Added/Returned: Head (1), Shoulder (3)
        -- Removed: Cloak (15), Bracers (9)
        -- Standard: Chest (5), Legs (7), Feet (8), Rings (11, 12), MainHand (16)
        if slotID == 1 or slotID == 3 or slotID == 5 or slotID == 7 or slotID == 8 or
            slotID == 11 or slotID == 12 or slotID == 16 then
            return true
        end
        if slotID == 17 and itemEquipLoc ~= "INVTYPE_SHIELD" and itemEquipLoc ~= "INVTYPE_HOLDABLE" then
            return true
        end
        return false
    else
        -- Pre-12.0 Retail (11.x The War Within / Dragonflight):
        -- Enchantable: Chest (5), Legs (7), Feet (8), Wrist (9), Rings (11, 12), Cloak (15), MainHand (16)
        if slotID == 5 or slotID == 7 or slotID == 8 or slotID == 9 or
            slotID == 11 or slotID == 12 or slotID == 15 or slotID == 16 then
            return true
        end
        if slotID == 17 and itemEquipLoc ~= "INVTYPE_SHIELD" and itemEquipLoc ~= "INVTYPE_HOLDABLE" then
            return true
        end
        return false
    end
end
Module.IsSlotEnchantable = IsSlotEnchantable

local function GetHeaderBadge(parentFrame, globalName)
    if not parentFrame then return nil end
    local frame = _G[globalName]
    if not frame then
        frame = CreateFrame("Frame", globalName, parentFrame, "BackdropTemplate")
        frame:SetClampedToScreen(true)
        frame:EnableMouse(false)

        frame:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })

        frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
        frame.text:SetJustifyH("CENTER")
        frame.text:SetJustifyV("MIDDLE")
    end

    -- Tab visual styling: warm Blizzard active-tab gold border with deep dark backdrop
    frame:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    frame:SetBackdropBorderColor(0.85, 0.70, 0.30, 1.0)

    -- Anchor seamlessly to the top edge of the parent frame (no gap, attached like a tab)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOM", parentFrame, "TOP", 0, -2)

    local strata = parentFrame.GetFrameStrata and parentFrame:GetFrameStrata() or "MEDIUM"
    frame:SetFrameStrata(strata)
    local level = parentFrame.GetFrameLevel and parentFrame:GetFrameLevel() or 10
    frame:SetFrameLevel(level + 2)

    return frame
end

local function UpdateMPlusSummary(parentFrame, score, yOffset)
    if not parentFrame then return end
    if parentFrame.wtMPlusText then
        parentFrame.wtMPlusText:Hide()
    end
end

local function SafeCompare(a, b)
    if not a or not b then return false end
    if scrub then
        a = scrub(a); b = scrub(b)
    end
    if not a or not b then return false end
    local ok, res = pcall(function() return a == b end)
    return ok and res
end

local function GetDurabilityColor(percent)
    if percent > 0.8 then
        return "00FF00"
    elseif percent > 0.3 then
        return "FFFF00"
    else
        return "FF0000"
    end
end

local function GetSafeItemQuality(itemLink)
    if not itemLink then return nil end
    if C_Item and C_Item.GetItemQualityByID then
        local ok, q = pcall(C_Item.GetItemQualityByID, itemLink)
        if ok and q then return q end
    end
    if C_Item and C_Item.GetItemInfo then
        local ok, _, _, q = pcall(C_Item.GetItemInfo, itemLink)
        if ok and q then return q end
    end
    if _G["GetItem" .. "Info"] then
        local ok, _, _, q = pcall(_G["GetItem" .. "Info"], itemLink)
        if ok and q then return q end
    end
    local itemID = string.match(itemLink, "item:(%d+)")
    if itemID then
        itemID = tonumber(itemID)
        if C_Item and C_Item.GetItemQualityByID then
            local ok, q = pcall(C_Item.GetItemQualityByID, itemID)
            if ok and q then return q end
        end
    end
    return nil
end

local function GetUnitAvgQuality(unit)
    local tQ, c = 0, 0
    local maxSlots = (WT.Compat and WT.Compat.IsForever) and 18 or 17
    for i = 1, maxSlots do
        if i ~= 4 then
            local ok, rawLink = pcall(GetInventoryItemLink, unit, i)
            local link = ok and Unsecret(rawLink) or nil
            if ok and link then
                local q = GetSafeItemQuality(link)
                if q and q >= 0 then
                    tQ = tQ + q; c = c + 1
                elseif C_Item and C_Item.RequestLoadItemDataByID then
                    pcall(C_Item.RequestLoadItemDataByID, link)
                end
            end
        end
    end
    return c > 0 and math.floor((tQ / c) + 0.5) or 1
end

local function ApplyPosition(fs, slotFrame, side, posStyle, isShared, isDura, sharedOffset)
    fs:ClearAllPoints()
    local xOffset, yOffset = 0, 0
    if isShared then
        if string.find(posStyle, "OUTSIDE") then
            if side == "TOP" then
                xOffset = isDura and (sharedOffset + 4) or -(sharedOffset + 4)
            else
                yOffset = isDura and -(sharedOffset / 2 + 1) or (sharedOffset / 2 + 1)
            end
        else
            if posStyle == "INNER_TOPRIGHT" then
                if isDura then yOffset = -sharedOffset - 2 end
            elseif posStyle == "INNER_BOTTOMRIGHT" then
                if not isDura then yOffset = sharedOffset + 2 end
            elseif posStyle == "INNER_CENTER" then
                yOffset = isDura and -(sharedOffset / 2 + 1) or (sharedOffset / 2 + 1)
            end
        end
    end

    if posStyle == "INNER_TOPRIGHT" then
        fs:SetPoint("TOPRIGHT", slotFrame, "TOPRIGHT", -2 + xOffset, -2 + yOffset); fs:SetJustifyH("RIGHT")
    elseif posStyle == "INNER_CENTER" then
        fs:SetPoint("CENTER", slotFrame, "CENTER", xOffset, yOffset); fs:SetJustifyH("CENTER")
    elseif posStyle == "INNER_BOTTOMRIGHT" then
        fs:SetPoint("BOTTOMRIGHT", slotFrame, "BOTTOMRIGHT", -2 + xOffset, 2 + yOffset); fs:SetJustifyH("RIGHT")
    elseif posStyle == "OUTSIDE_TOP" then
        if side == "LEFT" then
            fs:SetPoint("TOPLEFT", slotFrame, "TOPRIGHT", 7 + xOffset, 0 + yOffset); fs:SetJustifyH("LEFT")
        elseif side == "RIGHT" then
            fs:SetPoint("TOPRIGHT", slotFrame, "TOPLEFT", -7 + xOffset, 0 + yOffset); fs:SetJustifyH("RIGHT")
        else
            fs:SetPoint("BOTTOMRIGHT", slotFrame, "TOPRIGHT", 0 + xOffset, 7 + yOffset); fs:SetJustifyH("RIGHT")
        end
    elseif posStyle == "OUTSIDE_CENTER" then
        if side == "LEFT" then
            fs:SetPoint("LEFT", slotFrame, "RIGHT", 7 + xOffset, 0 + yOffset); fs:SetJustifyH("LEFT")
        elseif side == "RIGHT" then
            fs:SetPoint("RIGHT", slotFrame, "LEFT", -7 + xOffset, 0 + yOffset); fs:SetJustifyH("RIGHT")
        else
            fs:SetPoint("BOTTOM", slotFrame, "TOP", 0 + xOffset, 7 + yOffset); fs:SetJustifyH("CENTER")
        end
    elseif posStyle == "OUTSIDE_BOTTOM" then
        if side == "LEFT" then
            fs:SetPoint("BOTTOMLEFT", slotFrame, "BOTTOMRIGHT", 7 + xOffset, 0 + yOffset); fs:SetJustifyH("LEFT")
        elseif side == "RIGHT" then
            fs:SetPoint("BOTTOMRIGHT", slotFrame, "BOTTOMLEFT", -7 + xOffset, 0 + yOffset); fs:SetJustifyH("RIGHT")
        else
            fs:SetPoint("BOTTOMLEFT", slotFrame, "TOPLEFT", 0 + xOffset, 7 + yOffset); fs:SetJustifyH("LEFT")
        end
    end
end

local function ApplyAvgIlvlVisuals(statFrame)
    if not statFrame or not statFrame.Value then return end

    if not statFrame.wtOrigR then
        local r, g, b = statFrame.Value:GetTextColor()
        statFrame.wtOrigR, statFrame.wtOrigG, statFrame.wtOrigB = r, g, b
    end

    -- BATTLE-SAFE: Only SetTextColor is used. Avoid SetFont or SetShadow on restricted elements,
    -- as resizing native text triggers a Layout-Pass, which leads to execution taint in combat.
    if WT.DB and WT.DB.CharacterSheet and WT.DB.Modules.CharacterSheet and WT.DB.CharacterSheet.ShowItemLevel then
        if WT.DB.CharacterSheet.ItemLevelColorize then
            local avgQual = GetUnitAvgQuality("player")
            local hex = "FFFFFFFF"
            local db = WT.DB.CharacterSheet
            if avgQual == 0 then
                hex = WT.Colors:GetHex(db.ItemLevelColPoor, 0.62, 0.62, 0.62)
            elseif avgQual == 1 then
                hex = WT.Colors:GetHex(db.ItemLevelColCommon, 1, 1, 1)
            elseif avgQual == 2 then
                hex = WT.Colors:GetHex(db.ItemLevelColUncommon, 0.12, 1, 0)
            elseif avgQual == 3 then
                hex = WT.Colors:GetHex(db.ItemLevelColRare, 0, 0.44, 0.87)
            elseif avgQual == 4 then
                hex = WT.Colors:GetHex(db.ItemLevelColEpic, 0.64, 0.19, 0.79)
            elseif avgQual == 5 then
                hex = WT.Colors:GetHex(db.ItemLevelColLegendary, 1, 0.5, 0)
            elseif avgQual == 6 then
                hex = WT.Colors:GetHex(db.ItemLevelColArtifact, 0.9, 0.8, 0.5)
            elseif avgQual == 7 then
                hex = WT.Colors:GetHex(db.ItemLevelColHeirloom, 0, 0.8, 1)
            end

            local r, g, b = WT.Colors:HexToRGB(hex)
            statFrame.Value:SetTextColor(r, g, b)
        else
            statFrame.Value:SetTextColor(statFrame.wtOrigR or 1, statFrame.wtOrigG or 0.82, statFrame.wtOrigB or 0)
        end
    else
        statFrame.Value:SetTextColor(statFrame.wtOrigR or 1, statFrame.wtOrigG or 0.82, statFrame.wtOrigB or 0)
    end
end

function Module:UpdateCharacterSheet()
    if not WT.DB or not WT.DB.CharacterSheet or not WT.DB.Modules.CharacterSheet then return end

    -- ITEM LEVELS
    local showILvl = WT.DB.CharacterSheet.ShowItemLevel
    local ilvlFontPath = (WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", WT.DB.CharacterSheet.ItemLevelFont or "Friz Quadrata TT")) or
    "Fonts\\FRIZQT__.TTF"
    local ilvlFontSize = WT.DB.CharacterSheet.ItemLevelSize or 14
    local ilvlOutline = (WT.DB.CharacterSheet.ItemLevelOutline == "NONE") and "" or
    (WT.DB.CharacterSheet.ItemLevelOutline or "OUTLINE")
    local ilvlPos = "OUTSIDE_CENTER"

    -- DURABILITY
    local showDura = WT.DB.CharacterSheet.ShowDurability
    local duraFontPath = (WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", WT.DB.CharacterSheet.DurabilityFont or "Friz Quadrata TT")) or
    "Fonts\\FRIZQT__.TTF"
    local duraFontSize = WT.DB.CharacterSheet.DurabilityFontSize or 12
    local duraOutline = (WT.DB.CharacterSheet.DurabilityFontOutline == "NONE") and "" or
    (WT.DB.CharacterSheet.DurabilityFontOutline or "OUTLINE")
    local duraPos = "INNER_BOTTOMRIGHT"

    local isSharedPos = false
    local sharedOffset = math.max(ilvlFontSize, duraFontSize)

    local missingData = false

    -- UPDATE ITEM LEVELS
    for slotID, slotName in pairs(ilvlSlots) do
        local slotFrame = _G["Character" .. slotName .. "Slot"]
        if slotFrame then
            if not ilvlStrings[slotID] then
                ilvlStrings[slotID] = slotFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
            end
            if not missingStrings[slotID] then
                missingStrings[slotID] = slotFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
            end
            local fs = ilvlStrings[slotID]
            local mfs = missingStrings[slotID]

            if not showILvl then
                fs:Hide(); mfs:Hide()
            else
                fs:SetFont(ilvlFontPath, ilvlFontSize, ilvlOutline)
                fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
                ApplyPosition(fs, slotFrame, slotSides[slotID], ilvlPos, isSharedPos, false, sharedOffset)

                mfs:SetFont(ilvlFontPath, math.max(8, ilvlFontSize - 2), ilvlOutline)
                mfs:SetShadowColor(0, 0, 0, 1); mfs:SetShadowOffset(1, -1)
                mfs:ClearAllPoints()
                if slotSides[slotID] == "LEFT" then
                    mfs:SetPoint("LEFT", fs, "RIGHT", 4, 0)
                    mfs:SetJustifyH("LEFT")
                elseif slotSides[slotID] == "RIGHT" then
                    mfs:SetPoint("RIGHT", fs, "LEFT", -4, 0)
                    mfs:SetJustifyH("RIGHT")
                else
                    mfs:SetPoint("BOTTOM", fs, "TOP", 0, 2)
                    mfs:SetJustifyH("CENTER")
                end

                local itemLink = GetInventoryItemLink("player", slotID)
                if itemLink then
                    local effectiveILvl = C_Item.GetDetailedItemLevelInfo(itemLink)
                    local itemName = C_Item.GetItemInfo(itemLink)
                    if not effectiveILvl or not itemName then
                        effectiveILvl = effectiveILvl or 0
                        missingData = true
                        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemLink) end
                    end

                    local quality = GetSafeItemQuality(itemLink)
                    if not quality then
                        missingData = true
                        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemLink) end
                    end

                    local missingParts = {}
                    if WT.DB.CharacterSheet.ShowMissingEnchants and effectiveILvl > 0 then
                        local enchant, gem1, gem2, gem3, gem4 = string.match(itemLink,
                            "item:%d+:([^:]*):([^:]*):([^:]*):([^:]*):([^:]*)")
                        local itemEquipLoc = select(9, C_Item.GetItemInfo(itemLink))

                        local canEnchant = IsSlotEnchantable(slotID, itemEquipLoc)

                        if canEnchant then
                            if (not enchant or enchant == "" or enchant == "0") then
                                table.insert(missingParts, ICON_ENCHANT)
                            else
                                table.insert(missingParts, ICON_ENCHANT_OK)
                            end
                        end

                        local stats = C_Item.GetItemStats(itemLink)
                        local totalSockets = 0
                        if stats then
                            for stat, val in pairs(stats) do
                                if string.find(stat, "EMPTY_SOCKET") then totalSockets = totalSockets + val end
                            end
                        end

                        local filledSockets = 0
                        local function addGem(g)
                            local icon = GetGemIcon(g)
                            if icon then
                                table.insert(missingParts, icon)
                                filledSockets = filledSockets + 1
                            end
                        end

                        addGem(gem1)
                        addGem(gem2)
                        addGem(gem3)
                        addGem(gem4)

                        local emptySockets = totalSockets - filledSockets

                        if emptySockets > 0 then
                            table.insert(missingParts, string.rep(ICON_SOCKET, emptySockets))
                        end
                    end

                    local missingStr = table.concat(missingParts, " ")
                    if missingStr ~= "" then
                        mfs:SetText(missingStr)
                        mfs:Show()
                    else
                        mfs:Hide()
                    end

                    if effectiveILvl > 0 then
                        local hex = "FFFFFFFF"
                        if WT.DB.CharacterSheet.ItemLevelColorize then
                            if quality == 0 then
                                hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColPoor, 0.62, 0.62, 0.62)
                            elseif quality == 1 then
                                hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColCommon, 1, 1, 1)
                            elseif quality == 2 then
                                hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColUncommon, 0.12, 1, 0)
                            elseif quality == 3 then
                                hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColRare, 0, 0.44, 0.87)
                            elseif quality == 4 then
                                hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColEpic, 0.64, 0.19, 0.79)
                            elseif quality == 5 then
                                hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColLegendary, 1, 0.5, 0)
                            elseif quality == 6 then
                                hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColArtifact, 0.9, 0.8, 0.5)
                            elseif quality == 7 then
                                hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColHeirloom, 0, 0.8, 1)
                            elseif quality then
                                local _, _, _, hexColor = C_Item.GetItemQualityColor(quality); if hexColor then hex =
                                    hexColor end
                            end
                            hex = string.gsub(hex, "^#", "")
                        end
                        fs:SetText(string.format("|c%s%d|r", hex, effectiveILvl))
                        fs:Show()
                    elseif itemLink then
                        fs:SetText("|cFF888888...|r")
                        fs:Show()
                        mfs:Hide()
                    else
                        fs:Hide(); mfs:Hide()
                    end
                else
                    fs:Hide(); mfs:Hide()
                end
            end
        end
    end

    -- UPDATE DURABILITY
    for slotID, slotName in pairs(duraSlots) do
        local slotFrame = _G[slotName]
        if slotFrame then
            if not duraStrings[slotID] then
                duraStrings[slotID] = slotFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
            end
            local fs = duraStrings[slotID]

            if not showDura then
                fs:Hide()
            else
                fs:SetFont(duraFontPath, duraFontSize, duraOutline)
                fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
                ApplyPosition(fs, slotFrame, slotSides[slotID], duraPos, isSharedPos, true, sharedOffset)

                local okDura, v, max = pcall(GetInventoryItemDurability, slotID)
                local safeV, safeMax = (okDura and v) and SafeNum(v) or 0, (okDura and max) and SafeNum(max) or 0
                if safeMax > 0 then
                    local percent = safeV / safeMax
                    if WT.DB.CharacterSheet.DurabilityOnlyDamaged and percent >= 0.99 then
                        fs:Hide()
                    else
                        fs:SetText(string.format("|cFF%s%.0f%%|r", GetDurabilityColor(percent), percent * 100))
                        fs:Show()
                    end
                else
                    fs:Hide()
                end
            end
        end
    end

    -- UPDATE OVERALL ITEM LEVEL
    if CharacterStatsPane and CharacterStatsPane.ItemLevelFrame then
        ApplyAvgIlvlVisuals(CharacterStatsPane.ItemLevelFrame)
    end

    -- DOCKED HEADER (Player CharacterFrame)
    if _G["CharacterModelFrame"] and _G["CharacterModelFrame"].wtMPlusText then
        _G["CharacterModelFrame"].wtMPlusText:Hide()
    end

    if CharacterFrame and WT.DB.CharacterSheet.ShowMPlusSummary and not (WT.Compat and WT.Compat.IsForever) then
        local isPaperDoll = not _G["PaperDollFrame"] or _G["PaperDollFrame"]:IsShown()
        local charHeader = GetHeaderBadge(CharacterFrame, "WT_CharacterHeaderFrame")
        if charHeader then
            local score = (C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore) and
            C_ChallengeMode.GetOverallDungeonScore() or 0
            if isPaperDoll and score and score > 0 then
                local mplusHex = "FFFFFFFF"
                local rarityColor = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and
                C_ChallengeMode.GetDungeonScoreRarityColor(score)
                if rarityColor then
                    local safeCall = securecallfunction or securecall
                    local ok, res = pcall(safeCall, rarityColor.GenerateHexColor, rarityColor)
                    if ok and res then mplusHex = res end
                end
                mplusHex = string.gsub(mplusHex, "^#", "")

                local mplusLabel = STAT_AVERAGE_ITEM_LEVEL and "Mythic+ Score" or "Mythic+ IO"
                charHeader.text:SetFont(ilvlFontPath, math.max(12, ilvlFontSize), ilvlOutline)
                charHeader.text:SetShadowColor(0, 0, 0, 1)
                charHeader.text:SetShadowOffset(1, -1)
                charHeader.text:SetSpacing(2)
                charHeader.text:SetText(string.format("|cFFFFD100%s:|r |c%s%d|r", mplusLabel, mplusHex, score))

                local textW = charHeader.text:GetStringWidth()
                local textH = charHeader.text:GetStringHeight()
                charHeader:SetSize(math.max(140, textW + 22), math.max(22, textH + 8))
                charHeader:Show()
            else
                charHeader:Hide()
            end
        end
    else
        local charHeader = _G["WT_CharacterHeaderFrame"]
        if charHeader then charHeader:Hide() end
    end

    if self.UpdateInspectItemLevels then self:UpdateInspectItemLevels() end

    if missingData and not self.isRetrying then
        self.retryCount = (self.retryCount or 0) + 1
        if self.retryCount < 10 then
            self.isRetrying = true
            C_Timer.After(0.5, function()
                self.isRetrying = false
                self:UpdateCharacterSheet()
            end)
        else
            self.retryCount = 0
        end
    else
        if not missingData then self.retryCount = 0 end
    end
end

local function CalculateAverageItemLevel(unit)
    local isForever = WT.Compat and WT.Compat.IsForever
    local total, count = 0, isForever and 17 or 16
    local mh, oh = 0, 0
    local is2H = false

    for slotID, _ in pairs(ilvlSlots) do
        local ok, itemLink = pcall(GetInventoryItemLink, unit, slotID)
        if ok and itemLink then
            local effectiveILvl = C_Item.GetDetailedItemLevelInfo(itemLink)
            if effectiveILvl then
                if slotID == 16 then
                    mh = effectiveILvl
                    local _, _, _, _, _, _, _, _, itemEquipLoc = C_Item.GetItemInfo(itemLink)
                    if itemEquipLoc == "INVTYPE_2HWEAPON" or itemEquipLoc == "INVTYPE_RANGED" or itemEquipLoc == "INVTYPE_RANGEDRIGHT" then
                        is2H = true
                    end
                elseif slotID == 17 then
                    oh = effectiveILvl
                else
                    total = total + effectiveILvl
                end
            end
        end
    end

    if mh > 0 and oh > 0 then
        total = total + mh + oh
    elseif mh > 0 and is2H and not isForever then
        total = total + (mh * 2)
    else
        total = total + mh + oh
    end

    return math.floor((total / count) + 0.5)
end

function Module:UpdateInspectItemLevels()
    if not (InspectFrame and InspectFrame:IsShown()) then return end
    if InspectPaperDollFrame and not InspectPaperDollFrame:IsShown() then
        local header = _G["WT_InspectHeaderFrame"]
        if header then header:Hide() end
        return
    end
    if not WT.DB or not WT.DB.CharacterSheet then return end

    local showILvl = WT.DB.CharacterSheet.ShowItemLevel
    if not showILvl then
        for _, fs in pairs(inspectStrings) do fs:Hide() end
        for _, mfs in pairs(inspectMissingStrings) do mfs:Hide() end
        if InspectPaperDollFrame and InspectPaperDollFrame.wtAvgIlvlText then InspectPaperDollFrame.wtAvgIlvlText:Hide() end
        if InspectModelFrame and InspectModelFrame.wtAvgIlvlText then InspectModelFrame.wtAvgIlvlText:Hide() end
        if InspectModelFrame and InspectModelFrame.wtMPlusText then InspectModelFrame.wtMPlusText:Hide() end
        local header = _G["WT_InspectHeaderFrame"]
        if header then header:Hide() end
        return
    end

    local unit = InspectFrame.unit or "target"
    local fontPath = (WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", WT.DB.CharacterSheet.ItemLevelFont or "Friz Quadrata TT")) or
    "Fonts\\FRIZQT__.TTF"
    local fontSize = WT.DB.CharacterSheet.ItemLevelSize or 14
    local outline = (WT.DB.CharacterSheet.ItemLevelOutline == "NONE") and "" or
    (WT.DB.CharacterSheet.ItemLevelOutline or "OUTLINE")
    local posStyle = "OUTSIDE_CENTER"

    local missingData = false
    local hasAnyItem = false

    for slotID, slotName in pairs(ilvlSlots) do
        local slotFrame = _G["Inspect" .. slotName .. "Slot"]
        if slotFrame then
            if not inspectStrings[slotID] then
                inspectStrings[slotID] = slotFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
            end
            if not inspectMissingStrings[slotID] then
                inspectMissingStrings[slotID] = slotFrame:CreateFontString(nil, "OVERLAY",
                    "GameFontHighlightSmallOutline")
            end
            local fs = inspectStrings[slotID]
            local mfs = inspectMissingStrings[slotID]

            fs:SetFont(fontPath, fontSize, outline)
            fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
            ApplyPosition(fs, slotFrame, slotSides[slotID], posStyle, false, false, fontSize)

            mfs:SetFont(fontPath, math.max(8, fontSize - 2), outline)
            mfs:SetShadowColor(0, 0, 0, 1); mfs:SetShadowOffset(1, -1)
            mfs:ClearAllPoints()
            if slotSides[slotID] == "LEFT" then
                mfs:SetPoint("LEFT", fs, "RIGHT", 4, 0)
                mfs:SetJustifyH("LEFT")
            elseif slotSides[slotID] == "RIGHT" then
                mfs:SetPoint("RIGHT", fs, "LEFT", -4, 0)
                mfs:SetJustifyH("RIGHT")
            else
                mfs:SetPoint("BOTTOM", fs, "TOP", 0, 2)
                mfs:SetJustifyH("CENTER")
            end

            local ok, itemLink = pcall(GetInventoryItemLink, unit, slotID)
            if ok and itemLink then
                hasAnyItem = true
                local effectiveILvl = C_Item.GetDetailedItemLevelInfo(itemLink)
                local itemName = C_Item.GetItemInfo(itemLink)
                if not effectiveILvl or not itemName then
                    effectiveILvl = effectiveILvl or 0
                    missingData = true
                    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemLink) end
                end

                local quality = GetSafeItemQuality(itemLink)
                if not quality then
                    missingData = true
                    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemLink) end
                end

                local missingParts = {}
                if WT.DB.CharacterSheet.ShowMissingEnchants and effectiveILvl > 0 then
                    local enchant, gem1, gem2, gem3, gem4 = string.match(itemLink,
                        "item:%d+:([^:]*):([^:]*):([^:]*):([^:]*):([^:]*)")
                    local itemEquipLoc = select(9, C_Item.GetItemInfo(itemLink))

                    local canEnchant = IsSlotEnchantable(slotID, itemEquipLoc)

                    if canEnchant then
                        if (not enchant or enchant == "" or enchant == "0") then
                            table.insert(missingParts, ICON_ENCHANT)
                        else
                            table.insert(missingParts, ICON_ENCHANT_OK)
                        end
                    end

                    local stats = C_Item.GetItemStats(itemLink)
                    local totalSockets = 0
                    if stats then
                        for stat, val in pairs(stats) do
                            if string.find(stat, "EMPTY_SOCKET") then totalSockets = totalSockets + val end
                        end
                    end

                    local filledSockets = 0
                    local function addGem(g)
                        local icon = GetGemIcon(g)
                        if icon then
                            table.insert(missingParts, icon)
                            filledSockets = filledSockets + 1
                        end
                    end

                    addGem(gem1)
                    addGem(gem2)
                    addGem(gem3)
                    addGem(gem4)

                    local emptySockets = totalSockets - filledSockets

                    if emptySockets > 0 then
                        table.insert(missingParts, string.rep(ICON_SOCKET, emptySockets))
                    end
                end

                local missingStr = table.concat(missingParts, " ")
                if missingStr ~= "" then
                    mfs:SetText(missingStr)
                    mfs:Show()
                else
                    mfs:Hide()
                end

                if effectiveILvl > 0 then
                    local hex = "FFFFFFFF"
                    if WT.DB.CharacterSheet.ItemLevelColorize then
                        if quality == 0 then
                            hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColPoor, 0.62, 0.62, 0.62)
                        elseif quality == 1 then
                            hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColCommon, 1, 1, 1)
                        elseif quality == 2 then
                            hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColUncommon, 0.12, 1, 0)
                        elseif quality == 3 then
                            hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColRare, 0, 0.44, 0.87)
                        elseif quality == 4 then
                            hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColEpic, 0.64, 0.19, 0.79)
                        elseif quality == 5 then
                            hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColLegendary, 1, 0.5, 0)
                        elseif quality == 6 then
                            hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColArtifact, 0.9, 0.8, 0.5)
                        elseif quality == 7 then
                            hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColHeirloom, 0, 0.8, 1)
                        elseif quality then
                            local _, _, _, hexColor = C_Item.GetItemQualityColor(quality); if hexColor then hex =
                                hexColor end
                        end
                        hex = string.gsub(hex, "^#", "")
                    end
                    fs:SetText(string.format("|c%s%d|r", hex, effectiveILvl))
                    fs:Show()
                elseif itemLink then
                    fs:SetText("|cFF888888...|r")
                    fs:Show()
                    mfs:Hide()
                else
                    fs:Hide(); mfs:Hide()
                end
            else
                fs:Hide(); mfs:Hide()
            end
        end
    end

    if not hasAnyItem then
        missingData = true
    end

    -- OVERALL INSPECT ITEM LEVEL
    local avgIlvl = 0
    if C_PaperDollInfo and type(C_PaperDollInfo.GetInspectItemLevel) == "function" then
        local ok, ilvl = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
        avgIlvl = (ok and ilvl) and math.floor(ilvl) or 0
    end
    if avgIlvl == 0 then
        avgIlvl = CalculateAverageItemLevel(unit)
    end

    -- DOCKED HEADER BADGE (Above InspectFrame)
    local header = GetHeaderBadge(InspectFrame, "WT_InspectHeaderFrame")
    if header then
        local parts = {}

        -- Item Level
        if showILvl then
            local hex = "FFFFD100"
            if WT.DB.CharacterSheet.ItemLevelColorize then
                local avgQual = GetUnitAvgQuality(unit)
                local db = WT.DB.CharacterSheet
                if avgQual == 0 then
                    hex = WT.Colors:GetHex(db.ItemLevelColPoor, 0.62, 0.62, 0.62)
                elseif avgQual == 1 then
                    hex = WT.Colors:GetHex(db.ItemLevelColCommon, 1, 1, 1)
                elseif avgQual == 2 then
                    hex = WT.Colors:GetHex(db.ItemLevelColUncommon, 0.12, 1, 0)
                elseif avgQual == 3 then
                    hex = WT.Colors:GetHex(db.ItemLevelColRare, 0, 0.44, 0.87)
                elseif avgQual == 4 then
                    hex = WT.Colors:GetHex(db.ItemLevelColEpic, 0.64, 0.19, 0.79)
                elseif avgQual == 5 then
                    hex = WT.Colors:GetHex(db.ItemLevelColLegendary, 1, 0.5, 0)
                elseif avgQual == 6 then
                    hex = WT.Colors:GetHex(db.ItemLevelColArtifact, 0.9, 0.8, 0.5)
                elseif avgQual == 7 then
                    hex = WT.Colors:GetHex(db.ItemLevelColHeirloom, 0, 0.8, 1)
                end
                hex = string.gsub(hex, "^#", "")
            end

            if avgIlvl > 0 then
                table.insert(parts,
                    string.format("|cFFFFD100%s:|r |c%s%d|r", STAT_AVERAGE_ITEM_LEVEL or "Item Level", hex, avgIlvl))
            elseif hasAnyItem then
                table.insert(parts,
                    string.format("|cFFFFD100%s:|r |cFF888888...|r", STAT_AVERAGE_ITEM_LEVEL or "Item Level"))
                missingData = true
            else
                missingData = true
            end
        end

        -- Mythic+ Score
        if WT.DB.CharacterSheet.ShowMPlusSummary and not (WT.Compat and WT.Compat.IsForever) then
            local mplus = C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
            local score = mplus and mplus.currentSeasonScore or 0
            if score and score > 0 then
                local mplusHex = "FFFFFFFF"
                local rarityColor = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and
                C_ChallengeMode.GetDungeonScoreRarityColor(score)
                if rarityColor then
                    local safeCall = securecallfunction or securecall
                    local ok, res = pcall(safeCall, rarityColor.GenerateHexColor, rarityColor)
                    if ok and res then mplusHex = res end
                end
                mplusHex = string.gsub(mplusHex, "^#", "")
                local mplusLabel = STAT_AVERAGE_ITEM_LEVEL and "Mythic+ Score" or "Mythic+ IO"
                table.insert(parts, string.format("|cFFFFD100%s:|r |c%s%d|r", mplusLabel, mplusHex, score))
            end
        end

        if #parts > 0 then
            local isMultiLine = (#parts > 1)
            local tabFontSize = isMultiLine and math.max(11, math.min(13, fontSize - 1)) or math.max(12, fontSize)
            header.text:SetFont(fontPath, tabFontSize, outline)
            header.text:SetShadowColor(0, 0, 0, 1)
            header.text:SetShadowOffset(1, -1)
            header.text:SetSpacing(2)
            header.text:SetText(table.concat(parts, "\n"))

            local textW = header.text:GetStringWidth()
            local textH = header.text:GetStringHeight()
            local padX = 22
            local padY = isMultiLine and 10 or 8
            header:SetSize(math.max(140, textW + padX), math.max(22, textH + padY))
            header:Show()
        else
            header:Hide()
        end
    end

    -- Cleanup legacy in-model text
    local modelFrame = InspectModelFrame or InspectPaperDollFrame
    if modelFrame and modelFrame.wtAvgIlvlText then modelFrame.wtAvgIlvlText:Hide() end
    if InspectModelFrame and InspectModelFrame.wtMPlusText then InspectModelFrame.wtMPlusText:Hide() end

    if missingData and not self.isInspectRetrying then
        self.inspectRetryCount = (self.inspectRetryCount or 0) + 1
        if self.inspectRetryCount < 10 then
            self.isInspectRetrying = true
            -- If items haven't arrived after 1s (server throttled or dropped request), re-request once
            if self.inspectRetryCount == 2 and not InCombatLockdown() and WT.Utils and WT.Utils.Units and WT.Utils.Units.SafeCanInspect and WT.Utils.Units.SafeCanInspect(unit) then
                pcall(_G.NotifyInspect, unit)
            end
            C_Timer.After(0.5, function()
                self.isInspectRetrying = false
                self:UpdateInspectItemLevels()
            end)
        else
            self.inspectRetryCount = 0
        end
    else
        if not missingData then self.inspectRetryCount = 0 end
    end
end

function Module:Initialize()
    if not WT.DB.Modules.CharacterSheet then return end

    local updateQueued = false
    local function QueueCharacterSheetUpdate()
        if not updateQueued then
            updateQueued = true
            C_Timer.After(0.1, function()
                updateQueued = false
                Module:UpdateCharacterSheet()
            end)
        end
    end

    WT.Core.Events:Register("PLAYER_EQUIPMENT_CHANGED", QueueCharacterSheetUpdate)
    WT.Core.Events:Register("UPDATE_INVENTORY_DURABILITY", QueueCharacterSheetUpdate)
    WT.Core.Events:Register("GET_ITEM_INFO_RECEIVED", QueueCharacterSheetUpdate)

    if not Module.avgIlvlHooked and type(_G["PaperDollFrame_SetItemLevel"]) == "function" then
        Module.avgIlvlHooked = true
        hooksecurefunc("PaperDollFrame_SetItemLevel", function(statFrame, unit)
            if unit ~= "player" then return end
            if not statFrame or not statFrame.Value then return end
            if CharacterStatsPane and statFrame ~= CharacterStatsPane.ItemLevelFrame then return end

            ApplyAvgIlvlVisuals(statFrame)
        end)
    end

    if CharacterFrame then
        CharacterFrame:HookScript("OnShow", function() Module:UpdateCharacterSheet() end)
        CharacterFrame:HookScript("OnHide", function()
            local header = _G["WT_CharacterHeaderFrame"]
            if header then header:Hide() end
        end)
        if PaperDollFrame then
            PaperDollFrame:HookScript("OnShow", function() Module:UpdateCharacterSheet() end)
            PaperDollFrame:HookScript("OnHide", function()
                local header = _G["WT_CharacterHeaderFrame"]
                if header then header:Hide() end
            end)
        end
    end

    local inspectQueued = false
    local function QueueInspectUpdate()
        if not inspectQueued then
            inspectQueued = true
            C_Timer.After(0.05, function()
                inspectQueued = false
                Module:UpdateInspectItemLevels()
            end)
        end
    end

    local function HookInspectUI()
        if not Module.inspectHooked and _G["InspectFrame"] then
            Module.inspectHooked = true
            InspectFrame:HookScript("OnShow", QueueInspectUpdate)
            InspectFrame:HookScript("OnHide", function()
                local header = _G["WT_InspectHeaderFrame"]
                if header then header:Hide() end
            end)
            if InspectPaperDollFrame then
                InspectPaperDollFrame:HookScript("OnShow", QueueInspectUpdate)
                InspectPaperDollFrame:HookScript("OnHide", function()
                    local header = _G["WT_InspectHeaderFrame"]
                    if header then header:Hide() end
                end)
            end
            if type(_G["InspectPaperDollItemSlotButton_Update"]) == "function" then
                hooksecurefunc("InspectPaperDollItemSlotButton_Update", QueueInspectUpdate)
            end
        end
    end
    HookInspectUI()

    WT.Core.Events:Register("ADDON_LOADED", function(event, addon)
        if addon == "Blizzard_InspectUI" then
            HookInspectUI()
        end
    end)

    WT.Core.Events:Register("INSPECT_READY", function(event, guid)
        if InspectFrame and InspectFrame:IsShown() then
            local unit = InspectFrame.unit or "target"
            local unitGUID = SafeUnitGUID(unit)
            if not guid or not unitGUID or SafeCompare(unitGUID, guid) or SafeCompare(InspectFrame.unitGUID, guid) then
                QueueInspectUpdate()
            end
        end
    end)

    self:UpdateCharacterSheet()
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

    panel:CreateTitle(builder, WT.L.GROUP_FRAMES_CHAR_SHEET)
    AddDescription(WT.L.OPT_DESC_GROUP_CHAR_SHEET)

    local function UpdateBoth() if Module.UpdateCharacterSheet then Module:UpdateCharacterSheet() end end

    local ilvlInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_SHOW_ILVL, WT.L.OPT_DESC_FRAMES_SHOW_ILVL,
        "CharacterSheet", "ShowItemLevel", UpdateBoth)

    local ilvlColInit = panel:CreateCheckbox(builder, WT.L.OPT_FRAMES_ILVL_COLOR, WT.L.OPT_DESC_FRAMES_ILVL_COLOR,
        "CharacterSheet", "ItemLevelColorize", UpdateBoth, ilvlInit)
    panel:CreateColorPicker(builder, WT.L.OPT_ILVL_COL_POOR, WT.L.OPT_DESC_COLOR_VALUE, "CharacterSheet",
        "ItemLevelColPoor", false, ilvlColInit, UpdateBoth)
    panel:CreateColorPicker(builder, WT.L.OPT_ILVL_COL_COMMON, WT.L.OPT_DESC_COLOR_VALUE, "CharacterSheet",
        "ItemLevelColCommon", false, ilvlColInit, UpdateBoth)
    panel:CreateColorPicker(builder, WT.L.OPT_ILVL_COL_UNCOMMON, WT.L.OPT_DESC_COLOR_VALUE,
        "CharacterSheet", "ItemLevelColUncommon", false, ilvlColInit, UpdateBoth)
    panel:CreateColorPicker(builder, WT.L.OPT_ILVL_COL_RARE, WT.L.OPT_DESC_COLOR_VALUE, "CharacterSheet",
        "ItemLevelColRare", false, ilvlColInit, UpdateBoth)
    panel:CreateColorPicker(builder, WT.L.OPT_ILVL_COL_EPIC, WT.L.OPT_DESC_COLOR_VALUE, "CharacterSheet",
        "ItemLevelColEpic", false, ilvlColInit, UpdateBoth)
    panel:CreateColorPicker(builder, WT.L.OPT_ILVL_COL_LEGENDARY, WT.L.OPT_DESC_COLOR_VALUE,
        "CharacterSheet", "ItemLevelColLegendary", false, ilvlColInit, UpdateBoth)
    panel:CreateColorPicker(builder, WT.L.OPT_ILVL_COL_ARTIFACT, WT.L.OPT_DESC_COLOR_VALUE,
        "CharacterSheet", "ItemLevelColArtifact", false, ilvlColInit, UpdateBoth)
    panel:CreateColorPicker(builder, WT.L.OPT_ILVL_COL_HEIRLOOM, WT.L.OPT_DESC_COLOR_VALUE,
        "CharacterSheet", "ItemLevelColHeirloom", false, ilvlColInit, UpdateBoth)

    if WT.Utils and WT.Utils.SharedMedia then
        panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "CharacterSheet", "ItemLevelFont",
            WT.Utils.SharedMedia:GetOptions("font"), UpdateBoth, ilvlInit)
    end
    panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "CharacterSheet", "ItemLevelSize", 8, 30, 1,
        UpdateBoth, ilvlInit)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "CharacterSheet",
        "ItemLevelOutline", UpdateBoth, ilvlInit)

    panel:CreateCheckbox(builder, WT.L.OPT_CHAR_MISSING_ENCHANTS, WT.L.OPT_DESC_CHAR_MISSING_ENCHANTS, "CharacterSheet",
        "ShowMissingEnchants", UpdateBoth)
    local mplusCb = panel:CreateCheckbox(builder, WT.L.OPT_CHAR_MPLUS_SUMMARY, WT.L.OPT_DESC_CHAR_MPLUS_SUMMARY,
        "CharacterSheet", "ShowMPlusSummary", UpdateBoth)
    panel:SetFlavor(mplusCb, "RETAIL")

    local charInit = panel:CreateCheckbox(builder, WT.L.OPT_DURABILITY_CHARACTER, WT.L.OPT_DESC_DURABILITY_CHARACTER,
        "CharacterSheet", "ShowDurability", UpdateBoth)
    panel:CreateCheckbox(builder, WT.L.OPT_DURA_ONLY_DAMAGED, WT.L.OPT_DESC_DURA_ONLY_DAMAGED, "CharacterSheet",
        "DurabilityOnlyDamaged", UpdateBoth, charInit)

    if WT.Utils and WT.Utils.SharedMedia then panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT,
            "CharacterSheet", "DurabilityFont", WT.Utils.SharedMedia:GetOptions("font"), UpdateBoth, charInit) end
    panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "CharacterSheet", "DurabilityFontSize", 8,
        30, 1, UpdateBoth, charInit)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "CharacterSheet",
        "DurabilityFontOutline", UpdateBoth, charInit)
end
