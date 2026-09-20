-- Turning the room left under a posted limit into a number of crafts.
--
-- The limit, and the room left under it, are counted in ITEMS -- that is what
-- goes up for sale. Every queue in the addon is counted in CRAFTS. For most
-- recipes the two are the same number and the difference never shows, which is
-- exactly why it survived: Rough Sharpening Stone makes five per craft, and
-- clamping a craft count straight against the item room let a limit of ten
-- become fifty stones on the auction house.
--
-- The craft pane was fixed for this first. The Profit tab's Max button and its
-- quantity box had the same arithmetic and were missed, so the conversion now
-- lives in Logic/Profit.lua where both of them reach it and neither can drift
-- away from the other.
--
-- The rounding is deliberate and asymmetric: down, but never below one. Any
-- room at all should allow the smallest thing you can actually make, because
-- you cannot craft part of one and refusing outright would stall a queue on a
-- recipe that still has shelf space.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

ns.Util = { Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
            Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
            FormatMoney = function(c) return tostring(c) end,
            FormatAge = function() return "" end,
            HasFunction = function() return false end,
            GetItemLabel = function(i) return "item" .. tostring(i) end }

ns.Config = { Get = function() return nil end, GetPriceTable = function() return {} end }
ns.Scanner = { IsCommodity = function() return true end }
ns.Cost = { FindRecipeForItem = function() return nil end }

time = time or os.time

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)

local RoomInCrafts = ns.Profit.RoomInCrafts

local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(string.format("  %-58s %-8s %s", label, tostring(got), ok and "ok"
        or ("WRONG, wanted " .. tostring(expected))))
end

local ONE_EACH = { quantityMin = 1 }
local FIVE_EACH = { quantityMin = 5 }

--------------------------------------------------------------------------------
-- No limit, and no room
--------------------------------------------------------------------------------

print("\nwhen there is no limit, or none of it left")

-- nil is "no limit is set", which must stay distinguishable from "the limit is
-- full". One means do not clamp at all; the other means do not queue. The same
-- absence-is-not-a-negative distinction as the ownership flag in Data/Scanner.
check("no limit set means no clamp at all", RoomInCrafts(nil, FIVE_EACH), nil)
check("a full shelf leaves no crafts", RoomInCrafts(0, ONE_EACH), 0)
check("and a shelf past full does not go negative", RoomInCrafts(-3, ONE_EACH), 0)

--------------------------------------------------------------------------------
-- One item per craft: the case that always worked
--------------------------------------------------------------------------------

print("\nwhen a craft makes one item")

check("room passes straight through", RoomInCrafts(10, ONE_EACH), 10)
check("including a single space", RoomInCrafts(1, ONE_EACH), 1)

--------------------------------------------------------------------------------
-- Several items per craft: the bug
--------------------------------------------------------------------------------

print("\nwhen a craft makes several items")

-- The whole point. Ten items of room, five to a craft, is two crafts. Before
-- this it was read as ten crafts, which is fifty stones against a limit of ten.
check("ten items of room at five each is two crafts", RoomInCrafts(10, FIVE_EACH), 2)
check("and that is ten items, not fifty", RoomInCrafts(10, FIVE_EACH) * 5, 10)

check("odd room rounds down", RoomInCrafts(7, { quantityMin = 2 }), 3)
check("rather than overshooting the limit", RoomInCrafts(7, { quantityMin = 2 }) * 2, 6)

-- Overshooting by part of a craft is accepted on purpose, because the
-- alternative is a recipe that can never be queued while it still has room.
check("a part-craft of room still allows one", RoomInCrafts(4, FIVE_EACH), 1)
check("and one of exactly the wrong size too", RoomInCrafts(1, FIVE_EACH), 1)

--------------------------------------------------------------------------------
-- Recipes that do not say
--------------------------------------------------------------------------------

print("\nwhen the recipe does not say how many it makes")

check("a missing recipe is one per craft", RoomInCrafts(6, nil), 6)
check("so is a recipe with no quantity", RoomInCrafts(6, {}), 6)

-- A zero would divide the room away entirely, or divide by zero outright,
-- depending on how it was written. Guarded to one either way.
check("a zero yield does not swallow the room", RoomInCrafts(6, { quantityMin = 0 }), 6)

--------------------------------------------------------------------------------
-- What the panes actually do with it
--------------------------------------------------------------------------------

print("\nthe clamp the Max button performs")

-- Both the Max button and the quantity box in UI/Tab_Profit.lua run this
-- arithmetic, and so does UI/CraftPanel.lua. Written out here because the
-- numbers are the part worth reading: materials for twenty crafts, room for
-- ten items, five items a craft.
local function MaxButton(craftableNow, room, recipe)
    local most = math.max(1, craftableNow or 1)
    local allowed = RoomInCrafts(room, recipe)
    if allowed then most = math.max(1, math.min(most, allowed)) end
    return most
end

check("materials for 20, room for 10 items at 5 each", MaxButton(20, 10, FIVE_EACH), 2)
check("which lists 10 items, exactly the limit", MaxButton(20, 10, FIVE_EACH) * 5, 10)
check("materials are still the other ceiling", MaxButton(1, 100, ONE_EACH), 1)
check("no limit set leaves materials in charge", MaxButton(20, nil, FIVE_EACH), 20)
check("a full shelf still offers the smallest craft", MaxButton(20, 0, FIVE_EACH), 1)

print("")
if failures > 0 then
    error(string.format("%d craft-room check(s) failed", failures), 0)
end
print("PASS -- room under a posted limit is counted in crafts, not in items")
print("")
