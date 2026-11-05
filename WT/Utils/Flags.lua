local _, WT = ...

WT.Utils.Flags = {}

-- Set a CVar and remember its original state if we haven't already
function WT.Utils.Flags:SetCVar(cvar, value)
    if not WT.DB.Internal.OriginalCVars then
        WT.DB.Internal.OriginalCVars = {}
    end
    
    local getCVar = C_CVar and C_CVar.GetCVar or _G["GetCVar"]
    local setCVar = C_CVar and C_CVar.SetCVar or _G["SetCVar"]

    -- Only save the original state if we haven't saved one yet
    if WT.DB.Internal.OriginalCVars[cvar] == nil then
        local ok, current = pcall(getCVar, cvar)
        WT.DB.Internal.OriginalCVars[cvar] = ok and current or nil
    end
    
    pcall(setCVar, cvar, value)
end