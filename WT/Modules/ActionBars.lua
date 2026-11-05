local _, WT = ...

-- ============================================================================
-- ACTION BARS
-- ============================================================================
-- Opt-in tweaks for Blizzard's action buttons:
--   * text styling for macro names, hotkeys and charges (incl. shortened hotkeys)
--   * cooldown swipe, own cooldown text and icon desaturation
--   * red icon tint while out of range
--   * Masque support and a protection for the vehicle exit button
--   * the spell queue window, which the game offers in no settings menu
-- Options the game provides itself (key down casting, auto push spells, cooldown numbers)
-- are intentionally not part of WT.
--
-- Nothing is changed while an option is off. Every change is recorded per button and
-- reverted immediately when its option is turned off, using the Blizzard defaults from
-- Blizzard_ActionBar/Mainline/ActionButtonTemplate.xml and ActionButton.lua.

local Module = WT:NewModule("ActionBars")

local Unsecret = WT.Utils.Safety.Unsecret
local SafeNum = WT.Utils.Safety.SafeNum
local IsSecret = WT.Utils.Safety.IsSecret

-- Readable boolean or nil if unknown (secret value / no value). Unsecret() is not suitable
-- here because it only handles strings and numbers; SafeBool() turns secrets into false.
---@param v any
---@return boolean|nil
local function ReadBool(v)
    if type(v) ~= "boolean" or IsSecret(v) then return nil end
    return v
end

local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local GetActionInfo = GetActionInfo
local GetMacroSpell = GetMacroSpell
local GetMacroItem = GetMacroItem
local GetPetActionInfo = GetPetActionInfo
local GetPetActionCooldown = GetPetActionCooldown

local SOLID_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local BLIZZ_SWIPE_COLOR = { 0, 0, 0, 0.64 }          -- <SwipeTexture><Color a="0.64"/> of the action button cooldown
local OUT_OF_RANGE_COLOR = { 0.8, 0.1, 0.1 }
local COOLDOWN_TICK_INTERVAL = 0.05

local BUTTON_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button",
    "MultiBar6Button", "MultiBar7Button", "PetActionButton", "StanceButton",
}

-- Per element: font string key on the button and the matching option keys
local TEXT_ELEMENTS = {
    { region = "Name",   custom = "CustomMacroText",  hide = "HideMacroText",  font = "MacroFont",  size = "MacroSize",  outline = "MacroOutline",  color = "MacroColor",  defaultSize = 10 },
    { region = "HotKey", custom = "CustomHotkeyText", hide = "HideHotkeyText", font = "HotkeyFont", size = "HotkeySize", outline = "HotkeyOutline", color = "HotkeyColor", defaultSize = 14 },
    { region = "Count",  custom = "CustomCountText",  hide = "HideCountText",  font = "CountFont",  size = "CountSize",  outline = "CountOutline",  color = "CountColor",  defaultSize = 14 },
}

local trackedButtons = {}                                   -- array of { frame = button, type = "action"|"pet"|"stance"|"custom" }
local buttonState = setmetatable({}, { __mode = "k" })      -- button -> WT bookkeeping (never stored on Blizzard frames)

local function GetState(button)
    local state = buttonState[button]
    if not state then
        state = {}
        buttonState[button] = state
    end
    return state
end

local function DB()
    return WT.DB.ActionBars
end

local function ToRGBA(color, r, g, b, a)
    if type(color) == "table" then
        return color.r or r, color.g or g, color.b or b, color.a or a
    elseif type(color) == "string" then
        local hr, hg, hb = WT.Colors:HexToRGB(color)
        return hr, hg, hb, a
    end
    return r, g, b, a
end

local function FetchFont(fontKey)
    return (WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", fontKey)) or "Fonts\\FRIZQT__.TTF"
end

local function NormalizeOutline(outline)
    if outline == "NONE" then return "" end
    return outline or "OUTLINE"
end

-- ----------------------------------------------------------------------------
-- Text styling (macro names, hotkeys, charges)
-- ----------------------------------------------------------------------------
-- The first time WT touches a font string, its Blizzard font, color and alpha are saved;
-- turning the options off restores exactly that state.
local function SaveTextState(state, key, fontString)
    if state[key] then return end
    local font, size, flags = fontString:GetFont()
    local r, g, b, a = fontString:GetTextColor()
    state[key] = { font = font, size = size, flags = flags, r = r, g = g, b = b, a = a, alpha = fontString:GetAlpha() }
end

local function RestoreTextState(state, key, fontString)
    local saved = state[key]
    if not saved then return end
    if saved.font then fontString:SetFont(saved.font, saved.size, saved.flags) end
    -- The hotkey color depends on the range state and is restored by UpdateHotkeyColor
    if key ~= "HotKey" then fontString:SetTextColor(saved.r, saved.g, saved.b, saved.a) end
    fontString:SetAlpha(saved.alpha)
    state[key] = nil
end

local hotkeyCache = {}
local function ShortenHotkey(text)
    if not text or text == "" or text == RANGE_INDICATOR then return text end
    if hotkeyCache[text] then return hotkeyCache[text] end

    local short = text
    short = string.gsub(short, "(s%-)", "S-")
    short = string.gsub(short, "(a%-)", "A-")
    short = string.gsub(short, "(c%-)", "C-")
    short = string.gsub(short, "Mouse Button ", "M")
    short = string.gsub(short, "Middle Mouse", "M3")
    short = string.gsub(short, "Num Pad ", "N")
    short = string.gsub(short, "Page Up", "PU")
    short = string.gsub(short, "Page Down", "PD")
    short = string.gsub(short, "Spacebar", "Spc")
    short = string.gsub(short, "Insert", "Ins")
    short = string.gsub(short, "Home", "Hm")
    short = string.gsub(short, "Delete", "Del")
    short = string.gsub(short, "Num Lock", "NL")

    -- Key names of the German client (binding texts are localized by the game)
    if GetLocale() == "deDE" then
        short = string.gsub(short, "Mittlere Maustaste", "M3")
        short = string.gsub(short, "Maustaste ", "M")
        short = string.gsub(short, "Bild auf", "PU")
        short = string.gsub(short, "Bild ab", "PD")
        short = string.gsub(short, "Leertaste", "Spc")
        short = string.gsub(short, "Einfügen", "Ins")
        short = string.gsub(short, "Pos1", "Hm")
        short = string.gsub(short, "Entfernen", "Del")
        short = string.gsub(short, "Nummernblock ", "N")
    end

    hotkeyCache[text] = short
    return short
end

-- Blizzard writes the hotkey text in UpdateHotkeys(); remember it before WT shortens it.
local function CaptureHotkeyText(button, state)
    if not button.HotKey then return end
    local text = Unsecret(button.HotKey:GetText())
    if text and text ~= state.shortHotkey then
        state.rawHotkey = text
    end
end

local function UpdateHotkeyText(button, state)
    local hotkey = button.HotKey
    if not hotkey then return end

    if DB().CleanHotkeys and state.rawHotkey then
        local short = ShortenHotkey(state.rawHotkey)
        if short ~= state.rawHotkey then
            hotkey:SetText(short)
            state.shortHotkey = short
            return
        end
    end
    if state.shortHotkey then
        hotkey:SetText(state.rawHotkey or "")
        state.shortHotkey = nil
    end
end

-- Blizzard colors the hotkey grey or red (out of range) in ActionButton_UpdateRangeIndicator.
-- For font strings SetVertexColor and SetTextColor are the same color, so the custom hotkey
-- color must never be applied while the action is out of range. This is the only place that
-- sets the hotkey color.
local function UpdateHotkeyColor(button, state)
    local hotkey = button.HotKey
    if not hotkey then return end

    local db = DB()
    if state.outOfRange and RED_FONT_COLOR then
        if db.CustomHotkeyText or state.hotkeyColorChanged then
            hotkey:SetTextColor(RED_FONT_COLOR:GetRGB())
            if db.CustomHotkeyText then state.hotkeyColorChanged = true end
        end
    elseif db.CustomHotkeyText then
        hotkey:SetTextColor(ToRGBA(db.HotkeyColor, 1, 1, 1, 1))
        state.hotkeyColorChanged = true
    elseif state.hotkeyColorChanged and ACTIONBAR_HOTKEY_FONT_COLOR then
        hotkey:SetTextColor(ACTIONBAR_HOTKEY_FONT_COLOR:GetRGB())
        state.hotkeyColorChanged = nil
    end
end

local function UpdateTexts(button, state)
    local db = DB()
    for _, element in ipairs(TEXT_ELEMENTS) do
        local fontString = button[element.region]
        if fontString then
            if db[element.hide] then
                SaveTextState(state, element.region, fontString)
                fontString:SetAlpha(0)
            elseif db[element.custom] then
                SaveTextState(state, element.region, fontString)
                fontString:SetAlpha(state[element.region].alpha)
                local font, size, outline = FetchFont(db[element.font]), db[element.size] or element.defaultSize, NormalizeOutline(db[element.outline])
                local curFont, curSize, curFlags = fontString:GetFont()
                if curFont ~= font or curSize ~= size or (curFlags or "") ~= outline then
                    fontString:SetFont(font, size, outline)
                end
                -- The hotkey color depends on the range state and is handled by UpdateHotkeyColor
                if element.region ~= "HotKey" then
                    fontString:SetTextColor(ToRGBA(db[element.color], 1, 1, 1, 1))
                end
            else
                RestoreTextState(state, element.region, fontString)
            end
        end
    end
    UpdateHotkeyText(button, state)
    UpdateHotkeyColor(button, state)
end

-- ----------------------------------------------------------------------------
-- Out of range tint
-- ----------------------------------------------------------------------------
-- Same coloring as ActionBarActionButtonMixin:UpdateUsable(), used to hand the icon back to Blizzard.
local function RestoreUsableColor(button)
    local icon = button.icon
    if not icon or type(button.action) ~= "number" then return end
    local rawUsable, rawNoMana = C_ActionBar.IsUsableAction(button.action)
    local isUsable, notEnoughMana = ReadBool(rawUsable), ReadBool(rawNoMana)
    if isUsable or isUsable == nil then
        icon:SetVertexColor(1, 1, 1)
    elseif notEnoughMana then
        icon:SetVertexColor(0.5, 0.5, 1)
    else
        icon:SetVertexColor(0.4, 0.4, 0.4)
    end
end

local function UpdateRangeTint(button, state)
    local icon = button.icon
    if not icon or type(button.action) ~= "number" then return end
    if DB().OutofRangeTint and state.outOfRange then
        icon:SetVertexColor(OUT_OF_RANGE_COLOR[1], OUT_OF_RANGE_COLOR[2], OUT_OF_RANGE_COLOR[3])
        state.tinted = true
    elseif state.tinted then
        state.tinted = nil
        RestoreUsableColor(button)
    end
end

-- ----------------------------------------------------------------------------
-- Cooldown swipe and numbers
-- ----------------------------------------------------------------------------
local function UpdateSwipe(button, state)
    local cooldown = button.cooldown
    if not cooldown then return end
    local db = DB()

    if db.CustomCooldown then
        -- Blizzard hides the swipe while the cast animation plays; leave that alone
        if not button.hideCooldownFrame then
            cooldown:SetSwipeTexture(SOLID_TEXTURE)
            cooldown:SetSwipeColor(ToRGBA(db.CooldownSwipeColor, 0, 0, 0, 0.8))
        end
        cooldown:SetDrawEdge(db.CooldownEdge and true or false)
        if cooldown.SetUseCircularEdge then cooldown:SetUseCircularEdge(false) end
        state.swipeChanged = true
    elseif state.swipeChanged then
        cooldown:SetSwipeTexture(SOLID_TEXTURE)
        cooldown:SetSwipeColor(BLIZZ_SWIPE_COLOR[1], BLIZZ_SWIPE_COLOR[2], BLIZZ_SWIPE_COLOR[3], BLIZZ_SWIPE_COLOR[4])
        cooldown:SetDrawEdge(false)
        state.swipeChanged = nil
    end
end

-- Blizzard shows the numbers according to the "countdownForCooldowns" game setting
-- (ActionButton_UpdateCooldownNumberHidden). WT only hides them while its own cooldown text is shown.
local function UpdateCountdownNumbers(button, state)
    local cooldown = button.cooldown
    if not cooldown then return end
    if DB().CustomCooldownText then
        cooldown:SetHideCountdownNumbers(true)
        state.numbersHidden = true
    elseif state.numbersHidden then
        cooldown:SetHideCountdownNumbers(not GetCVarBool("countdownForCooldowns"))
        state.numbersHidden = nil
    end
end

-- ----------------------------------------------------------------------------
-- Own cooldown text and icon desaturation (driven by a throttled ticker)
-- ----------------------------------------------------------------------------
local actionCache = {}     -- action slot -> { type, id }; GetActionInfo results cached for combat
local petActionCache = {}

local function IsCooldownTickerNeeded()
    local db = DB()
    return db.CustomCooldownText or db.DesaturateCooldown
end

local function UpdateActionCache()
    if InCombatLockdown() or not IsCooldownTickerNeeded() then return end
    for i = 1, 200 do
        local actionType, id = GetActionInfo(i)
        actionCache[i] = actionType and { type = actionType, id = id } or nil
    end
    for i = 1, 10 do
        local _, _, _, _, _, _, spellID = GetPetActionInfo(i)
        petActionCache[i] = spellID
    end
end

local function FormatCooldownTime(remain)
    if remain > 86400 then return string.format("%dd", math.ceil(remain / 86400))
    elseif remain > 3600 then return string.format("%dh", math.ceil(remain / 3600))
    elseif remain > 60 then return string.format("%dm", math.ceil(remain / 60))
    elseif remain >= 3 then return tostring(math.ceil(remain))
    elseif remain > 0 then return string.format("%.1f", remain)
    end
    return ""
end

local function ReadSpellCooldown(spellID)
    local start, duration, chargeStart, chargeDuration = 0, 0, 0, 0
    local info = C_Spell.GetSpellCooldown(spellID)
    if info then start, duration = SafeNum(info.startTime) or 0, SafeNum(info.duration) or 0 end
    local charges = C_Spell.GetSpellCharges(spellID)
    if charges then
        local current, max = SafeNum(charges.currentCharges), SafeNum(charges.maxCharges)
        if current and max and current < max then
            chargeStart, chargeDuration = SafeNum(charges.cooldownStartTime) or 0, SafeNum(charges.cooldownDuration) or 0
        end
    end
    return start, duration, chargeStart, chargeDuration
end

local function ReadItemCooldown(itemID)
    local start, duration = C_Container.GetItemCooldown(itemID)
    return SafeNum(start) or 0, SafeNum(duration) or 0, 0, 0
end

local function ReadActionCooldown(button, buttonType)
    if buttonType == "action" and type(button.action) == "number" then
        local actionType, id
        if InCombatLockdown() then
            local cached = actionCache[button.action]
            if cached then actionType, id = cached.type, cached.id end
        else
            actionType, id = GetActionInfo(button.action)
        end

        if actionType == "spell" and type(id) == "number" then
            return ReadSpellCooldown(id)
        elseif actionType == "item" and type(id) == "number" then
            return ReadItemCooldown(id)
        elseif actionType == "macro" and type(id) == "number" and not InCombatLockdown() then
            local spellID = GetMacroSpell(id)
            if spellID and spellID > 0 then return ReadSpellCooldown(spellID) end
            local itemName, itemLink = GetMacroItem(id)
            local itemID = tonumber(string.match(type(itemLink) == "string" and itemLink or (itemName or ""), "item:(%d+)") or "")
            if itemID then return ReadItemCooldown(itemID) end
        end
    elseif buttonType == "pet" then
        local spellID
        if InCombatLockdown() then
            spellID = petActionCache[button:GetID()]
        else
            local _, _, _, _, _, _, petSpellID = GetPetActionInfo(button:GetID())
            spellID = petSpellID
        end
        if type(spellID) == "number" then return ReadSpellCooldown(spellID) end
        if not button:IsProtected() then
            local start, duration = GetPetActionCooldown(button:GetID())
            return SafeNum(start) or 0, SafeNum(duration) or 0, 0, 0
        end
    elseif not button:IsProtected() and not InCombatLockdown() then
        local start, duration, chargeStart, chargeDuration = 0, 0, 0, 0
        if button.cooldown and button.cooldown:IsShown() then
            local s, d = button.cooldown:GetCooldownTimes()
            start, duration = (SafeNum(s) or 0) / 1000, (SafeNum(d) or 0) / 1000
        end
        if button.chargeCooldown and button.chargeCooldown:IsShown() then
            local s, d = button.chargeCooldown:GetCooldownTimes()
            chargeStart, chargeDuration = (SafeNum(s) or 0) / 1000, (SafeNum(d) or 0) / 1000
        end
        return start, duration, chargeStart, chargeDuration
    end
    return 0, 0, 0, 0
end

local function EnsureCooldownText(button, state)
    if not state.cooldownText then
        state.cooldownFrame = CreateFrame("Frame", nil, button)
        state.cooldownFrame:SetAllPoints(button)
        state.cooldownText = state.cooldownFrame:CreateFontString(nil, "OVERLAY")
        state.cooldownText:SetPoint("CENTER", state.cooldownFrame, "CENTER", 1, 0)
    end
    local level = button.cooldown and button.cooldown:GetFrameLevel() or button:GetFrameLevel()
    if button.chargeCooldown then level = math.max(level, button.chargeCooldown:GetFrameLevel()) end
    state.cooldownFrame:SetFrameLevel(level + 5)

    local db = DB()
    state.cooldownText:SetFont(FetchFont(db.CooldownFont), db.CooldownFontSize or 14, NormalizeOutline(db.CooldownFontOutline))
    local r, g, b = ToRGBA(db.CooldownTextColor, 1, 1, 0, 1)
    state.cooldownText:SetTextColor(r, g, b)
    state.cooldownText:Show()
end

local function SetDesaturated(button, state, desaturated)
    if (state.desaturated or false) == desaturated then return end
    local icon = button.icon or button.Icon
    if icon then icon:SetDesaturated(desaturated) end
    state.desaturated = desaturated or nil
end

local function CooldownTick()
    local db = DB()
    local doText, doDesaturate = db.CustomCooldownText, db.DesaturateCooldown
    local threshold = db.CooldownMinDuration or 1.5
    local now = GetTime()

    for i = 1, #trackedButtons do
        local entry = trackedButtons[i]
        local button = entry.frame
        local state = GetState(button)
        local remain = 0

        local cooldownShown = (button.cooldown and button.cooldown:IsShown()) or (button.chargeCooldown and button.chargeCooldown:IsShown())
        if button:IsVisible() and cooldownShown then
            local start, duration, chargeStart, chargeDuration = ReadActionCooldown(button, entry.type)
            if duration > threshold then remain = math.max(remain, start + duration - now) end
            if chargeDuration > threshold then remain = math.max(remain, chargeStart + chargeDuration - now) end
        end

        if doText and state.cooldownText then
            local text = FormatCooldownTime(remain)
            if state.lastCooldownText ~= text then
                state.cooldownText:SetText(text)
                state.lastCooldownText = text
            end
        end
        SetDesaturated(button, state, doDesaturate and remain > 0 or false)
    end
end

function Module:UpdateCooldownTicker()
    local db = DB()
    for _, entry in ipairs(trackedButtons) do
        local state = GetState(entry.frame)
        if db.CustomCooldownText then
            EnsureCooldownText(entry.frame, state)
        elseif state.cooldownText then
            state.cooldownText:SetText("")
            state.cooldownText:Hide()
            state.lastCooldownText = nil
        end
        if not db.DesaturateCooldown then SetDesaturated(entry.frame, state, false) end
    end

    if IsCooldownTickerNeeded() then
        UpdateActionCache()
        self:RegisterOnUpdate(CooldownTick, COOLDOWN_TICK_INTERVAL)
    else
        self:UnregisterOnUpdate(CooldownTick)
    end
end

-- ----------------------------------------------------------------------------
-- Buttons and hooks
-- ----------------------------------------------------------------------------
local function UpdateButton(button)
    local state = GetState(button)
    UpdateTexts(button, state)
    UpdateRangeTint(button, state)
    UpdateSwipe(button, state)
    UpdateCountdownNumbers(button, state)
end

local hookedButtons = setmetatable({}, { __mode = "k" })
local function HookButton(button)
    if hookedButtons[button] then return end
    hookedButtons[button] = true
    -- Instance hooks: the mixin methods are copied onto every button when it is created,
    -- so hooking ActionBarActionButtonMixin itself would never reach the existing buttons.
    if type(button.UpdateHotkeys) == "function" then
        hooksecurefunc(button, "UpdateHotkeys", function(self)
            local state = GetState(self)
            CaptureHotkeyText(self, state)
            UpdateTexts(self, state)
        end)
    end
    if type(button.Update) == "function" then
        hooksecurefunc(button, "Update", function(self) UpdateTexts(self, GetState(self)) end)
    end
    if type(button.UpdateUsable) == "function" then
        hooksecurefunc(button, "UpdateUsable", function(self) UpdateRangeTint(self, GetState(self)) end)
    end
end

local function CollectButtons()
    wipe(trackedButtons)
    for _, prefix in ipairs(BUTTON_PREFIXES) do
        for i = 1, 12 do
            local button = _G[prefix .. i]
            if button then
                local buttonType = "action"
                if prefix == "PetActionButton" then buttonType = "pet"
                elseif prefix == "StanceButton" then buttonType = "stance"
                elseif type(button.action) ~= "number" then buttonType = "custom" end
                trackedButtons[#trackedButtons + 1] = { frame = button, type = buttonType }
            end
        end
    end

    local zoneAbility = _G["ZoneAbilityFrame"] and _G["ZoneAbilityFrame"].SpellButton
    local special = { _G["ExtraActionButton1"], zoneAbility }
    for i = 1, 6 do special[#special + 1] = _G["OverrideActionBarButton" .. i] end
    for _, button in pairs(special) do
        if button then trackedButtons[#trackedButtons + 1] = { frame = button, type = "action" } end
    end

    for _, entry in ipairs(trackedButtons) do
        CaptureHotkeyText(entry.frame, GetState(entry.frame))
    end
end

local globalHooksInstalled = false
local function InstallGlobalHooks()
    if globalHooksInstalled then return end
    globalHooksInstalled = true

    -- Range state arrives here for every action button; checksRange/inRange may be secret values
    if ActionButton_UpdateRangeIndicator then
        hooksecurefunc("ActionButton_UpdateRangeIndicator", function(button, checksRange, inRange)
            if not buttonState[button] then return end
            local state = GetState(button)
            state.outOfRange = (ReadBool(checksRange) and ReadBool(inRange) == false) or false
            UpdateHotkeyColor(button, state)
            UpdateRangeTint(button, state)
        end)
    end
    -- Blizzard resets the swipe color after the cast animation and then calls this
    if ActionButton_UpdateCooldown then
        hooksecurefunc("ActionButton_UpdateCooldown", function(button)
            if buttonState[button] then UpdateSwipe(button, GetState(button)) end
        end)
    end
    -- Called when the "countdownForCooldowns" game setting changes
    if ActionButton_UpdateCooldownNumberHidden then
        hooksecurefunc("ActionButton_UpdateCooldownNumberHidden", function(button)
            if buttonState[button] then UpdateCountdownNumbers(button, GetState(button)) end
        end)
    end
end

-- Options that need the button hooks. Hooks are only installed once one of them is enabled.
local BUTTON_OPTIONS = {
    "CustomMacroText", "HideMacroText", "CustomHotkeyText", "HideHotkeyText", "CleanHotkeys",
    "CustomCountText", "HideCountText", "OutofRangeTint", "CustomCooldown", "CustomCooldownText",
}

local function IsAnyButtonOptionActive()
    local db = DB()
    for _, key in ipairs(BUTTON_OPTIONS) do
        if db[key] then return true end
    end
    return false
end

--- Applies all text, range and cooldown settings to every action button.
--- With every option off this only reverts earlier changes and installs nothing.
function Module:UpdateAllBars()
    local active = IsAnyButtonOptionActive()
    if active then InstallGlobalHooks() end
    for _, entry in ipairs(trackedButtons) do
        if active then HookButton(entry.frame) end
        UpdateButton(entry.frame)
    end
    self:UpdateCooldownTicker()
end

-- ----------------------------------------------------------------------------
-- Spell queue window (CVar)
-- ----------------------------------------------------------------------------
-- The slider shows and changes the game's own setting. WT never writes it on login;
-- the stored value only mirrors the current game setting for the options page.
local SQW_CVAR = "SpellQueueWindow"

local function ReadSpellQueueWindow()
    local value = tonumber(C_CVar.GetCVar(SQW_CVAR))
    if value then DB().SpellQueueWindow = value end
end

local function RefreshSpellQueueSlider()
    local registry = WT.Config.Builder and WT.Config.Builder.Registry
    local slider = registry and registry.Sliders and registry.Sliders.ActionBars and registry.Sliders.ActionBars.SpellQueueWindow
    if slider and slider:GetValue() ~= DB().SpellQueueWindow then slider:SetValue(DB().SpellQueueWindow) end
end

local function WriteSpellQueueWindow()
    if WT.Core.CombatQueue:Add("ActionBarsSpellQueueWindow", false, WriteSpellQueueWindow) then return end
    local value = tostring(DB().SpellQueueWindow)
    if C_CVar.GetCVar(SQW_CVAR) ~= value then WT.Utils.Flags:SetCVar(SQW_CVAR, value) end
end

-- ----------------------------------------------------------------------------
-- Masque support
-- ----------------------------------------------------------------------------
local masqueGroups
local masqueButtons = {}   -- button -> group

local function GetMasque()
    return LibStub and LibStub("Masque", true)
end

function Module:UpdateMasque()
    local masque = GetMasque()
    if not masque then return end

    if not DB().MasqueSupport then
        for button, group in pairs(masqueButtons) do group:RemoveButton(button) end
        wipe(masqueButtons)
        return
    end

    masqueGroups = masqueGroups or {
        actionBars = masque:Group("WT (W1LD Tools)", "ActionBars"),
        bags = masque:Group("WT (W1LD Tools)", "BagsBar"),
        extra = masque:Group("WT (W1LD Tools)", "Extra Abilities"),
        misc = masque:Group("WT (W1LD Tools)", "Misc"),
    }
    local function Add(button, group)
        if button and not masqueButtons[button] then
            group:AddButton(button)
            masqueButtons[button] = group
        end
    end

    for _, prefix in ipairs(BUTTON_PREFIXES) do
        local count = (prefix == "PetActionButton" or prefix == "StanceButton") and 10 or 12
        for i = 1, count do Add(_G[prefix .. i], masqueGroups.actionBars) end
    end
    for _, name in ipairs({ "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot", "CharacterReagentBag0Slot" }) do
        Add(_G[name], masqueGroups.bags)
    end
    Add(_G["ExtraActionButton1"], masqueGroups.extra)
    Add(_G["MainMenuBarVehicleLeaveButton"], masqueGroups.misc)
end

-- ----------------------------------------------------------------------------
-- Vehicle exit button protection
-- ----------------------------------------------------------------------------
-- Keeps the vehicle exit icon visible when other addons (mainly Masque skins) hide or clear it.
local vehicleState = {}

local function GetVehicleButton()
    return _G["MainMenuBarVehicleLeaveButton"] or _G["OverrideActionBarLeaveFrameLeaveButton"]
end

local function IsVehicleProtectionActive()
    return DB().ProtectVehicleButton
end

local function GetNativeVehicleArt(button)
    local region = button.icon or button.Icon
    local atlas = region and region.GetAtlas and region:GetAtlas()
    local texture = region and region.GetTexture and region:GetTexture()
    if not atlas and not texture and button.GetNormalTexture and button:GetNormalTexture() then
        local normal = button:GetNormalTexture()
        atlas = normal.GetAtlas and normal:GetAtlas()
        texture = normal.GetTexture and normal:GetTexture()
    end
    return atlas, texture
end

-- Masque skin: Masque skins the button background, WT draws the exit icon on top.
local function ProtectWithMasque(button)
    if not vehicleState.icon then
        vehicleState.icon = button:CreateTexture(nil, "OVERLAY", nil, 7)
        vehicleState.icon:SetAllPoints(button)
    end
    local atlas, texture = GetNativeVehicleArt(button)
    vehicleState.atlas = atlas or ((not texture) and "UI-HUD-Vehicle-Exit-Up" or nil)
    vehicleState.texture = (not atlas) and texture or nil
    if vehicleState.atlas then vehicleState.icon:SetAtlas(vehicleState.atlas) else vehicleState.icon:SetTexture(vehicleState.texture) end
    vehicleState.icon:Show()

    local nativeIcon = button.icon or button.Icon
    if nativeIcon then
        if vehicleState.nativeIconAlpha == nil then vehicleState.nativeIconAlpha = nativeIcon:GetAlpha() end
        nativeIcon:SetAlpha(0)
        if not vehicleState.nativeIconHooked then
            vehicleState.nativeIconHooked = true
            hooksecurefunc(nativeIcon, "SetAlpha", function(self, alpha)
                if IsVehicleProtectionActive() and GetMasque() and alpha > 0 then self:SetAlpha(0) end
            end)
        end
    end
end

-- No skin addon: keep Blizzard's own normal texture visible and on top.
local function ProtectWithoutMasque(button)
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if not normal then return end
    if vehicleState.drawLayer == nil then
        vehicleState.drawLayer, vehicleState.subLevel = normal:GetDrawLayer()
    end
    normal:SetAlpha(1)
    normal:Show()
    normal:SetDrawLayer("OVERLAY", 7)

    if not vehicleState.normalHooked then
        vehicleState.normalHooked = true
        hooksecurefunc(normal, "SetAlpha", function(self, alpha)
            if IsVehicleProtectionActive() and not InCombatLockdown() and alpha == 0 and button:IsShown() then self:SetAlpha(1) end
        end)
    end
end

function Module:UpdateVehicleButton()
    local button = GetVehicleButton()
    if not button then return end

    if IsVehicleProtectionActive() then
        if GetMasque() then ProtectWithMasque(button) else ProtectWithoutMasque(button) end
        return
    end

    -- Option off: hand everything back to Blizzard
    if vehicleState.icon then vehicleState.icon:Hide() end
    local nativeIcon = button.icon or button.Icon
    if nativeIcon and vehicleState.nativeIconAlpha ~= nil then
        nativeIcon:SetAlpha(vehicleState.nativeIconAlpha)
        vehicleState.nativeIconAlpha = nil
    end
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal and vehicleState.drawLayer ~= nil then
        normal:SetDrawLayer(vehicleState.drawLayer, vehicleState.subLevel)
        vehicleState.drawLayer, vehicleState.subLevel = nil, nil
    end
end

-- ----------------------------------------------------------------------------
-- Module
-- ----------------------------------------------------------------------------
function Module:OnEnable()
    ReadSpellQueueWindow()
    RefreshSpellQueueSlider()

    CollectButtons()
    self:UpdateAllBars()
    self:UpdateMasque()
    self:UpdateVehicleButton()

    self:RegisterEvent("CVAR_UPDATE", function(_, cvar)
        if cvar == SQW_CVAR then
            ReadSpellQueueWindow()
            RefreshSpellQueueSlider()
        end
    end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", UpdateActionCache)
    self:RegisterEvent("ACTIONBAR_SLOT_CHANGED", UpdateActionCache)
    self:RegisterEvent("PET_BAR_UPDATE", UpdateActionCache)
end

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
    local function UpdateAll() self:UpdateAllBars() end

    -- Show the game's current value, not WT's stored default
    ReadSpellQueueWindow()

    panel:CreateTitle(builder, WT.L.GROUP_ACTIONBARS_BEHAVIOR)
    AddDescription(WT.L.OPT_DESC_GROUP_ACTIONBARS_BEHAVIOR)

    panel:CreateSlider(builder, WT.L.OPT_ACTIONBARS_SQW, WT.L.OPT_DESC_ACTIONBARS_SQW, "ActionBars", "SpellQueueWindow", 0, 400, 10, WriteSpellQueueWindow)

    panel:CreateCheckbox(builder, WT.L.OPT_AB_MASQUE_SUPPORT, WT.L.OPT_DESC_AB_MASQUE_SUPPORT, "ActionBars", "MasqueSupport", function() self:UpdateMasque() end)
    panel:CreateCheckbox(builder, WT.L.OPT_AB_PROTECT_VEHICLE, WT.L.OPT_DESC_AB_PROTECT_VEHICLE, "ActionBars", "ProtectVehicleButton", function() self:UpdateVehicleButton() end)
    panel:CreateCheckbox(builder, WT.L.OPT_AB_OOR_TINT, WT.L.OPT_DESC_AB_OOR_TINT, "ActionBars", "OutofRangeTint", UpdateAll)

    panel:CreateTitle(builder, WT.L.GROUP_ACTIONBARS_TEXT)
    AddDescription(WT.L.OPT_DESC_GROUP_ACTIONBARS_TEXT)

    local fontOptions = WT.Utils.SharedMedia:GetOptions("font")
    local cmInit = panel:CreateCheckbox(builder, WT.L.OPT_AB_CUSTOM_MACRO, WT.L.OPT_DESC_AB_CUSTOM_MACRO, "ActionBars", "CustomMacroText", UpdateAll)
    panel:CreateCheckbox(builder, WT.L.OPT_AB_HIDE_MACRO, WT.L.OPT_DESC_AB_HIDE_MACRO, "ActionBars", "HideMacroText", UpdateAll)
    panel:CreateDropdown(builder, WT.L.OPT_AB_MACRO_FONT, WT.L.OPT_DESC_AB_MACRO_FONT, "ActionBars", "MacroFont", fontOptions, UpdateAll, cmInit)
    panel:CreateSlider(builder, WT.L.OPT_AB_MACRO_SIZE, WT.L.OPT_DESC_AB_MACRO_SIZE, "ActionBars", "MacroSize", 8, 24, 1, UpdateAll, cmInit)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "ActionBars", "MacroOutline", UpdateAll, cmInit)
    panel:CreateColorPicker(builder, WT.L.OPT_AB_MACRO_COLOR, WT.L.OPT_DESC_AB_MACRO_COLOR, "ActionBars", "MacroColor", false, cmInit, UpdateAll)

    local chInit = panel:CreateCheckbox(builder, WT.L.OPT_AB_CUSTOM_HOTKEY, WT.L.OPT_DESC_AB_CUSTOM_HOTKEY, "ActionBars", "CustomHotkeyText", UpdateAll)
    panel:CreateCheckbox(builder, WT.L.OPT_AB_HIDE_HOTKEY, WT.L.OPT_DESC_AB_HIDE_HOTKEY, "ActionBars", "HideHotkeyText", UpdateAll)
    panel:CreateCheckbox(builder, WT.L.OPT_AB_CLEAN_HOTKEYS, WT.L.OPT_DESC_AB_CLEAN_HOTKEYS, "ActionBars", "CleanHotkeys", UpdateAll)
    panel:CreateDropdown(builder, WT.L.OPT_AB_HOTKEY_FONT, WT.L.OPT_DESC_AB_HOTKEY_FONT, "ActionBars", "HotkeyFont", fontOptions, UpdateAll, chInit)
    panel:CreateSlider(builder, WT.L.OPT_AB_HOTKEY_SIZE, WT.L.OPT_DESC_AB_HOTKEY_SIZE, "ActionBars", "HotkeySize", 8, 24, 1, UpdateAll, chInit)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "ActionBars", "HotkeyOutline", UpdateAll, chInit)
    panel:CreateColorPicker(builder, WT.L.OPT_AB_HOTKEY_COLOR, WT.L.OPT_DESC_AB_HOTKEY_COLOR, "ActionBars", "HotkeyColor", false, chInit, UpdateAll)

    local ccInit = panel:CreateCheckbox(builder, WT.L.OPT_AB_CUSTOM_COUNT, WT.L.OPT_DESC_AB_CUSTOM_COUNT, "ActionBars", "CustomCountText", UpdateAll)
    panel:CreateCheckbox(builder, WT.L.OPT_AB_HIDE_COUNT, WT.L.OPT_DESC_AB_HIDE_COUNT, "ActionBars", "HideCountText", UpdateAll)
    panel:CreateDropdown(builder, WT.L.OPT_AB_COUNT_FONT, WT.L.OPT_DESC_FONT, "ActionBars", "CountFont", fontOptions, UpdateAll, ccInit)
    panel:CreateSlider(builder, WT.L.OPT_AB_COUNT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "ActionBars", "CountSize", 8, 24, 1, UpdateAll, ccInit)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "ActionBars", "CountOutline", UpdateAll, ccInit)
    panel:CreateColorPicker(builder, WT.L.OPT_AB_COUNT_COLOR, WT.L.OPT_DESC_COLOR_VALUE, "ActionBars", "CountColor", false, ccInit, UpdateAll)

    panel:CreateTitle(builder, WT.L.GROUP_ACTIONBARS_COOLDOWN)
    AddDescription(WT.L.OPT_DESC_GROUP_ACTIONBARS_COOLDOWN)

    panel:CreateCheckbox(builder, WT.L.OPT_AB_DESATURATE_COOLDOWN, WT.L.OPT_DESC_AB_DESATURATE_COOLDOWN, "ActionBars", "DesaturateCooldown", UpdateAll)
    local cdtInit = panel:CreateCheckbox(builder, WT.L.OPT_AB_CUSTOM_COOLDOWN_TEXT, WT.L.OPT_DESC_AB_CUSTOM_COOLDOWN_TEXT, "ActionBars", "CustomCooldownText", UpdateAll)
    panel:CreateDropdown(builder, WT.L.OPT_AB_CD_FONT, WT.L.OPT_DESC_FONT, "ActionBars", "CooldownFont", fontOptions, UpdateAll, cdtInit)
    panel:CreateSlider(builder, WT.L.OPT_AB_CD_SIZE, WT.L.OPT_DESC_FONT_SIZE, "ActionBars", "CooldownFontSize", 10, 36, 1, UpdateAll, cdtInit)
    panel:CreateSlider(builder, WT.L.OPT_AB_CD_MIN_DURATION, WT.L.OPT_DESC_AB_CD_MIN_DURATION, "ActionBars", "CooldownMinDuration", 0, 5, 0.1, UpdateAll, cdtInit)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "ActionBars", "CooldownFontOutline", UpdateAll, cdtInit)
    panel:CreateColorPicker(builder, WT.L.OPT_AB_CD_COLOR, WT.L.OPT_DESC_COLOR_VALUE, "ActionBars", "CooldownTextColor", false, cdtInit, UpdateAll)

    local cdInit = panel:CreateCheckbox(builder, WT.L.OPT_AB_CUSTOM_COOLDOWN, WT.L.OPT_DESC_AB_CUSTOM_COOLDOWN, "ActionBars", "CustomCooldown", UpdateAll)
    panel:CreateColorPicker(builder, WT.L.OPT_AB_COOLDOWN_SWIPE, WT.L.OPT_DESC_AB_COOLDOWN_SWIPE, "ActionBars", "CooldownSwipeColor", true, cdInit, UpdateAll)
    panel:CreateCheckbox(builder, WT.L.OPT_AB_COOLDOWN_EDGE, WT.L.OPT_DESC_AB_COOLDOWN_EDGE, "ActionBars", "CooldownEdge", UpdateAll, cdInit)
end
