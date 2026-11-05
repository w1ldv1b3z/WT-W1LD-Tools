local _, WT = ...
local Module = WT.Modules.Tooltip

-- Weak table for taint-free tooltip variables
Module.TooltipClassCache = setmetatable({}, { __mode = "k" })

local inspectCache = {}
local currentInspectGUID = nil
local currentInspectUnit = nil
local lastInspectTime = 0
local cachedPlayerGuild = nil
local mountSpellCache = {}
local targetStringCache = {}

local travelFormSpells = {
    [783] = true,    -- Travel Form
    [165077] = true, -- Travel Form (Update)
    [21019] = true,  -- Flight Form
    [33943] = true,  -- Flight Form
    [40120] = true,  -- Swift Flight Form
    [2645] = true,   -- Ghost Wolf
    [248443] = true, -- Travel Form (Gathering)
}

local CLASS_TO_ID = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
    DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8, WARLOCK = 9, MONK = 10,
    DRUID = 11, DEMONHUNTER = 12, EVOKER = 13
}

local Unsecret = WT.Utils.Safety.Unsecret
local SafeNum = WT.Utils.Safety.SafeNum

local strtrim = strtrim or string.trim or function(s) return s and string.match(s, "^%s*(.-)%s*$") or "" end
local strsplit = strsplit or string.split or function(d, s)
    if not s then return nil end
    local t, i = {}, 1
    while true do
        local j = string.find(s, d, i, true)
        if not j then table.insert(t, string.sub(s, i)) break end
        table.insert(t, string.sub(s, i, j - 1))
        i = j + #d
    end
    return (unpack or rawget(table, "unpack"))(t)
end

local function SafeCompare(a, b)
    if not a or not b then return false end
    if scrub then a = scrub(a); b = scrub(b) end
    if not a or not b then return false end
    local ok, res = pcall(function() return a == b end)
    return ok and res
end

local SafeUnitExists = WT.Utils.Units.SafeUnitExists
local SafeUnitGUID = WT.Utils.Units.SafeUnitGUID
local SafeUnitIsPlayer = WT.Utils.Units.SafeUnitIsPlayer
local SafeUnitIsUnit = WT.Utils.Units.SafeUnitIsUnit
local SafeUnitIsAFK = WT.Utils.Units.SafeUnitIsAFK
local SafeUnitIsDND = WT.Utils.Units.SafeUnitIsDND
local SafeCanInspect = WT.Utils.Units.SafeCanInspect
local SafeUnitName = WT.Utils.Units.SafeUnitName
local SafeUnitClass = WT.Utils.Units.SafeUnitClass
local SafeUnitLevel = WT.Utils.Units.SafeUnitLevel
local SafeUnitSex = WT.Utils.Units.SafeUnitSex
local SafeUnitFactionGroup = WT.Utils.Units.SafeUnitFactionGroup
local SafeUnitRace = WT.Utils.Units.SafeUnitRace
local SafeGetGuildInfo = WT.Utils.Units.SafeGetGuildInfo

local function GetQualityHex(quality)
    local hex = "ffffffff"
    if WT.DB.CharacterSheet then
        if quality == 0 then hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColPoor, 0.62, 0.62, 0.62)
        elseif quality == 1 then hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColCommon, 1, 1, 1)
        elseif quality == 2 then hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColUncommon, 0.12, 1, 0)
        elseif quality == 3 then hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColRare, 0, 0.44, 0.87)
        elseif quality == 4 then hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColEpic, 0.64, 0.19, 0.79)
        elseif quality == 5 then hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColLegendary, 1, 0.5, 0)
        elseif quality == 6 then hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColArtifact, 0.9, 0.8, 0.5)
        elseif quality == 7 then hex = WT.Colors:GetHex(WT.DB.CharacterSheet.ItemLevelColHeirloom, 0, 0.8, 1)
                elseif quality then 
                    if C_Item and type(C_Item.GetItemQualityColor) == "function" then
                        local _, _, _, hexColor = C_Item.GetItemQualityColor(quality)
                        if hexColor then hex = hexColor end 
                    end
                end
    elseif quality then
                if C_Item and type(C_Item.GetItemQualityColor) == "function" then
                    local _, _, _, hexColor = C_Item.GetItemQualityColor(quality)
                    if hexColor then hex = hexColor end
                end
    end
    return string.gsub(hex, "^#", "")
end

local fnGetInvItemLink = _G["GetInventoryItemLink"]
local fnGetItemQuality = C_Item and C_Item.GetItemQualityByID
local fnReqLoadItem = C_Item and C_Item.RequestLoadItemDataByID

local function GetUnitAvgQuality(unit)
    local tQ, c = 0, 0
    local maxSlots = (WT.Compat and WT.Compat.IsForever) and 18 or 17
    for i = 1, maxSlots do 
        if i ~= 4 then 
            local link = Unsecret(fnGetInvItemLink(unit, i))
            if link then 
                local q = SafeNum(fnGetItemQuality and fnGetItemQuality(link))
                if q and q >= 0 then 
                    tQ = tQ + q; c = c + 1 
                elseif fnReqLoadItem then
                    fnReqLoadItem(link)
                end 
            end 
        end 
    end
    return c > 0 and math.floor((tQ/c)+0.5) or 1, c
end

local function RefreshTooltip(tooltip, guid)
    if not tooltip or not tooltip:IsVisible() or tooltip:IsForbidden() or InCombatLockdown() then return end
    
    local ttData = tooltip["GetTooltipData"] and tooltip["GetTooltipData"](tooltip)
    if not ttData or Unsecret(ttData.guid) ~= guid then return end
    
    local isFading = tooltip.fadeOut or (tooltip.fadeInfo and tooltip.fadeInfo.mode == "OUT") or (tooltip:GetAlpha() < 0.95)
    if isFading then return end
    
    if tooltip == GameTooltip then
        local owner = tooltip:GetOwner()
        if not (SafeCompare(SafeUnitGUID("mouseover"), guid) or (owner and owner ~= UIParent and owner ~= WorldFrame and owner:IsMouseOver())) then return end
    end
    
    if type(tooltip["RefreshData"]) == "function" then tooltip["RefreshData"](tooltip) end
end

local function EscapeRegex(str)
    if type(str) ~= "string" then return "" end
    return string.gsub(str, "([%%%.%+%-%*%?%[%]%^%$%(%)])", "%%%1")
end

local levelWord = LEVEL or "Level"
local safeLevelWord = EscapeRegex(levelWord)
local pStr = PLAYER or "Player"
local prefixCache = {}
local function GetPrefixRegex(label)
    if not prefixCache[label] then
        prefixCache[label] = "^" .. EscapeRegex(label)
    end
    return prefixCache[label]
end

local playerGSCache = { time = 0, ilvl = 0, qual = 1 }
local targetCountCache = { time = 0, guid = nil, count = 0 }

local lfgSortedClasses = {}
local colorizeTokens = {}
local classNamesCache = {}

local function LfgTokenizeColor(m)
    table.insert(colorizeTokens, m)
    return "\001" .. #colorizeTokens .. "\002"
end
local function LfgTokenizeReset(m)
    table.insert(colorizeTokens, m)
    return "\003" .. #colorizeTokens .. "\004"
end
local function LfgTokenizeIcon(m)
    table.insert(colorizeTokens, m)
    return "\005" .. #colorizeTokens .. "\006"
end
local function LfgDetokenize(id)
    return colorizeTokens[tonumber(id)] or ""
end

local function ColorizeClass(text, cName, hex)
    if not cName or not string.find(text, cName, 1, true) then return text end
    
    local safeName = WT.Utils.Strings:EscapeRegex(cName)
    local targetColor = "|c" .. hex
    
    -- Prevents double coloring
    if string.find(text, targetColor .. cName .. "|r", 1, true) then return text end
    
    -- Saves the active Blizzard color to restore it after our own |r
    local prefix = string.match(text, "(|c%x%x%x%x%x%x%x%x)[^|]*" .. safeName)
    local restoreColor = prefix or ""
    
    local hasTokens = string.find(text, "|", 1, true)
    local temp = text
    if hasTokens then
        -- Converts color tags and icons into single, non-alphanumeric control characters
        wipe(colorizeTokens)
        temp = string.gsub(text, "(|c%x%x%x%x%x%x%x%x)", LfgTokenizeColor)
        temp = string.gsub(temp, "(|r)", LfgTokenizeReset)
        temp = string.gsub(temp, "(|[AT].-|[at])", LfgTokenizeIcon)
    end
    
    -- Padding and [^%w_\128-\255] ensures that e.g. "Mage" inside "Damage" or UTF-8 words is ignored
    local padded = " " .. temp .. " "
    local newText = string.gsub(padded, "([^%w_\128-\255])(" .. safeName .. ")([^%w_\128-\255])", "%1" .. targetColor .. "%2|r" .. restoreColor .. "%3")
    newText = string.sub(newText, 2, -2)
    
    if hasTokens then
        -- Restores the color tags
        newText = string.gsub(newText, "\001(%d+)\002", LfgDetokenize)
        newText = string.gsub(newText, "\003(%d+)\004", LfgDetokenize)
        newText = string.gsub(newText, "\005(%d+)\006", LfgDetokenize)
    end
    
    return newText
end

local function ProcessLfgLine(lineObj)
    if lineObj and lineObj:IsShown() then
        local t = lineObj:GetText()
        if t then
            -- BATTLE-SAFE: Ignore secret strings in restricted UI environments
            local isSecret = false
            if type(t) == "string" then
                local ok = pcall(string.match, t, "")
                if not ok then isSecret = true end
            end
            if isSecret then return end
            
            local newT = t
            for _, classData in ipairs(lfgSortedClasses) do
                local classLoc = LOCALIZED_CLASS_NAMES_MALE[classData.eng]
                local classLocF = LOCALIZED_CLASS_NAMES_FEMALE[classData.eng]
                local hex = WT.Colors:GetHex(classData.color)
                
                newT = ColorizeClass(newT, classLoc, hex)
                if classLocF and classLocF ~= classLoc then
                    newT = ColorizeClass(newT, classLocF, hex)
                end
            end
            local ok, diff = pcall(function() return newT ~= t end)
            if ok and diff then lineObj:SetText(newT) end
        end
    end
end

function Module:ColorizeLFGTooltipClasses(tooltip)
    if not WT.DB.Modules.Tooltip or not WT.DB.Tooltip.ExtClass then return end
    if not tooltip or tooltip:IsForbidden() then return end
    local tooltipName = tooltip:GetName()
    if not tooltipName then return end

    if #lfgSortedClasses == 0 then
        for classEng, color in pairs(WT.DB.ClassColors or RAID_CLASS_COLORS) do
            table.insert(lfgSortedClasses, { eng = classEng, color = color })
        end
        -- Sort by length to prevent partial matches (e.g. "Demon Hunter" before "Hunter")
        table.sort(lfgSortedClasses, function(a, b)
            local aLoc = LOCALIZED_CLASS_NAMES_MALE[a.eng] or a.eng
            local bLoc = LOCALIZED_CLASS_NAMES_MALE[b.eng] or b.eng
            return string.len(aLoc) > string.len(bLoc)
        end)
    end

    for i = 2, tooltip:NumLines() do
        ProcessLfgLine(_G[tooltipName .. "TextLeft" .. i])
        ProcessLfgLine(_G[tooltipName .. "TextRight" .. i])
    end
end

local function GetTotClassColor(c) return WT.DB.ClassColors and WT.DB.ClassColors[c] or RAID_CLASS_COLORS[c] end

local function FormatUnitTooltip(tooltip, data)
    if tooltip:IsForbidden() then return end
    if data and data.type ~= Enum.TooltipDataType.Unit then return end
    if type(tooltip.NumLines) ~= "function" then return end
    if not WT.DB.Modules.Tooltip then return end
    local tooltipName = WT.Utils.Safety.GetSafeTooltipName(tooltip)
    if not tooltipName then return end
    
    local db = WT.DB.Tooltip
    if not db then return end
    local needsLineScan = db.ShowRealm or db.ClassColor or db.ExtLevel or db.Gender or db.ExtFactionIcon or db.GuildRank or db.ExtGuild or db.GuildBro or db.ExtClass or (db.PlayerStyle and db.PlayerStyle ~= "DEFAULT")
    local needsExtra = db.TargetOfTarget or db.Mount or db.TargetCount or db.NerdIDs
    if not needsLineScan and not needsExtra then return end
    
    local unit = nil
    if data and data.guid then
        local uGuid = Unsecret(data.guid)
        if uGuid then
            if SafeCompare(SafeUnitGUID("mouseover"), uGuid) then unit = "mouseover"
            elseif SafeCompare(SafeUnitGUID("target"), uGuid) then unit = "target"
            elseif SafeCompare(SafeUnitGUID("focus"), uGuid) then unit = "focus"
            end
        end
    end
    if not unit then
        local okUnit, _, unitRaw = pcall(tooltip.GetUnit, tooltip)
        if okUnit and type(unitRaw) == "string" then
            unit = Unsecret(unitRaw)
        end
    end

    local currentTooltipName = WT.Utils.Safety.GetSafeTooltipName(tooltip)
    if not unit and currentTooltipName == "NamePlateTooltip" and SafeUnitExists("mouseover") then
        unit = "mouseover"
    end

    local isPlayer = false
    ---@type string|nil, string|nil, string|nil, string|nil, number|nil
    local className, class, raceName, engRace, sex
    local guid = (data and data.guid and Unsecret(data.guid)) or (unit and SafeUnitGUID(unit))

    if unit then
        isPlayer = SafeUnitIsPlayer(unit)
        className, class = SafeUnitClass(unit)
        raceName, engRace = SafeUnitRace(unit)
        sex = SafeUnitSex(unit)
    end
    if not isPlayer and guid and type(guid) == "string" and string.match(guid, "^Player%-") then
        isPlayer = true
        local locClass, engClass, locRace, eRace, pSex = WT.Utils:GetPlayerInfoByGUID(guid)
        if locClass or engClass then
            className, class = locClass, engClass
            raceName, engRace = locRace, eRace
            sex = pSex
        end
    elseif isPlayer and (not class or not raceName) and guid and type(guid) == "string" and string.match(guid, "^Player%-") then
        local locClass, engClass, locRace, eRace, pSex = WT.Utils:GetPlayerInfoByGUID(guid)
        if locClass or engClass then
            if not className then className = locClass end
            if not class then class = engClass end
            if not raceName then raceName = locRace end
            if not engRace then engRace = eRace end
            if not sex then sex = pSex end
        end
    end
        
        if class and sex then
            if sex == 3 and LOCALIZED_CLASS_NAMES_FEMALE[class] then
                className = LOCALIZED_CLASS_NAMES_FEMALE[class]
            elseif LOCALIZED_CLASS_NAMES_MALE[class] then
                className = LOCALIZED_CLASS_NAMES_MALE[class]
            end
        end

    local lfgLvl = nil
    if not className and type(tooltip.GetOwner) == "function" then
        local owner = tooltip:GetOwner()
        if owner and owner.applicantID and owner.memberIdx then
                if C_LFGList and type(C_LFGList.GetApplicantMemberInfo) == "function" then
                    local ok, _, classEng, classLoc, level = pcall(C_LFGList.GetApplicantMemberInfo, owner.applicantID, owner.memberIdx)
                    if ok and classLoc then
                        className = Unsecret(classLoc)
                        local ce = Unsecret(classEng)
                        class = type(ce) == "string" and string.upper(ce) or nil
                        isPlayer = true
                        lfgLvl = SafeNum(level)
                    end
            end
        end
    end

    local lvl = unit and SafeUnitLevel(unit) or lfgLvl
    local lvlStr = (lvl and lvl > 0) and tostring(lvl) or "??"
    local lvlHex = WT.Colors:GetHex(WT.DB.Tooltip.ColLevelV, 1, 0.8196, 0)
    
    local classHex, classColor, facIcon, gName, guildRankName, guildHex, genderStr = nil, nil, "", nil, nil, nil, ""
    
    if class then
        local ok, color = pcall(function() return WT.DB.ClassColors and WT.DB.ClassColors[class] or RAID_CLASS_COLORS[class] end)
        if ok and color then
            classColor = color
            classHex = WT.Colors:GetHex(color)
        else
            classHex = "ffffffff"
        end
    end

    if isPlayer then
        if sex == 2 and WT.DB.Tooltip.Gender then 
            local mStr = string.gsub(tostring(WT.L.GENDER_MALE), "[%(%)]", "")
            genderStr = string.format(" (|c%s%s|r)", WT.Colors:GetHex(WT.DB.Tooltip.ColMale, 0, 0.44, 1), mStr)
        elseif sex == 3 and WT.DB.Tooltip.Gender then 
            local fStr = string.gsub(tostring(WT.L.GENDER_FEMALE), "[%(%)]", "")
            genderStr = string.format(" (|c%s%s|r)", WT.Colors:GetHex(WT.DB.Tooltip.ColFemale, 1, 0.41, 0.7), fStr) 
        end
        
        local fGroup
        if unit then fGroup = SafeUnitFactionGroup(unit) end
        if not fGroup and engRace then
            fGroup = WT.Utils.Units.RACE_TO_FACTION[engRace]
        end
        if not fGroup and isPlayer then
            local ok, myFaction = pcall(UnitFactionGroup, "player")
            if ok and myFaction == "Alliance" then
                fGroup = "Horde"
            elseif ok and myFaction == "Horde" then
                fGroup = "Alliance"
            end
        end
        
        if unit then gName, guildRankName = SafeGetGuildInfo(unit) end
        if gName and string.find(gName, "%-") then
            local cleanGuild = strsplit("-", gName)
            if cleanGuild then gName = cleanGuild end
        end
        if not fGroup and engRace then fGroup = WT.Utils.Units.RACE_TO_FACTION[engRace] end
        if gName then guildHex = WT.Colors:GetHex(WT.DB.Tooltip.ColGuildV, 0.2, 1, 0.2) end
        
        if WT.DB.Tooltip.ExtFactionIcon then
            if fGroup == "Horde" then facIcon = " |TInterface\\FriendsFrame\\PlusManz-Horde:14:14:0:-1|t"
            elseif fGroup == "Alliance" then facIcon = " |TInterface\\FriendsFrame\\PlusManz-Alliance:14:14:0:-1|t" end
        end
    end

    local hasModifiedLevel = false
    local hasModifiedGuild = false
    local hasModifiedClass = false

    local safeLvlStr = EscapeRegex(lvlStr)
    local gNameSafe = EscapeRegex(gName)
    
    local safeClassNames = nil
    if WT.DB.Tooltip.ExtClass and classHex and (class or className) then
        local cacheKey = tostring(class) .. "_" .. tostring(className)
        if not classNamesCache[cacheKey] then
            local arr = {}
            if class then
                if LOCALIZED_CLASS_NAMES_MALE[class] then table.insert(arr, { raw = LOCALIZED_CLASS_NAMES_MALE[class], safe = EscapeRegex(LOCALIZED_CLASS_NAMES_MALE[class]) }) end
                if LOCALIZED_CLASS_NAMES_FEMALE[class] and LOCALIZED_CLASS_NAMES_FEMALE[class] ~= LOCALIZED_CLASS_NAMES_MALE[class] then table.insert(arr, { raw = LOCALIZED_CLASS_NAMES_FEMALE[class], safe = EscapeRegex(LOCALIZED_CLASS_NAMES_FEMALE[class]) }) end
            end
            if className then
                local exists = false
                for _, v in ipairs(arr) do if v.raw == className then exists = true; break end end
                if not exists then table.insert(arr, { raw = className, safe = EscapeRegex(className) }) end
            end
            if #arr > 1 then
                table.sort(arr, function(a, b) return string.len(a.raw) > string.len(b.raw) end)
            end
            classNamesCache[cacheKey] = arr
        end
        safeClassNames = classNamesCache[cacheKey]
    end

    for i = tooltip:NumLines(), 1, -1 do
        if not needsLineScan then break end
        
        local line = _G[tooltipName .. "TextLeft" .. i]
        local rightLine = _G[tooltipName .. "TextRight" .. i]
        local lineData = data and data.lines and data.lines[i]
        local rawText = line and line:IsShown() and lineData and lineData.leftText
        local text = Unsecret(rawText)
        
        local isSafeText = false
        if type(text) == "string" then
            local ok, res = pcall(function() return text ~= "" and string.len(text) > 0 end)
            if ok and res then isSafeText = true end
        end
        
        if isSafeText then
                    local lType = lineData and lineData.type or nil

                    if i == 1 then
                        local roleIcon = ""
                        if unit and WT.DB.Tooltip.ClassColor and type(UnitGroupRolesAssigned) == "function" then
                            local ok, rawRole = pcall(UnitGroupRolesAssigned, unit)
                            local role = ok and Unsecret(rawRole) or nil
                            if role == "TANK" then roleIcon = "|A:groupfinder-icon-role-micro-tank:14:14|a "
                            elseif role == "HEALER" then roleIcon = "|A:groupfinder-icon-role-micro-heal:14:14|a "
                            elseif role == "DAMAGER" then roleIcon = "|A:groupfinder-icon-role-micro-dps:14:14|a " end
                        end
                        
                        if WT.DB.Tooltip.ShowRealm and string.find(text, "%-") then
                            local rName = nil
                            if unit then 
                                _, rName = SafeUnitName(unit)
                            end
                            if (not rName or rName == "") and guid then
                        local _, _, _, _, _, _, pRealm = WT.Utils:GetPlayerInfoByGUID(guid)
                            if pRealm and pRealm ~= "" then rName = pRealm end
                            end
                            
                            if rName and rName ~= "" then
                                text = string.gsub(text, "%-" .. WT.Utils.Strings:EscapeRegex(rName), "")
                                text = string.gsub(text, "%-" .. WT.Utils.Strings:EscapeRegex(string.gsub(rName, "%s+", "")), "")
                            else
                                local cleanTxt = text
                                if string.find(cleanTxt, "|", 1, true) then
                                    cleanTxt = string.gsub(cleanTxt, "|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", ""):gsub("|[AT].-|[at]", "")
                                end
                                local base, possibleRealm = string.match(cleanTxt, "^(.*)%-([^%-%s]+)$")
                                if base and possibleRealm then
                                    if WT.Utils and WT.Utils.Realms and type(WT.Utils.Realms.IsKnownRealm) == "function" then
                                        if WT.Utils.Realms:IsKnownRealm(possibleRealm) then
                                            text = string.gsub(text, "%-" .. WT.Utils.Strings:EscapeRegex(possibleRealm), "")
                                        end
                                    end
                                end
                            end
                        end
                        
                        if string.find(text, "|", 1, true) then
                            if isPlayer and WT.DB.Tooltip.ClassColor then
                                text = string.gsub(text, "|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
                            end
                            text = string.gsub(text, "|A:groupfinder%-icon%-role.-|a%s*", "")
                        end
                        
                        line:SetText(roleIcon .. text)
                        
                        if isPlayer and WT.DB.Tooltip.ClassColor and classColor then
                            local r, g, b = WT.Colors:GetRGB(classColor)
                            line:SetTextColor(r, g, b)
                        end
                    else
                    local cleanText = text
                    if string.find(cleanText, "|", 1, true) then
                        cleanText = string.gsub(cleanText, "|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                    end
                    local trimmedClean = strtrim(cleanText)
                    
                    local isLevelLine = false
                    if string.find(trimmedClean, "^" .. safeLevelWord .. "%s+") or string.match(trimmedClean, "^%?%?") or string.match(trimmedClean, "^Stufe%s+") then
                        isLevelLine = true
                    end
                    
                    -- 1. Level Line
                    if isLevelLine and not hasModifiedLevel then
                        hasModifiedLevel = true
                        
                        if lvlStr == "??" then
                            local extracted = string.match(trimmedClean, "%d+")
                            if extracted then lvlStr = extracted end
                        end
                        
                        if isPlayer and raceName then
                            -- Player Level Line Rebuild
                            local useHex = (lvlStr == "??") and "ffff0000" or lvlHex
                            local fIconStr = (WT.DB.Tooltip.ExtFactionIcon and facIcon) and facIcon or ""
                            
                            local lvlPart = WT.DB.Tooltip.ExtLevel and ("|c" .. useHex .. "[" .. lvlStr .. "]|r") or (levelWord .. " " .. lvlStr)
                            
                            local statusPart = ""
                            if unit and SafeUnitIsAFK(unit) then statusPart = "|cffffd100[AFK]|r"
                            elseif unit and SafeUnitIsDND(unit) then statusPart = "|cffff3333[DND]|r"
                            else
                                if data and data.lines and data.lines[1] and data.lines[1].leftText then
                                local nTxt = data.lines[1].leftText
                                nTxt = Unsecret(nTxt)
                                    if type(nTxt) == "string" then
                                        if string.find(nTxt, "<AFK>") or string.find(nTxt, "%(AFK%)") then statusPart = "|cffffd100[AFK]|r"
                                        elseif string.find(nTxt, "<DND>") or string.find(nTxt, "%(DND%)") then statusPart = "|cffff3333[DND]|r" end
                                    end
                                end
                            end
                            
                            local racePart = raceName and (raceName .. (genderStr or "")) or ""
                            
                            local pTag = ""
                            if WT.DB.Tooltip.PlayerStyle == "COLOR" or WT.DB.Tooltip.PlayerStyle == "FORMAT" then
                                local pHex = WT.Colors:GetHex(WT.DB.Tooltip.ColPlayerV, 0.2, 1, 0.2)
                                pTag = "|c" .. pHex .. "(" .. pStr .. ")|r"
                            elseif WT.DB.Tooltip.PlayerStyle ~= "HIDE" then
                                pTag = "(" .. pStr .. ")"
                            end
                            
                            local extraTags = ""
                            local trailing = string.match(trimmedClean, "%(([^%)]+)%)$")
                            if trailing and trailing ~= pStr then
                                extraTags = "(" .. trailing .. ")"
                            end
                            
                            -- Join parts safely and clean up multiple spaces
                            local newLevelLine = lvlPart
                            if statusPart ~= "" then newLevelLine = newLevelLine .. " " .. statusPart end
                            if fIconStr ~= "" then newLevelLine = newLevelLine .. " " .. fIconStr end
                            if racePart ~= "" then newLevelLine = newLevelLine .. " " .. racePart end
                            if pTag ~= "" then newLevelLine = newLevelLine .. " " .. pTag end
                            if extraTags ~= "" then newLevelLine = newLevelLine .. " " .. extraTags end
                            
                            line:SetText(newLevelLine)
                            
                        else
                            -- NPC Level Line Rebuild
                            local newText = text
                            if WT.DB.Tooltip.ExtLevel then
                                local useHex = (lvlStr == "??") and "ffff0000" or lvlHex
                                if string.match(newText, "^|c%x%x%x%x%x%x%x%x%s*" .. safeLevelWord .. "%s+" .. safeLvlStr) then
                                    newText = string.gsub(newText, "^(|c%x%x%x%x%x%x%x%x)%s*" .. safeLevelWord .. "%s+" .. safeLvlStr, "%%1|c" .. useHex .. "[" .. lvlStr .. "]|r")
                                elseif string.match(newText, "^%s*" .. safeLevelWord .. "%s+" .. safeLvlStr) then
                                    newText = string.gsub(newText, "^%s*" .. safeLevelWord .. "%s+" .. safeLvlStr, "|c" .. useHex .. "[" .. lvlStr .. "]|r")
                                elseif string.match(newText, "^|c%x%x%x%x%x%x%x%x%s*Stufe%s+" .. safeLvlStr) then
                                    newText = string.gsub(newText, "^(|c%x%x%x%x%x%x%x%x)%s*Stufe%s+" .. safeLvlStr, "%%1|c" .. useHex .. "[" .. lvlStr .. "]|r")
                                elseif string.match(newText, "^%s*Stufe%s+" .. safeLvlStr) then
                                    newText = string.gsub(newText, "^%s*Stufe%s+" .. safeLvlStr, "|c" .. useHex .. "[" .. lvlStr .. "]|r")
                                elseif lvlStr == "??" then
                                    if string.match(newText, "^|c%x%x%x%x%x%x%x%x%s*%?%?") then
                                        newText = string.gsub(newText, "^(|c%x%x%x%x%x%x%x%x)%s*%?%?", "%%1|cffff0000[??]|r")
                                    elseif string.match(newText, "^%s*%?%?") then
                                        newText = string.gsub(newText, "^%s*%?%?", "|cffff0000[??]|r")
                                    end
                                end
                            end
                            
                            if safeClassNames then
                                for _, cData in ipairs(safeClassNames) do
                                    local targetColor = "|c" .. classHex
                                    local cw = cData.raw
                                    local safeName = cData.safe
                                    if string.find(newText, safeName) and not string.find(newText, targetColor .. cw .. "|r", 1, true) then
                                        local padded = " " .. newText .. " "
                                        local repCount = 0
                                        padded, repCount = string.gsub(padded, "([^%w_\128-\255])(" .. safeName .. ")([^%w_\128-\255])", "%1" .. targetColor .. "%2|r%3")
                                        if repCount > 0 then
                                            newText = string.sub(padded, 2, -2)
                                            break
                                        end
                                    end
                                end
                            end
                            
                            local ok, diff = pcall(function() return newText ~= text end)
                            if ok and diff then
                                line:SetText(newText)
                            end
                        end
                        
                    -- 2. Guild Line
                    elseif isPlayer and gName and not hasModifiedGuild and string.find(trimmedClean, gNameSafe) then
                        hasModifiedGuild = true
                        
                        -- Removes any previously appended guild rank to prevent duplicates during tooltip refreshes
                        if string.find(text, "|c", 1, true) then
                            text = string.gsub(text, " |c%x%x%x%x%x%x%x%x%([^%)]+%)|r%s*$", "")
                        end
                        
                        local gRankText = ""
                        if WT.DB.Tooltip.GuildRank and guildRankName and guildRankName ~= "" then
                            local rankHex = WT.Colors:GetHex(WT.DB.Tooltip.ColGuildRankV, 0.6, 0.6, 0.6)
                            gRankText = " |c" .. rankHex .. "(" .. guildRankName .. ")|r"
                        end
                        
                        local gNameBase = strsplit("-", gName)
                        local playerGuildBase = cachedPlayerGuild and strsplit("-", cachedPlayerGuild)
                        
                        if WT.DB.Tooltip.GuildBro and playerGuildBase and gNameBase == playerGuildBase and not (unit and SafeUnitIsUnit(unit, "player")) then
                            local isFemale = unit and UnitSex(unit) == 3
                            local broText
                            if isFemale then
                                broText = string.format(tostring(WT.L.TT_GUILD_SIS), tostring(guildRankName or ""))
                            else
                                broText = string.format(tostring(WT.L.TT_GUILD_BRO), tostring(guildRankName or ""))
                            end
                            line:SetText("|cff00ff00" .. broText .. "|r")
                        else
                            if WT.DB.Tooltip.ExtGuild and guildHex then
                                local targetColor = "|c" .. guildHex
                                local newText = text
                                
                                if not string.find(newText, targetColor .. gName .. "|r", 1, true) then
                                    newText = string.gsub(newText, "<(" .. gNameSafe .. ")>", "<" .. targetColor .. "%1|r>")
                                    newText = string.gsub(newText, "&lt;(" .. gNameSafe .. ")&gt;", "&lt;" .. targetColor .. "%1|r&gt;")
                                    local okT, sameT = pcall(function() return newText == text end)
                                    if okT and sameT then 
                                        newText = string.gsub(text, gNameSafe, targetColor .. gName .. "|r")
                                    end
                                end
                                line:SetText(newText .. gRankText)
                            else
                                line:SetText(text .. gRankText)
                            end
                        end
                        
                    -- 3. Class Line
                    elseif (class or className) and not hasModifiedClass and not isLevelLine then
                        local isQuestLine = false
                        if lType and Enum.TooltipDataLineType then
                            if lType == Enum.TooltipDataLineType.QuestObjective or lType == Enum.TooltipDataLineType.QuestTitle then
                                isQuestLine = true
                            end
                        end
                        if not isQuestLine and string.match(trimmedClean, "^%-") then
                            isQuestLine = true
                        end
                        
                        if not isQuestLine and safeClassNames then
                            local foundClassWord = nil
                            for _, cData in ipairs(safeClassNames) do
                                if string.find(trimmedClean, cData.safe) then
                                    foundClassWord = cData.raw
                                    break
                                end
                            end
                            
                            if foundClassWord then
                                    hasModifiedClass = true
                                    if WT.DB.Tooltip.ExtClass and classHex then
                                        local targetColor = "|c" .. classHex
                                        local newText = text
                                        
                                        local specIcon = ""
                                        local foundSpecName = nil
                                        if class then
                                            local classID = CLASS_TO_ID[class]
                                            if classID and GetSpecializationInfoForClassID then
                                                for s = 1, 5 do
                                                    local id, sName, _, icon = GetSpecializationInfoForClassID(classID, s)
                                                    if not id then break end
                                                    if sName and string.find(trimmedClean, WT.Utils.Strings:EscapeRegex(sName)) then
                                                        specIcon = icon and ("|T" .. icon .. ":14:14:0:0:64:64:4:60:4:60|t ") or ""
                                                        foundSpecName = sName
                                                        break
                                                    end
                                                end
                                            end
                                        end
                                        
                                        if foundSpecName then
                                            local cleanLine = text
                                            if string.find(cleanLine, "|", 1, true) then
                                                cleanLine = string.gsub(cleanLine, "|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                                            end
                                            if not string.find(cleanLine, "|T", 1, true) then
                                                newText = specIcon .. targetColor .. cleanLine .. "|r"
                                            else
                                                newText = targetColor .. cleanLine .. "|r"
                                            end
                                        else
                                            if not string.find(text, targetColor .. foundClassWord .. "|r", 1, true) then
                                                local safeName = EscapeRegex(foundClassWord)
                                                local tempText, repCount = string.gsub(text, "%f[%w\128-\255](" .. safeName .. ")%f[^%w\128-\255]", targetColor .. "%1|r")
                                                if repCount > 0 then
                                                    newText = tempText
                                                end
                                            end
                                        end
                                        
                                        local ok, diff = pcall(function() return newText ~= text end)
                                        if ok and diff then
                                            line:SetText(newText)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

Module.FormatUnitTooltip = FormatUnitTooltip

local function CheckInspectCache(g) return inspectCache[g] end
local function AppendUnitExtraData(tooltip, unit, isPlayer, guid, data)
    if not guid then return end
    
    -- Performance: Skip expensive API calls completely if no extra info features are enabled
    local db = WT.DB.Tooltip
    if not db or (not db.RealmFlag and not db.ShowRealm and not db.GearScore and not db.PvPRating and not db.MythicPlus and not db.MythicPlusBest and not db.TargetOfTarget and not db.Mount and not db.TargetCount and not db.NerdIDs) then return end
    
    -- Taint protection: GetUnit() can return secret strings on restricted frames
    if not pcall(CheckInspectCache, guid) then return end
    
    local tooltipName = WT.Utils.Safety.GetSafeTooltipName(tooltip)
    if not tooltipName then return end
    local function GetLineIndex(label, isPrefix)
        if not data or not data.lines then return nil end
        for i, lineData in ipairs(data.lines) do
            local txt = lineData.leftText
            txt = Unsecret(txt)
            if txt and txt ~= "" then
                if isPrefix then
                    if string.find(txt, GetPrefixRegex(label)) then return i end
                else
                    if txt == label then return i end
                end
            end
        end
        return nil
    end

    local added = false
    local function SetOrAddDoubleLine(label, value, lr, lg, lb, vr, vg, vb)
        local index = GetLineIndex(label, false)
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
            added = true
        end
    end

    local function SetOrAddLine(text, r, g, b, prefixStr)
        local index = GetLineIndex(prefixStr, true)
        if index then
            local leftLine = _G[tooltipName .. "TextLeft" .. index]
            if leftLine then 
                leftLine:SetText(text); leftLine:SetTextColor(r, g, b) 
            end
        else
            -- AddLine with wrap set to true prevents any unconstrained horizontal stretching
            tooltip:AddLine(text, r, g, b, true)
            added = true
        end
    end

    if isPlayer then
        local unitRealm
        if WT.DB.Tooltip.RealmFlag or WT.DB.Tooltip.ShowRealm then
            if unit then 
                _, unitRealm = SafeUnitName(unit)
            elseif data and data.lines and data.lines[1] and data.lines[1].leftText then
                local nTxtRaw = data.lines[1].leftText
                local okN = type(nTxtRaw) == "string" and pcall(string.match, nTxtRaw, "")
                if okN then
                    local nTxt = nTxtRaw:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", ""):gsub("|[AT].-|[at]", "")
                    if string.find(nTxt, "%-") then 
                        local _, rBase = strsplit("-", nTxt, 2)
                        if rBase then
                            unitRealm = strtrim((strsplit(",", rBase)))
                        end
                    end
                end
            end
        end
        
        local displayRealm = (unitRealm and unitRealm ~= "") and unitRealm or GetRealmName()
        if displayRealm and displayRealm ~= "" then
            local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColRealmL, 1, 0.82, 0)
            local vr, vg, vb = WT.Colors:GetRGB(WT.DB.Tooltip.ColRealmV, 1, 1, 1)
            
            if WT.DB.Tooltip.RealmFlag and WT.Utils and WT.Utils.Realms then
                local flagWithText = WT.Utils.Realms:GetFlagString(displayRealm, true)
                if flagWithText ~= "" then
                    SetOrAddDoubleLine(tostring(WT.L.TT_REGION) .. ":", flagWithText, lr, lg, lb, 1, 1, 1)
                end
            end
            
            if WT.DB.Tooltip.ShowRealm then
                SetOrAddDoubleLine(tostring(WT.L.TT_REALM) .. ":", tostring(displayRealm), lr, lg, lb, vr, vg, vb)
            end
        end
        
        local isForever = WT.Compat and WT.Compat.IsForever
        if not isForever then
            local summary = inspectCache[guid] and inspectCache[guid].mplus
            if not summary or ((SafeNum(summary.currentSeasonScore) or 0) == 0) then
                if C_PlayerInfo and type(C_PlayerInfo.GetPlayerMythicPlusRatingSummary) == "function" then
                    local ok, res = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
                    summary = ok and res or nil
                    if summary then
                        if not inspectCache[guid] then inspectCache[guid] = {} end
                        inspectCache[guid].mplus = summary
                    end
                end
            end
            
            if summary then
                local currentSeasonScore = SafeNum(summary.currentSeasonScore)
                if WT.DB.Tooltip.MythicPlus and currentSeasonScore and currentSeasonScore > 0 then
                    local rarityColor = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(currentSeasonScore)
                    local hex = "ffffffff"
                    if rarityColor then
                        local safeCall = securecallfunction or securecall
                        local ok, res = pcall(safeCall, rarityColor.GenerateHexColor, rarityColor)
                        if ok and res then hex = res end
                    end
                    local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColMplusL, 1, 0.82, 0)
                    SetOrAddDoubleLine(tostring(WT.L.TT_MYTHIC_SCORE), "|c" .. hex .. currentSeasonScore .. "|r", lr, lg, lb, 1, 1, 1)
                end
                
                if WT.DB.Tooltip.MythicPlusBest and summary.runs then
                    local best = 0
                    for _, run in ipairs(summary.runs) do
                        local runLevel = SafeNum(run.bestRunLevel) or 0
                        if runLevel > best then best = runLevel end
                    end
                    if best > 0 then
                        local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColMplusBestL, 1, 0.82, 0)
                        local vr, vg, vb = WT.Colors:GetRGB(WT.DB.Tooltip.ColMplusBestV, 1, 1, 1)
                        SetOrAddDoubleLine(tostring(WT.L.TT_MPLUS_BEST), "+" .. tostring(best), lr, lg, lb, vr, vg, vb)
                    end
                end
            end
        end
        
        local doInspect = WT.DB.Tooltip.GearScore or WT.DB.Tooltip.PvPRating or WT.DB.Tooltip.MythicPlus or WT.DB.Tooltip.MythicPlusBest
        if doInspect then
            if unit and SafeUnitIsUnit(unit, "player") then
                if WT.DB.Tooltip.GearScore then
                    local now = GetTime()
                    if now - playerGSCache.time > 1.0 then
                        local _, avgIlvl = GetAverageItemLevel()
                        playerGSCache.ilvl = SafeNum(avgIlvl) or 0
                        if WT.DB.Tooltip.GearScoreColorize then playerGSCache.qual = GetUnitAvgQuality("player") end
                        playerGSCache.time = now
                    end
                    local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColGsL, 1, 0.82, 0)
                    local hexV = WT.DB.Tooltip.GearScoreColorize and GetQualityHex(playerGSCache.qual) or WT.Colors:GetHex(WT.DB.Tooltip.ColGsV, 1, 0.82, 0)
                    SetOrAddDoubleLine(tostring(WT.L.TT_GEARSCORE), "|c" .. hexV .. math.floor(playerGSCache.ilvl) .. "|r", lr, lg, lb, 1, 1, 1)
                end
                if WT.DB.Tooltip.PvPRating and C_PvP and C_PvP.GetPersonalRatedInfo then
                    local maxPvP = 0
                    for b = 1, 7 do
                        local info = C_PvP.GetPersonalRatedInfo(b)
                        if info then
                            local r = type(info) == "table" and info.rating or (type(info) == "number" and info or 0)
                            r = SafeNum(r) or 0
                            if r > maxPvP then maxPvP = r end
                        end
                    end
                    if maxPvP > 0 then
                        local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColPvpL, 1, 0.82, 0)
                        local hexV = WT.Colors:GetHex(WT.DB.Tooltip.ColPvpV, 0.8, 0.2, 1)
                        SetOrAddDoubleLine(tostring(WT.L.TT_PVPRATING), "|c" .. hexV .. tostring(maxPvP) .. "|r", lr, lg, lb, 1, 1, 1)
                    end
                end
            else
                local cache = inspectCache[guid]
                local needsInspect = false
                
                if cache then
                    if WT.DB.Tooltip.GearScore and cache.ilvl and cache.ilvl > 0 then
                        local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColGsL, 1, 0.82, 0)
                        local hexV = (WT.DB.Tooltip.GearScoreColorize and cache.quality) and GetQualityHex(cache.quality) or WT.Colors:GetHex(WT.DB.Tooltip.ColGsV, 1, 0.82, 0)
                        SetOrAddDoubleLine(tostring(WT.L.TT_GEARSCORE), "|c" .. hexV .. tostring(cache.ilvl) .. "|r", lr, lg, lb, 1, 1, 1)
                    elseif WT.DB.Tooltip.GearScore and (not cache.ilvl or cache.ilvl == 0) then
                        needsInspect = true
                    end
                    
                    if WT.DB.Tooltip.PvPRating and cache.pvp and cache.pvp > 0 then
                        local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColPvpL, 1, 0.82, 0)
                        local hexV = WT.Colors:GetHex(WT.DB.Tooltip.ColPvpV, 0.8, 0.2, 1)
                        SetOrAddDoubleLine(tostring(WT.L.TT_PVPRATING), "|c" .. hexV .. tostring(cache.pvp) .. "|r", lr, lg, lb, 1, 1, 1)
                    elseif WT.DB.Tooltip.PvPRating and not cache.pvp then
                        needsInspect = true
                    end
                    
                    if not (WT.Compat and WT.Compat.IsForever) and (WT.DB.Tooltip.MythicPlus or WT.DB.Tooltip.MythicPlusBest) and (not cache.mplus or (SafeNum(cache.mplus.currentSeasonScore) or 0) == 0) then
                        needsInspect = true
                    end
                else
                    needsInspect = true
                end
                
                if needsInspect and unit and not InCombatLockdown() and SafeCanInspect(unit) then
                    -- Performance protection: No server requests in the first 5 seconds after login
                    if GetTime() - (WT.Core.LoadTime or 0) < 5 then return end
                    
                    local now = GetTime()
                    if now - lastInspectTime > 1.2 then
                        if not (InspectFrame and InspectFrame:IsShown()) then
                            lastInspectTime = now
                            currentInspectGUID = guid
                            currentInspectUnit = unit
                            -- TAINT FIX: We break out of the secure execution path! 
                            -- Executing NotifyInspect directly in TooltipDataProcessor leads to Action Blocked taints.
                            C_Timer.After(0.05, function()
                                if not InCombatLockdown() and not (InspectFrame and InspectFrame:IsShown()) then
                                    if SafeUnitExists(unit) and SafeUnitGUID(unit) == guid and SafeCanInspect(unit) then
                                pcall(_G.NotifyInspect, unit)
                                    end
                                end
                            end)
                        end
                    end
                end
            end
        end
    end
    
    if WT.DB.Tooltip.TargetOfTarget then
        local tot = unit and (unit.."target") or nil
        if SafeUnitExists(tot) then
            local totName
            local isTotPlayer = SafeUnitIsPlayer(tot)
            
            if SafeUnitIsUnit(tot, "player") then
                -- Fast-Path: Target is the player (Massive API optimization + better visual)
                totName = "<< " .. (YOU or "You") .. " >>"
            else
                totName = SafeUnitName(tot)
                if (not totName or totName == "Unknown" or totName == UNKNOWNOBJECT) and isTotPlayer then
                    local guid = SafeUnitGUID(tot)
                    if guid then
                    local _, _, _, _, _, name = WT.Utils:GetPlayerInfoByGUID(guid)
                    if name and name ~= "" then totName = name end
                    end
                end
                totName = totName or "Unknown"
            end
            
            if WT.DB.Tooltip.ClassColor and isTotPlayer then
                local _, totClass = SafeUnitClass(tot)
                local ok, totColor = pcall(GetTotClassColor, totClass)
                if ok and totColor then totName = "|c" .. WT.Colors:GetHex(totColor) .. totName .. "|r" end
            end
            local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColTotL, 1, 0.82, 0)
            local vr, vg, vb = WT.Colors:GetRGB(WT.DB.Tooltip.ColTotV, 1, 0.5, 0)
            SetOrAddDoubleLine(tostring(WT.L.TT_TARGET_PREFIX), totName, lr, lg, lb, vr, vg, vb)
        end
    end
    
    if WT.DB.Tooltip.Mount and isPlayer and unit and not InCombatLockdown() then
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_MountJournal then
            local function GetMountID(sId)
                local mID = mountSpellCache[sId]
                if mID == nil then
                    mID = C_MountJournal.GetMountFromSpell(sId) or false
                    mountSpellCache[sId] = mID
                end
                return mID
            end
            local function CheckTravelForm(sId) return travelFormSpells[sId] end
            
            for i = 1, 40 do
                local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
                if not ok or not aura then break end
                if aura.spellId then
                    local ok, mountID = pcall(GetMountID, aura.spellId)
                    
                    if not ok then
                        local success, mID = pcall(C_MountJournal.GetMountFromSpell, aura.spellId)
                        if success then mountID = mID end
                    end
                    
                    local okForm, isKnownForm = pcall(CheckTravelForm, aura.spellId)
                
                if type(mountID) == "number" or (okForm and isKnownForm) then
                    local mountName = nil
                    if type(mountID) == "number" then
                        local success, mName = pcall(C_MountJournal.GetMountInfoByID, mountID)
                        if success and mName and type(mName) == "string" and mName ~= "" then mountName = Unsecret(mName) end
                    end
                    
                    -- Fallback: Use aura.name if MountInfo fails (uncached) or it's a druid form
                    if not mountName and aura.name then mountName = Unsecret(aura.name) end
                    
                    if mountName then
                            local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColMountL, 1, 0.82, 0)
                            local vr, vg, vb = WT.Colors:GetRGB(WT.DB.Tooltip.ColMountV, 0.8, 0.2, 1)
                            SetOrAddDoubleLine(tostring(WT.L.TT_MOUNT), tostring(mountName), lr, lg, lb, vr, vg, vb)
                            break
                        end
                    end
                end
            end
        end
    end
    
    if WT.DB.Tooltip.TargetCount and unit and not InCombatLockdown() then
        local uGuid = SafeUnitGUID(unit)
        local now = GetTime()
        if uGuid and IsInGroup() then
            local count = 0
            if targetCountCache.guid == uGuid and (now - targetCountCache.time < 0.25) then
                count = targetCountCache.count
            else
                local prefix = IsInRaid() and "raid" or "party"
                local pGuid = SafeUnitGUID("player")
                for i=1, GetNumGroupMembers() do
                    local groupUnit = prefix..i
                    local gGuid = SafeUnitGUID(groupUnit)
                    if not SafeCompare(gGuid, pGuid) then
                        local targetUnit = targetStringCache[groupUnit]
                        if not targetUnit then 
                            targetUnit = groupUnit.."target"
                            targetStringCache[groupUnit] = targetUnit 
                        end
                        if SafeCompare(SafeUnitGUID(targetUnit), uGuid) then count = count + 1 end
                    end
                end
                if SafeCompare(SafeUnitGUID("playertarget"), uGuid) then count = count + 1 end
                targetCountCache.guid = uGuid
                targetCountCache.count = count
                targetCountCache.time = now
            end
            if count > 0 then 
                local prefix = tostring(WT.L.TT_TARGETED_BY)
                SetOrAddLine(prefix .. " " .. count, 0.8, 0.2, 0.2, prefix)
            end
        end
    end
    
    if WT.DB.Tooltip.NerdIDs and WT.DB.Tooltip.NerdIDsNPCs ~= false then
        -- BATTLE-SAFE: Use the already unsecreted 'guid' parameter instead of shadowing it
        if guid and type(guid) == "string" then
            local unitType, _, _, _, _, npc_id = strsplit("-", guid)
            if unitType == "Creature" or unitType == "Vehicle" then
                local safeNpcId = Unsecret(npc_id)
                if safeNpcId then
                    local label = tostring(WT.L.TT_NPC_ID)
                    local lr, lg, lb = WT.Colors:GetRGB(WT.DB.Tooltip.ColNerdL, 0.5, 0.5, 0.5)
                    local vr, vg, vb = WT.Colors:GetRGB(WT.DB.Tooltip.ColNerdV, 1, 1, 1)
                    SetOrAddDoubleLine(label, tostring(safeNpcId), lr, lg, lb, vr, vg, vb)
                end
            end
        end
    end
    
end

function Module:SetupUnitTooltip()
    if not TooltipDataProcessor then return end
    
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
        if tooltip:IsForbidden() then return end
        
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

        local unit = nil
        if data and data.guid then
            local uGuid = Unsecret(data.guid)
            if uGuid then
            if SafeCompare(SafeUnitGUID("mouseover"), uGuid) then unit = "mouseover"
            elseif SafeCompare(SafeUnitGUID("target"), uGuid) then unit = "target"
            elseif SafeCompare(SafeUnitGUID("focus"), uGuid) then unit = "focus"
                end
            end
        end
        if not unit then
            local okUnit, _, unitRaw = pcall(tooltip.GetUnit, tooltip)
            if okUnit and type(unitRaw) == "string" then
            unit = Unsecret(unitRaw)
            end
        end
        
        local isPlayer = false
        ---@type string|nil, string|nil, string|nil, string|nil, number|nil
        local className, class, raceName, engRace, sex
        
        local guid = (data and data.guid and Unsecret(data.guid)) or (unit and SafeUnitGUID(unit))
        if not guid and not unit then return end

        if unit then
            isPlayer = SafeUnitIsPlayer(unit)
            className, class = SafeUnitClass(unit)
            raceName, engRace = SafeUnitRace(unit)
            sex = SafeUnitSex(unit)
        end
        
        -- Fallback to GUID if unit isn't available or didn't yield results
        if not isPlayer and guid and type(guid) == "string" and string.match(guid, "^Player%-") then
            isPlayer = true
        local locClass, engClass, locRace, eRace, pSex = WT.Utils:GetPlayerInfoByGUID(guid)
            if locClass or engClass then
                className, class = locClass, engClass
                raceName, engRace = locRace, eRace
                sex = pSex
            end
        elseif isPlayer and (not class or not raceName) and guid and type(guid) == "string" and string.match(guid, "^Player%-") then
        local locClass, engClass, locRace, eRace, pSex = WT.Utils:GetPlayerInfoByGUID(guid)
            if locClass or engClass then
                if not className then className = locClass end
            if not class then class = engClass end
                if not raceName then raceName = locRace end
                if not engRace then engRace = eRace end
                if not sex then sex = pSex end
            end
        end
        
        if class and isPlayer then WT.Modules.Tooltip.TooltipClassCache[tooltip] = class else WT.Modules.Tooltip.TooltipClassCache[tooltip] = nil end
        
        FormatUnitTooltip(tooltip, data)
        
        AppendUnitExtraData(tooltip, unit, isPlayer, guid, data)
        
        if WT.Modules.Tooltip.UpdateTooltipStyle then
            WT.Modules.Tooltip:UpdateTooltipStyle(tooltip)
        end
        
        if WT.DB.Tooltip.HealthBar then
            local hb = tooltip.healthBar or tooltip.HealthBar or tooltip.statusBar or tooltip.StatusBar or _G["GameTooltipStatusBar"]
            if hb then
                if WT.Modules.Tooltip.HookHealthBar then
                    WT.Modules.Tooltip:HookHealthBar(hb)
                end
                
                if WT.DB.Tooltip.HealthBar and type(hb.GetStatusBarColor) == "function" then
                    local r, g, b = hb:GetStatusBarColor()
                    if r then hb:SetStatusBarColor(r, g, b) end
                end
            end
        end
    
    -- Global Layout Fix: Forces all tooltips to recalculate their width synchronously 
    -- after all text modifications (including those from Tooltip.lua) are finished.
    for _, dataType in pairs(Enum.TooltipDataType) do
        TooltipDataProcessor.AddTooltipPostCall(dataType, function(tt)
            if tt and not tt:IsForbidden() and tt.Layout then
                tt:Layout()
            end
        end)
    end
    end)
end

local function OnInspectReady(guid)
    if not WT.DB.Tooltip.GearScore and not WT.DB.Tooltip.PvPRating and not WT.DB.Tooltip.MythicPlus and not WT.DB.Tooltip.MythicPlusBest then return end
    if type(guid) ~= "string" then return end
    if not pcall(function() return inspectCache[guid] end) then return end
    
    local unit = nil
    if SafeCompare(currentInspectGUID, guid) and currentInspectUnit and SafeCompare(SafeUnitGUID(currentInspectUnit), guid) then
        unit = currentInspectUnit
    end
    
    if not unit then
        if SafeCompare(SafeUnitGUID("mouseover"), guid) then unit = "mouseover"
        elseif SafeCompare(SafeUnitGUID("target"), guid) then unit = "target"
        elseif SafeCompare(SafeUnitGUID("focus"), guid) then unit = "focus"
        end
        
        if not unit and IsInGroup() then
            local prefix = IsInRaid() and "raid" or "party"
            for i = 1, GetNumGroupMembers() do
                if SafeCompare(SafeUnitGUID(prefix..i), guid) then unit = prefix..i; break end
            end
        end
    end
    
    if unit then
        local avg = 0
        local avgQual = 1
        local itemsCounted = 0
        if WT.DB.Tooltip.GearScore and C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then 
            local ok, ilvl = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
            avg = ok and (SafeNum(ilvl) or 0) or 0 
            if WT.DB.Tooltip.GearScoreColorize then avgQual, itemsCounted = GetUnitAvgQuality(unit) end
        end

        local maxPvP = 0
        if WT.DB.Tooltip.PvPRating then
            local inspectFunc = (C_PvP and C_PvP.GetInspectPvPData) or _G.GetInspectArenaData
            if inspectFunc then
                for b = 1, 7 do
                    local success, info = pcall(inspectFunc, b)
                    if success and info then
                        local r = type(info) == "table" and info.rating or (type(info) == "number" and info or 0)
                        r = SafeNum(r) or 0
                        if r > maxPvP then maxPvP = r end
                    end
                end
            end
        end
        
        local mplus = nil
        if WT.DB.Tooltip.MythicPlus or WT.DB.Tooltip.MythicPlusBest then
            if C_PlayerInfo and type(C_PlayerInfo.GetPlayerMythicPlusRatingSummary) == "function" then
                local ok, res = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
                mplus = ok and res or nil
            end
        end

        local mplusScore = mplus and SafeNum(mplus.currentSeasonScore) or 0
        if avg > 0 or maxPvP > 0 or (mplus and mplusScore > 0) then
            if not inspectCache[guid] then inspectCache[guid] = {} end
            if avg > 0 then 
                inspectCache[guid].ilvl = math.floor(avg) 
                inspectCache[guid].quality = avgQual
            end
            if maxPvP > 0 then inspectCache[guid].pvp = maxPvP end
            if mplus then inspectCache[guid].mplus = mplus end
            
            RefreshTooltip(GameTooltip, guid)
            RefreshTooltip(ItemRefTooltip, guid)
        end
        
        if avg == 0 or (WT.DB.Tooltip.GearScoreColorize and itemsCounted < 6) or (mplus and mplusScore == 0) then
            C_Timer.After(0.5, function()
                if unit and SafeCompare(SafeUnitGUID(unit), guid) then
                    local retryAvg = 0
                        local retryQual = 1
                        if WT.DB.Tooltip.GearScore and C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then 
                            local ok, ilvl = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
                            retryAvg = ok and (SafeNum(ilvl) or 0) or 0 
                            if WT.DB.Tooltip.GearScoreColorize then retryQual, _ = GetUnitAvgQuality(unit) end
                        end
                    
                    local retryMplus = nil
                    if WT.DB.Tooltip.MythicPlus or WT.DB.Tooltip.MythicPlusBest then
                        if C_PlayerInfo and type(C_PlayerInfo.GetPlayerMythicPlusRatingSummary) == "function" then
                            local ok, res = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
                            retryMplus = ok and res or nil
                        end
                    end
                    
                    local retryScore = retryMplus and SafeNum(retryMplus.currentSeasonScore) or 0
                    if retryAvg > 0 or (retryMplus and retryScore > 0) then
                        if not inspectCache[guid] then inspectCache[guid] = {} end
                        if retryAvg > 0 then
                            inspectCache[guid].ilvl = math.floor(retryAvg)
                            inspectCache[guid].quality = retryQual
                        end
                        if retryMplus then inspectCache[guid].mplus = retryMplus end
                        
                        RefreshTooltip(GameTooltip, guid)
                        RefreshTooltip(ItemRefTooltip, guid)
                    end
                end
                
                if SafeCompare(currentInspectGUID, guid) then
                    currentInspectGUID = nil
                end
            end)
        else
            if SafeCompare(currentInspectGUID, guid) then
                currentInspectGUID = nil
            end
        end
    else
        if SafeCompare(currentInspectGUID, guid) then
            currentInspectGUID = nil
        end
    end
end

local function PreInspectUnit(unit)
    if not unit or type(unit) ~= "string" then return end
    if string.match(unit, "^nameplate") then return end
    if not WT.DB.Tooltip.GearScore and not WT.DB.Tooltip.PvPRating and not WT.DB.Tooltip.MythicPlus and not WT.DB.Tooltip.MythicPlusBest then return end
    if InCombatLockdown() or not SafeCanInspect(unit) or not SafeUnitIsPlayer(unit) or SafeUnitIsUnit(unit, "player") then return end
    
    -- Performance protection: No server requests in the first 5 seconds after login
    if GetTime() - (WT.Core.LoadTime or 0) < 5 then return end
    
    local guid = SafeUnitGUID(unit)
    if not guid then return end
    if not pcall(CheckInspectCache, guid) then return end
    
    local cache = inspectCache[guid]
    local needsInspect = false
    if not cache then
        needsInspect = true
    else
        if WT.DB.Tooltip.GearScore and (not cache.ilvl or cache.ilvl == 0) then needsInspect = true end
        if WT.DB.Tooltip.PvPRating and not cache.pvp then needsInspect = true end
        if not (WT.Compat and WT.Compat.IsForever) and (WT.DB.Tooltip.MythicPlus or WT.DB.Tooltip.MythicPlusBest) and (not cache.mplus or (SafeNum(cache.mplus.currentSeasonScore) or 0) == 0) then needsInspect = true end
    end
    
    if needsInspect then
        local now = GetTime()
        if now - lastInspectTime > 1.2 and not (InspectFrame and InspectFrame:IsShown()) then
            lastInspectTime = now
            currentInspectGUID = guid
            currentInspectUnit = unit
            C_Timer.After(0.05, function()
                if not InCombatLockdown() and not (InspectFrame and InspectFrame:IsShown()) then
                    if SafeUnitExists(unit) and SafeCompare(SafeUnitGUID(unit), guid) and SafeCanInspect(unit) then
                                pcall(_G.NotifyInspect, unit)
                    end
                end
            end)
        end
    end
end

WT.Core.Events:Register("PLAYER_ENTERING_WORLD", function() 
    cachedPlayerGuild = SafeGetGuildInfo("player") 
    -- Free up memory from old inspection caches when switching zones
    if inspectCache then wipe(inspectCache) end
    if targetStringCache then wipe(targetStringCache) end
end)
WT.Core.Events:Register("PLAYER_GUILD_UPDATE", function() cachedPlayerGuild = SafeGetGuildInfo("player") end)
WT.Core.Events:Register("INSPECT_READY", function(_, guid) OnInspectReady(guid) end)
WT.Core.Events:Register("PLAYER_TARGET_CHANGED", function() PreInspectUnit("target") end)
WT.Core.Events:Register("UPDATE_MOUSEOVER_UNIT", function() PreInspectUnit("mouseover") end)