-- The slim strip inside the profession window (the owner said build it,
-- 2026-11-16): when the craft pane has no room beside the profession
-- window, or the one window has no room there at a size that can be read,
-- a strip with the next craft sits at the foot of the game's recipe pane.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Theme, ns.Widgets = {}, {}
ns.L = setmetatable({ Format = string.format }, { __index = function(_, key) return key end })
assert(loadfile(lfs_cwd .. "/UI/CraftStrip.lua"))("Blackthornes_TS", ns)
local Strip = ns.CraftStrip

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\nwhen the pane has no room")
check("folded under the character sheet", Strip.NoRoom("fold") == true)
check("past the sheet there is room", Strip.NoRoom("past", 1000, 0, 6, 350, 1920) == false)
check("drawn under a sheet it can't read stays as it was", Strip.NoRoom("under", 1000, 0, 6, 350, 1920) == false)
check("beside it with room", Strip.NoRoom("dock", 1000, 40, 6, 350, 1920) == false)
check("beside it past the screen's edge", Strip.NoRoom("dock", 1600, 0, 6, 350, 1920) == true)
check("the profession tabs count", Strip.NoRoom("dock", 1530, 40, 6, 350, 1920) == true)
check("just fits", Strip.NoRoom("dock", 1564, 0, 6, 350, 1920) == false)
check("unknown edges keep the pane", Strip.NoRoom("dock", nil, 0, 6, 350, 1920) == false)

print("\nroom for the one window")
check("fits on the right", Strip.Fits(100, 700, 600, 6, 1920) == true)
check("fits on the left", Strip.Fits(1200, 1800, 600, 6, 1920) == true)
check("fits on neither side", Strip.Fits(600, 1300, 650, 6, 1920) == false)
check("unknown edges count as room", Strip.Fits(nil, 1300, 650, 6, 1920) == true)

print("\nthe line")
check("the next craft and how many", Strip.LineText({ name = "Heavy Runecloth Bandage", count = 5 })
    == "Next: Heavy Runecloth Bandage x5")
check("an empty queue", Strip.LineText({ empty = true }) == "Nothing is queued")
check("nothing ready here", Strip.LineText({}) == "Nothing here can be made yet")

print("\nwhen it shows")
local NONE = {}
ns.Queue = { Count = function() return #NONE end }
check("an empty queue says so", Strip:State().empty == true)
NONE[1] = true
ns.CraftPanel = { GetNextReadyHere = function() return { recipeID = 7, quantity = 5 }, 0, 2 end }
ns.Recipes = { GetAny = function() return { name = "Heavy Runecloth Bandage" } end }
ns.Profit = { GetCraftableCount = function() return 3 end }
local state = Strip:State()
check("names the next craft", state.name == "Heavy Runecloth Bandage")
check("only as many as you can make", state.count == 3)
check("keeps the entry for the button", state.entry and state.entry.recipeID == 7)
ns.CraftPanel = { GetNextReadyHere = function() return nil, 1 end }
check("nothing ready here", Strip:State().entry == nil and not Strip:State().empty)

print(("\n%d checks passed"):format(checks))
