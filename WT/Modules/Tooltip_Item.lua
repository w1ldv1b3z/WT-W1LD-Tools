local _, WT = ...
local Module = WT.Modules.Tooltip

local itemReqCache = {}
local cachedDurabilityTemplate = nil

local strtrim = strtrim or string.trim or function(s) return s and string.match(s, "^%s*(.-)%s*$") or "" end

local SafeNum = WT.Utils.Safety.SafeNum
local Unsecret = WT.Utils.Safety.Unsecret

local function FormatItemTooltip(tooltip, data)
    if tooltip:IsForbidden() then return end
    if not WT.DB.Modules.Tooltip then return end
    
    local tooltipName = WT.Utils.Safety.GetSafeTooltipName(tooltip)
    local tooltipName = WT.Utils.Safety.GetSafeTooltipName(tooltip)
    if not tooltipName then return end
    
    -- Performance: Skip expensive line scanning completely if no text-modifying features are enabled
    local db = WT.DB.Tooltip
    if not db then return end
    local checkLearned = db.Learned
    local checkDurability = WT.DB.Durability and WT.DB.Durability.ShowTooltip
    if not checkLearned and not checkDurability then return end
    
    for i = tooltip:NumLines(), 2, -1 do
        local line = _G[tooltipName .. "TextLeft" .. i]
        local lineData = data and data.lines and data.lines[i]
        local rawTxt = line and line:IsShown() and lineData and lineData.leftText
        local txt = Unsecret(rawTxt)
            
        local isSafeText = false
        if type(txt) == "string" then
            local ok, res = pcall(function() return txt ~= "" and string.len(txt) > 0 end)
            if ok and res then isSafeText = true end
        end
        
        if isSafeText then
                local ok, same = pcall(function() return txt == ITEM_SPELL_KNOWN end)
                if checkLearned and ok and same then
                    line:SetText("|cff00ff00" .. txt .. "|r")
                end
                
                if checkDurability and type(txt) == "string" then
                    local v, max = string.match(txt, "(%d+)%s*/%s*(%d+)")
                    if v and max then
                        local cleanTxt = txt
                        if string.find(cleanTxt, "|", 1, true) then
                            cleanTxt = string.gsub(cleanTxt, "|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
                        end
                        cleanTxt = string.gsub(cleanTxt, "%d+%s*/%s*%d+", "")
                        if not cachedDurabilityTemplate then
                            cachedDurabilityTemplate = strtrim(string.gsub(string.gsub(DURABILITY_TEMPLATE, "%%%d?%$?[sd]", ""), "%s*/%s*", ""))
                        end
                        if strtrim(cleanTxt) == cachedDurabilityTemplate and tonumber(max) > 0 then
                            local pct = tonumber(v) / tonumber(max)
                            local hex = pct > 0.8 and "ff00ff00" or (pct > 0.3 and "ffffff00" or "ffff0000")
                            if not string.find(txt, "%%|r%)") then
                                line:SetText(txt .. string.format(" (|c%s%.0f%%|r)", hex, pct * 100))
                            end
                        end
                    end
                end
        end
    end
end

local function AppendItemExtraData(tooltip, data)
    local itemID = data and SafeNum(data.id)
    if type(itemID) ~= "number" then return end
    
    -- Performance: Skip expensive API calls completely if no extra info features are enabled
    local db = WT.DB.Tooltip
    if not db or (not db.Expansion and not db.MaterialTracker and not db.KnownToys and not db.NerdIDs and not db.QuestWarn) then return end
    
    local tooltipName = WT.Utils.Safety.GetSafeTooltipName(tooltip)
    if not tooltipName then return end
    local function GetLineIndex(label)
        if not data or not data.lines then return nil end
        for i, lineData in ipairs(data.lines) do
            local txt = lineData.leftText
            txt = Unsecret(txt)
            if type(txt) == "string" and txt == label then return i end
        end
        return nil
    end

    local function SetOrAddDoubleLine(label, value, lr, lg, lb, vr, vg, vb)
        local index = GetLineIndex(label)
        if index then
            local leftLine = _G[tooltipName .. "TextLeft" .. index]
            local rightLine = _G[tooltipName .. "TextRight" .. index]
            if leftLine then 
                leftLine:SetText(label); leftLine:SetTextColor(lr, lg, lb) 
            end
            if rightLine and rightLine:IsShown() then 
                rightLine:SetText(value); rightLine:SetTextColor(vr, vg, vb)
            end
        else
            tooltip:AddDoubleLine(label, value, lr, lg, lb, vr, vg, vb)
        end
    end
    
    local function SetOrAddLine(text, r, g, b)
        local index = GetLineIndex(text)
        if index then
            local leftLine = _G[tooltipName .. "TextLeft" .. index]
            if leftLine then 
                leftLine:SetText(text); leftLine:SetTextColor(r, g, b) 
            end
        else
            tooltip:AddLine(text, r, g, b)
        end
    end

    local fnGetItemInfo = C_Item.GetItemInfo
    local itemName, _, _, _, _, _, _, _, _, _, _, classID, _, bindType, expacID = fnGetItemInfo(itemID)
    
    if not itemName then
        if not itemReqCache[itemID] then
            itemReqCache[itemID] = true
            if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        end
    end
    
    if WT.DB.Tooltip.Expansion then
        if type(expacID) == "number" then
            local expacName
            local C_ExpInfo = _G["C_ExpansionInfo"]
            if C_ExpInfo and C_ExpInfo.GetExpansionData then
                local expacData = C_ExpInfo.GetExpansionData(expacID)
                if expacData then expacName = expacData.name end
            end
            if not expacName then
                expacName = _G["EXPANSION_NAME"..expacID]
            end
            
            if expacName then 
                local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColExpL, 1, 0.82, 0)
                local vr, vg, vb = WT.Colors:GetRGB(WT.DB.Tooltip.ColExpV, 1, 1, 1)
                SetOrAddDoubleLine(tostring(WT.L.TT_EXPANSION_PREFIX), tostring(expacName), lr, lg, lb, vr, vg, vb) 
            end
        end
    end
    
    if WT.DB.Tooltip.MaterialTracker then
        local fnGetItemCount = C_Item and C_Item.GetItemCount or _G["GetItem".."Count"]
        local bag = fnGetItemCount(itemID, false, false, false)
        local bank = fnGetItemCount(itemID, true, false, true) - bag
        if bag > 0 or bank > 0 then
            local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColMatL, 1, 0.82, 0)
            local hexV = WT.Colors:GetHex(WT.DB.Tooltip.ColMatV, 1, 1, 1)
            local infoStr = string.format("|cFF888888%s|r |c%s%d|r |cFF888888|||r |cFF888888%s|r |c%s%d|r", tostring(WT.L.TT_BAGS), hexV, bag, tostring(WT.L.TT_BANK), hexV, bank)
            SetOrAddDoubleLine(tostring(WT.L.TT_STOCK_PREFIX), infoStr, lr, lg, lb, 1, 1, 1)
        end
    end
    
    if WT.DB.Tooltip.KnownToys then
        local isToy = C_ToyBox and C_ToyBox.GetToyInfo(itemID)
        if isToy then
            if PlayerHasToy(itemID) then SetOrAddLine(tostring(WT.L.TT_KNOWN_TOY), 0, 1, 0) else SetOrAddLine(tostring(WT.L.TT_MISSING_TOY), 1, 0, 0) end
        end
    end
    
    if WT.DB.Tooltip.NerdIDs and WT.DB.Tooltip.NerdIDsItems ~= false then
        local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColNerdL, 0.5, 0.5, 0.5)
        local vr, vg, vb = WT.Colors:GetRGB(WT.DB.Tooltip.ColNerdV, 1, 1, 1)
        SetOrAddDoubleLine(tostring(WT.L.TT_ITEM_ID), tostring(itemID), lr, lg, lb, vr, vg, vb)
    end
    
    if WT.DB.Tooltip.QuestWarn then
        if classID == 12 or bindType == 4 then
            SetOrAddLine(tostring(WT.L.TT_QUEST_ITEM), 1, 0, 0)
        end
    end
    
end

function Module:SetupItemTooltip()
    if not TooltipDataProcessor then return end
    
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip:IsForbidden() then return end
        if type(tooltip.NumLines) ~= "function" then return end
        if not WT.DB.Modules.Tooltip then return end
        
        -- Taint protection for Housing
        local owner = type(tooltip.GetOwner) == "function" and tooltip:GetOwner() or nil
        if owner then
            local current = owner
            for _ = 1, 10 do
                if not current then break end
                if current == _G["HouseListFrame"] or current == _G["HouseEditorFrame"] then return end
                if type(current.GetName) == "function" then
                    local okN, rawName = pcall(current.GetName, current)
                    local name = okN and WT.Utils.Safety.Unsecret(rawName) or nil
                    if name and (string.match(name, "House") or string.match(name, "Housing")) then return end
                end
                local okP, p = pcall(current.GetParent, current)
                if okP and p then current = p else break end
            end
        end

        -- Prevents layout loops (framedrops) in ShoppingTooltips caused by added lines
        local tooltipName = nil
        local rawName = tooltip:GetName()
        if type(rawName) == "string" then
            local ok = pcall(string.match, rawName, "")
            if ok then tooltipName = rawName end
        end
        if not (tooltipName and string.find(tooltipName, "ShoppingTooltip")) then
            FormatItemTooltip(tooltip, data)
            AppendItemExtraData(tooltip, data)
        end
        
        if WT.Modules.Tooltip.UpdateTooltipStyle then
            WT.Modules.Tooltip:UpdateTooltipStyle(tooltip)
        end
    end)
end