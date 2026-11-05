local _, WT = ...

-- ============================================================================
-- MAP COORDINATES
-- ============================================================================
-- Shows player and cursor coordinates below the world map (or in a movable box).
-- Opt-in: nothing is created until "Show Map Coordinates" is enabled, and turning
-- it off simply hides the box again. Blizzard's world map itself is never modified.

local Module = WT:NewModule("Coords")

local SafeNum = WT.Utils.Safety.SafeNum
local math_floor = math.floor
local string_format = string.format

local UPDATE_INTERVAL = 0.05
local POSITION_KEY = "WTMapCoords"

local coordsFrame          -- created on first use
local style = {}           -- color codes and labels, rebuilt by ApplyStyle()
local lastText, lastState  -- avoid rebuilding identical strings every tick

function Module:IsSupported()
    return WorldMapFrame ~= nil and WorldMapFrame.ScrollContainer ~= nil
        and C_Map ~= nil and C_Map.GetPlayerMapPosition ~= nil
end

local function ColorCode(c, r, g, b)
    if type(c) ~= "table" then c = {} end
    return string_format("|c%02x%02x%02x%02x", (c.a or 1) * 255, (c.r or r) * 255, (c.g or g) * 255, (c.b or b) * 255)
end

local function Label(text)
    text = tostring(text or "")
    return text ~= "" and (text .. " ") or ""
end

-- Returns the player position in percent, or nil where the game does not provide it (e.g. instances).
local function GetPlayerCoords(mapID)
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = SafeNum(pos.x), SafeNum(pos.y)
    if not x or not y then return nil end
    return x * 100, y * 100
end

-- Returns the cursor position on the map in percent, or nil if the cursor is not over the map.
local function GetCursorCoords()
    local container = WorldMapFrame.ScrollContainer
    if not (WorldMapFrame:IsMouseOver() or container:IsMouseOver()) then return nil end
    local x, y = container:GetNormalizedCursorPosition()
    x, y = SafeNum(x), SafeNum(y)
    if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x * 100, y * 100
end

local function FormatCoords(label, x, y)
    if not x then
        return string_format("%s%s|r%s%s|r", style.label, label, style.value, WT.L.LBL_NOT_AVAILABLE)
    end
    return string_format("%s%s|r%s%.1f, %.1f|r", style.label, label, style.value, x, y)
end

local function UpdateText(self, elapsed)
    self.timer = (self.timer or 0) + elapsed
    if self.timer < UPDATE_INTERVAL then return end
    self.timer = 0

    local mapID = SafeNum(WorldMapFrame:GetMapID())
    local px, py
    if mapID then px, py = GetPlayerCoords(mapID) end
    local cx, cy = GetCursorCoords()

    -- Cheap numeric comparison first, string formatting only when something changed
    local state = string_format("%d:%d:%d:%d", math_floor((px or -1) * 10), math_floor((py or -1) * 10),
        math_floor((cx or -1) * 10), math_floor((cy or -1) * 10))
    if state == lastState then return end
    lastState = state

    local text = FormatCoords(style.playerLabel, px, py)
    if cx then
        text = text .. style.separator .. FormatCoords(style.cursorLabel, cx, cy)
    end
    if text == lastText then return end
    lastText = text

    self.text:SetText(text)
    local width = self.text:GetStringWidth() + 20
    if not self.lastWidth or math.abs(self.lastWidth - width) > 2 then
        self:SetWidth(width)
        self.lastWidth = width
    end
end

local function UpdateVisibility()
    if not coordsFrame then return end
    coordsFrame:SetShown(WT.DB.Coords.ShowMapCoords and WorldMapFrame:IsShown())
end

local function SavePosition(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", _G["WT_UIContainer"], "BOTTOMLEFT", left, top)
    WT.DB.Internal.Positions = WT.DB.Internal.Positions or {}
    WT.DB.Internal.Positions[POSITION_KEY] = {
        point = "TOPLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", xOfs = left, yOfs = top,
    }
end

local function CreateCoordsFrame()
    local container = _G["WT_UIContainer"]
    local frame = CreateFrame("Frame", "WTMapCoords", container, "BackdropTemplate")
    frame.ignoreInLayout = true
    frame.ignoreFramePositionManager = true

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("LEFT", frame, "LEFT", 10, 0)
    frame.text:SetJustifyH("LEFT")

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if WT.DB.Coords.Movable and IsAltKeyDown() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    -- Runs only while the frame is shown, i.e. while the world map is open
    frame:SetScript("OnUpdate", UpdateText)

    WorldMapFrame:HookScript("OnShow", UpdateVisibility)
    WorldMapFrame:HookScript("OnHide", UpdateVisibility)
    return frame
end

local function ApplyStyle()
    local db = WT.DB.Coords

    style.label = ColorCode(db.TextColor, 1, 0.82, 0)
    style.value = ColorCode(db.ValueColor, 1, 1, 1)
    style.separator = ColorCode(db.SeparatorColor, 0.5, 0.5, 0.5) .. (db.Separator or " | ") .. "|r"
    style.playerLabel = Label(WT.L.MAP_COORDS_PLAYER)
    style.cursorLabel = Label(WT.L.MAP_COORDS_CURSOR)
    lastText, lastState = nil, nil

    local fontPath = (WT.Utils.SharedMedia and WT.Utils.SharedMedia:Fetch("font", db.Font)) or "Fonts\\FRIZQT__.TTF"
    local size = db.FontSize or 10
    local outline = (db.FontOutline == "NONE") and "" or (db.FontOutline or "OUTLINE")
    coordsFrame.text:SetFont(fontPath, size, outline)
    coordsFrame:SetHeight(size + 14)

    local bg = type(db.BgColor) == "table" and db.BgColor or {}
    local bc = type(db.BorderColor) == "table" and db.BorderColor or {}
    coordsFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    coordsFrame:SetBackdropColor(bg.r or WT.Colors.STD_BG_R, bg.g or WT.Colors.STD_BG_G, bg.b or WT.Colors.STD_BG_B, bg.a or WT.Colors.STD_BG_A)
    coordsFrame:SetBackdropBorderColor(bc.r or 1, bc.g or 1, bc.b or 1, bc.a or 1)

    local container = _G["WT_UIContainer"]
    coordsFrame:ClearAllPoints()
    if db.Movable then
        coordsFrame:SetFrameStrata(db.Strata or "DIALOG")
        coordsFrame:SetMovable(true)
        coordsFrame:EnableMouse(true)
        local pos = WT.DB.Internal.Positions and WT.DB.Internal.Positions[POSITION_KEY]
        if pos then
            coordsFrame:SetPoint(pos.point, container, pos.relativePoint, pos.xOfs, pos.yOfs)
        else
            coordsFrame:SetPoint("TOPLEFT", container, "TOP", -50, -50)
        end
    else
        coordsFrame:SetFrameStrata(WorldMapFrame:GetFrameStrata())
        coordsFrame:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 10)
        coordsFrame:SetMovable(false)
        coordsFrame:EnableMouse(false)
        coordsFrame:SetPoint("TOP", WorldMapFrame, "BOTTOM", 0, -2)
    end
end

--- Applies the current settings. Called on login and whenever an option changes.
function Module:Refresh()
    if not WT.DB.Coords.ShowMapCoords then
        UpdateVisibility()   -- hides the box if it already exists
        return
    end
    coordsFrame = coordsFrame or CreateCoordsFrame()
    ApplyStyle()
    UpdateVisibility()
end

function Module:OnEnable()
    self:Refresh()
end

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
    local function Refresh() self:Refresh() end

    panel:CreateTitle(builder, WT.L.GROUP_MAP_COORDS)
    AddDescription(WT.L.OPT_DESC_GROUP_MAP_COORDS)

    local showInit = panel:CreateCheckbox(builder, WT.L.OPT_COORDS_SHOW, WT.L.OPT_DESC_COORDS_SHOW, "Coords", "ShowMapCoords", Refresh)

    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BG, WT.L.OPT_DESC_COLOR_BG, "Coords", "BgColor", true, showInit, Refresh)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_BORDER, WT.L.OPT_DESC_COLOR_BORDER, "Coords", "BorderColor", true, showInit, Refresh)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_LABEL, WT.L.OPT_DESC_COLOR_LABEL, "Coords", "TextColor", true, showInit, Refresh)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_VALUE, WT.L.OPT_DESC_COLOR_VALUE, "Coords", "ValueColor", true, showInit, Refresh)

    panel:CreateCheckbox(builder, WT.L.OPT_COORDS_MOVABLE, WT.L.OPT_DESC_COORDS_MOVABLE, "Coords", "Movable", Refresh)
    panel:CreateStrataDropdown(builder, WT.L.OPT_STRATA, WT.L.OPT_DESC_STRATA, "Coords", "Strata", Refresh, showInit)

    if WT.Utils.SharedMedia then
        panel:CreateDropdown(builder, WT.L.OPT_FONT, WT.L.OPT_DESC_FONT, "Coords", "Font", WT.Utils.SharedMedia:GetOptions("font"), Refresh, showInit)
    end
    panel:CreateSlider(builder, WT.L.OPT_FONT_SIZE, WT.L.OPT_DESC_FONT_SIZE, "Coords", "FontSize", 8, 24, 1, Refresh, showInit)
    panel:CreateOutlineDropdown(builder, WT.L.OPT_FONT_OUTLINE, WT.L.OPT_DESC_FONT_OUTLINE, "Coords", "FontOutline", Refresh, showInit)
    local sepInit = panel:CreateEditBox(builder, WT.L.OPT_SEPARATOR, WT.L.OPT_DESC_SEPARATOR, "Coords", "Separator", nil, Refresh)
    panel:CreateColorPicker(builder, WT.L.OPT_COLOR_SEP, WT.L.OPT_DESC_COLOR_SEP, "Coords", "SeparatorColor", true, sepInit, Refresh)
end
