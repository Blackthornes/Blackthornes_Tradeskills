-- One soulbound copy hides only itself on the Sell list.
--
-- The owner's report (2026-11-27): six Mageweave Reagent Bags he made were
-- in his bags, and none showed on Sell. One of them was soulbound. The list
-- read the first copy in the bags, the auction house said that copy can't be
-- sold, and the whole item dropped off. The free copies should show, count
-- without the bound one, and list from a free slot.

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
            isBound = entry.isBound and true or false,
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

-- The auction house refuses a soulbound copy and counts every copy of the
-- item as postable, as the client does when it can't tell them apart.
C_AuctionHouse = {
    IsSellItemValid = function(location)
        local entry = bags[location.bag] and bags[location.bag][location.slot]
        return entry ~= nil and not entry.isBound
    end,
    GetAvailablePostCount = function(location)
        local entry = bags[location.bag] and bags[location.bag][location.slot]
        return entry and ns.Inventory:GetBagCount(entry.itemID) or 0
    end,
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

local BAG, CLOTH = 254035, 4338

local function LineFor(lines, itemID)
    for _, line in ipairs(lines) do
        if line.itemID == itemID then return line end
    end
end

prices = { [BAG] = { market = 25999 }, [CLOTH] = { market = 40 } }
commodities = { [BAG] = false, [CLOTH] = true }
bags = {
    [0] = {
        { itemID = BAG, stackCount = 1, quality = 1, isBound = true },
        { itemID = CLOTH, stackCount = 20, quality = 1 },
    },
    [1] = {
        { itemID = BAG, stackCount = 1, quality = 1 },
        { itemID = BAG, stackCount = 1, quality = 1 },
        { itemID = BAG, stackCount = 1, quality = 1 },
    },
}

print("")
print("a soulbound copy hides only itself")

do
    local lines = Posting:GetPostable({ includeAll = true, showHeld = true, showNoted = true })
    local line = LineFor(lines, BAG)
    check("the free bags show on Sell", line ~= nil, true)
    check("the bound one is not counted", line and line.count, 3)
    check("it lists from a free copy, not the bound one", line and line.bag, 1)
    check("the cloth still shows", LineFor(lines, CLOTH) ~= nil, true)
end

do
    bags[1] = {}
    local lines = Posting:GetPostable({ includeAll = true, showHeld = true, showNoted = true })
    check("only the bound one left: it stays off", LineFor(lines, BAG), nil)
end

print("")

-- The suites share one Lua state: leave no auction house for the next one.
C_AuctionHouse = nil

if failures > 0 then
    error(("%d check(s) failed"):format(failures), 0)
end

print("PASS -- a soulbound copy hides only itself")
print("")
