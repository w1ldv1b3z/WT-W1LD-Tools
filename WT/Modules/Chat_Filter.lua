local _, WT = ...
local Module = WT.Modules.Chat

local cachedHighlights = {}
local cachedBlacklist = {}
local cachedWhitelist = {}
local chanSearchCache = {}
local chanHexCache = {}

local guidTracker = CreateFrame("Frame")
local chatEvents = {
    "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_SAY", "CHAT_MSG_YELL",
    "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER_INFORM"
}

local strtrim = strtrim or string.trim or function(s) return s and string.match(s, "^%s*(.-)%s*$") or "" end
local strsplit = strsplit or string.split or function(d, s)
    if not s then return nil end
    local t, i = {}, 1
    while true do
        local j = string.find(s, d, i, true)
        if not j then
            table.insert(t, string.sub(s, i))
            break
        end
        table.insert(t, string.sub(s, i, j - 1))
        i = j + #d
    end
    return (unpack or rawget(table, "unpack"))(t)
end

local wipe = table.wipe or wipe or function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

Module.LastSentMessages = {}

local function CleanString(text)
    if not text or type(text) ~= "string" then return text or "" end
    if not string.find(text, "|", 1, true) then return text end
    local str = string.gsub(text, "|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
    str = string.gsub(str, "|[Hh].-|[hH](.-)|[hH]", "%1")
    str = string.gsub(str, "|[Tt].-|[tT]", "")
    str = string.gsub(str, "|[Aa].-|[aA]", "")
    str = string.gsub(str, "|[Kk].-|[kK]", "")
    return str
end

local function TrackOutgoingMessage(msg)
    if not WT.DB or not WT.DB.Modules.Chat then return end
    Module.LastSendTime = GetTime()

    -- BATTLE-SAFE: Prevent secret strings from crashing string operations
    if type(msg) ~= "string" then return end
    local safeMsg = WT.Utils.Safety.Unsecret(msg)
    if not safeMsg or safeMsg == "" then return end

    local textToCache = strtrim(safeMsg)
    if string.sub(textToCache, 1, 1) == "/" then
        local numRest = string.match(textToCache, "^/%d+%s+(.*)")
        if numRest then
            textToCache = numRest
        else
            local cmd, rest = string.match(textToCache, "^/([^%s]+)%s+(.*)")
            if cmd then
                cmd = string.lower(cmd)
                if cmd == "w" or cmd == "whisper" or cmd == "t" or cmd == "tell" then
                    local _, wMsg = string.match(rest, "^([^%s]+)%s+(.*)")
                    if wMsg then textToCache = wMsg else textToCache = rest end
                else
                    textToCache = rest
                end
            end
        end
    end

    local cleanMsg = strtrim(CleanString(textToCache))
    if cleanMsg ~= "" then
        local lastEntry = Module.LastSentMessages[#Module.LastSentMessages]
        if lastEntry and lastEntry.text == cleanMsg and (GetTime() - lastEntry.time < 0.5) then return end
        table.insert(Module.LastSentMessages, { text = cleanMsg, time = GetTime() })
        local over = #Module.LastSentMessages - 20
        if over > 0 then
            for i = 1, 20 do Module.LastSentMessages[i] = Module.LastSentMessages[i + over] end
            for i = 21, #Module.LastSentMessages do Module.LastSentMessages[i] = nil end
        end
    end
end
Module.TrackOutgoingMessage = TrackOutgoingMessage

local filterState = setmetatable({}, { __mode = "k" })

if not Module.outgoingTrackerHooked then
    Module.outgoingTrackerHooked = true

    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", function(_, editBox)
            local txt = editBox and editBox:GetText()
            if txt and txt ~= "" then
                TrackOutgoingMessage(txt)
            end
        end)
    end

    hooksecurefunc("SendChatMessage", function(msg) TrackOutgoingMessage(msg) end)
    hooksecurefunc("BNSendWhisper", function(id, msg) TrackOutgoingMessage(msg) end)
    -- DO NOT hook C_Club.SendMessage! Hooking C_* namespace tables taints them
    -- and causes ADDON_ACTION_BLOCKED errors in the Communities UI (e.g. SetAvatarTexture).
    if _G["BNSendConversationMessage"] then
        hooksecurefunc("BNSendConversationMessage", function(target, msg)
            Module.LastCommunitySendTime = GetTime()
            TrackOutgoingMessage(msg)
        end)
    end
end


local SafeNum = WT.Utils.Safety.SafeNum
local Unsecret = WT.Utils.Safety.Unsecret

local Ambiguate = Ambiguate or
function(name, context) return name and
    ((context == "short" or context == "guild") and string.match(name, "^([^%-]+)") or name) or "" end
local GetNumGuildMembers = GetNumGuildMembers or (C_GuildInfo and C_GuildInfo.GetNumGuildMembers) or
function() return 0 end
local GetGuildRosterInfo = GetGuildRosterInfo or (C_GuildInfo and C_GuildInfo.GetGuildRosterInfo) or
function() return nil end

for _, ev in ipairs(chatEvents) do guidTracker:RegisterEvent(ev) end
guidTracker:SetScript("OnEvent", function(_, event, ...)
    if not WT.DB or not WT.DB.Modules.Chat then return end
    local msg = select(1, ...)
    local sender = select(2, ...)
    local guid = select(12, ...)
    local bnSenderID = select(13, ...)

    local isSelf = WT.Modules.Chat:IsSelfMessage(event, guid, bnSenderID, sender, msg)

    if isSelf then
        if type(msg) == "string" and msg ~= "" then
            Module.wtLastServerSelfTime = GetTime()
            Module.wtLastServerSelfMsg = msg
        end
    end
end)



local pNameRetryCount = 0

function Module:UpdateChatFilters()
    wipe(cachedHighlights)
    if WT.DB.Chat.EnableHighlights and WT.DB.Chat.HighlightWords and WT.DB.Chat.HighlightWords ~= "" then
        local ok, nameRes = pcall(UnitName, "player")
        local pName = ok and Unsecret(nameRes) or "Unknown"
        if not pName or pName == "Unknown" then
            pName = ""
            -- Retry building the cache once the player name is fully loaded by the server
            if pNameRetryCount < 10 then
                pNameRetryCount = pNameRetryCount + 1
                C_Timer.After(2, function() Module:UpdateChatFilters() end)
            end
        end

        for word in string.gmatch(WT.DB.Chat.HighlightWords, "([^,;]+)") do
            local parsedWord = strtrim(word)
            if parsedWord:upper() == "%ME%" and pName ~= "" then parsedWord = pName end

            if parsedWord ~= "" and parsedWord:upper() ~= "%ME%" then
                local safeWord = WT.Utils.Strings:EscapeRegex(parsedWord)
                -- Convert wildcard * to .*
                local hasWildcard = string.find(safeWord, "%%%*")
                safeWord = safeWord:gsub("%%%*", ".*")

                local pattern = safeWord:gsub("%a",
                    function(c) return string.format("[%s%s]", string.lower(c), string.upper(c)) end)
                if not hasWildcard then
                    local prefix = string.match(parsedWord, "^[%w_\128-\255]") and "%f[%w_\128-\255]" or ""
                    local suffix = string.match(parsedWord, "[%w_\128-\255]$") and "%f[^%w_\128-\255]" or ""
                    pattern = prefix .. pattern .. suffix
                end
                table.insert(cachedHighlights, pattern)
            end
        end
    end

    wipe(cachedBlacklist)
    if WT.DB.Chat.EnableBlacklist and WT.DB.Chat.BlacklistWords and WT.DB.Chat.BlacklistWords ~= "" then
        for word in string.gmatch(WT.DB.Chat.BlacklistWords, "([^,;]+)") do
            local origWord = strtrim(word)
            local lowerWord = string.lower(origWord)
            if lowerWord ~= "" then
                local safeWord = WT.Utils.Strings:EscapeRegex(lowerWord)
                local hasWildcard = string.find(safeWord, "%%%*")
                safeWord = safeWord:gsub("%%%*", ".*")

                local ciPattern = WT.Utils.Strings:EscapeRegex(origWord)
                ciPattern = ciPattern:gsub("%a",
                    function(c) return string.format("[%s%s]", string.lower(c), string.upper(c)) end)
                ciPattern = ciPattern:gsub("%%%*", ".*")

                if not hasWildcard then
                    local prefix = string.match(lowerWord, "^[%w_\128-\255]") and "%f[%w_\128-\255]" or ""
                    local suffix = string.match(lowerWord, "[%w_\128-\255]$") and "%f[^%w_\128-\255]" or ""
                    safeWord = prefix .. safeWord .. suffix
                    ciPattern = prefix .. ciPattern .. suffix
                end

                table.insert(cachedBlacklist, { normal = safeWord, ciPattern = ciPattern, original = origWord })
            end
        end
    end

    wipe(cachedWhitelist)
    if WT.DB.Chat.WhitelistPlayers and WT.DB.Chat.WhitelistPlayers ~= "" then
        for name in string.gmatch(WT.DB.Chat.WhitelistPlayers, "([^,;]+)") do
            local cleanName = string.lower(strtrim(name))
            if cleanName ~= "" then
                cachedWhitelist[cleanName] = true
            end
        end
    end

    wipe(chanSearchCache)
    wipe(chanHexCache)
end

-- ============================================================================
-- PIPELINE HELPER FUNCTIONS
-- ============================================================================

local cachedPlayerName = nil
local cachedSafePlayerName = nil
local cachedBNetName = nil
local cachedSafeBNetName = nil

local function CleanEmojis(text)
    text = string.gsub(text, "[\240-\244][\128-\191][\128-\191][\128-\191]", "")
    text = string.gsub(text, "\226[\154-\157][\128-\191]", "")
    text = string.gsub(text, "\226[\172-\173][\128-\191]", "")
    return text
end

local function DetectSelfMessage(selfOrText, maybeSender)
    local text = selfOrText
    local senderParam = nil
    if type(text) == "table" and (type(maybeSender) == "string" or maybeSender ~= nil) then
        text = maybeSender
    elseif type(maybeSender) == "string" then
        senderParam = maybeSender
    end
    text = Unsecret(text)
    if type(text) ~= "string" or text == "" then return false end

    local pName = cachedPlayerName or (UnitName and UnitName("player"))
    if senderParam and pName and pName ~= "" then
        local sClean = tostring(senderParam):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        sClean = sClean:gsub("|[Hh].-|[hH](.-)|[hH]", "%1"):gsub("|[Hh].-|[hH]", ""):gsub("|h", "")
        sClean = sClean:gsub("%s*%(%*%)", ""):gsub("[%[%]]", "")
        sClean = strtrim(sClean)
        local sBase = string.match(sClean, "^([^%-]+)") or sClean
        sBase = strtrim(sBase)
        local sBaseLower = (strlower and strlower(sBase)) or (_G["mbstrlower"] and _G["mbstrlower"](sBase)) or
        string.lower(sBase)
        local pLower = (strlower and strlower(pName)) or (_G["mbstrlower"] and _G["mbstrlower"](pName)) or
        string.lower(pName)
        if sBase == pName or (sBaseLower ~= "" and sBaseLower == pLower) or sClean == pName then
            return true
        end
    end

    local timeNow = GetTime()
    local serverText = Module.wtLastServerSelfMsg or ""

    local hasServerText = (Module.wtLastServerSelfTime and (timeNow - Module.wtLastServerSelfTime < 1.5) and serverText ~= "")

    local recentSent = false
    if Module.LastSentMessages then
        for i = #Module.LastSentMessages, 1, -1 do
            if timeNow - Module.LastSentMessages[i].time < 15.0 then
                recentSent = true; break
            end
        end
    end

    local tNoColor, tPure
    if hasServerText or recentSent then
        tNoColor = text
        if string.find(tNoColor, "|", 1, true) then
            tNoColor = string.gsub(tNoColor, "|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            tPure = string.gsub(tNoColor, "|[Hh].-|[hH](.-)|[hH]", "%1")
            tPure = string.gsub(tPure, "|[aA].-|[aA]", ""):gsub("|[Tt].-|[Tt]", "")
            tPure = string.gsub(tPure, "|[Kk].-|[kK]", "")
        else
            tPure = tNoColor
        end
        tPure = strtrim(tPure)

        local tPureLower = nil

        if hasServerText then
            local serverTextNoColor = serverText
            if string.find(serverTextNoColor, "|", 1, true) then
                serverTextNoColor = string.gsub(serverTextNoColor, "|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                serverTextNoColor = string.gsub(serverTextNoColor, "|[Hh].-|[hH](.-)|[hH]", "%1")
                serverTextNoColor = string.gsub(serverTextNoColor, "|[aA].-|[aA]", ""):gsub("|[Tt].-|[Tt]", "")
                serverTextNoColor = string.gsub(serverTextNoColor, "|[Kk].-|[kK]", "")
            end
            serverTextNoColor = strtrim(serverTextNoColor)

            if serverTextNoColor ~= "" then
                if string.find(tPure, serverTextNoColor, 1, true) then return true end
                tPureLower = (strlower and strlower(tPure)) or (_G["mbstrlower"] and _G["mbstrlower"](tPure)) or
                string.lower(tPure)
                local sTextLower = (strlower and strlower(serverTextNoColor)) or
                (_G["mbstrlower"] and _G["mbstrlower"](serverTextNoColor)) or string.lower(serverTextNoColor)
                if string.find(tPureLower, sTextLower, 1, true) then return true end
            end
        end

        if recentSent then
            tPureLower = tPureLower or (strlower and strlower(tPure)) or (_G["mbstrlower"] and _G["mbstrlower"](tPure)) or
            string.lower(tPure)
            for i = #Module.LastSentMessages, 1, -1 do
                local sent = Module.LastSentMessages[i]
                if sent then
                    local sText = type(sent) == "table" and sent.text or (type(sent) == "string" and sent)
                    local sTime = type(sent) == "table" and (sent.time or 0) or timeNow
                    if sText and sText ~= "" and (timeNow - sTime < 15.0) then
                        if string.find(tPure, sText, 1, true) then return true end
                        local sentLower = (strlower and strlower(sText)) or
                        (_G["mbstrlower"] and _G["mbstrlower"](sText)) or string.lower(sText)
                        if string.find(tPureLower, sentLower, 1, true) then return true end
                    end
                end
            end
        end
    end

    if not cachedPlayerName then
        local ok, pName = pcall(UnitName, "player")
        cachedPlayerName = ok and Unsecret(pName) or nil
        if cachedPlayerName then
            cachedSafePlayerName = WT.Utils.Strings:EscapeRegex(cachedPlayerName)
        end
    end

    if not cachedBNetName then
        local okBN, myInfo = false, nil
        if C_BattleNet and C_BattleNet.GetMyAccountInfo then okBN, myInfo = pcall(C_BattleNet.GetMyAccountInfo) end
        if okBN and myInfo and myInfo.battleTag then
            local bName = strsplit("#", myInfo.battleTag)
            if bName then
                cachedBNetName = bName
                cachedSafeBNetName = WT.Utils.Strings:EscapeRegex(bName)
            end
        else
            if BNGetInfo then
                local ok, _, _, myBattleTag = pcall(BNGetInfo)
                if ok and type(myBattleTag) == "string" then
                    local bName = strsplit("#", myBattleTag)
                    if bName then
                        cachedBNetName = bName
                        cachedSafeBNetName = WT.Utils.Strings:EscapeRegex(bName)
                    end
                end
            end
        end
    end

    local function CheckName(safeName, rawName)
        if not safeName or safeName == "" then return false end
        local rName = rawName or safeName
        local sLower = (strlower and strlower(rName)) or (_G["mbstrlower"] and _G["mbstrlower"](rName)) or
        string.lower(rName)
        local tLower = (strlower and strlower(text)) or (_G["mbstrlower"] and _G["mbstrlower"](text)) or
        string.lower(text)

        -- 1. Plain text checks on hyperlink target (immune to regex pattern errors and UTF-8 casing)
        if string.find(text, "|hplayer:" .. rName .. ":", 1, true) or
            string.find(text, "|hplayer:" .. rName .. "-", 1, true) or
            string.find(text, "|hbnplayer:" .. rName .. ":", 1, true) or
            string.find(text, "|hbnplayer:" .. rName .. "-", 1, true) or
            string.find(text, "|hplayer:" .. rName .. "|", 1, true) or
            string.find(tLower, "|hplayer:" .. sLower .. ":", 1, true) or
            string.find(tLower, "|hplayer:" .. sLower .. "-", 1, true) or
            string.find(tLower, "|hbnplayer:" .. sLower .. ":", 1, true) or
            string.find(tLower, "|hbnplayer:" .. sLower .. "-", 1, true) or
            string.find(tLower, "|hplayer:" .. sLower .. "|", 1, true) then
            return true
        end

        if not tNoColor then tNoColor = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
        pcall(function()
            if string.match(tNoColor, "|[Hh]%a*player:.-|[hH]%[?.-" .. safeName .. "[^%]]*%]?|[hH]") then return true end
            if string.match(tNoColor, "|[Hh]club[Mm]ember:.-|[hH]%[?.-" .. safeName .. "[^%]]*%]?|[hH]") then return true end
        end)

        if not tPure then
            tPure = tNoColor:gsub("|[Hh].-|[hH](.-)|[hH]", "%1")
            tPure = tPure:gsub("|[aA].-|[aA]", "")
            tPure = tPure:gsub("|[Tt].-|[Tt]", "")
            tPure = tPure:gsub("|[Kk].-|[kK]", "")
            tPure = strtrim(tPure)
        end
        local okP, matchP = pcall(string.match, tPure, "%]%s*%[?.-" .. safeName .. "[^%]:]*%]?%s*:")
        if okP and matchP then return true end
        local okP2, matchP2 = pcall(string.match, tPure, "^%s*%[?.-" .. safeName .. "[^%]:]*%]?%s*:")
        if okP2 and matchP2 then return true end
        return false
    end

    if cachedSafePlayerName and CheckName(cachedSafePlayerName, cachedPlayerName) then return true end
    if cachedSafeBNetName and CheckName(cachedSafeBNetName, cachedBNetName) then return true end

    return false
end
Module.DetectSelfMessage = DetectSelfMessage

local function ProcessBlacklist(text, isSelfMsg, currentSender, ...)
    if not WT.DB.Chat.EnableBlacklist or #cachedBlacklist == 0 then return true, text end

    -- EARLY EXIT OPTIMIZATIONS: Skip blacklist processing entirely for excluded sources
    if WT.DB.Chat.FilterOwnMessages and isSelfMsg then return true, text end
    if string.find(text, "channel:", 1, true) then
        if WT.DB.Chat.FilterGuild and string.match(text, "|[Hh]channel:[Gg][Uu][Ii][Ll][Dd]|[hH]") then return true, text end
        if WT.DB.Chat.FilterGroup and (string.match(text, "|[Hh]channel:[Pp][Aa][Rr][Tt][Yy]|[hH]") or string.match(text, "|[Hh]channel:[Rr][Aa][Ii][Dd]|[hH]") or string.match(text, "|[Hh]channel:[Ii][Nn][Ss][Tt][Aa][Nn][Cc][Ee]_[Cc][Hh][Aa][Tt]|[hH]")) then return
            true, text end
    end

    -- Bypass filtering for System, Boss, NPC and Monster messages (they lack player/bnet links)
    if not currentSender and not isSelfMsg then
        return true, text
    end

    if currentSender then
        local cleanSender = strsplit("-", currentSender)
        local fullSender = string.lower(currentSender)
        if cachedWhitelist[string.lower(cleanSender)] or cachedWhitelist[fullSender] then
            return true, text
        end

        if WT.DB.Chat.FilterFriends then
            local isFriend = Module.friendCache and Module.friendCache[currentSender]
            if isFriend == nil then
                isFriend = C_FriendList.GetFriendInfo(currentSender) ~= nil
                if not isFriend then
                    local numBNet = SafeNum((C_BattleNet and C_BattleNet.GetFriendCount and C_BattleNet.GetFriendCount()) or
                    (BNGetNumFriends and BNGetNumFriends()) or 0)
                    if numBNet > 0 then
                        for bIdx = 1, numBNet do
                            local accountInfo = C_BattleNet.GetFriendAccountInfo(bIdx)
                            if accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.characterName then
                                local charName = accountInfo.gameAccountInfo.characterName
                                if charName == currentSender or string.match(currentSender, "^" .. charName .. "-") then
                                    isFriend = true; break
                                end
                            end
                        end
                    end
                end
                if Module.friendCache then Module.friendCache[currentSender] = isFriend end
            end
            if isFriend then return true, text end
        end
    end

    local isBlocked = false
    local matchedData = nil

    -- OPTIMIZATION: Avoid string.lower() allocations by using the pre-compiled ciPattern regex
    for _, data in ipairs(cachedBlacklist) do
        if string.find(text, data.ciPattern) then
            isBlocked = true; matchedData = data; break
        end
    end

    if isBlocked and matchedData then
        Module.SessionBlockedCount = (Module.SessionBlockedCount or 0) + 1
        if not WT.DB.Internal then WT.DB.Internal = {} end
        WT.DB.Internal.TotalBlocked = (WT.DB.Internal.TotalBlocked or 0) + 1

        if WT.DB.Chat.BlacklistNotify then
            local bCol = WT.Colors:GetHex(WT.DB.Chat.BlacklistNotifyColor, 1, 0, 0)

            local chanDisplay = string.match(text, "(|Hchannel:[^|]+|h%[.-%]|h)") or
            string.match(text, "(|HclubStream:[^|]+|h%[.-%]|h)") or ""

            if not Module.blockedMessages then
                Module.blockedMessages = {}
                Module.blockedMessageIndex = 1
            end

            local bId = tostring(Module.blockedMessageIndex)
            Module.blockedMessageIndex = Module.blockedMessageIndex >= 50 and 1 or (Module.blockedMessageIndex + 1)
            local cleanTT = string.gsub(text, "|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")

            local tokens = {}
            local tempTT = string.gsub(cleanTT, "(|c%x%x%x%x%x%x%x%x)",
                function(m)
                    table.insert(tokens, m); return "\001" .. #tokens .. "\002"
                end)
            tempTT = string.gsub(tempTT, "(|r)",
                function(m)
                    table.insert(tokens, m); return "\003" .. #tokens .. "\004"
                end)

            tempTT = string.gsub(tempTT, "(" .. matchedData["ciPattern"] .. ")", "|cFFFF0000%1|r")

            cleanTT = string.gsub(tempTT, "\001(%d+)\002", function(id) return tokens[tonumber(id)] end)
            cleanTT = string.gsub(cleanTT, "\003(%d+)\004", function(id) return tokens[tonumber(id)] end)

            local tsString = ""
            if not Module.isRestoringHistory and WT.DB.Chat.Timestamps and WT.Modules.ChatUI and WT.Modules.ChatUI.GetTimestampString then
                tsString = WT.Modules.ChatUI:GetTimestampString()
            end

            local r, g, b = select(1, ...)
            local textToSave = text
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                local clampR = math.max(0, math.min(1, r))
                local clampG = math.max(0, math.min(1, g))
                local clampB = math.max(0, math.min(1, b))
                local hexColor = string.format("FF%02x%02x%02x", math.floor(clampR * 255 + 0.5),
                    math.floor(clampG * 255 + 0.5), math.floor(clampB * 255 + 0.5))
                textToSave = "|c" .. hexColor .. string.gsub(textToSave, "|[rR]", "|r|c" .. hexColor) .. "|r"
            end

            Module.blockedMessages[bId] = { tooltipText = strtrim(cleanTT), originalText = textToSave, timestamp =
            tsString, sender = currentSender }

            local msg = "|Hwtblock:" ..
            bId .. "|h" .. string.format(WT.L.MSG_FILTERED, matchedData["original"]) .. "|h"

            return false, tsString .. "|c" .. bCol .. msg .. "|r " .. chanDisplay
        end
        return false, nil
    end
    return true, text
end


local sharedTokens = {}
local function SharedTokenize(m)
    table.insert(sharedTokens, m)
    return "\001" .. #sharedTokens .. "\002"
end
local function SharedDetokenize(id)
    return sharedTokens[tonumber(id)] or ""
end

local function ProcessHighlightsAndURLs(text, isSelfMsg)
    local hasHighlights = WT.DB.Chat.EnableHighlights and #cachedHighlights > 0
    if not (hasHighlights or WT.DB.Chat.ClickableLinks) then return text end

    local isPlayerMsg = string.match(text, "|[Hh]player:") or string.match(text, "|[Hh][Bb][Nn]player:") or
    string.match(text, "|[Hh]club[Mm]ember:")
    local doHighlight = hasHighlights and not isSelfMsg and (not WT.DB.Chat.HighlightOnlyPlayers or isPlayerMsg)

    -- PERFORMANCE: Fast check to skip heavy tokenization if there's definitely no URL
    local hasURL = WT.DB.Chat.ClickableLinks and
    (string.find(text, "://", 1, true) or string.find(text, "www%.", 1, true))
    local hasWowhead = WT.DB.Chat.ClickableLinks and
    (string.find(text, "npc:%d+") or string.find(text, "spell:%d+") or string.find(text, "item:%d+") or string.find(text, "quest:%d+") or string.find(text, "achievement:%d+") or string.find(text, "currency:%d+") or string.find(text, "mount:%d+") or string.find(text, "player:[%w\128-\255%-]+"))

    if doHighlight or hasURL or hasWowhead then
        wipe(sharedTokens)

        local temp = string.gsub(text, "(|H.-|h)", SharedTokenize)
        temp = string.gsub(temp, "(|h)", SharedTokenize)
        temp = string.gsub(temp, "(|c%x%x%x%x%x%x%x%x)", SharedTokenize)
        temp = string.gsub(temp, "(|cn.-:)", SharedTokenize)
        temp = string.gsub(temp, "(|r)", SharedTokenize)
        temp = string.gsub(temp, "(|T.-|[tT])", SharedTokenize)
        temp = string.gsub(temp, "(|A.-|[aA])", SharedTokenize)
        temp = string.gsub(temp, "(|K.-|[kK])", SharedTokenize)

        if hasURL then
            temp = string.gsub(temp, "(%a+://[%w_/%.%?%%=~&%-]+)", "|Hwturl:%1|h|cFF00FFFF[%1]|r|h")
            temp = string.gsub(temp, "([^%a/])(www%.[%w_/%.%?%%=~&%-]+)", "%1|Hwturl:%2|h|cFF00FFFF[%2]|r|h")
            temp = string.gsub(temp, "^(www%.[%w_/%.%?%%=~&%-]+)", "|Hwturl:%1|h|cFF00FFFF[%1]|r|h")

            -- Wowhead specific routing for direct DB links
            temp = string.gsub(temp, "|Hwturl:https?://[%w%.]*wowhead%.com.-/([^=/%s]+)=(%d+)[^|]*|h|cFF00FFFF%[.-%]|r|h",
                "|Hwtwowhead:%1:%2|h|cFF00FFFF[%1:%2]|r|h")
            temp = string.gsub(temp, "|Hwturl:[%w%.]*wowhead%.com.-/([^=/%s]+)=(%d+)[^|]*|h|cFF00FFFF%[.-%]|r|h",
                "|Hwtwowhead:%1:%2|h|cFF00FFFF[%1:%2]|r|h")

            -- Raider.io specific routing for direct characters
            temp = string.gsub(temp,
                "|Hwturl:https?://[%w%.]*raider%.io/characters/([^/]+)/([^/]+)/([^/|%?%s]+)[^|]*|h|cFF00FFFF%[.-%]|r|h",
                "|Hwtwowhead:player:%3-%2:%1|h|cFF00FFFF[%3-%2]|r|h")
            temp = string.gsub(temp,
                "|Hwturl:[%w%.]*raider%.io/characters/([^/]+)/([^/]+)/([^/|%?%s]+)[^|]*|h|cFF00FFFF%[.-%]|r|h",
                "|Hwtwowhead:player:%3-%2:%1|h|cFF00FFFF[%3-%2]|r|h")
        end

        if hasWowhead then
            temp = string.gsub(temp, "([^%a/])(npc:%d+)", "%1|Hwtwowhead:%2|h|cFF00FFFF[%2]|r|h")
            temp = string.gsub(temp, "^(npc:%d+)", "|Hwtwowhead:%1|h|cFF00FFFF[%1]|r|h")
            temp = string.gsub(temp, "([^%a/])(spell:%d+)", "%1|Hwtwowhead:%2|h|cFF00FFFF[%2]|r|h")
            temp = string.gsub(temp, "^(spell:%d+)", "|Hwtwowhead:%1|h|cFF00FFFF[%1]|r|h")
            temp = string.gsub(temp, "([^%a/])(item:%d+)", "%1|Hwtwowhead:%2|h|cFF00FFFF[%2]|r|h")
            temp = string.gsub(temp, "^(item:%d+)", "|Hwtwowhead:%1|h|cFF00FFFF[%1]|r|h")
            temp = string.gsub(temp, "([^%a/])(quest:%d+)", "%1|Hwtwowhead:%2|h|cFF00FFFF[%2]|r|h")
            temp = string.gsub(temp, "^(quest:%d+)", "|Hwtwowhead:%1|h|cFF00FFFF[%1]|r|h")
            temp = string.gsub(temp, "([^%a/])(player:[%w\128-\255%-]+)", "%1|Hwtwowhead:%2|h|cFF00FFFF[%2]|r|h")
            temp = string.gsub(temp, "^(player:[%w\128-\255%-]+)", "|Hwtwowhead:%1|h|cFF00FFFF[%1]|r|h")
            temp = string.gsub(temp, "([^%a/])(achievement:%d+)", "%1|Hwtwowhead:%2|h|cFF00FFFF[%2]|r|h")
            temp = string.gsub(temp, "^(achievement:%d+)", "|Hwtwowhead:%1|h|cFF00FFFF[%1]|r|h")
            temp = string.gsub(temp, "([^%a/])(currency:%d+)", "%1|Hwtwowhead:%2|h|cFF00FFFF[%2]|r|h")
            temp = string.gsub(temp, "^(currency:%d+)", "|Hwtwowhead:%1|h|cFF00FFFF[%1]|r|h")
            temp = string.gsub(temp, "([^%a/])(mount:%d+)", "%1|Hwtwowhead:%2|h|cFF00FFFF[%2]|r|h")
            temp = string.gsub(temp, "^(mount:%d+)", "|Hwtwowhead:%1|h|cFF00FFFF[%1]|r|h")
        end

        if hasURL or hasWowhead then
            temp = string.gsub(temp, "(|H.-|h)", SharedTokenize)
            temp = string.gsub(temp, "(|h)", SharedTokenize)
            temp = string.gsub(temp, "(|c%x%x%x%x%x%x%x%x)", SharedTokenize)
            temp = string.gsub(temp, "(|cn.-:)", SharedTokenize)
            temp = string.gsub(temp, "(|r)", SharedTokenize)
        end

        local wasHighlighted = false
        if doHighlight then
            local hCol = WT.Colors:GetHex(WT.DB.Chat.HighlightColor, 0, 1, 0)
            if #hCol < 8 then hCol = "FF" .. hCol end

            for _, pattern in ipairs(cachedHighlights) do
                local newTemp, count = string.gsub(temp, "(" .. pattern .. ")", "|c" .. hCol .. "%1|r")
                if count > 0 then
                    temp = newTemp
                    wasHighlighted = true
                end
            end
        end

        if wasHighlighted or WT.DB.Chat.ClickableLinks then
            local s_tok, res_tok = pcall(string.gsub, temp, "\001(%d+)\002", SharedDetokenize)
            if s_tok then text = res_tok end
            if wasHighlighted and WT.DB.Chat.HighlightSound and WT.DB.Chat.HighlightSound ~= "None" then WT.Utils.Audio
                    :Play(WT.DB.Chat.HighlightSound, "HIGHLIGHT", WT.DB.Chat.HighlightSoundChannel) end
        end
    end
    return text
end

local function ProcessChannelModifications(text, isSelfMsg)
    if not WT.DB.Modules.Chat then return text end

    -- Performance check: Early exit if no channel modifications are enabled
    local hasShortChannels = WT.DB.Chat.ShortChannelNames
    local db = WT.DB.ChatChannels
    if not hasShortChannels and (not db or not (db.CustomChan1Enabled or db.CustomChan2Enabled or db.CustomChan3Enabled or
            db.ChanGuildAliasEnabled or db.ChanGuildColorEnabled or
            db.ChanOfficerAliasEnabled or db.ChanOfficerColorEnabled or
            db.ChanPartyAliasEnabled or db.ChanPartyColorEnabled or
            db.ChanRaidAliasEnabled or db.ChanRaidColorEnabled or
            db.ChanInstanceAliasEnabled or db.ChanInstanceColorEnabled)) then
        return text
    end

    if not (string.find(text, "|Hchannel:", 1, true) or string.find(text, "|HclubStream:", 1, true)) then return text end

    local chanStart, _, fullLink, _, innerName
    if string.find(text, "|Hchannel:", 1, true) then
        chanStart, _, fullLink, _, innerName = string.find(text, "((|Hchannel:.-|h)%[(.-)%](|h))")
    elseif string.find(text, "|HclubStream:", 1, true) then
        chanStart, _, fullLink, _, innerName = string.find(text, "((|HclubStream:.-|h)%[(.-)%](|h))")
    end

    if chanStart then
        local matchedChannel = false
        local cNumMatch = string.match(innerName, "^(%d+)%.")
        local cNum = cNumMatch and tonumber(cNumMatch) or nil
        local justName = string.match(innerName, "^%d+%.%s*(.+)") or innerName
        local justNameLower = string.lower(justName) -- One-time string operation

        for idx = 1, 3 do
            local cEnabled = WT.DB.ChatChannels["CustomChan" .. idx .. "Enabled"]
            local cName = WT.DB.ChatChannels["CustomChan" .. idx .. "Name"]
            local cSound = WT.DB.ChatChannels["CustomChan" .. idx .. "Sound"]

            if cEnabled and cName and cName ~= "" then
                local searchNameLower = string.lower(strtrim(cName))
                if searchNameLower ~= "" then
                    local searchData = chanSearchCache[cName]
                    if not searchData then
                        searchData = { lower = searchNameLower, num = tonumber(searchNameLower) }
                        chanSearchCache[cName] = searchData
                    end

                    local isMatch = false

                    if searchData.num and cNum and searchData.num == cNum then
                        isMatch = true
                    elseif not searchData.num then
                        local safeSearch = WT.Utils.Strings:EscapeRegex(searchData.lower)
                        if justNameLower == searchData.lower then
                            isMatch = true
                        elseif string.find(justNameLower, "%f[%w_\128-\255]" .. safeSearch .. "%f[^%w_\128-\255]") then
                            isMatch = true
                        end
                    end

                    if isMatch then
                        matchedChannel = true
                        local displayTag = innerName
                        if db and db["CustomChan" .. idx .. "AliasEnabled"] and db["CustomChan" .. idx .. "Alias"] ~= "" then
                            displayTag = db["CustomChan" .. idx .. "Alias"]
                        elseif hasShortChannels and cNum then
                            displayTag = tostring(cNum)
                        end

                        local restOfMessage = string.sub(text, chanStart + string.len(fullLink))
                        if db and db["CustomChan" .. idx .. "ColorEnabled"] then
                            local cColor = db["CustomChan" .. idx .. "Color"]
                            local hex = chanHexCache[cColor]
                            if not hex then
                                hex = WT.Colors:GetHex(cColor, 0.8, 0.8, 0.8)
                                chanHexCache[cColor] = hex
                            end

                            displayTag = "|c" .. hex .. displayTag .. "|r"
                            local spacer, msgBody = string.match(restOfMessage, "^(:?%s*)(.*)")
                            if spacer and msgBody then restOfMessage = spacer ..
                                "|c" .. hex .. string.gsub(msgBody, "|r", "|r|c" .. hex) .. "|r" end
                        end

                        if string.find(fullLink, "|HclubStream:", 1, true) then
                            local clubStr = string.match(fullLink, "|HclubStream:([^|]+)|h")
                            if clubStr then
                                text = string.sub(text, 1, chanStart - 1) ..
                                "|HclubStream:" .. clubStr .. "|h[" .. displayTag .. "]|h" .. restOfMessage
                            end
                        else
                            text = string.sub(text, 1, chanStart - 1) ..
                            "|Hchannel:" .. justName .. "|h[" .. displayTag .. "]|h" .. restOfMessage
                        end
                        break
                    end
                end
            end
        end
        if not matchedChannel and string.find(fullLink, "|Hchannel:", 1, true) then
            local chanStr = string.match(fullLink, "|Hchannel:(%w+)|h")
            if chanStr then
                local chanStrUpper = string.upper(chanStr)
                if chanStrUpper == "INSTANCE_CHAT_LEADER" then chanStrUpper = "INSTANCE_CHAT" end
                if chanStrUpper == "PARTY_LEADER" then chanStrUpper = "PARTY" end
                if chanStrUpper == "RAID_LEADER" then chanStrUpper = "RAID" end

                local dbPrefix = ""
                if chanStrUpper == "GUILD" then
                    dbPrefix = "ChanGuild"
                elseif chanStrUpper == "OFFICER" then
                    dbPrefix = "ChanOfficer"
                elseif chanStrUpper == "PARTY" then
                    dbPrefix = "ChanParty"
                elseif chanStrUpper == "RAID" then
                    dbPrefix = "ChanRaid"
                elseif chanStrUpper == "INSTANCE_CHAT" then
                    dbPrefix = "ChanInstance"
                end

                if dbPrefix ~= "" then
                    local tag = nil
                    if db and db[dbPrefix .. "AliasEnabled"] then
                        tag = db[dbPrefix .. "Alias"]
                    elseif hasShortChannels then
                        if justName == "Guild" or justName == "Gilde" or justName == "Guilde" or justName == "Hermandad" or justName == "Gilda" or justName == "Гильдия" then
                            tag = "G"
                        elseif justName == "Officer" or justName == "Offizier" or justName == "Officier" or justName == "Oficial" or justName == "Ufficiale" or justName == "Офицер" then
                            tag = "O"
                        elseif justName == "Party" or justName == "Gruppe" or justName == "Groupe" or justName == "Grupo" or justName == "Gruppo" or justName == "Группа" then
                            tag = "P"
                        elseif justName == "Party Leader" or justName == "Gruppenanführer" or justName == "Chef de groupe" or justName == "Líder del grupo" or justName == "Capogruppo" or justName == "Лидер группы" then
                            tag = "PL"
                        elseif justName == "Party Guide" or justName == "Gruppenleiter" or justName == "Guide de groupe" or justName == "Guía del grupo" or justName == "Guida del gruppo" or justName == "Руководитель группы" then
                            tag = "PG"
                        elseif justName == "Raid" or justName == "Schlachtzug" or justName == "Banda" or justName == "Incursione" or justName == "Рейд" then
                            tag = "R"
                        elseif justName == "Raid Leader" or justName == "Schlachtzugsleiter" or justName == "Chef de raid" or justName == "Líder de banda" or justName == "Capoincursione" or justName == "Лидер рейда" then
                            tag = "RL"
                        elseif justName == "Raid Warning" or justName == "Schlachtzugswarnung" or justName == "Avertissement Raid" or justName == "Alerta de banda" or justName == "Avviso Incursione" or justName == "Объявление рейду" then
                            tag = "RW"
                        elseif justName == "Instance" or justName == "Instanz" or justName == "Instance" or justName == "Instancia" or justName == "Istanza" or justName == "Подземелье" then
                            tag = "I"
                        elseif justName == "Instance Leader" or justName == "Instanzanführer" or justName == "Chef d'instance" or justName == "Líder de instancia" or justName == "Capoistanza" or justName == "Лидер подземелья" then
                            tag = "IL"
                        else
                            -- Fallback for English default channel name prefixes if translation matches miss
                            if string.match(chanStr, "^[Gg]uild") then
                                tag = "G"
                            elseif string.match(chanStr, "^[Oo]fficer") then
                                tag = "O"
                            elseif string.match(chanStr, "^[Pp]arty") then
                                tag = "P"
                            elseif string.match(chanStr, "^[Rr]aid") then
                                tag = "R"
                            elseif string.match(chanStr, "^[Ii]nstance") then
                                tag = "I"
                            end
                        end
                    end

                    if tag and tag ~= "" then
                        local safeTag = string.gsub(tag, "%%", "%%%%")
                        text = string.gsub(text, "(|Hchannel:" .. chanStr .. "[^|]*|h)%[.-%](|h)",
                            "%1[" .. safeTag .. "]%2")
                    end

                    if db and db[dbPrefix .. "ColorEnabled"] then
                        local cColor = db[dbPrefix .. "Color"]
                        local cHex = chanHexCache[cColor]
                        if not cHex then
                            cHex = WT.Colors:GetHex(cColor, 0.8, 0.8, 0.8)
                            chanHexCache[cColor] = cHex
                        end

                        text = string.gsub(text, "(|Hchannel:" .. chanStr .. ".-|h%[.-%]|h:?%s*)(.*)", function(p1, rest)
                            local prefix, link, spacer, msgBody = string.match(rest,
                                "^(.-)(|H[bB]?[nN]?[pP]layer:.-|h%[.-%]|h)([^:]*:?%s*)(.*)$")
                            if not link then prefix, link, spacer, msgBody = string.match(rest,
                                    "^(.-)(|HclubMember:.-|h%[.-%]|h)([^:]*:?%s*)(.*)$") end
                            if prefix and link and spacer and msgBody then
                                return p1 ..
                                prefix ..
                                link .. spacer .. "|c" .. cHex .. string.gsub(msgBody, "|r", "|r|c" .. cHex) .. "|r"
                            else
                                return p1 .. "|c" .. cHex .. string.gsub(rest, "|r", "|r|c" .. cHex) .. "|r"
                            end
                        end, 1)
                    end
                end
            end
        elseif not matchedChannel and hasShortChannels and cNum and string.find(fullLink, "|Hchannel:", 1, true) then
            -- Catch-all for any other numbered channels if short channel names is enabled
            local chanStr = string.match(fullLink, "|Hchannel:(%w+)|h")
            if chanStr then
                text = string.gsub(text, "(|Hchannel:" .. chanStr .. "[^|]*|h)%[.-%](|h)",
                    "%1[" .. tostring(cNum) .. "]%2")
            end
        end
    end
    return text
end

local function ProcessSayYellModifications(text, ...)
    local id = select(4, ...)
    local dbPrefix = nil
    if ChatTypeInfo["SAY"] and id == ChatTypeInfo["SAY"].id then
        dbPrefix = "ChanSay"
    elseif ChatTypeInfo["YELL"] and id == ChatTypeInfo["YELL"].id then
        dbPrefix = "ChanYell"
    end
    if not dbPrefix then return text end

    local db = WT.DB.ChatChannels
    if db and db[dbPrefix .. "ColorEnabled"] then
        local cColor = db[dbPrefix .. "Color"]
        local cHex = chanHexCache[cColor]
        if not cHex then
            cHex = WT.Colors:GetHex(cColor, 1, 1, 1)
            chanHexCache[cColor] = cHex
        end

        local prefix, msgBody = string.match(text, "^(.-:%s*)(.*)$")
        if prefix and msgBody then
            text = prefix .. "|c" .. cHex .. string.gsub(msgBody, "|r", "|r|c" .. cHex) .. "|r"
        else
            text = "|c" .. cHex .. string.gsub(text, "|r", "|r|c" .. cHex) .. "|r"
        end
    end
    return text
end

local function ProcessWhisperModifications(text, isSelfMsg, ...)
    if not WT.DB.Modules.Chat then return text end

    -- Performance check: Early exit if no whisper modifications are enabled
    local db = WT.DB.ChatChannels
    if not db or (not db.ChanWhisperAliasEnabled and not db.ChanWhisperColorEnabled and not db.ChanBNetWhisperAliasEnabled and not db.ChanBNetWhisperColorEnabled) then
        return text
    end

    if string.find(text, "channel:", 1, true) or string.find(text, "clubStream:", 1, true) then
        return text
    end

    local hasPlayer = string.find(text, "player:", 1, true)
    local hasPlayerLink = hasPlayer and string.match(text, "|[Hh]player:")
    local hasBNetLink = hasPlayer and string.match(text, "|[Hh][Bb][Nn]player:")

    local r, g, b = select(1, ...), select(2, ...), select(3, ...)
    local isWoWWhisper = false
    local isBNetWhisper = false

    if hasPlayerLink then
        local rV = type(r) == "number" and r or 1
        local gV = type(g) == "number" and g or 1
        local bV = type(b) == "number" and b or 1
        pcall(function()
            if (rV > 0.9 and gV > 0.4 and gV < 0.6 and bV > 0.9) then
                isWoWWhisper = true
            end
        end)
    end
    if hasBNetLink then
        local rV = type(r) == "number" and r or 1
        local gV = type(g) == "number" and g or 1
        local bV = type(b) == "number" and b or 1
        pcall(function()
            if (rV < 0.1 and gV > 0.9 and bV > 0.9) then
                isBNetWhisper = true
            end
        end)
    end

    if not isWoWWhisper and not isBNetWhisper then return text end

    local dbPrefix = isWoWWhisper and "ChanWhisper" or "ChanBNetWhisper"

    if WT.DB.ChatChannels[dbPrefix .. "AliasEnabled"] then
        local tag = WT.DB.ChatChannels[dbPrefix .. "Alias"]
        if tag and tag ~= "" then
            local safeTag = string.gsub(tag, "%%", "%%%%")
            text = string.gsub(text, "(|H[bB]?[nN]?[pP]layer.-|h.-|h)%s*[^|:]*:%s*", "%1 " .. safeTag .. ": ", 1)
        end
    end

    if WT.DB.ChatChannels[dbPrefix .. "ColorEnabled"] then
        local cColor = WT.DB.ChatChannels[dbPrefix .. "Color"]
        local cHex = chanHexCache[cColor]
        if not cHex then
            cHex = WT.Colors:GetHex(cColor, 0.8, 0.8, 0.8)
            if #cHex < 8 then cHex = "FF" .. cHex end
            chanHexCache[cColor] = cHex
        end

        local prefix, link, spacer, msgBody = string.match(text,
            "^(.-)(|H[bB]?[nN]?[pP]layer:.-|h%[.-%]|h)([^:]*:?%s*)(.*)$")
        if not link then prefix, link, spacer, msgBody = string.match(text,
                "^(.-)(|HclubMember:.-|h%[.-%]|h)([^:]*:?%s*)(.*)$") end
        if prefix and link and spacer and msgBody then
            text = prefix .. link .. spacer .. "|c" .. cHex .. string.gsub(msgBody, "|r", "|r|c" .. cHex) .. "|r"
        else
            text = "|c" .. cHex .. string.gsub(text, "|r", "|r|c" .. cHex) .. "|r"
        end
    end

    return text
end

local function ProcessGuildNotes(text, isSelfMsg)
    if not WT.DB.Chat.ShowGuildNotes then return text end

    if not string.find(text, "channel:", 1, true) and not string.find(text, "clubStream:", 1, true) then return text end

    local isGuild = string.match(text, "|[Hh]channel:[Gg][Uu][Ii][Ll][Dd]|[hH]") ~= nil
    if not isGuild then
        local clubMatch = string.match(text, "|[Hh]club[Ss]tream:.-|[hH]%[(.-)%]|[hH]")
        if clubMatch then
            clubMatch = string.lower(clubMatch)
            if clubMatch == "guild" or clubMatch == "gilde" or clubMatch == "guilde" or clubMatch == "hermandad" or clubMatch == "gilda" or clubMatch == "гильдия" or clubMatch == "g" then
                isGuild = true
            end
        end
    end
    if not isGuild then return text end

    local authorLink = string.match(text, "|Hplayer:([^:|]+)")
    if not authorLink then
        authorLink = string.match(text, "|HclubMember:([^:|]+)")
    end
    if authorLink then
        local gName = Ambiguate(authorLink, "guild")
        local note = Module.rosterCache and Module.rosterCache[gName]

        if not note and Module.rosterCache then
            local shortName = strsplit("-", authorLink)
            note = Module.rosterCache[shortName]
        end

        if note == -1 then return text end

        -- SECURITY FIX: Always search the live roster if the note is missing from the cache!
        if not note and IsInGuild() then
            local foundMatch = false
            for i = 1, GetNumGuildMembers() do
                local rName, _, _, _, _, _, rNote = GetGuildRosterInfo(i)
                local uName = Unsecret(rName)
                if uName and uName ~= "" then
                    local rAmbig = Ambiguate(uName, "guild")
                    local okSplit, rShort = pcall(strsplit, "-", uName)
                    rShort = okSplit and rShort or uName
                    if rAmbig == gName or rShort == gName or uName == authorLink then
                        foundMatch = true
                        local uNote = Unsecret(rNote)
                        note = (uNote and strtrim(uNote) ~= "") and uNote or -1
                        if Module.rosterCache then
                            Module.rosterCache[rAmbig] = note
                            Module.rosterCache[rShort] = note
                        end
                        break
                    end
                end
            end
            if not foundMatch and Module.rosterCache then
                Module.rosterCache[gName] = -1
            end
        end

        local cleanNote = (note and note ~= -1 and strtrim(note) ~= "") and strtrim(note) or nil

        local headerStart, _, header, headerColon, msgPayload = string.find(text,
            "(|Hplayer:[^|]+|h%[.-%].-|h)(:?%s*)(.*)")
        if not headerStart then
            headerStart, _, header, headerColon, msgPayload = string.find(text,
                "(|HclubMember:[^|]+|h%[.-%].-|h)(:?%s*)(.*)")
        end
        if headerStart and header and msgPayload then
            local notePart = ""
            local actualMsg = msgPayload

            if WT.DB.Chat.ShowGuildNotes and cleanNote and (not isSelfMsg or WT.DB.Chat.ShowOwnGuildNote) then
                local cHex = WT.Colors:GetHex(WT.DB.Chat.NoteColor, 0.5, 1, 0.5)
                if #cHex < 8 then cHex = "FF" .. cHex end
                notePart = " |c" .. cHex .. "(" .. cleanNote .. ")|r"
            end

            if notePart ~= "" then
                local colStr = headerColon ~= "" and headerColon or ": "
                text = string.sub(text, 1, headerStart - 1) .. header .. notePart .. colStr .. actualMsg
            end
        end
    end
    return text
end

local function ProcessServerNames(text)
    if not WT.DB.Chat.HideServerNames then return text end

    if string.find(text, "|Hplayer:", 1, true) then
        local s_hide, res_hide = pcall(string.gsub, text, "(|Hplayer:[^|:%-]+)%-([^|:]+)(.-|h%[)(.-)(%]|h)",
            function(p1, pRealm, p3, pName, p5)
                local safeRealm = WT.Utils.Strings:EscapeRegex(pRealm)
                local safeRealmNoSpace = WT.Utils.Strings:EscapeRegex(string.gsub(pRealm, "%s+", ""))
                local newName = string.gsub(pName, "%-" .. safeRealm .. "$", "")
                newName = string.gsub(newName, "%-" .. safeRealmNoSpace .. "$", "")
                return p1 .. "-" .. pRealm .. p3 .. newName .. p5
            end)
        if s_hide then text = res_hide end
    end

    if string.find(text, "%-") then
        local s_hide, res_hide = pcall(string.gsub, text, "(|H[^|]+|h%[)(.-)(%]|h)", function(pStart, pName, pEnd)
            local base, possibleRealm = string.match(pName, "^(.*)%-([^%-%s]+)$")
            if base and possibleRealm and WT.Utils and WT.Utils.Realms and type(WT.Utils.Realms.IsKnownRealm) == "function" then
                if WT.Utils.Realms:IsKnownRealm(possibleRealm) then return pStart .. base .. pEnd end
            end
            return pStart .. pName .. pEnd
        end)
        if s_hide then text = res_hide end
    end
    return text
end

local function PlayerLevelReplaceFunc(linkStart, linkName, displayName, linkEnd)
    if string.match(displayName, "^|cFFFFD100") then return nil end
    local level = Module.playerLevelCache and Module.playerLevelCache[linkName]
    local shortName = strsplit("-", linkName)
    if not level and shortName and Module.playerLevelCache then
        level = Module.playerLevelCache[shortName]
    end

    if level == -1 then return string.format("%s[|cFFFFD100--|r] [%s]%s", linkStart, displayName, linkEnd) end -- Negative cache hit (Unknown player)

    if not level then
        local foundLevel = nil
        if UnitExists(linkName) then
            foundLevel = SafeNum(UnitLevel(linkName))
        elseif shortName and UnitExists(shortName) then
            foundLevel = SafeNum(UnitLevel(shortName))
        end

        if not foundLevel and IsInGuild() then
            local numGuild = SafeNum(GetNumGuildMembers())
            for i = 1, numGuild do
                local name, _, _, lvl = GetGuildRosterInfo(i)
                if name then
                    local n1 = Ambiguate(name, "none")
                    local n2 = strsplit("-", name)
                    if name == linkName or n1 == linkName or n2 == shortName then
                        foundLevel = SafeNum(lvl)
                        break
                    end
                end
            end
            return string.format("%s[|cFFFFD100--|r] [%s]%s", linkStart, displayName, linkEnd)
        end

        if not foundLevel then
            local numFriends = C_FriendList.GetNumFriends()
            local safeNumFriends = SafeNum(numFriends)
            if safeNumFriends > 0 then
                for i = 1, safeNumFriends do
                    local info = C_FriendList.GetFriendInfoByIndex(i)
                    if info and info.name and (info.name == linkName or strsplit("-", info.name) == shortName) then
                        foundLevel = SafeNum(info.level)
                        break
                    end
                end
            end
        end

        if not foundLevel then
            local numBNet = SafeNum((C_BattleNet and C_BattleNet.GetFriendCount and C_BattleNet.GetFriendCount()) or
            (BNGetNumFriends and BNGetNumFriends()) or 0)
            for i = 1, numBNet do
                local acc = C_BattleNet.GetFriendAccountInfo(i)
                if acc and acc.gameAccountInfo and acc.gameAccountInfo.isOnline and acc.gameAccountInfo.characterLevel then
                    local cName = acc.gameAccountInfo.characterName
                    if cName and (cName == shortName or cName == linkName) then
                        foundLevel = SafeNum(acc.gameAccountInfo.characterLevel)
                        break
                    end
                end
            end
        end

        if foundLevel and foundLevel > 0 then
            level = foundLevel
            if Module.playerLevelCache then
                Module.playerLevelCache[linkName] = level
                if shortName then Module.playerLevelCache[shortName] = level end
            end
        else
            if Module.playerLevelCache then
                Module.playerLevelCache[linkName] = -1
            end
        end
    end

    if level and level > 0 then return string.format("%s[|cFFFFD100%d|r] [%s]%s", linkStart, level, displayName, linkEnd) end
end

local function ProcessPlayerLevels(text)
    if WT.DB.Chat.ShowPlayerLevels and Module.playerLevelCache then
        if not string.find(text, "player:", 1, true) and not string.find(text, "clubMember:", 1, true) then return text end

        text = string.gsub(text, "(|Hplayer:([^:|]+).-|h)%[([^%]]+)%](|h)", PlayerLevelReplaceFunc)
        text = string.gsub(text, "(|HclubMember:([^:|]+).-|h)%[([^%]]+)%](|h)", PlayerLevelReplaceFunc)
    end
    return text
end

local function ProcessTimestamps(text)
    if not WT.DB.Chat.Timestamps or type(text) ~= "string" then return text end
    if Module.isRestoringHistory then return text end

    local ok, tsString = pcall(function()
        return WT.Modules.ChatUI and WT.Modules.ChatUI.GetTimestampString and WT.Modules.ChatUI:GetTimestampString() or
        ""
    end)

    if not ok or type(tsString) ~= "string" or tsString == "" then return text end

    -- Strip native or existing uncolored timestamps (e.g. 15:30, 03:45 PM)
    text = string.gsub(text, "^%s*%d+:%d+[:%d]*%s*", "")
    local upperText = string.upper(text)
    if string.match(upperText, "^AM%s+") or string.match(upperText, "^PM%s+") then
        text = string.gsub(text, "^[AaPp][Mm]%s+", "")
    end

    if strtrim(CleanString(text)) == "" then return text end

    -- Check if it already has our colored timestamp format
    if not string.match(text, "^|c[fF][fF]%x%x%x%x%x%x[%[%s%(]*%d%d?[:%.]%d%d") then
        text = tsString .. text
    end
    return text
end

local function ProcessChatHistory(self, text, isGuildHistoryForce, extractedName, ...)
    if not (WT.DB.Chat.ChatHistory and type(text) == "string") then return end

    if strtrim(CleanString(text)) == "" then return end

    local saveLine = false
    local r, g, b = select(1, ...), select(2, ...), select(3, ...)

    local hasChannel = string.find(text, "channel:", 1, true)
    local hasClub = string.find(text, "clubStream:", 1, true)
    local hasPlayer = string.find(text, "player:", 1, true)

    -- Abort immediately for Community Channels (K-String encryption prevents readable storage)
    if hasClub or string.match(text, "|[Hh]channel:[Cc][Oo][Mm][Mm][Uu][Nn][Ii][Tt][Yy]") then
        return
    end

    -- Core Channels
    if isGuildHistoryForce or (hasChannel and (string.match(text, "|[Hh]channel:[Gg][Uu][Ii][Ll][Dd]|[hH]") or string.match(text, "|[Hh]channel:[Oo][Ff][Ff][Ii][Cc][Ee][Rr]|[hH]") or string.match(text, "|[Hh]channel:[Oo]|[hH]") or string.match(text, "|[Hh]channel:[Pp][Aa][Rr][Tt][Yy]|[hH]") or string.match(text, "|[Hh]channel:[Rr][Aa][Ii][Dd]|[hH]") or string.match(text, "|[Hh]channel:[Ii][Nn][Ss][Tt][Aa][Nn][Cc][Ee]_[Cc][Hh][Aa][Tt]|[hH]"))) then
        saveLine = true
        -- Whispers (identified via standard whisper RGB colors)
    elseif hasPlayer and (string.match(text, "|[Hh]player:") or string.match(text, "|[Hh][Bb][Nn]player:")) then
        local rV = type(r) == "number" and r or 1
        local gV = type(g) == "number" and g or 1
        local bV = type(b) == "number" and b or 1
        pcall(function()
            if (rV > 0.9 and gV > 0.4 and gV < 0.6 and bV > 0.9) then
                saveLine = true
            end -- WoW Whisper (FF80FF)
            if (rV < 0.1 and gV > 0.9 and bV > 0.9) then
                saveLine = true
            end -- BNet Whisper (00FFFF)
        end)
    end

    -- Global, Custom, and Community Channels
    if not saveLine and string.match(text, "|[Hh]channel:.-|[hH]") then
        local tLower = string.lower(text)
        if WT.DB.Chat.HistoryChanGeneral and (string.find(tLower, "allgemein") or string.find(tLower, "general")) then saveLine = true end
        if WT.DB.Chat.HistoryChanTrade and (string.find(tLower, "handel") or string.find(tLower, "trade")) then saveLine = true end
        if WT.DB.Chat.HistoryChanLocalDef and (string.find(tLower, "lokale verteidigung") or string.find(tLower, "localdefense")) then saveLine = true end
        if WT.DB.Chat.HistoryChanServices and (string.find(tLower, "dienste") or string.find(tLower, "services")) then saveLine = true end

        if WT.DB.ChatChannels and WT.DB.ChatChannels.CustomChan1History and WT.DB.ChatChannels.CustomChan1Name and WT.DB.ChatChannels.CustomChan1Name ~= "" and string.find(tLower, string.lower(WT.DB.ChatChannels.CustomChan1Name)) then saveLine = true end
        if WT.DB.ChatChannels and WT.DB.ChatChannels.CustomChan2History and WT.DB.ChatChannels.CustomChan2Name and WT.DB.ChatChannels.CustomChan2Name ~= "" and string.find(tLower, string.lower(WT.DB.ChatChannels.CustomChan2Name)) then saveLine = true end
        if WT.DB.ChatChannels and WT.DB.ChatChannels.CustomChan3History and WT.DB.ChatChannels.CustomChan3Name and WT.DB.ChatChannels.CustomChan3Name ~= "" and string.find(tLower, string.lower(WT.DB.ChatChannels.CustomChan3Name)) then saveLine = true end
    end

    if saveLine then
        local fname = self.GetName and self:GetName() or "UnknownFrame"
        if not WT.DB.Chat.HistoryIncludeGeneral and fname == "ChatFrame1" then return end

        if not WT.DB.Internal then WT.DB.Internal = {} end
        if not WT.DB.Internal.ChatLog then WT.DB.Internal.ChatLog = {} end
        if WT.DB.Internal.ChatLog[1] and type(WT.DB.Internal.ChatLog[1]) == "string" then WT.DB.Internal.ChatLog = {} end -- Wipe legacy format

        if self.isTemporary and self.chatTarget then
            local target = Unsecret(self.chatTarget)
            if target then
                if self.chatType == "BN_WHISPER" then
                    local bnetID = type(target) == "number" and target or SafeNum(tonumber(target))
                    if type(bnetID) == "number" then
                        local s, acc = false, nil
                        if C_BattleNet and C_BattleNet.GetAccountInfoByID then s, acc = pcall(
                            C_BattleNet.GetAccountInfoByID, bnetID) end
                        if s and acc and acc.battleTag then target = acc.battleTag end
                    end
                end
                fname = "TEMP_" .. tostring(target)
            end
        end

        if not WT.DB.Internal.ChatLog[fname] then WT.DB.Internal.ChatLog[fname] = {} end

        local textToSave = text
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            local clampR = math.max(0, math.min(1, r))
            local clampG = math.max(0, math.min(1, g))
            local clampB = math.max(0, math.min(1, b))
            local hexColor = string.format("FF%02x%02x%02x", math.floor(clampR * 255 + 0.5),
                math.floor(clampG * 255 + 0.5), math.floor(clampB * 255 + 0.5))
            textToSave = "|c" .. hexColor .. string.gsub(textToSave, "|[rR]", "|r|c" .. hexColor) .. "|r"
        end

        if string.find(textToSave, "|K", 1, true) then
            local event = Module.CurrentChatEvent
            local args = Module.CurrentChatArgs or {}
            local rawMsgTag = args[1]
            local rawAuthorTag = args[2]
            local chatLineID = args[11]
            local bnetIDAccount = args[13]

            local function ReplaceAll(str, search, replace)
                if not search or search == "" or not replace then return str end
                local escapedSearch = string.gsub(search, "([%%%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
                local escapedReplace = string.gsub(replace, "%%", "%%%%")
                return string.gsub(str, escapedSearch, escapedReplace)
            end

            -- 1. Exact Native Resolution for BNet Names
            if (event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM") and bnetIDAccount then
                local bnetName = nil
                if C_BattleNet and C_BattleNet.GetAccountInfoByID then
                    local s, acc = pcall(C_BattleNet.GetAccountInfoByID, bnetIDAccount)
                    if s and acc then
                        bnetName = (acc.battleTag and strsplit("#", acc.battleTag)) or
                        (acc.accountName and acc.accountName ~= "" and acc.accountName)
                    end
                end

                if bnetName and rawAuthorTag and string.find(rawAuthorTag, "|K", 1, true) then
                    textToSave = ReplaceAll(textToSave, rawAuthorTag, bnetName)
                end
            end

            -- 2. Exact Native Resolution for Community Chat Messages
            if chatLineID and C_ChatInfo and C_ChatInfo.GetChatLineText then
                local s, nativeText = pcall(C_ChatInfo.GetChatLineText, chatLineID)
                if s and type(nativeText) == "string" and nativeText ~= "" then
                    if rawMsgTag and string.find(rawMsgTag, "|K", 1, true) and rawMsgTag ~= nativeText then
                        textToSave = ReplaceAll(textToSave, rawMsgTag, nativeText)
                    end
                end
            end

            -- 2b. Ultimate Fallback: UI-Engine K-Tag Decryption (for when C_ChatInfo fails, e.g. Community Chat)
            if string.find(textToSave, "|K", 1, true) and rawMsgTag and string.find(rawMsgTag, "|K", 1, true) then
                if not Module.hiddenKTagResolver then
                    Module.hiddenKTagResolver = UIParent:CreateFontString(nil, "BACKGROUND", "ChatFontNormal")
                    Module.hiddenKTagResolver:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, -10000)
                    Module.hiddenKTagResolver:SetAlpha(0.01)
                end
                Module.hiddenKTagResolver:SetText(rawMsgTag)
                local dummyWidth = Module.hiddenKTagResolver:GetStringWidth() -- Force layout update
                local engineResolved = Module.hiddenKTagResolver:GetText()
                if engineResolved and engineResolved ~= "" and engineResolved ~= rawMsgTag then
                    textToSave = ReplaceAll(textToSave, rawMsgTag, engineResolved)
                end
            end

            -- 3. Safely extract Names trapped in BNet/Guild hyperlinks (Fallback for everything else)
            textToSave = string.gsub(textToSave, "(|[Hh][^|:]+.-|[Hh])(.-)(|K.-|k)(.-)(|[Hh])",
                function(fullLink, beforeTag, kTag, afterTag, closing)
                    local resolved = nil
                    local lType = string.match(string.lower(fullLink), "|h(%w+):")

                    if lType and string.match(lType, "player$") then
                        resolved = string.match(fullLink, ":([^|:]+)")
                    elseif lType == "achievement" then
                        local achId = string.match(fullLink, ":(%d+)")
                        if achId then
                            local ok, _, name = pcall(GetAchievementInfo, tonumber(achId))
                            if ok and name and name ~= "" then resolved = name end
                        end
                    elseif lType == "clubstream" or lType == "clubfinder" then
                        local clubId = string.match(fullLink, ":(%d+)")
                        resolved = "Community"
                        if type(clubId) == "string" and C_Club and C_Club.GetClubInfo then
                            local clubInfo = C_Club.GetClubInfo(clubId)
                            if clubInfo then
                                local safeName = Unsecret(clubInfo.shortName or clubInfo.name)
                                if safeName and safeName ~= "" then resolved = safeName end
                            end
                        end
                    elseif lType == "channel" then
                        resolved = "Channel"
                        local cName = string.match(fullLink, ":([^|:]+)")
                        if cName and not string.match(cName, "^Community") then resolved = cName end
                    end

                    -- Generic GUID fallback inside hyperlinks
                    if not resolved or resolved == "Unknown" or resolved == "" then
                        local kType = string.sub(kTag, 3, 3)
                        local kData = string.match(kTag, "|K%w([^|]+)|k")
                        if kType == "q" and kData then
                            local ok, _, _, _, _, _, name = pcall(GetPlayerInfoByGUID, kData)
                            if ok and name and name ~= "" then resolved = name end
                        end
                    end

                    if resolved and resolved ~= "" and resolved ~= "Unknown" then
                        return fullLink .. beforeTag .. resolved .. afterTag .. closing
                    end

                    -- If completely unresolvable, defang the K-tag so its raw data is visible instead of disappearing.
                    local defanged = string.match(kTag, "|K.-:?([^|:]+)|k") or string.match(kTag, "|K.-([^|]+)|k") or ""
                    return fullLink .. beforeTag .. defanged .. afterTag .. closing
                end)

            -- 4. Smart Extraction for Wrapped Messages (e.g. |K.report:123|Hello World|k)
            textToSave = string.gsub(textToSave, "|K[^|]+|(.-)|k", "%1")

            -- 5. Universal K-Tag Defanger for remaining standalone tags (e.g. if GetChatLineText was unavailable)
            textToSave = string.gsub(textToSave, "|K.-:([^|:]+)|k", "%1")
            textToSave = string.gsub(textToSave, "|K.-([^|]+)|k", "%1")

            -- 6. Final Safety Catch (for completely empty or malformed K-tags)
            textToSave = string.gsub(textToSave, "|K.-|k", "")
        end

        local histLine = "|cFF888888[HIST]|r " .. textToSave
        local logTable = WT.DB.Internal.ChatLog[fname]
        if logTable[#logTable] ~= histLine then
            table.insert(logTable, histLine)

            local maxLines = type(WT.DB.Chat.HistoryMaxLines) == "number" and WT.DB.Chat.HistoryMaxLines or 100
            local over = #logTable - maxLines
            if over > 0 then
                -- High-Performance Array Shift
                for i = 1, maxLines do
                    logTable[i] = logTable[i + over]
                end
                for i = maxLines + 1, #logTable do
                    logTable[i] = nil
                end
            end
        end
    end
end

-- ============================================================================
-- MAIN HOOK
-- ============================================================================

local function FilterLogic(self, rawText, ...)
    local text = WT.Utils.Safety.Unsecret(rawText)
    if not text then return true, rawText end

    if not WT.DB or not WT.DB.Modules.Chat or not WT.DB.Chat then return true, text end

    local id = select(4, ...)
    if ChatTypeInfo["GUILD_ACHIEVEMENT"] and id == ChatTypeInfo["GUILD_ACHIEVEMENT"].id then
        local chanName = WT.DB.Chat.ShortChannelNames and "[G]" or "[" .. (GUILD or "Guild") .. "]"
        local prefix = "|Hchannel:GUILD|h" .. chanName .. "|h "
        text = prefix .. text
        -- Note: We can't set isGuildHistoryForce here anymore because it's defined lower.
        -- We will inject the tag instead, so the lower logic catches it.
        text = "||WT_GHIST||" .. text
    end

    text = CleanEmojis(text)

    local extractedName = string.match(text, "|[Hh]player:([^:]+)")
    if not extractedName then extractedName = string.match(text, "|[Hh]player:.-|h%[([^%]]+)%]|h") end
    if not extractedName then extractedName = string.match(text, "|[Hh][Bb][Nn]player:.-|h%[([^%]]+)%]|h") end
    if not extractedName then extractedName = string.match(text, "|[Hh]clubMember:.-|h%[([^%]]+)%]|h") end

    local event = Module.CurrentChatEvent
    local args = Module.CurrentChatArgs or {}
    local guid = args[12]
    local bnSenderID = args[13]
    local sender = args[2] or extractedName

    local isSelfMsg = WT.Modules.Chat:IsSelfMessage(event, guid, bnSenderID, sender, text)
    if not isSelfMsg and extractedName and extractedName ~= sender then
        isSelfMsg = WT.Modules.Chat:IsSelfMessage(event, guid, bnSenderID, extractedName, text)
    end
    if not isSelfMsg then isSelfMsg = DetectSelfMessage(text, sender or extractedName) end
    if not isSelfMsg then
        local pName = cachedPlayerName or (UnitName and UnitName("player"))
        if pName and pName ~= "" then
            local rawS = sender or extractedName
            if rawS then
                local sClean = tostring(rawS):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                sClean = sClean:gsub("|[Hh].-|[hH](.-)|[hH]", "%1"):gsub("|[Hh].-|[hH]", ""):gsub("|h", "")
                sClean = sClean:gsub("%s*%(%*%)", ""):gsub("[%[%]]", "")
                sClean = strtrim(sClean)
                local sBase = string.match(sClean, "^([^%-]+)") or sClean
                sBase = strtrim(sBase)
                local sBaseLower = (strlower and strlower(sBase)) or (_G["mbstrlower"] and _G["mbstrlower"](sBase)) or
                string.lower(sBase)
                local pLower = (strlower and strlower(pName)) or (_G["mbstrlower"] and _G["mbstrlower"](pName)) or
                string.lower(pName)
                if sBase == pName or (sBaseLower ~= "" and sBaseLower == pLower) or sClean == pName then
                    isSelfMsg = true
                end
            end
        end
    end

    if WT.Modules.Chat.ProcessSmartLogins then
        local allowLogin, newText = WT.Modules.Chat:ProcessSmartLogins(text)
        if not allowLogin then return false, nil end
        text = newText
    end

    local isGuildHistoryForce = false
    if string.find(text, "||WT_GHIST||", 1, true) then
        text = string.gsub(text, "||WT_GHIST||", "")
        isGuildHistoryForce = true
    end

    local allow, blockMsg = ProcessBlacklist(text, isSelfMsg, extractedName, ...)
    if not allow then
        return false, blockMsg
    end

    text = ProcessHighlightsAndURLs(text, isSelfMsg)
    text = ProcessSayYellModifications(text, ...)
    text = ProcessChannelModifications(text, isSelfMsg)
    text = ProcessWhisperModifications(text, isSelfMsg, ...)
    text = ProcessGuildNotes(text, isSelfMsg)
    text = ProcessServerNames(text)
    text = ProcessPlayerLevels(text)
    text = ProcessTimestamps(text)

    ProcessChatHistory(self, text, isGuildHistoryForce, extractedName, ...)

    return true, text
end

function Module:HookAddMessage()
    -- Use Blizzard's official Event Filter API to capture the exact chat event arguments (ChatLineID, BNetAccountID)
    -- This runs synchronously right before the ChatFrame formats the message and calls AddMessage!
    if not Module.isEventHandlerHooked then
        Module.isEventHandlerHooked = true

        local function CaptureChatEventArgs(chatFrame, event, ...)
            Module.CurrentChatEvent = event
            Module.CurrentChatArgs = { ... }
            return false, ... -- Do not filter, just capture
        end

        local eventsToCapture = {
            "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL",
            "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY",
            "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
            "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
            "CHAT_MSG_SAY", "CHAT_MSG_YELL",
            "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER",
            "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER_INFORM",
            "CHAT_MSG_RAID_WARNING", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE"
        }

        for _, ev in ipairs(eventsToCapture) do
            ChatFrame_AddMessageEventFilter(ev, CaptureChatEventArgs)
        end
    end

    local safeCall = securecallfunction or securecall
    for _, frameName in ipairs(CHAT_FRAMES) do
        local cf = _G[frameName]
        if cf then
            local fs = filterState[cf]
            if not fs then
                fs = {}; filterState[cf] = fs
            end
            if not fs.addMessageHooked then
                fs.addMessageHooked = true
                local oldAddMessage = cf.AddMessage
                cf.AddMessage = function(self, text, ...)
                    if Module.isRestoringBlockedMsg then return safeCall(oldAddMessage, self, text, ...) end
                    if Module.isRestoringHistory then return safeCall(oldAddMessage, self, text, ...) end
                    if WT.isLoggerPrinting then return safeCall(oldAddMessage, self, text, ...) end

                    local success, allow, outText = pcall(FilterLogic, self, text, ...)

                    if not success then
                        -- The filter crashed! Print the error directly to chat if debug is active.
                        if WT.DB and WT.DB.General and WT.DB.General.DebugMode then
                            if not Module.isPrintingError then
                                Module.isPrintingError = true
                                safeCall(oldAddMessage, self, "|cFFFF0000[WT Chat Filter Error]|r " .. tostring(allow))
                                Module.isPrintingError = false
                            end
                        end
                        -- Forward the unformatted original text so the chat doesn't break!
                        return safeCall(oldAddMessage, self, text, ...)
                    end

                    if not allow then
                        if outText then return safeCall(oldAddMessage, self, outText, ...) end
                        return
                    end

                    return safeCall(oldAddMessage, self, outText, ...)
                end
            end
        end
    end
end

WT.Modules.ChatFilter = {}
function WT.Modules.ChatFilter:BuildOptions(builder, panel)
    local function AddDescription(text)
        if not text then return end
        local desc = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
        desc:SetWidth(550)
        desc:SetJustifyH("LEFT")
        desc:SetText(text)
        builder:AddSpace(desc:GetStringHeight() + 25)
    end

    panel:CreateTitle(builder, WT.L.GROUP_CHAT_FILTERS)
    AddDescription(WT.L.OPT_DESC_GROUP_CHAT_FILTERS)

    local totalBlocked = WT.DB.Internal and WT.DB.Internal.TotalBlocked or 0
    local sessionBlocked = WT.Modules.Chat.SessionBlockedCount or 0
    local statsText = string.format(WT.L.CHAT_FILTER_STATS,
        sessionBlocked, totalBlocked)
    local statsLbl = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    statsLbl:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
    statsLbl:SetText(statsText)
    builder:AddSpace(30)

    local updateTimer
    local function DebounceUpdate()
        if updateTimer then updateTimer:Cancel() end
        updateTimer = C_Timer.NewTimer(0.5, function() WT.Modules.Chat:UpdateChatFilters() end)
    end

    local hlInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_HIGHLIGHTS, WT.L.OPT_DESC_CHAT_HIGHLIGHTS, "Chat",
        "EnableHighlights", DebounceUpdate)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_HIGHLIGHT, WT.L.OPT_DESC_COLOR_VALUE, "Chat", "HighlightColor", false,
        hlInit)
    panel:CreateSoundDropdown(builder, WT.L.OPT_CHAT_HIGHLIGHT_SOUND, WT.L.OPT_DESC_CHAT_HIGHLIGHT_SOUND, "Chat",
        "HighlightSound", hlInit)
    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_HL_PLAYERS, WT.L.OPT_DESC_CHAT_HL_PLAYERS, "Chat", "HighlightOnlyPlayers",
        DebounceUpdate, hlInit)

    panel:CreateMultiLineEditBox(builder, WT.L.OPT_CHAT_HIGHLIGHT_WORDS, WT.L.OPT_DESC_CHAT_HIGHLIGHT_WORDS, "Chat",
        "HighlightWords", 80, DebounceUpdate)

    local blInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_BLACKLIST, WT.L.OPT_DESC_CHAT_BLACKLIST, "Chat",
        "EnableBlacklist", DebounceUpdate)
    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_FILTER_OWN, WT.L.OPT_DESC_CHAT_FILTER_OWN, "Chat", "FilterOwnMessages",
        DebounceUpdate, blInit)
    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_FILTER_GUILD, WT.L.OPT_DESC_CHAT_FILTER_GUILD, "Chat", "FilterGuild",
        DebounceUpdate, blInit)
    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_FILTER_GROUP, WT.L.OPT_DESC_CHAT_FILTER_GROUP, "Chat", "FilterGroup",
        DebounceUpdate, blInit)
    panel:CreateCheckbox(builder, WT.L.OPT_CHAT_FILTER_FRIENDS, WT.L.OPT_DESC_CHAT_FILTER_FRIENDS, "Chat",
        "FilterFriends", DebounceUpdate, blInit)
    panel:CreateMultiLineEditBox(builder, WT.L.OPT_CHAT_BLACKLIST_WORDS, WT.L.OPT_DESC_CHAT_BLACKLIST_WORDS, "Chat",
        "BlacklistWords", 80, DebounceUpdate)
    local notifyInit = panel:CreateCheckbox(builder, WT.L.OPT_CHAT_BL_NOTIFY, WT.L.OPT_DESC_CHAT_BL_NOTIFY, "Chat",
        "BlacklistNotify", nil, blInit)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_TEXT, WT.L.OPT_DESC_COLOR_VALUE, "Chat", "BlacklistNotifyColor",
        false, notifyInit)

    panel:CreateMultiLineEditBox(builder, WT.L.OPT_CHAT_WHITELIST_PLAYERS, WT.L.OPT_DESC_CHAT_WHITELIST_PLAYERS, "Chat",
        "WhitelistPlayers", 80, DebounceUpdate)
end
