local _, WT = ...

WT.Modules.Farming = {}
local Module = WT.Modules.Farming

local barFrame, toolsBar, seedsBar, portalsBar
local toolButtons = {}
local seedButtons = {}
local portalButtons = {}

local VALID_ZONES = {
    ["Sunsong Ranch"] = true,
    ["Gehöft Sonnensang"] = true,
}

-- Fishing Variables
local fishingBtn
local isFishingCast = false
local origAudio = {}
local interactCvars = {}

local WTFishingKeybindBtn = CreateFrame("Button", "WTFishingKeybindBtn", UIParent, "SecureActionButtonTemplate, SecureHandlerStateTemplate")
WTFishingKeybindBtn:SetSize(1, 1)
WTFishingKeybindBtn:SetPoint("TOPLEFT", 0, 0)
WTFishingKeybindBtn:Show()
WTFishingKeybindBtn:RegisterForClicks("AnyUp", "AnyDown")
WTFishingKeybindBtn:SetAttribute("type", "spell")
local _spellName = C_Spell.GetSpellName(131474) or "Fishing"
WTFishingKeybindBtn:SetAttribute("spell", _spellName)

WTFishingKeybindBtn:SetAttribute("_onstate-fishing", [[
    local key = self:GetAttribute("boundKey")
    if key then
        if newstate == 1 then
            self:SetBinding(true, key, "INTERACTTARGET")
        else
            self:ClearBindings()
        end
    end
]])


local TOOLS = {
    89815, -- Master Plow
    89880, -- Dented Shovel
    80513, -- Vintage Bug Sprayer
    79104, -- Rusty Watering Can
}

local faction = UnitFactionGroup("player")
local PORTALS = faction == "Alliance" and {
    91860, -- Stormwind
    91864, -- Ironforge
    91865, -- Darnassus
    91866  -- Exodar
} or {
    91850, -- Orgrimmar
    91862, -- Undercity
    91861, -- Thunder Bluff
    91863  -- Silvermoon
}

local SEEDS = {
    79102, 89328, 80590, 80592, 80594, 80593, 80591, 89329, 80595, 89326, 
    85219, 85216, 85217, 89202, 85215, 89233, 89197, 91806, 85267, 85268, 85269
}

local function UpdateBarLayout()
    if not barFrame then return end
    local size = WT.DB.Farming.ButtonSize or 40
    local spacing = WT.DB.Farming.ButtonSpacing or 5
    local isHorizontal = (WT.DB.Farming.Direction == "HORIZONTAL")
    local padding = 8

    local function LayoutBarSingle(bar, btnList, btnSize)
        if not bar:IsShown() then return 0, 0 end
        local count = #btnList
        if count == 0 then return 0, 0 end
        
        local width, height
        if isHorizontal then
            width = count * btnSize + (count - 1) * spacing + (padding * 2)
            height = btnSize + (padding * 2)
        else
            height = count * btnSize + (count - 1) * spacing + (padding * 2)
            width = btnSize + (padding * 2)
        end
        bar:SetSize(width, height)
        
        for i, btn in ipairs(btnList) do
            btn:SetSize(btnSize, btnSize)
            btn:ClearAllPoints()
            if isHorizontal then
                btn:SetPoint("LEFT", bar, "LEFT", padding + (i - 1) * (btnSize + spacing), 0)
            else
                btn:SetPoint("TOP", bar, "TOP", 0, -(padding + (i - 1) * (btnSize + spacing)))
            end
        end
        return width, height
    end

    local function LayoutBarGrid(bar, btnList, btnSize)
        if not bar:IsShown() then return 0, 0 end
        local count = #btnList
        if count == 0 then return 0, 0 end
        
        local cols = 7
        local rows = math.ceil(count / cols)
        if not isHorizontal then
            rows = 7
            cols = math.ceil(count / rows)
        end
        
        local width = cols * btnSize + (cols - 1) * spacing + (padding * 2)
        local height = rows * btnSize + (rows - 1) * spacing + (padding * 2)
        bar:SetSize(width, height)
        
        for i, btn in ipairs(btnList) do
            btn:SetSize(btnSize, btnSize)
            btn:ClearAllPoints()
            local r, c
            if isHorizontal then
                c = (i - 1) % cols
                r = math.floor((i - 1) / cols)
            else
                r = (i - 1) % rows
                c = math.floor((i - 1) / rows)
            end
            
            local x = padding + c * (btnSize + spacing)
            local y = -(padding + r * (btnSize + spacing))
            btn:SetPoint("TOPLEFT", bar, "TOPLEFT", x, y)
        end
        return width, height
    end

    local function ApplyBg(bar)
        if WT.DB.Farming.Background then
            local bg = WT.DB.Farming.BgColor or { r = WT.Colors.STD_BG_R, g = WT.Colors.STD_BG_G, b = WT.Colors.STD_BG_B, a = WT.Colors.STD_BG_A }
            bar:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
        else
            bar:SetBackdropColor(0, 0, 0, 0)
        end
        if WT.DB.Farming.Border then
            local bord = WT.DB.Farming.BorderColor or { r = 1, g = 1, b = 1, a = 1 }
            bar:SetBackdropBorderColor(bord.r, bord.g, bord.b, bord.a)
        else
            bar:SetBackdropBorderColor(0, 0, 0, 0)
        end
    end

    local w1, h1 = LayoutBarGrid(seedsBar, seedButtons, size * 0.6)
    local w2, h2 = LayoutBarSingle(toolsBar, toolButtons, size)
    local w3, h3 = LayoutBarSingle(portalsBar, portalButtons, size * 0.5)

    if seedsBar:IsShown() then ApplyBg(seedsBar) end
    if toolsBar:IsShown() then ApplyBg(toolsBar) end
    if portalsBar:IsShown() then ApplyBg(portalsBar) end

    local bars = {}
    if seedsBar:IsShown() then table.insert(bars, seedsBar) end
    if toolsBar:IsShown() then table.insert(bars, toolsBar) end
    if portalsBar:IsShown() then table.insert(bars, portalsBar) end

    if #bars == 0 then
        barFrame:Hide()
        return
    end
    barFrame:Show()

    local totalW, totalH = 0, 0
    for i, b in ipairs(bars) do
        b:ClearAllPoints()
        if isHorizontal then
            if i == 1 then b:SetPoint("TOP", barFrame, "TOP", 0, 0)
            else b:SetPoint("TOP", bars[i-1], "BOTTOM", 0, -spacing) end
            totalH = totalH + b:GetHeight() + (i > 1 and spacing or 0)
            totalW = math.max(totalW, b:GetWidth())
        else
            if i == 1 then b:SetPoint("LEFT", barFrame, "LEFT", 0, 0)
            else b:SetPoint("LEFT", bars[i-1], "RIGHT", spacing, 0) end
            totalW = totalW + b:GetWidth() + (i > 1 and spacing or 0)
            totalH = math.max(totalH, b:GetHeight())
        end
    end
    barFrame:SetSize(totalW, totalH)
    barFrame:SetScale(WT.DB.Farming.Scale or 1.0)
end



local function UpdateButtons()
    if InCombatLockdown() then
        WT.Core.CombatQueue:Add("FarmingUpdate", true, UpdateButtons)
        return
    end

    local subzone = GetMinimapZoneText()
    if not VALID_ZONES[subzone] then
        if barFrame then barFrame:Hide() end
        return
    end

    local function ConfigureButton(btn, itemID)
        local count = C_Item.GetItemCount(itemID)
        btn:SetAttribute("item", "item:" .. itemID)
        btn.itemID = itemID
        local icon = C_Item.GetItemIconByID(itemID)
        if icon then btn.icon:SetTexture(icon) end
        
        if count > 0 then
            btn.icon:SetDesaturated(false)
            btn.icon:SetVertexColor(1, 1, 1)
        else
            btn.icon:SetDesaturated(true)
            btn.icon:SetVertexColor(0.5, 0.5, 0.5)
        end
        if btn.countText then btn.countText:SetText(count) end
        btn:Show()
    end

    toolsBar:Show()
    for i, itemID in ipairs(TOOLS) do ConfigureButton(toolButtons[i], itemID) end

    if WT.DB.Farming.ShowSeeds then
        seedsBar:Show()
        for i, itemID in ipairs(SEEDS) do ConfigureButton(seedButtons[i], itemID) end
    else
        seedsBar:Hide()
        for i, itemID in ipairs(SEEDS) do seedButtons[i]:Hide() end
    end

    if WT.DB.Farming.ShowPortals then
        portalsBar:Show()
        for i, itemID in ipairs(PORTALS) do ConfigureButton(portalButtons[i], itemID) end
    else
        portalsBar:Hide()
        for i, itemID in ipairs(PORTALS) do portalButtons[i]:Hide() end
    end

    UpdateBarLayout()
end

function Module:SetupBar()
    if InCombatLockdown() then
        WT.Core.CombatQueue:Add("FarmingSetup", true, function() Module:SetupBar() end)
        return
    end

    if not barFrame then
        barFrame = CreateFrame("Frame", "WTFarmingFrame", _G["WT_UIContainer"])
        barFrame:SetFrameStrata(WT.DB.Farming.Strata or "MEDIUM")
        barFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
        barFrame:SetSize(10, 10)

        local function SetupBarFrame(f)
            f:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 14,
                insets = { left = 3, right = 3, top = 3, bottom = 3 }
            })
            f:EnableMouse(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", function()
                if InCombatLockdown() then return end
                local mod = WT.DB.Farming.MoveModifier or "ALT"
                local canMove = false
                if mod == "SHIFT" then canMove = IsShiftKeyDown()
                elseif mod == "CTRL" then canMove = IsControlKeyDown()
                elseif mod == "ALT" then canMove = IsAltKeyDown() end
                if WT.DB.Farming.Movable and canMove then barFrame:StartMoving() end
            end)
            f:SetScript("OnDragStop", function()
                barFrame:StopMovingOrSizing()
                local p, _, rP, x, y = barFrame:GetPoint()
                if not WT.DB.Internal.Positions then WT.DB.Internal.Positions = {} end
                WT.DB.Internal.Positions["WTFarmingFrame"] = { point = p, relativeTo = "UIParent", relativePoint = rP, xOfs = x, yOfs = y }
            end)
        end

        toolsBar = CreateFrame("Frame", "WTFarmingToolsBar", barFrame, "BackdropTemplate")
        seedsBar = CreateFrame("Frame", "WTFarmingSeedsBar", barFrame, "BackdropTemplate")
        portalsBar = CreateFrame("Frame", "WTFarmingPortalsBar", barFrame, "BackdropTemplate")
        SetupBarFrame(toolsBar)
        SetupBarFrame(seedsBar)
        SetupBarFrame(portalsBar)

        local function CreateBtn(name, parent)
            local btn = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
            btn:RegisterForClicks("AnyUp", "AnyDown")
            btn:SetAttribute("type", "item")
            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetAllPoints()
            btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            
            btn.countText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            btn.countText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
            btn:Hide()

            btn:SetScript("OnEnter", function(self)
                if self.itemID then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetItemByID(self.itemID)
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
            end)

            return btn
        end

        for i = 1, #TOOLS do table.insert(toolButtons, CreateBtn("WTFarmingButton" .. i, toolsBar)) end
        for i = 1, #SEEDS do table.insert(seedButtons, CreateBtn("WTFarmingSeedBtn" .. i, seedsBar)) end
        for i = 1, #PORTALS do table.insert(portalButtons, CreateBtn("WTFarmingPortalBtn" .. i, portalsBar)) end
    end

    barFrame:SetMovable(WT.DB.Farming.Movable)
    barFrame:SetFrameStrata(WT.DB.Farming.Strata or "MEDIUM")

    if WT.DB.Internal.Positions and WT.DB.Internal.Positions["WTFarmingFrame"] then
        local pos = WT.DB.Internal.Positions["WTFarmingFrame"]
        barFrame:ClearAllPoints()
        barFrame:SetPoint(pos.point, _G["WT_UIContainer"], pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        barFrame:ClearAllPoints()
        barFrame:SetPoint("CENTER", _G["WT_UIContainer"], "CENTER", 0, -150)
    end

    UpdateButtons()
end

local function HandleFishingAudio(enable)
    if not WT.DB.Farming.FishingSmartAudio then return end
    if enable then
        origAudio.master = GetCVar("Sound_MasterVolume")
        origAudio.sfx = GetCVar("Sound_SFXVolume")
        origAudio.music = GetCVar("Sound_MusicVolume")
        origAudio.ambience = GetCVar("Sound_AmbienceVolume")
        
        SetCVar("Sound_MasterVolume", "1.0")
        SetCVar("Sound_SFXVolume", "1.0")
        SetCVar("Sound_MusicVolume", "0.0")
        SetCVar("Sound_AmbienceVolume", "0.0")
    else
        if origAudio.master then SetCVar("Sound_MasterVolume", origAudio.master) end
        if origAudio.sfx then SetCVar("Sound_SFXVolume", origAudio.sfx) end
        if origAudio.music then SetCVar("Sound_MusicVolume", origAudio.music) end
        if origAudio.ambience then SetCVar("Sound_AmbienceVolume", origAudio.ambience) end
    end
end

function Module:UpdateFishingState()
    if InCombatLockdown() then
        WT.Core.CombatQueue:Add("FishingUpdate", true, function() Module:UpdateFishingState() end)
        return
    end

    if WT.DB.Farming.EnableFishing then
        -- Enable Soft Targeting for Fishing
        interactCvars.interact = GetCVar("SoftTargetInteract")
        interactCvars.tooltip = GetCVar("SoftTargetTooltipInteract")
        interactCvars.icon = GetCVar("SoftTargetIconInteract")
        interactCvars.range = GetCVar("SoftTargetInteractRange")
        
        SetCVar("SoftTargetInteract", 3)
        SetCVar("SoftTargetTooltipInteract", 1)
        SetCVar("SoftTargetIconInteract", 1)
        SetCVar("SoftTargetInteractRange", 30)

        if WT.DB.Farming.FishingDoubleClick then
            if not fishingBtn then
                fishingBtn = CreateFrame("Button", "WTFishingDoubleClickBtn", UIParent, "SecureActionButtonTemplate, SecureHandlerStateTemplate")
                fishingBtn:SetAllPoints(UIParent)
                fishingBtn:SetFrameStrata("FULLSCREEN_DIALOG")
                fishingBtn:RegisterForClicks("RightButtonUp", "RightButtonDown")
                fishingBtn:SetAttribute("type", "spell")
                local spellName = C_Spell.GetSpellName(131474) or "Fishing"
                fishingBtn:SetAttribute("spell", spellName)
                
                -- Ensure the invisible button is hidden immediately when combat starts to prevent screen lockups
                RegisterStateDriver(fishingBtn, "combat", "[combat] 1; 0")
                fishingBtn:SetAttribute("_onstate-combat", [[ if newstate == 1 then self:Hide() end ]])
                fishingBtn:Hide()
                
                fishingBtn:SetScript("PostClick", function(self)
                    if not InCombatLockdown() then
                        self:Hide()
                    end
                end)
                
                WorldFrame:HookScript("OnMouseDown", function(self, button)
                    if InCombatLockdown() or not WT.DB.Farming.EnableFishing or not WT.DB.Farming.FishingDoubleClick or isFishingCast then return end
                    
                    local mod = WT.DB.Farming.FishingDoubleClickModifier or "ALT"
                    if mod == "NONE" then mod = "ALT" end -- Fallback for old settings
                    
                    if mod == "ALT" and not IsAltKeyDown() then return end
                    if mod == "CTRL" and not IsControlKeyDown() then return end
                    if mod == "SHIFT" and not IsShiftKeyDown() then return end
                    
                    if UnitExists("mouseover") or GetUnitSpeed("player") > 0 then return end
                    if button == "RightButton" then
                        if not fishingBtn:IsShown() then
                            fishingBtn:Show()
                            C_Timer.After(0.4, function()
                                if not InCombatLockdown() then
                                    fishingBtn:Hide()
                                end
                            end)
                        end
                    end
                end)
            end
        else
            if fishingBtn then 
                if not InCombatLockdown() then fishingBtn:Hide() end
            end
        end
    else
        if fishingBtn then 
            if not InCombatLockdown() then fishingBtn:Hide() end
        end
        -- Restore CVars
        if interactCvars.interact then SetCVar("SoftTargetInteract", interactCvars.interact) end
        if interactCvars.tooltip then SetCVar("SoftTargetTooltipInteract", interactCvars.tooltip) end
        if interactCvars.icon then SetCVar("SoftTargetIconInteract", interactCvars.icon) end
        if interactCvars.range then SetCVar("SoftTargetInteractRange", interactCvars.range) end
    end
end

local function OnFishingEvent(event, unit, _, spellID)
    if unit ~= "player" then return end
    if spellID == 131474 or spellID == 7620 then -- Fishing spells
        if event == "UNIT_SPELLCAST_CHANNEL_START" then
            isFishingCast = true
            HandleFishingAudio(true)
        elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if isFishingCast then
                isFishingCast = false
                C_Timer.After(1, function() HandleFishingAudio(false) end) -- Slight delay for the splash sound
            end
        end
    end
end

function Module:Initialize()
    if not WT.DB.Modules.Farming then
        if barFrame then barFrame:Hide() end
        return
    end

    if WT.DB.Farming.EnableFishing then
        RegisterStateDriver(WTFishingKeybindBtn, "fishing", "[channeling] 1; 0")
        local key = GetBindingKey("CLICK WTFishingKeybindBtn:LeftButton")
        if key then WTFishingKeybindBtn:SetAttribute("boundKey", key) end
    else
        UnregisterStateDriver(WTFishingKeybindBtn, "fishing")
    end

    self:SetupBar()
    self:UpdateFishingState()

    WT.Core.Events:Register("BAG_UPDATE_DELAYED", UpdateButtons)
    WT.Core.Events:Register("ZONE_CHANGED", UpdateButtons)
    WT.Core.Events:Register("ZONE_CHANGED_NEW_AREA", UpdateButtons)
    WT.Core.Events:Register("MINIMAP_UPDATE_ZOOM", UpdateButtons)
    
    WT.Core.Events:Register("UNIT_SPELLCAST_CHANNEL_START", OnFishingEvent)
    WT.Core.Events:Register("UNIT_SPELLCAST_CHANNEL_STOP", OnFishingEvent)
    
    WT.Core.Events:Register("UPDATE_BINDINGS", function()
        if not InCombatLockdown() then
            local key = GetBindingKey("CLICK WTFishingKeybindBtn:LeftButton")
            WTFishingKeybindBtn:SetAttribute("boundKey", key or nil)
        end
    end)
end

WT.Core.Events:Register("PLAYER_LOGIN", function()
    Module:Initialize()
end)

function Module:BuildOptions(builder, panel)
    local function AddDescription(text)
        if not text then return end
        local desc = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
        desc:SetWidth(550)
        desc:SetJustifyH("LEFT")
        desc:SetText(text)
        builder:AddSpace(desc:GetStringHeight() + 25)
    end



    -- Title for the Farming section in the Automations tab
    panel:CreateTitle(builder, WT.L.CATEGORY_FARMING)
    AddDescription(WT.L.OPT_DESC_MODULE_FARMING)
    AddDescription(WT.L.OPT_DESC_GROUP_FH_DISPLAY)

    local moveInit = panel:CreateCheckbox(builder, WT.L.OPT_FH_MOVABLE, WT.L.OPT_DESC_FH_MOVABLE, "Farming", "Movable",
        function() self:SetupBar() end)
    local modOptions = { { value = "ALT", label = "ALT" }, { value = "CTRL", label = "CTRL" }, { value = "SHIFT", label = "SHIFT" } }
    panel:CreateDropdown(builder, WT.L.OPT_SW_MOVE_MODIFIER, WT.L.OPT_DESC_SW_MOVE_MODIFIER, "Farming", "MoveModifier",
        modOptions, nil, moveInit)

    local dirOptions = { { value = "HORIZONTAL", label = WT.L.OPT_FH_DIR_HORIZ }, { value = "VERTICAL", label = WT.L.OPT_FH_DIR_VERT } }
    panel:CreateDropdown(builder, WT.L.OPT_FH_DIRECTION, WT.L.OPT_DESC_FH_DIRECTION, "Farming", "Direction", dirOptions,
        function() UpdateBarLayout() end)

    panel:CreateStrataDropdown(builder, WT.L.OPT_STRATA, WT.L.OPT_DESC_STRATA, "Farming", "Strata",
        function() self:SetupBar() end)

    panel:CreateSlider(builder, WT.L.OPT_FH_BTN_SIZE, WT.L.OPT_DESC_FH_BTN_SIZE, "Farming", "ButtonSize", 20, 64, 1,
        function() UpdateBarLayout() end)
    panel:CreateSlider(builder, WT.L.OPT_FH_BTN_SPACE, WT.L.OPT_DESC_FH_BTN_SPACE, "Farming", "ButtonSpacing", 0, 20, 1,
        function() UpdateBarLayout() end)
    panel:CreateSlider(builder, WT.L.OPT_FH_SCALE, WT.L.OPT_DESC_FH_SCALE, "Farming", "Scale", 0.5, 2.0, 0.1,
        function() UpdateBarLayout() end)

    local bgInit = panel:CreateCheckbox(builder, WT.L.OPT_FH_BACKGROUND, WT.L.OPT_DESC_FH_BACKGROUND, "Farming",
        "Background", function() UpdateBarLayout() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BG, WT.L.OPT_DESC_COLOR_BG, "Farming", "BgColor", true, bgInit,
        function() UpdateBarLayout() end)
    local borderInit = panel:CreateCheckbox(builder, WT.L.OPT_FH_BORDER, WT.L.OPT_DESC_FH_BORDER, "Farming", "Border",
        function() UpdateBarLayout() end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BORDER, WT.L.OPT_DESC_COLOR_BORDER, "Farming", "BorderColor", true,
        borderInit, function() UpdateBarLayout() end)

    panel:CreateCheckbox(builder, WT.L.OPT_FH_SHOW_SEEDS, WT.L.OPT_DESC_FH_SHOW_SEEDS, "Farming", "ShowSeeds",
        function() UpdateButtons() end)
    panel:CreateCheckbox(builder, WT.L.OPT_FH_SHOW_PORTALS, WT.L.OPT_DESC_FH_SHOW_PORTALS, "Farming", "ShowPortals",
        function() UpdateButtons() end)
        
    panel:CreateButton(builder, WT.L.OPT_FH_RESET_POS, "Reset", nil, function()
        if WT.DB.Internal and WT.DB.Internal.Positions then
            WT.DB.Internal.Positions["WTFarmingFrame"] = nil
        end
        if _G["WTFarmingFrame"] then
            _G["WTFarmingFrame"]:ClearAllPoints()
            _G["WTFarmingFrame"]:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
        end
    end, moveInit)
    
    builder:AddSpace(20)
    panel:CreateTitle(builder, WT.L.CATEGORY_FISHING)
    AddDescription(WT.L.OPT_DESC_MODULE_FISHING)
    local fishInit = panel:CreateCheckbox(builder, WT.L.OPT_FH_ENABLE_FISHING, WT.L.OPT_DESC_FH_ENABLE_FISHING, "Farming", "EnableFishing", function() Module:UpdateFishingState() end)
    local doubleClickInit = panel:CreateCheckbox(builder, WT.L.OPT_FH_DOUBLE_CLICK, WT.L.OPT_DESC_FH_DOUBLE_CLICK, "Farming", "FishingDoubleClick", function() Module:UpdateFishingState() end, fishInit)
    
    local clickModOptions = { { value = "ALT", label = "ALT" }, { value = "CTRL", label = "CTRL" }, { value = "SHIFT", label = "SHIFT" } }
    panel:CreateDropdown(builder, WT.L.OPT_FH_DC_MODIFIER, WT.L.OPT_DESC_FH_DC_MODIFIER, "Farming", "FishingDoubleClickModifier", clickModOptions, nil, doubleClickInit)
    
    panel:CreateCheckbox(builder, WT.L.OPT_FH_SMART_AUDIO, WT.L.OPT_DESC_FH_SMART_AUDIO, "Farming", "FishingSmartAudio", nil, fishInit)
    panel:CreateKeybindButton(builder, WT.L.OPT_FH_KEYBIND, WT.L.OPT_DESC_FH_KEYBIND, "CLICK WTFishingKeybindBtn:LeftButton")
end
