local _, WT = ...
local Module = WT.Modules.Chat

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

local Ambiguate = Ambiguate or function(name, context) return name and ((context == "short" or context == "guild") and string.match(name, "^([^%-]+)") or name) or "" end
local GetNumGuildMembers = GetNumGuildMembers or (C_GuildInfo and C_GuildInfo.GetNumGuildMembers) or function() return 0 end
local GetGuildRosterInfo = GetGuildRosterInfo or (C_GuildInfo and C_GuildInfo.GetGuildRosterInfo) or function() return nil end

local Unsecret = WT.Utils.Safety.Unsecret

local function StripForMatch(text)
    if not text then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("%[", "")
    text = text:gsub("%]", "")
    return strtrim(text)
end

local function ExtractNameFromSystemMessage(msg)
    if not msg then return nil, nil end
    
    -- Fast-Path: Ignore 99% of system messages that don't contain login/logout keywords BEFORE doing expensive stripping
    local quickLower = string.lower(msg)
    if not string.find(quickLower, "offline", 1, true) and 
       not string.find(quickLower, "ausgeloggt", 1, true) and 
       not string.find(quickLower, "online", 1, true) and 
       not string.find(quickLower, "eingeloggt", 1, true) and 
       not string.find(quickLower, "joined the guild", 1, true) and 
       not string.find(quickLower, "der gilde beigetreten", 1, true) and 
       not string.find(quickLower, "left the guild", 1, true) and 
       not string.find(quickLower, "die gilde verlassen", 1, true) and 
       not string.find(quickLower, "kicked out of the guild", 1, true) and 
       not string.find(quickLower, "aus der gilde geworfen", 1, true) then
        return nil, nil
    end

    local cleanMsg = StripForMatch(msg)
    if string.find(cleanMsg, ":", 1, true) then return nil, nil end
    local tLower = string.lower(cleanMsg)
    
    local eventType = nil
    if string.find(tLower, " offline") or string.find(tLower, "ausgeloggt") then eventType = "OFFLINE"
    elseif string.find(tLower, " online") or string.find(tLower, "eingeloggt") then eventType = "ONLINE"
    elseif string.find(tLower, "joined the guild") or string.find(tLower, "der gilde beigetreten") then eventType = "JOIN"
    elseif string.find(tLower, "left the guild") or string.find(tLower, "die gilde verlassen") or string.find(tLower, "kicked out of the guild") or string.find(tLower, "aus der gilde geworfen") then eventType = "LEAVE" end
    
    if eventType ~= nil then
        local linkName = string.match(msg, "|[Hh]player:([^:|]+)")
        if linkName then return eventType, linkName end
        
        local bnetName = string.match(msg, "|[Hh][Bb][Nn]player:.-|h%[([^%]]+)%]|h")
        if bnetName then return eventType, bnetName end
        
        -- Fallback to first word (usually the player name without spaces)
        local name = string.match(cleanMsg, "^%[?(%S+)%]?")
        if name then return eventType, name end
    end
    
    return nil, nil
end

local function FormatLoginMessage(rawName, eventType, classFileName, sourceType)
    local displayName = rawName
    if sourceType == "GUILD" then
        displayName = Ambiguate(rawName, "guild")
    end
    
    local isPositive = (eventType == "ONLINE" or eventType == "JOIN")
    local color = isPositive and WT.Colors:GetHex(WT.DB.Chat.ColGuildLogin, 0, 1, 0) or WT.Colors:GetHex(WT.DB.Chat.ColGuildLogout, 0.5, 0.5, 0.5)
    
    local sign = isPositive and "+" or "-"
    local status = ""
    if eventType == "ONLINE" then status = WT.L.CHAT_ONLINE
    elseif eventType == "OFFLINE" then status = WT.L.CHAT_OFFLINE
    elseif eventType == "JOIN" then status = WT.L.CHAT_JOINED
    elseif eventType == "LEAVE" then status = WT.L.CHAT_LEFT
    end
    
    local classColor = "FFFFFFFF"
    if classFileName then
        local cColor = WT.DB.ClassColors and WT.DB.ClassColors[classFileName] or RAID_CLASS_COLORS[classFileName]
        if cColor then classColor = WT.Colors:GetHex(cColor) end
    end
    
    if sourceType == "BNET" and classColor == "FFFFFFFF" then
        classColor = "FF82C5FF"
    end
    
    local prefix = ""
    local prefixColor = "FF40FF40"
    
    if sourceType == "GUILD" then
        prefix = WT.DB.Chat.ShortChannelNames and "[G]" or "[" .. (GUILD or "Guild") .. "]"
    elseif sourceType == "FRIEND" then
        prefix = WT.DB.Chat.ShortChannelNames and "[F]" or "[" .. (FRIENDS or "Friends") .. "]"
    elseif sourceType == "BNET" then
        prefix = WT.DB.Chat.ShortChannelNames and "[B]" or "[BNet]"
        prefixColor = "FF00FFFF"
    end
    
    -- Append hidden tag so Chat_Filter grabs this line for history routing
    return string.format("||WT_GHIST|||c%s%s|r |c%s%s|r |c%s%s|r |c%s%s|r", prefixColor, prefix, color, sign, classColor, displayName, color, status)
end

local lastParsedMsg = nil
local lastParsedData = nil

local function ParseSmartLogin(msg)
    if msg == lastParsedMsg and lastParsedData then
        return (unpack or rawget(table, "unpack"))(lastParsedData)
    end

    local eventType, rawName = ExtractNameFromSystemMessage(msg)
    if not rawName then 
        lastParsedMsg = msg
        lastParsedData = { nil }
        return nil 
    end
    
    local sourceType = nil
    local classFileName = nil
    
    -- 1. Check if it is a BNet friend
    local bnetNameMatch = string.match(msg, "|[Hh][Bb][Nn]player:")
    if bnetNameMatch then
                sourceType = "BNET"
                local numBNet = (C_BattleNet and C_BattleNet.GetFriendCount and C_BattleNet.GetFriendCount()) or (BNGetNumFriends and BNGetNumFriends()) or 0
                for i = 1, numBNet do
            local accInfo = nil
            if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
                local ok, info = pcall(C_BattleNet.GetFriendAccountInfo, i)
                if ok then accInfo = info end
            end
                    if accInfo and (accInfo.accountName == rawName or accInfo.battleTag == rawName) then
                        if accInfo.gameAccountInfo and accInfo.gameAccountInfo.className then
                            classFileName = accInfo.gameAccountInfo.className
                        end
                        break
                    end
                end
            else
                -- 2. Check if it is actually a guild member
                local ambigName = Ambiguate(rawName, "guild")
                classFileName = Module.guildMemberCache[ambigName]
                if not classFileName then
                    local shortName = strsplit("-", rawName)
                    classFileName = Module.guildMemberCache[shortName]
                end
                
                if classFileName == -1 then 
                    classFileName = nil 
                else
                -- SECURITY FIX: Always search the live roster if the player is missing from the cache!
                if not classFileName and IsInGuild() then
                    for i = 1, GetNumGuildMembers() do
                        local name, _, _, _, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
                        local uName = nil
                        if type(name) == "string" then
                        local ok = pcall(string.match, name, "")
                        if ok then uName = name end
                        end
                        if uName and uName ~= "" then
                            local aName = Ambiguate(uName, "guild")
                            local okSplit, sName = pcall(strsplit, "-", uName)
                            sName = okSplit and sName or uName
                            if aName == ambigName or sName == ambigName or aName == rawName then
                            local uClass = nil
                            if type(class) == "string" then
                            local okC = pcall(string.match, class, "")
                            if okC then uClass = class end
                            end
                            classFileName = uClass or "UNKNOWN"
                                Module.guildMemberCache[aName] = classFileName
                                Module.guildMemberCache[sName] = classFileName
                                break
                            end
                        end
                    end
                end
                if not classFileName then Module.guildMemberCache[ambigName] = -1 end
                end
                
                if classFileName then
                    sourceType = "GUILD"
                else
                    -- 3. Check WoW Friends
                    local numFriends = C_FriendList.GetNumFriends()
                    if numFriends then
                        for i = 1, numFriends do
                            local friendInfo = C_FriendList.GetFriendInfoByIndex(i)
                            if friendInfo and friendInfo.name then
                                local fName = strsplit("-", friendInfo.name)
                                if friendInfo.name == rawName or fName == rawName then
                                    sourceType = "FRIEND"
                                    classFileName = friendInfo.className
                                    break
                                end
                            end
                        end
                    end
                    
                    -- 4. Check BNet Friends as fallback
                    if not sourceType then
                        local numBNet = (C_BattleNet and C_BattleNet.GetFriendCount and C_BattleNet.GetFriendCount()) or (BNGetNumFriends and BNGetNumFriends()) or 0
                        for i = 1, numBNet do
                    local accInfo = nil
                    if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
                        local ok, info = pcall(C_BattleNet.GetFriendAccountInfo, i)
                        if ok then accInfo = info end
                    end
                            if accInfo and (accInfo.accountName == rawName or accInfo.battleTag == rawName) then
                                sourceType = "BNET"
                                if accInfo.gameAccountInfo and accInfo.gameAccountInfo.className then
                                    classFileName = accInfo.gameAccountInfo.className
                                end
                                break
                            end
                        end
                    end
                end
            end
            
            if not sourceType then
                if eventType == "ONLINE" or eventType == "OFFLINE" then
                    lastParsedMsg = msg
                    lastParsedData = { nil }
                    return nil 
                else
                    classFileName = "UNKNOWN"
                    sourceType = "GUILD"
                end
            end
            
    lastParsedMsg = msg
    lastParsedData = { eventType, rawName, classFileName, sourceType }
    return eventType, rawName, classFileName, sourceType
end

function Module:ProcessSmartLogins(msg)
    if not WT.DB or not WT.DB.Modules.Chat or not WT.DB.Chat or not WT.DB.Chat.SmartGuildLogins then return true, msg end
    
    if type(msg) ~= "string" then return true, msg end
    local safeMsg = WT.Utils.Safety.Unsecret(msg)
    if not safeMsg or safeMsg == "" then return true, msg end
    
    local eventType, rawName, classFileName, sourceType = ParseSmartLogin(safeMsg)
    if not eventType then return true, msg end
    
    -- Guild members and WoW friends share Blizzard's login sound, so they are always handled together.
    if sourceType == "BNET" and not WT.DB.Chat.SmartLoginShowBNetFriends then return false, nil end
    if (eventType == "ONLINE" or eventType == "OFFLINE") and (GetTime() - (WT.Core.LoadTime or 0) < 5) then return false, nil end
    
    local newMsg = FormatLoginMessage(rawName, eventType, classFileName, sourceType)
    return true, newMsg
end

local smartLoginEventFrame = CreateFrame("Frame")
smartLoginEventFrame:SetScript("OnEvent", function(_, _, msg, ...)
    if not WT.DB or not WT.DB.Chat or not WT.DB.Chat.SmartGuildLogins then return end
    if type(msg) ~= "string" then return end
    local safeMsg = WT.Utils.Safety.Unsecret(msg)
    if not safeMsg or safeMsg == "" then return end
    
    local eventType, rawName, classFileName, sourceType = ParseSmartLogin(safeMsg)
    if not eventType then return end

    if sourceType == "BNET" and not WT.DB.Chat.SmartLoginShowBNetFriends then return end
    if (eventType == "ONLINE" or eventType == "OFFLINE") and (GetTime() - (WT.Core.LoadTime or 0) < 5) then return end
    
    if (eventType == "ONLINE" or eventType == "JOIN") then
        if WT.DB.Chat.SmartLoginSound and WT.DB.Chat.SmartLoginSound ~= "None" then
            if WT.Utils and WT.Utils.Audio then
                WT.Utils.Audio:Play(WT.DB.Chat.SmartLoginSound, "CHANNEL", WT.DB.Chat.SmartLoginSoundChannel)
            end
        end
    end
    
    if sourceType == "GUILD" then
        local newMsg = FormatLoginMessage(rawName, eventType, classFileName, sourceType)
        local info = ChatTypeInfo["SYSTEM"]
        
        for _, frameName in ipairs(CHAT_FRAMES) do
            local cf = _G[frameName]
            if cf then
                local hasGuild = false
                local hasSystem = false
                for _, group in ipairs(cf.messageTypeList or {}) do
                    if group == "GUILD" then hasGuild = true end
                    if group == "SYSTEM" then hasSystem = true end
                end
                if hasGuild and not hasSystem then
                    cf:AddMessage(newMsg, info.r, info.g, info.b, info.id)
                end
            end
        end
    end
end)

function Module:UpdateSmartLogins(enable)
    if enable then
        smartLoginEventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    else
        smartLoginEventFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
    end
end