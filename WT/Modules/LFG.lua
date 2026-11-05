local _, WT = ...

WT.Modules.LFG = {}
local Module = WT.Modules.LFG

-- Feature Compatibility: The modern Group Finder API is not available on WoW Forever.
-- Halt module initialization to prevent missing API exceptions.
if not C_LFGList then return end

local lfgFlagCache = {}

local Unsecret = WT.Utils.Safety.Unsecret

-- Appends the target icon/flag natively into the font strings without replacing existing text
local function UpdateLFGNameString(fontString, actualRealm, factionGroup)
    if not fontString or type(fontString.GetText) ~= "function" then return end
    actualRealm = actualRealm or ""

    local currentText = fontString:GetText()
    currentText = Unsecret(currentText)
    if not currentText then return end

    local isModified = false
    local newText = currentText

    local facIcon = ""
    if WT.DB.LFG.FactionIcons and factionGroup then
        if factionGroup == 0 then
            facIcon = "|TInterface\\FriendsFrame\\PlusManz-Horde:14:14:0:-1|t "
        elseif factionGroup == 1 then
            facIcon = "|TInterface\\FriendsFrame\\PlusManz-Alliance:14:14:0:-1|t "
        end
    end

    local flagStr = ""
    if WT.DB.LFG.RealmFlags and WT.Utils and WT.Utils.Realms then
        flagStr = lfgFlagCache[actualRealm]
        if not flagStr then
            flagStr = WT.Utils.Realms:GetFlagString(actualRealm, false)
            lfgFlagCache[actualRealm] = flagStr
        end
    end

    if facIcon ~= "" and not string.find(newText, "PlusManz") then
        newText = facIcon .. newText
        isModified = true
    end

    if flagStr ~= "" and not string.find(newText, flagStr, 1, true) then
        newText = flagStr .. " " .. newText
        isModified = true
    end

    if isModified then
        fontString:SetText(newText)
    end
end

local function OnAppViewerMemberEnter(selfBtn)
    local currentAppID = selfBtn.applicantID or (selfBtn:GetParent() and selfBtn:GetParent().applicantID)
    local currentIdx = selfBtn.memberIdx or 1
    if not currentAppID then return end

    local mName = Unsecret(C_LFGList.GetApplicantMemberInfo(currentAppID, currentIdx))
    if mName then
        local cAppInfo = C_LFGList.GetApplicantInfo(currentAppID)
        local cFacGroup = cAppInfo and cAppInfo["factionGroup"]

        if WT.DB.LFG.FactionIcons and cFacGroup then
            local titleLine = _G["GameTooltipTextLeft1"]
            if titleLine then
                local currentTitle = titleLine:GetText() or ""
                if not string.find(currentTitle, "PlusManz") then
                    local facIcon = ""
                    if cFacGroup == 0 then
                        facIcon = "|TInterface\\FriendsFrame\\PlusManz-Horde:14:14:0:-1|t "
                    elseif cFacGroup == 1 then
                        facIcon = "|TInterface\\FriendsFrame\\PlusManz-Alliance:14:14:0:-1|t "
                    end
                    if facIcon ~= "" then titleLine:SetText(facIcon .. currentTitle) end
                end
            end
        end

        if WT.DB.LFG.RealmFlags and WT.Utils and WT.Utils.Realms then
            local _, mRealm = strsplit("-", mName)
            local displayRealm = (mRealm and mRealm ~= "") and mRealm or GetRealmName()
            local flagWithText = WT.Utils.Realms:GetFlagString(displayRealm, true)
            if flagWithText ~= "" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine((WT.L.TT_REGION) .. ":", flagWithText, 1, 0.82, 0, 1, 1, 1)
                GameTooltip:Show()
            end
        end
    end
end

local function ProcessSearchBtn(btn)
    local fontString = btn.Name or btn.name or btn.ActivityName
    if btn.resultID and fontString then
        local result = C_LFGList.GetSearchResultInfo(btn.resultID)
        local leaderName = result and Unsecret(result.leaderName) or nil
        if leaderName then
            local extractedRealm = string.match(leaderName, "%-(.+)")
            local displayRealm = (extractedRealm and extractedRealm ~= "") and extractedRealm or GetRealmName()
            UpdateLFGNameString(fontString, displayRealm, nil)
        end
    end
end

local function ProcessAppBtn(btn)
    local appID = btn.applicantID
    if appID then
        local appInfo = C_LFGList.GetApplicantInfo(appID)
        local validFacGroup = appInfo and appInfo["factionGroup"] or nil

        for i = 1, 5 do
            local memberBtn = btn["Member" .. i]
            if memberBtn and memberBtn:IsShown() then
                local fontString = memberBtn.Name or memberBtn.name or memberBtn.ActivityName
                local memberIdx = memberBtn.memberIdx or i

                if fontString then
                    local name = Unsecret(C_LFGList.GetApplicantMemberInfo(appID, memberIdx))
                    if name then
                        local extractedRealm = string.match(name, "%-(.+)")
                        local displayRealm = (extractedRealm and extractedRealm ~= "") and extractedRealm or
                        GetRealmName()
                        UpdateLFGNameString(fontString, displayRealm, validFacGroup)
                    end

                    if not memberBtn.WTHookedOnEnter then
                        memberBtn.WTHookedOnEnter = true
                        memberBtn:HookScript("OnEnter", OnAppViewerMemberEnter)
                    end
                end
            end
        end
    end
end

local function DoLFGPoll()
    -- 1. Search Tooltip Hook (Leader hover)
    if not Module.LFG_SearchTooltipHooked and _G["LFGListUtil_SetSearchEntryTooltip"] then
        Module.LFG_SearchTooltipHooked = true
        hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", function(tooltip, searchResultID)
            if WT.Modules.Tooltip and type(WT.Modules.Tooltip.ColorizeLFGTooltipClasses) == "function" then
                WT.Modules.Tooltip:ColorizeLFGTooltipClasses(tooltip)
            end
            if not WT.DB.LFG.RealmFlags then return end
            local result = C_LFGList.GetSearchResultInfo(searchResultID)
            local leaderName = result and Unsecret(result.leaderName)
            if leaderName then
                if WT.Utils and WT.Utils.Realms then
                    local extractedRealm = string.match(leaderName, "%-(.+)")
                    local displayRealm = (extractedRealm and extractedRealm ~= "") and extractedRealm or GetRealmName()
                    local flagWithText = WT.Utils.Realms:GetFlagString(displayRealm, true)
                    if flagWithText ~= "" then
                        tooltip:AddLine(" ")
                        tooltip:AddLine((WT.L.TT_REGION) .. ": |cffffffff" .. flagWithText .. "|r", 1, 0.82,
                            0)
                        tooltip:Show()
                    end
                end
            end
        end)
    end

    -- 1.5 Applicant Tooltip Hook
    if not Module.LFG_AppTooltipHooked and _G["LFGListUtil_SetApplicantMemberTooltip"] then
        Module.LFG_AppTooltipHooked = true
        hooksecurefunc("LFGListUtil_SetApplicantMemberTooltip", function(tooltip, applicantID, memberIdx)
            if WT.Modules.Tooltip and type(WT.Modules.Tooltip.ColorizeLFGTooltipClasses) == "function" then
                WT.Modules.Tooltip:ColorizeLFGTooltipClasses(tooltip)
            end
        end)
    end

    -- 2. Search Panel List Poller
    if LFGListFrame and LFGListFrame.SearchPanel and LFGListFrame.SearchPanel.ScrollBox and LFGListFrame.SearchPanel.ScrollBox.ForEachFrame then
        LFGListFrame.SearchPanel.ScrollBox:ForEachFrame(ProcessSearchBtn)
    end

    -- 3. Application Viewer List Poller
    if LFGListFrame and LFGListFrame.ApplicationViewer and LFGListFrame.ApplicationViewer.ScrollBox and LFGListFrame.ApplicationViewer.ScrollBox.ForEachFrame then
        LFGListFrame.ApplicationViewer.ScrollBox:ForEachFrame(ProcessAppBtn)
    end
end

local function LFGPollWrapper()
    -- Performance check: Only run when LFG List is visible to the player
    if not (LFGListFrame and LFGListFrame:IsVisible()) then
        return
    end

    -- Isolated execution to prevent engine crashing during WoW API hiccups
    pcall(DoLFGPoll)
end

local knownApplicants = {}

local function OnApplicantListUpdated()
    if not WT.DB.Modules.Groups or not WT.DB.LFG.AudioAlert or not WT.DB.LFG.AudioAlertSound or WT.DB.LFG.AudioAlertSound == "None" then return end

    local activeEntry = C_LFGList.GetActiveEntryInfo()
    if not activeEntry then
        wipe(knownApplicants)
        return
    end

    local applicants = C_LFGList.GetApplicants()
    if not applicants then return end

    local hasNew = false
    local currentApplicants = {}

    for _, appID in ipairs(applicants) do
        pcall(function()
            currentApplicants[appID] = true
            if not knownApplicants[appID] then
                local info = C_LFGList.GetApplicantInfo(appID)
                -- Only alert if the status is freshly applied (not invited/declined)
                if info and info.applicationStatus == "applied" then
                    hasNew = true
                end
                knownApplicants[appID] = true
            end
        end)
    end

    -- Cleanup removed applicants to prevent memory leaks over long sessions
    for appID in pairs(knownApplicants) do
        if not currentApplicants[appID] then
            knownApplicants[appID] = nil
        end
    end

    if hasNew and WT.Utils and WT.Utils.Audio then
        WT.Utils.Audio:Play(WT.DB.LFG.AudioAlertSound, nil, WT.DB.LFG.AudioAlertSoundChannel)
    end
end

function Module:Initialize()
    if not WT.DB.Modules.Groups then
        WT.Core.Events:UnregisterOnUpdate(LFGPollWrapper)
        return
    end

    WT.Core.Events:Register("LFG_LIST_APPLICANT_LIST_UPDATED", OnApplicantListUpdated, "LFG")
    WT.Core.Events:Register("LFG_LIST_ACTIVE_ENTRY_UPDATE", function()
        if not C_LFGList.GetActiveEntryInfo() then wipe(knownApplicants) end
    end, "LFG")

    WT.Core.Events:RegisterOnUpdate(LFGPollWrapper, 0.3, "LFG")
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

    panel:CreateTitle(builder, WT.L.GROUP_LFG_DISPLAY)
    AddDescription(WT.L.OPT_DESC_GROUP_LFG_DISPLAY)

    panel:CreateCheckbox(builder, WT.L.OPT_LFG_FACTION_ICONS, WT.L.OPT_DESC_LFG_FACTION_ICONS, "LFG", "FactionIcons")
    panel:CreateCheckbox(builder, WT.L.OPT_LFG_REALM_FLAGS, WT.L.OPT_DESC_LFG_REALM_FLAGS, "LFG", "RealmFlags")

    local aaInit = panel:CreateCheckbox(builder, WT.L.OPT_LFG_AUDIO_ALERT, WT.L.OPT_DESC_LFG_AUDIO_ALERT, "LFG",
        "AudioAlert")
    if WT.Utils and WT.Utils.SharedMedia then
        panel:CreateSoundDropdown(builder, WT.L.OPT_LFG_AUDIO_ALERT_SOUND, WT.L.OPT_DESC_LFG_AUDIO_ALERT_SOUND, "LFG",
            "AudioAlertSound", aaInit)
    end
end
