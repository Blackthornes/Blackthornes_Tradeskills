-- Blackthornes Tradeskills -- Logic/WayArrow.lua
-- The arrow for Show the way (the owner asked 2026-10-22: Butler and
-- Tradeskills give the same guidance as the addons with an arrow). The
-- dial is Farmer's goal arrow, Equipment's quest arrow and Pets' beast
-- arrow brought over as a copy, not a call; only one Blackthornes arrow is
-- on screen at a time (UI/WayArrow.lua).
--
-- Show the way (a trainer or vendor: Learn next, Road to 300, the vendor
-- pins) aims it at a place: { name, zone, map, x,
-- y (0-1) }, kept per character in `wayArrowPlace` (never rename it). It
-- shows only while a place is set: the close gem, or opening the trainer
-- once you are there, puts it away. A place in another zone or across the
-- sea, with "Guide Me:" ticked, is led to step by step (Logic/Travel.lua),
-- and with TomTom installed and "Use TomTom:" ticked, TomTom's arrow shows
-- the way instead of the dial (Logic/TomTom.lua). Nothing here makes up a
-- coordinate.
--
-- Direction and distance come from the game's world coordinates
-- (C_Map.GetWorldPosFromMapPos), which run across a continent in yards.
-- Everything the client is asked is read only and inside a pcall; inside a
-- dungeon the arrow hides.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local WayArrow = ns.NewModule("WayArrow")

-- How close counts as there, in yards.
local ARRIVED = 15
WayArrow.ARRIVED = ARRIVED

-- How often the place is worked out again, seconds. The pointing and the
-- distance are redone every time the dial draws.
WayArrow.REFRESH = 2

local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local result = { pcall(fn, ...) }
    if not result[1] then return nil end
    return unpack(result, 2)
end

local function Plain(value)
    local ok, copy = pcall(function()
        if type(value) == "string" and value ~= "" then return value .. "" end
    end)
    return ok and copy or nil
end

local function Number(value)
    local ok, copy = pcall(function()
        local number = tonumber(value)
        if number and number == number then return number + 0 end
    end)
    return ok and copy or nil
end

local function Map() return type(_G.C_Map) == "table" and _G.C_Map or nil end

--------------------------------------------------------------------------------
-- What it points at
--------------------------------------------------------------------------------

--- The place the arrow follows, or nil.
function WayArrow:Place()
    local place = ns.charDb and ns.charDb.wayArrowPlace
    if type(place) ~= "table" or not (Number(place.map) and Number(place.x) and Number(place.y)) then return nil end
    return place
end

--- On while there is a place to follow.
function WayArrow.IsOn()
    return WayArrow:Place() ~= nil
end

--- Aim the arrow at a place: { name, zone, map, x, y (0-1) }. True when
--- it took it.
function WayArrow:Aim(place)
    if type(place) ~= "table" or not ns.charDb then return false end
    local map, x, y = Number(place.map or place.mapID), Number(place.x), Number(place.y)
    if not (map and x and y) then return false end
    ns.charDb.wayArrowPlace = { name = Plain(place.name), zone = Plain(place.zone), map = map, x = x, y = y }
    if ns.WayArrowUI and ns.WayArrowUI.Claim then ns.WayArrowUI:Claim() end
    self:Changed()
    return true
end

--- Aim the arrow at a trainer or vendor as Tradeskills keeps them: { zone
--- or mapID, x, y (0-100) }. True when it took it; false when the map for
--- the zone is not known here, so the caller pins it instead.
function WayArrow:AimAt(place, title)
    if type(place) ~= "table" then return false end
    local x, y = Number(place.x), Number(place.y)
    if not (x and y) then return false end
    local mapID = Number(place.mapID)
    if not mapID and ns.Waypoints and ns.Waypoints.MapFor then
        local ok, found = pcall(ns.Waypoints.MapFor, ns.Waypoints, place.zone)
        mapID = ok and Number(found) or nil
    end
    if not mapID then return false end
    return self:Aim({ name = title, zone = place.zone, map = mapID, x = x / 100, y = y / 100 })
end

--- Put the arrow away.
function WayArrow:Clear()
    if ns.charDb then ns.charDb.wayArrowPlace = nil end
    self:Changed()
end

--- Something the arrow shows changed: work it out again on the next draw.
function WayArrow:Changed()
    self.listedAt = nil
    if ns.WayArrowUI and ns.WayArrowUI.Refresh then ns.WayArrowUI:Refresh() end
end

--------------------------------------------------------------------------------
-- Where the player is
--------------------------------------------------------------------------------

--- A point on a map as world coordinates: continent, north, west (yards).
--- Nil when the client will not say.
function WayArrow.WorldPos(mapID, x, y)
    local map = Map()
    if not (map and mapID and x and y) then return nil end
    if type(map.GetWorldPosFromMapPos) ~= "function" or type(_G.CreateVector2D) ~= "function" then
        return nil
    end
    local ok, continent, position = pcall(map.GetWorldPosFromMapPos, mapID, _G.CreateVector2D(x, y))
    if not ok or type(position) ~= "table" then return nil end
    local read, north, west = pcall(position.GetXY, position)
    if not read then return nil end
    continent, north, west = Number(continent), Number(north), Number(west)
    if not (continent and north and west) then return nil end
    return continent, north, west
end

local mapSizes = {}

--- How big a map is, in yards: width, height. Nil when the client will not
--- say. Kept once read.
function WayArrow.MapSize(mapID)
    local kept = mapSizes[mapID]
    if kept then return kept[1], kept[2] end
    if kept == false then return nil end
    local map = Map()
    if not (map and mapID) then return nil end

    local width, height
    local ok, w, h = pcall(map.GetMapWorldSize, mapID)
    if ok then width, height = Number(w), Number(h) end

    if not (width and height and width > 0 and height > 0) then
        local _, ax, ay = WayArrow.WorldPos(mapID, 0, 0)
        local _, bx, by = WayArrow.WorldPos(mapID, 1, 1)
        if ax and ay and bx and by then
            width, height = math.abs(ay - by), math.abs(ax - bx)
        end
    end

    if width and height and width > 0 and height > 0 then
        mapSizes[mapID] = { width, height }
        return width, height
    end
    mapSizes[mapID] = false
    return nil
end

--- Which way the player faces, radians anticlockwise from north. Nil if
--- not read.
function WayArrow.Facing()
    return Number(Read(_G.GetPlayerFacing))
end

--- Where the player stands: { map, x, y (0-1), continent, north, west,
--- zone }, or nil when the client will not say.
function WayArrow:Here()
    local map = Map()
    if not map then return nil end
    local mapID = Number(Read(map.GetBestMapForUnit, "player"))
    if not mapID then return nil end
    local position = Read(map.GetPlayerMapPosition, mapID, "player")
    if position == nil then return nil end
    local ok, x, y = pcall(function()
        if type(position) == "table" and position.GetXY then
            local px, py = position:GetXY()
            return px + 0, py + 0
        end
        return position + 0, nil
    end)
    if not ok or not x or not y or (x == 0 and y == 0) then return nil end

    local here = { map = mapID, x = x, y = y }
    here.continent, here.north, here.west = WayArrow.WorldPos(mapID, x, y)
    here.zone = Plain(Read(_G.GetRealZoneText))
    return here
end

--- Inside a dungeon, raid or battleground: the game keeps the position to
--- itself there.
function WayArrow.Inside()
    local ok, inside = pcall(function()
        return type(_G.IsInInstance) == "function" and _G.IsInInstance() and true or false
    end)
    return ok and inside or false
end

--------------------------------------------------------------------------------
-- Measuring
--------------------------------------------------------------------------------

--- Yards north and west from `here` to a point `x`, `y` (0-1) on map
--- `mapID`, or nil when the two cannot be put on one grid. A target's world
--- position is read once and kept on it.
function WayArrow.Offset(here, mapID, x, y, target)
    if not (here and mapID and x and y) then return nil end

    if here.continent then
        local continent, north, west
        if target and target.world then
            continent, north, west = target.world[1], target.world[2], target.world[3]
        else
            continent, north, west = WayArrow.WorldPos(mapID, x, y)
            if target and continent then target.world = { continent, north, west } end
        end
        if continent and continent == here.continent then
            return north - here.north, west - here.west
        end
        if continent then return nil end
    end

    -- No world coordinates: only the map the player is on can be measured.
    if mapID ~= here.map then return nil end
    local width, height = WayArrow.MapSize(mapID)
    if not (width and height) then return nil end

    -- Map x runs east, map y runs south.
    return (here.y - y) * height, (here.x - x) * width
end

--- How far, in yards, and which way: radians anticlockwise from north.
function WayArrow.Measure(north, west)
    return math.sqrt(north * north + west * west), math.atan2(west, north)
end

--- Which way the arrow turns on screen: the bearing less the facing,
--- anticlockwise. North up without a facing.
function WayArrow.Turn(bearing, facing)
    local turn = bearing - (facing or 0)
    while turn > math.pi do turn = turn - 2 * math.pi end
    while turn < -math.pi do turn = turn + 2 * math.pi end
    return turn
end

--- Rounded yards: "8 yd", "140 yd", "1,250 yd".
function WayArrow.Yards(yards)
    local whole = math.floor(yards + 0.5)
    if whole >= 1000 then
        return L.Format("%d,%03d yd", math.floor(whole / 1000), whole % 1000)
    end
    if whole >= 100 then whole = math.floor(whole / 10 + 0.5) * 10 end
    return L.Format("%d yd", whole)
end

--------------------------------------------------------------------------------
-- The state
--------------------------------------------------------------------------------

--- The place as a target from `here`: { name, zone, map, mx, my, far }.
function WayArrow:Target(place, here)
    local target = { name = place.name, zone = place.zone, map = place.map, mx = place.x, my = place.y,
        x = place.x * 100, y = place.y * 100 }
    if not WayArrow.Offset(here, target.map, target.mx, target.my, target) then target.far = true end
    return target
end

--- Everything the dial needs for this moment:
---   { mode, name, target, turn, yards, distance, place, note, noteColor }
--- `mode` is "off", "inside", "blind" (no position), "point", "arrived",
--- "far" or "trip".
function WayArrow:State(clock)
    local place = self:Place()
    if not place then return { mode = "off" } end
    if WayArrow.Inside() then return { mode = "inside" } end

    local here = self:Here()
    local state = { name = place.name }

    clock = clock or 0
    if self.stamp ~= place or not self.listedAt or clock - self.listedAt >= WayArrow.REFRESH
        or clock < self.listedAt then
        self.target = self:Target(place, here)
        self.listedAt = clock
        self.stamp = place
    end

    if not here then
        state.mode = "blind"
        return state
    end

    local target = self.target
    state.target = target
    state.place = target.zone or ""
    state.note, state.noteColor = "", "muted"

    -- A place in another zone or on the other continent: the way there,
    -- step by step, the arrow on the next stop (Logic/Travel.lua).
    local trip = ns.Travel and ns.Travel:Use(target, here, clock)
    if trip then return self:TripState(state, trip, here) end

    local north, west = WayArrow.Offset(here, target.map, target.mx, target.my, target)
    if not north then
        state.mode = "far"
        state.distance = target.zone or L["Far away"]
        return state
    end

    local yards, bearing = WayArrow.Measure(north, west)
    local facing = WayArrow.Facing()
    state.yards, state.bearing = yards, bearing
    state.turn = WayArrow.Turn(bearing, facing)
    state.facing = facing ~= nil

    if yards <= ARRIVED then
        state.mode = "arrived"
        state.distance = L["You're there"]
        return state
    end

    state.mode = "point"
    state.distance = WayArrow.Yards(yards)
    return state
end

--- The dial's words and turn for a step of a trip.
function WayArrow:TripState(state, trip, here)
    state.trip = trip
    state.distance = L.Format("Step %d of %d", trip.index, trip.count)
    state.place = trip.line
    state.note, state.noteColor = trip.small, "muted"

    if trip.continent and trip.continent == here.continent and not trip.onTaxi then
        local yards, bearing = WayArrow.Measure(trip.north - here.north, trip.west - here.west)
        state.yards, state.bearing = yards, bearing
        local facing = WayArrow.Facing()
        state.turn = WayArrow.Turn(bearing, facing)
        state.facing = facing ~= nil
        state.mode = "point"
        local point = ns.Travel.MapPos(trip.continent, trip.north, trip.west)
        if point then point.mx, point.my = point.x, point.y end
        trip.point = point
        if not trip.atStop then
            local far = WayArrow.Yards(yards)
            state.note = state.note ~= "" and (state.note .. ", " .. far) or far
        end
        return state
    end
    state.mode = "trip"
    return state
end

--- Opening a trainer or vendor once you are there: the arrow's job is done.
function WayArrow:Reached()
    if not self:Place() then return end
    local state = self:State(Number(Read(_G.GetTime)) or 0)
    if state.mode == "arrived" then self:Clear() end
end

function WayArrow:OnEnable()
    ns.RegisterEvent(self, "TRAINER_SHOW", function() WayArrow:Reached() end)
    ns.RegisterEvent(self, "MERCHANT_SHOW", function() WayArrow:Reached() end)
end

--------------------------------------------------------------------------------
-- Checking what the client allows
--------------------------------------------------------------------------------

local function YesNo(ok)
    local colors = ns.COLORS
    return ("|c%s%s|r"):format(ok and colors.good or colors.warn, ok and "yes" or "no")
end

--- The arrow check: what the arrow can read here, line by line.
function WayArrow:Check()
    ns.Print("arrow check:")
    local here = self:Here()
    ns.PrintRaw(("  map position: %s%s"):format(YesNo(here),
        here and (" (map %d, %.1f, %.1f)"):format(here.map, here.x * 100, here.y * 100) or ""))
    local facing = WayArrow.Facing()
    ns.PrintRaw(("  facing: %s%s"):format(YesNo(facing), facing and (" (%.2f)"):format(facing) or ""))
    ns.PrintRaw(("  world position: %s"):format(YesNo(here and here.continent)))
    ns.PrintRaw(("  in an instance: %s"):format(WayArrow.Inside() and "yes, so the arrow hides" or "no"))
    if ns.TomTom then ns.PrintRaw(ns.TomTom.CheckLine()) end
    if ns.Travel then
        local count = 0
        for _ in pairs(ns.Travel:AllFlights()) do count = count + 1 end
        ns.PrintRaw(("  way there: %s, %d flight paths known"):format(ns.Travel.IsOn() and "on" or "off", count))
    end
    local place = self:Place()
    ns.PrintRaw(("  following: %s"):format(place and (place.name or "?") or "nothing"))
end

--------------------------------------------------------------------------------
-- What Logic/Travel.lua (the same file in every addon) asks of Tradeskills
--------------------------------------------------------------------------------

ns.TravelHost = {
    Here = function() return WayArrow:Here() end,
    InInstance = function() return WayArrow.Inside() end,
    Key = function(target)
        return ("%s|%s|%s|%s"):format(tostring(target.zone), tostring(target.name), tostring(target.x), tostring(target.y))
    end,
    Changed = function() WayArrow:Changed() end,
    Refresh = function() if ns.WayArrowUI and ns.WayArrowUI.Refresh then ns.WayArrowUI:Refresh() end end,
    State = function() return ns.WayArrowUI and ns.WayArrowUI.state end,
    Print = function(text) ns.Print(text) end,
}
