-- Things about the one window (UI/SharedWindow.lua) that must hold for any
-- input, tried with many random ones. The same test in all five addons.
--
-- A property test states something that can never be false and throws
-- hundreds of made-up inputs at it, so it finds the odd cases nobody thought
-- to write down. The seed is fixed so a failure comes back the same each run;
-- the failing input is printed.
--
-- What must hold:
--   1. A small window's spot comes back where it was dropped, at any UI
--      scale: saved as screen pixels, laid again at the same place.
--   2. Saving a spot twice keeps the same spot (nothing creeps).
--   3. The window's size setting always lands between SCALE_MIN and
--      SCALE_MAX, whatever is in the save, and clamping twice changes nothing.

local NAMES = { "CreateFrame", "UIParent", "C_Timer", "hooksecurefunc", "BlackthornesWindow",
    "UISpecialFrames", "InCombatLockdown" }
local saved = {}
for _, name in ipairs(NAMES) do saved[name] = _G[name] end

local function Object()
    local o = { shown = false, scripts = {}, hooks = {}, left = 0, top = 0, effective = 1 }
    function o:Show() self.shown = true end
    function o:Hide() self.shown = false end
    function o:IsShown() return self.shown end
    function o:SetScript(name, fn) self.scripts[name] = fn end
    function o:HookScript(name, fn)
        self.hooks[name] = self.hooks[name] or {}
        table.insert(self.hooks[name], fn)
    end
    function o:Fire(name)
        for _, fn in ipairs(self.hooks[name] or {}) do fn(self) end
    end
    function o:GetLeft() return self.left end
    function o:GetTop() return self.top end
    function o:GetEffectiveScale() return self.effective end
    function o:ClearAllPoints() self.point = nil end
    function o:SetPoint(...) self.point = { ... } end
    function o:GetPoint() if self.point then return unpack(self.point) end end
    function o:StopMovingOrSizing() end
    return setmetatable(o, { __index = function() return function() end end })
end

CreateFrame = function() return Object() end
UIParent = Object()
C_Timer = nil
UISpecialFrames = {}
BlackthornesWindow = nil
InCombatLockdown = function() return false end
hooksecurefunc = function(t, name, fn)
    local old = t[name]
    t[name] = function(...) old(...) fn(...) end
end

local ns = {
    Theme = {
        Unpack = function() return 0, 0, 0, 1 end,
        Fill = function() end,
        Border = function() end,
        CreateLabel = function() return Object() end,
    },
}
local chunk = assert(loadfile(lfs_cwd .. "/UI/SharedWindow.lua"))
chunk("Blackthornes_Properties", ns)
local SW = ns.SharedWindow
assert(SW, "SharedWindow loads")

local db = {}
SW:Join({ key = "props", order = 1, name = "props", icon = "icon",
    db = function() return db end, open = function() end, settings = function() end })

math.randomseed(20261116)
local TRIES = 300
local checks = 0

local function Near(a, b) return math.abs(a - b) < 1e-6 * math.max(1, math.abs(a), math.abs(b)) end

-- 1 and 2. A spot comes back where it was dropped, at any scale.
for i = 1, TRIES do
    local key = "props.window" .. i
    local frame = Object()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    SW.KeepSpot(frame, key)
    local scale = 0.4 + math.random() * 1.6
    local left = math.random() * 3000
    local top = math.random() * 2000
    frame.effective = scale
    frame.left, frame.top = left, top
    frame:StopMovingOrSizing()
    local spot = db.windowSpots and db.windowSpots[key]
    assert(spot, ("try %d: the drop is saved"):format(i))
    frame:StopMovingOrSizing()
    local again = db.windowSpots[key]
    assert(Near(again.x, spot.x) and Near(again.y, spot.y),
        ("try %d: saved twice, the spot creeps (%s, %s)"):format(i, left, top))
    frame:ClearAllPoints()
    frame:Show()
    frame:Fire("OnShow")
    local p = frame.point
    assert(p and p[1] == "TOPLEFT", ("try %d: laid again by its top left"):format(i))
    assert(Near(p[4], left) and Near(p[5], top),
        ("try %d: scale %.3f, dropped at %.2f, %.2f, came back at %.2f, %.2f"):format(
            i, scale, left, top, p[4], p[5]))
    checks = checks + 3
end

-- 3. The size setting stays in range, whatever is saved.
-- Not a number (0/0) is here since this test found Clamp let it through
-- (2026-11-17, fixed in FILE_VERSION 12).
local odd = { nil, "", "abc", -1e9, 1e9, 0, -0.5, 0 / 0, math.huge, -math.huge, true, {} }
for i = 1, TRIES do odd[#odd + 1] = (math.random() - 0.5) * 1000 end
for i = 1, #odd + 1 do
    local value = odd[i]
    local ok, once = pcall(SW.Clamp, value)
    assert(ok, ("Clamp(%s) raises: %s"):format(tostring(value), tostring(once)))
    assert(type(once) == "number" and once == once, ("Clamp(%s) is a number"):format(tostring(value)))
    assert(once >= SW.SCALE_MIN and once <= SW.SCALE_MAX,
        ("Clamp(%s) gave %s, outside %s to %s"):format(tostring(value), tostring(once), SW.SCALE_MIN, SW.SCALE_MAX))
    assert(SW.Clamp(once) == once, ("Clamp twice changes %s"):format(tostring(once)))
    checks = checks + 3
end

for _, name in ipairs(NAMES) do _G[name] = saved[name] end
print(("  properties_window: %d checks passed"):format(checks))
