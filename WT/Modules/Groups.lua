local _, WT = ...

WT.Modules.Groups = {}
local Module = WT.Modules.Groups

local Unsecret = WT.Utils.Safety.Unsecret

local GetNumGuildMembers = GetNumGuildMembers or (C_GuildInfo and C_GuildInfo.GetNumGuildMembers) or function() return 0 end
local GetGuildRosterInfo = GetGuildRosterInfo or (C_GuildInfo and C_GuildInfo.GetGuildRosterInfo) or function() return nil end

local function IsValidInviter(name, mode)
    if mode == "ALL" then return true end

    if not name then return false end

    local isFriend = false
    local isGuild = false

    local inviterBase = strsplit("-", name)
    if not inviterBase then inviterBase = name end
    inviterBase = string.lower(inviterBase)
    local nameLower = string.lower(name)

    if mode == "FRIENDS" or mode == "BOTH" then
        for i = 1, C_FriendList.GetNumFriends() do
            local friendInfo = C_FriendList.GetFriendInfoByIndex(i)
            if friendInfo and friendInfo.name then 
                local fName = string.lower(Unsecret(friendInfo.name) or "")
                local fBase = strsplit("-", fName) or fName
                if fName == nameLower or fBase == inviterBase then
                    isFriend = true; break 
                end
            end
        end
        
        if not isFriend then
            local numBNet = (C_BattleNet and C_BattleNet.GetFriendCount and C_BattleNet.GetFriendCount()) or (BNGetNumFriends and BNGetNumFriends()) or 0
            if numBNet > 0 then
                for i = 1, numBNet do
                    local accInfo = C_BattleNet.GetFriendAccountInfo(i)
                    if accInfo and accInfo.gameAccountInfo and accInfo.gameAccountInfo.characterName then
                        local cName = string.lower(Unsecret(accInfo.gameAccountInfo.characterName) or "")
                        local rName = string.lower(Unsecret(accInfo.gameAccountInfo.realmName) or "")
                        
                        if cName ~= "" then
                            local fullBNetName = cName
                            if rName and rName ~= "" then fullBNetName = cName .. "-" .. rName:gsub("%s+", "") end
                            
                            if cName == nameLower or fullBNetName == nameLower or cName == inviterBase then
                                isFriend = true; break
                            end
                        end
                    end
                end
            end
        end
    end

    if mode == "GUILD" or mode == "BOTH" then
        if IsInGuild() then
            for i = 1, GetNumGuildMembers() do
                local rawGuildName = GetGuildRosterInfo(i)
                local guildName = string.lower(Unsecret(rawGuildName) or "")
                if guildName ~= "" then
                    local gBase = strsplit("-", guildName) or guildName
                    if guildName == nameLower or gBase == inviterBase then 
                        isGuild = true; break 
                    end
                end
            end
        end
    end

    if mode == "FRIENDS" and isFriend then return true end
    if mode == "GUILD" and isGuild then return true end
    if mode == "BOTH" and (isFriend or isGuild) then return true end

    return false
end

local function ProcessAutoAccept()
    local accepted = false
    
    -- Modern 12.x UI Click Approach
    local lfgInvitePopup = _G["LFGInvitePopup"]
    if lfgInvitePopup and lfgInvitePopup:IsShown() then
        local btn = lfgInvitePopup.AcceptButton or _G["LFGInvitePopupAcceptButton"]
        if btn and btn:IsEnabled() then pcall(function() btn:Click() end); accepted = true end
    end
    
    if not accepted then
        for i = 1, 4 do
            local popup = _G["StaticPopup"..i]
            if popup and popup:IsShown() and (popup.which == "PARTY_INVITE" or popup.which == "PARTY_INVITE_XREALM") then
                local btn = _G["StaticPopup"..i.."Button1"]
                if btn and btn:IsEnabled() then pcall(function() btn:Click() end); accepted = true end
                break
            end
        end
    end
    
    -- API Fallback for non-standard UI frames
    if not accepted then
        if C_PartyInfo and C_PartyInfo.ConfirmInvite then pcall(C_PartyInfo.ConfirmInvite)
        elseif C_PartyInfo and C_PartyInfo.AcceptInvite then pcall(C_PartyInfo.AcceptInvite)
        else local fn = _G["AcceptGroup"]; if fn then pcall(fn) end end
    end
end

function Module:OnPartyInvite(inviter)
    if not WT.DB or not WT.DB.Groups then return end
    if not WT.DB.Groups.AutoAcceptInvites then return end
    local mode = WT.DB.Groups.AutoAcceptMode or "ALL"
    
    local safeInviter = Unsecret(inviter)
    local ok, valid = pcall(IsValidInviter, safeInviter, mode)
    if ok and valid then
        local delay = math.random(8, 15) / 10.0
        C_Timer.After(delay, ProcessAutoAccept)
    end
end

local function ProcessDeclineDuel()
    local fnCancel = _G["CancelDuel"]
    if fnCancel then pcall(fnCancel) end
    local fnHide = _G["StaticPopup_Hide"]
    if fnHide then pcall(fnHide, "DUEL_REQUESTED") end
end

local function ProcessDeclinePetBattle()
    if C_PetBattles and type(C_PetBattles.DeclinePetBattle) == "function" then pcall(C_PetBattles.DeclinePetBattle) end
    local fnHide = _G["StaticPopup_Hide"]
    if fnHide then pcall(fnHide, "PET_BATTLE_PVP_DUEL_REQUESTED") end
end

function Module:OnDuelRequest(inviter, isPetBattle)
    if not WT.DB or not WT.DB.Groups then return end
    if not WT.DB.Groups.BlockDuels then return end
    local mode = WT.DB.Groups.BlockDuelsMode or "NONE"
    
    local safeInviter = Unsecret(inviter)
    local ok, valid = pcall(IsValidInviter, safeInviter, mode)
    if ok and not valid then
        -- Delay slightly to ensure Blizzard's UI creates the popup before we hide it
        C_Timer.After(0.1, function()
            if not isPetBattle then ProcessDeclineDuel() else ProcessDeclinePetBattle() end
        end)
    end
end

local function ProcessAutoSummon()
    local accepted = false
    for i = 1, 4 do
        local popup = _G["StaticPopup"..i]
        if popup and popup:IsShown() and popup.which == "CONFIRM_SUMMON" then
            local btn = _G["StaticPopup"..i.."Button1"]
            if btn and btn:IsEnabled() then pcall(function() btn:Click() end); accepted = true end
            break
        end
    end
    
    if not accepted and C_SummonInfo and type(C_SummonInfo.ConfirmSummon) == "function" then pcall(C_SummonInfo.ConfirmSummon) end
end

local lastLFGTime = 0
local function ProcessAutoLFG()
    
    local accepted = false
    
    local popups = { "LFGRoleCheckPopup", "LFDRoleCheckPopup", "LFRRoleCheckPopup" }
    for _, popupName in ipairs(popups) do
        local rolePopup = _G[popupName]
        if not accepted and rolePopup and rolePopup:IsShown() then
            local btn = rolePopup.AcceptButton or _G[popupName.."AcceptButton"]
            
            -- Force select the current specialization's role ONLY if accept is disabled
            if btn and not btn:IsEnabled() then
                local okSpec, spec = pcall(GetSpecialization)
                if okSpec and spec then
                    local okInfo, _, _, _, _, role = pcall(GetSpecializationInfo, spec)
                    if okInfo and role then
                        local roleBtn
                        if role == "TANK" then roleBtn = rolePopup.TankButton or _G[popupName.."RoleButtonTank"] or (rolePopup.RoleButtonTank and rolePopup.RoleButtonTank.CheckButton)
                        elseif role == "HEALER" then roleBtn = rolePopup.HealerButton or _G[popupName.."RoleButtonHealer"] or (rolePopup.RoleButtonHealer and rolePopup.RoleButtonHealer.CheckButton)
                        elseif role == "DAMAGER" then roleBtn = rolePopup.DPSButton or _G[popupName.."RoleButtonDPS"] or (rolePopup.RoleButtonDPS and rolePopup.RoleButtonDPS.CheckButton) end
                        
                        if roleBtn and type(roleBtn.Click) == "function" then
                            local isChecked = false
                            if type(roleBtn.GetChecked) == "function" then isChecked = roleBtn:GetChecked() end
                            if not isChecked then
                                pcall(function() roleBtn:Click() end)
                            end
                        end
                    end
                end
            end
            
            if btn and btn:IsEnabled() then
                pcall(function() btn:Click() end)
                accepted = true
            end
        end
    end
    
    -- 2. Role Poll (Custom UI)
    local pollPopup = _G["RolePollPopup"]
    if not accepted and pollPopup and pollPopup:IsShown() then
        local btn = pollPopup.AcceptButton or _G["RolePollPopupAcceptButton"]
        if btn and btn:IsEnabled() then
            pcall(function() btn:Click() end)
            accepted = true
        end
    end
    
    -- 3. Legacy API Fallbacks
    if not accepted then
        local isAnyRoleCheckShown = false
        for _, popupName in ipairs(popups) do
            if _G[popupName] and _G[popupName]:IsShown() then isAnyRoleCheckShown = true; break end
        end
        
        local fnLFG = _G["LFGCompleteRoleCheck"]
        if isAnyRoleCheckShown and fnLFG then pcall(fnLFG, true); accepted = true end
        local fnCRC = _G["CompleteRoleCheck"]
        if isAnyRoleCheckShown and fnCRC then pcall(fnCRC, true); accepted = true end
        local fnVote = _G["UnitVoteRolePoll"]
        if pollPopup and pollPopup.role and fnVote then pcall(fnVote, pollPopup.role); accepted = true end
    end
    
    if accepted then
        local now = GetTime()
        if now - lastLFGTime > 2 then
            lastLFGTime = now
            if WT.Utils and WT.Utils.Logger then WT.Utils.Logger:Print(WT.L.AUTOMATION_ROLE_CHECK) end
        end
    end
end

function Module:Initialize()
    if not WT.DB.Modules.Groups then return end
    
    WT.Core.Events:Register("PARTY_INVITE_REQUEST", function(_, inviter) Module:OnPartyInvite(inviter) end)
    WT.Core.Events:Register("DUEL_REQUESTED", function(_, inviter) Module:OnDuelRequest(inviter, false) end)
    WT.Core.Events:Register("PET_BATTLE_PVP_DUEL_REQUESTED", function(_, inviter) Module:OnDuelRequest(inviter, true) end)
    
    WT.Core.Events:Register("LFG_ROLE_CHECK_SHOW", function()
        if not WT.DB or not WT.DB.Groups then return end
        if WT.DB.Groups.AutoAcceptLFG then
            C_Timer.After(0.8, ProcessAutoLFG)
        end
    end)
    
    WT.Core.Events:Register("LFG_ROLE_CHECK_ROLE_CHOSEN", function()
        if not WT.DB or not WT.DB.Groups then return end
        if WT.DB.Groups.AutoAcceptLFG then
            C_Timer.After(0.8, ProcessAutoLFG)
        end
    end)
    
    WT.Core.Events:Register("LFG_ROLE_CHECK_UPDATE", function()
        if not WT.DB or not WT.DB.Groups then return end
        if WT.DB.Groups.AutoAcceptLFG then
            C_Timer.After(0.8, ProcessAutoLFG)
        end
    end)
    
    WT.Core.Events:Register("ROLE_POLL_BEGIN", function()
        if not WT.DB or not WT.DB.Groups then return end
        if WT.DB.Groups.AutoAcceptLFG then
            C_Timer.After(0.8, ProcessAutoLFG)
        end
    end)
    
    WT.Core.Events:Register("CONFIRM_SUMMON", function()
        if not WT.DB or not WT.DB.Groups then return end
        if WT.DB.Groups.AutoAcceptSummon then
            local delay = math.random(5, 15) / 10.0
            C_Timer.After(delay, ProcessAutoSummon)
        end
    end)
end

WT.Core.Events:Register("PLAYER_LOGIN", function() Module:Initialize() end)

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
    
    panel:CreateTitle(builder, WT.L.GROUP_GROUP_MGMT)
    AddDescription(WT.L.OPT_DESC_GROUP_GROUP_MGMT)
    
    local acceptInit = panel:CreateCheckbox(builder, WT.L.OPT_GROUPS_AUTO_ACCEPT, WT.L.OPT_DESC_GROUPS_AUTO_ACCEPT, "Groups", "AutoAcceptInvites")
    
    local modeOptions = {
        { value = "ALL", label = WT.L.GROUP_ALL },
        { value = "FRIENDS", label = WT.L.GROUP_FRIENDS },
        { value = "GUILD", label = WT.L.GROUP_GUILD },
        { value = "BOTH", label = WT.L.GROUP_BOTH }
    }
    panel:CreateDropdown(builder, WT.L.OPT_GROUPS_MODE, WT.L.OPT_DESC_GROUPS_MODE, "Groups", "AutoAcceptMode", modeOptions, nil, acceptInit)
    
    local lfgInit = panel:CreateCheckbox(builder, WT.L.OPT_GROUPS_AUTO_LFG, WT.L.OPT_DESC_GROUPS_AUTO_LFG, "Groups", "AutoAcceptLFG")
    panel:CreateCheckbox(builder, WT.L.OPT_GROUPS_AUTO_LFG_TOOLTIP, WT.L.OPT_DESC_GROUPS_AUTO_LFG_TOOLTIP, "Groups", "AutoLFGTooltip", nil, lfgInit)
    
    panel:CreateCheckbox(builder, WT.L.OPT_GROUPS_AUTO_SUMMON, WT.L.OPT_DESC_GROUPS_AUTO_SUMMON, "Groups", "AutoAcceptSummon")
    
    panel:CreateTitle(builder, WT.L.GROUP_PVP_INTERACT)
    AddDescription(WT.L.OPT_DESC_GROUP_PVP_INTERACT)
    
    local duelInit = panel:CreateCheckbox(builder, WT.L.OPT_GROUPS_BLOCK_DUELS, WT.L.OPT_DESC_GROUPS_BLOCK_DUELS, "Groups", "BlockDuels")
    
    local duelModeOptions = {
        { value = "NONE", label = WT.L.GROUP_NONE },
        { value = "FRIENDS", label = WT.L.GROUP_FRIENDS },
        { value = "GUILD", label = WT.L.GROUP_GUILD },
        { value = "BOTH", label = WT.L.GROUP_BOTH }
    }
    panel:CreateDropdown(builder, WT.L.OPT_GROUPS_DUEL_MODE, WT.L.OPT_DESC_GROUPS_DUEL_MODE, "Groups", "BlockDuelsMode", duelModeOptions, nil, duelInit)
end