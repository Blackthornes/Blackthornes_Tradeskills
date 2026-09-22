-- Selling what is in the bags, not only what the recipes make.
--
-- The Post tab used to show crafted output alone. Everything else a player
-- holds -- a drop, a gathered stack, something bought to resell -- was simply
-- absent, with nothing on screen to say why. This is the rule that replaced
-- that, and the three things it must not break while doing it:
--
--   * a reagent a queued craft is waiting on is still held back, because
--     listing those costs real work to undo;
--   * an item with no price still never reaches anything that picks something
--     to list on the player's behalf -- it is shown, and only shown;
--   * an item sitting in a locked slot cannot be listed from, so it is not
--     offered as though it could.

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

C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local entry = bags[bag] and bags[bag][slot]
        if not entry then return nil end
        return {
            itemID = entry.itemID,
            stackCount = entry.stackCount,
            isLocked = entry.isLocked and true or false,
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
            1,                              -- quality
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

ns.Cost = { FindRecipeForItem = function() return nil end }

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

local CRAFTED, BOUGHT, UNPRICED = 2589, 7955, 2770
local NEEDED, SOULBOUND, LOCKED = 3466, 6948, 4306

--- The whole bag, as the Post tab asks for it.
local function Everything()
    return Posting:GetPostable({ includeAll = true, includeUnpriced = true })
end

local function LineFor(lines, itemID)
    for _, line in ipairs(lines) do
        if line.itemID == itemID then return line end
    end
end

local function Reset()
    Posting.chosenQuantity = {}

    commodities = { [CRAFTED] = true, [UNPRICED] = true, [NEEDED] = true }
    bindTypes = { [SOULBOUND] = 1 }
    reserved = { [NEEDED] = true }
    recipes = { [11] = { recipeID = 11, outputItemID = CRAFTED } }

    prices = {
        [CRAFTED]   = { market = 40 },
        [BOUGHT]    = { market = 5000 },
        [NEEDED]    = { market = 70 },
        [SOULBOUND] = { market = 900 },
        [LOCKED]    = { market = 300 },
        -- UNPRICED deliberately absent: nothing has ever seen one sell.
    }

    bags = {
        [0] = {
            { itemID = CRAFTED,   stackCount = 20 },
            { itemID = BOUGHT,    stackCount = 1 },
            { itemID = UNPRICED,  stackCount = 12 },
            { itemID = NEEDED,    stackCount = 5 },
            { itemID = SOULBOUND, stackCount = 1 },
            { itemID = LOCKED,    stackCount = 8, isLocked = true },
        },
    }
end

print("")
print("what the crafted-only view shows")

Reset()

do
    local lines = Posting:GetPostable()

    check("what a recipe makes is offered",       LineFor(lines, CRAFTED) ~= nil, true)
    check("and is marked as crafted",             LineFor(lines, CRAFTED).isCrafted, true)
    check("bag stock is not",                     LineFor(lines, BOUGHT), nil)
    check("nor is anything unpriced",             LineFor(lines, UNPRICED), nil)
end

print("")
print("what the whole-bag view shows")

Reset()

do
    local lines = Everything()

    check("what a recipe makes is still there",   LineFor(lines, CRAFTED) ~= nil, true)
    check("and so is a thing simply bought",      LineFor(lines, BOUGHT) ~= nil, true)
    check("which is not marked as crafted",       LineFor(lines, BOUGHT).isCrafted, false)
    check("it carries its price",                 LineFor(lines, BOUGHT).unitPrice, 5000)
end

print("")
print("an item nothing has ever priced")

Reset()

do
    -- Shown, and shown as unpriced. Before this it was absent, which on a
    -- client that prints no errors is indistinguishable from a bug.
    local line = LineFor(Everything(), UNPRICED)

    check("it is on the list",                    line ~= nil, true)
    check("with no price on it",                  line and line.unitPrice, nil)
    check("nothing is invented for its value",    line and line.total, nil)
    check("but the count is real",                line and line.count, 12)
    check("and it cannot be at a loss",           line and line.atALoss, false)
end

do
    -- includeAll on its own is what Post ALL and its summary ask for, and
    -- those pick something to list without anyone looking at a row first.
    local lines = Posting:GetPostable({ includeAll = true })
    check("asking without includeUnpriced skips it", LineFor(lines, UNPRICED), nil)
end

print("")
print("nothing chooses an unpriced item to list")

Reset()

do
    local count = select(1, Posting:GetSummary({ includeAll = true }))

    check("the summary counts only priced stock",  count, 2)
    check("the next one to list has a price",
        Posting:GetNextPostable({ includeAll = true }).unitPrice ~= nil, true)
end

print("")
print("reagents a queued craft is waiting on")

Reset()

do
    check("held back from the whole-bag view",    LineFor(Everything(), NEEDED), nil)

    reserved = {}
    check("and offered once nothing needs them",  LineFor(Everything(), NEEDED) ~= nil, true)
end

print("")
print("an item that binds when it is picked up")

Reset()

do
    -- No C_AuctionHouse on this client, so IsSellItemValid cannot be asked and
    -- binding is the only thing left to go on.
    check("is not offered for sale",              LineFor(Everything(), SOULBOUND), nil)

    bindTypes = {}
    check("while the same item unbound is",       LineFor(Everything(), SOULBOUND) ~= nil, true)
end

do
    -- And when the client can answer, its answer wins outright.
    Reset()

    C_AuctionHouse = {
        IsSellItemValid = function() return true end,
    }

    check("the client's own answer is taken",     LineFor(Everything(), SOULBOUND) ~= nil, true)

    C_AuctionHouse = nil
end

print("")
print("stock that cannot be listed from where it sits")

Reset()

do
    -- FindInBags always skipped locked slots; the single bag walk that
    -- replaced it has to skip them the same way, or the list offers a
    -- listing that cannot be made.
    check("a locked slot is not offered",         LineFor(Everything(), LOCKED), nil)

    bags[0][6].isLocked = false
    check("and is once the slot settles",         LineFor(Everything(), LOCKED) ~= nil, true)
end

print("")
print("the same bag twice in a row")

Reset()

do
    -- Unpriced rows are all worth the same nothing, and table.sort is not
    -- stable. The list rebuilds itself once a second at the auction house, so
    -- an order that is merely arbitrary has to be the same arbitrary order.
    bags[0][#bags[0] + 1] = { itemID = 1111, stackCount = 1 }
    bags[0][#bags[0] + 1] = { itemID = 2222, stackCount = 1 }
    bags[0][#bags[0] + 1] = { itemID = 3333, stackCount = 1 }

    local function Order()
        local ids = {}
        for _, line in ipairs(Everything()) do ids[#ids + 1] = line.itemID end
        return table.concat(ids, ",")
    end

    check("the rows come back in the same order", Order(), Order())
end

print("")
print("finding a slot once instead of once per item")

Reset()

do
    -- GetSellInfo takes the slot its caller already found. A table with no bag
    -- means the caller looked and there was nowhere to list from, which must
    -- read the same as finding nothing at all.
    check("a hinted slot is used",     select(2, Posting:GetSellInfo(CRAFTED, { bag = 0, slot = 1 })), 20)
    check("an empty hint is a refusal", Posting:GetSellInfo(CRAFTED, {}), false)
    check("and offers nothing",        select(2, Posting:GetSellInfo(CRAFTED, {})), 0)
    check("no hint still searches",    select(2, Posting:GetSellInfo(CRAFTED)), 20)
end

print("")

if failures > 0 then
    error(("%d check(s) failed"):format(failures), 0)
end

print("PASS -- the Post tab offers the bag, and still refuses what it should")
print("")
