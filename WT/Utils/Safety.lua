local _, WT = ...

WT.Utils = WT.Utils or {}
WT.Utils.Safety = {}

function WT.Utils.Safety.IsSecret(v)
    if not v then return false end
    if issecretvalue and issecretvalue(v) then return true end
    if canaccessvalue and not canaccessvalue(v) then return true end
    if type(v) == "string" then
        local ok = pcall(string.lower, v)
        return not ok
    end
    return false
end

function WT.Utils.Safety.Unsecret(str)
    if issecretvalue and issecretvalue(str) then return nil end
    if canaccessvalue and not canaccessvalue(str) then return nil end
    if scrub then
        str = scrub(str)
    end
    if type(str) == "string" then
        local ok1 = pcall(string.lower, str)
        local ok2 = pcall(function() return str == "" end)
        local ok3 = pcall(function() return str ~= "wt_secret_test" end)
        if ok1 and ok2 and ok3 then return str end
        return nil
    end
    if type(str) == "number" then
        local ok1 = pcall(tostring, str)
        local ok2 = pcall(function() return str == 0 end)
        if ok1 and ok2 then return str end
        return nil
    end
    return nil
end

function WT.Utils.Safety.SafeNum(v)
    if issecretvalue and issecretvalue(v) then return nil end
    if canaccessvalue and not canaccessvalue(v) then return nil end
    if scrub then
        v = scrub(v)
    end
    if type(v) == "number" then
        local ok1 = pcall(tostring, v)
        local ok2 = pcall(function() return v == 0 end)
        if ok1 and ok2 then return v end
        return nil
    end
    if type(v) == "string" then
        local ok1 = pcall(string.match, v, "")
        local ok2 = pcall(function() return v == "" end)
        if ok1 and ok2 then return tonumber(v) end
        return nil
    end
    return nil
end

function WT.Utils.Safety.IsSafeBoolean(v)
    if issecretvalue and issecretvalue(v) then return false end
    if canaccessvalue and not canaccessvalue(v) then return false end
    if scrub then
        v = scrub(v)
    end
    if type(v) == "boolean" then
        local ok = pcall(function() return v == true end)
        if ok then return v end
    end
    return false
end

local KNOWN_TOOLTIPS = {
    "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
    "GameSmallTooltip", "NamePlateTooltip", "QuickKeybindTooltip",
    "BattlePetTooltip", "PetBattlePrimaryUnitTooltip", "PetBattlePrimaryAbilityTooltip",
    "FloatingBattlePetTooltip", "FloatingGarrisonPetTooltip", "FloatingPetBattleAbilityTooltip",
    "ReputationParagonTooltip", "LibDBIconTooltip", "DatatextTooltip", "WTSocialTooltip", "WTCustomTooltip"
}
function WT.Utils.Safety.GetSafeTooltipName(tooltip)
    if not tooltip then return nil end
    for i = 1, #KNOWN_TOOLTIPS do
        if _G[KNOWN_TOOLTIPS[i]] == tooltip then return KNOWN_TOOLTIPS[i] end
    end
    if not tooltip:IsForbidden() and type(tooltip.GetName) == "function" then
        local ok, res = pcall(tooltip.GetName, tooltip)
        if ok and type(res) == "string" then return WT.Utils.Safety.Unsecret(res) end
    end
    return nil
end

function WT.Utils.Safety.SafeBool(v)
    if issecretvalue and issecretvalue(v) then return false end
    if canaccessvalue and not canaccessvalue(v) then return false end
    if scrub then
        v = scrub(v)
    end
    if type(v) == "boolean" then
        local ok = pcall(function() return v == true end)
        if ok then return v end
    end
    return false
end