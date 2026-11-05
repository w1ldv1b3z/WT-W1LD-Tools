local _, WT = ...

WT.Utils.SharedMedia = {}
local SharedMedia = WT.Utils.SharedMedia

local cachedLSM = nil
local hasCheckedLSM = false

local function GetLSM()
    if not hasCheckedLSM then
        hasCheckedLSM = true
        if type(LibStub) == "table" then
            local lib = LibStub("LibSharedMedia-3.0", true)
            if type(lib) == "table" then
                cachedLSM = lib
                
                local mt = lib["MediaType"]
                local soundKey = (type(mt) == "table" and mt["SOUND"]) or "sound"
                local fontKey = (type(mt) == "table" and mt["FONT"]) or "font"
                local statusbarKey = (type(mt) == "table" and mt["STATUSBAR"]) or "statusbar"
                local backgroundKey = (type(mt) == "table" and mt["BACKGROUND"]) or "background"
                local borderKey = (type(mt) == "table" and mt["BORDER"]) or "border"
                local highlightKey = (type(mt) == "table" and mt["HIGHLIGHT"]) or "highlight"
                
                local regFunc = lib["Register"]
                if type(regFunc) == "function" then
                    for sName, soundPath in pairs(WT.Utils.Audio.w1ldSounds or {}) do
                        regFunc(lib, soundKey, sName, soundPath)
                    end
                    
                    if WT.CustomMedia and type(WT.CustomMedia.Fonts) == "table" then
                        for fName, fontPath in pairs(WT.CustomMedia.Fonts) do
                            regFunc(lib, fontKey, fName, fontPath)
                        end
                    end
                    
                    if WT.CustomMedia and type(WT.CustomMedia.Statusbars) == "table" then
                        for sbName, sbPath in pairs(WT.CustomMedia.Statusbars) do
                            regFunc(lib, statusbarKey, sbName, sbPath)
                        end
                    end
                    
                    if WT.CustomMedia and type(WT.CustomMedia.Backgrounds) == "table" then
                        for bgName, bgPath in pairs(WT.CustomMedia.Backgrounds) do
                            regFunc(lib, backgroundKey, bgName, bgPath)
                        end
                    end
                    
                    if WT.CustomMedia and type(WT.CustomMedia.Borders) == "table" then
                        for bName, bPath in pairs(WT.CustomMedia.Borders) do
                            regFunc(lib, borderKey, bName, bPath)
                        end
                    end
                    
                    if WT.CustomMedia and type(WT.CustomMedia.Highlights) == "table" then
                        for hName, hPath in pairs(WT.CustomMedia.Highlights) do
                            regFunc(lib, highlightKey, hName, hPath)
                        end
                    end
                end
            end
        end
    end
    return cachedLSM
end

local debuggedMedia = {}

function SharedMedia:Fetch(mediaType, key)
    local fetched = nil
    local LSM = GetLSM()
    if type(LSM) == "table" then
        local fetchFunc = LSM["Fetch"]
        if type(fetchFunc) == "function" then
            fetched = fetchFunc(LSM, mediaType, key)
        end
    end
    
    -- Native fallbacks in case LibSharedMedia is not loaded
    if not fetched and mediaType == "font" then
        if WT.CustomMedia and WT.CustomMedia.Fonts and WT.CustomMedia.Fonts[key] then fetched = WT.CustomMedia.Fonts[key]
        elseif key == "Friz Quadrata TT" then fetched = "Fonts\\FRIZQT__.TTF"
        elseif key == "Arial Narrow" then fetched = "Fonts\\ARIALN.TTF"
        elseif key == "Morpheus" then fetched = "Fonts\\MORPHEUS.TTF"
        elseif key == "Skurri" then fetched = "Fonts\\skurri.ttf" end
    elseif not fetched and mediaType == "statusbar" then
        if WT.CustomMedia and WT.CustomMedia.Statusbars and WT.CustomMedia.Statusbars[key] then fetched = WT.CustomMedia.Statusbars[key]
        elseif key == "Blizzard" then fetched = "Interface\\TargetingFrame\\UI-StatusBar" end
    elseif not fetched and mediaType == "background" then
        if WT.CustomMedia and WT.CustomMedia.Backgrounds and WT.CustomMedia.Backgrounds[key] then fetched = WT.CustomMedia.Backgrounds[key]
        elseif key == "Blizzard Tooltip" then fetched = "Interface\\Tooltips\\UI-Tooltip-Background"
        elseif key == "Blizzard Chat" then fetched = "Interface\\ChatFrame\\ChatFrameBackground" end
    elseif not fetched and mediaType == "border" then
        if WT.CustomMedia and WT.CustomMedia.Borders and WT.CustomMedia.Borders[key] then fetched = WT.CustomMedia.Borders[key]
        elseif key == "Blizzard Tooltip" then fetched = "Interface\\Tooltips\\UI-Tooltip-Border"
        elseif key == "Blizzard Dialog" then fetched = "Interface\\DialogFrame\\UI-DialogBox-Border" end
    elseif not fetched and mediaType == "highlight" then
        if WT.CustomMedia and WT.CustomMedia.Highlights and WT.CustomMedia.Highlights[key] then fetched = WT.CustomMedia.Highlights[key]
        elseif key == "Blizzard" then fetched = "Interface\\QuestFrame\\UI-QuestTitleHighlight" end
    end
    
    fetched = fetched or key
    
    if type(fetched) == "string" then
        -- FORCE CACHE: Pre-loading custom fonts and textures on hidden elements forces the WoW Engine 
        -- to immediately cache them in memory, ensuring instant visual updates across the UI!
        if not SharedMedia.dummyFrame then 
            SharedMedia.dummyFrame = CreateFrame("Frame", nil, _G["WT_UIContainer"] or UIParent)
            SharedMedia.dummyFrame.ignoreInLayout = true
            SharedMedia.dummyFrame.ignoreFramePositionManager = true
            if SharedMedia.dummyFrame.SetIsFramePositionManaged then pcall(function() SharedMedia.dummyFrame:SetIsFramePositionManaged(false) end) end
            SharedMedia.dummyFrame:SetAlpha(0)
            SharedMedia.dummyFS = SharedMedia.dummyFrame:CreateFontString(nil, "BACKGROUND")
            SharedMedia.dummyTex = SharedMedia.dummyFrame:CreateTexture(nil, "BACKGROUND")
        end

        if mediaType == "font" then
            local success = SharedMedia.dummyFS:SetFont(fetched, 12, "")
            pcall(function() SharedMedia.dummyFS:SetText("W1LD_CACHE") end)
            if WT.DB and WT.DB.General and WT.DB.General.DebugMode and WT.Utils and WT.Utils.Logger then
                if not debuggedMedia[fetched] then
                    debuggedMedia[fetched] = true
                    WT.Utils.Logger:Debug(string.format(WT.L.MSG_DEBUG_FONT, fetched, success and WT.L.LBL_YES or WT.L.LBL_NO))
                end
            end
        elseif mediaType == "statusbar" or mediaType == "background" or mediaType == "border" or mediaType == "highlight" then
            SharedMedia.dummyTex:SetTexture(fetched)
        end
    end

    return fetched
end

local optionsCache = {}

function SharedMedia:GetOptions(mediaType)
    if optionsCache[mediaType] then return optionsCache[mediaType] end
    
    local options = {}
    
    if mediaType == "sound" then
        table.insert(options, { value = "None", label = "None" })
        
        table.insert(options, { value = "WT_SEPARATOR", label = "--- Standard ---" })
        local stdKeys = {}
        for k in pairs(WT.Utils.Audio.standardSounds) do
            if k ~= "None" then table.insert(stdKeys, k) end
        end
        table.sort(stdKeys)
        for _, k in ipairs(stdKeys) do table.insert(options, { value = k, label = k }) end
        
        table.insert(options, { value = "WT_SEPARATOR", label = "--- W1LD Tools ---" })
        local w1ldKeys = {}
        for k in pairs(WT.Utils.Audio.w1ldSounds) do table.insert(w1ldKeys, k) end
        
        local LSM = GetLSM()
        local mt = type(LSM) == "table" and LSM["MediaType"] or nil
        local soundKey = (type(mt) == "table" and mt["SOUND"]) or "sound"
        
        local smSounds = nil
        if type(LSM) == "table" then
            local listFunc = LSM["List"]
            if type(listFunc) == "function" then
                smSounds = listFunc(LSM, soundKey)
            end
        end

        -- Add all SharedMedia sounds that start with "W1LD" to our list
        if smSounds then
            for _, sName in ipairs(smSounds) do
                if string.match(sName, "^W1LD") and not WT.Utils.Audio.w1ldSounds[sName] then
                    table.insert(w1ldKeys, sName)
                end
            end
        end
        
        table.sort(w1ldKeys)
        for _, k in ipairs(w1ldKeys) do table.insert(options, { value = k, label = k }) end
        
        if LSM then
            if smSounds and #smSounds > 0 then
                local addedSeparator = false
                for _, sName in ipairs(smSounds) do
                    -- Put all remaining external sounds into the SharedMedia category
                    if sName ~= "None" and not WT.Utils.Audio.w1ldSounds[sName] and not WT.Utils.Audio.standardSounds[sName] and not string.match(sName, "^W1LD") then
                        if not addedSeparator then
                        table.insert(options, { value = "WT_SEPARATOR", label = "--- External Media ---" })
                            addedSeparator = true
                        end
                        table.insert(options, { value = sName, label = sName })
                    end
                end
            end
        end
        
    elseif mediaType == "font" then
        table.insert(options, { value = "WT_SEPARATOR", label = "--- Standard ---" })
        table.insert(options, { value = "Friz Quadrata TT", label = "Friz Quadrata TT" })
        table.insert(options, { value = "Arial Narrow", label = "Arial Narrow" })
        table.insert(options, { value = "Morpheus", label = "Morpheus" })
        table.insert(options, { value = "Skurri", label = "Skurri" })
        
        local w1ldKeys = {}
        for k in pairs(WT.CustomMedia.Fonts or {}) do table.insert(w1ldKeys, k) end
        
        local LSM = GetLSM()
        local mt = type(LSM) == "table" and LSM["MediaType"] or nil
        local fontKey = (type(mt) == "table" and mt["FONT"]) or "font"
        
        local smFonts = nil
        if type(LSM) == "table" then
            local listFunc = LSM["List"]
            if type(listFunc) == "function" then
                smFonts = listFunc(LSM, fontKey)
            end
        end

        if smFonts then
            for _, fName in ipairs(smFonts) do
                if string.match(fName, "^W1LD") and not (WT.CustomMedia.Fonts and WT.CustomMedia.Fonts[fName]) then
                    table.insert(w1ldKeys, fName)
                end
            end
        end
        
        if #w1ldKeys > 0 then
            table.insert(options, { value = "WT_SEPARATOR", label = "--- W1LD Tools ---" })
            table.sort(w1ldKeys)
            for _, k in ipairs(w1ldKeys) do table.insert(options, { value = k, label = k }) end
        end
        
        if LSM then
            if smFonts and #smFonts > 0 then
                local addedSeparator = false
                for _, fName in ipairs(smFonts) do
                    if fName ~= "Friz Quadrata TT" and fName ~= "Arial Narrow" and fName ~= "Morpheus" and fName ~= "Skurri" and not (WT.CustomMedia.Fonts and WT.CustomMedia.Fonts[fName]) and not string.match(fName, "^W1LD") then
                        if not addedSeparator then
                            table.insert(options, { value = "WT_SEPARATOR", label = "--- SharedMedia ---" })
                            addedSeparator = true
                        end
                        table.insert(options, { value = fName, label = fName })
                    end
                end
            end
        end
    elseif mediaType == "statusbar" then
        table.insert(options, { value = "WT_SEPARATOR", label = "--- Standard ---" })
        table.insert(options, { value = "Blizzard", label = "Blizzard" })
        
        local w1ldKeys = {}
        for k in pairs(WT.CustomMedia.Statusbars or {}) do table.insert(w1ldKeys, k) end
        
        local LSM = GetLSM()
        local mt = type(LSM) == "table" and LSM["MediaType"] or nil
        local statusbarKey = (type(mt) == "table" and mt["STATUSBAR"]) or "statusbar"
        
        local smStatusbars = nil
        if type(LSM) == "table" then
            local listFunc = LSM["List"]
            if type(listFunc) == "function" then
                smStatusbars = listFunc(LSM, statusbarKey)
            end
        end

        if smStatusbars then
            for _, sbName in ipairs(smStatusbars) do
                if string.match(sbName, "^W1LD") and not (WT.CustomMedia.Statusbars and WT.CustomMedia.Statusbars[sbName]) then
                    table.insert(w1ldKeys, sbName)
                end
            end
        end
        
        if #w1ldKeys > 0 then
            table.insert(options, { value = "WT_SEPARATOR", label = "--- W1LD Tools ---" })
            table.sort(w1ldKeys)
            for _, k in ipairs(w1ldKeys) do table.insert(options, { value = k, label = k }) end
        end
        
        if LSM then
            if smStatusbars and #smStatusbars > 0 then
                local addedSeparator = false
                for _, sbName in ipairs(smStatusbars) do
                    if sbName ~= "Blizzard" and not (WT.CustomMedia.Statusbars and WT.CustomMedia.Statusbars[sbName]) and not string.match(sbName, "^W1LD") then
                        if not addedSeparator then
                            table.insert(options, { value = "WT_SEPARATOR", label = "--- SharedMedia ---" })
                            addedSeparator = true
                        end
                        table.insert(options, { value = sbName, label = sbName })
                    end
                end
            end
        end
    elseif mediaType == "background" or mediaType == "border" or mediaType == "highlight" then
        table.insert(options, { value = "WT_SEPARATOR", label = "--- Standard ---" })
        if mediaType == "background" then
            table.insert(options, { value = "Blizzard Tooltip", label = "Blizzard Tooltip" })
            table.insert(options, { value = "Blizzard Chat", label = "Blizzard Chat" })
        elseif mediaType == "highlight" then
            table.insert(options, { value = "Blizzard", label = "Blizzard" })
        else
            table.insert(options, { value = "Blizzard Tooltip", label = "Blizzard Tooltip" })
            table.insert(options, { value = "Blizzard Dialog", label = "Blizzard Dialog" })
        end
        
        local w1ldKeys = {}
        local customTable = mediaType == "background" and (WT.CustomMedia.Backgrounds or {}) or (mediaType == "highlight" and (WT.CustomMedia.Highlights or {}) or (WT.CustomMedia.Borders or {}))
        for k in pairs(customTable) do table.insert(w1ldKeys, k) end
        
        local LSM = GetLSM()
        local mt = type(LSM) == "table" and LSM["MediaType"] or nil
        local typeKey = (type(mt) == "table" and (mediaType == "background" and mt["BACKGROUND"] or (mediaType == "highlight" and mt["HIGHLIGHT"] or mt["BORDER"]))) or mediaType
        
        local smItems = nil
        if type(LSM) == "table" then
            local listFunc = LSM["List"]
            if type(listFunc) == "function" then
                smItems = listFunc(LSM, typeKey)
            end
        end

        if smItems then
            for _, itemName in ipairs(smItems) do
                if string.match(itemName, "^W1LD") and not customTable[itemName] then
                    table.insert(w1ldKeys, itemName)
                end
            end
        end
        
        if #w1ldKeys > 0 then
            table.insert(options, { value = "WT_SEPARATOR", label = "--- W1LD Tools ---" })
            table.sort(w1ldKeys)
            for _, k in ipairs(w1ldKeys) do table.insert(options, { value = k, label = k }) end
        end
        
        if LSM then
            if smItems and #smItems > 0 then
                local addedSeparator = false
                for _, itemName in ipairs(smItems) do
                    local isStandard = false
                    if mediaType == "background" then
                        if itemName == "Blizzard Tooltip" or itemName == "Blizzard Chat" then isStandard = true end
                    elseif mediaType == "highlight" then
                        if itemName == "Blizzard" then isStandard = true end
                    else
                        if itemName == "Blizzard Tooltip" or itemName == "Blizzard Dialog" then isStandard = true end
                    end
                    
                    if not isStandard and not customTable[itemName] and not string.match(itemName, "^W1LD") then
                        if not addedSeparator then
                            table.insert(options, { value = "WT_SEPARATOR", label = "--- SharedMedia ---" })
                            addedSeparator = true
                        end
                        table.insert(options, { value = itemName, label = itemName })
                    end
                end
            end
        end
    end
    
    optionsCache[mediaType] = options
    return options
end