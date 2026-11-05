local _, WT = ...

WT.Modules.ClassColors = {}
local Module = WT.Modules.ClassColors

local defaultColors = {
    DEATHKNIGHT = {r=0.77, g=0.12, b=0.23},
    DEMONHUNTER = {r=0.64, g=0.19, b=0.79},
    DRUID       = {r=1.00, g=0.49, b=0.04},
    EVOKER      = {r=0.20, g=0.58, b=0.50},
    HUNTER      = {r=0.67, g=0.83, b=0.45},
    MAGE        = {r=0.25, g=0.78, b=0.92},
    MONK        = {r=0.00, g=1.00, b=0.59},
    PALADIN     = {r=0.96, g=0.55, b=0.73},
    PRIEST      = {r=1.00, g=1.00, b=1.00},
    ROGUE       = {r=1.00, g=0.96, b=0.41},
    SHAMAN      = {r=0.00, g=0.44, b=0.87},
    WARLOCK     = {r=0.53, g=0.53, b=0.93},
    WARRIOR     = {r=0.78, g=0.61, b=0.43},
}

function Module:UpdateColors()
    if not WT.DB.Modules.Frames then return end
    
    -- We NO LONGER update RAID_CLASS_COLORS because it heavily taints Blizzard's Raid and Party frames (WoW 10.0+).
    -- Instead, we update CUSTOM_CLASS_COLORS for 3rd-party addons that support the standard,
    -- and WT modules read directly from WT.DB.ClassColors.
    local CCC = _G["CUSTOM_CLASS_COLORS"]
    if not CCC then
        -- If no dedicated ClassColor addon is installed, WT takes over as the global provider!
        CCC = {}
        _G["CUSTOM_CLASS_COLORS"] = CCC
        
        local callbacks = {}
        local api = {
            RegisterCallback = function(self, method, handler)
                table.insert(callbacks, { method = method, handler = handler })
            end,
            UnregisterCallback = function(self, method, handler)
                for i = #callbacks, 1, -1 do
                    if callbacks[i].method == method and callbacks[i].handler == handler then
                        table.remove(callbacks, i)
                    end
                end
            end,
            NotifyChanges = function(self)
                for _, cb in ipairs(callbacks) do
                    if type(cb.handler) == "table" and type(cb.method) == "string" and type(cb.handler[cb.method]) == "function" then
                        cb.handler[cb.method](cb.handler)
                    elseif type(cb.method) == "function" then
                        cb.method(cb.handler)
                    elseif type(cb.method) == "string" and type(_G[cb.method]) == "function" then
                        _G[cb.method]()
                    end
                end
            end
        }
        setmetatable(CCC, { __index = api })
    end

    for class, color in pairs(WT.DB.ClassColors) do
        if not CCC[class] then CCC[class] = {} end
        CCC[class].r = color.r
        CCC[class].g = color.g
        CCC[class].b = color.b
        CCC[class].colorStr = WT.Colors:GetHex(color, 1, 1, 1)
        
        -- Synchronize WTs own global format strings
        if WT.Colors and WT.Colors.Classes then
            WT.Colors.Classes[class] = "|c" .. CCC[class].colorStr
        end
    end
    
    if type(CCC["NotifyChanges"]) == "function" then
        CCC["NotifyChanges"](CCC)
    end
end

function Module:Initialize()
    if not WT.DB.Modules.Frames then return end
    self:UpdateColors()
end

WT.Core.Events:Register("PLAYER_LOGIN", function()
    Module:Initialize()
end)

function Module:BuildOptions(builder, panel)
    local function PromptReload() if WT.Config and WT.Config.OptionsPanel and WT.Config.OptionsPanel.ShowReloadPrompt then WT.Config.OptionsPanel:ShowReloadPrompt() end end
    local function AddDescription(text)
        if not text then return end
        local desc = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
        desc:SetWidth(550)
        desc:SetJustifyH("LEFT")
        desc:SetText(text)
        builder:AddSpace(desc:GetStringHeight() + 25)
    end

    panel:CreateTitle(builder, WT.L.CATEGORY_CLASSCOLORS)
    AddDescription(WT.L.OPT_DESC_MODULE_CLASSCOLORS)
    
    local isForever = WT.Compat and WT.Compat.IsForever
    local sortedClasses = {}
    for k in pairs(defaultColors) do
        if not isForever or (k ~= "DEATHKNIGHT" and k ~= "DEMONHUNTER" and k ~= "EVOKER" and k ~= "MONK") then
            table.insert(sortedClasses, k)
        end
    end
    table.sort(sortedClasses)

    local locNames = _G["LOCALIZED_CLASS_NAMES_MALE"]
    for _, class in ipairs(sortedClasses) do
        local className = locNames and locNames[class] or class
        panel:CreateColorPicker(builder, className, WT.L.OPT_DESC_COLOR_VALUE, "ClassColors", class, false, nil, function() self:UpdateColors(); PromptReload() end)
    end
end
