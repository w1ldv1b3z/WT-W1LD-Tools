local _, WT = ...

WT.L = {}

-- Fallback mechanism for missing translations
-- Uses a protected call to prevent engine crashes if external scripts index with restricted objects
WT.L.OPT_FRAMES_UF_PORTRAIT_OPT4 = "Faction Logo"
WT.L.OPT_FRAMES_UF_PORTRAIT_OPT5 = "Flat (No Borders)"
WT.L.OPT_FRAMES_UF_CORNER_COLOR = "Corner Icon Color"
WT.L.OPT_FRAMES_UF_CORNER_COLOR_DESC = "Colorize the PlayerPortraitCornerIcon (if present)."
setmetatable(WT.L, {
    __index = function(t, key)
        if type(key) == "string" then return key end
        return "UNKNOWN_KEY"
    end
})