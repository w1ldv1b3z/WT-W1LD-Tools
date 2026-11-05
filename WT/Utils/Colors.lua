local _, WT = ...

WT.Colors = {
    PRIMARY = "|cFF00FFFF",
    
    -- UI Colors (R, G, B, A)
    PRIMARY_R = 0, PRIMARY_G = 1, PRIMARY_B = 1,
    SUBTEXT_R = 0.66, SUBTEXT_G = 0.66, SUBTEXT_B = 0.66,
    BG_R = 0, BG_G = 0, BG_B = 0, BG_A = 0.4,
    STD_BG_R = 0, STD_BG_G = 0, STD_BG_B = 0, STD_BG_A = 0.8,
    
    -- WoW Class Colors
    Classes = {
        DEATHKNIGHT = "|cFFC41E3A",
        DEMONHUNTER = "|cFFA330C9",
        DRUID       = "|cFFFF7D0A",
        EVOKER      = "|cFF33937F",
        HUNTER      = "|cFFABD473",
        MAGE        = "|cFF3FC7EB",
        MONK        = "|cFF00FF96",
        PALADIN     = "|cFFF48CBA",
        PRIEST      = "|cFFFFFFFF",
        ROGUE       = "|cFFFFF468",
        SHAMAN      = "|cFF0070DD",
        WARLOCK     = "|cFF8788EE",
        WARRIOR     = "|cFFC69B6D",
    }
}

local SafeNum = WT.Utils.Safety.SafeNum

local hexCache = setmetatable({}, { __mode = "k" })
local fallbackHexCache = {}

-- Globally accessible function to efficiently fetch a hex string from an RGBA table
function WT.Colors:GetHex(colorTable, defR, defG, defB)
    if colorTable == nil then
        local fbKey = (defR or 1) .. "_" .. (defG or 1) .. "_" .. (defB or 1)
        if fallbackHexCache[fbKey] then return fallbackHexCache[fbKey] end
        local hex = string.format("ff%02x%02x%02x", math.floor((defR or 1) * 255 + 0.5), math.floor((defG or 1) * 255 + 0.5), math.floor((defB or 1) * 255 + 0.5))
        fallbackHexCache[fbKey] = hex
        return hex
    end
    if hexCache[colorTable] then return hexCache[colorTable] end
    
    if type(colorTable) == "string" then
        local hex = string.gsub(colorTable, "^#", "")
        if #hex < 8 then hex = "ff" .. hex end
        hex = string.lower(hex)
        hexCache[colorTable] = hex
        return hex
    end
    
    local r = SafeNum((type(colorTable) == "table" and colorTable.r) or defR or 1)
    local g = SafeNum((type(colorTable) == "table" and colorTable.g) or defG or 1)
    local b = SafeNum((type(colorTable) == "table" and colorTable.b) or defB or 1)
    
    local hex = string.format("ff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
    
    if type(colorTable) == "table" then hexCache[colorTable] = hex end
    
    return hex
end

-- Globally accessible function to safely fetch R, G, B values from an RGBA table
function WT.Colors:GetRGB(colorTable, defR, defG, defB)
    if type(colorTable) == "string" then
        return self:HexToRGB(colorTable)
    end
    if type(colorTable) == "table" then
        return colorTable.r or defR or 1, colorTable.g or defG or 1, colorTable.b or defB or 1
    end
    return defR or 1, defG or 1, defB or 1
end

-- Globally accessible function to convert a hex string to R, G, B values
function WT.Colors:HexToRGB(hex)
    if type(hex) ~= "string" then return 1, 1, 1 end
    hex = string.gsub(hex, "^#", "")
    if #hex == 8 then
        local r = tonumber(string.sub(hex, 3, 4), 16) or 255
        local g = tonumber(string.sub(hex, 5, 6), 16) or 255
        local b = tonumber(string.sub(hex, 7, 8), 16) or 255
        return r/255, g/255, b/255
    elseif #hex == 6 then
        local r = tonumber(string.sub(hex, 1, 2), 16) or 255
        local g = tonumber(string.sub(hex, 3, 4), 16) or 255
        local b = tonumber(string.sub(hex, 5, 6), 16) or 255
        return r/255, g/255, b/255
    end
    return 1, 1, 1
end