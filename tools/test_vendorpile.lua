-- An item a vendor pays more for than the auction house would after its cut
-- is left off the Sell list and counted for the vendor, not shown as a loss.
-- A price the player typed this session still lists.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

--------------------------------------------------------------------------------
-- A player with bags
--------------------------------------------------------------------------------

-- bags[bag][slot] = { itemID, stackCount, isLocked }
local bags = {}
local commodities = {}
local prices = {}
local bindTypes = {}
local reserved = {}
local recipes = {}
local qualities = {}
local vendorPaid = {}

C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local entry = bags[bag] and bags[bag][slot]
        if not entry then return nil end
        return {
            itemID = entry.itemID,
            stackCount = entry.stackCount,
            isLocked = entry.isLocked and true or false,
            quality = entry.quality,
        }
    end,
}

-- The client's own item data, in the order C_Item.GetItemInfo returns it.
-- bindType is the fourteenth, which is the one under test here; the vendor
-- price is deliberately zero so no loss floor muddies these rows.
C_Item = {
    GetItemInfo = function(itemID)
        return ("item%d"):format(itemID),  -- name
            nil,                            -- link
            qualities[itemID] or 1,         -- quality
            1, 1, "Trade Goods", "Cloth",   -- ilvl, minLevel, type, subType
            20,                             -- maxStack
            "", "",                         -- equipLoc, texture
            0,                              -- sellPrice
            0, 0,                           -- classID, subclassID
            bindTypes[itemID] or 0          -- bindType
    end,
    RequestLoadItemDataByID = function() end,
}

ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot)
        return { bag = bag, slot = slot, IsValid = function() return true end }
    end,
}

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
ns.Config = {
    Get = function(_, k)
        if k == "undercutCopper" then return 1 end
        if k == "staleAfterSeconds" then return 48 * 3600 end
        if k == "postDuration" then return 2 end
        if k == "allowPostingAtALoss" then return false end
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
    GetCarriedBags = function() return { 0, 1, 2, 3, 4, 5 } end,

    -- Locked slots still hold stock: the count is what is there, and whether
    -- any of it can be listed right now is a separate question.
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

ns.Recipes = { GetAccountWide = function() return recipes end }

ns.Queue = {
    GetShoppingList = function()
        local list = {}
        for itemID in pairs(reserved) do list[#list + 1] = { itemID = itemID } end
        return list
    end,
}

ns.Vendor = { GetPaid = function(_, id) return vendorPaid[id] end }
ns.Cost = { FindRecipeForItem = function() return nil end }
ns.Cost.FindAnyRecipeForItem = ns.Cost.FindRecipeForItem

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Posting.lua"))("Blackthornes_TS", ns)

local Posting = ns.Posting

-- What a craft cost is not what this file is about, and the real Analyse wants
-- a whole recipe tree to answer. A flat figure keeps the crafted rows honest
-- without dragging costing into a test about which rows appear at all.
ns.Profit.Analyse = function(_, recipeID)
    return recipeID and { costPerUnit = 1 } or nil
end

--------------------------------------------------------------------------------

local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-52s %-8s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

local SCRAPS, LEATHER, TYPED = 2934, 2318, 2589

local function LineFor(lines, itemID)
    for _, line in ipairs(lines) do
        if line.itemID == itemID then return line end
    end
end

-- Scraps: 12c at auction is 11.4c after the cut, a vendor pays 15c.
-- Leather: 45c at auction, a vendor pays 10c. Typed: vendor pays more, but
-- the player set a price this session.
prices = { [SCRAPS] = { market = 13 }, [LEATHER] = { market = 46 }, [TYPED] = { market = 13 } }
commodities = { [SCRAPS] = true, [LEATHER] = true, [TYPED] = true }
vendorPaid = { [SCRAPS] = 15, [LEATHER] = 10, [TYPED] = 15 }
bags = {
    [0] = {
        { itemID = SCRAPS, stackCount = 13, quality = 1 },
        { itemID = LEATHER, stackCount = 9, quality = 1 },
        { itemID = TYPED, stackCount = 4, quality = 1 },
    },
}
Posting.chosenPrice = { [TYPED] = 20 }

print("")
print("what a vendor pays more for goes to the vendor")

do
    local lines, toVendor = Posting:GetPostable({ includeAll = true, showHeld = true })
    check("leather the auction house pays well for is offered", LineFor(lines, LEATHER) ~= nil, true)
    check("scraps a vendor pays more for are not", LineFor(lines, SCRAPS), nil)
    check("a price the player typed still lists", LineFor(lines, TYPED) ~= nil, true)
    check("and one is counted for the vendor", toVendor, 1)
    check("List all never picks the scraps",
        (Posting:GetNextPostable({ includeAll = true }, lines) or {}).itemID ~= SCRAPS, true)
end

do
    check("equal pay goes to the vendor", Posting.VendorPaysMore(1, 10, 10), true)
    check("no vendor price never does", Posting.VendorPaysMore(1, 10, nil), false)
    check("no auction price never does", Posting.VendorPaysMore(1, nil, 10), false)
end

-- A sale that beats the vendor by less than one deposit is not worth the
-- risk of the listing running out, so it goes to the vendor too.
do
    local Profit = ns.Profit
    local oldEach, oldLost = Profit.LostDepositEach, Profit.LostListings
    Profit.LostDepositEach = function() return 5 end
    Profit.LostListings = function() return 0 end
    -- 100 after the 5% cut is 95: 3 over a vendor's 92, under the 5 deposit
    check("a win under one deposit goes to the vendor", Posting.VendorPaysMore(1, 100, 92), true)
    check("a win over one deposit still lists", Posting.VendorPaysMore(1, 100, 80), false)
    -- one lost deposit already in the net is not taken off a second time
    Profit.LostListings = function() return 1 end
    check("a deposit is never counted twice", Posting.VendorPaysMore(1, 100, 89), false)
    check("and the counted one still counts", Posting.VendorPaysMore(1, 100, 90), true)
    -- the report's own numbers: 300c market, 227c vendor, a 1s deposit
    Profit.LostDepositEach = function() return 100 end
    Profit.LostListings = function() return 0 end
    check("Simple Britches: 300c is 185c after the cut and the risk",
        Profit:NetAfterRisk(1, 300), 185)
    check("so a 227c vendor pays more", Posting.VendorPaysMore(1, 300, 227), true)
    Profit.LostDepositEach, Profit.LostListings = oldEach, oldLost
end

-- A share each left from the old 1 silver floor (100c for 11, about 9c)
-- is not the item's deposit now. Counted, it sent a 12c stone to a 4c
-- vendor (a player's sell list, 2026-11-13).
do
    local Profit = ns.Profit
    local oldLost, oldDeposits = Profit.LostListings, ns.db.deposits
    Profit.LostListings = function() return 0 end
    local before = Posting.FLOOR_ENDED - 5000
    local duration = Posting:DurationFor(9100)
    ns.db.deposits = { [9100] = { unit = 100 / 11, quantity = 11, least = 100,
        leastQuantity = 11, leastAt = before, duration = duration, at = before } }
    check("a stale 1s floor share sends nothing to the vendor",
        Posting.VendorPaysMore(9100, 12, 4), false)
    ns.db.deposits[9100].leastAt, ns.db.deposits[9100].at = Posting.FLOOR_ENDED + 5, Posting.FLOOR_ENDED + 5
    check("the game's own 1s, seen since, still does",
        Posting.VendorPaysMore(9100, 12, 4), true)
    Profit.LostListings, ns.db.deposits = oldLost, oldDeposits
end

-- "Ignore Deposit:" (a player asked, 2026-11-14): ticked, no deposit is
-- counted, so profit and the vendor choice see only the auction house cut.
do
    local Profit = ns.Profit
    local oldGet, oldLost = ns.Config.Get, Profit.LostListings
    local ignore = false
    ns.Config.Get = function(self, k)
        if k == "ignoreDeposit" then return ignore end
        return oldGet(self, k)
    end
    Profit.LostListings = function() return 1 end
    check("off, a deposit is counted", Profit.LostDepositEach(1) > 0, true)
    ignore = true
    check("ticked, no deposit is counted", Profit.LostDepositEach(1), 0)
    check("ticked, a listing nets only the cut", Profit:NetFromListing(1, 300), 285)
    Profit.LostListings = function() return 0 end
    check("ticked, no risk is taken off either", Profit:NetAfterRisk(1, 300), 285)
    check("ticked, a 3c win over the vendor still lists", Posting.VendorPaysMore(1, 100, 92), false)
    ns.Config.Get, Profit.LostListings = oldGet, oldLost
end

print("")

if failures > 0 then
    error(("%d check(s) failed"):format(failures), 0)
end

print("PASS -- the vendor gets what it pays more for")
print("")
