local _, WT = ...

WT.Modules.Questing = {}
local Module = WT.Modules.Questing

local SafeBool = WT.Utils.Safety.SafeBool
local SafeNum = WT.Utils.Safety.SafeNum
local Unsecret = WT.Utils.Safety.Unsecret

-- Function to handle in-engine cutscenes
function Module:OnCinematicStart()
    if not WT.DB or not WT.DB.Questing then return end
    if WT.DB.Questing.AutoSkipCinematics then
        if CinematicFrame_CancelCinematic then
            pcall(CinematicFrame_CancelCinematic)
        else
            pcall(StopCinematic)
        end
        WT.Utils.Logger:Debug(WT.L.AUTOMATION_SKIPPED_CINEMATIC)
    end
end

-- Function to handle pre-rendered movies
function Module:OnPlayMovie()
    if not WT.DB or not WT.DB.Questing then return end
    if WT.DB.Questing.AutoSkipCinematics then
        if _G["GameMovieFinished"] then pcall(_G["GameMovieFinished"]) end
        WT.Utils.Logger:Debug(WT.L.AUTOMATION_SKIPPED_CINEMATIC)
    end
end

-- Function to handle auto-accepting quests
function Module:OnQuestDetail()
    C_Timer.After(0.05, function()
        if not WT.DB or not WT.DB.Questing then return end
        if InCombatLockdown() then return end
        if WT.DB.Questing.AutoAcceptQuests or (WT.DB.Questing.FastQuesting and IsShiftKeyDown()) then
        pcall(AcceptQuest)
            WT.Utils.Logger:Debug(WT.L.AUTOMATION_ACCEPTED_QUEST)
        end
    end)
end

-- Function to handle old-style quest greetings (NPCs with multiple quests but no gossip options)
function Module:OnQuestGreeting()
    C_Timer.After(0.05, function()
        if not WT.DB or not WT.DB.Questing then return end
        if InCombatLockdown() then return end
        
        if WT.DB.Questing.AutoTurnInQuests or (WT.DB.Questing.FastQuesting and IsShiftKeyDown()) then
            local okAct, numActiveRaw = pcall(GetNumActiveQuests)
            local numActive = okAct and SafeNum(numActiveRaw) or 0
            for i = 1, numActive do
                local okT, title, isComplete = pcall(GetActiveTitle, i)
                if okT and SafeBool(isComplete) then
                    pcall(_G["SelectActiveQuest"], i)
                    return
                end
            end
        end
        
        if WT.DB.Questing.AutoAcceptQuests or (WT.DB.Questing.FastQuesting and IsShiftKeyDown()) then
            local okAvail, numAvailRaw = pcall(GetNumAvailableQuests)
            local numAvail = okAvail and SafeNum(numAvailRaw) or 0
            for i = 1, numAvail do
                pcall(_G["SelectAvailableQuest"], i)
                return
            end
        end
    end)
end

-- Function to handle quest progress (continue dialog)
function Module:OnQuestProgress()
    C_Timer.After(0.05, function()
        if not WT.DB or not WT.DB.Questing then return end
        if InCombatLockdown() then return end
        if WT.DB.Questing.AutoTurnInQuests or (WT.DB.Questing.FastQuesting and IsShiftKeyDown()) then
            local ok, isCompletable = pcall(IsQuestCompletable)
            if ok and SafeBool(isCompletable) then
            pcall(CompleteQuest)
            end
        end
    end)
end

-- Function to handle quest completion (picking rewards if safe)
function Module:OnQuestComplete()
    C_Timer.After(0.05, function()
        if not WT.DB or not WT.DB.Questing then return end
        if InCombatLockdown() then return end
        if WT.DB.Questing.AutoTurnInQuests or (WT.DB.Questing.FastQuesting and IsShiftKeyDown()) then
            local ok, choices = pcall(GetNumQuestChoices)
            local numChoices = ok and SafeNum(choices) or 0
            if numChoices <= 1 then
                if numChoices == 1 then pcall(GetQuestReward, 1) else pcall(GetQuestReward, 0) end
                WT.Utils.Logger:Debug(WT.L.AUTOMATION_TURNED_IN_QUEST)
            end
        end
    end)
end

-- Function to smartly select gossip options
function Module:OnGossipShow()
    -- 0.05s Delay: Allows custom quest dialog UIs to build,
    -- preventing race conditions before we click through the dialogs.
    C_Timer.After(0.05, function()
        if not WT.DB or not WT.DB.Questing then return end
        -- Safety protection: No automatic clicking in combat!
        if InCombatLockdown() then return end
        
        local okOpts, rawOpts = pcall(C_GossipInfo.GetOptions)
        local opts = okOpts and rawOpts or nil
        local okAct, rawAct = pcall(C_GossipInfo.GetActiveQuests)
        local active = okAct and rawAct or nil
        local okAv, rawAv = pcall(C_GossipInfo.GetAvailableQuests)
        local available = okAv and rawAv or nil
        
        local firstOptIsSafe = false
        if opts and opts[1] then
            local icon = SafeNum(opts[1].icon)
            
            local isBadIcon = (icon == 1 or icon == 2 or icon == 3 or icon == 4 or icon == 5 or icon == 6 or icon == 7 or icon == 8 or icon == 9 or icon == 10 or icon == 33)
            
            if Enum.GossipOptionIcon then
                if icon == Enum.GossipOptionIcon.Vendor or icon == Enum.GossipOptionIcon.Taxi or icon == Enum.GossipOptionIcon.Trainer or icon == Enum.GossipOptionIcon.Binder or icon == Enum.GossipOptionIcon.Banker then
                    isBadIcon = true
                end
            end
            
            if not isBadIcon then
                firstOptIsSafe = true
            end
            
            if not firstOptIsSafe and opts[1].name then
                local optName = Unsecret(opts[1].name)
                if optName then
                    optName = string.lower(optName)
                    if string.find(optName, "quest", 1, true) or string.find(optName, "kampagne", 1, true) or string.find(optName, "campaign", 1, true) or string.find(optName, "story", 1, true) then
                        firstOptIsSafe = true
                    end
                end
            end
        end
        
        if WT.DB.Questing.AutoTurnInQuests and not IsShiftKeyDown() then
            if active then
                for _, q in ipairs(active) do
                    if SafeBool(q.isComplete) then pcall(C_GossipInfo.SelectActiveQuest, SafeNum(q.questID)); return end
                end
            end
        end
        
        if WT.DB.Questing.AutoAcceptQuests and not IsShiftKeyDown() then
            if available then
                for _, q in ipairs(available) do
                    pcall(C_GossipInfo.SelectAvailableQuest, SafeNum(q.questID)); return
                end
            end
        end

        if WT.DB.Questing.SmartGossip and not IsShiftKeyDown() then
            -- Safety check: We ONLY want to auto-click pure story dialogs ("gossip")!
            -- Prevents us from accidentally binding hearthstones ("binder") or starting flight masters ("taxi").
            if opts and #opts == 1 and (not active or #active == 0) and (not available or #available == 0) then
                if firstOptIsSafe then
                    pcall(C_GossipInfo.SelectOption, SafeNum(opts[1].gossipOptionID))
                    return
                end
            end
        end
        
        if WT.DB.Questing.FastQuesting and IsShiftKeyDown() then
            if active then for _, q in ipairs(active) do if SafeBool(q.isComplete) then pcall(C_GossipInfo.SelectActiveQuest, SafeNum(q.questID)) return end end end
            
            if available then for _, q in ipairs(available) do pcall(C_GossipInfo.SelectAvailableQuest, SafeNum(q.questID)) return end end
            
            if opts and opts[1] then
                pcall(C_GossipInfo.SelectOption, SafeNum(opts[1].gossipOptionID))
            end
        end
    end)
end

function Module:RefreshGossipFrames()
    if GossipFrame and GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.ScrollBox then
        pcall(function() GossipFrame.GreetingPanel.ScrollBox:Update() end)
    elseif GossipFrame and GossipFrame.ScrollBox then
        pcall(function() GossipFrame.ScrollBox:Update() end)
    end
    if _G["QuestFrameGreetingPanel"] and _G["QuestFrameGreetingPanel"]:IsShown() and _G["QuestFrame_UpdateGreetingPanel"] then
        pcall(_G["QuestFrame_UpdateGreetingPanel"])
    end
end

function Module:UpdateQuestFonts()
    if not WT.DB or not WT.DB.Questing then return end
    if not WT.DB.Questing.CustomQuestFont then return end
    
    local fontKey = WT.DB.Questing.QuestFont or "Friz Quadrata TT"
    local fontPath = (WT.Utils and WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", fontKey)) or "Fonts\\FRIZQT__.TTF"
    local outline = "" -- Hardcoded empty outline to prevent unreadable black blobs on dark quest text
    local size = WT.DB.Questing.QuestFontSize or 13
    
    local fontsToUpdate = {
        { obj = _G["QuestFont"], size = size, justify = "LEFT" },
        { obj = _G["QuestFontNormalSmall"], size = size - 2, justify = "LEFT" },
        { obj = _G["QuestFontHighlight"], size = size, justify = "LEFT" },
        { obj = _G["QuestTitleFont"], size = size + 5, justify = "LEFT" },
        { obj = _G["QuestTitleFontBlackShadow"], size = size + 5, justify = "LEFT", shadow = true },
        { obj = _G["QuestFont_Shadow_Huge"], size = size + 15, justify = "CENTER", shadow = true },
        { obj = _G["QuestFont_Enormous"], size = size + 17, justify = "CENTER", shadow = true },
        { obj = _G["QuestFont_Super_Huge"], size = size + 11, justify = "CENTER", shadow = true },
        { obj = _G["QuestFont_Shadow_Small"], size = size - 3, justify = "LEFT", shadow = true },
    }
    
    for _, fData in ipairs(fontsToUpdate) do
        if fData.obj and type(fData.obj.SetFont) == "function" then
            fData.obj:SetFont(fontPath, fData.size, outline)
            
            if fData.justify and type(fData.obj.SetJustifyH) == "function" then
                fData.obj:SetJustifyH(fData.justify)
            end
            
            if type(fData.obj.SetShadowColor) == "function" then
                if fData.shadow then
                    fData.obj:SetShadowColor(0, 0, 0, 0.8)
                    if type(fData.obj.SetShadowOffset) == "function" then fData.obj:SetShadowOffset(1, -1) end
                else
                    fData.obj:SetShadowColor(0, 0, 0, 0)
                end
            end
        end
    end
end

local function SetupQuestAutomations()
    local function ScanGossipFrames()
        if not WT.DB or not WT.DB.Questing then return end
        if not WT.DB.Questing.GossipQuestColor then return end
        local hex = WT.Colors:GetHex(WT.DB.Questing.GossipQuestColV, 1, 0.82, 0)
        
        local function FormatText(textObj)
            if textObj and textObj.GetText then
                local text = Unsecret(textObj:GetText())
                if text and string.find(text, "(", 1, true) and not string.find(text, "|c" .. hex, 1, true) then
                    local newText = string.gsub(text, "%(([^%)]+)%)", function(inner)
                        return "|c" .. hex .. "[" .. string.upper(inner) .. "]|r"
                    end)
                    if newText ~= text then textObj:SetText(newText) end
                end
            end
        end

        local scrollBox = GossipFrame and GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.ScrollBox
        if scrollBox and scrollBox.ForEachFrame then
            pcall(function() scrollBox:ForEachFrame(function(btn) FormatText(btn.Text or btn.Title or (btn.GetFontString and btn:GetFontString())) end) end)
        end
        if GossipFrame and GossipFrame.ScrollBox and GossipFrame.ScrollBox.ForEachFrame then
            pcall(function() GossipFrame.ScrollBox:ForEachFrame(function(btn) FormatText(btn.Text or btn.Title or (btn.GetFontString and btn:GetFontString())) end) end)
        end
        for i = 1, 32 do
            local btn = _G["QuestTitleButton"..i]
            if btn and btn:IsVisible() then FormatText(btn.Text or (btn.GetFontString and btn:GetFontString()) or btn) end
        end
    end

    local scrollBox = GossipFrame and GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.ScrollBox
    if scrollBox and type(scrollBox.RegisterCallback) == "function" then
        pcall(function() scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, ScanGossipFrames, Module) end)
    elseif GossipFrame and GossipFrame.ScrollBox and type(GossipFrame.ScrollBox.RegisterCallback) == "function" then
        pcall(function() GossipFrame.ScrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, ScanGossipFrames, Module) end)
    end

    if _G["QuestFrameGreetingPanel"] then _G["QuestFrameGreetingPanel"]:HookScript("OnShow", ScanGossipFrames) end
    if _G["QuestFrame_UpdateGreetingPanel"] then hooksecurefunc("QuestFrame_UpdateGreetingPanel", ScanGossipFrames) end

    local gossipWatcher = CreateFrame("Frame")
    gossipWatcher:RegisterEvent("GOSSIP_SHOW")
    gossipWatcher:RegisterEvent("QUEST_GREETING")
    gossipWatcher:SetScript("OnEvent", function() C_Timer.After(0.05, ScanGossipFrames); C_Timer.After(0.2, ScanGossipFrames) end)

    WT.Core.Events:Register("CINEMATIC_START", function() Module:OnCinematicStart() end)
    WT.Core.Events:Register("PLAY_MOVIE", function() Module:OnPlayMovie() end)
    WT.Core.Events:Register("GOSSIP_SHOW", function() Module:OnGossipShow() end)
    WT.Core.Events:Register("QUEST_GREETING", function() Module:OnQuestGreeting() end)
    WT.Core.Events:Register("QUEST_DETAIL", function() Module:OnQuestDetail() end)
    WT.Core.Events:Register("QUEST_ACCEPT_CONFIRM", function() if not InCombatLockdown() and WT.DB.Questing.FastQuesting and IsShiftKeyDown() then pcall(ConfirmAcceptQuest) end end)
    WT.Core.Events:Register("QUEST_PROGRESS", function() Module:OnQuestProgress() end)
    WT.Core.Events:Register("QUEST_COMPLETE", function() Module:OnQuestComplete() end)
end

function Module:Initialize()
    if not WT.DB.Modules.Automations then return end
    SetupQuestAutomations()
    Module:UpdateQuestFonts()
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
    
    panel:CreateTitle(builder, WT.L.GROUP_QUESTS)
    AddDescription(WT.L.OPT_DESC_GROUP_QUESTS)
    
    panel:CreateCheckbox(builder, WT.L.OPT_AUTO_SKIP_CINEMATICS, WT.L.OPT_DESC_AUTO_SKIP_CINEMATICS, "Questing", "AutoSkipCinematics")
    panel:CreateCheckbox(builder, WT.L.OPT_AUTO_SMART_GOSSIP, WT.L.OPT_DESC_AUTO_SMART_GOSSIP, "Questing", "SmartGossip")
    local gossipColInit = panel:CreateCheckbox(builder, WT.L.OPT_AUTO_GOSSIP_COLOR, WT.L.OPT_DESC_AUTO_GOSSIP_COLOR, "Questing", "GossipQuestColor", function() if WT.Modules.Questing and WT.Modules.Questing.RefreshGossipFrames then WT.Modules.Questing:RefreshGossipFrames() end end)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "Questing", "GossipQuestColV", false, gossipColInit, function() if WT.Modules.Questing and WT.Modules.Questing.RefreshGossipFrames then WT.Modules.Questing:RefreshGossipFrames() end end)
    panel:CreateCheckbox(builder, WT.L.OPT_AUTO_FAST_QUEST, WT.L.OPT_DESC_AUTO_FAST_QUEST, "Questing", "FastQuesting")
    panel:CreateCheckbox(builder, WT.L.OPT_AUTO_ACCEPT_QUESTS, WT.L.OPT_DESC_AUTO_ACCEPT_QUESTS, "Questing", "AutoAcceptQuests")
    panel:CreateCheckbox(builder, WT.L.OPT_AUTO_TURN_IN_QUESTS, WT.L.OPT_DESC_AUTO_TURN_IN_QUESTS, "Questing", "AutoTurnInQuests")
    
    local function PromptReload() if WT.Config and WT.Config.OptionsPanel and WT.Config.OptionsPanel.ShowReloadPrompt then WT.Config.OptionsPanel:ShowReloadPrompt() end end
    local qFontInit = panel:CreateCheckbox(builder, WT.L.OPT_QUEST_CUSTOM_FONT, WT.L.OPT_DESC_QUEST_CUSTOM_FONT, "Questing", "CustomQuestFont", function(val) if val then if WT.Modules.Questing and WT.Modules.Questing.UpdateQuestFonts then WT.Modules.Questing:UpdateQuestFonts() end else PromptReload() end end)
    if WT.Utils and WT.Utils.SharedMedia then
        panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "Questing", "QuestFont", WT.Utils.SharedMedia:GetOptions("font"), function() if WT.Modules.Questing and WT.Modules.Questing.UpdateQuestFonts then WT.Modules.Questing:UpdateQuestFonts() end end, qFontInit)
    end
    panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "Questing", "QuestFontSize", 8, 24, 1, function() if WT.Modules.Questing and WT.Modules.Questing.UpdateQuestFonts then WT.Modules.Questing:UpdateQuestFonts() end end, qFontInit)
end