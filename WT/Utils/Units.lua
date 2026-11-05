local _, WT = ...

WT.Utils = WT.Utils or {}
WT.Utils.Units = {}

WT.Utils.Units.RACE_TO_FACTION = {
    ["Human"] = "Alliance", ["Dwarf"] = "Alliance", ["NightElf"] = "Alliance", ["Gnome"] = "Alliance", ["Draenei"] = "Alliance", ["Worgen"] = "Alliance",
    ["LightforgedDraenei"] = "Alliance", ["VoidElf"] = "Alliance", ["DarkIronDwarf"] = "Alliance", ["KulTiran"] = "Alliance", ["Mechagnome"] = "Alliance",
    ["PandarenTushui"] = "Alliance", ["DracthyrAlliance"] = "Alliance", ["EarthenAlliance"] = "Alliance", ["EarthenDwarfAlliance"] = "Alliance",
    ["Orc"] = "Horde", ["Scourge"] = "Horde", ["Tauren"] = "Horde", ["Troll"] = "Horde", ["BloodElf"] = "Horde", ["Goblin"] = "Horde",
    ["Nightborne"] = "Horde", ["HighmountainTauren"] = "Horde", ["MagharOrc"] = "Horde", ["ZandalariTroll"] = "Horde", ["Vulpera"] = "Horde",
    ["PandarenHuojin"] = "Horde", ["DracthyrHorde"] = "Horde", ["EarthenHorde"] = "Horde", ["EarthenDwarfHorde"] = "Horde"
}

local SafeNum = WT.Utils.Safety.SafeNum
local Unsecret = WT.Utils.Safety.Unsecret
local IsSafeBoolean = WT.Utils.Safety.IsSafeBoolean

local function CallUnitIsAFK(u) return UnitIsAFK(u) end
local function CallUnitIsDND(u) return UnitIsDND(u) end

function WT.Utils.Units.SafeUnitExists(u) 
    if not u then return false end
    local ok, res = pcall(UnitExists, u)
    if ok then
        local ok2, safeRes = pcall(IsSafeBoolean, res)
        if ok2 and safeRes then return true end
    end
    return false 
end

function WT.Utils.Units.SafeUnitGUID(u) 
    if not u then return nil end
    local ok, guid = pcall(UnitGUID, u)
    return ok and Unsecret(guid) or nil
end

function WT.Utils.Units.SafeUnitIsPlayer(u) 
    if not u then return false end
    local ok, res = pcall(UnitIsPlayer, u)
    if ok then
        local ok2, safeRes = pcall(IsSafeBoolean, res)
        if ok2 and safeRes then return true end
    end
    
    local guid = WT.Utils.Units.SafeUnitGUID(u)
    if guid and type(guid) == "string" and string.match(guid, "^Player%-") then
        return true
    end
    return false
end

function WT.Utils.Units.SafeUnitIsUnit(u1, u2) 
    if not u1 or not u2 then return false end
    local g1 = WT.Utils.Units.SafeUnitGUID(u1)
    local g2 = WT.Utils.Units.SafeUnitGUID(u2)
    if not g1 or not g2 then return false end
    local ok, res = pcall(function() return g1 == g2 end)
    return ok and res
end

function WT.Utils.Units.SafeUnitIsAFK(u) 
    if not u then return false end
    local ok, res = pcall(CallUnitIsAFK, u)
    if ok then
        local ok2, safeRes = pcall(IsSafeBoolean, res)
        if ok2 and safeRes then return true end
    end
    return false 
end

function WT.Utils.Units.SafeUnitIsDND(u) 
    if not u then return false end
    local ok, res = pcall(CallUnitIsDND, u)
    if ok then
        local ok2, safeRes = pcall(IsSafeBoolean, res)
        if ok2 and safeRes then return true end
    end
    return false 
end

function WT.Utils.Units.SafeCanInspect(u) 
    if not u then return false end
    local ok, res = pcall(CanInspect, u)
    if ok then
        local ok2, safeRes = pcall(IsSafeBoolean, res)
        if ok2 and safeRes then return true end
    end
    return false 
end

function WT.Utils.Units.SafeUnitName(u) 
    if not u then return nil, nil end
    local ok, name, realm = pcall(UnitName, u)
    return (ok and Unsecret(name) or nil), (ok and Unsecret(realm) or nil)
end

function WT.Utils.Units.SafeUnitClass(u) 
    if not u then return nil, nil end
    local ok, loc, eng = pcall(UnitClass, u)
    if ok and loc and eng then
        local uEng = Unsecret(eng)
        return Unsecret(loc), (type(uEng) == "string") and string.upper(uEng) or nil
    end
    
    local guid = WT.Utils.Units.SafeUnitGUID(u)
    if guid and type(guid) == "string" and string.match(guid, "^Player%-") then
        local loc2, eng2 = WT.Utils:GetPlayerInfoByGUID(guid)
        if loc2 or eng2 then
            return loc2, eng2
        end
    end
    return nil, nil
end

function WT.Utils.Units.SafeUnitLevel(u) 
    if not u then return nil end
    local ok, res = pcall(UnitLevel, u)
    return ok and SafeNum(res) or nil 
end

function WT.Utils.Units.SafeUnitSex(u) 
    if not u then return nil end
    local ok, res = pcall(UnitSex, u)
    if ok then
        local safeRes = SafeNum(res)
        if safeRes then return safeRes end
    end
    
    local guid = WT.Utils.Units.SafeUnitGUID(u)
    if guid and type(guid) == "string" and string.match(guid, "^Player%-") then
        local _, _, _, _, sex2 = WT.Utils:GetPlayerInfoByGUID(guid)
        if sex2 then return sex2 end
    end
    return nil 
end

function WT.Utils.Units.SafeUnitFactionGroup(u) 
    if not u then return nil, nil end
    local ok, eng, loc = pcall(UnitFactionGroup, u)
    return (ok and Unsecret(eng) or nil), (ok and Unsecret(loc) or nil) 
end

function WT.Utils.Units.SafeUnitRace(u) 
    if not u then return nil, nil end
    local ok, loc, eng = pcall(UnitRace, u)
    if ok and loc and eng then return Unsecret(loc), Unsecret(eng) end
    
    local guid = WT.Utils.Units.SafeUnitGUID(u)
    if guid and type(guid) == "string" and string.match(guid, "^Player%-") then
        local _, _, loc2, eng2 = WT.Utils:GetPlayerInfoByGUID(guid)
        if loc2 or eng2 then return loc2, eng2 end
    end
    return nil, nil 
end

function WT.Utils.Units.SafeGetGuildInfo(u) 
    if not u then return nil, nil, nil, nil end
    if u and type(u) == "string" and string.match(u, "^nameplate") then return nil, nil, nil, nil end
    local ok, gName, gRank, _, gRealm = pcall(GetGuildInfo, u)
    if ok then return Unsecret(gName), Unsecret(gRank), nil, Unsecret(gRealm) end
    return nil, nil, nil, nil
end

function WT.Utils.Units.SafeUnitIsEnemy(u1, u2) 
    if not u1 or not u2 then return false end
    local ok, res = pcall(UnitIsEnemy, u1, u2)
    if ok then
        local ok2 = pcall(IsSafeBoolean, res)
        return ok2 and res or false
    end
    return false
end

function WT.Utils.Units.SafeUnitCanAttack(u1, u2) 
    if not u1 or not u2 then return false end
    local ok, res = pcall(UnitCanAttack, u1, u2)
    if ok then
        local ok2 = pcall(IsSafeBoolean, res)
        return ok2 and res or false
    end
    return false
end

function WT.Utils.Units.SafeUnitClassification(u) 
    if not u then return "normal" end
    local ok, res = pcall(UnitClassification, u)
    return ok and Unsecret(res) or "normal" 
end

function WT.Utils.Units.SafeUnitAffectingCombat(u) 
    if not u then return false end
    local ok, res = pcall(UnitAffectingCombat, u)
    if ok then
        local ok2 = pcall(IsSafeBoolean, res)
        return ok2 and res or false
    end
    return false
end

function WT.Utils.Units.SafeUnitPowerType(u) 
    local ok, res = pcall(UnitPowerType, u)
    return ok and SafeNum(res) or -1 
end