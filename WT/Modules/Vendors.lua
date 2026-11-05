local _, WT = ...

WT.Modules.Vendor = {}
local Module = WT.Modules.Vendor

local SafeBool = WT.Utils.Safety.SafeBool
local SafeNum = WT.Utils.Safety.SafeNum
local Unsecret = WT.Utils.Safety.Unsecret

-- Function to handle automations when visiting a merchant
function Module:OnMerchantShow()
    if not WT.DB or not WT.DB.Vendor then return end
    
    -- 1. Auto Repair
    if WT.DB.Vendor.AutoRepair and not Module.isRepairing then
        Module.isRepairing = true
        local repairIterations = 0
        
        local function ProcessRepairQueue()
            if not MerchantFrame or not MerchantFrame:IsShown() or not CanMerchantRepair() then 
                Module.isRepairing = false
                return 
            end
            
            repairIterations = repairIterations + 1
            if repairIterations > 20 then 
                Module.isRepairing = false
                return 
            end -- Failsafe to prevent infinite loops
            
            -- Smart check: Are there even any damaged items left?
            local damagedItems = 0
            local fnGetInvDura = _G["GetInventoryItemDurability"]
            local fnGetBagDura = C_Container and C_Container.GetContainerItemDurability or _G["GetContainerItemDurability"]
            
            for slot = 1, 19 do
                local v, max = fnGetInvDura(slot)
                if v and max and v < max then damagedItems = damagedItems + 1 end
            end
            for bag = 0, 5 do
                for slot = 1, C_Container.GetContainerNumSlots(bag) do
                    if fnGetBagDura then
                        local v, max = fnGetBagDura(bag, slot)
                        if v and max and v < max then damagedItems = damagedItems + 1 end
                    end
                end
            end
            
            if damagedItems == 0 then
                -- Everything is fully repaired
                Module.isRepairing = false
                return
            end
            
            local repairCost, canRepair = GetRepairAllCost()
                
            if canRepair and repairCost > 0 then
                -- Server lag compensation: If the cost is exactly the same as our last repair, 
                -- we assume it's a duplicate check from the 0.5s timer before the server updated.
                if repairCost == Module.lastRepairCost then
                    C_Timer.After(0.5, ProcessRepairQueue)
                    return
                end
                Module.lastRepairCost = repairCost
                
                local itemString = damagedItems > 0 and (" (" .. damagedItems .. "x)") or ""
                local repaired = false

                -- Try guild bank repair first
                if WT.DB.Vendor.AutoRepairGuildBank and IsInGuild() and CanGuildBankRepair() then
                    local withdrawLimit = GetGuildBankWithdrawMoney()
                    local guildBankMoney = GetGuildBankMoney()
                    
                    local availableFunds = guildBankMoney
                    if withdrawLimit ~= -1 then availableFunds = math.min(withdrawLimit, guildBankMoney) end
                    
                    if availableFunds >= repairCost then
                        RepairAllItems(true)
                        repaired = true
                        local moneyString = C_CurrencyInfo.GetCoinTextureString(repairCost)
                        if WT.Utils and WT.Utils.Logger then WT.Utils.Logger:Print((WT.L.AUTOMATION_REPAIRED_GUILD) .. " " .. moneyString .. itemString) end
                        if WT.Utils and WT.Utils.Audio then WT.Utils.Audio:Play(WT.DB.Vendor.AutoRepairSound, nil, WT.DB.Vendor.AutoRepairSoundChannel) end
                    end
                end

                -- Fallback to personal funds
                if not repaired then
                    if GetMoney() >= repairCost then
                        RepairAllItems()
                        repaired = true
                        local moneyString = C_CurrencyInfo.GetCoinTextureString(repairCost)
                        if WT.Utils and WT.Utils.Logger then WT.Utils.Logger:Print((WT.L.AUTOMATION_REPAIRED) .. " " .. moneyString .. itemString) end
                        if WT.Utils and WT.Utils.Audio then WT.Utils.Audio:Play(WT.DB.Vendor.AutoRepairSound, nil, WT.DB.Vendor.AutoRepairSoundChannel) end
                    else
                        local msg = WT.L.AUTOMATION_REPAIR_FAILED
                        if WT.Utils and WT.Utils.Logger then WT.Utils.Logger:Warn(msg) end
                        if WT.Modules.Frames and type(WT.Modules.Frames.ShowError) == "function" then
                            WT.Modules.Frames:ShowError(msg, 1.0, 0.1, 0.1)
                        elseif UIErrorsFrame then
                            UIErrorsFrame:AddMessage(msg, 1.0, 0.1, 0.1)
                        end
                        PlaySound(847)
                        Module.isRepairing = false
                        return -- Stop trying if we are out of money
                    end
                end
                
                if repaired then
                    -- Wait a moment and check again to make sure nothing was missed
                    C_Timer.After(0.5, ProcessRepairQueue)
                end
            else
                -- Server lag: We have damaged items, but cost is 0 or canRepair is false
                -- We wait and retry intelligently
                C_Timer.After(0.3, ProcessRepairQueue)
            end
        end
        
        C_Timer.After(0.2, ProcessRepairQueue)
    end

    -- 2. Auto Sell Junk
    if WT.DB.Vendor.AutoSellJunk and not Module.isSelling then
        Module.isSelling = true
        C_Timer.After(0.2, function()
            local totalProfit = 0
            local totalItemsSold = 0
            local totalItemsFailed = 0
            local iterations = 0
            local attemptedItems = {}
            
            local function ProcessSellQueue()
                if not MerchantFrame or not MerchantFrame:IsShown() then 
                    Module.isSelling = false
                    return 
                end
                if CursorHasItem() then ClearCursor() end
                
                Module.SuppressUntil = GetTime() + 1.0 -- Suppress native error spam during the active loop
                
                iterations = iterations + 1
                if iterations > 50 then 
                    Module.isSelling = false
                    return 
                end -- Failsafe to prevent infinite loops
                
                local itemsToSell = {}
                local currentBatchProfit = 0
                local lockedJunkCount = 0

                local ignoreList = {}
                if type(WT.DB.Vendor.AutoSellIgnoreList) == "string" then
                    for id in string.gmatch(WT.DB.Vendor.AutoSellIgnoreList, "%d+") do
                        ignoreList[tonumber(id)] = true
                    end
                end
                
                for bag = 0, 5 do
                    for slot = 1, C_Container.GetContainerNumSlots(bag) do
                        local itemID = C_Container.GetContainerItemID(bag, slot)
                        if itemID then
                            local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
                            local itemKey = bag .. "_" .. slot .. "_" .. itemID
                            
                            if itemInfo and SafeNum(itemInfo.itemID) > 0 and type(itemInfo.quality) == "number" and itemInfo.quality == 0 and not SafeBool(itemInfo.hasNoValue) and not ignoreList[itemInfo.itemID] then
                                local attempts = attemptedItems[itemKey] or 0
                                if attempts < 3 then
                                    if SafeBool(itemInfo.isLocked) then
                                        lockedJunkCount = lockedJunkCount + 1
                                    else
                                local isInSet = false
                                if C_Container.GetContainerItemEquipmentSetInfo then
                                    local s, setInfo = pcall(C_Container.GetContainerItemEquipmentSetInfo, bag, slot)
                                    if s and setInfo then
                                        if type(setInfo) == "table" and #setInfo > 0 then isInSet = true
                                        elseif setInfo == true then isInSet = true end
                                    end
                                end
                                if not isInSet then
                                    local price = 0
                                    local price = select(11, C_Item.GetItemInfo(SafeNum(itemInfo.itemID))) or 0
                                    local safePrice = SafeNum(price)
                                    
                                    if safePrice > 0 then
                                        table.insert(itemsToSell, {bag = bag, slot = slot, price = safePrice * SafeNum(itemInfo.stackCount), key = itemKey})
                                    else
                                        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, SafeNum(itemInfo.itemID)) end
                                        lockedJunkCount = lockedJunkCount + 1
                                    end
                                end
                                    end
                                elseif attempts == 3 then
                                    attemptedItems[itemKey] = 4 -- Prevent spam
                            
                            local price = 0
                            local price = select(11, C_Item.GetItemInfo(SafeNum(itemInfo.itemID))) or 0
                            local safePrice = SafeNum(price)
                            
                            if safePrice > 0 then
                                totalProfit = totalProfit - (safePrice * SafeNum(itemInfo.stackCount))
                                totalItemsSold = totalItemsSold - 1
                            end
                            
                            totalItemsFailed = totalItemsFailed + 1
                                end
                            end
                        end
                    end
                end

                if #itemsToSell > 0 then
                    local batchLimit = 0
                    local newItemsThisBatch = 0
                    for _, item in ipairs(itemsToSell) do
                        if batchLimit >= 6 then break end
                        attemptedItems[item.key] = (attemptedItems[item.key] or 0) + 1
                        C_Container.UseContainerItem(item.bag, item.slot)
                        
                        -- Only add profit if it's the first attempt, to avoid overcounting
                        if attemptedItems[item.key] == 1 then
                            currentBatchProfit = currentBatchProfit + item.price
                            newItemsThisBatch = newItemsThisBatch + 1
                        end
                        batchLimit = batchLimit + 1
                    end
                    
                    totalProfit = totalProfit + currentBatchProfit
                    totalItemsSold = totalItemsSold + newItemsThisBatch
                    
                    C_Timer.After(0.3, ProcessSellQueue)
                elseif lockedJunkCount > 0 then
                    -- Still waiting for items to unlock (server processing)
                    C_Timer.After(0.3, ProcessSellQueue)
                else
                    if totalItemsSold > 0 and totalProfit > 0 then
                        local moneyString = C_CurrencyInfo.GetCoinTextureString(totalProfit) or "0"
                        local msg = (WT.L.AUTOMATION_SOLD_JUNK) .. " " .. moneyString
                        
                        if WT.Utils and WT.Utils.Logger then WT.Utils.Logger:Print(msg) end
                        if WT.Utils and WT.Utils.Audio then WT.Utils.Audio:Play(WT.DB.Vendor.AutoSellSound, nil, WT.DB.Vendor.AutoSellSoundChannel) end
                    elseif totalItemsFailed > 0 then
                        local msg = WT.L.AUTOMATION_SELL_NOT_POSSIBLE
                        if WT.Utils and WT.Utils.Logger then WT.Utils.Logger:Warn(msg) end
                        if WT.Modules.Frames and type(WT.Modules.Frames.ShowError) == "function" then
                            WT.Modules.Frames:ShowError(msg, 1.0, 0.1, 0.1)
                        elseif UIErrorsFrame then
                            UIErrorsFrame:AddMessage(msg, 1.0, 0.1, 0.1)
                        end
                        PlaySound(847)
                        Module.SuppressUntil = GetTime() + 2.0 -- Suppress late server responses
                    end
                    Module.isSelling = false
                end
            end
            
            ProcessSellQueue()
        end)
    end
end

function Module:OnMerchantClosed()
    Module.isRepairing = false
    Module.isSelling = false
    Module.lastRepairCost = nil
end
local processedBagButtons = setmetatable({}, {__mode = "k"})

local function UpdateBagButtonVisual(button, forcedBag, forcedSlot)
    if not button then return end
    
    local bag = forcedBag
    local slot = forcedSlot
    
    if not bag then
        if type(button.GetBagID) == "function" then
            bag = button:GetBagID()
        elseif type(button.GetBag) == "function" then
            bag = button:GetBag()
        elseif button.GetParent and type(button.GetParent) == "function" then
            local parent = button:GetParent()
            if parent and type(parent.GetID) == "function" then
                bag = parent:GetID()
            end
        end
    end
    
    if not slot then
        if type(button.GetID) == "function" then
            slot = button:GetID()
        end
    end
    
    if type(bag) ~= "number" or type(slot) ~= "number" or slot == 0 then return end
    
    processedBagButtons[button] = true
    
    local isIgnored = false
    local isJunk = false
    
    if WT.DB.Vendor.AutoSellJunk then
        local itemID
        local quality
        
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            itemID = info.itemID
            quality = info.quality
        end
        
        if itemID then
            if type(quality) ~= "number" or quality == -1 then
                if C_Item and C_Item.RequestLoadItemDataByID then 
                    pcall(C_Item.RequestLoadItemDataByID, itemID) 
                end
                
                if not button.wtPendingUpdate then
                    button.wtPendingUpdate = true
                    C_Timer.After(0.5, function()
                        if button then button.wtPendingUpdate = false end
                        UpdateBagButtonVisual(button, bag, slot)
                    end)
                end
                return
            end
            
            local currentList = WT.DB.Vendor.AutoSellIgnoreList or ""
            local searchStr = tostring(itemID)
            for id in string.gmatch(currentList, "%d+") do
                if id == searchStr then
                    isIgnored = true
                    break
                end
            end
            
            if type(quality) == "number" and quality == Enum.ItemQuality.Poor then
                isJunk = true
            end
        end
    end
    
    -- Icon logic
    if isIgnored then
        if not button.wtAutoSellIgnoreIcon then
            button.wtAutoSellIgnoreIcon = button:CreateTexture(nil, "OVERLAY", nil, 7)
        end
        
        button.wtAutoSellIgnoreIcon:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
        button.wtAutoSellIgnoreIcon:ClearAllPoints()
        button.wtAutoSellIgnoreIcon:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.wtAutoSellIgnoreIcon:SetSize(18, 18)
        button.wtAutoSellIgnoreIcon:Show()
    else
        if button.wtAutoSellIgnoreIcon then
            button.wtAutoSellIgnoreIcon:Hide()
        end
    end
    
    if button.JunkIcon then
        if not button.wtJunkIconHooked then
            button.wtJunkIconHooked = true
            hooksecurefunc(button.JunkIcon, "Show", function(self)
                if not button.wtIsJunk then self:Hide() end
            end)
            hooksecurefunc(button.JunkIcon, "Hide", function(self)
                if button.wtIsJunk then self:Show() end
            end)
        end
        button.wtIsJunk = (isJunk and WT.DB.Vendor.AutoSellJunkIcon)
        
        button.JunkIcon:SetAlpha(1)
        if button.wtIsJunk then
            button.JunkIcon:Show()
        else
            button.JunkIcon:Hide()
        end
    end
    
    -- Desaturation logic
    if WT.DB.Vendor.AutoSellJunkDesaturate then
        local icon = button.icon
        if not icon and button.GetName and button:GetName() then
            icon = _G[button:GetName().."IconTexture"]
        end
        
        if icon then
            if not icon.wtDesatHooked then
                icon.wtDesatHooked = true
                hooksecurefunc(icon, "SetDesaturated", function(self, desat)
                    if button.wtJunkDesaturated and not desat then
                        self:SetDesaturated(true)
                    end
                end)
                hooksecurefunc(icon, "SetVertexColor", function(self, r, g, b)
                    if button.wtJunkDesaturated and (r > 0.5 or g > 0.5 or b > 0.5) then
                        self:SetVertexColor(0.5, 0.5, 0.5)
                    end
                end)
            end
            
            if isJunk then
                button.wtJunkDesaturated = true
                icon:SetDesaturated(true)
                icon:SetVertexColor(0.5, 0.5, 0.5)
            elseif button.wtJunkDesaturated then
                button.wtJunkDesaturated = false
                icon:SetDesaturated(false)
                icon:SetVertexColor(1, 1, 1)
            end
        end
    end
end

local hookedButtons = {}

local function UpdateContainerFrame(container)
    if not container or type(container.EnumerateValidItems) ~= "function" then return end
    for a, b in container:EnumerateValidItems() do
        local itemButton = type(a) == "table" and a or b
        if itemButton then
            if not hookedButtons[itemButton] then
                hookedButtons[itemButton] = true
                if type(itemButton.UpdateItemContextOverlay) == "function" then
                    hooksecurefunc(itemButton, "UpdateItemContextOverlay", UpdateBagButtonVisual)
                end
                if type(itemButton.UpdateItemContextMatching) == "function" then
                    hooksecurefunc(itemButton, "UpdateItemContextMatching", UpdateBagButtonVisual)
                end
            end
            UpdateBagButtonVisual(itemButton)
        end
    end
end

local function RefreshAllBagVisuals()
    for button in pairs(processedBagButtons) do
        UpdateBagButtonVisual(button)
    end
    
    if ContainerFrameCombinedBags then
        UpdateContainerFrame(ContainerFrameCombinedBags)
    end
    
    local containerFrames = ContainerFrameContainer and ContainerFrameContainer["ContainerFrames"]
    if not containerFrames and UIParent and UIParent["ContainerFrames"] then
        containerFrames = UIParent["ContainerFrames"]
    end
    
    if containerFrames then
        for _, frame in pairs(containerFrames) do
            UpdateContainerFrame(frame)
        end
    else
        for i = 1, 13 do
            local frame = _G["ContainerFrame"..i]
            if frame then UpdateContainerFrame(frame) end
        end
    end
    
    local bgn = _G["Baganator"]
    if bgn and type(bgn.API) == "table" and type(bgn.API.RequestItemButtonsRefresh) == "function" then
        if bgn.Constants and bgn.Constants.RefreshReason and bgn.Constants.RefreshReason.ItemWidgets then
            bgn.API.RequestItemButtonsRefresh({ bgn.Constants.RefreshReason.ItemWidgets })
        else
            bgn.API.RequestItemButtonsRefresh()
        end
    end
end

local function GetBaganatorItemButton(frame)
    local current = frame
    for i = 1, 4 do
        if not current then break end
        if current.BGR then return current end
        if current.GetParent then
            current = current:GetParent()
        else
            break
        end
    end
    return nil
end

local function HookBaganatorDesaturation(itemButton)
    if not itemButton or not itemButton.BGR then return end
    
    local icon = itemButton.icon
    if not icon and itemButton.GetName and itemButton:GetName() then
        icon = _G[itemButton:GetName().."IconTexture"]
    end

    if icon and not icon.wtBgnHooked then
        icon.wtBgnHooked = true
        hooksecurefunc(icon, "SetDesaturated", function(self, desat)
            if itemButton.wtJunkDesaturated and not desat then
                self:SetDesaturated(true)
            end
        end)
        hooksecurefunc(icon, "SetVertexColor", function(self, r, g, b)
            if itemButton.wtJunkDesaturated and (r > 0.5 or g > 0.5 or b > 0.5) then
                self:SetVertexColor(0.5, 0.5, 0.5)
            end
        end)
    end
    
    if not WT.DB.Vendor.AutoSellJunkDesaturate or not itemButton.BGR.itemID then return end
    
    local quality = C_Item.GetItemQualityByID(itemButton.BGR.itemID)
    if type(quality) == "number" and quality == Enum.ItemQuality.Poor then
        itemButton.wtJunkDesaturated = true
        icon:SetDesaturated(true)
        icon:SetVertexColor(0.5, 0.5, 0.5)
    elseif itemButton.wtJunkDesaturated then
        itemButton.wtJunkDesaturated = false
        icon:SetDesaturated(false)
        icon:SetVertexColor(1, 1, 1)
    end
end

local function InitBaganatorHooks()
    local bgn = _G["Baganator"]
    if not bgn or type(bgn.API) ~= "table" then return end
    
    if not WT.bgnUpdateHooked then
        WT.bgnUpdateHooked = true
        if type(SetItemButtonTexture) == "function" then
            hooksecurefunc("SetItemButtonTexture", function(btn) HookBaganatorDesaturation(btn) end)
        end
        if type(SetItemButtonQuality) == "function" then
            hooksecurefunc("SetItemButtonQuality", function(btn) HookBaganatorDesaturation(btn) end)
        end
        if ItemButtonMixin and type(ItemButtonMixin.SetItemButtonTexture) == "function" then
            hooksecurefunc(ItemButtonMixin, "SetItemButtonTexture", function(btn) HookBaganatorDesaturation(btn) end)
        end
        if type(SetItemButtonDesaturated) == "function" then
            hooksecurefunc("SetItemButtonDesaturated", function(btn) HookBaganatorDesaturation(btn) end)
        end
    end

    if bgn.API.RegisterJunkPlugin then
        bgn.API.RegisterJunkPlugin("W1LD Tools", "w1ld_tools_junk", function(bagID, slotID, itemID, itemLink)
            if not WT.DB.Vendor.AutoSellJunk then return false end
            
            local quality = C_Item.GetItemQualityByID(itemLink)
            if type(quality) == "number" and quality == Enum.ItemQuality.Poor then
                return true
            end
            
            return false
        end)
    end
    
    -- Removed dummy w1ld_tools_desaturate widget
    
    if bgn.API.RegisterCornerWidget then
        bgn.API.RegisterCornerWidget("WT Ignore", "w1ld_tools_ignore_v2", 
            function(cornerFrame, details)
                local itemID = details.itemID
                if not itemID then return false end
                
                HookBaganatorDesaturation(GetBaganatorItemButton(cornerFrame))
                
                local currentList = WT.DB.Vendor.AutoSellIgnoreList or ""
                local searchStr = tostring(itemID)
                for id in string.gmatch(currentList, "%d+") do
                    if id == searchStr then
                        return true
                    end
                end
                
                return false
            end,
            function(itemButton)
                local icon = itemButton:CreateTexture(nil, "OVERLAY", nil, 7)
                icon:SetTexture("Interface\\PetBattles\\PetBattle-LockIcon")
                icon:SetSize(18, 18)
                return icon
            end,
            {corner = "top_left", priority = 1}
        )
        
        bgn.API.RegisterCornerWidget("WT Junk", "w1ld_tools_junk_icon_v2", 
            function(cornerFrame, details)
                local itemID = details.itemID
                if not itemID then return false end
                
                HookBaganatorDesaturation(GetBaganatorItemButton(cornerFrame))
                
                if not WT.DB.Vendor.AutoSellJunkIcon then return false end
                
                local quality = C_Item.GetItemQualityByID(itemID)
                local isJunk = (type(quality) == "number" and quality == Enum.ItemQuality.Poor)
                
                if isJunk then
                    return true
                end
                
                return false
            end,
            function(itemButton)
                local icon = itemButton:CreateTexture(nil, "OVERLAY", nil, 7)
                icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Coin-Up")
                icon:SetSize(12, 12)
                return icon
            end,
            {corner = "top_left", priority = 2}
        )
    end
end

local function InitBagnonHooks()
    local bagnon = _G["Bagnon"]
    if bagnon and type(bagnon.Item) == "table" and type(bagnon.Item.Update) == "function" then
        hooksecurefunc(bagnon.Item, "Update", function(self)
            UpdateBagButtonVisual(self)
        end)
    end
end

local function InitBagHooks()
    local function OnBagButtonUpdated(button)
        UpdateBagButtonVisual(button)
    end
    
    local mixin = ContainerFrameItemButtonMixin
    if mixin then
        if type(mixin.UpdateItemContextMatching) == "function" then
            hooksecurefunc(mixin, "UpdateItemContextMatching", OnBagButtonUpdated)
        end
        if type(mixin.UpdateItemContextOverlay) == "function" then
            hooksecurefunc(mixin, "UpdateItemContextOverlay", OnBagButtonUpdated)
        end
        if type(mixin.Update) == "function" then
            hooksecurefunc(mixin, "Update", OnBagButtonUpdated)
        end
    end
    
    if ContainerFrameCombinedBags and type(ContainerFrameCombinedBags.UpdateItems) == "function" then
        hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", UpdateContainerFrame)
    end
    
    local containerFrames = ContainerFrameContainer and ContainerFrameContainer["ContainerFrames"]
    if not containerFrames and UIParent and UIParent["ContainerFrames"] then
        containerFrames = UIParent["ContainerFrames"]
    end
    
    if containerFrames then
        for _, frame in pairs(containerFrames) do
            if type(frame.UpdateItems) == "function" then
                hooksecurefunc(frame, "UpdateItems", UpdateContainerFrame)
            end
        end
    else
        for i = 1, 13 do
            local frame = _G["ContainerFrame"..i]
            if frame and type(frame.UpdateItems) == "function" then
                hooksecurefunc(frame, "UpdateItems", UpdateContainerFrame)
            end
        end
    end
    
    InitBaganatorHooks()
    InitBagnonHooks()
    
    local refreshQueued = false
    local function TriggerDebouncedBagRefresh()
        if not refreshQueued then
            refreshQueued = true
            C_Timer.After(0.2, function()
                refreshQueued = false
                RefreshAllBagVisuals()
            end)
        end
    end
    
    WT.Core.Events:Register("BAG_UPDATE_DELAYED", RefreshAllBagVisuals)
    WT.Core.Events:Register("GET_ITEM_INFO_RECEIVED", TriggerDebouncedBagRefresh)
    C_Timer.After(0.5, RefreshAllBagVisuals)
end

local function ToggleIgnoreItem(itemID, link)
    if not itemID then return end
    
    local currentList = WT.DB.Vendor.AutoSellIgnoreList or ""
    local list = {}
    for id in string.gmatch(currentList, "%d+") do
        list[tonumber(id)] = true
    end
    
    local itemIdentifier = link or itemID
    
    if list[itemID] then
        list[itemID] = nil
        if WT.Utils and WT.Utils.Logger then WT.Utils.Logger:Print(string.format(WT.L.AUTOMATION_IGNORE_REMOVED, itemIdentifier)) end
    else
        list[itemID] = true
        if WT.Utils and WT.Utils.Logger then WT.Utils.Logger:Print(string.format(WT.L.AUTOMATION_IGNORE_ADDED, itemIdentifier)) end
    end
    
    local newList = ""
    for id in pairs(list) do
        newList = newList .. (newList == "" and "" or ", ") .. id
    end
    WT.DB.Vendor.AutoSellIgnoreList = newList
    RefreshAllBagVisuals()
end

local function AddAutoSellHint(tooltip, data)
    if not WT.DB.Vendor.AutoSellJunk then return end
    if tooltip:IsForbidden() then return end
    if not data or not data.id then return end

    if C_Item and C_Item.GetItemQualityByID then
        local quality = C_Item.GetItemQualityByID(data.id)
        if quality == 0 then
            local isIgnored = false
            local currentList = WT.DB.Vendor.AutoSellIgnoreList or ""
            for id in string.gmatch(currentList, "%d+") do
                if tonumber(id) == data.id then
                    isIgnored = true
                    break
                end
            end
            
            local statusText = isIgnored and (WT.L.TT_AUTOSELL_IGNORED)
            local hintText = tostring(WT.L.TT_AUTOSELL_IGNORE_HINT)
            
            local tooltipName = WT.Utils and WT.Utils.Safety and WT.Utils.Safety.GetSafeTooltipName(tooltip) or tooltip:GetName()
            local found = false
            if tooltipName and type(tooltip.NumLines) == "function" then
                for i = 1, tooltip:NumLines() do
                    local line = _G[tooltipName .. "TextLeft" .. i]
                    if line and line:GetText() == hintText then
                        found = true
                        break
                    end
                end
            end
            
            if not found then
                tooltip:AddLine(" ")
                tooltip:AddLine(hintText, 0, 1, 1)
                if statusText then tooltip:AddLine(statusText) end
            end
        end
    end
end

function Module:Initialize()
    if not WT.DB.Modules.Automations then return end
    WT.Core.Events:Register("MERCHANT_SHOW", function() Module:OnMerchantShow() end)
    WT.Core.Events:Register("MERCHANT_CLOSED", function() Module:OnMerchantClosed() end)

    InitBagHooks()

    hooksecurefunc("HandleModifiedItemClick", function(link)
        if IsAltKeyDown() and IsControlKeyDown() and not IsShiftKeyDown() then
            if link then
                local itemID = string.match(link, "item:(%d+)")
                if itemID then
                    ToggleIgnoreItem(tonumber(itemID), link)
                end
            end
        end
    end)
    
    if TooltipDataProcessor then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddAutoSellHint)
    end
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
    
    panel:CreateTitle(builder, WT.L.GROUP_REPAIRS)
    AddDescription(WT.L.OPT_DESC_GROUP_REPAIRS)
    
    local repairInit = panel:CreateCheckbox(builder, WT.L.OPT_AUTO_REPAIR, WT.L.OPT_DESC_AUTO_REPAIR, "Vendor", "AutoRepair")
    panel:CreateCheckbox(builder, WT.L.OPT_AUTO_REPAIR_GUILD, WT.L.OPT_DESC_AUTO_REPAIR_GUILD, "Vendor", "AutoRepairGuildBank", nil, repairInit)
    if WT.Utils and WT.Utils.SharedMedia then
        panel:CreateSoundDropdown(builder, WT.L.OPT_AUTO_REPAIR_SOUND, WT.L.OPT_DESC_AUTO_REPAIR_SOUND, "Vendor", "AutoRepairSound", repairInit)
    end
    
    panel:CreateTitle(builder, WT.L.GROUP_SELLING)
    AddDescription(WT.L.OPT_DESC_GROUP_SELLING)
    
    local sellInit = panel:CreateCheckbox(builder, WT.L.OPT_AUTO_SELL_JUNK, WT.L.OPT_DESC_AUTO_SELL_JUNK, "Vendor", "AutoSellJunk")
    panel:CreateCheckbox(builder, WT.L.OPT_AUTO_SELL_JUNK_ICON, WT.L.OPT_DESC_AUTO_SELL_JUNK_ICON, "Vendor", "AutoSellJunkIcon", nil, sellInit)
    panel:CreateCheckbox(builder, WT.L.OPT_AUTO_SELL_JUNK_DESATURATE, WT.L.OPT_DESC_AUTO_SELL_JUNK_DESATURATE, "Vendor", "AutoSellJunkDesaturate", nil, sellInit)
    if WT.Utils and WT.Utils.SharedMedia then
        panel:CreateSoundDropdown(builder, WT.L.OPT_AUTO_SELL_SOUND, WT.L.OPT_DESC_AUTO_SELL_SOUND, "Vendor", "AutoSellSound", sellInit)
    end
    
    panel:CreateMultiLineEditBox(builder, WT.L.OPT_AUTO_SELL_IGNORE, WT.L.OPT_DESC_AUTO_SELL_IGNORE, "Vendor", "AutoSellIgnoreList", 60)
end