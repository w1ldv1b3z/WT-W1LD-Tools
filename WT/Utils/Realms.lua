local addonName, WT = ...
WT.Utils.Realms = {}

-- Path to the flag texture (must be in the addon folder)
local FLAG_TEXTURE = "Interface\\AddOns\\" .. addonName .. "\\Media\\Graphics\\Flags.tga"

-- Texture coordinates for a 4x4 grid (left, right, top, bottom)
local flagCoords = {
-- Row 1: EU Core
    ["EN"] = { 0.00, 0.25, 0.00, 0.25 },
    ["DE"] = { 0.25, 0.50, 0.00, 0.25 },
    ["FR"] = { 0.50, 0.75, 0.00, 0.25 },
    ["RU"] = { 0.75, 1.00, 0.00, 0.25 },
    -- Row 2: EU Extra & Fallback
    ["ES"] = { 0.00, 0.25, 0.25, 0.50 },
    ["IT"] = { 0.25, 0.50, 0.25, 0.50 },
    ["PT"] = { 0.50, 0.75, 0.25, 0.50 },
    ["EU"] = { 0.75, 1.00, 0.25, 0.50 },
    -- Row 3: Americas & Oceania
    ["US"] = { 0.00, 0.25, 0.50, 0.75 },
    ["BR"] = { 0.25, 0.50, 0.50, 0.75 },
    ["MX"] = { 0.50, 0.75, 0.50, 0.75 },
    ["AU"] = { 0.75, 1.00, 0.50, 0.75 },
    -- Row 4: Asia & Global
    ["KR"] = { 0.00, 0.25, 0.75, 1.00 },
    ["TW"] = { 0.25, 0.50, 0.75, 1.00 },
    ["CN"] = { 0.50, 0.75, 0.75, 1.00 },
    ["UN"] = { 0.75, 1.00, 0.75, 1.00 },
}

-- Determine the current region for fallback flags
local currentRegion = GetCurrentRegion() or 3
local fallbackFlag = "UN"

if currentRegion == 1 then fallbackFlag = "US"
elseif currentRegion == 2 then fallbackFlag = "KR"
elseif currentRegion == 3 then fallbackFlag = "EU"
elseif currentRegion == 4 then fallbackFlag = "TW"
elseif currentRegion == 5 then fallbackFlag = "CN"
end

local Unsecret = WT.Utils.Safety.Unsecret

local isDE = (GetLocale() == "deDE")
local countryNames = {
    ["DE"] = isDE and "Deutschland" or "Germany",
    ["EN"] = isDE and "Großbritannien" or "United Kingdom",
    ["US"] = isDE and "USA" or "United States",
    ["FR"] = isDE and "Frankreich" or "France",
    ["RU"] = isDE and "Russland" or "Russia",
    ["ES"] = isDE and "Spanien" or "Spain",
    ["IT"] = isDE and "Italien" or "Italy",
    ["PT"] = isDE and "Portugal" or "Portugal",
    ["BR"] = isDE and "Brasilien" or "Brazil",
    ["MX"] = isDE and "Mexiko" or "Mexico",
    ["KR"] = isDE and "Südkorea" or "South Korea",
    ["TW"] = isDE and "Taiwan" or "Taiwan",
    ["CN"] = isDE and "China" or "China",
    ["EU"] = isDE and "Europa" or "Europe",
    ["UN"] = isDE and "Unbekannt" or "Unknown",
    ["AU"] = isDE and "Ozeanien" or "Oceania"
}

local realmToRegion = {}

if currentRegion == 3 then
    -- EUROPEAN REGION (EU)
    realmToRegion = {
        -- German (DE)
        ["aegwynn"] = "DE", ["alexstrasza"] = "DE", ["alleria"] = "DE", ["amanthul"] = "DE", 
        ["ambossar"] = "DE", ["antonidas"] = "DE", ["anubarak"] = "DE", ["area52"] = "DE", 
        ["arthas"] = "DE", ["arygos"] = "DE", ["azshara"] = "DE", ["baelgun"] = "DE", 
        ["blackhand"] = "DE", ["blackmoore"] = "DE", ["blackrock"] = "DE", ["blutkessel"] = "DE", 
        ["dalvengyr"] = "DE", ["daskonsortium"] = "DE", ["konsortium"] = "DE", ["dassyndikat"] = "DE", 
        ["syndikat"] = "DE", ["derabyssischerat"] = "DE", ["abyssischerat"] = "DE", ["dermithrilorden"] = "DE", 
        ["mithrilorden"] = "DE", ["derratvondalaran"] = "DE", ["ratvondalaran"] = "DE", ["destromath"] = "DE", 
        ["dethecus"] = "DE", ["diealdor"] = "DE", ["aldor"] = "DE", ["diearguswacht"] = "DE", 
        ["arguswacht"] = "DE", ["dieewigewacht"] = "DE", ["ewigewacht"] = "DE", ["dienachtwache"] = "DE", 
        ["nachtwache"] = "DE", ["diesilbernehand"] = "DE", ["silbernehand"] = "DE", ["dietodeskrallen"] = "DE", 
        ["todeskrallen"] = "DE", ["dunmorogh"] = "DE", ["durotan"] = "DE", ["echsenkessel"] = "DE", 
        ["eredar"] = "DE", ["festungderstürme"] = "DE", ["festungderstuerme"] = "DE", ["festungdersturme"] = "DE", 
        ["forscherliga"] = "DE", ["frostmourne"] = "DE", ["frostwolf"] = "DE", ["garrosh"] = "DE", 
        ["gilneas"] = "DE", ["gorgonnash"] = "DE", ["guldan"] = "DE", ["kargath"] = "DE", 
        ["kelthuzad"] = "DE", ["khazgoroth"] = "DE", ["kiljaeden"] = "DE", ["kragjin"] = "DE", 
        ["kultderverdammten"] = "DE", ["verdammten"] = "DE", ["kultiras"] = "DE", ["lordaeron"] = "DE", 
        ["lothar"] = "DE", ["madmortem"] = "DE", ["malfurion"] = "DE", ["malganis"] = "DE", 
        ["malorne"] = "DE", ["malygos"] = "DE", ["mannoroth"] = "DE", ["mugthol"] = "DE", 
        ["nathrezim"] = "DE", ["nazjatar"] = "DE", ["nefarian"] = "DE", ["nerathor"] = "DE",
        ["nethersturm"] = "DE", ["norgannon"] = "DE", ["nozdormu"] = "DE", ["onyxia"] = "DE", 
        ["perenolde"] = "DE", ["proudmoore"] = "DE", ["rajaxx"] = "DE", ["rexxar"] = "DE", 
        ["senjin"] = "DE", ["shattrath"] = "DE", ["taerar"] = "DE", ["teldrassil"] = "DE", 
        ["terrordar"] = "DE", ["theradras"] = "DE", ["thrall"] = "DE", ["tichondrius"] = "DE", 
        ["tirion"] = "DE", ["todeswache"] = "DE", ["ulduar"] = "DE", ["ungorokrater"] = "DE", 
        ["ungoro"] = "DE", ["veklor"] = "DE", ["wrathbringer"] = "DE", ["ysera"] = "DE", 
        ["zirkeldescenarius"] = "DE", ["cenarius"] = "DE", ["zuluhed"] = "DE",

        -- French (FR)
        ["arakarahm"] = "FR", ["archimonde"] = "FR", ["chantséternels"] = "FR", ["chantseternels"] = "FR", 
        ["chogall"] = "FR", ["confrériedethorium"] = "FR", ["confreriedethorium"] = "FR", ["conseildesombres"] = "FR", 
        ["cultedelarivenoire"] = "FR", ["dalaran"] = "FR", ["drekthar"] = "FR", ["eitrigg"] = "FR", 
        ["eldrethalas"] = "FR", ["elune"] = "FR", ["garona"] = "FR", ["hyjal"] = "FR", 
        ["illidan"] = "FR", ["kaelthas"] = "FR", ["khazmodan"] = "FR", ["kirintor"] = "FR", 
        ["krasus"] = "FR", ["lesclairvoyants"] = "FR", ["clairvoyants"] = "FR", ["lessentinelles"] = "FR", 
        ["sentinelles"] = "FR", ["marécagedezangar"] = "FR", ["marecagedezangar"] = "FR", ["medivh"] = "FR", 
        ["nerzhul"] = "FR", ["rashgarroth"] = "FR", ["sargeras"] = "FR", ["sinstralis"] = "FR", 
        ["suramar"] = "FR", ["templemoir"] = "FR", ["templenoir"] = "FR", ["throkferoth"] = "FR", 
        ["uldaman"] = "FR", ["varimathras"] = "FR", ["voljin"] = "FR", ["ysondre"] = "FR",

        -- Spanish (ES)
        ["colinaspardas"] = "ES", ["cthun"] = "ES", ["dunmodr"] = "ES", ["exodar"] = "ES", 
        ["loserrantes"] = "ES", ["errantes"] = "ES", ["minahonda"] = "ES", ["sanguino"] = "ES", 
        ["shendralar"] = "ES", ["tyrande"] = "ES", ["uldum"] = "ES", ["zuljin"] = "ES",

        -- Italian (IT)
        ["nemesis"] = "IT", ["pozzodelleternità"] = "IT", ["pozzodelleternita"] = "IT", ["pozzo"] = "IT",

        -- Portuguese (PT)
        ["aggraportuguês"] = "PT", ["aggraportugues"] = "PT", ["aggra"] = "PT",

        -- Russian (RU)
        ["amina"] = "RU", ["ashenvale"] = "RU", ["azuregos"] = "RU", ["bootybay"] = "RU", 
        ["boreantundra"] = "RU", ["deathguard"] = "RU", ["eversong"] = "RU", ["fordragon"] = "RU", 
        ["galakrond"] = "RU", ["goldrinn"] = "RU", ["gordunni"] = "RU", ["greymane"] = "RU", 
        ["grom"] = "RU", ["howlingfjord"] = "RU", ["lichking"] = "RU", ["soulflayer"] = "RU", 
        ["thermaplugg"] = "RU", ["veknilash"] = "RU",
        
        -- English (EN)
        ["aeriepeak"] = "EN", ["agamaggan"] = "EN", ["aggramar"] = "EN", ["ahnqiraj"] = "EN", 
        ["alakir"] = "EN", ["alonsus"] = "EN", ["anachronos"] = "EN", ["arathi"] = "EN", 
        ["arathor"] = "EN", ["argentdawn"] = "EN", ["aszune"] = "EN", ["auchindoun"] = "EN", 
        ["azjolnerub"] = "EN", ["azuremyst"] = "EN", ["balnazzar"] = "EN", ["bladefist"] = "EN", 
        ["bladesedge"] = "EN", ["bloodfeather"] = "EN", ["bloodhoof"] = "EN", ["bloodscalp"] = "EN", 
        ["boulderfist"] = "EN", ["bronzebeard"] = "EN", ["bronzedragonflight"] = "EN", ["burningblade"] = "EN", 
        ["burninglegion"] = "EN", ["chamberofaspects"] = "EN", ["chromaggus"] = "EN", ["crushridge"] = "EN", 
        ["daggerspine"] = "EN", ["darkmoonfaire"] = "EN", ["darksorrow"] = "EN", ["darkspear"] = "EN", 
        ["deathwing"] = "EN", ["defiasbrotherhood"] = "EN", ["dentarg"] = "EN", ["doomhammer"] = "EN", 
        ["draenor"] = "EN", ["dragonblight"] = "EN", ["dragonmaw"] = "EN", ["drakthul"] = "EN", 
        ["dunemaul"] = "EN", ["earthenring"] = "EN", ["emeralddream"] = "EN", ["emeriss"] = "EN", 
        ["eonar"] = "EN", ["executus"] = "EN", ["frostmane"] = "EN", ["frostwhisper"] = "EN", 
        ["genjuros"] = "EN", ["ghostlands"] = "EN", ["grimbatol"] = "EN", ["hakkar"] = "EN", 
        ["haomarush"] = "EN", ["hellscream"] = "EN", ["jaedenar"] = "EN", ["karazhan"] = "EN", 
        ["kazzak"] = "EN", ["khadgar"] = "EN", ["kilrogg"] = "EN", ["korall"] = "EN", 
        ["laughingskull"] = "EN", ["lightbringer"] = "EN", ["lightningsblade"] = "EN", ["magtheridon"] = "EN", 
        ["mazrigos"] = "EN", ["moonglade"] = "EN", ["muradin"] = "EN", ["nagrand"] = "EN", 
        ["neptulon"] = "EN", ["nordrassil"] = "EN", ["outland"] = "EN", ["quelthalas"] = "EN", 
        ["ragnaros"] = "EN", ["ravencrest"] = "EN", ["ravenholdt"] = "EN", ["runetotem"] = "EN", 
        ["saurfang"] = "EN", ["scarshieldlegion"] = "EN", ["shadowsong"] = "EN", ["shatteredhalls"] = "EN", 
        ["shatteredhand"] = "EN", ["silvermoon"] = "EN", ["spinebreaker"] = "EN", ["sporeggar"] = "EN", 
        ["stormrage"] = "EN", ["stormreaver"] = "EN", ["stormscale"] = "EN", ["sunstrider"] = "EN", 
        ["sylvanas"] = "EN", ["talnivarr"] = "EN", ["tarrenmill"] = "EN", ["terenas"] = "EN", 
        ["terokkar"] = "EN", ["themaelstrom"] = "EN", ["maelstrom"] = "EN", ["theshatar"] = "EN", ["shatar"] = "EN", 
        ["thunderhorn"] = "EN", ["trollbane"] = "EN", ["turalyon"] = "EN", ["twilightshammer"] = "EN", 
        ["twistingnether"] = "EN", ["vashj"] = "EN", ["wildhammer"] = "EN", ["xavius"] = "EN", ["zenedar"] = "EN"
    }
elseif currentRegion == 1 then
    -- AMERICAS & OCEANIA REGION (US)
    realmToRegion = {
        -- Brazil (BR)
        ["azralon"] = "BR", ["gallywix"] = "BR", ["goldrinn"] = "BR", ["nemesis"] = "BR", ["tolbarad"] = "BR",
        
        -- Latin America (MX)
        ["drakkari"] = "MX", ["quelthalas"] = "MX", ["ragnaros"] = "MX",
        
        -- Oceania (AU)
        ["amanthul"] = "AU", ["barthilas"] = "AU", ["caelestrasz"] = "AU", ["dathremar"] = "AU", 
        ["dreadmaul"] = "AU", ["frostmourne"] = "AU", ["gundrak"] = "AU", ["jubeithos"] = "AU", 
        ["khazgoroth"] = "AU", ["nagrand"] = "AU", ["saurfang"] = "AU", ["thaurissan"] = "AU",
        
        -- United States / NA English (US)
        ["aegwynn"] = "US", ["aeriepeak"] = "US", ["agamaggan"] = "US", ["aggramar"] = "US", ["akama"] = "US", 
        ["alexstrasza"] = "US", ["alleria"] = "US", ["altarofstorms"] = "US", ["alteracmountains"] = "US", 
        ["andorhal"] = "US", ["anetheron"] = "US", ["antonidas"] = "US", ["anubarak"] = "US", ["anvilmar"] = "US", 
        ["arathor"] = "US", ["archimonde"] = "US", ["area52"] = "US", ["argentdawn"] = "US", ["arthas"] = "US", 
        ["arygos"] = "US", ["auchindoun"] = "US", ["azgalor"] = "US", ["azjolnerub"] = "US", ["azshara"] = "US", 
        ["azuremyst"] = "US", ["baelgun"] = "US", ["balnazzar"] = "US", ["blackdragonflight"] = "US", 
        ["blackhand"] = "US", ["blackrock"] = "US", ["blackwaterraiders"] = "US", ["blackwinglair"] = "US", 
        ["bladesedge"] = "US", ["bladefist"] = "US", ["bleedinghollow"] = "US", ["bloodfurnace"] = "US", 
        ["bloodhoof"] = "US", ["bloodscalp"] = "US", ["bonechewer"] = "US", ["boreantundra"] = "US", 
        ["boulderfist"] = "US", ["bronzebeard"] = "US", ["burningblade"] = "US", ["burninglegion"] = "US", 
        ["cairne"] = "US", ["cenarioncircle"] = "US", ["cenarius"] = "US", ["chogall"] = "US", ["chromaggus"] = "US", 
        ["coilfang"] = "US", ["crushridge"] = "US", ["daggerspine"] = "US", ["dalaran"] = "US", ["dalvengyr"] = "US", 
        ["darkirondwarves"] = "US", ["darkiron"] = "US", ["darkspear"] = "US", ["darrowmere"] = "US", 
        ["dawnbringer"] = "US", ["deathwing"] = "US", ["demonwhisper"] = "US", ["dentarg"] = "US", ["destromath"] = "US", 
        ["dethecus"] = "US", ["detheroc"] = "US", ["doomhammer"] = "US", ["draenor"] = "US", ["dragonblight"] = "US", 
        ["dragonmaw"] = "US", ["draktharon"] = "US", ["drakthul"] = "US", ["drenden"] = "US", ["dunemaul"] = "US", 
        ["durotan"] = "US", ["duskwood"] = "US", ["earthenring"] = "US", ["echoisles"] = "US", ["eitrigg"] = "US", 
        ["eldrethalas"] = "US", ["elune"] = "US", ["emeralddream"] = "US", ["eonar"] = "US", ["eredar"] = "US", 
        ["executus"] = "US", ["exodar"] = "US", ["farstriders"] = "US", ["feathermoon"] = "US", ["fenris"] = "US", 
        ["firetree"] = "US", ["fizzcrank"] = "US", ["frostmane"] = "US", ["frostwolf"] = "US", ["galakrond"] = "US", 
        ["garithos"] = "US", ["garona"] = "US", ["garrosh"] = "US", ["ghostlands"] = "US", ["gilneas"] = "US", 
        ["gnomeregan"] = "US", ["gorefiend"] = "US", ["gorgonnash"] = "US", ["greymane"] = "US", ["grizzlyhills"] = "US", 
        ["guldan"] = "US", ["gurubashi"] = "US", ["hakkar"] = "US", ["haomarush"] = "US", ["hellscream"] = "US", 
        ["hydraxis"] = "US", ["hyjal"] = "US", ["icecrown"] = "US", ["illidan"] = "US", ["jaedenar"] = "US", 
        ["kaelthas"] = "US", ["kalecgos"] = "US", ["kargath"] = "US", ["kelthuzad"] = "US", ["khadgar"] = "US", 
        ["khazmodan"] = "US", ["kiljaeden"] = "US", ["kilrogg"] = "US", ["kirintor"] = "US", ["korgath"] = "US", 
        ["korialstrasz"] = "US", ["kultiras"] = "US", ["laughingskull"] = "US", ["lethon"] = "US", ["lightbringer"] = "US", 
        ["lightningsblade"] = "US", ["lightninghoof"] = "US", ["llane"] = "US", ["lothar"] = "US", ["madoran"] = "US", 
        ["maelstrom"] = "US", ["magtheridon"] = "US", ["maiev"] = "US", ["malganis"] = "US", ["malfurion"] = "US", 
        ["malorne"] = "US", ["malygos"] = "US", ["mannoroth"] = "US", ["marrowgar"] = "US", ["medivh"] = "US", 
        ["misha"] = "US", ["moknathal"] = "US", ["moonguard"] = "US", ["moonrunner"] = "US", ["mugthol"] = "US", 
        ["muradin"] = "US", ["nathrezim"] = "US", ["nazgrel"] = "US", ["nazjatar"] = "US", ["nerzhul"] = "US", 
        ["nesingwary"] = "US", ["norgannon"] = "US", ["nozdormu"] = "US", ["onyxia"] = "US", ["outland"] = "US", 
        ["perenolde"] = "US", ["proudmoore"] = "US", ["ravencrest"] = "US", ["ravenholdt"] = "US", ["rexxar"] = "US", 
        ["rivendare"] = "US", ["runetotem"] = "US", ["sargeras"] = "US", ["scarletcrusade"] = "US", ["scilla"] = "US", 
        ["senjin"] = "US", ["sentinels"] = "US", ["shadowcouncil"] = "US", ["shadowmoon"] = "US", ["shadowsong"] = "US", 
        ["shatteredhand"] = "US", ["shatteredhalls"] = "US", ["shandris"] = "US", ["shattrath"] = "US", ["shirvallah"] = "US", 
        ["shuhalo"] = "US", ["silverhand"] = "US", ["silvermoon"] = "US", ["sistersofelune"] = "US", ["skullcrusher"] = "US", 
        ["skywall"] = "US", ["smolderthorn"] = "US", ["spinebreaker"] = "US", ["spirestone"] = "US", ["staghelm"] = "US", 
        ["stonemaul"] = "US", ["stormrage"] = "US", ["stormreaver"] = "US", ["stormscale"] = "US", ["suramar"] = "US", 
        ["sylvanas"] = "US", ["tanaris"] = "US", ["terenas"] = "US", ["terokkar"] = "US", ["theforgottencoast"] = "US", 
        ["forgottencoast"] = "US", ["thescryers"] = "US", ["scryers"] = "US", ["theunderbog"] = "US", ["underbog"] = "US", 
        ["theventureco"] = "US", ["ventureco"] = "US", ["thoriumbrotherhood"] = "US", ["thrall"] = "US", ["thunderhorn"] = "US", 
        ["thunderlord"] = "US", ["tichondrius"] = "US", ["tortheldrin"] = "US", ["trollbane"] = "US", ["turalyon"] = "US", 
        ["twistingnether"] = "US", ["uldaman"] = "US", ["uldum"] = "US", ["ungorocrater"] = "US", ["ursin"] = "US", 
        ["uther"] = "US", ["vashj"] = "US", ["veknilash"] = "US", ["velen"] = "US", ["whisperwind"] = "US", 
        ["wildhammer"] = "US", ["windrunner"] = "US", ["winterhoof"] = "US", ["wyrmrestaccord"] = "US", ["ysera"] = "US", 
        ["ysondre"] = "US", ["zangarmarsh"] = "US", ["zuljin"] = "US", ["zuluhed"] = "US"
    }
end

-- Determines the correct region (abbreviation) based on the server name
function WT.Utils.Realms:GetRegion(realmName)
    realmName = Unsecret(realmName)
    if not realmName or realmName == "" then return fallbackFlag end
    local cleanRealm = string.lower(realmName):gsub("[%s%p]", "")
    return realmToRegion[cleanRealm] or fallbackFlag
end

function WT.Utils.Realms:IsKnownRealm(realmName)
    realmName = Unsecret(realmName)
    if not realmName or realmName == "" then return false end
    local cleanRealm = string.lower(realmName):gsub("[%s%p]", "")
    return realmToRegion[cleanRealm] ~= nil
end

local flagStrCache = {}

-- Returns the formatted WoW UI texture string that can be rendered in tooltips and buttons
function WT.Utils.Realms:GetFlagString(realmName, showText)
    realmName = Unsecret(realmName)
    local cacheKey = (realmName or "") .. tostring(showText)
    if flagStrCache[cacheKey] then return flagStrCache[cacheKey] end

    local region = self:GetRegion(realmName)
    local coords = flagCoords[region]
    
    -- Fallback in case coordinates are invalid
    if not coords then 
        flagStrCache[cacheKey] = ""
        return "" 
    end
    
    -- Perfect 4:3 cropping
    local xInset = 0
    local yInset = 8
    local c1 = math.floor((coords[1] * 256) + xInset)
    local c2 = math.floor((coords[2] * 256) - xInset)
    local c3 = math.floor((coords[3] * 256) + yInset)
    local c4 = math.floor((coords[4] * 256) - yInset)
    
    local xOffset = 0
    local yOffset = 1
    
    local texStr = string.format("|T%s:9:12:%d:%d:256:256:%d:%d:%d:%d|t", FLAG_TEXTURE, xOffset, yOffset, c1, c2, c3, c4)
    
    if showText then
        local country = countryNames[region] or region
        flagStrCache[cacheKey] = country .. " " .. texStr
    else
        flagStrCache[cacheKey] = texStr
    end
    return flagStrCache[cacheKey]
end