local _, WT = ...

-- Event Registry: Stores all callbacks for a specific event
local eventRegistry = {}
local onUpdateRegistry = {}

local function ErrorHandler(err)
    geterrorhandler()(err)
    return tostring(err)
end

-- Internal frame for WoW events
local EventFrame = CreateFrame("Frame")
EventFrame:SetScript("OnEvent", function(_, event, ...)
    if eventRegistry[event] then
        for _, reg in ipairs(eventRegistry[event]) do
            -- BATTLE-SAFE: Isolates faulty callbacks so the rest of the event queue does not crash
            xpcall(reg.cb, ErrorHandler, event, ...)
        end
    end
end)

WT.Core.Events = {}

-- Function to register an event
function WT.Core.Events:Register(event, callback)
    if type(callback) ~= "function" then return end
    
    if not eventRegistry[event] then
        eventRegistry[event] = {}
        pcall(function() EventFrame:RegisterEvent(event) end)
    end
    table.insert(eventRegistry[event], { cb = callback })
end

-- Function to unregister an event
function WT.Core.Events:Unregister(event, callback)
    if not eventRegistry[event] then return end
    for i, reg in ipairs(eventRegistry[event]) do
        if reg.cb == callback then
            table.remove(eventRegistry[event], i)
            break
        end
    end
    if #eventRegistry[event] == 0 then
        pcall(function() EventFrame:UnregisterEvent(event) end)
        eventRegistry[event] = nil
    end
end

-- Function to manually fire an event (useful for testing or custom modules)
function WT.Core.Events:Fire(event, ...)
    local handler = EventFrame:GetScript("OnEvent")
    if handler then
        handler(EventFrame, event, ...)
    end
end

-- Global OnUpdate Dispatcher
local UpdateFrame = CreateFrame("Frame")
UpdateFrame:SetScript("OnUpdate", function(self, elapsed)
    for i = 1, #onUpdateRegistry do
        local reg = onUpdateRegistry[i]
        reg.timer = reg.timer + elapsed
        if reg.timer >= reg.interval then
            local execElapsed = reg.timer
            reg.timer = 0
            
            -- BATTLE-SAFE: Error isolation for the OnUpdate dispatcher
            xpcall(reg.cb, ErrorHandler, self, execElapsed)
        end
    end
end)

function WT.Core.Events:RegisterOnUpdate(callback, interval)
    if type(callback) ~= "function" then return end
    table.insert(onUpdateRegistry, { cb = callback, interval = interval or 0, timer = 0 })
end

function WT.Core.Events:UnregisterOnUpdate(callback)
    for i, reg in ipairs(onUpdateRegistry) do
        if reg.cb == callback then table.remove(onUpdateRegistry, i); break end
    end
end

-- ============================================================================
-- COMBAT QUEUE (Safety Routine)
-- ============================================================================
WT.Core.CombatQueue = {}
local combatQueueTasks = {}

function WT.Core.CombatQueue:Add(taskKey, isSilent, func, ...)
    if InCombatLockdown() then
        combatQueueTasks[taskKey] = { fn = func, args = {...} }
        if not isSilent and WT.Utils and WT.Utils.Logger then 
            WT.Utils.Logger:Warn(WT.L.MSG_COMBAT_BLOCK) 
        end
        return true -- Task was queued
    end
    return false -- Safe to execute immediately
end

WT.Core.Events:Register("PLAYER_REGEN_ENABLED", function()
    if next(combatQueueTasks) then
        -- BATTLE-SAFE: Delaying by 1 frame ensures the engine has completely lifted the combat lockdown
        C_Timer.After(0, function()
            if InCombatLockdown() then return end
            for key, task in pairs(combatQueueTasks) do
                pcall(task.fn, unpack(task.args))
            end
            wipe(combatQueueTasks)
        end)
    end
end)