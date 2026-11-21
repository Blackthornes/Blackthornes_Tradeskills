-- The trip line on the world map (UI/TravelMap.lua, the same file in all
-- five addons, and so is this test). Found 2026-11-20:
-- `local x, y = from and Place(...)` keeps only the first value, so y was
-- always nil, Draw raised inside its pcall and the line and dots never
-- showed.
--
-- The file is loaded by itself with a small world of its own, so the test
-- runs the same in every addon.
--
-- What must hold:
--   1. Draw runs without an error for a trip with a leg, a stop and a place.
--   2. The leg gets a line, from and to the spots the map gave.
--   3. The stop and the place each get a dot.
--   4. A leg with no start, and a plan with no place, raise nothing.

-- Tests share one Lua state: every global set here is put back at the end.
local GLOBALS = { "CreateFrame", "UIParent", "InCombatLockdown", "WorldMapFrame", "C_Map", "CreateVector2D" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local failures = 0
local function check(label, ok, detail)
    if ok then return end
    failures = failures + 1
    print(("  FAIL %s%s"):format(label, detail and ("  -> " .. tostring(detail)) or ""))
end

-- A frame, texture or line that takes any call and remembers a few.
local function Piece()
    local piece = { shown = true }
    function piece:Show() self.shown = true end
    function piece:Hide() self.shown = false end
    function piece:IsShown() return self.shown end
    function piece:SetStartPoint(_, _, x, y) self.startX, self.startY = x, y end
    function piece:SetEndPoint(_, _, x, y) self.endX, self.endY = x, y end
    function piece:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
    function piece:GetFrameLevel() return 1 end
    function piece:GetWidth() return 1000 end
    function piece:GetHeight() return 600 end
    function piece:IsShown() return self.shown end
    function piece:GetCanvas() return self.canvas end
    function piece:GetMapID() return 1 end
    function piece:CreateTexture() return Piece() end
    function piece:CreateLine() return Piece() end
    return setmetatable(piece, { __index = function() return function() end end })
end

CreateFrame = function() return Piece() end
UIParent = Piece()
InCombatLockdown = function() return false end
WorldMapFrame = Piece()
WorldMapFrame.canvas = Piece()
-- The map's answer: x and y as shares of the map, a hundredth of the yards.
CreateVector2D = function(north, west) return { north = north, west = west } end
C_Map = {
    GetMapPosFromWorldPos = function(_, point)
        return 1, { GetXY = function() return point.west / 100, point.north / 100 end }
    end,
}

local plan = { key = "test", done = 0, steps = {}, place = { continent = 1, north = 30, west = 60 } }
local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.Debug = function() end
ns.Travel = {
    Number = function(value) return type(value) == "number" and value or nil end,
    Host = {
        Here = function() return { continent = 1, north = 10, west = 10 } end,
        State = function() return { trip = { plan = plan } } end,
    },
}

local chunk = assert(loadfile(lfs_cwd .. "/UI/TravelMap.lua"))
chunk("Blackthornes_Test", ns)
local TravelMap = ns.TravelMap

local legs = {
    { kind = "walk", from = { continent = 1, north = 10, west = 20 },
        to = { continent = 1, north = 40, west = 50 }, stop = true },
}
TravelMap.Legs = function() return legs end

local function Shown(list, key)
    local count = 0
    for _, item in ipairs(list or {}) do
        if (key and item[key] or item):IsShown() then count = count + 1 end
    end
    return count
end

local ok, err = pcall(TravelMap.Draw, TravelMap)
check("the trip draws without an error", ok, err)
local layer = TravelMap.layer or { lines = {}, dots = {} }
check("the leg gets a line", Shown(layer.lines, "gold") == 1, Shown(layer.lines, "gold"))
local gold = layer.lines[1] and layer.lines[1].gold or {}
check("the line starts where the leg starts", gold.startX == 200 and gold.startY == -60,
    tostring(gold.startX) .. "," .. tostring(gold.startY))
check("and ends where it ends", gold.endX == 500 and gold.endY == -240,
    tostring(gold.endX) .. "," .. tostring(gold.endY))
check("the stop and the place each get a dot", Shown(layer.dots) == 2, Shown(layer.dots))
local dot = layer.dots[2] or {}
check("the place's dot sits on the place", dot.x == 600 and dot.y == -180, tostring(dot.x) .. "," .. tostring(dot.y))

-- A leg that starts nowhere known: no line, no error, the dots stay.
legs[1].from = nil
plan.key = "test2"
ok, err = pcall(TravelMap.Draw, TravelMap)
check("a leg with no start raises nothing", ok, err)
check("and draws no line", Shown(layer.lines, "gold") == 0, Shown(layer.lines, "gold"))
check("its stop and the place still get dots", Shown(layer.dots) == 2, Shown(layer.dots))

-- No place on the plan: only the stop's dot.
plan.place = nil
plan.key = "test3"
ok, err = pcall(TravelMap.Draw, TravelMap)
check("a plan with no place raises nothing", ok, err)
check("only the stop's dot is left", Shown(layer.dots) == 1, Shown(layer.dots))

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

if failures > 0 then error(string.format("%d travel map check(s) failed", failures)) end
print("  travelmap: all checks passed")
