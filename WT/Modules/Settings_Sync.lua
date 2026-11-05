local addonName, WT = ...

WT.Modules.SettingsSync = {}
local Module = WT.Modules.SettingsSync

local strsplit = strsplit or string.split or function(d, s)
    if not s then return nil end
    local t, i = {}, 1
    while true do
        local j = string.find(s, d, i, true)
        if not j then
            table.insert(t, string.sub(s, i))
            break
        end
        table.insert(t, string.sub(s, i, j - 1))
        i = j + #d
    end
    return (unpack or rawget(table, "unpack"))(t)
end

-- Blacklist to prevent syncing hardware, graphics, and system-specific CVars
local CVarBlacklist = {
    "^gx", "^hw", "^sound", "^audio", "^voice", "^mouse", "rawmouse",
    "farclip", "shadow", "particle", "ssao", "msaa", "componenttexture",
    "scripterrors", "taintlog", "accountname", "realmname", "graphics",
    "^showactionbar", "^multibar", "^actionbar", "^compactraid", "^raidoptionshown"
}

local function IsBlacklisted(cvarName)
    local c = string.lower(cvarName)
    for _, pattern in ipairs(CVarBlacklist) do
        if string.find(c, pattern) then return true end
    end
    return false
end

-- Explicitly add Settings API options that might be hidden from C_Console in modern WoW (10.0 - 12.1+)
-- Note: Do NOT include secure action bar visibility toggles (showActionBar2..8) here, as toggling them via
-- addon code taints MultiActionBar_Update and triggers [ADDON_ACTION_BLOCKED] on MultiBarBottomLeft:ShowBase().
local ExtraSettingsToSync = {
    -- Raid Frames
    "raidFramesDisplayIncomingHeals", "raidFramesDisplayPowerBars", "raidFramesDisplayOnlyHealerPowerBars",
    "raidFramesDisplayAggroHighlight", "raidFramesDisplayClassColor", "raidOptionShowPets",
    "raidOptionDisplayMainTankAndAssist", "raidFramesDisplayDebuffs", "raidFramesDisplayMajorDebuffs",
    "raidFramesDisplayOnlyDispellableDebuffs", "raidOptionShowBorders", "raidFramesHealthText",
    "raidOptionKeepGroupsTogether", "raidOptionLocked",
    
    -- Action Bars (Safe CVars only, no secure bar visibility toggles)
    "alwaysShowActionBars", "countdownForCooldowns", "lockActionBars", 
    "ActionButtonUseKeyDown",
    
    -- Modern WoW Gameplay/Combat Options (Often hidden from standard CVars)
    "autoLootDefault", "SpellQueueWindow", "empowerTapControls",
    "pingSystemEnable", "clickCastEnabled", "SoftTargetEnemy", "SoftTargetInteract"
}

local function SaveSettings()
    if not WT.DB.Sync then WT.DB.Sync = {} end
    local syncDB = WT.DB.Sync

    -- Mark current character as Master for auto-saving
    local name = UnitName("player")
    local realm = GetNormalizedRealmName() or GetRealmName()
    if name and realm then
        syncDB.MasterCharacter = name .. "-" .. realm
    end

    -- 1. CHAT SETTINGS
    local chatSettings = {}
    for i = 1, NUM_CHAT_WINDOWS do
        local name, fontSize, r, g, b, alpha, shown, locked, docked, uninteractable = FCF_GetChatWindowInfo(i)
        if name and name ~= "" and i ~= 2 then
            local messages = { GetChatWindowMessages(i) }
            local chanData = { GetChatWindowChannels(i) }
            local channels = {}
            for _, chan in ipairs(chanData) do
                if type(chan) == "string" then
                    local baseChan = string.match(chan, "^(.-) %- ") or chan
                    table.insert(channels, baseChan)
                end
            end
            local frame = _G["ChatFrame" .. i]
            chatSettings[i] = {
                name = name,
                fontSize = fontSize,
                r = r,
                g = g,
                b = b,
                alpha = alpha,
                shown = shown,
                locked = locked,
                isDocked = frame and frame.isDocked,
                uninteractable = uninteractable,
                messages = messages,
                channels = channels
            }
        end
    end
    syncDB.Chat = chatSettings

    -- 2. MACROS (Character Specific: 121 to 150)
    local macros = {}
    for i = 121, 150 do
        local name, icon, body = GetMacroInfo(i)
        if name then
            table.insert(macros, { name = name, icon = icon, body = body })
        end
    end
    syncDB.Macros = macros

    -- 3. EDIT MODE LAYOUT
    if EditModeManagerFrame and EditModeManagerFrame.GetActiveLayoutInfo then
        local layout = EditModeManagerFrame:GetActiveLayoutInfo()
        if layout and layout.layoutName then
            syncDB.EditModeLayout = layout.layoutName
        end
    end

    -- 4. CVARS (Dynamic Blacklist Approach)
    local cvars = {}
    local commands = _G["C_Console"] and _G["C_Console"]["GetAllCommands"] and _G["C_Console"]["GetAllCommands"]()
    if commands then
        for _, cmd in ipairs(commands) do
            local cv = cmd.command
            if cv and type(cv) == "string" and not IsBlacklisted(cv) then
                local val = C_CVar.GetCVar(cv)
                local default = C_CVar.GetCVarDefault(cv)
                -- Only save if it's a valid CVar and differs from the default
                if val and default and val ~= default then
                    cvars[cv] = val
                end
            end
        end
    end

    -- Explicitly add Extra Settings API options that might be hidden from C_Console in modern WoW
    for _, cv in ipairs(ExtraSettingsToSync) do
        local val = nil
        local default = C_CVar.GetCVarDefault(cv)
        if C_CVar.GetCVar(cv) ~= nil then
            val = C_CVar.GetCVar(cv)
        elseif Settings and Settings.GetSetting then
            local setting = Settings.GetSetting(cv)
            if setting then 
                val = tostring(setting:GetValue())
                default = tostring(setting:GetDefaultValue())
            end
        end
        if val ~= nil and val ~= default then
            cvars[cv] = val
        end
    end

    syncDB.CVars = cvars

    -- 5. KEYBINDINGS
    local binds = {}
    for i = 1, GetNumBindings() do
        local command, _, key1, key2 = GetBinding(i)
        if command and (key1 or key2) then
            table.insert(binds, { c = command, k1 = key1, k2 = key2 })
        end
    end
    syncDB.Keybindings = binds

    if WT.Utils and WT.Utils.Logger then
        WT.Utils.Logger:Print(WT.L.MSG_SYNC_SAVED)
    end
end

local function RestoreSettings()
    if not WT.DB.Sync then return end
    local syncDB = WT.DB.Sync

    -- 1. CHAT SETTINGS
    if WT.DB.SettingsSync.SyncChat and syncDB.Chat then
        for i = 1, NUM_CHAT_WINDOWS do
            local config = syncDB.Chat[i]
            local frame = _G["ChatFrame" .. i]
            if config and frame and i ~= 2 then
                -- DO NOT sync 'name', 'fontSize', 'color', 'alpha', 'locked', 'isDocked', or 'shown' state!
                -- HUD Edit Mode manages ChatFrames natively and iterates over them on profile switch.
                -- Modifying *any* visual or layout property on the ChatFrame table (like frame.name)
                -- from insecure code taints the frame. When Edit Mode reads this tainted frame,
                -- the execution path gets tainted and cascades into CompactUnitFrames errors!
                -- Syncing layouts dynamically also heavily corrupts the FCF DockManager.

                local targetChannels = {}
                if config.channels then
                    for _, chan in ipairs(config.channels) do
                        local baseChan = string.match(chan, "^(.-) %- ") or chan
                        targetChannels[baseChan] = true
                        targetChannels[chan] = true
                    end
                end

                local currentChannels = { GetChatWindowChannels(i) }
                local currentChanMap = {}
                for _, chan in ipairs(currentChannels) do
                    if type(chan) == "string" then
                        local baseChan = string.match(chan, "^(.-) %- ") or chan
                        currentChanMap[baseChan] = true
                        currentChanMap[chan] = true

                        if not targetChannels[baseChan] and not targetChannels[chan] then
                            ChatFrame_RemoveMessageGroup(frame, chan)
                            RemoveChatWindowChannel(i, chan)
                        end
                    end
                end

                ChatFrame_RemoveAllMessageGroups(frame)
                if config.messages then
                    for _, msg in ipairs(config.messages) do ChatFrame_AddMessageGroup(frame, msg) end
                end

                if config.channels then
                    for _, chan in ipairs(config.channels) do
                        local baseChan = string.match(chan, "^(.-) %- ") or chan
                        if not currentChanMap[baseChan] and not currentChanMap[chan] then
                            local isZoneChannel = false
                            if EnumerateServerChannels then
                                for _, sc in ipairs({ EnumerateServerChannels() }) do
                                    local scBase = string.match(sc, "^(.-) %- ") or sc
                                    if sc == chan or scBase == baseChan then
                                        isZoneChannel = true; break
                                    end
                                end
                            end
                            if not isZoneChannel then
                                -- Fallback for channels that are not available yet for this character (prevents permanent acoustic system message spam)
                                local pLevel = UnitLevel("player") or 1
                                local isRestricted = false
                                local restrictedChans = {
                                    ["LookingForGroup"] = 10,
                                    ["SucheNachGruppe"] = 10,
                                    ["Services"] = 10,
                                    ["Dienste"] = 10
                                }
                                
                                if restrictedChans[chan] and pLevel < restrictedChans[chan] then
                                    isRestricted = true
                                end
                                
                                if not isRestricted then
                                    pcall(JoinPermanentChannel, chan, nil, i, 0)
                                end
                            end
                            AddChatWindowChannel(i, chan)
                            if ChatFrame_AddChannel then ChatFrame_AddChannel(frame, chan) end
                            if frame.zoneChannelList then
                                local zc = frame.zoneChannelList[chan]
                                if zc == true or zc == 1 or zc == nil then frame.zoneChannelList[chan] = chan end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. MACROS
    if WT.DB.SettingsSync.SyncMacros and syncDB.Macros then
        local currentMacros = {}
        for i = 121, 150 do
            local name, icon, body = GetMacroInfo(i)
            if name then currentMacros[name] = { icon = icon, body = body, id = i } end
        end
        
        for _, m in ipairs(syncDB.Macros) do
            local existing = currentMacros[m.name]
            if existing then
                -- Compare body to avoid unnecessary edits; icon IDs can fluctuate depending on API version
                if existing.body ~= m.body then 
                    EditMacro(existing.id, m.name, m.icon, m.body)
                end
                currentMacros[m.name] = nil
            else
                CreateMacro(m.name, m.icon, m.body, true)
            end
        end
        
        for name, _ in pairs(currentMacros) do
            DeleteMacro(name)
        end
    end

    -- 3. EDIT MODE LAYOUT
    if syncDB.EditModeLayout then
        local target = syncDB.EditModeLayout
        -- Addons cannot programmatically change Edit Mode Layouts without causing severe taint errors.
        -- Since layouts are account-wide in WoW natively, we just notify the user to select it.
        if WT.Utils and WT.Utils.Logger then
            WT.Utils.Logger:Print("|cFF00FFFF[" .. WT.L.LBL_EDIT_MODE .. "]|r " ..
                (WT.L.MSG_SYNC_EDITMODE_PROMPT) ..
                "|cFFFFFF00" .. target .. "|r")
        end
    end

    -- 4. CVARS
    if WT.DB.SettingsSync.SyncCVars and syncDB.CVars then
        local cvarChanged = false
        
        local function ApplySetting(k, targetVal)
            if targetVal == nil or InCombatLockdown() then return end
            if IsBlacklisted(k) then return end
            
            -- FAST PATH: Check if the CVar is already correct to avoid thousands of heavy Settings API lookups
            local currentCVar = C_CVar.GetCVar(k)
            if currentCVar ~= nil and tostring(currentCVar) == tostring(targetVal) then return end
            
            -- Try Settings API first (safest for modern options like raid profiles)
            if Settings and Settings.GetSetting then
                local setting = Settings.GetSetting(k)
                if setting then
                    local currentVal = setting:GetValue()
                    local castedTarget = targetVal
                    if type(currentVal) == "boolean" then
                        castedTarget = (tostring(targetVal) == "1" or tostring(targetVal) == "true")
                    elseif type(currentVal) == "number" then
                        castedTarget = tonumber(targetVal) or currentVal
                    end
                    if tostring(currentVal) ~= tostring(castedTarget) then
                        pcall(function() setting:SetValue(castedTarget) end)
                        cvarChanged = true
                    end
                    return
                end
            end
            -- Fallback to CVar
            if tostring(C_CVar.GetCVar(k)) ~= tostring(targetVal) then
                pcall(function() C_CVar.SetCVar(k, targetVal) end)
                cvarChanged = true
            end
        end

        -- SAFE RESTORE: Only apply settings and CVars that were explicitly saved by the Master Character.
        -- Never iterate thousands of console commands to force arbitrary default values, which risks
        -- touching protected secure frames and causing taint.
        for k, targetVal in pairs(syncDB.CVars) do
            if k and type(k) == "string" and not IsBlacklisted(k) and targetVal ~= nil then
                ApplySetting(k, targetVal)
            end
        end

        if cvarChanged and WT.Utils and WT.Utils.Logger then
            WT.Utils.Logger:Print(
            "|cFF999999Some Interface/Nameplate CVars were updated. A /reload might be required if you experience UI errors.|r")
        end
    end

    -- 5. KEYBINDINGS
    if WT.DB.SettingsSync.SyncKeybinds and syncDB.Keybindings then
        local currentKeyMap = {}
        for i = 1, GetNumBindings() do
            local command, _, k1, k2 = GetBinding(i)
            if command then
                if k1 then currentKeyMap[k1] = command end
                if k2 then currentKeyMap[k2] = command end
            end
        end
        
        local targetKeyMap = {}
        for _, b in ipairs(syncDB.Keybindings) do
            if b.k1 then targetKeyMap[b.k1] = b.c end
            if b.k2 then targetKeyMap[b.k2] = b.c end
        end
        
        local bindsChanged = false
        for k, v in pairs(targetKeyMap) do if currentKeyMap[k] ~= v then bindsChanged = true; break end end
        if not bindsChanged then
            for k, v in pairs(currentKeyMap) do if targetKeyMap[k] ~= v then bindsChanged = true; break end end
        end
        
        if bindsChanged then
            for i = 1, GetNumBindings() do
                local _, _, k1, k2 = GetBinding(i)
                if k1 then SetBinding(k1, nil) end
                if k2 then SetBinding(k2, nil) end
            end
            for _, b in ipairs(syncDB.Keybindings) do
                if b.k1 then SetBinding(b.k1, b.c) end
                if b.k2 then SetBinding(b.k2, b.c) end
            end
            SaveBindings(GetCurrentBindingSet())
        end
    end

    if WT.Utils and WT.Utils.Logger then
        WT.Utils.Logger:Print(WT.L.MSG_SYNC_APPLIED)
    end
end

function Module:ForceSave() SaveSettings() end

function Module:ForceRestore()
    if InCombatLockdown() then
        if WT.Utils and WT.Utils.Logger then
            WT.Utils.Logger:Warn(WT.L.MSG_COMBAT_BLOCK)
        end
        WT.Core.CombatQueue:Add("SettingsSync", true, function() Module:ForceRestore() end)
        return
    end

    local name = UnitName("player")
    local realm = GetNormalizedRealmName() or GetRealmName()
    local currentPlayer = name and realm and (name .. "-" .. realm) or ""

    if WT.DB.Sync and WT.DB.Sync.MasterCharacter and currentPlayer == WT.DB.Sync.MasterCharacter then
        if WT.Utils and WT.Utils.Logger then
            WT.Utils.Logger:Print(WT.L.MSG_SYNC_IS_MASTER)
        end
        SaveSettings()
    else
        RestoreSettings()
    end
end

local currentPlayer = ""

-- Minimal initialization (Restore on load, Save on Master logout)
function Module:Initialize()
    if not WT.DB.Modules.SettingsSync then return end

    local initialRestoreDone = false
    WT.Core.Events:Register("PLAYER_ENTERING_WORLD", function()
        local name = UnitName("player")
        local realm = GetNormalizedRealmName() or GetRealmName()
        if name and realm then
            currentPlayer = name .. "-" .. realm
        end

        if not initialRestoreDone then
            initialRestoreDone = true

            -- Do not auto-restore if this character is the master character
            if WT.DB.Sync and WT.DB.Sync.MasterCharacter and currentPlayer == WT.DB.Sync.MasterCharacter then
                -- Master character: auto-save their settings in case anything wasn't caught,
                -- or just let them be. The user requested that we do not reset their settings.
                return
            end

            C_Timer.After(2, function()
                if InCombatLockdown() then
                    WT.Core.CombatQueue:Add("SettingsSync", true, RestoreSettings)
                else
                    RestoreSettings()
                end
            end)
        end
    end)

    WT.Core.Events:Register("PLAYER_LOGOUT", function()
        if WT.DB.Sync and WT.DB.Sync.MasterCharacter then
            if currentPlayer ~= "" and currentPlayer == WT.DB.Sync.MasterCharacter then
                SaveSettings()
            end
        end
    end)
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

    panel:CreateTitle(builder, WT.L.CATEGORY_SETTINGSSYNC)
    AddDescription(WT.L.OPT_DESC_SETTINGS_SYNC)

    panel:CreateCheckbox(builder, WT.L.OPT_SYNC_CHAT, WT.L.OPT_DESC_SYNC_CHAT,
        "SettingsSync", "SyncChat")
    AddDescription(WT.L.OPT_DESC_SYNC_CHAT_LIMIT)
    AddDescription(WT.L.OPT_DESC_SYNC_CHAT_TIP)
    panel:CreateCheckbox(builder, WT.L.OPT_SYNC_MACROS, WT.L.OPT_DESC_SYNC_MACROS,
        "SettingsSync", "SyncMacros")
    panel:CreateCheckbox(builder, WT.L.OPT_SYNC_CVARS, WT.L.OPT_DESC_SYNC_CVARS, "SettingsSync",
        "SyncCVars")
    panel:CreateCheckbox(builder, WT.L.OPT_SYNC_KEYBINDS, WT.L.OPT_DESC_SYNC_KEYBINDS,
        "SettingsSync", "SyncKeybinds")

    builder:AddSpace(20)

    local saveBtn = panel:CreateButton(builder, " ", WT.L.BTN_SYNC_SAVE, "", function()
        Module:ForceSave()
        if _G.WTSyncStatusUpdate then _G.WTSyncStatusUpdate() end
    end)

    local applyBtn = panel:CreateButton(builder, " ", WT.L.BTN_SYNC_RESTORE, "", function()
        Module:ForceRestore()
    end)

    local syncStatusTitle = builder.content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    syncStatusTitle:SetPoint("TOPLEFT", applyBtn, "BOTTOMLEFT", 0, -15)
    syncStatusTitle:SetJustifyH("LEFT")

    local syncStatusName = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    syncStatusName:SetPoint("TOPLEFT", syncStatusTitle, "BOTTOMLEFT", 20, -5)
    syncStatusName:SetJustifyH("LEFT")

    _G.WTSyncStatusUpdate = function()
        local s = WT.DB.Sync
        if s and s.MasterCharacter then
            syncStatusTitle:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:16|t |cFF00FF00" ..
                (WT.L.TXT_SYNC_SAVED) .. "|r")
            syncStatusName:SetText("|cFFFFFFFF" .. s.MasterCharacter .. "|r")
            applyBtn:Enable()
        else
            syncStatusTitle:SetText("|TInterface\\RaidFrame\\ReadyCheck-NotReady:16|t |cFF888888" ..
                (WT.L.TXT_SYNC_EMPTY) .. "|r")
            syncStatusName:SetText("")
            applyBtn:Disable()
        end
    end
    _G.WTSyncStatusUpdate()
end

WT.Core.Events:Register("PLAYER_LOGIN", function()
    Module:Initialize()
end)
