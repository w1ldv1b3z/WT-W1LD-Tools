local _, WT = ...

WT.Utils = WT.Utils or {}
WT.Utils.Strings = {}

function WT.Utils.Strings:EscapeRegex(text)
    if not text then return "" end
    local safeText = WT.Utils.Safety.Unsecret(text)
    if type(safeText) ~= "string" then return "" end
    
    -- Fast-Path: Skip expensive gsub allocation if the string contains no magic regex characters at all
    if not string.find(safeText, "[%%%^%$%(%)%.%[%]%*%+%-%?]") then
        return safeText
    end
    
    return (string.gsub(safeText, "([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"))
end