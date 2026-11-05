local _, WT = ...

WT.Compat = WT.Compat or {}

-- 1. Query client version, build number, and TOC version
local clientVersion, buildNumber, buildDate, tocVersion = GetBuildInfo()
local toc = tonumber(tocVersion) or 0
local bNum = tonumber(buildNumber) or 0

-- 2. Detect "WoW Forever" (Camelot / 1.60 architecture)
-- Forever clients identify via:
--   - WOW_PROJECT_CAMELOT (ID 18) or WOW_PROJECT_FOREVER
--   - TOC versions in the 16.x branch (e.g. 16001, 16000, 160000..169999)
--   - Version string starting with "1.60"
local isCamelot = (_G["WOW_PROJECT_CAMELOT"] ~= nil and _G["WOW_PROJECT_ID"] == _G["WOW_PROJECT_CAMELOT"])
local isForeverProject = (_G["WOW_PROJECT_FOREVER"] ~= nil and _G["WOW_PROJECT_ID"] == _G["WOW_PROJECT_FOREVER"])
local isForeverToc = (toc >= 16000 and toc < 20000) or (toc >= 160000 and toc < 170000)
local isForeverVersion = type(clientVersion) == "string" and (string.match(clientVersion, "^1%.60") ~= nil)

local isForever = isCamelot or isForeverProject or isForeverToc or isForeverVersion or false

-- 3. Detect "WoW Retail" (Midnight 12.1.x / War Within 11.x)
local isRetail = not isForever and (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE or toc >= 110000)
local isMidnight = isRetail and ((toc >= 120000) or (type(clientVersion) == "string" and (string.match(clientVersion, "^12%.") ~= nil)))

-- 4. Expose core compatibility flags
WT.Compat.IsForever = isForever
WT.Compat.IsRetail = isRetail
WT.Compat.IsMidnight = isMidnight
WT.Compat.ClientVersion = clientVersion or "0.0.0"
WT.Compat.BuildNumber = bNum
WT.Compat.BuildDate = buildDate or ""
WT.Compat.TocVersion = toc
WT.Compat.Flavor = isForever and "Forever" or (isRetail and "Retail" or "Forever")

-- 5. Feature capability flags
WT.Compat.HasRangedSlot = isForever -- Slot 18 (Ranged / Wand / Relic)
WT.Compat.HasMythicPlus = isRetail  -- Mythic+ Dungeons & Rating
WT.Compat.HasCommunities = isRetail and (C_Club ~= nil)
WT.Compat.HasRaiderIO = isRetail
WT.Compat.MaxPlayerLevel = isForever and 60 or (isRetail and 90 or 60)

-- 6. Helper functions
function WT.Compat:GetFlavorName()
    if self.IsForever then
        return "WoW Forever (Beta)"
    elseif self.IsRetail then
        return "Retail"
    else
        return "WoW Forever (Beta)"
    end
end

function WT.Compat:GetWowheadSubdomain()
    return self.IsForever and "forever/" or ""
end
