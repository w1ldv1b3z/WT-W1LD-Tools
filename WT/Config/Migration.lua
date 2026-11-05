local _, WT = ...

WT.Config = WT.Config or {}

function WT.Config:RunMigrations(db)
    if not db.Internal then db.Internal = {} end
    local currentVer = db.Internal.DBVersion or 0

    if currentVer < 200 then
        -- Prepare for future migrations here (e.g. if currentVer < 210 then ... end)
        db.Internal.DBVersion = 200
    end

    if currentVer < 201 then
        if db.Chat then
            if type(db.ChatChannels) ~= "table" then db.ChatChannels = {} end
            local keysToMove = {
                "ChanGuildEnabled", "ChanGuildSound", "ChanGuildColorEnabled", "ChanGuildColor", "ChanGuildAliasEnabled",
                "ChanGuildAlias",
                "ChanPartyEnabled", "ChanPartySound", "ChanPartyColorEnabled", "ChanPartyColor", "ChanPartyAliasEnabled",
                "ChanPartyAlias",
                "ChanRaidEnabled", "ChanRaidSound", "ChanRaidColorEnabled", "ChanRaidColor", "ChanRaidAliasEnabled",
                "ChanRaidAlias",
                "ChanInstanceEnabled", "ChanInstanceSound", "ChanInstanceColorEnabled", "ChanInstanceColor",
                "ChanInstanceAliasEnabled", "ChanInstanceAlias",
                "ChanOfficerEnabled", "ChanOfficerSound", "ChanOfficerColorEnabled", "ChanOfficerColor",
                "ChanOfficerAliasEnabled", "ChanOfficerAlias",
                "CustomChan1Enabled", "CustomChan1Name", "CustomChan1Sound", "CustomChan1ColorEnabled",
                "CustomChan1Color", "CustomChan1AliasEnabled", "CustomChan1Alias",
                "CustomChan2Enabled", "CustomChan2Name", "CustomChan2Sound", "CustomChan2ColorEnabled",
                "CustomChan2Color", "CustomChan2AliasEnabled", "CustomChan2Alias",
                "CustomChan3Enabled", "CustomChan3Name", "CustomChan3Sound", "CustomChan3ColorEnabled",
                "CustomChan3Color", "CustomChan3AliasEnabled", "CustomChan3Alias"
            }
            for _, k in ipairs(keysToMove) do if db.Chat[k] ~= nil then db.ChatChannels[k] = db.Chat[k] end end
        end
        db.Internal.DBVersion = 201
    end

    if currentVer < 202 then
        if db.Frames then
            if type(db.Nameplates) ~= "table" then db.Nameplates = {} end
            local npKeys = { "SmartNameplates", "NameplateClassColors", "NameplateThreat", "NameplateStacking",
                "NameplateOverlapV" }
            for _, k in ipairs(npKeys) do
                if db.Frames[k] ~= nil then db.Nameplates[k] = db.Frames[k] end
            end
        end
        if db.Modules and db.Modules.Nameplates == nil and db.Modules.Frames ~= nil then
            db.Modules.Nameplates = db.Modules.Frames
        end
        db.Internal.DBVersion = 202
    end

    if currentVer < 203 then
        if db.Automations then
            if type(db.Questing) ~= "table" then db.Questing = {} end
            local qKeys = { "AutoSkipCinematics", "SmartGossip", "GossipQuestColor", "GossipQuestColV", "FastQuesting",
                "AutoAcceptQuests", "AutoTurnInQuests" }
            for _, k in ipairs(qKeys) do
                if db.Automations[k] ~= nil then db.Questing[k] = db.Automations[k] end
            end
        end
        if db.Modules and db.Modules.Questing == nil and db.Modules.Automations ~= nil then
            db.Modules.Questing = db.Modules.Automations
        end
        db.Internal.DBVersion = 203
    end

    if currentVer < 204 then
        if db.Frames then
            if type(db.Fader) ~= "table" then db.Fader = {} end
            local fKeys = {
                "FaderShowInCombat", "FaderBaseAlpha", "FaderSpeedIn", "FaderSpeedOut",
                "LinkBar12", "LinkBar123", "LinkBar45", "LinkBar67",
                "FadeBar1", "ScaleBar1", "FadeBar2", "ScaleBar2", "FadeBar3", "ScaleBar3",
                "FadeBar4", "ScaleBar4", "FadeBar5", "ScaleBar5", "FadeBar6", "ScaleBar6",
                "FadeBar7", "ScaleBar7", "FadeBar8", "ScaleBar8", "FadePetBar", "ScalePetBar",
                "FadeStanceBar", "ScaleStanceBar", "FadeBagsBar", "ScaleBagsBar",
                "FadeMicroMenu", "ScaleMicroMenu", "FadeStatusBars", "ScaleStatusBars",
                "FadeVehicleLeave", "ScaleVehicleLeave", "FadeExtraAbility", "ScaleExtraAbility"
            }
            for _, k in ipairs(fKeys) do
                if db.Frames[k] ~= nil then db.Fader[k] = db.Frames[k] end
            end
        end
        if db.Modules and db.Modules.Fader == nil and db.Modules.Frames ~= nil then
            db.Modules.Fader = db.Modules.Frames
        end
        db.Internal.DBVersion = 204
    end

    if currentVer < 206 then
        if db.Tooltip then
            if type(db.Wowhead) ~= "table" then db.Wowhead = {} end
            if db.Tooltip.WowheadLink ~= nil then db.Wowhead.ShowTooltipHint = db.Tooltip.WowheadLink end

            if type(db.Durability) ~= "table" then db.Durability = {} end
            if db.Tooltip.Durability ~= nil then db.Durability.ShowTooltip = db.Tooltip.Durability end
        end
        db.Internal.DBVersion = 206
    end

    if currentVer < 207 then
        if db.Chat and db.Chat.SmartLoginSound == "W1LD - 08" then
            db.Chat.SmartLoginSound = "None"
        end
        db.Internal.DBVersion = 208
    end

    if currentVer < 208 then
        if db.Modules then
            db.Modules.Chat = db.Modules.Chat or db.Modules.ChatUI or db.Modules.ChatChannels
            db.Modules.Automations = db.Modules.Automations or db.Modules.Questing or db.Modules.Vendor
            db.Modules.Groups = db.Modules.Groups or db.Modules.LFG
            db.Modules.Tooltip = db.Modules.Tooltip or db.Modules.Wowhead
            db.Modules.Frames = db.Modules.Frames or db.Modules.Durability

            db.Modules.ChatUI = nil
            db.Modules.ChatChannels = nil
            db.Modules.LFG = nil
            db.Modules.Wowhead = nil
            db.Modules.Vendor = nil
            db.Modules.Questing = nil
            db.Modules.Durability = nil
        end
        db.Internal.DBVersion = 208
    end

    if currentVer < 209 then
        if db.Frames and db.Frames.ShowItemLevel ~= nil then
            if type(db.CharacterSheet) ~= "table" then db.CharacterSheet = {} end
            local keys = { "ShowItemLevel", "ItemLevelPosition", "ItemLevelColorize", "ItemLevelBackground",
                "ItemLevelFont", "ItemLevelSize", "ItemLevelOutline" }
            for _, k in ipairs(keys) do
                if db.Frames[k] ~= nil then db.CharacterSheet[k] = db.Frames[k] end
            end
        end
        if db.Durability and db.Durability.ShowCharacterSheet ~= nil then
            if type(db.CharacterSheet) ~= "table" then db.CharacterSheet = {} end
            if db.Durability.ShowCharacterSheet ~= nil then db.CharacterSheet.ShowDurability = db.Durability
                .ShowCharacterSheet end
            if db.Durability.Position ~= nil then db.CharacterSheet.DurabilityPosition = db.Durability.Position end
            if db.Durability.OnlyDamaged ~= nil then db.CharacterSheet.DurabilityOnlyDamaged = db.Durability.OnlyDamaged end
            if db.Durability.Background ~= nil then db.CharacterSheet.DurabilityBackground = db.Durability.Background end
            if db.Durability.Font ~= nil then db.CharacterSheet.DurabilityFont = db.Durability.Font end
            if db.Durability.FontSize ~= nil then db.CharacterSheet.DurabilityFontSize = db.Durability.FontSize end
            if db.Durability.FontOutline ~= nil then db.CharacterSheet.DurabilityFontOutline = db.Durability.FontOutline end
        end
        if db.Modules and db.Modules.Frames ~= nil and db.Modules.CharacterSheet == nil then
            db.Modules.CharacterSheet = db.Modules.Frames
        end
        db.Internal.DBVersion = 209
    end

    if currentVer < 210 then
        if db.Modules then
            if db.Modules.Maps == nil then
                db.Modules.Maps = db.Modules.Minimap or db.Modules.Coords
            end
            if db.Modules.Chat == nil then
                db.Modules.Chat = db.Modules.SocialWidget
            elseif db.Modules.SocialWidget then
                db.Modules.Chat = true
            end
            if db.Modules.Frames == nil then
                db.Modules.Frames = db.Modules.ClassColors or db.Modules.Fader
            elseif db.Modules.ClassColors or db.Modules.Fader then
                db.Modules.Frames = true
            end

            db.Modules.Minimap = nil
            db.Modules.Coords = nil
            db.Modules.SocialWidget = nil
            db.Modules.ClassColors = nil
            db.Modules.Fader = nil
        end
        db.Internal.DBVersion = 210
    end

    if currentVer < 211 then
        if db.Modules then
            if db.Modules.SocialWidget == nil and db.Modules.Chat then
                db.Modules.SocialWidget = true
            end
        end
        db.Internal.DBVersion = 211
    end

    if currentVer < 212 then
        if db.Chat and db.Chat.CustomMutes ~= nil then
            if type(db.Audio) ~= "table" then db.Audio = {} end
            db.Audio.CustomMutes = db.Chat.CustomMutes
            db.Chat.CustomMutes = nil
        end
        if db.Modules then
            if db.Modules.ChatMute ~= nil then
                db.Modules.Audio = db.Modules.ChatMute
                db.Modules.ChatMute = nil
            elseif db.Modules.Audio == nil and db.Modules.Chat then
                db.Modules.Audio = true
            end
        end
        db.Internal.DBVersion = 212
    end

    if currentVer < 213 then
        if db.Frames and db.Frames.SkinPopups ~= nil then
            if type(db.General) ~= "table" then db.General = {} end
            db.General.SkinPopups = db.Frames.SkinPopups
            db.Frames.SkinPopups = nil
        end
        db.Internal.DBVersion = 213
    end

    if currentVer < 221 then
        db.Internal.DBVersion = 221
    end

    if currentVer < 240 then
        if db.Modules and db.Modules.Keybindings == nil and db.Modules.Chat ~= nil then
            db.Modules.Keybindings = db.Modules.Chat
        end
        db.Internal.DBVersion = 240
    end

    if currentVer < 282 then
        -- "Hide Tutorials" was removed (Blizzard has its own option). Undo the hidden CVar it set;
        -- showTutorials is left alone because players can see and change it in the game options.
        if db.Frames and db.Frames.HideTutorials and C_CVar and C_CVar.GetCVarDefault then
            local default = C_CVar.GetCVarDefault("hideHelptips")
            if default then C_CVar.SetCVar("hideHelptips", default) end
        end
        db.Internal.DBVersion = 282
    end
end
