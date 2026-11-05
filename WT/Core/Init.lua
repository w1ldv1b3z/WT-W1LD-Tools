local addonName, WT = ...

-- 1. Setup namespace structure
WT.Core = {}
WT.Config = {}
WT.Utils = {}
WT.Modules = {}
WT.Core.LoadTime = GetTime()

-- Addon metadata: WT.toc is the single source of truth for version and author
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G["GetAddOnMetadata"]
WT.Version = GetAddOnMetadata(addonName, "Version")
WT.Author = GetAddOnMetadata(addonName, "Author")

-- Create a dedicated container for all WT on-screen widgets to isolate them from UIParent layout passes
if not _G["WT_UIContainer"] then
    local wtContainer = CreateFrame("Frame", "WT_UIContainer", UIParent)
    wtContainer:SetAllPoints(UIParent)
    wtContainer:SetFrameStrata("BACKGROUND")
    wtContainer:SetFrameLevel(1)
    wtContainer.ignoreInLayout = true
    wtContainer.ignoreFramePositionManager = true
    if wtContainer.SetIsFramePositionManaged then pcall(function() wtContainer:SetIsFramePositionManaged(false) end) end
    if wtContainer.SetAttribute then pcall(function() wtContainer:SetAttribute("UIPanelLayout-ignore", true) end) end
end

-- (Optional) Global access in case external scripts or macros need to access WT
_G[addonName] = WT

-- 2. Addon Compartment function (Referenced in WT.toc)
function _G.WT_OnAddonCompartmentClick(addonName, buttonName)
    local function OpenOpts()
        if WT.Config and WT.Config.OptionsPanel and not WT.Config.OptionsPanel.Category and not WT.Config.OptionsPanel.isBuilding and type(WT.Config.OptionsPanel.Build) == "function" then
            WT.Config.OptionsPanel:Build()
        end
        if WT.Config and WT.Config.OptionsPanel then
            if WT.Config.OptionsPanel.Category and Settings and Settings.OpenToCategory then
                Settings.OpenToCategory(WT.Config.OptionsPanel.Category:GetID())
            elseif WT.Config.OptionsPanel.Category and _G["InterfaceOptionsFrame_OpenToCategory"] then
                _G["InterfaceOptionsFrame_OpenToCategory"](WT.Config.OptionsPanel.Category:GetID())
            else
                WT.Config.OptionsPanel.pendingOpen = true
            end
        end
    end
    if WT.Core.CombatQueue:Add("OpenOptions", true, OpenOpts) then
        if WT.Utils and WT.Utils.Logger then
            WT.Utils.Logger:Warn(WT.L.MSG_OPTIONS_QUEUED)
        end
        return
    end
    OpenOpts()
end

-- 5. Centralized Taint-Free Player Info Cache
WT.Utils.GuidCache = {}
function WT.Utils:GetPlayerInfoByGUID(guid)
    if not guid then return nil end
    if self.GuidCache[guid] then return unpack(self.GuidCache[guid]) end

    local v1, v2, v3, v4, v5, v6, v7
    pcall(function()
        v1, v2, v3, v4, v5, v6, v7 = GetPlayerInfoByGUID(guid)
    end)

    local uV2 = WT.Utils.Safety.Unsecret(v2)
    local r1, r2, r3, r4, r5, r6, r7 = WT.Utils.Safety.Unsecret(v1), (type(uV2) == "string") and string.upper(uV2) or nil,
        WT.Utils.Safety.Unsecret(v3), WT.Utils.Safety.Unsecret(v4), WT.Utils.Safety.SafeNum(v5),
        WT.Utils.Safety.Unsecret(v6), WT.Utils.Safety.Unsecret(v7)
    if r1 or r2 or r3 then self.GuidCache[guid] = { r1, r2, r3, r4, r5, r6, r7 } end
    return r1, r2, r3, r4, r5, r6, r7
end

-- 6. Base events for initialization
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

function WT.Config.InitializeDB(db, defaults, skipCleanup)
    if type(db) ~= "table" then db = {} end
    if type(defaults) ~= "table" then return db end

    for k, v in pairs(defaults) do
        if type(v) == "table" then
            -- Prevent the automatic garbage collector from wiping dynamic tables like 'Internal', 'SavedColors', or 'Sync'
            local doSkip = skipCleanup or (k == "Internal") or (k == "GlobalTabSettings") or (k == "Sync") or
                (k == "SavedColors")
            db[k] = WT.Config.InitializeDB(db[k], v, doSkip)
        elseif db[k] == nil then
            db[k] = v
        end
    end

    if not skipCleanup then
        for k, v in pairs(db) do
            if defaults[k] == nil then
                db[k] = nil
            end
        end
    end

    return db
end

local skinnedPopups = setmetatable({}, { __mode = "k" })

function WT.Core:SkinStaticPopups()
    if not WT.DB.General.SkinPopups then return end

    local framesToSkin = {
        "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4",
        "LFGDungeonReadyPopup", "LFGDungeonReadyDialog", "ReadyCheckFrame",
        "LFGInvitePopup", "LFGRoleCheckPopup"
    }

    for _, frameName in ipairs(framesToSkin) do
        local popup = _G[frameName]
        if popup and not skinnedPopups[popup] then
            skinnedPopups[popup] = true

            if popup["NineSlice"] then popup["NineSlice"]:SetAlpha(0) end
            if popup.Border then popup.Border:SetAlpha(0) end

            -- SECURITY FIX: Do not parent the background frame directly to the popup!
            -- Adding children to generic protected frames (like StaticPopup1) taints their
            -- entire execution path, blocking hardware actions like VisitHouse() or CastSpell().
            local bg = CreateFrame("Frame", nil, popup:GetParent() or UIParent)
            local visualBounds = popup["NineSlice"] or popup.Border or popup
            bg:SetAllPoints(visualBounds)
            bg:SetFrameStrata(popup:GetFrameStrata())
            bg:SetFrameLevel(math.max(0, popup:GetFrameLevel() - 1))
            bg.ignoreInLayout = true
            bg.ignoreFramePositionManager = true
            if bg.SetIsFramePositionManaged then pcall(function() bg:SetIsFramePositionManaged(false) end) end

            -- Since we anchor directly to the visual bounds (e.g. NineSlice), we do not need 4px insets.
            local bgTex = bg:CreateTexture(nil, "BACKGROUND")
            bgTex:SetPoint("TOPLEFT", 0, 0)
            bgTex:SetPoint("BOTTOMRIGHT", 0, 0)
            bgTex:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
            bgTex:SetVertexColor(WT.Colors.STD_BG_R, WT.Colors.STD_BG_G, WT.Colors.STD_BG_B, WT.Colors.STD_BG_A)

            local br, bg_g, bb = WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B
            local tEdge = bg:CreateTexture(nil, "BORDER")
            tEdge:SetPoint("TOPLEFT", 0, 0); tEdge:SetPoint("TOPRIGHT", 0, 0); tEdge:SetHeight(1)
            tEdge:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); tEdge:SetVertexColor(br, bg_g, bb, 0.8)
            local bEdge = bg:CreateTexture(nil, "BORDER")
            bEdge:SetPoint("BOTTOMLEFT", 0, 0); bEdge:SetPoint("BOTTOMRIGHT", 0, 0); bEdge:SetHeight(1)
            bEdge:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); bEdge:SetVertexColor(br, bg_g, bb, 0.8)
            local lEdge = bg:CreateTexture(nil, "BORDER")
            lEdge:SetPoint("TOPLEFT", 0, 0); lEdge:SetPoint("BOTTOMLEFT", 0, 0); lEdge:SetWidth(1)
            lEdge:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); lEdge:SetVertexColor(br, bg_g, bb, 0.8)
            local rEdge = bg:CreateTexture(nil, "BORDER")
            rEdge:SetPoint("TOPRIGHT", 0, 0); rEdge:SetPoint("BOTTOMRIGHT", 0, 0); rEdge:SetWidth(1)
            rEdge:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); rEdge:SetVertexColor(br, bg_g, bb, 0.8)

            if not popup:IsShown() then bg:Hide() end
            popup:HookScript("OnShow", function()
                bg:SetFrameLevel(math.max(0, popup:GetFrameLevel() - 1))
                bg:Show()
            end)
            popup:HookScript("OnHide", function() bg:Hide() end)

            if WT.Config and WT.Config.Builder then
                if string.match(frameName, "StaticPopup") then
                    -- SECURITY FIX: We intentionally do NOT style the buttons of the global StaticPopups!
                    -- Modifying these generic buttons causes execution taint, which blocks highly protected
                    -- hardware actions (like VisitHouse() or CastSpell()) when triggered from a dialog.
                    local eb = _G[frameName .. "EditBox"]
                    if eb then WT.Config.Builder:StyleEditBox(eb) end
                    local web = _G[frameName .. "WideEditBox"]
                    if web then WT.Config.Builder:StyleEditBox(web) end
                elseif frameName == "LFGDungeonReadyPopup" or frameName == "LFGDungeonReadyDialog" then
                    local btn1 = _G["LFGDungeonReadyDialogEnterDungeonButton"] or popup.enterButton or
                        popup.EnterDungeonButton
                    local btn2 = _G["LFGDungeonReadyDialogLeaveQueueButton"] or popup.leaveButton or
                        popup.LeaveQueueButton
                    if btn1 then WT.Config.Builder:StyleButton(btn1) end
                    if btn2 then WT.Config.Builder:StyleButton(btn2) end
                elseif frameName == "ReadyCheckFrame" then
                    local btn1 = _G["ReadyCheckFrameYesButton"] or popup.YesButton
                    local btn2 = _G["ReadyCheckFrameNoButton"] or popup.NoButton
                    if btn1 then WT.Config.Builder:StyleButton(btn1) end
                    if btn2 then WT.Config.Builder:StyleButton(btn2) end

                    -- Give text and buttons more room (less cramped layout)
                    popup:HookScript("OnShow", function(self)
                        if btn1 then
                            btn1:ClearAllPoints()
                            btn1:SetPoint("BOTTOMRIGHT", self, "BOTTOM", -8, 14)
                            btn1:SetWidth(120)
                            btn1:SetHeight(28)
                        end
                        if btn2 then
                            btn2:ClearAllPoints()
                            btn2:SetPoint("BOTTOMLEFT", self, "BOTTOM", 8, 14)
                            btn2:SetWidth(120)
                            btn2:SetHeight(28)
                        end

                        local text = _G["ReadyCheckFrameText"] or self.Text
                        if text then
                            text:ClearAllPoints()
                            -- Leave room at the top for the title
                            text:SetPoint("TOP", self, "TOP", 0, -40)
                            text:SetPoint("LEFT", self, "LEFT", 25, 0)
                            text:SetPoint("RIGHT", self, "RIGHT", -25, 0)

                            C_Timer.After(0.01, function()
                                self:SetHeight(text:GetStringHeight() + 100)
                                self:SetWidth(330)
                            end)
                        end
                    end)
                elseif frameName == "LFGInvitePopup" then
                    local btn1 = _G["LFGInvitePopupAcceptButton"] or popup.AcceptButton
                    local btn2 = _G["LFGInvitePopupDeclineButton"] or popup.DeclineButton
                    if btn1 then WT.Config.Builder:StyleButton(btn1) end
                    if btn2 then WT.Config.Builder:StyleButton(btn2) end
                elseif frameName == "LFGRoleCheckPopup" then
                    local btn1 = _G["LFGRoleCheckPopupAcceptButton"] or popup.AcceptButton
                    local btn2 = _G["LFGRoleCheckPopupDeclineButton"] or popup.DeclineButton
                    if btn1 then WT.Config.Builder:StyleButton(btn1) end
                    if btn2 then WT.Config.Builder:StyleButton(btn2) end
                end
            end
        end
    end
end

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        self:UnregisterEvent("ADDON_LOADED")
        -- SavedVariables are available from here on (WTSavedVariables)
        if type(_G.WTSavedVariables) ~= "table" then _G.WTSavedVariables = {} end
        local WTSavedVariables = _G.WTSavedVariables

        -- Legacy Cleanup: Remove old debug logs to declutter SavedVariables
        if WTSavedVariables.Internal then
            WTSavedVariables.Internal.LogHistory = nil
            WTSavedVariables.Internal.LogRawHistory = nil
        end

        -- Database Migration (Run BEFORE InitializeDB to rescue old keys from Garbage Collection)
        if WT.Config and type(WT.Config.RunMigrations) == "function" then
            WT.Config:RunMigrations(WTSavedVariables)
        end

        -- Intelligent First-Run CVar Sync: Adopts existing WoW settings before setting addon defaults
        if not WTSavedVariables.Internal.CVarSyncDone then
            if not WTSavedVariables.Frames then WTSavedVariables.Frames = {} end
            if not WTSavedVariables.Automations then WTSavedVariables.Automations = {} end
            if not WTSavedVariables.Nameplates then WTSavedVariables.Nameplates = {} end
            if not WTSavedVariables.ActionBars then WTSavedVariables.ActionBars = {} end
            if not WTSavedVariables.Chat then WTSavedVariables.Chat = {} end

            local fnGetCVar = (C_CVar and C_CVar.GetCVar) or _G["GetCVar"] or function() return nil end

            if fnGetCVar("ResampleAlwaysSharpen") == "1" then WTSavedVariables.Frames.SharpeningFilter = true end
            if fnGetCVar("autoLootRate") == "0" then WTSavedVariables.Automations.FastLoot = true end
            if fnGetCVar("nameplateMotion") == "1" then WTSavedVariables.Nameplates.NameplateStacking = true end
            if fnGetCVar("autoDismount") == "1" then WTSavedVariables.Automations.AutoDismount = true end
            if fnGetCVar("autoDismountFlying") == "1" or fnGetCVar("autoStand") == "1" then WTSavedVariables.Automations.AutoStand = true end
            if fnGetCVar("lootUnderMouse") == "1" then WTSavedVariables.Automations.LootUnderMouse = true end
            if fnGetCVar("screenEdgeFlash") == "0" then WTSavedVariables.Frames.DisableLowHealthFlash = true end
            if fnGetCVar("ffxDeath") == "0" or fnGetCVar("ffxGlow") == "0" then WTSavedVariables.Frames.DisableGlow = true end
            if fnGetCVar("colorChatNamesByClass") == "1" then WTSavedVariables.Chat.ClassColors = true end

            local ts = fnGetCVar("showTimestamps")
            if ts and ts ~= "none" and ts ~= "0" then WTSavedVariables.Chat.Timestamps = true end

            local currentZoom = WT.Utils.Safety.SafeNum(fnGetCVar("cameraDistanceMaxZoomFactor"))
            if currentZoom and currentZoom > 1.9 then
                WTSavedVariables.Frames.ExtendedCameraZoom = true
                WTSavedVariables.Frames.MaxZoom = math.floor(currentZoom * 10 + 0.5) / 10
            end

            local overlapV = WT.Utils.Safety.SafeNum(fnGetCVar("nameplateOverlapV"))
            if overlapV then WTSavedVariables.Nameplates.NameplateOverlapV = overlapV end

            WTSavedVariables.Internal.CVarSyncDone = true
        end

        if WT.Config and WT.Config.Defaults then
            _G.WTSavedVariables = WT.Config.InitializeDB(WTSavedVariables, WT.Config.Defaults)
            WTSavedVariables = _G.WTSavedVariables
        end
        WT.DB = WTSavedVariables

        -- Fix: Sync the hide state for LibDBIcon before the UI builds, to prevent minimap flickering
        if WT.DB.General then
            WT.DB.General.hide = not WT.DB.General.EnableMinimapIcon

            if WT.DB.General.AccentColorClass then
                local _, class = UnitClass("player")
                if class and WT.Colors.Classes[class] then
                    local hex = WT.Colors.Classes[class]
                    local cleanHex = string.match(hex, "|c%x%x(%x%x%x%x%x%x)") or hex
                    local r, g, b = WT.Colors:HexToRGB(cleanHex)
                    WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B = r, g, b
                    WT.Colors.PRIMARY = hex
                end
            elseif WT.DB.General.AccentColor then
                local ac = WT.DB.General.AccentColor
                WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B = ac.r, ac.g, ac.b
                WT.Colors.PRIMARY = "|c" .. WT.Colors:GetHex(ac)
            end
        end

        -- SECURE REGISTRATION: Build the Options Panel during ADDON_LOADED.
        -- This guarantees the Settings API registers our category BEFORE the Blizzard UI Layout Manager
        -- locks the frames, preventing cascading UI taints on reload.
        if WT.Config and WT.Config.OptionsPanel and not WT.Config.OptionsPanel.Category and type(WT.Config.OptionsPanel.Build) == "function" then
            WT.Config.OptionsPanel:Build()
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        -- The player is logged in, the UI is loaded. Initialize modules here.

        -- PRE-CREATE CUSTOM TOOLTIPS SAFELY
        -- Creating GameTooltipTemplate frames dynamically during combat/OnEnter can taint the global TooltipDataProcessor
        if not _G["WTCustomTooltip"] then
            local tt1 = CreateFrame("GameTooltip", "WTCustomTooltip", _G["WT_UIContainer"], "GameTooltipTemplate")
            tt1.ignoreInLayout = true; tt1.ignoreFramePositionManager = true
            if tt1.SetIsFramePositionManaged then pcall(function() tt1:SetIsFramePositionManaged(false) end) end
        end
        if not _G["WTSocialTooltip"] then
            local tt2 = CreateFrame("GameTooltip", "WTSocialTooltip", _G["WT_UIContainer"], "GameTooltipTemplate")
            tt2.ignoreInLayout = true; tt2.ignoreFramePositionManager = true
            if tt2.SetIsFramePositionManaged then pcall(function() tt2:SetIsFramePositionManaged(false) end) end
        end


        if WT.Core.SkinStaticPopups then WT.Core:SkinStaticPopups() end

        C_Timer.After(1, function()
            if WT.Config and WT.Config.OptionsPanel and WT.Config.OptionsPanel.SetupMinimapButton then
                WT.Config.OptionsPanel:SetupMinimapButton()
            end
            local ver = WT.Version
            local flavorStr = (WT.Compat and WT.Compat.IsForever) and " |cFF00FF00[WoW Forever (Beta)]|r" or ""
            WT.Utils.Logger:Print((WT.L.MSG_WELCOME) ..
                " |cFF00FFFF" .. ver .. "|r" .. flavorStr)
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Dynamic reset of performance and spam protection after every loading screen
        WT.Core.LoadTime = GetTime()

        if WT.Utils.GuidCache then wipe(WT.Utils.GuidCache) end
    end
end)
