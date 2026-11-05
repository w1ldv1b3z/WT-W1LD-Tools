local _, WT = ...
local Module = WT.Modules.Chat

Module.playerLevelCache = Module.playerLevelCache or {}
Module.guildMemberCache = Module.guildMemberCache or {}
Module.rosterCache = Module.rosterCache or {}
Module.friendCache = Module.friendCache or {}

local Unsecret = WT.Utils.Safety.Unsecret
local SafeNum = WT.Utils.Safety.SafeNum

local UnitIsPlayer = UnitIsPlayer
local UnitName = UnitName
local UnitLevel = UnitLevel
local GetNumGroupMembers = GetNumGroupMembers
local IsInGuild = IsInGuild
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local wipe = table.wipe or wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local Ambiguate = Ambiguate or function(name, context) return name and ((context == "short" or context == "guild") and string.match(name, "^([^%-]+)") or name) or "" end
local GetNumGuildMembers = GetNumGuildMembers or (C_GuildInfo and C_GuildInfo.GetNumGuildMembers) or function() return 0 end
local GetGuildRosterInfo = GetGuildRosterInfo or (C_GuildInfo and C_GuildInfo.GetGuildRosterInfo) or function() return nil end

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


function Module:CacheUnitLevel(unit)
    if not WT.DB.Chat.ShowPlayerLevels then return end
    if not unit then return end
    
    if UnitIsPlayer(unit) then
        local n, s = UnitName(unit)
        local name = nil
        if n then
            local nSafe = Unsecret(n)
            local sSafe = Unsecret(s)
            if nSafe then
                if sSafe and sSafe ~= "" then
                    name = nSafe .. "-" .. sSafe
                else
                    name = nSafe
                end
            end
        end
        local level = SafeNum(UnitLevel(unit)) or 0
        if name and level > 0 then
            self.playerLevelCache[name] = level
            local shortName = strsplit("-", name)
            if shortName then
                self.playerLevelCache[shortName] = level
            end
        end
    end
end

function Module:UpdatePlayerLevelCache()
    if not WT.DB.Chat.ShowPlayerLevels then return end
    
    self:CacheUnitLevel("player")
    
    if IsInGuild() then
        local numGuild = SafeNum(GetNumGuildMembers()) or 0
        for i = 1, numGuild do
            local name, _, _, rawLevel = GetGuildRosterInfo(i)
            local uName = Unsecret(name)
            local level = SafeNum(rawLevel) or 0
            if uName and level > 0 then
                self.playerLevelCache[uName] = level
                local shortName = strsplit("-", uName)
                if shortName then self.playerLevelCache[shortName] = level end
            end
        end
    end
    
    if IsInGroup() then
        local numGroup = SafeNum(GetNumGroupMembers()) or 0
        for i = 1, numGroup do
            local unit = IsInRaid() and "raid"..i or "party"..i
            self:CacheUnitLevel(unit)
        end
    end
end

function Module:BuildRosterCache()
    wipe(self.rosterCache)
    wipe(self.guildMemberCache)
    if self.friendCache then wipe(self.friendCache) end
    
    -- For older clients, force offline members to ensure we cache everyone
    local prevShowOffline
    if SetGuildRosterShowOffline then
        prevShowOffline = GetGuildRosterShowOffline()
        SetGuildRosterShowOffline(true)
    end
    
    local numGuild = SafeNum(GetNumGuildMembers()) or 0
    for i = 1, numGuild do
        local name, _, _, _, _, _, note, _, _, _, classFileName = GetGuildRosterInfo(i)
        local uName = Unsecret(name)
        local uClass = Unsecret(classFileName)
        if uName then
            local ambigName = Ambiguate(uName, "guild")
            self.guildMemberCache[ambigName] = uClass or "UNKNOWN"
            self.rosterCache[ambigName] = (note and strtrim(note) ~= "") and Unsecret(strtrim(note)) or -1
            
            local shortName = strsplit("-", uName)
            if shortName and shortName ~= ambigName then
                self.guildMemberCache[shortName] = uClass or "UNKNOWN"
                self.rosterCache[shortName] = (note and strtrim(note) ~= "") and Unsecret(strtrim(note)) or -1
            end
        end
    end
    
    if SetGuildRosterShowOffline and prevShowOffline ~= nil then
        SetGuildRosterShowOffline(prevShowOffline)
    end
end

WT.Core.Events:Register("PLAYER_ENTERING_WORLD", function()
    if Module.playerLevelCache then wipe(Module.playerLevelCache) end
    if Module.UpdatePlayerLevelCache then Module:UpdatePlayerLevelCache() end
end)