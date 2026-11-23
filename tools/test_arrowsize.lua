-- Arrow Size (the owner, 2026-10-26): the whole arrow can be drawn at 50%,
-- 75% or 100%. 100% is the default and saves nothing, so nobody's arrow
-- changes until a size is picked, and a new size keeps the arrow's spot.

local ns = {}
ns.L = setmetatable({}, { __index = function(_, key) return key end })
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.db = {}
assert(loadfile(lfs_cwd .. "/UI/WayArrow.lua"))("Blackthornes_TS", ns)
local ArrowUI, db = ns.WayArrowUI, ns.db

local failures = 0
local function check(label, ok)
    if not ok then
        failures = failures + 1
        print("  FAIL arrow size: " .. label)
    end
end

check("full size until one is picked", ArrowUI.Scale() == 1 and ArrowUI.Size() == 100)
ArrowUI:SetSize(75)
check("75% is kept", db.wayArrowSize == 75 and ArrowUI.Scale() == 0.75)
ArrowUI:SetSize(33)
check("a size not offered is ignored", db.wayArrowSize == 75)
db.wayArrowSize = "junk"
check("a bad save reads as full size", ArrowUI.Scale() == 1)
ArrowUI:SetSize(100)
check("100% saves nothing", db.wayArrowSize == nil)

-- The spot is kept in the screen's own units.
local placed
local frame = {
    ClearAllPoints = function() end,
    SetPoint = function(_, point, _, _, x, y) placed = { point = point, x = x, y = y } end,
    SetScale = function(self, scale) self.scale = scale end,
    GetCenter = function() return 200, 100 end,
}
ArrowUI.frame = frame
ArrowUI.AvoidXPBar = function() end
db.wayArrowX, db.wayArrowY = 400, 300
ArrowUI:SetSize(50)
check("drawn at half size", frame.scale == 0.5)
check("the spot stays on screen", placed and math.abs(placed.x - 800) < 0.01
    and math.abs(placed.y - 600) < 0.01)
check("the saved spot is untouched", db.wayArrowX == 400 and db.wayArrowY == 300)
ArrowUI:SavePosition()
check("a drag saves screen units", db.wayArrowX == 100 and db.wayArrowY == 50)
ArrowUI:SetSize(100)
check("back to full size", frame.scale == 1)

ArrowUI.frame, ArrowUI.AvoidXPBar = nil, nil
--------------------------------------------------------------------------------
-- Standing still, the dial is read about twice a second, not 33 times
-- (each read made new tables and words; memory climbed while idle in town)
--------------------------------------------------------------------------------

do
    local realDraw, realFrame, draws = ArrowUI.Draw, ArrowUI.frame, 0
    local realMoving, realFacing = rawget(_G, "IsPlayerMoving"), rawget(_G, "GetPlayerFacing")
    local moving, facing = false, 1.25
    _G.IsPlayerMoving = function() return moving end
    _G.GetPlayerFacing = function() return facing end
    ArrowUI.frame = { IsShown = function() return false end }
    ArrowUI.Draw = function() draws = draws + 1 end
    ArrowUI.since, ArrowUI.restFor, ArrowUI.settled = 0, 0, false
    for _ = 1, 100 do ArrowUI:Step(0.03) end
    check("standing still it looks about twice a second", draws >= 4 and draws <= 9, draws)
    draws = 0
    facing = 2.5
    ArrowUI:Step(0.03)
    check("turning shows at once", draws == 1, draws)
    draws, moving = 0, true
    for _ = 1, 10 do ArrowUI:Step(0.03) end
    check("walking keeps up every step", draws == 10, draws)
    draws, moving = 0, false
    ArrowUI.Draw = function(self) draws = draws + 1; self.drawnKey = tostring(draws) end
    for _ = 1, 10 do ArrowUI:Step(0.03) end
    check("words still changing keep up every step", draws == 10, draws)
    draws = 0
    _G.IsPlayerMoving = function() error("secret") end
    ArrowUI.Draw = function() draws = draws + 1 end
    for _ = 1, 10 do ArrowUI:Step(0.03) end
    check("a client that won't say keeps up every step", draws == 10, draws)
    _G.IsPlayerMoving, _G.GetPlayerFacing = realMoving, realFacing
    ArrowUI.Draw, ArrowUI.frame = realDraw, realFrame
    ArrowUI.settled, ArrowUI.drawnKey, ArrowUI.drawnFacing = nil, nil, nil
end


if failures > 0 then error(string.format("%d arrow size check(s) failed", failures)) end
print("  all arrow size checks passed")
print("")
