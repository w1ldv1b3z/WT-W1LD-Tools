local addonName, WT = ...

WT.Config.OptionsPanel = {}
local Panel = WT.Config.OptionsPanel

local strtrim = strtrim or string.trim or function(s) return s and string.match(s, "^%s*(.-)%s*$") or "" end

local SafeNum = WT.Utils.Safety.SafeNum

local function SafeSetGradient(tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    C_Timer.After(0, function()
        if tex and tex.SetGradient then
            tex:SetGradient(orientation, { r = r1, g = g1, b = b1, a = a1 }, { r = r2, g = g2, b = b2, a = a2 })
        elseif tex and type(tex.SetGradientAlpha) == "function" then
            tex:SetGradientAlpha(orientation, r1, g1, b1, a1, r2, g2, b2, a2)
        end
    end)
end

function Panel:ShowReloadPrompt()
    if not self.ReloadFrame then
        local f = CreateFrame("Frame", "WTReloadPrompt", _G["WT_UIContainer"], "BackdropTemplate")
        f:SetSize(400, 110)
        f:SetPoint("TOP", _G["WT_UIContainer"], "TOP", 0, -150)
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(10000)

        f.ignoreInLayout = true
        f.ignoreFramePositionManager = true
        if f.SetIsFramePositionManaged then pcall(function() f:SetIsFramePositionManaged(false) end) end

        f:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        f:SetBackdropColor(WT.Colors.STD_BG_R, WT.Colors.STD_BG_G, WT.Colors.STD_BG_B, WT.Colors.STD_BG_A)
        f:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.8)

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(36, 36)
        icon:SetPoint("TOPLEFT", 16, -16)
        icon:SetTexture("Interface\\Icons\\INV_Misc_Wrench_01")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)
        text:SetPoint("RIGHT", f, "RIGHT", -16, 0)
        text:SetJustifyH("LEFT")
        text:SetText(WT.L.MSG_RELOAD_REQUIRED)

        local btnYes = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btnYes:SetSize(120, 26)
        btnYes:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -5, 16)
        btnYes:SetText(YES or "Yes")
        if WT.Config and WT.Config.Builder and type(WT.Config.Builder.StyleButton) == "function" then
            WT.Config.Builder
                :StyleButton(btnYes)
        end
        btnYes:SetScript("OnClick", function()
            ReloadUI()
        end)

        local btnNo = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btnNo:SetSize(120, 26)
        btnNo:SetPoint("BOTTOMLEFT", f, "BOTTOM", 5, 16)
        btnNo:SetText(NO or "No")
        if WT.Config and WT.Config.Builder and type(WT.Config.Builder.StyleButton) == "function" then
            WT.Config.Builder
                :StyleButton(btnNo)
        end
        btnNo:SetScript("OnClick", function() f:Hide() end)

        self.ReloadFrame = f
    end
    if not self.ReloadFrame:IsShown() then
        self.ReloadFrame:Show()
    end
end

function Panel:SetupMinimapButton()
    if not LibStub then return end
    local ldb = LibStub("LibDataBroker-1.1", true)
    local icon = LibStub("LibDBIcon-1.0", true)
    if not ldb or not icon then return end

    WT.DB.General.hide = not WT.DB.General.EnableMinimapIcon
    if not WT.DB.General.minimapPos then
        WT.DB.General.minimapPos = WT.DB.General.MinimapIconPos or 45
    end

    if not self.MinimapRegistered then
        local dataObject = ldb:NewDataObject("W1LDTools", {
            type = "launcher",
            text = "W1LD Tools",
            icon = "Interface\\Icons\\inv_misc_wrench_01",
            OnClick = function(self, button)
                if button == "LeftButton" then
                    if IsShiftKeyDown() and WT.DB.Chat and WT.DB.Chat.AutoGZTooltip then
                        WT.DB.Chat.AutoGZ = not WT.DB.Chat.AutoGZ
                        if WT.Utils and WT.Utils.Logger then
                            WT.Utils.Logger:Print((WT.L.MSG_AUTO_GZ) ..
                                (WT.DB.Chat.AutoGZ and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
                        end
                        if WT.Config.Builder.Registry.Checkboxes["Chat"] and WT.Config.Builder.Registry.Checkboxes["Chat"]["AutoGZ"] then
                            WT.Config.Builder.Registry.Checkboxes["Chat"]["AutoGZ"]:SetChecked(WT.DB.Chat.AutoGZ)
                        end

                        local tt = _G["WTCustomTooltip"]
                        if tt and tt:GetOwner() == self then
                            tt:Hide()
                            if self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
                        end
                        return
                    end
                    local function OpenOpts()
                        if SettingsPanel and SettingsPanel:IsShown() then
                            SettingsPanel:Hide()
                        elseif WT.Config.OptionsPanel then
                            if WT.Config.OptionsPanel.Category and Settings.OpenToCategory then
                                Settings.OpenToCategory(WT.Config.OptionsPanel.Category:GetID())
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
                elseif button == "RightButton" then
                    if IsShiftKeyDown() and WT.DB.Groups and WT.DB.Groups.AutoLFGTooltip then
                        WT.DB.Groups.AutoAcceptLFG = not WT.DB.Groups.AutoAcceptLFG
                        if WT.Utils and WT.Utils.Logger then
                            WT.Utils.Logger:Print((WT.L.MSG_AUTO_ROLE) ..
                                (WT.DB.Groups.AutoAcceptLFG and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
                        end
                        if WT.Config.Builder.Registry.Checkboxes["Groups"] and WT.Config.Builder.Registry.Checkboxes["Groups"]["AutoAcceptLFG"] then
                            WT.Config.Builder.Registry.Checkboxes["Groups"]["AutoAcceptLFG"]:SetChecked(WT.DB.Groups
                                .AutoAcceptLFG)
                        end

                        local tt = _G["WTCustomTooltip"]
                        if tt and tt:GetOwner() == self then
                            tt:Hide()
                            if self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
                        end
                        return
                    end
                    ReloadUI()
                end
            end,
            OnEnter = function(self)
                local tt = _G["WTCustomTooltip"]
                if not tt then
                    tt = CreateFrame("GameTooltip", "WTCustomTooltip", _G["WT_UIContainer"] or UIParent,
                        "GameTooltipTemplate")
                    tt.ignoreInLayout = true
                    tt.ignoreFramePositionManager = true
                    if tt.SetIsFramePositionManaged then pcall(function() tt:SetIsFramePositionManaged(false) end) end
                end

                tt:SetOwner(self, "ANCHOR_BOTTOMLEFT")
                tt:ClearLines()

                local ver = WT.Version
                local flavor = (WT.Compat and WT.Compat.GetFlavorName and WT.Compat:GetFlavorName()) or
                    (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and "Retail" or "WoW Forever (Beta)")
                tt:AddDoubleLine(
                    "|TInterface\\AddOns\\" ..
                    addonName ..
                    "\\Media\\Graphics\\Logo.tga:16:16:0:0|t " .. WT.Colors.PRIMARY .. WT.L.OPTIONS_TITLE .. "|r",
                    "|cFF888888" .. ver .. " [" .. flavor .. "]|r")
                tt:AddLine(" ")

                local function AddAction(text, status)
                    local c, a = string.match(text, "^(.-):%s*(.+)$")
                    if c and a then
                        tt:AddLine(WT.Colors.PRIMARY .. "• " .. c .. ":|r |cFFFFFFFF" .. a .. (status or "") .. "|r")
                    else
                        tt:AddLine(WT.Colors.PRIMARY .. "•|r |cFFFFFFFF" .. text .. (status or "") .. "|r")
                    end
                end

                AddAction(WT.L.MINIMAP_BTN_TT_LEFT)
                if WT.DB.Chat and WT.DB.Chat.AutoGZTooltip then
                    local autoGzStatus = WT.DB.Chat.AutoGZ and " |cFF00FF00[ON]|r" or " |cFFFF3333[OFF]|r"
                    AddAction((WT.L.MINIMAP_BTN_TT_SHIFT_LEFT), autoGzStatus)
                end
                if WT.DB.Groups and WT.DB.Groups.AutoLFGTooltip then
                    local autoLFGStatus = WT.DB.Groups.AutoAcceptLFG and " |cFF00FF00[ON]|r" or " |cFFFF3333[OFF]|r"
                    AddAction((WT.L.MINIMAP_BTN_TT_SHIFT_RIGHT), autoLFGStatus)
                end
                AddAction(WT.L.MINIMAP_BTN_TT_RIGHT)



                tt:Show()
            end,
            OnLeave = function(self)
                if _G["WTCustomTooltip"] then _G["WTCustomTooltip"]:Hide() end
            end,
        })

        icon:Register("W1LDTools", dataObject, WT.DB.General)
        self.MinimapRegistered = true
    else
        icon:Refresh("W1LDTools", WT.DB.General)
    end
end

-- Build the native settings panel
function Panel:Build()
    -- 1. Root Category (Main Entry)
    local rootBuilder = WT.Config.Builder:CreateCategory(nil, WT.L.OPTIONS_TITLE)
    rootBuilder.moduleName = "General"
    Settings.RegisterAddOnCategory(rootBuilder.category)

    local ver = WT.Version
    local author = WT.Author

    local flavorName = (WT.Compat and WT.Compat.GetFlavorName and WT.Compat:GetFlavorName()) or
        (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and "Retail" or "WoW Forever (Beta)")
    local clientVer = (WT.Compat and WT.Compat.ClientVersion) or (GetBuildInfo and select(1, GetBuildInfo())) or ""
    local clientStr = flavorName .. (clientVer ~= "" and (" (" .. clientVer .. ")") or "")

    local logo = rootBuilder.content:CreateTexture(nil, "ARTWORK")
    logo:SetSize(48, 48)
    logo:SetPoint("TOPLEFT", rootBuilder.content, "TOPLEFT", 10, rootBuilder.cursorY)
    logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\Media\\Graphics\\Logo.tga")

    local title = rootBuilder.content:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 15, -5)
    title:SetText(WT.Colors.PRIMARY .. WT.L.OPTIONS_TITLE .. "|r")

    local verAuth = rootBuilder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    verAuth:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    verAuth:SetText((WT.L.UI_VERSION) ..
        " " ..
        ver ..
        " | " ..
        (WT.L.UI_CLIENT) .. " " .. clientStr .. " | " .. (WT.L.UI_AUTHOR) .. " " .. author)
    verAuth:SetTextColor(WT.Colors.SUBTEXT_R, WT.Colors.SUBTEXT_G, WT.Colors.SUBTEXT_B)

    rootBuilder:AddSpace(55)

    local desc = rootBuilder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", rootBuilder.content, "TOPLEFT", 15, rootBuilder.cursorY)
    desc:SetWidth(530)
    desc:SetJustifyH("LEFT")
    desc:SetText(WT.L.OPTIONS_DESC)

    rootBuilder:AddSpace(35)

    -- 1.5 Search Bar
    local function AddSearchBar(builder, suffix)
        local searchBox = CreateFrame("EditBox", "WTSettingsSearchBox" .. suffix, builder.content, "SearchBoxTemplate")
        searchBox:SetPoint("TOPRIGHT", builder.content, "TOPRIGHT", -25, -5)
        searchBox:SetSize(180, 22)
        searchBox:SetAutoFocus(false)
        searchBox:SetMaxLetters(50)

        if searchBox.Instructions then
            searchBox.Instructions:SetText(WT.L.SEARCH_PLACEHOLDER)
            searchBox.Instructions:ClearAllPoints()
            searchBox.Instructions:SetPoint("TOPLEFT", searchBox, "TOPLEFT", 14, -2)
            searchBox.Instructions:SetPoint("BOTTOMRIGHT", searchBox, "BOTTOMRIGHT", -15, -2)
        end

        WT.Config.Builder:StyleEditBox(searchBox)

        local l, r, t, b = searchBox:GetTextInsets()
        searchBox:SetTextInsets(l, r, t + 2, b)

        local searchResults = CreateFrame("Frame", "WTOptionsSearchResults" .. suffix, searchBox, "BackdropTemplate")
        searchResults:SetPoint("TOPRIGHT", searchBox, "BOTTOMRIGHT", 5, -5)
        searchResults:SetSize(400, 200)
        searchResults:SetFrameStrata("DIALOG")
        searchResults:SetFrameLevel(9999)
        searchResults:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        searchResults:SetBackdropColor(WT.Colors.STD_BG_R, WT.Colors.STD_BG_G, WT.Colors.STD_BG_B, 0.95)
        searchResults:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 1)
        searchResults:Hide()

        local scrollFrame = CreateFrame("ScrollFrame", nil, searchResults, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 6, -6)
        scrollFrame:SetPoint("BOTTOMRIGHT", -26, 6)

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetSize(368, 1)
        scrollFrame:SetScrollChild(scrollChild)

        local resultButtons = {}

        local function ClearSearchResults()
            for _, btn in ipairs(resultButtons) do btn:Hide() end
            searchResults:Hide()
        end

        searchResults:SetScript("OnUpdate", function(self)
            if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                if not self:IsMouseOver() and not searchBox:IsMouseOver() then
                    ClearSearchResults()
                    searchBox:ClearFocus()
                end
            end
        end)

        searchBox:HookScript("OnHide", function(self)
            self:SetText("")
            self:ClearFocus()
            ClearSearchResults()
        end)

        searchBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            ClearSearchResults()
        end)

        searchBox:SetScript("OnTextChanged", function(self, isUserInput)
            SearchBoxTemplate_OnTextChanged(self)
            if not isUserInput then return end

            local text = string.lower(strtrim(self:GetText()))
            if text == "" then
                ClearSearchResults(); return
            end

            local matches, seen = {}, {}
            if WT.Config.Builder.SearchIndex then
                for _, entry in ipairs(WT.Config.Builder.SearchIndex) do
                    if string.find(string.lower(entry.label), text, 1, true) then
                        local uniqueKey = entry.label ..
                            "_" ..
                            tostring(entry.module) .. "_" .. tostring(entry.title) .. "_" .. tostring(entry.subTitle)
                        if not seen[uniqueKey] then
                            seen[uniqueKey] = true
                            table.insert(matches, entry)
                        end
                    end
                end
            end

            if #matches == 0 then
                ClearSearchResults(); return
            end

            local yOffset = 0
            for i, match in ipairs(matches) do
                if i > 25 then break end

                local btn = resultButtons[i]
                if not btn then
                    btn = CreateFrame("Button", nil, scrollChild, "BackdropTemplate")
                    btn:SetSize(368, 24)
                    btn:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
                    btn:SetBackdropBorderColor(0, 0, 0, 0)

                    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1)
                    hl:SetColorTexture(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.2)

                    btn:HookScript("OnEnter",
                        function(self)
                            self:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G,
                                WT.Colors.PRIMARY_B, 0.8)
                        end)
                    btn:HookScript("OnLeave", function(self) self:SetBackdropBorderColor(0, 0, 0, 0) end)
                    btn:HookScript("OnHide", function(self) self:SetBackdropBorderColor(0, 0, 0, 0) end)

                    btn.lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    btn.lbl:SetPoint("LEFT", 6, 0); btn.lbl:SetPoint("RIGHT", -6, 0)
                    btn.lbl:SetJustifyH("LEFT"); btn.lbl:SetWordWrap(false)
                    resultButtons[i] = btn
                end

                local mainCat = WT.Config.OptionsPanel.ModuleToCategory and
                    WT.Config.OptionsPanel.ModuleToCategory[match.module] or match.module
                local locMod = WT.L["CATEGORY_" .. string.upper(mainCat)]

                local path = locMod
                if match.title then
                    path = path .. " > " .. string.gsub(match.title, "|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
                end
                if match.subTitle then
                    path = path .. " > " .. string.gsub(match.subTitle, "|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
                end

                btn.lbl:SetText(match.label .. " |cFF888888(" .. path .. ")|r")
                btn:SetPoint("TOPLEFT", 0, -yOffset)
                btn:Show()

                btn:SetScript("OnClick", function()
                    ClearSearchResults()
                    searchBox:ClearFocus()
                    searchBox:SetText("")

                    local targetCat = match.targetCategory
                    if not targetCat then
                        local mainCat = WT.Config.OptionsPanel.ModuleToCategory[match.module] or match.module
                        targetCat = WT.Config.OptionsPanel.SubCategories[mainCat]
                    end

                    local opened = false
                    if targetCat and Settings and Settings.OpenToCategory then
                        Settings.OpenToCategory(targetCat:GetID())
                        opened = true
                    elseif targetCat and _G["InterfaceOptionsFrame_OpenToCategory"] then
                        _G["InterfaceOptionsFrame_OpenToCategory"](targetCat:GetID())
                        opened = true
                    end

                    if opened then
                        C_Timer.After(0.1, function()
                            if match.builder and match.builder.scrollFrame and match.yPos then
                                local sf = match.builder.scrollFrame
                                local maxScroll = sf:GetVerticalScrollRange()
                                local targetScroll = math.abs(match.yPos) - 40
                                targetScroll = math.max(0, math.min(maxScroll, targetScroll))
                                sf:SetVerticalScroll(targetScroll)
                            end
                            if match.textObj then
                                WT.Config.Builder:ShowHighlight(match.textObj)
                            elseif match.widget then
                                WT.Config.Builder:ShowHighlight(match.widget)
                            end
                        end)
                    end
                end)
                yOffset = yOffset + 24
            end

            for i = #matches + 1, #resultButtons do resultButtons[i]:Hide() end

            scrollChild:SetHeight(yOffset)
            searchResults:SetHeight(math.min(250, yOffset + 12))
            searchResults:Show()
        end)
    end

    AddSearchBar(rootBuilder, "Root")

    local function AddDescription(builder, text)
        if not text then return end
        local desc = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
        desc:SetWidth(530)
        desc:SetJustifyH("LEFT")
        desc:SetText(text)
        builder:AddSpace(desc:GetStringHeight() + 25)
    end

    WT.Config.Builder:CreateTitle(rootBuilder, WT.L.GROUP_GENERAL)
    AddDescription(rootBuilder, WT.L.OPT_DESC_GROUP_GENERAL)

    WT.Config.Builder:CreateCheckbox(rootBuilder, WT.L.OPT_GEN_MINIMAP_ICON, WT.L.OPT_DESC_GEN_MINIMAP_ICON, "General",
        "EnableMinimapIcon", function() self:SetupMinimapButton() end)
    local function PromptReload()
        if WT.Config and WT.Config.OptionsPanel and WT.Config.OptionsPanel.ShowReloadPrompt then
            WT.Config.OptionsPanel:ShowReloadPrompt()
        end
    end
    local skinPopupsCb = WT.Config.Builder:CreateCheckbox(rootBuilder, WT.L.OPT_GEN_SKIN_POPUPS,
        WT.L.OPT_DESC_GEN_SKIN_POPUPS, "General", "SkinPopups", PromptReload)

    WT.Config.Builder:CreateColorPicker(rootBuilder, WT.L.OPT_GEN_ACCENT_COLOR,
        WT.L.OPT_DESC_GEN_ACCENT_COLOR,
        "General", "AccentColor", false, skinPopupsCb, PromptReload, true)

    WT.Config.Builder:CreateCheckbox(rootBuilder, WT.L.OPT_GEN_ACCENT_CLASS,
        WT.L.OPT_DESC_GEN_ACCENT_CLASS,
        "General", "AccentColorClass", PromptReload, skinPopupsCb)

    rootBuilder:AddSpace(10)

    WT.Config.Builder:CreateTitle(rootBuilder, WT.L.GROUP_MODULES)
    AddDescription(rootBuilder,
        WT.L.OPT_DESC_GROUP_MODULES)

    local moduleIcons = {
        Automations = "Interface\\Icons\\Trade_Engineering",
        ActionBars = "Interface\\Icons\\INV_Misc_Book_09",
        Chat = "Interface\\Icons\\UI_Chat",
        Keybindings = "Interface\\Icons\\INV_Misc_Key_03",
        CharacterSheet = "Interface\\Icons\\INV_Chest_Cloth_17",
        Frames = "Interface\\Icons\\INV_Misc_Wrench_01",
        Tooltip = "Interface\\Icons\\INV_Misc_Spyglass_02",
        CombatTracker = "Interface\\Icons\\Ability_Hunter_SniperShot",
        Groups = "Interface\\Icons\\Spell_Holy_PrayerOfHealing",
        Nameplates = "Interface\\Icons\\Spell_Holy_BlessingOfStrength",
        SocialWidget = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",
        TimeWidget = "Interface\\Icons\\Spell_Holy_BorrowedTime",
        Audio = "Interface\\Icons\\INV_Misc_Bell_01",
        Farming = "Interface\\Icons\\INV_Misc_Shovel_01",
        SettingsSync = "Interface\\Icons\\INV_Gizmo_02",
        ColorPicker = "Interface\\Icons\\INV_Misc_PunchCards_Blue",
    }

    local moduleGroups = {
        { title = WT.L.GROUP_MOD_UI,  modules = { "ActionBars", "Frames", "Nameplates", "CharacterSheet", "ColorPicker" } },
        { title = WT.L.GROUP_MOD_CHAT,          modules = { "Chat", "Keybindings", "SocialWidget", "Groups" } },
        { title = WT.L.GROUP_MOD_INFO, modules = { "Tooltip", "CombatTracker", "TimeWidget" } },
        { title = WT.L.GROUP_MOD_AUTO, modules = { "Automations", "Farming", "SettingsSync" } },
        { title = WT.L.CATEGORY_AUDIO,          modules = { "Audio" } }
    }

    for _, group in ipairs(moduleGroups) do
        local rows = math.ceil(#group.modules / 2)
        local boxHeight = 45 + (rows * 38) + 10

        local groupBg = CreateFrame("Frame", nil, rootBuilder.content, "BackdropTemplate")
        groupBg:SetPoint("TOPLEFT", rootBuilder.content, "TOPLEFT", 10, rootBuilder.cursorY)
        groupBg:SetSize(540, boxHeight)
        groupBg:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        groupBg:SetBackdropColor(WT.Colors.BG_R, WT.Colors.BG_G, WT.Colors.BG_B, WT.Colors.BG_A)
        groupBg:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.4)

        local groupGrad = groupBg:CreateTexture(nil, "BACKGROUND", nil, 1)
        groupGrad:SetPoint("TOPLEFT", 3, -3)
        groupGrad:SetPoint("BOTTOMRIGHT", -3, 3)
        groupGrad:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        SafeSetGradient(groupGrad, "HORIZONTAL", 0, 0, 0, 0, WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G,
            WT.Colors.PRIMARY_B, 0.05)

        local groupTitle = rootBuilder.content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        groupTitle:SetPoint("TOPLEFT", groupBg, "TOPLEFT", 12, -12)
        groupTitle:SetText(group.title)
        groupTitle:SetTextColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B)

        local divider = groupBg:CreateTexture(nil, "ARTWORK")
        divider:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        divider:SetColorTexture(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.2)
        divider:SetPoint("TOPLEFT", groupTitle, "BOTTOMLEFT", 0, -4)
        divider:SetSize(516, 1)

        rootBuilder:AddSpace(45)

        local isRight = false
        for _, modName in ipairs(group.modules) do
            local label = WT.L["OPT_MODULE_" .. string.upper(modName)]
            local desc = WT.L["OPT_DESC_MODULE_" .. string.upper(modName)]
            local icon = moduleIcons[modName] or "Interface\\Icons\\INV_Misc_QuestionMark"

            WT.Config.Builder:CreateModuleToggle(rootBuilder, label, desc, modName, icon, isRight)
            isRight = not isRight
        end

        rootBuilder:AddSpace(25)
    end

    WT.Config.Builder:CreateTitle(rootBuilder, WT.L.CAT_CREDITS)
    AddDescription(rootBuilder,
        WT.L.OPT_DESC_GROUP_CREDITS)

    local supporters = {
        { name = WT.Colors.Classes.MONK .. " Nachtlotus|r",    server = "Zirkel des Cenarius", faction = "Horde" },
        { name = WT.Colors.Classes.MONK .. " Rasthajin|r",     server = "Zirkel des Cenarius", faction = "Horde" },
        { name = WT.Colors.Classes.DEMONHUNTER .. " Yumiya|r", server = "Zirkel des Cenarius", faction = "Horde" },
        { name = WT.Colors.Classes.DRUID .. " Schneedorn|r",   server = "Antonidas",           faction = "Alliance" },
        { name = WT.Colors.Classes.WARLOCK .. " Chryz|r",      server = "Antonidas",           faction = "Alliance" },
        { name = WT.Colors.Classes.MAGE .. " Klopatra|r",      server = "Alleria",             faction = "Alliance" },
    }

    local wofStartY = rootBuilder.cursorY
    local cols = 3
    local colWidth = 520 / cols
    local rowHeight = 35
    local wofHeight = (math.ceil(#supporters / cols) * rowHeight) + 15

    local wofBg = CreateFrame("Frame", nil, rootBuilder.content, "BackdropTemplate")
    wofBg:SetPoint("TOPLEFT", rootBuilder.content, "TOPLEFT", 10, wofStartY)
    wofBg:SetSize(540, wofHeight)
    wofBg:SetFrameLevel(rootBuilder.content:GetFrameLevel() - 1)
    wofBg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    wofBg:SetBackdropColor(WT.Colors.BG_R, WT.Colors.BG_G, WT.Colors.BG_B, WT.Colors.BG_A)
    wofBg:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.3)

    local wofGrad = wofBg:CreateTexture(nil, "BACKGROUND", nil, 1)
    wofGrad:SetPoint("TOPLEFT", 3, -3)
    wofGrad:SetPoint("BOTTOMRIGHT", -3, 3)
    wofGrad:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    SafeSetGradient(wofGrad, "HORIZONTAL", 0, 0, 0, 0, WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B,
        0.05)

    for i, data in ipairs(supporters) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local xOffset = 20 + (col * colWidth)
        local yOffset = wofStartY - 15 - (row * rowHeight)

        local nameFs = rootBuilder.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameFs:SetWidth(colWidth)
        nameFs:SetJustifyH("CENTER")
        nameFs:SetPoint("TOPLEFT", rootBuilder.content, "TOPLEFT", xOffset, yOffset)

        local icon = data.faction == "Alliance" and "|TInterface\\FriendsFrame\\PlusManz-Alliance:12:12:0:0|t" or
            "|TInterface\\FriendsFrame\\PlusManz-Horde:12:12:0:0|t"
        nameFs:SetText(data.name .. " " .. icon)

        if data.server and data.server ~= "" then
            local srvFs = rootBuilder.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            srvFs:SetWidth(colWidth)
            srvFs:SetJustifyH("CENTER")
            srvFs:SetPoint("TOP", nameFs, "BOTTOM", 0, -2)
            srvFs:SetTextColor(WT.Colors.SUBTEXT_R, WT.Colors.SUBTEXT_G, WT.Colors.SUBTEXT_B)
            srvFs:SetText(data.server)
        end
    end

    rootBuilder:AddSpace(wofHeight + 15)
    rootBuilder:UpdateHeight()

    local tabs = {
        { name = "Frames",         check = { "Frames" },                      modules = { "Frames", "ClassColors", "Fader" } },
        { name = "UnitFrames",     check = { "Frames" },                      modules = { "UnitFramesOptions" } },
        { name = "ActionBars",     check = { "ActionBars" },                  modules = { "ActionBars" } },
        { name = "CharacterSheet", check = { "CharacterSheet" },              modules = { "CharacterSheet" } },
        { name = "Nameplates",     check = { "Nameplates" },                  modules = { "Nameplates" } },
        { name = "Tooltip",        check = { "Tooltip" },                     modules = { "Tooltip", "Wowhead" } },
        { name = "Maps",           check = {},                                modules = { "Minimap", "Coords" } },
        { name = "Chat",           check = { "Chat" },                        modules = { "ChatUI", "Chat", "ChatFilter", "ChatChannels" } },
        { name = "Keybindings",    check = { "Keybindings" },                 modules = { "Keybindings" } },
        { name = "Social",         check = { "SocialWidget", "Groups" },      modules = { "SocialWidget", "Groups", "LFG" } },
        { name = "Widgets",        check = { "CombatTracker", "TimeWidget" }, modules = { "CombatTracker", "TimeWidget" } },
        { name = "Automations",    check = { "Automations" },                 modules = { "Automations", "Questing", "Vendor", "Farming" } },
        { name = "Audio",          check = { "Audio" },                       modules = { "Audio" } },
        { name = "SettingsSync",   check = { "SettingsSync" },                modules = { "SettingsSync" } },
    }

    local sortedCategories = {}
    for _, tabData in ipairs(tabs) do
        -- Categories without a module toggle (modules built with WT:NewModule) are always shown
        local isEnabled = #tabData.check == 0
        for _, cMod in ipairs(tabData.check) do
            if WT.DB.Modules[cMod] then
                isEnabled = true; break
            end
        end
        if isEnabled then
            local catName = WT.L["CATEGORY_" .. string.upper(tabData.name)]
            table.insert(sortedCategories, { name = tabData.name, title = catName, subModules = tabData.modules })
        end
    end

    self.ModuleToCategory = {}
    for _, catData in ipairs(tabs) do
        for _, subName in ipairs(catData.modules) do
            self.ModuleToCategory[subName] = catData.name
        end
        if catData.check then
            for _, checkMod in ipairs(catData.check) do
                self.ModuleToCategory[checkMod] = catData.name
            end
        end
    end

    local moduleToggleMap = {
        ActionBars = "ActionBars",
        Frames = "Frames",
        ClassColors = "Frames",
        Fader = "Frames",
        CharacterSheet = "CharacterSheet",
        Nameplates = "Nameplates",
        ChatUI = "Chat",
        Chat = "Chat",
        ChatFilter = "Chat",
        ChatChannels = "Chat",
        Keybindings = "Keybindings",
        SocialWidget = "SocialWidget",
        Groups = "Groups",
        LFG = "Groups",
        Tooltip = "Tooltip",
        Wowhead = "Tooltip",
        CombatTracker = "CombatTracker",
        TimeWidget = "TimeWidget",
        Automations = "Automations",
        Questing = "Automations",
        Vendor = "Automations",
        Audio = "Audio",
        Farming = "Farming",
        SettingsSync = "SettingsSync",
        ColorPicker = "ColorPicker"
    }

    self.SubCategories = {}
    self.isBuilding = true

    local idx = 1
    while idx <= #sortedCategories do
        local catData = sortedCategories[idx]
        WT.Config.Builder.LastCreatedCategory = nil
        local builder = WT.Config.Builder:CreateCategory(rootBuilder.category, catData.title)
        builder.moduleName = catData.name

        AddSearchBar(builder, catData.name)

        for _, subName in ipairs(catData.subModules) do
            local requiredToggle = moduleToggleMap[subName]
            if not requiredToggle or WT.DB.Modules[requiredToggle] then
                local module = WT.Modules[subName]
                -- Modules built with WT:NewModule hide their options on clients that do not support them
                local available = not (module and module.IsAvailable) or module:IsAvailable()
                if module and available and type(module.BuildOptions) == "function" then
                    module:BuildOptions(builder, WT.Config.Builder)
                end
            end
        end
        builder:UpdateHeight()
        if WT.Config.Builder.LastCreatedCategory then
            self.SubCategories[catData.name] = WT.Config.Builder.LastCreatedCategory
        end
        idx = idx + 1
    end

    -- Always add the Profiles (Import/Export) category at the very bottom
    if WT.Config.Profiles and type(WT.Config.Profiles.BuildOptions) == "function" then
        local profBuilder = WT.Config.Builder:CreateCategory(rootBuilder.category, WT.L.CATEGORY_PROFILES)
        profBuilder.moduleName = "Profiles"
        AddSearchBar(profBuilder, "Profiles")
        WT.Config.Profiles:BuildOptions(profBuilder, WT.Config.Builder)
        profBuilder:UpdateHeight()
    end

    self.Category = rootBuilder.category
    self.isBuilding = false

    if self.pendingOpen then
        self.pendingOpen = false
        if Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(self.Category:GetID())
        elseif _G["InterfaceOptionsFrame_OpenToCategory"] then
            _G["InterfaceOptionsFrame_OpenToCategory"](self.Category:GetID())
        end
    end
end
