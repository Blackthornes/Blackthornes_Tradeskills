-- Turning what a listing costs into what one of the thing costs.
--
-- The bug, seen in game 2026-09-19: Trent went to post crafted Linen Bags and
-- the sell list offered them at 1c each, while the auction house in front of
-- him showed the cheapest at 3s. The arithmetic gives it away -- 241 Linen
-- Bags were on offer across all listings, and 300 copper divided by 241 is 1.
--
-- Item auctions quote the price of a whole stack, so a unit price is a
-- division. The quantity this client handed back was not a stack count though:
-- it was the total available across every listing of the item. A Linen Bag
-- stacks to one, so 241 of them can never be one listing.
--
-- Which way to err matters. Dividing when we should not prices an item at a
-- copper and Trent loses the item; not dividing when we should prices it too
-- high and he loses a sale. The second is recoverable, so doubt means no
-- division.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

-- itemID -> the largest stack it can form. Absent means the client has not
-- cached the item, which is a real state and not the same as "stacks to one".
local maxStacks = {}

C_Item = {
    GetItemInfo = function(itemID)
        -- name, link, quality, iLevel, reqLevel, class, subclass, maxStack
        return "item" .. tostring(itemID), nil, 1, 1, 1, nil, nil, maxStacks[itemID]
    end,
}

CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize",
                            "RegisterEvent", "UnregisterEvent" }) do
        frame[name] = function() end
    end
    return frame
end

GetTime = function() return os.clock() end
time = time or os.time

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)

local Util = ns.Util

local UnitPriceFromStack = Util.UnitPriceFromStack

local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-54s %-8s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

local LINEN_BAG, CLOTH, UNCACHED = 4238, 2589, 99999
maxStacks = { [LINEN_BAG] = 1, [CLOTH] = 20 }

print("")
print("reading a stack size")

check("a cached item reports it",          Util.GetMaxStackSize(CLOTH), 20)
check("something that does not stack",     Util.GetMaxStackSize(LINEN_BAG), 1)
check("an uncached item reports nothing",  Util.GetMaxStackSize(UNCACHED), nil)
check("no item, no answer",                Util.GetMaxStackSize(nil), nil)

print("")
print("the bag that was offered for a copper")

-- The real numbers from the screenshot: one listing at 3s, 241 on offer.
check("241 of a thing that stacks to 1 is not a stack",
    UnitPriceFromStack(LINEN_BAG, 300, 241), 300)

-- What it used to do, for the record.
check("the old arithmetic is what gave 1c", math.floor(300 / 241), 1)

print("")
print("a genuine stack still divides")

check("20 cloth at 2s the stack is 10c each",
    UnitPriceFromStack(CLOTH, 200, 20), 10)
check("a partial stack divides too",
    UnitPriceFromStack(CLOTH, 150, 15), 10)
check("exactly the stack size is still a stack",
    UnitPriceFromStack(CLOTH, 400, 20), 20)

print("")
print("quantities that cannot be stack counts")

check("one of something is already a unit price",
    UnitPriceFromStack(CLOTH, 300, 1), 300)
check("no quantity at all",
    UnitPriceFromStack(CLOTH, 300, nil), 300)
check("a listing cheaper than the number in it",
    UnitPriceFromStack(CLOTH, 15, 20), 15)
check("more than the stack size, by one",
    UnitPriceFromStack(CLOTH, 2100, 21), 2100)

print("")
print("when the stack size is not known")

-- The old behaviour stands rather than silently changing every price during a
-- scan of items the client has not cached. /bts listings surfaces this case.
check("an uncached item still divides",
    UnitPriceFromStack(UNCACHED, 300, 20), 15)
check("and still refuses the impossible division",
    UnitPriceFromStack(UNCACHED, 15, 20), 15)

print("")

if failures > 0 then
    print(("FAIL -- %d check(s) failed"):format(failures))
    os.exit(1)
end

print("PASS -- a price is only divided by a number that could be a stack")
print("")
