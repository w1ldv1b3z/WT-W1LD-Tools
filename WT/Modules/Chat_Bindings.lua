local _, WT = ...

local wipe = table.wipe or wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local safeCall = securecallfunction or securecall

WT.Modules.Keybindings = {}
local Module = WT.Modules.Keybindings

-- ==========================================
-- NORMAL HARDWARE BUTTONS (TAINT-FREE CHAT)
-- ==========================================
local function CreateChatBtn(name, prefix)
    local btn = CreateFrame("Button", name, _G["WT_UIContainer"])
    btn.ignoreInLayout = true
    btn.ignoreFramePositionManager = true
    if btn.SetIsFramePositionManaged then pcall(function() btn:SetIsFramePositionManaged(false) end) end
    btn:SetSize(1, 1)
    btn:SetPoint("TOPLEFT", _G["WT_UIContainer"], "TOPLEFT", 0, 0)
    btn:SetAlpha(0)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetScript("OnClick", function()
        ChatFrame_OpenChat(prefix)
    end)
    return btn
end

local btns = {}
btns[#btns+1] = CreateChatBtn("WT_ChatBtn_General", "/1 ")
btns[#btns+1] = CreateChatBtn("WT_ChatBtn_Trade", "/2 ")
btns[#btns+1] = CreateChatBtn("WT_ChatBtn_LocalDefense", "/3 ")
btns[#btns+1] = CreateChatBtn("WT_ChatBtn_Services", "/4 ")

btns[#btns+1] = CreateChatBtn("WT_ChatBtn_Say", "/s ")
btns[#btns+1] = CreateChatBtn("WT_ChatBtn_Yell", "/y ")
btns[#btns+1] = CreateChatBtn("WT_ChatBtn_Whisper", "/w ")
btns[#btns+1] = CreateChatBtn("WT_ChatBtn_Emote", "/e ")

btns[#btns+1] = CreateChatBtn("WT_ChatBtn_Guild", "/g ")
btns[#btns+1] = CreateChatBtn("WT_ChatBtn_Party", "/p ")
btns[#btns+1] = CreateChatBtn("WT_ChatBtn_Raid", "/ra ")
btns[#btns+1] = CreateChatBtn("WT_ChatBtn_Instance", "/i ")
btns[#btns+1] = CreateChatBtn("WT_ChatBtn_Officer", "/o ")
btns[#btns+1] = CreateChatBtn("WT_ChatBtn_RaidWarning", "/rw ")

local btnSmart = CreateFrame("Button", "WT_ChatBtn_SmartGroup", _G["WT_UIContainer"])
btnSmart.ignoreInLayout = true
btnSmart.ignoreFramePositionManager = true
if btnSmart.SetIsFramePositionManaged then pcall(function() btnSmart:SetIsFramePositionManaged(false) end) end
btnSmart:SetSize(1, 1)
btnSmart:SetPoint("TOPLEFT", _G["WT_UIContainer"], "TOPLEFT", 0, 0)
btnSmart:SetAlpha(0)
btnSmart:RegisterForClicks("AnyUp", "AnyDown")
btnSmart:SetScript("OnClick", function()
    local t = "/s "
    if IsInGroup(2) then t = "/i "
    elseif IsInRaid() then t = "/ra "
    elseif IsInGroup() then t = "/p "
    end
    ChatFrame_OpenChat(t)
end)
btns[#btns+1] = btnSmart

for i = 1, 3 do
    local btnCustom = CreateFrame("Button", "WT_ChatBtn_Custom"..i, _G["WT_UIContainer"])
    btnCustom.ignoreInLayout = true
    btnCustom.ignoreFramePositionManager = true
    if btnCustom.SetIsFramePositionManaged then pcall(function() btnCustom:SetIsFramePositionManaged(false) end) end
    btnCustom:SetSize(1, 1)
    btnCustom:SetPoint("TOPLEFT", _G["WT_UIContainer"], "TOPLEFT", 0, 0)
    btnCustom:SetAlpha(0)
    btnCustom:RegisterForClicks("AnyUp", "AnyDown")
    btnCustom:SetScript("OnClick", function()
        local n = WT.DB.ChatChannels["CustomChan"..i.."Name"]
        if n and n ~= "" then
            local c = tonumber(n) or GetChannelName(n)
            ChatFrame_OpenChat("/"..((c and c > 0) and c or n).." ")
        end
    end)
    btns[#btns+1] = btnCustom
end

-- Hook into module toggle to enable/disable buttons so we don't need to read WT.DB inside OnClick
if WT.Core and WT.Core.Events then
    WT.Core.Events:Register("CONFIG_UPDATED", function()
        local isEnabled = WT.DB.Modules.Keybindings
        for _, btn in ipairs(btns) do
            if isEnabled then btn:Enable() else btn:Disable() end
        end
    end)
end

-- Clear history button (Taint-free as it doesn't open the chat frame)
WT_ChatHotkey_Clear = function()
    if WT.DB.Internal.ChatLog then wipe(WT.DB.Internal.ChatLog) end
    if WT.DB.Internal.InputLog then wipe(WT.DB.Internal.InputLog) end
    if WT.Utils and WT.Utils.Logger then WT.Utils.Logger:Print(WT.L.MSG_HISTORY_CLEARED) end
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
    
    panel:CreateTitle(builder, WT.L.OPT_KEYBIND)
    AddDescription(WT.L.OPT_DESC_KEYBINDINGS)
    
    panel:CreateSubTitle(builder, WT.L.GROUP_CHAT_FUNCTIONALITY)
    panel:CreateKeybindButton(builder, WT.L.BINDING_SMARTGROUP, WT.L.OPT_DESC_CHAT_SMARTGROUP, "CLICK WT_ChatBtn_SmartGroup:LeftButton")
    panel:CreateKeybindButton(builder, WT.L.BINDING_GENERAL, "", "CLICK WT_ChatBtn_General:LeftButton")
    panel:CreateKeybindButton(builder, WT.L.BINDING_TRADE, "", "CLICK WT_ChatBtn_Trade:LeftButton")
    panel:CreateKeybindButton(builder, WT.L.BINDING_LOCALDEFENSE, "", "CLICK WT_ChatBtn_LocalDefense:LeftButton")
    panel:CreateKeybindButton(builder, WT.L.BINDING_SERVICES, "", "CLICK WT_ChatBtn_Services:LeftButton")
    panel:CreateKeybindButton(builder, WT.L.BINDING_CLEAR_CHAT, "", "WT_CHAT_CLEAR")
    
    panel:CreateSubTitle(builder, WT.L.GROUP_CHAT_CHANNELS)
    panel:CreateKeybindButton(builder, WT.L.BINDING_SAY, "", "CLICK WT_ChatBtn_Say:LeftButton")
    panel:CreateKeybindButton(builder, WT.L.BINDING_YELL, "", "CLICK WT_ChatBtn_Yell:LeftButton")
    panel:CreateKeybindButton(builder, WT.L.BINDING_WHISPER, "", "CLICK WT_ChatBtn_Whisper:LeftButton")
    panel:CreateKeybindButton(builder, WT.L.BINDING_BNET_WHISPER, "", "REPLY2")
    panel:CreateKeybindButton(builder, WT.L.BINDING_EMOTE, "", "CLICK WT_ChatBtn_Emote:LeftButton")
    
    panel:CreateSubTitle(builder, WT.L.CATEGORY_GROUPS)
    panel:CreateKeybindButton(builder, WT.L.BINDING_GUILD, "", "CLICK WT_ChatBtn_Guild:LeftButton")
    panel:CreateKeybindButton(builder, WT.L.BINDING_PARTY, "", "CLICK WT_ChatBtn_Party:LeftButton")
    panel:CreateKeybindButton(builder, WT.L.BINDING_RAID, "", "CLICK WT_ChatBtn_Raid:LeftButton")
    panel:CreateKeybindButton(builder, WT.L.BINDING_INSTANCE, "", "CLICK WT_ChatBtn_Instance:LeftButton")
    panel:CreateKeybindButton(builder, WT.L.BINDING_OFFICER, "", "CLICK WT_ChatBtn_Officer:LeftButton")
    panel:CreateKeybindButton(builder, WT.L.BINDING_RAID_WARNING, "", "CLICK WT_ChatBtn_RaidWarning:LeftButton")
    
    panel:CreateSubTitle(builder, WT.L.GROUP_CHAT_CUSTOM_CHANNELS)
    panel:CreateKeybindButton(builder, "Custom Channel 1", "", "CLICK WT_ChatBtn_Custom1:LeftButton")
    panel:CreateKeybindButton(builder, "Custom Channel 2", "", "CLICK WT_ChatBtn_Custom2:LeftButton")
    panel:CreateKeybindButton(builder, "Custom Channel 3", "", "CLICK WT_ChatBtn_Custom3:LeftButton")
end