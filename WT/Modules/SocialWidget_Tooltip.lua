local addonName, WT = ...
local Module = WT.Modules.SocialWidget

local guildListCache = {}
local wowFriendsListCache = {}
local appFriendsListCache = {}

local tostring = tostring
local string_format = string.format
local string_gsub = string.gsub
local string_upper = string.upper
local string_find = string.find
local table_insert = table.insert
local table_wipe = table.wipe or wipe
local pcall = pcall
local GetRealmName = GetRealmName
local UnitFactionGroup = UnitFactionGroup
local InCombatLockdown = InCombatLockdown

local Ambiguate = Ambiguate or
function(name, context) return name and
    ((context == "short" or context == "guild") and string.match(name, "^([^%-]+)") or name) or "" end
local GetNumGuildMembers = GetNumGuildMembers or (C_GuildInfo and C_GuildInfo.GetNumGuildMembers) or
function() return 0 end
local GetGuildRosterInfo = GetGuildRosterInfo or (C_GuildInfo and C_GuildInfo.GetGuildRosterInfo) or
function() return nil end

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

local Unsecret = WT.Utils.Safety.Unsecret
local SafeNum = WT.Utils.Safety.SafeNum

local function GetLevelString(level)
    if not WT.DB.SocialWidget.ShowLevel then return "" end
    local c = WT.Colors:GetHex(WT.DB.SocialWidget.ColLevel, 1, 0.8196, 0)
    if not level or level == "" or level == 0 then
        return "|c" .. c .. "[--]|r "
    end
    return "|c" .. c .. "[" .. level .. "]|r "
end

local function GetRaceString(race)
    if not WT.DB.SocialWidget.ShowRace then return "" end
    local c = WT.Colors:GetHex(WT.DB.SocialWidget.ColRace, 1, 1, 1)
    if not race or race == "" then
        return "|c" .. c .. "---|r "
    end
    return "|c" .. c .. race .. "|r "
end

local function GetGenderColor(sex)
    if not WT.DB.SocialWidget.ShowGender or not sex then return "" end
    local pColor = "|c" .. WT.Colors:GetHex(WT.DB.SocialWidget.ColRace, 1, 1, 1)
    local maleStr = string_gsub(tostring(WT.L.GENDER_MALE), "[%(%)]", "")
    local femaleStr = string_gsub(tostring(WT.L.GENDER_FEMALE), "[%(%)]", "")
    if sex == 2 then return pColor ..
        "(|r|c" .. WT.Colors:GetHex(WT.DB.SocialWidget.ColMale, 0, 0.44, 1) .. maleStr .. "|r" .. pColor .. ")|r " end
    if sex == 3 then return pColor ..
        "(|r|c" .. WT.Colors:GetHex(WT.DB.SocialWidget.ColFemale, 1, 0.41, 0.7) .. femaleStr .. "|r" .. pColor .. ")|r " end
    return ""
end

local function GetFactionIcon(faction)
    if not WT.DB.SocialWidget.ShowFaction then return "" end
    if faction == "Alliance" then return "|TInterface\\FriendsFrame\\PlusManz-Alliance:14:14:0:-1|t " end
    if faction == "Horde" then return "|TInterface\\FriendsFrame\\PlusManz-Horde:14:14:0:-1|t " end
    return "|TInterface\\COMMON\\Indicator-Gray:14:14:0:-1|t "
end

local function GetLocationString(loc)
    if not WT.DB.SocialWidget.ShowLocation then return "" end
    local c = WT.Colors:GetHex(WT.DB.SocialWidget.ColLocation, 0.66, 0.66, 0.66)
    if not loc or loc == "" then
        return "|c" .. c .. "- ---|r "
    end
    return "|c" .. c .. "- " .. loc .. "|r "
end

local function GetRealmString(realm)
    if not WT.DB.SocialWidget.ShowRealm then return "" end
    if not realm or realm == "" then realm = "---" end
    local dashColor = WT.Colors:GetHex(WT.DB.SocialWidget.ColLocation, 0.66, 0.66, 0.66)
    local lblColor = WT.Colors:GetHex(WT.DB.SocialWidget.ColLevel, 1, 0.82, 0)
    local valColor = WT.Colors:GetHex(WT.DB.SocialWidget.ColRealm, 1, 1, 1)
    return "|c" ..
    dashColor ..
    "-|r |c" ..
    lblColor .. tostring(WT.L.TT_REALM) .. " [|r|c" .. valColor .. realm .. "|r|c" .. lblColor .. "]|r "
end

local function GetStatusString(isAFK, isDND, rawStatus)
    if not WT.DB.SocialWidget.ShowStatus then return "" end
    if type(rawStatus) == "number" then
        if rawStatus == 1 then
            isAFK = true
        elseif rawStatus == 2 then
            isDND = true
        end
    elseif type(rawStatus) == "string" and rawStatus ~= "" then
        local upperStatus = string_upper(rawStatus)
        if string_find(upperStatus, "DND") or string_find(upperStatus, "NICHT") or string_find(upperStatus, "BUSY") then isDND = true else isAFK = true end
    end
    if isDND then
        return "|c" .. WT.Colors:GetHex(WT.DB.SocialWidget.ColDND, 1, 0.2, 0.2) .. "[DND]|r "
    elseif isAFK then
        return "|c" .. WT.Colors:GetHex(WT.DB.SocialWidget.ColAFK, 1, 0.82, 0) .. "[AFK]|r "
    end
    return ""
end

local function GetNoteString(note)
    if not WT.DB.SocialWidget.ShowNote or not note or note == "" then return "" end
    local pColor = "|c" .. WT.Colors:GetHex(WT.DB.SocialWidget.ColRace, 1, 1, 1)
    return pColor .. "(|r|c" .. WT.Colors:GetHex(WT.DB.SocialWidget.ColNote, 0, 1, 0) .. note .. "|r" .. pColor .. ")|r"
end

function Module:ShowDetailedTooltip(frame)
    if not WT.DB.SocialWidget then return end

    local tt = _G["WTSocialTooltip"]
    if not tt then
        tt = CreateFrame("GameTooltip", "WTSocialTooltip", _G["WT_UIContainer"], "GameTooltipTemplate")
        tt.ignoreInLayout = true
        tt.ignoreFramePositionManager = true
        if tt.SetIsFramePositionManaged then pcall(function() tt:SetIsFramePositionManaged(false) end) end
    end

    if WT.DB.SocialWidget.HideTooltipCombat and InCombatLockdown() then
        if tt:GetOwner() == frame then tt:Hide() end
        return
    end

    local mod = WT.DB.SocialWidget.TooltipModifier or "NONE"
    if mod == "SHIFT" and not IsShiftKeyDown() then
        if tt:GetOwner() == frame then tt:Hide() end; return
    end
    if mod == "CTRL" and not IsControlKeyDown() then
        if tt:GetOwner() == frame then tt:Hide() end; return
    end
    if mod == "ALT" and not IsAltKeyDown() then
        if tt:GetOwner() == frame then tt:Hide() end; return
    end

    if WT.DB.Tooltip and WT.DB.Tooltip.CursorAnchor then
        local align = WT.DB.Tooltip.CursorAnchorType
        local x = WT.DB.Tooltip.CursorX or 0
        local y = WT.DB.Tooltip.CursorY or 0

        if align == "ANCHOR_CURSOR_LEFT" then
            tt:SetOwner(frame, "ANCHOR_CURSOR", x, y)
        elseif align == "ANCHOR_CURSOR_RIGHT" then
            tt:SetOwner(frame, "ANCHOR_CURSOR_RIGHT", x, y)
        else
            tt:SetOwner(frame, "ANCHOR_CURSOR", x, y)
        end
    else
        local y = frame:GetBottom() or 0
        if y < (_G.GetScreenHeight() / 2) then
            tt:SetOwner(frame, "ANCHOR_TOP")
        else
            tt:SetOwner(frame, "ANCHOR_BOTTOM")
        end
    end

    tt:ClearLines()
    tt:AddLine(
    "|TInterface\\AddOns\\" ..
    addonName .. "\\Media\\Graphics\\Logo.tga:16:16:0:0|t " .. tostring(WT.L.SW_TITLE),
        WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B)

    local hasContent = false

    if WT.DB.SocialWidget.ShowGuild and IsInGuild() then
        local okG, numGuildRaw = pcall(GetNumGuildMembers)
        local numGuildMembers = okG and SafeNum(numGuildRaw) or 0
        local onlineGuild = 0
        table_wipe(guildListCache)
        local okFac, pFac = pcall(UnitFactionGroup, "player")
        local playerFaction = okFac and Unsecret(pFac) or "Alliance"

        for i = 1, numGuildMembers do
            local ok, name, _, _, level, _, zone, note, _, online, status, classFileName, _, _, _, _, _, GUID = pcall(
            GetGuildRosterInfo, i)
            local isOnline = ok and (type(online) == "boolean" and online) or false
            local uName = ok and Unsecret(name) or nil
            if isOnline and uName then
                onlineGuild = onlineGuild + 1
                local ok, cName = pcall(strsplit, "-", uName)
                local cleanName = ok and cName or uName
                local uZone = Unsecret(zone)
                local uNote = Unsecret(note)
                local uGuid = Unsecret(GUID)
                local uClass = Unsecret(classFileName)
                local _, _, race, englishRace, sex = WT.Utils:GetPlayerInfoByGUID(uGuid)
                local cColor = uClass and (WT.DB.ClassColors and WT.DB.ClassColors[uClass] or RAID_CLASS_COLORS[uClass]) or
                nil
                local classColorStr = cColor and WT.Colors:GetHex(cColor) or "ffffffff"
                local hexName = "|c" .. classColorStr .. cleanName .. "|r"

                local okR, rName = pcall(function() return select(2, strsplit("-", uName)) end)
                local realm = okR and rName or nil
                if not realm or realm == "" then realm = Unsecret(GetRealmName()) end

                local memberFaction = englishRace and WT.Utils.Units.RACE_TO_FACTION[englishRace] or playerFaction
                local statusStr = GetStatusString(false, false, Unsecret(status))
                local displayStr = GetLevelString(SafeNum(level)) ..
                statusStr ..
                GetFactionIcon(memberFaction) ..
                hexName ..
                " " ..
                GetRaceString(race) ..
                GetGenderColor(sex) .. GetLocationString(uZone) .. GetRealmString(realm) .. GetNoteString(uNote)
                table_insert(guildListCache, displayStr)
            end
        end

        if onlineGuild > 0 then
            hasContent = true
            tt:AddLine(" ")
            tt:AddLine(tostring(WT.L.SW_GUILD_ONLINE) .. onlineGuild, 0, 1, 0)
            tt:AddLine("|TInterface\\Common\\UI-TooltipDivider-Transparent:8:260:0:3|t")
            for _, info in ipairs(guildListCache) do tt:AddLine(info, 1, 1, 1) end
        end
    end

    if WT.DB.SocialWidget.ShowBNet then
        local okBN, numBnetRaw = pcall(function() return (C_BattleNet and C_BattleNet.GetFriendNum and C_BattleNet.GetFriendNum()) or
            (C_BattleNet and C_BattleNet.GetFriendCount and C_BattleNet.GetFriendCount()) or
            (BNGetNumFriends and BNGetNumFriends()) or 0 end)
        local bnetFriends = okBN and SafeNum(numBnetRaw) or 0
        local okF, numFriendsRaw = pcall(C_FriendList.GetNumFriends)
        local wowFriends = okF and SafeNum(numFriendsRaw) or 0
        table_wipe(wowFriendsListCache)
        table_wipe(appFriendsListCache)

        for i = 1, bnetFriends do
            local okAcc, accountInfo = false, nil
            if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
                okAcc, accountInfo = pcall(C_BattleNet.GetFriendAccountInfo, i)
            end
            if okAcc and accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline then
                local g = accountInfo.gameAccountInfo
                local client = g and Unsecret(g.clientProgram) or nil
                local nameStr = Unsecret(accountInfo.accountName) or ""

                if client == "WoW" or client == BNET_CLIENT_WOW then
                    local charName = Unsecret(g.characterName) or ""
                    local classColorStr = "ff4da6ff"
                    local sex = nil

                    local classFileName = g.className
                    local pGuid = Unsecret(g.playerGuid)
                    if pGuid then
                        local _, guidClassFile, _, _, playerSex = WT.Utils:GetPlayerInfoByGUID(pGuid)
                        sex = playerSex
                        if guidClassFile and not RAID_CLASS_COLORS[classFileName] then
                            classFileName = guidClassFile
                        end
                    end

                    if classFileName then
                        local cColor = WT.DB.ClassColors and WT.DB.ClassColors[classFileName] or
                        RAID_CLASS_COLORS[classFileName]
                        if cColor then classColorStr = WT.Colors:GetHex(cColor) end
                    end

                    if charName ~= "" then
                        nameStr = "|cFF82C5FF" .. nameStr .. "|r (|c" .. classColorStr .. charName .. "|r)"
                    else
                        nameStr = "|cFF82C5FF" .. nameStr .. "|r"
                    end

                    local realm = Unsecret(g.realmName) or ""
                    local statusStr = GetStatusString(accountInfo.isAFK or (g and g.isGameAFK),
                        accountInfo.isDND or (g and g.isGameBusy))
                    local displayStr = GetLevelString(SafeNum(g.characterLevel)) ..
                    statusStr ..
                    GetFactionIcon(Unsecret(g.factionName)) ..
                    nameStr ..
                    " " ..
                    GetRaceString(Unsecret(g.raceName)) ..
                    GetGenderColor(sex) ..
                    GetLocationString(Unsecret(g.areaName)) ..
                    GetRealmString(realm) .. GetNoteString(Unsecret(accountInfo.note))
                    table_insert(wowFriendsListCache, displayStr)
                else
                    local gameStr = (client and client ~= "") and (" [|cFF00FFFF" .. client .. "|r]") or
                    " [|cFF00FFFFApp|r]"
                    local statusStr = GetStatusString(accountInfo.isAFK or (g and g.isGameAFK),
                        accountInfo.isDND or (g and g.isGameBusy))
                    local displayStr = statusStr ..
                    "|cFF82C5FF" .. nameStr .. gameStr .. "|r " .. GetNoteString(Unsecret(accountInfo.note))
                    table_insert(appFriendsListCache, displayStr)
                end
            end
        end

        for i = 1, wowFriends do
            local okFInfo, friendInfo = pcall(C_FriendList.GetFriendInfoByIndex, i)
            if okFInfo and friendInfo and friendInfo.connected then
                local _, _, race, _, sex
                local fGuid = Unsecret(friendInfo.guid)
                if fGuid then _, _, race, _, sex = WT.Utils:GetPlayerInfoByGUID(fGuid) end

                local fClass = Unsecret(friendInfo.className)
                local fName = Unsecret(friendInfo.name) or "Unknown"

                local cColor = fClass and (WT.DB.ClassColors and WT.DB.ClassColors[fClass] or RAID_CLASS_COLORS[fClass]) or
                nil
                local classColorStr = cColor and WT.Colors:GetHex(cColor) or "ffffffff"
                local hexName = "|c" .. classColorStr .. fName .. "|r"

                local okR, rName = pcall(function() return select(2, strsplit("-", fName)) end)
                local realm = okR and rName or nil
                if not realm or realm == "" then realm = Unsecret(GetRealmName()) end

                local statusStr = GetStatusString(friendInfo.afk, friendInfo.dnd)
                local okFac2, pFac2 = pcall(UnitFactionGroup, "player")
                local pFaction2 = okFac2 and Unsecret(pFac2) or "Alliance"
                local displayStr = GetLevelString(SafeNum(friendInfo.level)) ..
                statusStr ..
                GetFactionIcon(pFaction2) ..
                hexName ..
                " " ..
                GetRaceString(race) ..
                GetGenderColor(sex) ..
                GetLocationString(Unsecret(friendInfo.area)) ..
                GetRealmString(realm) .. GetNoteString(Unsecret(friendInfo.notes))
                table_insert(wowFriendsListCache, displayStr)
            end
        end

        if #wowFriendsListCache > 0 then
            hasContent = true
            tt:AddLine(" ")
            tt:AddLine(tostring(WT.L.SW_FRIENDS_ONLINE) .. #wowFriendsListCache,
                WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B)
            tt:AddLine("|TInterface\\Common\\UI-TooltipDivider-Transparent:8:260:0:3|t")
            for _, info in ipairs(wowFriendsListCache) do tt:AddLine(info, 1, 1, 1) end
        end
        if #appFriendsListCache > 0 then
            hasContent = true
            tt:AddLine(" ")
            tt:AddLine(tostring(WT.L.SW_BNET_ONLINE) .. #appFriendsListCache, 0.6, 0.8, 1)
            tt:AddLine("|TInterface\\Common\\UI-TooltipDivider-Transparent:8:260:0:3|t")
            for _, info in ipairs(appFriendsListCache) do tt:AddLine(info, 1, 1, 1) end
        end
    end

    if not hasContent then
        tt:AddLine(" ")

        local showGuild = WT.DB.SocialWidget.ShowGuild
        local showBNet = WT.DB.SocialWidget.ShowBNet

        if showGuild and showBNet then
            if not IsInGuild() then
                tt:AddLine(tostring(WT.L.SW_TT_EMPTY_BOTH_NOGUILD), 0.5, 0.5, 0.5)
            else
                tt:AddLine(tostring(WT.L.SW_TT_EMPTY_BOTH), 0.5, 0.5, 0.5)
            end
        elseif showGuild then
            if not IsInGuild() then
                tt:AddLine(tostring(WT.L.SW_TT_NO_GUILD), 0.5, 0.5, 0.5)
            else
                tt:AddLine(tostring(WT.L.SW_TT_EMPTY_GUILD), 0.5, 0.5, 0.5)
            end
        elseif showBNet then
            tt:AddLine(tostring(WT.L.SW_TT_EMPTY_FRIENDS), 0.5, 0.5, 0.5)
        end
    end

    tt:Show()
end
