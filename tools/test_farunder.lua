-- A price far under the usual one asks rather than refuses.
--
-- The owner, 2026-10-31: Peacebloom sat on Ready to sell and List Next said
-- "nothing in your bags worth listing". Its usual price (a running average
-- of scans) was more than five times today's cheapest, so the fifth-of-market
-- guard held it back without a word. Now the row says so, and its own List
-- asks first, then lists it. List Next still passes it over, and the vendor
-- floor still refuses.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

--------------------------------------------------------------------------------
-- A player with bags
--------------------------------------------------------------------------------

-- bags[bag][slot] = { itemID, stackCount }
local bags = {}
local commodities = {}
local prices = {}

C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local entry = bags[bag] and bags[bag][slot]
        if not entry then return nil end
        return { itemID = entry.itemID, stackCount = entry.stackCount, isLocked = false }
    end,
}

-- MakeLocation only needs something that answers IsValid.
ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot)
        return { bag = bag, slot = slot, IsValid = function() return true end }
    end,
}

ns.Util = {
    Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    FormatMoney = function(c) return tostring(c) end,
    FormatAge = function() return "" end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
    -- Nothing from C_AuctionHouse: the postable count then comes from the bags
    -- and the deposit is unknown, which is the away-from-the-auction-house case
    -- and the one that keeps this test about quantities.
    HasFunction = function() return false end,
}

-- Core/Util.lua builds a worker frame at load time. Nothing here drives it.
CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize" }) do
        frame[name] = function() end
    end
    return frame
end

GetTime = function() return os.clock() end
time = time or os.time

ns.db = {}
postAnyway = nil
ns.Config = {
    Get = function(_, k)
        if k == "undercutCopper" then return 1 end
        if k == "staleAfterSeconds" then return 48 * 3600 end
        if k == "postDuration" then return 2 end
        if k == "postAnyway" then return postAnyway end
        return nil
    end,
    GetPriceTable = function() return {} end,
}

ns.Scanner = {
    isAuctionHouseOpen = false,
    IsCommodity = function(_, itemID) return commodities[itemID] == true end,
}

ns.Prices = {
    GetValue = function(_, itemID, key)
        local entry = prices[itemID]
        return entry and entry[key] or nil
    end,
}

ns.Inventory = {
    -- The containers the character carries, reagent bag last. Posting walks
    -- whatever this returns rather than keeping a range of its own, which is
    -- how a reagent bag came to be invisible to the sell list.
    GetCarriedBags = function() return { 0, 1, 2, 3, 4, 5 } end,

    GetBagCount = function(_, itemID)
        local total = 0
        for _, slots in pairs(bags) do
            for _, entry in ipairs(slots) do
                if entry.itemID == itemID then total = total + entry.stackCount end
            end
        end
        return total
    end,
}

ns.Recipes = { GetAccountWide = function() return {} end }
ns.Queue = { GetShoppingList = function() return {} end }

-- Nothing here is craftable, so the profit side stays out of the way and the
-- prices are whatever the price table says.
ns.Cost = { FindRecipeForItem = function() return nil end }
ns.Cost.FindAnyRecipeForItem = ns.Cost.FindRecipeForItem

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Posting.lua"))("Blackthornes_TS", ns)

local Posting = ns.Posting

local vendor = {}
ns.Util.GetVendorSellPrice = function(itemID) return vendor[itemID] end
ns.Prices.Get = function() return nil end

local failures = 0
local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-56s %-10s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

local HERB = 2447
prices = { [HERB] = { market = 94000 } }   -- usual about 9g 40s
vendor = { [HERB] = 500 }

print("")
print("which prices are far under")

check("1g 84s against a usual 9g 40s is far under", Posting:FarUnderUsual(HERB, 18400), true)
check("2g is not", Posting:FarUnderUsual(HERB, 20000), false)
check("under what a vendor pays still refuses", Posting:FarUnderUsual(HERB, 400), false)
check("a price typed by hand was never held", Posting:FarUnderUsual(HERB, 18400, true), false)
check("the floor says which it is", select(3, Posting:GetPriceFloor(HERB)), "market")

print("")
print("its List button asks, then lists")

local shown, posted
Posting.ShowConfirm = function(_, itemID, quantity, price, text, byHand)
    shown = { itemID = itemID, quantity = quantity, price = price, text = text, byHand = byHand }
end
Posting.Post = function(_, itemID, quantity, price, byHand)
    posted = { itemID = itemID, quantity = quantity, price = price, byHand = byHand }
    return true
end
Posting.CanPost = function() return true end
Posting.CanListOnClick = function() return true end
Posting.GetPostPrice = function() return 18400 end
ns.Scanner.isAuctionHouseOpen = true

check("the click is taken", Posting:Request(HERB, 4, 18400), true)
check("nothing is listed yet", posted, nil)
check("a box asks first", shown ~= nil, true)
check("for the same price", shown and shown.price, 18400)
check("and the same count", shown and shown.quantity, 4)
check("saying why", shown and shown.text:find("far under what it usually sells for", 1, true) ~= nil, true)
check("Yes lists it past the guard", shown and shown.byHand, true)

-- What Yes does: the popup's OnAccept posts with the guard stood aside.
Posting:Post(shown.itemID, shown.quantity, shown.price, shown.byHand)
check("then it lists", posted and posted.price, 18400)

shown, posted = nil, nil
Posting.GetPostPrice = function() return 30000 end
Posting:Request(HERB, 4, 30000)
check("an ordinary price lists without the box", posted and posted.price, 30000)
check("and no box", shown, nil)

print("")
print("with Bypass Disallowed Postings ticked")

postAnyway = true
check("nothing is far under", Posting:FarUnderUsual(HERB, 18400), false)
shown, posted = nil, nil
Posting.GetPostPrice = function() return 18400 end
Posting:Request(HERB, 4, 18400)
check("it lists without asking", posted and posted.price, 18400)
check("and no box", shown, nil)
postAnyway = nil
check("unticked again, it asks again", Posting:FarUnderUsual(HERB, 18400), true)

print("")
if failures > 0 then
    error(("%d far-under check(s) failed"):format(failures), 0)
end
print("PASS -- a price far under the usual one asks first")
print("")
