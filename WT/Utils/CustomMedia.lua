local addonName, WT = ...

WT.CustomMedia = {}

-- ============================================================================
-- CUSTOM MEDIA REGISTRY (HOW-TO)
-- ============================================================================
-- You can register your own custom media files here. These will be automatically
-- injected into W1LD Tools and LibSharedMedia, making them available in all
-- dropdown menus across the addon.
--
-- INSTRUCTIONS:
-- 1. Place your media files (.ogg/.mp3 for Sounds, .ttf for Fonts, .tga for Textures/Statusbars)
--    anywhere inside your WoW AddOns folder.
--    (Recommendation: Place them inside the WT/Media/ folder to keep things tidy).
-- 2. Add a new line to the corresponding table below.
-- 3. The format is: ["Your Custom Name"] = "Interface/AddOns/Path/To/File.ext",
--    (If you use the 'customPath' variable, it points to 'Interface/AddOns/WT/Media/').
-- 4. Save this file and completely restart World of Warcraft (or type /reload).
--
-- IMPORTANT WARNING:
-- If you add your own custom entries here, this file WILL be overwritten
-- when you update W1LD Tools to a new version! Please remember to back up
-- this file (or copy your additions) before updating the addon.
-- ============================================================================

local customPath = "Interface/AddOns/" .. addonName .. "/Media/"

WT.CustomMedia.Sounds = {
    ["W1LD-Selection: Alarm"] = customPath .. "Sounds/alarm.ogg",
    ["W1LD-Selection: Among US"] = customPath .. "Sounds/among-us.ogg",
    ["W1LD-Selection: Bruh"] = customPath .. "Sounds/bruh.ogg",
    ["W1LD-Selection: Island Boy"] = customPath .. "Sounds/island-boy.ogg",
    ["W1LD-Selection: Au! (Kinski)"] = customPath .. "Sounds/kinski-au.ogg",
    ["W1LD-Selection: Pass doch auf (Kinski)"] = customPath .. "Sounds/kinski-pass_doch_auf.ogg",
    ["W1LD-Selection: OMG"] = customPath .. "Sounds/oh-my-god.ogg",
    ["W1LD-Selection: Okay Let's Go!"] = customPath .. "Sounds/okay-lets-go.ogg",
    ["W1LD-Selection: Rizz"] = customPath .. "Sounds/rizz.ogg",
}

WT.CustomMedia.Fonts = {
    -- Register custom .ttf files here:
    ["W1LD-Selection: Exo 2"] = customPath .. "Fonts/Exo_2/Exo2-Regular.ttf",
    ["W1LD-Selection: Questrial"] = customPath .. "Fonts/Questrial/Questrial-Regular.ttf",
    ["W1LD-Selection: LuckiestGuy"] = customPath .. "Fonts/LuckiestGuy/LuckiestGuy-Regular.ttf",
}

WT.CustomMedia.Statusbars = {
    -- Register custom .tga or .blp files here (used for health bars, cast bars, XP bars, etc.):
    -- Note: For best results, texture dimensions should be a power of 2 (e.g., 256x32 or 512x64).
    -- ["W1LD-Selection: Clean"] = customPath .. "Statusbars/Clean.tga",
    -- ["W1LD-Selection: Flat"] = customPath .. "Statusbars/Flat.tga",
    -- ["W1LD-Selection: Glow"] = customPath .. "Statusbars/Glow.tga",
    -- ["W1LD-Selection: Minimal"] = customPath .. "Statusbars/Minimal.tga",
    -- ["W1LD-Selection: Smooth"] = customPath .. "Statusbars/Smooth.tga",
}

WT.CustomMedia.Backgrounds = {
    -- Register custom .tga or .blp files here (used for frame backgrounds):
    -- Note: For best results, texture dimensions should be a power of 2 (e.g., 256x256).
    -- ["W1LD-Background: Solid"] = customPath .. "Backgrounds/Solid.tga",
}

WT.CustomMedia.Borders = {
    -- Register custom .tga or .blp files here (used for frame borders):
    -- Note: Must be formatted as a standard UI border texture.
    -- ["W1LD-Border: Clean"] = customPath .. "Borders/Clean.tga",
}

WT.CustomMedia.Highlights = {
    -- Register custom .tga or .blp files here (used for mouse highlight textures):
    -- ["W1LD-Highlight: Glow"] = customPath .. "Highlights/Glow.tga",
}
