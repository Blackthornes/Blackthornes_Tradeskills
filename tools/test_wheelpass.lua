-- A drawer list and the wheel (2026-11-12): while the auction house wheel
-- is ours, a list under the mouse must let every turn through, a long one
-- too, or the turn scrolls when it should list or buy.

local ns = {}

local function Region()
    -- The catch-all below answers any missing field with a function, so the
    -- flags the list reads are set plainly here.
    local region = { shown = true, scripts = {}, height = 0, width = 0,
        wheelPass = false, wheelPassAlways = false }
    region.SetHeight = function(self, h) self.height = h end
    region.GetHeight = function(self) return self.height end
    region.SetSize = function(self, w, h) self.width, self.height = w, h end
    region.SetScript = function(self, name, fn) self.scripts[name] = fn end
    region.GetScript = function(self, name) return self.scripts[name] end
    region.CreateTexture = function() return Region() end
    region.CreateFontString = function() return Region() end
    region.GetMinMaxValues = function(self) return self.min or 0, self.max or 0 end
    region.SetMinMaxValues = function(self, lo, hi) self.min, self.max = lo, hi end
    region.GetValue = function(self) return self.value or 0 end
    region.SetValue = function(self, v) self.value = v end
    region.EnableMouseWheel = function(self, on) self.wheel = on end
    return setmetatable(region, { __index = function() return function() end end })
end

CreateFrame = function() return Region() end
UIParent = Region()

local function Load(path)
    local chunk = assert(loadfile(lfs_cwd .. path))
    chunk("Blackthornes_TS", ns)
end

Load("/UI/Theme.lua")
Load("/UI/Widgets.lua")

local function List(count)
    local list = ns.Widgets.CreateScrollList(Region(), { rowHeight = 20 })
    list:SetHeight(60)
    local data = {}
    for i = 1, count do data[i] = { id = i } end
    list:SetData(data)
    return list
end

local long, short = List(30), List(2)
assert(long.canScroll == true and short.canScroll == false, "one list scrolls, one does not")
assert(long.wheel == true and short.wheel == true, "both take the wheel to start")

-- The older ask: only a list with nothing more to show lets it through.
long:WheelPass(true)
short:WheelPass(true)
assert(long.wheel == true, "a long list keeps the wheel when not asked for always")
assert(short.wheel == false, "a short list lets it through")

-- Always: the long list lets it through too.
long:WheelPass(true, true)
short:WheelPass(true, true)
assert(long.wheel == false, "a long list lets every turn through when asked")
assert(short.wheel == false, "a short one still does")

-- New rows coming in never take the wheel back while it is passed.
local data = {}
for i = 1, 50 do data[i] = { id = i } end
short:SetData(data)
assert(short.canScroll == true and short.wheel == false, "grown long, it still lets the wheel through")

-- Given back, both scroll again.
long:WheelPass(false)
short:WheelPass(false)
assert(long.wheel == true and short.wheel == true, "the wheel scrolls again once given back")
assert(long.wheelPassAlways == false, "and always is forgotten")

print("test_wheelpass: all passed")
