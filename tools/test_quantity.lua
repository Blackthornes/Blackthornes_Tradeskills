-- Choosing how many of a stack to list.
--
-- The sell list used to post whole stacks and offer no way to say otherwise:
-- twenty Linen Cloth went up as one listing of twenty or not at all. That is
-- rarely what a seller wants, and it is not undoable once the auction is up.
--
-- The rule that matters here is that the ceiling and the choice are two
-- different numbers. The ceiling is what the auction house will accept in one
-- go -- everything in the bags for a commodity, one slot's worth for gear.
-- The choice is what the player asked for, and it is clamped against the
-- ceiling on the way out, never stored clamped: bags change, and a stack that
-- grows should not stay pinned to the size it happened to be when the number
-- was typed.

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
ns.Config = {
    Get = function(_, k)
        if k == "undercutCopper" then return 1 end
        if k == "staleAfterSeconds" then return 48 * 3600 end
        if k == "postDuration" then return 2 end
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

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Posting.lua"))("Blackthornes_TS", ns)

local Posting = ns.Posting

--------------------------------------------------------------------------------

local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-52s %-8s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

--- The one postable line for an item, from a real GetPostable run.
local function LineFor(itemID)
    for _, line in ipairs(Posting:GetPostable({ includeAll = true })) do
        if line.itemID == itemID then return line end
    end
end

local LINEN, SWORD = 2589, 7955

local function Reset()
    Posting.chosenQuantity = {}
    commodities = { [LINEN] = true }
    prices = { [LINEN] = { market = 40 }, [SWORD] = { market = 5000 } }

    -- Linen across two slots, because a commodity lists from every bag at once
    -- and a single-slot reading would be the bug this guards.
    bags = {
        [0] = {
            { itemID = LINEN, stackCount = 20 },
            { itemID = LINEN, stackCount = 12 },
            { itemID = SWORD, stackCount = 1 },
        },
    }
end

print("")
print("what a ceiling is")

Reset()

do
    local line = LineFor(LINEN)
    check("a commodity may list every one in the bags", line.maxQuantity, 32)
    check("and does so until told otherwise", line.postQuantity, 32)
    check("which is not a choice worth noting", line.quantityChosen, false)
end

do
    local line = LineFor(SWORD)
    check("an item auction is capped at one slot", line.maxQuantity, 1)
    check("and lists that", line.postQuantity, 1)
end

print("")
print("asking for fewer")

Reset()
Posting:SetChosenQuantity(LINEN, 5)

do
    local line = LineFor(LINEN)
    check("the amount asked for is what lists", line.postQuantity, 5)
    check("the ceiling is unchanged", line.maxQuantity, 32)
    check("and the line says a choice was made", line.quantityChosen, true)
    check("the value follows the amount", line.postTotal, 5 * 40)
    check("what is in the bags is still reported", line.count, 32)
    check("and what it is all worth", line.total, 32 * 40)
end

print("")
print("asking for more than there is")

Reset()
Posting:SetChosenQuantity(LINEN, 100)

check("clamped to what can go up", LineFor(LINEN).postQuantity, 32)

-- Remembered unclamped on purpose: craft more and the number asked for is
-- still the number meant. Clamping on the way in would quietly forget it.
bags[0][1].stackCount = 90
check("and the full amount comes back once it can", LineFor(LINEN).postQuantity, 100)

print("")
print("asking for everything")

Reset()
Posting:ApplyQuantity(LineFor(LINEN), 32)

check("listing the lot is not a choice to remember", Posting.chosenQuantity[LINEN], nil)

-- The point of forgetting it: a later, larger stack lists in full rather than
-- staying pinned at today's 32.
bags[0][1].stackCount = 50
check("so a bigger stack lists in full", LineFor(LINEN).postQuantity, 62)

print("")
print("changing a line in place")

Reset()

do
    -- The panel edits the line it already has rather than rebuilding the list,
    -- which would scroll it back to the top mid-edit.
    local line = LineFor(LINEN)
    local applied = Posting:ApplyQuantity(line, 8)

    check("it reports what it actually applied", applied, 8)
    check("the line lists that many", line.postQuantity, 8)
    check("and is worth that many", line.postTotal, 8 * 40)
    check("a later read agrees", LineFor(LINEN).postQuantity, 8)
end

do
    local line = LineFor(LINEN)
    check("nonsense leaves the choice alone", Posting:ApplyQuantity(line, "twelve"), 8)
    check("zero is not a listing", Posting:ApplyQuantity(line, 0), 1)
    check("nor is a negative one", Posting:ApplyQuantity(line, -5), 1)
    check("halves round down to whole items", Posting:ApplyQuantity(line, 7.9), 7)
end

print("")
print("forgetting a choice")

Reset()
Posting:SetChosenQuantity(LINEN, 4)
check("chosen", LineFor(LINEN).postQuantity, 4)

Posting:ClearChosenQuantity(LINEN)
check("cleared, so back to everything", LineFor(LINEN).postQuantity, 32)

print("")
print("one item's choice is its own")

Reset()
Posting:SetChosenQuantity(LINEN, 3)
check("the item chosen lists fewer", LineFor(LINEN).postQuantity, 3)
check("another item is untouched", LineFor(SWORD).postQuantity, 1)

print("")
print("stock kept in a reagent bag")

Reset()

-- Everything in the reagent bag and nothing loose, which is how the bug was
-- reported: the counts said none, and the sell list offered nothing to sell.
bags = {
    [5] = {
        { itemID = LINEN, stackCount = 20 },
        { itemID = LINEN, stackCount = 12 },
    },
}

do
    local line = LineFor(LINEN)
    check("the reagent bag is offered for sale",  line ~= nil, true)
    check("with everything in it",                line and line.maxQuantity, 32)
end

print("")
print("bags and reagent bag together")

Reset()
bags[5] = { { itemID = LINEN, stackCount = 8 } }

check("both are counted", LineFor(LINEN).maxQuantity, 40)

print("")
print("crafted stock a queued craft needs")

-- Linen is made by one of the account's recipes here, and a queued craft
-- needs 3 of it. Only those 3 are held back: holding back all 32 kept a
-- stack off Post Crafted for the sake of one queued bag.
Reset()
ns.Recipes.GetAccountWide = function() return { [100] = { recipeID = 100, outputItemID = LINEN } } end
ns.Profit.Analyse = function() return nil end
ns.Queue.GetReservedItems = function() return { [LINEN] = 3 } end

do
    local line = LineFor(LINEN)
    check("the rest of a crafted stack still lists", line and line.maxQuantity, 29)
end

ns.Queue.GetReservedItems = function() return { [LINEN] = 40 } end
check("a stack the queue needs all of is kept", LineFor(LINEN), nil)

ns.Recipes.GetAccountWide = function() return {} end
ns.Queue.GetReservedItems = nil

print("")

if failures > 0 then
    print(("FAIL -- %d check(s) failed"):format(failures))
    os.exit(1)
end

print("PASS -- a listing lists the amount asked for, clamped to what can go up")
print("")
