local addonName, WT = ...

-- ============================================================================
-- SOCIAL WIDGET: HOVER TOOLTIP
-- ============================================================================
-- Lists online guild members, WoW friends and Battle.net friends in other games / the app.
-- Uses the pre-created WTSocialTooltip (see Core/Init.lua) so the Tooltip module can style it.
-- With "Click to Whisper" the tooltip stays open while the mouse is over it, and every entry
-- gets an invisible button on top of its line that opens a whisper.

local Module = WT.Modules.SocialWidget

local tostring = tostring
local string_gsub = string.gsub
local string_match = string.match
local string_lower = string.lower
local string_format = string.format
local table_sort = table.sort
local wipe = wipe

local Unsecret = WT.Utils.Safety.Unsecret
local SafeNum = WT.Utils.Safety.SafeNum
local SafeBool = WT.Utils.Safety.SafeBool

local DIVIDER = "|TInterface\\Common\\UI-TooltipDivider-Transparent:8:260:0:3|t"
local COLOR_BNET_NAME = "|cFF82C5FF"
local COLOR_CLIENT = "|cFF00FFFF"
local COLOR_GROUP = "|cFF66CCFF"
local COLOR_MOBILE = "|cFF999999"
local COLOR_FALLBACK_CLASS = "ffffffff"
local COLOR_FALLBACK_BNET_CLASS = "ff4da6ff"
local CLIENT_ICON_SIZE = 14
local HOVER_CHECK_INTERVAL = 0.1

-- GetGuildRosterInfo status values
local STATUS_AFK = 1
local STATUS_DND = 2

local guildEntries = {}
local mobileEntries = {}
local wowFriendEntries = {}
local appFriendEntries = {}
local groupGUIDs = {}

-- Line index -> entry, filled while building an interactive tooltip
local lineEntries = {}
local rowButtons = {}

-- ----------------------------------------------------------------------------
-- Text helpers
-- ----------------------------------------------------------------------------

--- Splits "Name-Realm" into name and realm; realm falls back to the player's realm.
local function SplitName(fullName)
    local name, realm = string_match(fullName, "^([^%-]+)%-(.+)$")
    if not name then
        return fullName, Unsecret(GetRealmName())
    end
    return name, realm
end

local function GetClassColorHex(classFile)
    if not classFile then return nil end
    local color = (WT.DB.ClassColors and WT.DB.ClassColors[classFile]) or RAID_CLASS_COLORS[classFile]
    return color and WT.Colors:GetHex(color) or nil
end

local function GetClientIcon(client)
    local getAtlas = _G["BNet_GetClientEmbeddedAtlas"]
    if getAtlas then
        return getAtlas(client, CLIENT_ICON_SIZE) .. " "
    end
    return ""
end

local function GetLevelString(level)
    local db = WT.DB.SocialWidget
    if not db.ShowLevel then return "" end
    local color = WT.Colors:GetHex(db.ColLevel, 1, 0.8196, 0)
    if not level or level == 0 then
        return "|c" .. color .. "[--]|r "
    end
    return "|c" .. color .. "[" .. level .. "]|r "
end

local function GetRaceString(race)
    local db = WT.DB.SocialWidget
    if not db.ShowRace then return "" end
    local color = WT.Colors:GetHex(db.ColRace, 1, 1, 1)
    if not race or race == "" then
        return "|c" .. color .. "---|r "
    end
    return "|c" .. color .. race .. "|r "
end

local function GetGenderString(sex)
    local db = WT.DB.SocialWidget
    if not db.ShowGender or not sex then return "" end
    local bracketColor = "|c" .. WT.Colors:GetHex(db.ColRace, 1, 1, 1)
    local label, color
    if sex == 2 then
        label, color = WT.L.GENDER_MALE, WT.Colors:GetHex(db.ColMale, 0, 0.44, 1)
    elseif sex == 3 then
        label, color = WT.L.GENDER_FEMALE, WT.Colors:GetHex(db.ColFemale, 1, 0.41, 0.7)
    else
        return ""
    end
    label = string_gsub(tostring(label), "[%(%)]", "")
    return bracketColor .. "(|r|c" .. color .. label .. "|r" .. bracketColor .. ")|r "
end

local function GetFactionIcon(faction)
    if not WT.DB.SocialWidget.ShowFaction then return "" end
    if faction == "Alliance" then return "|TInterface\\FriendsFrame\\PlusManz-Alliance:14:14:0:-1|t " end
    if faction == "Horde" then return "|TInterface\\FriendsFrame\\PlusManz-Horde:14:14:0:-1|t " end
    return "|TInterface\\COMMON\\Indicator-Gray:14:14:0:-1|t "
end

local function GetLocationString(location)
    local db = WT.DB.SocialWidget
    if not db.ShowLocation then return "" end
    local color = WT.Colors:GetHex(db.ColLocation, 0.66, 0.66, 0.66)
    if not location or location == "" then location = "---" end
    return "|c" .. color .. "- " .. location .. "|r "
end

local function GetRealmString(realm)
    local db = WT.DB.SocialWidget
    if not db.ShowRealm then return "" end
    if not realm or realm == "" then realm = "---" end
    local dashColor = WT.Colors:GetHex(db.ColLocation, 0.66, 0.66, 0.66)
    local labelColor = WT.Colors:GetHex(db.ColLevel, 1, 0.82, 0)
    local valueColor = WT.Colors:GetHex(db.ColRealm, 1, 1, 1)
    return "|c" .. dashColor .. "-|r |c" .. labelColor .. tostring(WT.L.TT_REALM) .. " [|r|c" .. valueColor
        .. realm .. "|r|c" .. labelColor .. "]|r "
end

local function GetStatusString(isAFK, isDND)
    local db = WT.DB.SocialWidget
    if not db.ShowStatus then return "" end
    if isDND then
        return "|c" .. WT.Colors:GetHex(db.ColDND, 1, 0.2, 0.2) .. tostring(WT.L.SW_TAG_DND) .. "|r "
    elseif isAFK then
        return "|c" .. WT.Colors:GetHex(db.ColAFK, 1, 0.82, 0) .. tostring(WT.L.SW_TAG_AFK) .. "|r "
    end
    return ""
end

local function GetNoteString(note)
    local db = WT.DB.SocialWidget
    if not db.ShowNote or not note or note == "" then return "" end
    local bracketColor = "|c" .. WT.Colors:GetHex(db.ColRace, 1, 1, 1)
    return bracketColor .. "(|r|c" .. WT.Colors:GetHex(db.ColNote, 0, 1, 0) .. note .. "|r" .. bracketColor .. ")|r"
end

local function GetGroupTag(guid)
    if not WT.DB.SocialWidget.MarkGroupMembers or not guid or not groupGUIDs[guid] then return "" end
    return COLOR_GROUP .. tostring(WT.L.SW_TAG_GROUP) .. "|r "
end

--- One tooltip line for a WoW character (guild member or friend).
local function BuildCharacterLine(coloredName, level, isAFK, isDND, faction, race, sex, location, realm, note, guid)
    return GetGroupTag(guid) .. GetLevelString(level) .. GetStatusString(isAFK, isDND) .. GetFactionIcon(faction)
        .. coloredName .. " " .. GetRaceString(race) .. GetGenderString(sex) .. GetLocationString(location)
        .. GetRealmString(realm) .. GetNoteString(note)
end

--- Creates a list entry. sortName/level/zone are used for sorting, tellTarget/isBNet for whispers.
local function NewEntry(list, text, sortName, level, zone, tellTarget, isBNet)
    list[#list + 1] = {
        text = text,
        sortName = string_lower(sortName or ""),
        level = level or 0,
        zone = string_lower(zone or ""),
        tellTarget = tellTarget,
        isBNet = isBNet,
    }
end

-- ----------------------------------------------------------------------------
-- Data collection
-- ----------------------------------------------------------------------------

local function CollectGroupGUIDs()
    wipe(groupGUIDs)
    if not WT.DB.SocialWidget.MarkGroupMembers or not IsInGroup() then return end
    local prefix, count = "party", GetNumSubgroupMembers()
    if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
    for i = 1, count do
        local guid = Unsecret(UnitGUID(prefix .. i))
        if guid then groupGUIDs[guid] = true end
    end
end

local function GetPlayerFaction()
    return Unsecret(UnitFactionGroup("player")) or "Alliance"
end

local function CollectGuild(playerFaction)
    wipe(guildEntries)
    wipe(mobileEntries)
    if not IsInGuild() or not GetNumGuildMembers or not GetGuildRosterInfo then return end

    local showMobile = WT.DB.SocialWidget.ShowMobile
    local numMembers = SafeNum((GetNumGuildMembers())) or 0
    for i = 1, numMembers do
        local fullName, _, _, level, _, zone, note, _, isOnline, status, classFile, _, _, isMobile, _, _, guid = GetGuildRosterInfo(i)
        fullName = Unsecret(fullName)
        local online = SafeBool(isOnline)
        local mobileOnly = showMobile and not online and SafeBool(isMobile)
        if fullName and (online or mobileOnly) then
            local name, realm = SplitName(fullName)
            guid = Unsecret(guid)
            local coloredName = "|c" .. (GetClassColorHex(Unsecret(classFile)) or COLOR_FALLBACK_CLASS) .. name .. "|r"
            level = SafeNum(level)
            if mobileOnly then
                local text = COLOR_MOBILE .. tostring(WT.L.SW_TAG_MOBILE) .. "|r " .. GetLevelString(level) .. coloredName
                    .. " " .. GetNoteString(Unsecret(note))
                NewEntry(mobileEntries, text, name, level, nil, fullName, false)
            else
                local _, _, race, englishRace, sex = WT.Utils:GetPlayerInfoByGUID(guid)
                local faction = (englishRace and WT.Utils.Units.RACE_TO_FACTION[englishRace]) or playerFaction
                status = SafeNum(status)
                zone = Unsecret(zone)
                local text = BuildCharacterLine(coloredName, level, status == STATUS_AFK, status == STATUS_DND, faction,
                    race, sex, zone, realm, Unsecret(note), guid)
                NewEntry(guildEntries, text, name, level, zone, fullName, false)
            end
        end
    end
end

local function CollectBattleNetFriends()
    if not BNGetNumFriends or not (C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return end

    local numFriends = SafeNum((BNGetNumFriends())) or 0
    for i = 1, numFriends do
        local account = C_BattleNet.GetFriendAccountInfo(i)
        local game = account and account.gameAccountInfo
        if account and game and SafeBool(game.isOnline) then
            local accountName = Unsecret(account.accountName) or ""
            local sortName = Unsecret(account.battleTag) or accountName
            local client = Unsecret(game.clientProgram)
            local isAFK = account.isAFK or game.isGameAFK
            local isDND = account.isDND or game.isGameBusy
            local note = Unsecret(account.note)
            local characterName = Unsecret(game.characterName) or ""
            local projectID = SafeNum(game.wowProjectID)

            if client == BNET_CLIENT_WOW and (not projectID or projectID == WOW_PROJECT_ID) then
                -- Same WoW version: full character details
                local guid = Unsecret(game.playerGuid)
                local _, guidClass, _, _, sex = WT.Utils:GetPlayerInfoByGUID(guid)
                local classFile = Unsecret(game["classFilename"]) or guidClass
                local classColor = GetClassColorHex(classFile) or COLOR_FALLBACK_BNET_CLASS
                local coloredName = COLOR_BNET_NAME .. accountName .. "|r"
                if characterName ~= "" then
                    coloredName = coloredName .. " (|c" .. classColor .. characterName .. "|r)"
                end
                local zone = Unsecret(game.areaName)
                local level = SafeNum(game.characterLevel)
                local text = BuildCharacterLine(coloredName, level, isAFK, isDND, Unsecret(game.factionName),
                    Unsecret(game.raceName), sex, zone, Unsecret(game.realmName), note, guid)
                NewEntry(wowFriendEntries, text, characterName ~= "" and characterName or sortName, level, zone,
                    accountName, true)
            elseif client == BNET_CLIENT_WOW then
                -- Another WoW version (e.g. Classic): level and realm are not available, Blizzard's
                -- friends list shows the rich presence text instead, so do the same
                local coloredName = COLOR_BNET_NAME .. accountName .. "|r"
                if characterName ~= "" then
                    coloredName = coloredName .. " (" .. COLOR_BNET_NAME .. characterName .. "|r)"
                end
                local presence = Unsecret(game.richPresence)
                local text = GetStatusString(isAFK, isDND) .. GetClientIcon(client) .. coloredName .. " "
                    .. GetLocationString(presence) .. GetNoteString(note)
                NewEntry(appFriendEntries, text, sortName, 0, presence, accountName, true)
            else
                local icon = GetClientIcon(client)
                local clientText = ""
                if icon == "" then
                    local clientName = (client and client ~= "") and client or tostring(WT.L.SW_CLIENT_APP)
                    clientText = " [" .. COLOR_CLIENT .. clientName .. "|r" .. COLOR_BNET_NAME .. "]"
                end
                local text = GetStatusString(isAFK, isDND) .. icon .. COLOR_BNET_NAME .. accountName .. clientText
                    .. "|r " .. GetNoteString(note)
                NewEntry(appFriendEntries, text, sortName, 0, nil, accountName, true)
            end
        end
    end
end

local function CollectCharacterFriends(playerFaction)
    if not (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex) then return end

    local numFriends = SafeNum(C_FriendList.GetNumFriends()) or 0
    for i = 1, numFriends do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and SafeBool(info.connected) then
            local fullName = Unsecret(info.name) or UNKNOWN
            local name, realm = SplitName(fullName)
            local guid = Unsecret(info.guid)
            local _, _, race, englishRace, sex = WT.Utils:GetPlayerInfoByGUID(guid)
            -- Cross-faction friends are possible, so derive the faction from the race when known
            local faction = (englishRace and WT.Utils.Units.RACE_TO_FACTION[englishRace]) or playerFaction
            local coloredName = "|c" .. (GetClassColorHex(Unsecret(info.className)) or COLOR_FALLBACK_CLASS) .. name .. "|r"
            local level = SafeNum(info.level)
            local zone = Unsecret(info.area)
            local text = BuildCharacterLine(coloredName, level, info.afk, info.dnd, faction, race, sex, zone, realm,
                Unsecret(info.notes), guid)
            NewEntry(wowFriendEntries, text, name, level, zone, fullName, false)
        end
    end
end

-- ----------------------------------------------------------------------------
-- Sorting & output
-- ----------------------------------------------------------------------------

local function SortByName(a, b)
    return a.sortName < b.sortName
end

local function SortByLevel(a, b)
    if a.level ~= b.level then return a.level > b.level end
    return a.sortName < b.sortName
end

local function SortByZone(a, b)
    if a.zone ~= b.zone then return a.zone < b.zone end
    return a.sortName < b.sortName
end

local SORTERS = { NAME = SortByName, LEVEL = SortByLevel, ZONE = SortByZone }

local function AddSection(tooltip, header, entries, r, g, b, interactive)
    if #entries == 0 then return false end
    local sorter = SORTERS[WT.DB.SocialWidget.SortBy]
    if sorter then table_sort(entries, sorter) end

    tooltip:AddLine(" ")
    tooltip:AddLine(tostring(header) .. #entries, r, g, b)
    tooltip:AddLine(DIVIDER)

    local limit = SafeNum(WT.DB.SocialWidget.MaxEntries) or 0
    local shown = (limit > 0 and limit < #entries) and limit or #entries
    for i = 1, shown do
        tooltip:AddLine(entries[i].text, 1, 1, 1)
        if interactive then lineEntries[tooltip:NumLines()] = entries[i] end
    end
    if shown < #entries then
        tooltip:AddLine(string_format(tostring(WT.L.SW_MORE_ENTRIES), #entries - shown), 0.5, 0.5, 0.5)
    end
    return true
end

-- ----------------------------------------------------------------------------
-- Click to whisper
-- ----------------------------------------------------------------------------

local function Whisper(entry)
    if not entry or not entry.tellTarget or entry.tellTarget == "" then return end
    local chatUtil = _G["ChatFrameUtil"]
    if entry.isBNet then
        if chatUtil and chatUtil.SendBNetTell then
            chatUtil.SendBNetTell(entry.tellTarget)
        elseif _G["ChatFrame_SendBNetTell"] then
            _G["ChatFrame_SendBNetTell"](entry.tellTarget)
        end
    elseif chatUtil and chatUtil.SendTell then
        chatUtil.SendTell(entry.tellTarget)
    elseif _G["ChatFrame_SendTell"] then
        _G["ChatFrame_SendTell"](entry.tellTarget)
    end
end

local function GetRowButton(tooltip, index)
    local row = rowButtons[index]
    if not row then
        row = CreateFrame("Button", nil, tooltip)
        row:RegisterForClicks("LeftButtonUp")
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.08)
        row:SetScript("OnClick", function(self)
            Whisper(self.entry)
            tooltip:Hide()
        end)
        rowButtons[index] = row
    end
    row:SetFrameLevel(tooltip:GetFrameLevel() + 5)
    return row
end

local function LayoutRowButtons(tooltip)
    local used = 0
    local tooltipName = tooltip:GetName()
    for lineIndex, entry in pairs(lineEntries) do
        local line = _G[tooltipName .. "TextLeft" .. lineIndex]
        if line then
            used = used + 1
            local row = GetRowButton(tooltip, used)
            row.entry = entry
            row:ClearAllPoints()
            row:SetPoint("LEFT", tooltip, "LEFT", 4, 0)
            row:SetPoint("RIGHT", tooltip, "RIGHT", -4, 0)
            row:SetPoint("TOP", line, "TOP", 0, 1)
            row:SetPoint("BOTTOM", line, "BOTTOM", 0, -1)
            row:Show()
        end
    end
    for i = used + 1, #rowButtons do
        rowButtons[i]:Hide()
        rowButtons[i].entry = nil
    end
end

local function HideRowButtons()
    for _, row in ipairs(rowButtons) do
        row:Hide()
        row.entry = nil
    end
end

-- Keeps an interactive tooltip open while the mouse is over the widget or the tooltip
local function CheckHover()
    local tooltip = _G["WTSocialTooltip"]
    local owner = tooltip and tooltip:GetOwner()
    if not tooltip or not tooltip:IsShown() or not owner then
        Module:UnregisterOnUpdate(CheckHover)
        return
    end
    if not owner:IsMouseOver() and not tooltip:IsMouseOver() then
        tooltip:Hide()
        Module:UnregisterOnUpdate(CheckHover)
    end
end

--- Called by the widget's OnLeave. Interactive tooltips close once the mouse leaves both frames.
function Module:ReleaseTooltip(owner)
    local tooltip = _G["WTSocialTooltip"]
    if not tooltip or tooltip:GetOwner() ~= owner then return end
    if WT.DB.SocialWidget.ClickToWhisper and tooltip:IsShown() then
        self:RegisterOnUpdate(CheckHover, HOVER_CHECK_INTERVAL)
    else
        tooltip:Hide()
    end
end

-- ----------------------------------------------------------------------------
-- Tooltip
-- ----------------------------------------------------------------------------

local function IsTooltipModifierDown()
    local modifier = WT.DB.SocialWidget.TooltipModifier or "NONE"
    if modifier == "SHIFT" then return IsShiftKeyDown() end
    if modifier == "CTRL" then return IsControlKeyDown() end
    if modifier == "ALT" then return IsAltKeyDown() end
    return true
end

local function AnchorTooltip(tooltip, owner)
    -- Follow the cursor anchor of the Tooltip module when that module is in use
    local ttDB = WT.DB.Tooltip
    if WT.DB.SocialWidget.ClickToWhisper then
        -- A tooltip that follows the cursor could never be reached with the mouse
        ttDB = nil
    end
    if ttDB and WT.DB.Modules.Tooltip and ttDB.CursorAnchor then
        local anchor = (ttDB.CursorAnchorType == "ANCHOR_CURSOR_RIGHT") and "ANCHOR_CURSOR_RIGHT" or "ANCHOR_CURSOR"
        tooltip:SetOwner(owner, anchor, ttDB.CursorAnchorX or 0, ttDB.CursorAnchorY or 0)
    elseif (owner:GetBottom() or 0) < (GetScreenHeight() / 2) then
        tooltip:SetOwner(owner, "ANCHOR_TOP")
    else
        tooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    end
end

local function AddEmptyHint(tooltip)
    local db = WT.DB.SocialWidget
    local key
    if db.ShowGuild and db.ShowBNet then
        key = IsInGuild() and "SW_TT_EMPTY_BOTH" or "SW_TT_EMPTY_BOTH_NOGUILD"
    elseif db.ShowGuild then
        key = IsInGuild() and "SW_TT_EMPTY_GUILD" or "SW_TT_NO_GUILD"
    elseif db.ShowBNet then
        key = "SW_TT_EMPTY_FRIENDS"
    end
    if key then
        tooltip:AddLine(" ")
        tooltip:AddLine(tostring(WT.L[key]), 0.5, 0.5, 0.5)
    end
end

function Module:ShowDetailedTooltip(owner)
    local tooltip = _G["WTSocialTooltip"]
    if not tooltip then return end
    local db = WT.DB.SocialWidget

    if (db.HideTooltipCombat and InCombatLockdown()) or not IsTooltipModifierDown() then
        if tooltip:GetOwner() == owner then tooltip:Hide() end
        return
    end

    local interactive = db.ClickToWhisper and true or false
    wipe(lineEntries)

    AnchorTooltip(tooltip, owner)
    tooltip:ClearLines()
    tooltip:AddLine("|TInterface\\AddOns\\" .. addonName .. "\\Media\\Graphics\\Logo.tga:16:16:0:0|t "
        .. tostring(WT.L.SW_TITLE), WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B)

    local playerFaction = GetPlayerFaction()
    local hasContent = false
    CollectGroupGUIDs()

    if db.ShowGuild then
        CollectGuild(playerFaction)
        hasContent = AddSection(tooltip, WT.L.SW_GUILD_ONLINE, guildEntries, 0, 1, 0, interactive) or hasContent
        hasContent = AddSection(tooltip, WT.L.SW_GUILD_MOBILE, mobileEntries, 0.6, 0.6, 0.6, interactive) or hasContent
    end

    if db.ShowBNet then
        wipe(wowFriendEntries)
        wipe(appFriendEntries)
        CollectBattleNetFriends()
        CollectCharacterFriends(playerFaction)
        hasContent = AddSection(tooltip, WT.L.SW_FRIENDS_ONLINE, wowFriendEntries,
            WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, interactive) or hasContent
        hasContent = AddSection(tooltip, WT.L.SW_BNET_ONLINE, appFriendEntries, 0.6, 0.8, 1, interactive) or hasContent
    end

    if not hasContent then
        AddEmptyHint(tooltip)
    elseif interactive then
        tooltip:AddLine(" ")
        tooltip:AddLine(tostring(WT.L.SW_TT_HINT_WHISPER), 0.5, 0.5, 0.5)
    end

    tooltip:EnableMouse(interactive)
    tooltip:Show()
    if interactive then
        LayoutRowButtons(tooltip)
    else
        HideRowButtons()
    end
end
