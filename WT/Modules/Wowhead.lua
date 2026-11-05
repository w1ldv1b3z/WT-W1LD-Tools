local _, WT = ...

WT.Modules.Wowhead = {}
local Module = WT.Modules.Wowhead

local popupFrame = nil

local Unsecret = WT.Utils.Safety.Unsecret

local function CreatePopup()
    if popupFrame then return end

    popupFrame = CreateFrame("Frame", "WTWowheadPopup", _G["WT_UIContainer"], "BackdropTemplate")
    popupFrame:SetSize(350, 70)
    popupFrame:SetPoint("CENTER", _G["WT_UIContainer"], "CENTER", 0, 100)
    popupFrame:SetFrameStrata("DIALOG")
    popupFrame:SetFrameLevel(9000)
    popupFrame:Hide()
    
    popupFrame.ignoreInLayout = true
    popupFrame.ignoreFramePositionManager = true
    if popupFrame.SetIsFramePositionManaged then pcall(function() popupFrame:SetIsFramePositionManaged(false) end) end

    popupFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    popupFrame:SetBackdropColor(WT.Colors.STD_BG_R, WT.Colors.STD_BG_G, WT.Colors.STD_BG_B, WT.Colors.STD_BG_A)
    popupFrame:SetBackdropBorderColor(WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B, 0.8)

    popupFrame.title = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    popupFrame.title:SetPoint("TOP", popupFrame, "TOP", 12, -10)
    popupFrame.title:SetText(WT.L.WOWHEAD_LINK_TITLE)

    popupFrame.icon = popupFrame:CreateTexture(nil, "ARTWORK")
    popupFrame.icon:SetSize(18, 18)
    popupFrame.icon:SetPoint("RIGHT", popupFrame.title, "LEFT", -6, 0)
    popupFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    popupFrame.editBox = CreateFrame("EditBox", nil, popupFrame, "InputBoxTemplate")
    popupFrame.editBox:SetSize(300, 20)
    popupFrame.editBox:SetPoint("BOTTOM", popupFrame, "BOTTOM", 0, 15)
    popupFrame.editBox:SetAutoFocus(true)
    popupFrame.editBox:SetFontObject("ChatFontNormal")
    
    popupFrame.editBox:SetScript("OnCursorChanged", function(self)
        if self:HasFocus() then self:HighlightText() end
    end)
    popupFrame.editBox:SetScript("OnEscapePressed", function(self)
        self:GetParent():Hide()
    end)

    local closeBtn = CreateFrame("Button", nil, popupFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", popupFrame, "TOPRIGHT", -4, -4)
    closeBtn:SetFrameLevel(popupFrame:GetFrameLevel() + 10)
    closeBtn:SetScript("OnClick", function(self) self:GetParent():Hide() end)

    -- Add to UISpecialFrames to allow closing with the ESC key
    table.insert(UISpecialFrames, "WTWowheadPopup")

    if WT.Modules.Frames and WT.Modules.Frames.HookFrameForMove and WT.DB.Frames and WT.DB.Frames.MovableFrames then
        WT.Modules.Frames:HookFrameForMove(popupFrame)
    end
end

local function ShowPopup(url)
    if not popupFrame then CreatePopup() end
    local f = popupFrame
    if f and f.Show then
        local eb = f["editBox"]
        if eb then
            eb:SetText(url)
            -- Dynamically adjust icon and title based on the URL
            if string.find(url, "raider.io", 1, true) then
                f.title:SetText("|cFFFF8800Raider.io|r Link")
                f.icon:SetTexture("Interface\\Icons\\Achievement_Boss_Blackhand")
            elseif string.find(url, "foreverdb", 1, true) then
                f.title:SetText("|cFF00FFFFForeverDB|r Link")
                f.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
            else
                local subTitle = (WT.Compat and WT.Compat.IsForever) and "|cFFFF0000Wowhead (Forever)|r Link" or "|cFFFF0000Wowhead|r Link"
                f.title:SetText(subTitle)
                f.icon:SetTexture("Interface\\Icons\\INV_Misc_Bomb_04")
            end
            f:Show()
            eb:SetFocus()
            eb:HighlightText()
        end
    end
end

Module.ShowPopup = ShowPopup

local function ProcessWowheadLink(link)
    if WT.DB and WT.DB.Wowhead and WT.DB.Wowhead.EnableLinks == false then return false end
    if not link then return false end
    local linkType, id = string.match(link, "|Hwtwowhead:([^:]+):([^|]+)")
    if not linkType then
        linkType, id = string.match(link, "|H([^:]+):([^|:]+)")
    end
    if not linkType then
        linkType, id = string.match(link, "^([^:]+):([^|]+)")
    end

    if linkType and id then
        -- Player Profile Integration (Raider.io for Retail, ForeverDB for Forever)
        if linkType == "player" or linkType == "bnplayer" then
            local name, realm, overrideRegion
            local base
            base, overrideRegion = string.match(id, "^(.-):(.*)$")
            if base then
                name, realm = string.match(base, "^([^%-]+)%-(.+)$")
                if not name then name = base end
            else
                name, realm = string.match(id, "^([^%-]+)%-(.+)$")
                if not name then name = id end
            end
            
            if not realm or realm == "" then
                realm = string.gsub(GetRealmName() or "", "%s+", "")
            end
            if name and realm then
                local region = overrideRegion or (WT.Utils.Realms and WT.Utils.Realms:GetRegion(realm) or "eu")
                if region == "US" or region == "BR" or region == "MX" or region == "AU" or region == "us" then region = "us" 
                elseif region == "KR" or region == "kr" then region = "kr"
                elseif region == "TW" or region == "tw" then region = "tw"
                else region = "eu" end
                
                local realmSlug = string.lower(realm):gsub("[%s%p]", "")
                local nameSlug = string.lower(name)
                
                local url
                if WT.Compat and WT.Compat.IsForever then
                    url = string.format("https://foreverdb.net/player/%s/%s/%s", region, realmSlug, nameSlug)
                else
                    url = string.format("https://raider.io/characters/%s/%s/%s", region, realmSlug, nameSlug)
                end
                ShowPopup(url)
                return true
            end
        end

        local url = ""
        local lang = GetLocale()
        local langPrefix = "www."
        
        if lang == "deDE" then langPrefix = "de."
        elseif lang == "frFR" then langPrefix = "fr."
        elseif lang == "esES" or lang == "esMX" then langPrefix = "es."
        elseif lang == "ruRU" then langPrefix = "ru."
        elseif lang == "ptBR" or lang == "ptPT" then langPrefix = "pt."
        elseif lang == "itIT" then langPrefix = "it."
        elseif lang == "koKR" then langPrefix = "ko."
        end

        if linkType == "item" or linkType == "spell" or linkType == "enchant" or linkType == "achievement" or linkType == "quest" or linkType == "currency" or linkType == "mount" or linkType == "npc" then
            local resolvedType = (linkType == "enchant") and "spell" or linkType
            local subPath = (WT.Compat and WT.Compat.GetWowheadSubdomain and WT.Compat:GetWowheadSubdomain()) or ""
            url = string.format("https://%swowhead.com/%s%s=%s", langPrefix, subPath, resolvedType, id)
            ShowPopup(url)
            return true
        end
    end
    return false
end

Module.ProcessWowheadLink = ProcessWowheadLink

local function ShouldHideWowheadHint(owner)
    if not owner then return false end
    if owner.action then return true end
    
    local current = owner
    while current do
        local name = Unsecret(current:GetName())
        if name then
            if string.find(name, "ActionButton", 1, true) or string.find(name, "MultiBar", 1, true) or string.find(name, "StanceButton", 1, true) or 
                string.find(name, "PetAction", 1, true) or string.find(name, "PlayerSpellsFrame", 1, true) or string.find(name, "ClassTalentFrame", 1, true) or 
                string.find(name, "SpellBook", 1, true) or string.find(name, "SpellButton", 1, true) or string.find(name, "TalentButton", 1, true) or 
                string.find(name, "ZoneAbility", 1, true) or string.find(name, "ObjectiveTracker", 1, true) or string.find(name, "Kaliel", 1, true) or string.find(name, "QuestMap", 1, true) or
                string.match(name, "House") or string.match(name, "Housing") then
                return true
            end
        end
        if current == _G["HouseListFrame"] or current == _G["HouseEditorFrame"] then return true end
        if current == UIParent then break end
        local ok, p = pcall(current.GetParent, current)
        if ok and p then current = p else break end
    end
    return false
end

local function AddWowheadHint(tooltip)
    if WT.DB and WT.DB.Wowhead and WT.DB.Wowhead.EnableLinks == false then return end
    if not WT.DB.Wowhead.ShowTooltipHint then return end
    if tooltip:IsForbidden() then return end
    
    local tooltipName = WT.Utils.Safety.GetSafeTooltipName(tooltip)
    
    if tooltipName and string.find(tooltipName, "ShoppingTooltip", 1, true) then return end
    if not ShouldHideWowheadHint(tooltip:GetOwner()) then
        local hintText = tostring(WT.L.TT_WOWHEAD_HINT)
        local found = false
        if tooltipName and type(tooltip.NumLines) == "function" then
            for i = 1, tooltip:NumLines() do
                local line = _G[tooltipName .. "TextLeft" .. i]
                if line and line:GetText() == hintText then
                    if i == tooltip:NumLines() then
                        found = true
                    else
                        line:SetText("")
                        local prevLine = _G[tooltipName .. "TextLeft" .. (i - 1)]
                        if prevLine and prevLine:GetText() == " " then prevLine:SetText("") end
                    end
                end
            end
        end
        
        if not found then
            tooltip:AddLine(" ")
            tooltip:AddLine(hintText, WT.Colors.PRIMARY_R, WT.Colors.PRIMARY_G, WT.Colors.PRIMARY_B)
        end
    end
end

function Module:Initialize()
    if not WT.DB.Modules.Tooltip then return end

    hooksecurefunc("SetItemRef", function(link, text, button, chatFrame)
        if IsAltKeyDown() and not IsControlKeyDown() and not IsShiftKeyDown() and button ~= "RightButton" then
            C_Timer.After(0.01, function() ProcessWowheadLink(link) end)
        end
    end)

    hooksecurefunc("HandleModifiedItemClick", function(link)
        if IsAltKeyDown() and not IsControlKeyDown() and not IsShiftKeyDown() and GetMouseButtonClicked() ~= "RightButton" then
            C_Timer.After(0.01, function() ProcessWowheadLink(link) end)
        end
    end)
    
    local function HookAchievementButtons()
        if Module.achievementsHooked then return end
        if _G["AchievementButton_OnClick"] then
            Module.achievementsHooked = true
            hooksecurefunc("AchievementButton_OnClick", function(self)
                if IsAltKeyDown() and self.id then
                    C_Timer.After(0.01, function() ProcessWowheadLink("achievement:" .. self.id) end)
                end
            end)
        else
            local mixin = _G["AchievementTemplateMixin"]
            if mixin and type(mixin.OnClick) == "function" then
                Module.achievementsHooked = true
                hooksecurefunc(mixin, "OnClick", function(self)
                    if IsAltKeyDown() and self.id then
                        C_Timer.After(0.01, function() ProcessWowheadLink("achievement:" .. self.id) end)
                    end
                end)
            end
        end
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI") then
        HookAchievementButtons()
    else
        WT.Core.Events:Register("ADDON_LOADED", function(_, addon)
            if addon == "Blizzard_AchievementUI" then
                HookAchievementButtons()
            end
        end)
    end

    local function HookProfessionButtons()
        if Module.professionsHooked then return end
        local mixin = _G["ProfessionsRecipeListRecipeButtonMixin"]
        if mixin and type(mixin.OnClick) == "function" then
            Module.professionsHooked = true
            hooksecurefunc(mixin, "OnClick", function(self)
                if IsAltKeyDown() then
                    local recipeID = self.elementData and self.elementData.recipeInfo and self.elementData.recipeInfo.recipeID
                    if not recipeID and self.recipeInfo then recipeID = self.recipeInfo.recipeID end
                    if recipeID then
                        C_Timer.After(0.01, function() ProcessWowheadLink("spell:" .. recipeID) end)
                    end
                end
            end)
        end
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Professions") then
        HookProfessionButtons()
    else
        WT.Core.Events:Register("ADDON_LOADED", function(_, addon)
            if addon == "Blizzard_Professions" then
                HookProfessionButtons()
            end
        end)
    end

    local function HookTalentButtons()
        if Module.talentsHooked then return end
        local mixin = _G["TalentButtonMixin"]
        if mixin and type(mixin.OnClick) == "function" then
            Module.talentsHooked = true
            hooksecurefunc(mixin, "OnClick", function(self)
                if IsAltKeyDown() then
                    local spellID = (type(self.GetSpellID) == "function" and self:GetSpellID()) or self.spellID
                    if spellID then
                        C_Timer.After(0.01, function() ProcessWowheadLink("spell:" .. spellID) end)
                    end
                end
            end)
        end
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_ClassTalentUI") then
        HookTalentButtons()
    else
        WT.Core.Events:Register("ADDON_LOADED", function(_, addon)
            if addon == "Blizzard_ClassTalentUI" then
                HookTalentButtons()
            end
        end)
    end

    -- 100% Usability: Explicitly hook bags, since native HandleModifiedItemClick ignores Alt-Clicks
    local cfibm = _G["ContainerFrameItemButtonMixin"]
    if cfibm and type(cfibm.OnClick) == "function" then
        hooksecurefunc(cfibm, "OnClick", function(self, button)
            if IsAltKeyDown() and not IsControlKeyDown() and not IsShiftKeyDown() and button ~= "RightButton" then
                local itemID = self:GetItemID()
                if itemID then C_Timer.After(0.01, function() ProcessWowheadLink("item:" .. itemID) end) end
            end
        end)
    end

    -- 100% Usability: Explicitly hook the modern Spellbook (WoW 11.0+)
    local function HookSpellbook()
        local sbm = _G["SpellBookItemMixin"]
        if sbm and type(sbm.OnClick) == "function" then
            hooksecurefunc(sbm, "OnClick", function(self)
                if IsAltKeyDown() and not IsControlKeyDown() and not IsShiftKeyDown() then
                    local spellID = (self.spellBookItemInfo and self.spellBookItemInfo.spellID) or self.spellID
                    if spellID then C_Timer.After(0.01, function() ProcessWowheadLink("spell:" .. spellID) end) end
                end
            end)
        end
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_PlayerSpells") then
        HookSpellbook()
    else
        WT.Core.Events:Register("ADDON_LOADED", function(_, addon)
            if addon == "Blizzard_PlayerSpells" then HookSpellbook() end
        end)
    end

    -- 100% Usability: Explicitly hook the Mount Journal
    local function HookMounts()
        local mdbm = _G["MountListDragButtonMixin"]
        if mdbm and type(mdbm.OnClick) == "function" then
            hooksecurefunc(mdbm, "OnClick", function(self)
                if IsAltKeyDown() and not IsControlKeyDown() and not IsShiftKeyDown() and self.spellID then
                    C_Timer.After(0.01, function() ProcessWowheadLink("mount:" .. self.spellID) end)
                end
            end)
        end
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Collections") then
        HookMounts()
    else
        WT.Core.Events:Register("ADDON_LOADED", function(_, addon)
            if addon == "Blizzard_Collections" then HookMounts() end
        end)
    end

    -- 100% Usability: Explicitly hook the Encounter Journal
    local function HookEncounterJournal()
        local ejim = _G["EncounterJournalItemMixin"]
        if ejim and type(ejim.OnClick) == "function" then
            hooksecurefunc(ejim, "OnClick", function(self)
                if IsAltKeyDown() and not IsControlKeyDown() and not IsShiftKeyDown() then
                    if self.itemID then
                        C_Timer.After(0.01, function() ProcessWowheadLink("item:" .. self.itemID) end)
                    elseif self.link then
                        C_Timer.After(0.01, function() ProcessWowheadLink(self.link) end)
                    end
                end
            end)
        end
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
        HookEncounterJournal()
    else
        WT.Core.Events:Register("ADDON_LOADED", function(_, addon)
            if addon == "Blizzard_EncounterJournal" then HookEncounterJournal() end
        end)
    end

    -- 100% Usability: Explicitly hook the Transmog Wardrobe
    local function HookWardrobe()
        if Module.wardrobeHooked then return end
        local mixin = _G["WardrobeCollectionFrameModelMixin"]
        if mixin and type(mixin.OnMouseDown) == "function" then
            Module.wardrobeHooked = true
            hooksecurefunc(mixin, "OnMouseDown", function(self, button)
                if IsAltKeyDown() and self.visualInfo and self.visualInfo.sourceID then
                    local sourceInfo = C_TransmogCollection.GetSourceInfo(self.visualInfo.sourceID)
                    if sourceInfo and sourceInfo.itemID then
                        C_Timer.After(0.01, function() ProcessWowheadLink("item:" .. sourceInfo.itemID) end)
                    end
                end
            end)
        end
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Collections") then
        HookWardrobe()
    else
        WT.Core.Events:Register("ADDON_LOADED", function(_, addon)
            if addon == "Blizzard_Collections" then HookWardrobe() end
        end)
    end

    -- Raider.io: LFG List Hooks
    local lfgSearchMixin = _G["LFGListSearchEntryMixin"]
    if lfgSearchMixin and type(lfgSearchMixin.OnClick) == "function" then
        hooksecurefunc(lfgSearchMixin, "OnClick", function(self)
            if IsAltKeyDown() and self.resultID then
                local ok, result = pcall(C_LFGList.GetSearchResultInfo, self.resultID)
                if ok and result and result.leaderName then
                    C_Timer.After(0.01, function() ProcessWowheadLink("player:" .. result.leaderName) end)
                end
            end
        end)
    end
    
    local lfgAppMixin = _G["LFGListApplicationViewerScrollFrameButtonMixin"]
    if lfgAppMixin and type(lfgAppMixin.OnClick) == "function" then
        hooksecurefunc(lfgAppMixin, "OnClick", function(self)
            if IsAltKeyDown() and self.applicantID then
                local ok, name = pcall(C_LFGList.GetApplicantMemberInfo, self.applicantID, 1)
                if ok and name then
                    C_Timer.After(0.01, function() ProcessWowheadLink("player:" .. name) end)
                end
            end
        end)
    end
    
    -- Raider.io: Unit Frame Hooks
    local function HookUnitFrame(frame)
        if frame then
            frame:HookScript("OnMouseUp", function(self, button)
                if IsAltKeyDown() and self.unit and UnitIsPlayer(self.unit) then
                    local name, realm = UnitName(self.unit)
                    if name then
                        if not realm or realm == "" then realm = string.gsub(GetRealmName() or "", "%s+", "") end
                        C_Timer.After(0.01, function() ProcessWowheadLink("player:" .. name .. "-" .. realm) end)
                    end
                end
            end)
        end
    end
    HookUnitFrame(TargetFrame)
    HookUnitFrame(FocusFrame)

    if not self.ttData then self.ttData = setmetatable({}, { __mode = "k" }) end
    local ttData = self.ttData
    
    if ItemRefTooltip then
        local iData = ttData[ItemRefTooltip]
        if not iData then iData = {}; ttData[ItemRefTooltip] = iData end
        
        if not iData.wtLinkHooked then
            iData.wtLinkHooked = true
            hooksecurefunc(ItemRefTooltip, "SetHyperlink", function(self, link)
                local sData = ttData[self]
                if not sData then sData = {}; ttData[self] = sData end
                sData.wtCurrentLink = link
            end)
            ItemRefTooltip:HookScript("OnMouseUp", function(self, button)
                local sData = ttData[self]
                if button == "RightButton" and sData and sData.wtCurrentLink then
                    C_Timer.After(0.01, function()
                        if ProcessWowheadLink(sData.wtCurrentLink) then self:Hide() end
                    end)
                end
            end)
        end
    end
    
    if TooltipDataProcessor then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddWowheadHint)
        if Enum.TooltipDataType.Achievement then TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Achievement, AddWowheadHint) end
        if Enum.TooltipDataType.Currency then TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Currency, AddWowheadHint) end
        if Enum.TooltipDataType.Mount then TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Mount, AddWowheadHint) end
        if Enum.TooltipDataType.Quest then TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Quest, AddWowheadHint) end
    end
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

    panel:CreateTitle(builder, WT.L.GROUP_WOWHEAD)
    AddDescription(WT.L.OPT_DESC_WOWHEAD_ENABLE_LINKS)
    
    local enableInit = panel:CreateCheckbox(builder, WT.L.OPT_WOWHEAD_ENABLE_LINKS, WT.L.OPT_DESC_WOWHEAD_ENABLE_LINKS, "Wowhead", "EnableLinks")
    panel:CreateCheckbox(builder, WT.L.OPT_TOOLTIP_WOWHEAD, WT.L.OPT_DESC_TOOLTIP_WOWHEAD, "Wowhead", "ShowTooltipHint", nil, enableInit)
end

WT.Core.Events:Register("PLAYER_LOGIN", function()
    Module:Initialize()
end)