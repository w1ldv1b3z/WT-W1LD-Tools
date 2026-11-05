local _, WT = ...

WT.Modules.UpdateCheck = {}
local Module = WT.Modules.UpdateCheck

local PREFIX = "WT_VerCheck"
local sessionNotified = false

-- Version parse function: converts "2.5.2" or "v.3.0.0-dev" to comparable numbers
local function ParseVersion(vStr)
    if not vStr then return 0, 0, 0, false end

    local isDev = false
    if string.find(string.lower(vStr), "%-dev") then
        isDev = true
    end

    local major, minor, patch = string.match(vStr, "(%d+)%.(%d+)%.(%d+)")
    major = tonumber(major) or 0
    minor = tonumber(minor) or 0
    patch = tonumber(patch) or 0

    return major, minor, patch, isDev
end

-- Compare two versions. Returns true if `received` is strictly greater than `current`.
local function IsNewerVersion(currentStr, receivedStr)
    local cMaj, cMin, cPat, cIsDev = ParseVersion(currentStr)
    local rMaj, rMin, rPat, rIsDev = ParseVersion(receivedStr)

    -- Filter out dev versions as requested by the user
    if rIsDev then return false end

    if rMaj > cMaj then return true end
    if rMaj == cMaj and rMin > cMin then return true end
    if rMaj == cMaj and rMin == cMin and rPat > cPat then return true end

    -- If versions match but current is dev and received is stable, recommend stable
    if rMaj == cMaj and rMin == cMin and rPat == cPat then
        if cIsDev and not rIsDev then return true end
    end

    return false
end

local function OnAddonMessage(event, prefix, text, channel, sender)
    if prefix ~= PREFIX then return end

    local myName = UnitName("player")
    local myRealm = GetRealmName()

    -- Ignore our own messages
    if sender == myName .. "-" .. myRealm or sender == myName then return end

    -- Prevent spamming the user multiple times per session
    if sessionNotified then return end

    local currentVersion = WT.Version

    if IsNewerVersion(currentVersion, text) then
        sessionNotified = true
        if WT.Utils and WT.Utils.Logger then
            local msg = (WT.L.MSG_UPDATE_AVAILABLE) ..
                "|cFF00FF00" .. text .. "|r"
            WT.Utils.Logger:Print("|cFF00FFFF" .. WT.L.LBL_UPDATE .. ":|r " .. msg)
        end
    end
end

local function BroadcastVersion()
    local currentVersion = WT.Version

    if IsInGuild() then
        C_ChatInfo.SendAddonMessage(PREFIX, currentVersion, "GUILD")
    end

    if IsInGroup() then
        local channel = IsInRaid() and "RAID" or "PARTY"
        C_ChatInfo.SendAddonMessage(PREFIX, currentVersion, channel)
    end
end

local function OnLogin()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    -- Broadcast immediately (with slight delay to allow login to settle)
    C_Timer.After(5, BroadcastVersion)
end

function Module:Initialize()
    WT.Core.Events:Register("CHAT_MSG_ADDON", OnAddonMessage)
    WT.Core.Events:Register("PLAYER_ENTERING_WORLD", OnLogin)
    WT.Core.Events:Register("GROUP_ROSTER_UPDATE", BroadcastVersion)
end

WT.Core.Events:Register("PLAYER_LOGIN", function()
    Module:Initialize()
end)
