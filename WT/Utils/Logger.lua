local addonName, WT = ...

WT.Utils.Logger = {}

local PREFIX = WT.Colors.PRIMARY .. "[" .. addonName .. "]|r"
local Unsecret = WT.Utils.Safety and WT.Utils.Safety.Unsecret or function(s) return s end

---@param ... any
---@return string
local function JoinArgs(...)
    local count = select("#", ...)
    if count == 0 then return "" end
    if count == 1 then return tostring(Unsecret((...)) or "") end
    local result = {}
    for i = 1, count do
        table.insert(result, tostring(Unsecret(select(i, ...)) or ""))
    end
    return table.concat(result, " ")
end

local function PrintToChat(prefix, level, msg)
    if not msg or string.match(msg, "^%s*$") then return end
    
    local outMsg = ""
    if level == "INFO" then
        outMsg = prefix .. " " .. msg
    else
        local levelColor = "FF888888"
        local levelText = level
        if level == "WARN" then levelColor = "FFFFFF00"; levelText = WT.L.PREFIX_WARN
        elseif level == "ERROR" then levelColor = "FFFF0000"; levelText = WT.L.PREFIX_ERROR
        elseif level == "DEBUG" then levelColor = "FF888888"; levelText = WT.L.PREFIX_DEBUG end
        outMsg = prefix .. " |c" .. levelColor .. "[" .. levelText .. "]|r " .. msg
    end
    
    WT.isLoggerPrinting = true
    if DEFAULT_CHAT_FRAME then 
        DEFAULT_CHAT_FRAME:AddMessage(outMsg)
    else 
        print(outMsg) 
    end
    WT.isLoggerPrinting = false
end

function WT.Utils.Logger:Print(...)
    PrintToChat(PREFIX, "INFO", JoinArgs(...))
end

function WT.Utils.Logger:PrintNoLog(...)
    PrintToChat(PREFIX, "INFO", JoinArgs(...))
end

function WT.Utils.Logger:Warn(...)
    PrintToChat(PREFIX, "WARN", JoinArgs(...))
end

function WT.Utils.Logger:Error(...)
    PrintToChat(PREFIX, "ERROR", JoinArgs(...))
end

function WT.Utils.Logger:Debug(...)
    local isDebug = WT.DB and WT.DB.General and WT.DB.General.DebugMode
    if isDebug then
        PrintToChat(PREFIX, "DEBUG", JoinArgs(...))
    end
end