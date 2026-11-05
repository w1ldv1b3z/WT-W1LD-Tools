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
-- Icons of the option areas on the main page
local AREA_ICONS = {
    Area_Interface  = "Interface\\Icons\\INV_Misc_Wrench_01",
    Area_Widgets    = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    Area_Chat       = "Interface\\Icons\\UI_Chat",
    Area_Graphics   = "Interface\\Icons\\INV_Misc_Spyglass_02",
    Area_Automation = "Interface\\Icons\\Trade_Engineering",
    Audio           = "Interface\\Icons\\INV_Misc_Bell_01",
    Area_Profiles   = "Interface\\Icons\\INV_Gizmo_02",
}

local function StyleCard(frame, alpha)
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(WT.Colors.BG_R, WT.Colors.BG_G, WT.Colors.BG_B, WT.Colors.BG_A)
    frame:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, alpha)
end

--- Clickable tiles that open the option areas.
function Panel:BuildAreaTiles(builder, areaNames)
    if #areaNames == 0 then return end
    WT.Config.Builder:CreateTitle(builder, WT.L.GROUP_AREAS)

    local tileWidth, tileHeight, gap = 266, 62, 8
    local startY = builder.cursorY
    for i, areaName in ipairs(areaNames) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local tile = CreateFrame("Button", nil, builder.content, "BackdropTemplate")
        tile:SetSize(tileWidth, tileHeight)
        tile:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 10 + col * (tileWidth + gap), startY - row * (tileHeight + gap))
        StyleCard(tile, 0.35)

        local icon = tile:CreateTexture(nil, "ARTWORK")
        icon:SetSize(38, 38)
        icon:SetPoint("LEFT", tile, "LEFT", 12, 0)
        icon:SetTexture(AREA_ICONS[areaName] or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local name = tile:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
        name:SetText(WT.L["CATEGORY_" .. string.upper(areaName)])
        name:SetTextColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B)

        local desc = tile:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
        desc:SetWidth(tileWidth - 70)
        desc:SetJustifyH("LEFT")
        desc:SetMaxLines(2)
        desc:SetText(WT.L["OPT_DESC_" .. string.upper(areaName)])
        desc:SetTextColor(WT.Colors.SUBTEXT_R, WT.Colors.SUBTEXT_G, WT.Colors.SUBTEXT_B)

        local highlight = tile:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetPoint("TOPLEFT", 3, -3)
        highlight:SetPoint("BOTTOMRIGHT", -3, 3)
        highlight:SetColorTexture(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.12)

        tile:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.9) end)
        tile:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.35) end)
        tile:SetScript("OnClick", function()
            local category = self.SubCategories and self.SubCategories[areaName]
            if category and Settings and Settings.OpenToCategory then
                Settings.OpenToCategory(category:GetID())
            end
        end)
    end
    builder:AddSpace(math.ceil(#areaNames / 2) * (tileHeight + gap) + 10)
end

-- ============================================================================
-- CREDITS
-- ============================================================================
-- Player names (not characters) with a personal title. Names and titles are personal and are
-- shown exactly as written in every language, so they are data here and not in the language files.
-- Order = order on the page. icon = texture shown in the title badge and as a large watermark.
local CREDITS = {
    { name = "Schneedorn", title = "SUPPORT",       r = 1.00, g = 0.45, b = 0.65, icon = "Interface\\Icons\\INV_Misc_Flower_04" },
    { name = "Jasmin",     title = "RUHEPOL",       r = 0.35, g = 0.90, b = 0.80, icon = "Interface\\Icons\\INV_Misc_Flower_02" },
    { name = "Adrian",     title = "TANKGOTT",      r = 0.55, g = 0.70, b = 1.00, icon = "Interface\\Icons\\INV_Shield_06" },
    { name = "B-Town",     title = "THE WHIZZARD!", r = 0.75, g = 0.50, b = 1.00, icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
}

local SHINE_DURATION = 1.2
local SHINE_PAUSE = 5

--- Adds a soft light sweep that runs across a card every few seconds.
local function AddShine(card, cardWidth, cardHeight, delay)
    card:SetClipsChildren(true)
    local shine = CreateFrame("Frame", nil, card)
    shine:SetSize(60, cardHeight)
    shine:SetPoint("LEFT", card, "LEFT", -70, 0)

    local left = shine:CreateTexture(nil, "OVERLAY")
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMRIGHT", shine, "BOTTOM", 0, 0)
    left:SetColorTexture(1, 1, 1, 1)
    SafeSetGradient(left, "HORIZONTAL", 1, 1, 1, 0, 1, 1, 1, 0.12)
    local right = shine:CreateTexture(nil, "OVERLAY")
    right:SetPoint("TOPLEFT", shine, "TOP", 0, 0); right:SetPoint("BOTTOMRIGHT")
    right:SetColorTexture(1, 1, 1, 1)
    SafeSetGradient(right, "HORIZONTAL", 1, 1, 1, 0.12, 1, 1, 1, 0)

    local group = shine:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    local sweep = group:CreateAnimation("Translation")
    sweep:SetOffset(cardWidth + 140, 0)
    sweep:SetDuration(SHINE_DURATION)
    sweep:SetStartDelay(delay)
    sweep:SetSmoothing("IN_OUT")
    sweep:SetOrder(1)
    local pause = group:CreateAnimation("Alpha")
    pause:SetFromAlpha(1); pause:SetToAlpha(1)
    pause:SetDuration(SHINE_PAUSE)
    pause:SetOrder(2)
    -- Only animate while the options page is visible
    card:HookScript("OnShow", function() group:Play() end)
    card:HookScript("OnHide", function() group:Stop() end)
    if card:IsVisible() then group:Play() end
end

local function CreateTitleBadge(card, person, anchor)
    local badge = CreateFrame("Frame", nil, card, "BackdropTemplate")
    badge:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    badge:SetBackdropColor(person.r, person.g, person.b, 0.15)
    badge:SetBackdropBorderColor(person.r, person.g, person.b, 0.6)

    local icon = badge:CreateTexture(nil, "ARTWORK")
    icon:SetSize(12, 12)
    icon:SetPoint("LEFT", badge, "LEFT", 4, 0)
    icon:SetTexture(person.icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local text = badge:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    text:SetText(person.title)
    text:SetTextColor(person.r, person.g, person.b)

    badge:SetSize(text:GetStringWidth() + 26, 16)
    badge:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
end

--- Thank-you section: one card per person with a personal title badge.
function Panel:BuildCredits(builder)
    WT.Config.Builder:CreateTitle(builder, WT.L.CAT_CREDITS)
    local intro = builder.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    intro:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 16, builder.cursorY)
    intro:SetWidth(530)
    intro:SetJustifyH("LEFT")
    intro:SetText(WT.L.OPT_DESC_GROUP_CREDITS)
    builder:AddSpace(intro:GetStringHeight() + 15)

    local cols, cardWidth, cardHeight, gap = 2, 266, 62, 8
    local startY = builder.cursorY
    for i, person in ipairs(CREDITS) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)

        local card = CreateFrame("Frame", nil, builder.content, "BackdropTemplate")
        card:SetSize(cardWidth, cardHeight)
        card:SetPoint("TOPLEFT", builder.content, "TOPLEFT", 10 + col * (cardWidth + gap), startY - row * (cardHeight + gap))
        StyleCard(card, 0.25)
        card:SetBackdropBorderColor(person.r, person.g, person.b, 0.45)

        -- Colored accent stripe on the left in the color of the person
        local stripe = card:CreateTexture(nil, "ARTWORK")
        stripe:SetPoint("TOPLEFT", 4, -4)
        stripe:SetPoint("BOTTOMLEFT", 4, 4)
        stripe:SetWidth(3)
        stripe:SetColorTexture(person.r, person.g, person.b, 0.9)

        local glow = card:CreateTexture(nil, "BACKGROUND", nil, 1)
        glow:SetPoint("TOPLEFT", 3, -3)
        glow:SetPoint("BOTTOMRIGHT", -3, 3)
        glow:SetColorTexture(1, 1, 1, 1)
        SafeSetGradient(glow, "HORIZONTAL", person.r, person.g, person.b, 0.16, person.r, person.g, person.b, 0)

        -- Large faded icon on the right as a personal watermark
        local watermark = card:CreateTexture(nil, "BORDER")
        watermark:SetSize(cardHeight - 12, cardHeight - 12)
        watermark:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        watermark:SetTexture(person.icon)
        watermark:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        watermark:SetAlpha(0.22)

        local name = card:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        name:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -10)
        name:SetWidth(cardWidth - 22)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        name:SetText(person.name)
        name:SetTextColor(1, 1, 1)

        CreateTitleBadge(card, person, name)

        AddShine(card, cardWidth, cardHeight, (i - 1) * 0.35)
    end
    builder:AddSpace(math.ceil(#CREDITS / cols) * (cardHeight + gap) + 15)
end

function Panel:Build()
    -- 1. Root Category (Main Entry)
    local rootBuilder = WT.Config.Builder:CreateCategory(nil, WT.L.OPTIONS_TITLE)
    rootBuilder.moduleName = "General"
    rootBuilder.path = WT.L.CATEGORY_GENERAL
    Settings.RegisterAddOnCategory(rootBuilder.category)

    -- Header card: logo, name, short description and version information
    local clientText = string.format(WT.L.UI_CLIENT_BUILD, WT.Compat:GetFlavorName(), WT.Compat.ClientVersion,
        tostring(WT.Compat.BuildNumber), WT.Compat.BuildDate)

    rootBuilder:AddSpace(20)
    local header = CreateFrame("Frame", nil, rootBuilder.content, "BackdropTemplate")
    header:SetPoint("TOPLEFT", rootBuilder.content, "TOPLEFT", 10, rootBuilder.cursorY)
    header:SetSize(540, 96)
    header:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    header:SetBackdropColor(WT.Colors.BG_R, WT.Colors.BG_G, WT.Colors.BG_B, WT.Colors.BG_A)
    header:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.6)

    local headerGlow = header:CreateTexture(nil, "BACKGROUND", nil, 1)
    headerGlow:SetPoint("TOPLEFT", 3, -3)
    headerGlow:SetPoint("BOTTOMRIGHT", -3, 3)
    headerGlow:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    SafeSetGradient(headerGlow, "HORIZONTAL", WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.18,
        WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0)

    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(64, 64)
    logo:SetPoint("LEFT", header, "LEFT", 16, 0)
    logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\Media\\Graphics\\Logo.tga")

    local title = header:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 16, -4)
    title:SetText(WT.Colors.PRIMARY .. WT.L.OPTIONS_TITLE .. "|r")

    local tagline = header:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    tagline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    tagline:SetWidth(430)
    tagline:SetJustifyH("LEFT")
    tagline:SetText(WT.L.OPTIONS_DESC)

    local info = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", tagline, "BOTTOMLEFT", 0, -6)
    info:SetWidth(430)
    info:SetJustifyH("LEFT")
    info:SetText(string.format(WT.L.UI_INFO_LINE, WT.Version, clientText, WT.Author))
    info:SetTextColor(WT.Colors.SUBTEXT_R, WT.Colors.SUBTEXT_G, WT.Colors.SUBTEXT_B)

    rootBuilder:AddSpace(96 + 15)

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

                -- Every options page stores its position in the menu tree as "Area > Page"
                local path = match.builder and match.builder.path or ""
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


    local moduleToggleMap = {
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
        Groups = "Groups",
        LFG = "Groups",
        Tooltip = "Tooltip",
        Wowhead = "Tooltip",
        Automations = "Automations",
        Questing = "Automations",
        Vendor = "Automations",
        Audio = "Audio",
        Farming = "Farming",
        SettingsSync = "SettingsSync",
        ColorPicker = "ColorPicker"
    }

    -- Options tree: areas (first level below WT) with pages (second level).
    -- A module entry is either a module name or { module, part } for modules that spread their
    -- options over several pages (see the "part" argument of their BuildOptions).
    -- Areas without "pages" show their modules directly on the area page.
    local menu = {
        { name = "Area_Interface", pages = {
            { name = "ActionBars",     modules = { "ActionBars", "Fader" } },
            { name = "UnitFrames",     modules = { "UnitFramesOptions" } },
            { name = "Nameplates",     modules = { "Nameplates" } },
            { name = "Tooltip",        modules = { "Tooltip", "Wowhead" } },
            { name = "Maps",           modules = { "Minimap", "Coords", { "Frames", "MapFade" } } },
            { name = "CharacterSheet", modules = { "CharacterSheet" } },
            { name = "Windows",        modules = { { "Frames", "Windows" } } },
            { name = "ClassColors",    modules = { "ClassColors" } },
        } },
        { name = "Area_Widgets", pages = {
            { name = "SocialWidget",   modules = { "SocialWidget" } },
            { name = "TimeWidget",     modules = { "TimeWidget" } },
            { name = "CombatTracker",  modules = { "CombatTracker" } },
            { name = "SystemWidget",   modules = { { "Frames", "SystemWidget" } } },
        } },
        { name = "Area_Chat", pages = {
            { name = "ChatDisplay",    modules = { { "ChatUI", "Display" } } },
            { name = "ChatFunctions",  modules = { { "ChatUI", "Functions" }, { "Chat", "Functions" } } },
            { name = "ChatGuild",      modules = { { "Chat", "Guild" } } },
            { name = "ChatFilter",     modules = { "ChatFilter" } },
            { name = "ChatChannels",   modules = { "ChatChannels" } },
            { name = "ChatHotkeys",    modules = { "Keybindings" } },
        } },
        { name = "Area_Graphics", modules = { { "Frames", "Graphics" } } },
        { name = "Area_Automation", pages = {
            { name = "AutoGeneral",    modules = { { "Automations", "General" } } },
            { name = "Questing",       modules = { "Questing" } },
            { name = "Vendors",        modules = { "Vendor" } },
            { name = "Groups",         modules = { "Groups", "LFG" } },
            { name = "Farming",        modules = { "Farming" } },
            { name = "ClassHelpers",   modules = { { "Automations", "ClassHelpers" } } },
        } },
        { name = "Audio", modules = { "Audio" } },
        { name = "Area_Profiles", pages = {
            { name = "SettingsSync",   modules = { "SettingsSync" } },
            { name = "Profiles",       modules = { "Profiles" } },
        } },
    }

    local function GetEntryModule(entry)
        local moduleName, part = entry, nil
        if type(entry) == "table" then moduleName, part = entry[1], entry[2] end
        local module = (moduleName == "Profiles") and WT.Config.Profiles or WT.Modules[moduleName]
        return moduleName, module, part
    end

    -- An entry is shown when its module exists, is supported on this client, has options and
    -- (for modules in the old format) its module toggle is on.
    local function IsEntryVisible(entry)
        local moduleName, module = GetEntryModule(entry)
        if not module or type(module.BuildOptions) ~= "function" then return false end
        local requiredToggle = moduleToggleMap[moduleName]
        if requiredToggle and not WT.DB.Modules[requiredToggle] then return false end
        return not module.IsAvailable or module:IsAvailable()
    end

    local function HasVisibleEntries(modules)
        for _, entry in ipairs(modules or {}) do
            if IsEntryVisible(entry) then return true end
        end
        return false
    end

    local function GetTitle(name)
        return WT.L["CATEGORY_" .. string.upper(name)]
    end

    self.SubCategories = {}
    self.ModuleToCategory = {}
    self.isBuilding = true

    local function BuildPage(parentCategory, pageData, path)
        WT.Config.Builder.LastCreatedCategory = nil
        local pageTitle = GetTitle(pageData.name)
        local builder = WT.Config.Builder:CreateCategory(parentCategory, pageTitle)
        builder.moduleName = pageData.name
        builder.path = path and (path .. " > " .. pageTitle) or pageTitle
        AddSearchBar(builder, pageData.name)

        for _, entry in ipairs(pageData.modules or {}) do
            if IsEntryVisible(entry) then
                local moduleName, module, part = GetEntryModule(entry)
                module:BuildOptions(builder, WT.Config.Builder, part)
                -- Module toggles and search results jump to the first page of a module
                self.ModuleToCategory[moduleName] = self.ModuleToCategory[moduleName] or pageData.name
                local toggle = moduleToggleMap[moduleName]
                if toggle then self.ModuleToCategory[toggle] = self.ModuleToCategory[toggle] or pageData.name end
            end
        end
        builder:UpdateHeight()
        self.SubCategories[pageData.name] = builder.category
        return builder
    end

    local visibleAreas = {}
    for _, area in ipairs(menu) do
        local visiblePages = {}
        for _, page in ipairs(area.pages or {}) do
            if HasVisibleEntries(page.modules) then visiblePages[#visiblePages + 1] = page end
        end

        if area.pages and #visiblePages > 0 then
            -- Area page: short overview with buttons to its pages
            local areaTitle = GetTitle(area.name)
            local areaBuilder = BuildPage(rootBuilder.category, { name = area.name }, nil)
            WT.Config.Builder:CreateTitle(areaBuilder, areaTitle)
            AddDescription(areaBuilder, WT.L["OPT_DESC_" .. string.upper(area.name)])
            for _, page in ipairs(visiblePages) do
                local pageName = page.name
                WT.Config.Builder:CreateButton(areaBuilder, GetTitle(pageName), WT.L.BTN_OPEN, nil, function()
                    local category = self.SubCategories[pageName]
                    if category and Settings and Settings.OpenToCategory then
                        Settings.OpenToCategory(category:GetID())
                    end
                end)
            end
            areaBuilder:UpdateHeight()

            for _, page in ipairs(visiblePages) do
                BuildPage(areaBuilder.category, page, areaTitle)
            end
            visibleAreas[#visibleAreas + 1] = area.name
        elseif HasVisibleEntries(area.modules) then
            BuildPage(rootBuilder.category, area, nil)
            visibleAreas[#visibleAreas + 1] = area.name
        end
    end


    -- Main page, part 2 (needs the options tree): area tiles, general settings, module overview, credits
    self:BuildAreaTiles(rootBuilder, visibleAreas)

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
        Chat = "Interface\\Icons\\UI_Chat",
        Keybindings = "Interface\\Icons\\INV_Misc_Key_03",
        CharacterSheet = "Interface\\Icons\\INV_Chest_Cloth_17",
        Frames = "Interface\\Icons\\INV_Misc_Wrench_01",
        Tooltip = "Interface\\Icons\\INV_Misc_Spyglass_02",
        Groups = "Interface\\Icons\\Spell_Holy_PrayerOfHealing",
        Nameplates = "Interface\\Icons\\Spell_Holy_BlessingOfStrength",
        Audio = "Interface\\Icons\\INV_Misc_Bell_01",
        Farming = "Interface\\Icons\\INV_Misc_Shovel_01",
        SettingsSync = "Interface\\Icons\\INV_Gizmo_02",
        ColorPicker = "Interface\\Icons\\INV_Misc_PunchCards_Blue",
    }

    local moduleGroups = {
        { title = WT.L.GROUP_MOD_UI,  modules = { "Frames", "Nameplates", "CharacterSheet", "ColorPicker" } },
        { title = WT.L.GROUP_MOD_CHAT,          modules = { "Chat", "Keybindings", "Groups" } },
        { title = WT.L.GROUP_MOD_INFO, modules = { "Tooltip" } },
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


    self:BuildCredits(rootBuilder)
    rootBuilder:UpdateHeight()

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
