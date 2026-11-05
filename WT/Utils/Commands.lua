local _, WT = ...

WT.Utils.Commands = {}

local strtrim = strtrim or string.trim or function(s) return s and string.match(s, "^%s*(.-)%s*$") or "" end

local Unsecret = WT.Utils.Safety.Unsecret

WT.Utils.Commands.List = {}
local cmdList = WT.Utils.Commands.List

cmdList["WTRELOAD"] = function()
    if WT.Modules and WT.Modules.Chat and WT.Modules.Chat.SaveInputHistoryLine then
        pcall(WT.Modules.Chat.SaveInputHistoryLine, "/rl")
    end
    ReloadUI()
end

cmdList["WTOOLS"] = function(rawMsg)
    local msg = Unsecret(rawMsg)
    msg = msg and string.lower(strtrim(msg)) or ""

    if msg == "help" or msg == "hilfe" then
        WT.Utils.Logger:PrintNoLog(WT.L.OPTIONS_TITLE .. " - " .. (WT.L.CMD_HELP_TITLE))

        WT.Utils.Logger:PrintNoLog("/rl - " .. (WT.L.CMD_HELP_RL))
        WT.Utils.Logger:PrintNoLog("|cFF00FFFF" .. (WT.L.CMD_HELP_CAT_GENERAL) .. "|r")
        WT.Utils.Logger:PrintNoLog("/wt - " .. (WT.L.CMD_HELP_OPTIONS))
        WT.Utils.Logger:PrintNoLog("/wt reset all - " ..
        (WT.L.CMD_HELP_RESET_ALL))
        WT.Utils.Logger:PrintNoLog("/wt minimap - " .. (WT.L.CMD_HELP_MINIMAP))
        WT.Utils.Logger:PrintNoLog("/wt debug - " .. WT.L.CMD_HELP_DEBUG)

        WT.Utils.Logger:PrintNoLog("|cFF00FFFF" .. (WT.L.CMD_HELP_CAT_UI) .. "|r")
        WT.Utils.Logger:PrintNoLog("/wt reset pos - " ..
        (WT.L.CMD_HELP_RESET_POS))
        WT.Utils.Logger:PrintNoLog("/wt reset scale - " ..
        (WT.L.CMD_HELP_RESET_SCALE))
        WT.Utils.Logger:PrintNoLog("/wt reset config - " ..
        (WT.L.CMD_HELP_RESET_CONFIG))
        WT.Utils.Logger:PrintNoLog("/wt reset zoom - " ..
        (WT.L.CMD_HELP_RESET_ZOOM))
        WT.Utils.Logger:PrintNoLog("/wt reset <window> - " ..
        (WT.L.CMD_HELP_RESET_WINDOW))

        WT.Utils.Logger:PrintNoLog("|cFF00FFFF" .. (WT.L.CMD_HELP_CAT_CHAT) .. "|r")
        WT.Utils.Logger:PrintNoLog("/wt chat clear - " ..
        (WT.L.CMD_HELP_CHAT_CLEAR))
        WT.Utils.Logger:PrintNoLog("/wt chat clear-all - " ..
        (WT.L.CMD_HELP_CHAT_CLEAR_ALL))
        WT.Utils.Logger:PrintNoLog("/wt chat clear-history - " ..
        (WT.L.CMD_HELP_CHAT_CLEAR_HIST))
        WT.Utils.Logger:PrintNoLog("/wt chat clear-input - " ..
        (WT.L.CMD_HELP_CHAT_CLEAR_INP))
        WT.Utils.Logger:PrintNoLog("/wt gz - " .. (WT.L.CMD_HELP_GZ))
    elseif msg == "reset pos" then
        if WT.DB.Internal.Positions then wipe(WT.DB.Internal.Positions) end
        WT.Utils.Logger:Print(WT.L.MSG_POSITIONS_RESET)
        ReloadUI()
    elseif msg == "reset scale" then
        if WT.DB.Internal.Scales then wipe(WT.DB.Internal.Scales) end
        WT.Utils.Logger:Print(WT.L.MSG_SCALES_RESET)
        ReloadUI()
    elseif msg == "reset config" then
        if WT.DB.Internal.Positions then wipe(WT.DB.Internal.Positions) end
        if WT.DB.Internal.Scales then wipe(WT.DB.Internal.Scales) end
        WT.Utils.Logger:Print(WT.L.MSG_POSITIONS_RESET)
        WT.Utils.Logger:Print(WT.L.MSG_SCALES_RESET)
        ReloadUI()
    elseif msg == "reset zoom" then
        WT.DB.Frames.ExtendedCameraZoom = false
        WT.DB.Frames.MaxZoom = 1.9
        if WT.Modules.Frames and WT.Modules.Frames.UpdateExtendedCameraZoom then WT.Modules.Frames
                :UpdateExtendedCameraZoom(false) end
        WT.Utils.Logger:Print(WT.L.MSG_ZOOM_RESET)
    elseif msg == "reset all" then
        local cvarSync = WT.DB and WT.DB.Internal and WT.DB.Internal.CVarSyncDone
        local origCVars = WT.DB and WT.DB.Internal and WT.DB.Internal.OriginalCVars

        -- Restore original CVars to the WoW Client before wiping
        if origCVars then
            local setCVar = C_CVar and C_CVar.SetCVar or _G["SetCVar"]
            for cvar, val in pairs(origCVars) do
                pcall(setCVar, cvar, val)
            end
        end

        -- Nuke the logger history in memory so it doesn't sync back into the fresh DB
        if WT.Utils and WT.Utils.Logger then
            if WT.Utils.Logger.History then wipe(WT.Utils.Logger.History) end
            if WT.Utils.Logger.RawHistory then wipe(WT.Utils.Logger.RawHistory) end
        end

        -- Nuclear reset: Wipe the global table reference instead of replacing it to ensure WoW saves it
        if _G.WTSavedVariables then wipe(_G.WTSavedVariables) else _G.WTSavedVariables = {} end
        _G.WTSavedVariables.Internal = {
            CVarSyncDone = cvarSync,
            OriginalCVars = origCVars
        }

        -- Trigger DB re-initialization manually
        if WT.Config and WT.Config.Defaults then
            _G.WTSavedVariables = WT.Config.InitializeDB(_G.WTSavedVariables, WT.Config.Defaults)
            WT.DB = _G.WTSavedVariables
        end

        WT.Utils.Logger:Print(WT.L.MSG_FACTORY_RESET)
        ReloadUI()
    elseif string.match(msg, "^reset%s+(.+)$") then
        local target = string.match(msg, "^reset%s+(.+)$")
        local lTarget = string.lower(target)
        if lTarget == "poison" or lTarget == "poisons" or lTarget == "roguepoison" or lTarget == "wtroguepoisonreminder" then
            if WT.Modules.Automations and WT.Modules.Automations.ResetRoguePoisonPosition then
                WT.Modules.Automations:ResetRoguePoisonPosition()
            end
        elseif target ~= "pos" and target ~= "scale" and target ~= "config" and target ~= "zoom" and target ~= "all" then
            if WT.Modules.Frames and WT.Modules.Frames.ResetSpecificWindow then
                WT.Modules.Frames:ResetSpecificWindow(target)
            end
        end
    elseif msg == "chat clear" then
        local activeFrame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
        if activeFrame then
            if type(activeFrame.Clear) == "function" then activeFrame:Clear() end
            if activeFrame.historyBuffer and type(activeFrame.historyBuffer.Clear) == "function" then activeFrame
                    .historyBuffer:Clear() end
            activeFrame:AddMessage(" "); activeFrame:Clear()
        end
        if WT.DB.Internal.ChatLog then wipe(WT.DB.Internal.ChatLog) end
        if WT.DB.Internal.InputLog then wipe(WT.DB.Internal.InputLog) end
        for _, frameName in ipairs(CHAT_FRAMES) do
            local eb = _G[frameName .. "EditBox"]
            if eb and type(eb.ClearHistory) == "function" then eb:ClearHistory() end
        end
        WT.Utils.Logger:Print(WT.L.MSG_HISTORY_CLEARED)
    elseif msg == "chat clear-all" then
        for _, frameName in ipairs(CHAT_FRAMES) do
            local cf = _G[frameName]
            if cf then
                if type(cf.Clear) == "function" then cf:Clear() end
                if cf.historyBuffer and type(cf.historyBuffer.Clear) == "function" then cf.historyBuffer:Clear() end
                cf:AddMessage(" "); cf:Clear()
            end
        end
        WT.Utils.Logger:Print(WT.L.MSG_ALL_CHAT_CLEARED)
    elseif msg == "chat clear-history" then
        if WT.DB.Internal.ChatLog then wipe(WT.DB.Internal.ChatLog) end
        WT.Utils.Logger:Print(WT.L.MSG_CHAT_HIST_CLEARED)
    elseif msg == "chat clear-input" then
        if WT.DB.Internal.InputLog then wipe(WT.DB.Internal.InputLog) end
        for _, frameName in ipairs(CHAT_FRAMES) do
            local eb = _G[frameName .. "EditBox"]
            if eb and type(eb.ClearHistory) == "function" then eb:ClearHistory() end
        end
        WT.Utils.Logger:Print(WT.L.MSG_INPUT_CLEARED)
    elseif msg == "gz" or msg == "autogz" then
        WT.DB.Chat.AutoGZ = not WT.DB.Chat.AutoGZ
        WT.Utils.Logger:Print((WT.L.MSG_AUTO_GZ) ..
        (WT.DB.Chat.AutoGZ and ("|cFF00FF00" .. WT.L.LBL_ON .. "|r") or ("|cFFFF0000" .. WT.L.LBL_OFF .. "|r")))
        if WT.Config.Builder.Registry.Checkboxes["Chat"] and WT.Config.Builder.Registry.Checkboxes["Chat"]["AutoGZ"] then
            WT.Config.Builder.Registry.Checkboxes["Chat"]["AutoGZ"]:SetChecked(WT.DB.Chat.AutoGZ)
        end
    elseif msg == "debug" then
        WT.DB.General.DebugMode = not WT.DB.General.DebugMode
        WT.Utils.Logger:Print(WT.L.MSG_DEBUG_MODES ..
            (WT.DB.General.DebugMode and ("|cFF00FF00" .. WT.L.LBL_ON .. "|r") or ("|cFFFF0000" .. WT.L.LBL_OFF .. "|r")))
    elseif msg == "minimap" then
        WT.DB.General.EnableMinimapIcon = not WT.DB.General.EnableMinimapIcon
        if WT.Config.OptionsPanel and WT.Config.OptionsPanel.SetupMinimapButton then
            WT.Config.OptionsPanel:SetupMinimapButton()
        end
    else
        local function OpenOpts()
            if SettingsPanel and SettingsPanel:IsShown() then
                SettingsPanel:Hide()
            else
                if not WT.Config.OptionsPanel.Category and not WT.Config.OptionsPanel.isBuilding and type(WT.Config.OptionsPanel.Build) == "function" then
                    WT.Config.OptionsPanel:Build()
                end
                if WT.Config.OptionsPanel then
                    if WT.Config.OptionsPanel.Category and Settings and Settings.OpenToCategory then
                        Settings.OpenToCategory(WT.Config.OptionsPanel.Category:GetID())
                    elseif WT.Config.OptionsPanel.Category and _G["InterfaceOptionsFrame_OpenToCategory"] then
                        _G["InterfaceOptionsFrame_OpenToCategory"](WT.Config.OptionsPanel.Category:GetID())
                    else
                        WT.Config.OptionsPanel.pendingOpen = true
                    end
                end
            end
        end
        if WT.Core.CombatQueue:Add("OpenOptions", true, OpenOpts) then
            if WT.Utils and WT.Utils.Logger then WT.Utils.Logger:Warn(WT.L.MSG_OPTIONS_QUEUED) end
            return
        end
        OpenOpts()
    end
end

-- ============================================================================
-- SLASH COMMAND REGISTRATION
-- ============================================================================

SlashCmdList["WTOOLS"] = cmdList["WTOOLS"]
SLASH_WTOOLS1 = "/wt"
SLASH_WTOOLS2 = "/wtools"

SlashCmdList["WTRELOAD"] = cmdList["WTRELOAD"]
SLASH_WTRELOAD1 = "/rl"
SLASH_WTRELOAD2 = "/reloadui"
