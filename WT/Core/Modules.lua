local _, WT = ...

-- ============================================================================
-- MODULE SYSTEM
-- ============================================================================
-- Every feature module is created with WT:NewModule(name). There are no module
-- toggles: modules are always active, and every feature inside a module is opt-in
-- through its own settings. A module must change nothing while all of its options
-- are disabled, and turning an option off must restore the WoW default right away.
--
--   local Module = WT:NewModule("Coords")
--
--   function Module:IsSupported()          -- optional, e.g. a feature missing on WoW Forever
--       return WorldMapFrame ~= nil
--   end
--
--   function Module:OnEnable()             -- called once at PLAYER_LOGIN if supported
--       self:RegisterEvent("ZONE_CHANGED", function() self:Refresh() end)
--   end
--
--   function Module:BuildOptions(builder, panel) end   -- options page content
--
-- Events and OnUpdate callbacks registered through the module methods are owned by
-- the module (see WT.Core.Events:UnregisterAll).

local modules = {}       -- name -> module
local moduleOrder = {}   -- modules in load (TOC) order

local function ErrorHandler(err)
    geterrorhandler()(err)
    return err
end

local ModulePrototype = {}

function ModulePrototype:IsSupported()
    return true
end

--- Cached result of IsSupported(). Errors inside IsSupported() are reported and count as unsupported.
---@return boolean
function ModulePrototype:IsAvailable()
    if self.available == nil then
        local ok, supported = xpcall(self.IsSupported, ErrorHandler, self)
        self.available = (ok and supported) and true or false
    end
    return self.available
end

function ModulePrototype:RegisterEvent(event, callback)
    return WT.Core.Events:Register(event, callback, self.name)
end

function ModulePrototype:UnregisterEvent(event, callback)
    WT.Core.Events:Unregister(event, callback)
end

function ModulePrototype:RegisterOnUpdate(callback, interval)
    WT.Core.Events:RegisterOnUpdate(callback, interval, self.name)
end

function ModulePrototype:UnregisterOnUpdate(callback)
    WT.Core.Events:UnregisterOnUpdate(callback)
end

local moduleMeta = { __index = ModulePrototype }

--- Creates and registers a new module. The module is also reachable as WT.Modules[name].
---@param name string Unique module name
---@return table module
function WT:NewModule(name)
    if modules[name] then
        error("WT: module '" .. tostring(name) .. "' already exists", 2)
    end
    local module = setmetatable({ name = name }, moduleMeta)
    modules[name] = module
    moduleOrder[#moduleOrder + 1] = module
    WT.Modules[name] = module
    return module
end

---@param name string
---@return table|nil module
function WT:GetModule(name)
    return modules[name]
end

-- Enable all supported modules once the UI is loaded. Each module runs isolated:
-- an error in one module is reported but does not stop the others.
WT.Core.Events:Register("PLAYER_LOGIN", function()
    for _, module in ipairs(moduleOrder) do
        if module:IsAvailable() and type(module.OnEnable) == "function" then
            xpcall(module.OnEnable, ErrorHandler, module)
        end
    end
end, "Core")
