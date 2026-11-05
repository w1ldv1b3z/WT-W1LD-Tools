local _, WT = ...

-- ============================================================================
-- EVENT BUS
-- ============================================================================
-- Central dispatcher for game events, WT-internal events and throttled OnUpdate
-- callbacks. Modules register here instead of creating their own event frames.
--
-- Guarantees:
--   * Every callback runs isolated: an error is reported to the error handler
--     (BugSack) but never stops the remaining callbacks of the same event.
--   * Callback lists are copied on write, so registering or unregistering while
--     an event is being dispatched never skips or breaks other callbacks.
--   * A callback is registered at most once per event.
--   * Event names starting with "WT_" are WT-internal: they are never registered
--     with the game and are only dispatched via WT.Core.Events:Fire().
--   * An optional owner (e.g. the module name) allows removing all callbacks of
--     that owner at once with UnregisterAll(owner).

WT.Core.Events = {}
local Events = WT.Core.Events

local eventRegistry = {}     -- event -> array of { cb = function, owner = string? }
local onUpdateRegistry = {}  -- array of { cb = function, interval = number, timer = number, owner = string? }

local function ErrorHandler(err)
    geterrorhandler()(err)
    return err
end

local function IsInternalEvent(event)
    return string.sub(event, 1, 3) == "WT_"
end

-- Returns a copy of `list` without the entries matching `predicate`; removed entries are flagged
-- so that a dispatch currently iterating over the old list skips them.
local function CopyWithout(list, predicate)
    local result = {}
    for i = 1, #list do
        local reg = list[i]
        if predicate(reg) then
            reg.removed = true
        else
            result[#result + 1] = reg
        end
    end
    return result
end

local function CopyWith(list, entry)
    local result = {}
    for i = 1, #list do result[i] = list[i] end
    result[#result + 1] = entry
    return result
end

-- ----------------------------------------------------------------------------
-- Throttled OnUpdate callbacks (dispatcher frame)
-- ----------------------------------------------------------------------------
-- The dispatcher frame is only shown while at least one callback is registered,
-- so it costs nothing when no module needs per-frame updates.
local UpdateFrame = CreateFrame("Frame")
UpdateFrame:Hide()
UpdateFrame:SetScript("OnUpdate", function(self, elapsed)
    local list = onUpdateRegistry
    for i = 1, #list do
        local reg = list[i]
        if not reg.removed then
            reg.timer = reg.timer + elapsed
            if reg.timer >= reg.interval then
                local execElapsed = reg.timer
                reg.timer = 0
                xpcall(reg.cb, ErrorHandler, self, execElapsed)
            end
        end
    end
end)

local function SetOnUpdateList(list)
    onUpdateRegistry = list
    UpdateFrame:SetShown(#list > 0)
end

-- ----------------------------------------------------------------------------
-- Game and internal events
-- ----------------------------------------------------------------------------
local EventFrame = CreateFrame("Frame")

local function Dispatch(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    for i = 1, #list do
        local reg = list[i]
        if not reg.removed then
            xpcall(reg.cb, ErrorHandler, event, ...)
        end
    end
end

EventFrame:SetScript("OnEvent", function(_, event, ...)
    Dispatch(event, ...)
end)

local function RegisterGameEvent(event)
    -- Feature detection: RegisterEvent raises an error for events that do not exist in this
    -- client (e.g. Retail-only events on WoW Forever) or that addons may not register.
    -- Such events are skipped without a Lua error.
    return (pcall(EventFrame.RegisterEvent, EventFrame, event))
end

--- Registers `callback(event, ...)` for a game event or a WT-internal event ("WT_...").
--- Registering the same callback twice for one event has no effect.
---@param event string
---@param callback function
---@param owner string|nil Optional owner name, used by UnregisterAll()
---@return boolean registered false if the event does not exist in this client
function Events:Register(event, callback, owner)
    if type(event) ~= "string" or type(callback) ~= "function" then return false end

    local list = eventRegistry[event]
    if list then
        for i = 1, #list do
            if list[i].cb == callback then return true end
        end
    else
        if not IsInternalEvent(event) and not RegisterGameEvent(event) then
            return false
        end
        list = {}
    end

    eventRegistry[event] = CopyWith(list, { cb = callback, owner = owner })
    return true
end

local function SetEventList(event, list)
    if #list > 0 then
        eventRegistry[event] = list
        return
    end
    eventRegistry[event] = nil
    if not IsInternalEvent(event) then
        EventFrame:UnregisterEvent(event)
    end
end

--- Removes `callback` from `event`.
---@param event string
---@param callback function
function Events:Unregister(event, callback)
    local list = eventRegistry[event]
    if not list then return end
    SetEventList(event, CopyWithout(list, function(reg) return reg.cb == callback end))
end

--- Removes every event and OnUpdate callback that was registered with `owner`.
---@param owner string
function Events:UnregisterAll(owner)
    if owner == nil then return end
    local function isOwned(reg) return reg.owner == owner end

    local events = {}
    for event in pairs(eventRegistry) do events[#events + 1] = event end
    for _, event in ipairs(events) do
        SetEventList(event, CopyWithout(eventRegistry[event], isOwned))
    end

    SetOnUpdateList(CopyWithout(onUpdateRegistry, isOwned))
end

--- Dispatches `event` to all its callbacks. Mainly used for WT-internal events ("WT_...").
---@param event string
function Events:Fire(event, ...)
    Dispatch(event, ...)
end

-- ----------------------------------------------------------------------------
-- Throttled OnUpdate callbacks (registration)
-- ----------------------------------------------------------------------------
--- Calls `callback(frame, elapsed)` at most every `interval` seconds.
--- Registering an already registered callback only updates its interval.
---@param callback function
---@param interval number|nil Seconds between calls (0 or nil = every frame)
---@param owner string|nil Optional owner name, used by UnregisterAll()
function Events:RegisterOnUpdate(callback, interval, owner)
    if type(callback) ~= "function" then return end
    for i = 1, #onUpdateRegistry do
        local reg = onUpdateRegistry[i]
        if reg.cb == callback then
            reg.interval = interval or 0
            return
        end
    end
    SetOnUpdateList(CopyWith(onUpdateRegistry, { cb = callback, interval = interval or 0, timer = 0, owner = owner }))
end

---@param callback function
function Events:UnregisterOnUpdate(callback)
    SetOnUpdateList(CopyWithout(onUpdateRegistry, function(reg) return reg.cb == callback end))
end

-- ============================================================================
-- COMBAT QUEUE
-- ============================================================================
-- Actions that are blocked during combat (protected frames, CVars, ...) are queued
-- and executed once combat ends. Usage:
--     if WT.Core.CombatQueue:Add("MyTask", true, MyFunction, arg1, arg2) then return end
--     -- not in combat: continue and do the work right away
-- Queuing the same taskKey again replaces the previous entry.
WT.Core.CombatQueue = {}
local combatQueueTasks = {}

--- Queues `func(...)` if the player is in combat.
---@param taskKey string Unique name of the task; a newer entry replaces an older one
---@param isSilent boolean|nil true = do not print the "blocked in combat" warning
---@param func function
---@return boolean queued true if the task was queued, false if it is safe to run now
function WT.Core.CombatQueue:Add(taskKey, isSilent, func, ...)
    if not InCombatLockdown() then return false end

    combatQueueTasks[taskKey] = { fn = func, n = select("#", ...), args = { ... } }
    if not isSilent and WT.Utils and WT.Utils.Logger then
        WT.Utils.Logger:Warn(WT.L.MSG_COMBAT_BLOCK)
    end
    return true
end

local function RunCombatQueue()
    -- Combat may have started again within the delay; the tasks then wait for the next end of combat.
    if InCombatLockdown() or not next(combatQueueTasks) then return end

    local tasks = combatQueueTasks
    combatQueueTasks = {}
    for _, task in pairs(tasks) do
        xpcall(task.fn, ErrorHandler, unpack(task.args, 1, task.n))
    end
end

Events:Register("PLAYER_REGEN_ENABLED", function()
    -- Delay by one frame so the engine has completely lifted the combat lockdown
    if next(combatQueueTasks) then C_Timer.After(0, RunCombatQueue) end
end, "Core")
