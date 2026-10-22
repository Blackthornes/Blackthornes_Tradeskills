-- Blackthornes -- UI/TravelMap.lua
-- The arrow's trip (Logic/Travel.lua) drawn on the world map: a gold line
-- over a dark one from where you stand through each stop to the place,
-- dotted while you fly, dashed on a boat or zeppelin, solid on foot, with a
-- dot at each stop. The owner said build it (2026-10-21) from the mockup.
--
-- Only the steps still ahead, only while the arrow is on a trip, only on
-- the map shown (a stop the map does not cover is left off). Its own frame
-- over the world map's canvas, just under the gathered-node markers; it
-- never touches a Blizzard frame and is never drawn in a fight. Drawn
-- again only when the map, the plan, the step or where you stand (by
-- MOVED yards) changes.
--
-- The same file in every addon whose arrow takes trips (a fix to it belongs
-- in all of them); the addon's own parts come through Travel.Host. The dot
-- is Media/Frame/TravelDot.tga in each (Farmer's tools/make_heat_art.py).

local addonName, ns = ...

local TravelMap = ns.NewModule("TravelMap")

-- The whole world's map, for a trip across the sea.
TravelMap.WORLD = 947

local DOT = "Interface\\AddOns\\" .. tostring(addonName) .. "\\Media\\Frame\\TravelDot.tga"

local GOLD = { 1, 0.82, 0.3, 0.95 }
local DARK = { 0, 0, 0, 0.7 }
-- Line widths as a share of the map's width.
local GOLD_WIDTH, DARK_WIDTH = 0.0028, 0.006
-- Dashes as a share of the map's width: { drawn, gap }.
TravelMap.DASHES = { fly = { 0.004, 0.006 }, boat = { 0.016, 0.01 }, zeppelin = { 0.016, 0.01 } }
-- Most line pieces drawn.
TravelMap.MAX_PIECES = 600
-- Yards you move before the line from you is drawn again.
TravelMap.MOVED = 20
-- Seconds between looks.
local LOOK = 0.5
-- Frame levels over the canvas: over the kill heat glow, under the nodes.
TravelMap.WORLD_ABOVE = 2

local function Map() return _G.C_Map end

local function Number(value) return ns.Travel.Number(value) end

local function InFight()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

--- A world point as a spot on `mapID` (0 to 1 each way), or nil when the
--- client will not say.
function TravelMap.Spot(mapID, continent, north, west)
    local map = Map()
    if not (map and mapID and continent and north and west) then return nil end
    if type(map.GetMapPosFromWorldPos) ~= "function" or type(CreateVector2D) ~= "function" then return nil end
    local ok, _, position = pcall(map.GetMapPosFromWorldPos, continent, CreateVector2D(north, west), mapID)
    if not ok or type(position) ~= "table" then return nil end
    local read, x, y = pcall(position.GetXY, position)
    x, y = read and Number(x), read and Number(y)
    if not (x and y) then return nil end
    -- Well off the map shown: not on it.
    if x < -0.05 or x > 1.05 or y < -0.05 or y > 1.05 then return nil end
    return x, y
end

--- The trip as lines: { { kind, from = {continent, north, west}, to = ... } },
--- from where you stand through every step still ahead. A Hearthstone has
--- no line; it starts the next one where it lands.
function TravelMap.Legs(plan, here)
    local legs = {}
    local at = here
    for _, step in ipairs(plan and plan.steps or {}) do
        if step.kind == "hearth" then
            at = step.to
        elseif step.kind == "walk" then
            legs[#legs + 1] = { kind = "walk", from = at, to = step.to }
            at = step.to
        else
            if at and step.from and at ~= step.from then
                legs[#legs + 1] = { kind = "walk", from = at, to = step.from, stop = true }
            end
            legs[#legs + 1] = { kind = step.kind, from = step.from, to = step.to, stop = true }
            at = step.to
        end
    end
    return legs
end

--- The pieces of one line: { x1, y1, x2, y2 } in map shares, broken into
--- dashes for a ride.
function TravelMap.Pieces(kind, x1, y1, x2, y2, aspect)
    local dash = TravelMap.DASHES[kind]
    if not dash then return { { x1, y1, x2, y2 } } end
    aspect = aspect or 1
    local dx, dy = x2 - x1, (y2 - y1) / aspect
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0 then return {} end
    local pieces = {}
    local along, period = 0, dash[1] + dash[2]
    while along < length and #pieces < TravelMap.MAX_PIECES do
        local stop = math.min(length, along + dash[1])
        local a, b = along / length, stop / length
        pieces[#pieces + 1] = { x1 + (x2 - x1) * a, y1 + (y2 - y1) * a, x1 + (x2 - x1) * b, y1 + (y2 - y1) * b }
        along = along + period
    end
    return pieces
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function TravelMap:Layer(canvas)
    local layer = self.layer
    if layer and layer.parent == canvas then return layer end
    if layer then self:Trim(0) layer.frame:Hide() end
    local frame = CreateFrame("Frame", nil, canvas)
    frame:SetAllPoints(canvas)
    frame:EnableMouse(false)
    layer = { frame = frame, parent = canvas, lines = {}, dots = {} }
    self.layer = layer
    return layer
end

local function Line(layer, index)
    local pair = layer.lines[index]
    if pair then return pair end
    if type(layer.frame.CreateLine) ~= "function" then return nil end
    local okDark, dark = pcall(layer.frame.CreateLine, layer.frame, nil, "OVERLAY", nil, 1)
    local okGold, gold = pcall(layer.frame.CreateLine, layer.frame, nil, "OVERLAY", nil, 2)
    if not (okDark and dark and okGold and gold) then return nil end
    dark:SetColorTexture(DARK[1], DARK[2], DARK[3], DARK[4])
    gold:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
    pair = { dark = dark, gold = gold }
    layer.lines[index] = pair
    return pair
end

local function Dot(layer, index)
    local dot = layer.dots[index]
    if not dot then
        dot = layer.frame:CreateTexture(nil, "OVERLAY", nil, 3)
        dot:SetTexture(DOT)
        dot:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
        layer.dots[index] = dot
    end
    return dot
end

--- Hides every line past `lines` and every dot past `dots`.
function TravelMap:Trim(lines, dots)
    local layer = self.layer
    if not layer then return end
    for index = (lines or 0) + 1, #layer.lines do
        layer.lines[index].dark:Hide()
        layer.lines[index].gold:Hide()
    end
    for index = (dots or 0) + 1, #layer.dots do layer.dots[index]:Hide() end
end

function TravelMap:Clear()
    self:Trim(0, 0)
    self.drawnKey = nil
end

--- The trip the dial is on, or nil.
function TravelMap.Trip()
    local state = ns.Travel.Host.State()
    return type(state) == "table" and state.trip or nil
end

--- The world map while it shows: { canvas, mapID, width, height }, or nil.
function TravelMap.WorldView()
    local map = _G.WorldMapFrame
    if type(map) ~= "table" then return nil end
    local okShown, shown = pcall(map.IsShown, map)
    if not (okShown and shown) then return nil end

    local canvas
    if type(map.GetCanvas) == "function" then
        local ok, value = pcall(map.GetCanvas, map)
        if ok then canvas = value end
    end
    canvas = canvas or (map.ScrollContainer and map.ScrollContainer.Child)
    if type(canvas) ~= "table" then return nil end

    local mapID
    if type(map.GetMapID) == "function" then
        local ok, value = pcall(map.GetMapID, map)
        if ok then mapID = Number(value) end
    end
    if not mapID then return nil end

    local okW, width = pcall(canvas.GetWidth, canvas)
    local okH, height = pcall(canvas.GetHeight, canvas)
    width, height = okW and Number(width) or nil, okH and Number(height) or nil
    if not (width and height and width > 0 and height > 0) then return nil end
    return { canvas = canvas, mapID = mapID, width = width, height = height }
end

--- The frame level over the map's art: the addon's own (Farmer's markers
--- share it), else the canvas's.
function TravelMap.BaseLevel(canvas)
    if ns.MapMarkers and type(ns.MapMarkers.BaseLevel) == "function" then
        local ok, level = pcall(ns.MapMarkers.BaseLevel, canvas)
        if ok and tonumber(level) then return level end
    end
    local ok, level = pcall(canvas.GetFrameLevel, canvas)
    return ok and tonumber(level) or 1
end

function TravelMap:Draw()
    local trip = TravelMap.Trip()
    if not trip or not trip.plan or InFight() then
        if not InFight() then self:Clear() end
        return
    end
    local view = TravelMap.WorldView()
    if not view then
        self:Clear()
        return
    end
    local here = ns.Travel.Host.Here()
    local plan = trip.plan
    local moved = TravelMap.MOVED
    local key = ("%d:%s:%s:%s:%d:%d:%s:%s"):format(view.mapID, view.width, view.height, plan.key or "",
        plan.done or 0, #plan.steps,
        here and here.north and math.floor(here.north / moved) or "-",
        here and here.west and math.floor(here.west / moved) or "-")
    if key == self.drawnKey then return end
    self.drawnKey = key

    local layer = self:Layer(view.canvas)
    pcall(layer.frame.SetFrameLevel, layer.frame, TravelMap.BaseLevel(view.canvas) + TravelMap.WORLD_ABOVE)
    layer.frame:Show()

    local width, height = view.width, view.height
    local aspect = height / width
    local lines, dots = 0, 0
    local function Place(continent, north, west)
        return TravelMap.Spot(view.mapID, continent, north, west)
    end
    local function AddDot(x, y, size)
        dots = dots + 1
        local dot = Dot(layer, dots)
        dot:SetSize(width * size, width * size)
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", layer.frame, "TOPLEFT", x * width, -y * height)
        dot:Show()
    end

    for _, leg in ipairs(TravelMap.Legs(plan, here)) do
        local from, to = leg.from, leg.to
        local x1, y1 = from and Place(from.continent, from.north, from.west)
        local x2, y2 = to and Place(to.continent, to.north, to.west)
        if x1 and x2 and from.continent == to.continent then
            for _, piece in ipairs(TravelMap.Pieces(leg.kind, x1, y1, x2, y2, aspect)) do
                if lines >= TravelMap.MAX_PIECES then break end
                local pair = Line(layer, lines + 1)
                if not pair then break end
                lines = lines + 1
                for _, line in ipairs({ pair.dark, pair.gold }) do
                    line:SetStartPoint("TOPLEFT", layer.frame, piece[1] * width, -piece[2] * height)
                    line:SetEndPoint("TOPLEFT", layer.frame, piece[3] * width, -piece[4] * height)
                    line:SetThickness(width * (line == pair.dark and DARK_WIDTH or GOLD_WIDTH))
                    line:Show()
                end
            end
        end
        if x2 and leg.stop then AddDot(x2, y2, 0.012) end
    end
    local place = plan.place
    local px, py = place and Place(place.continent, place.north, place.west)
    if px then AddDot(px, py, 0.02) end
    self:Trim(lines, dots)
end

function TravelMap:Step(elapsed)
    self.since = (self.since or 0) + (elapsed or 0)
    if self.since < LOOK then return end
    self.since = 0
    local ok, err = pcall(self.Draw, self)
    if not ok and ns.Debug then ns.Debug("travel map:", tostring(err)) end
end

function TravelMap:OnEnable()
    local driver = CreateFrame("Frame", nil, UIParent)
    driver:SetScript("OnUpdate", function(_, elapsed) TravelMap:Step(elapsed) end)
    driver:Show()
    self.driver = driver
end
