-- Several copies of an item that does not stack, in one listing click.
--
-- Izbode, 2026-10-04: Mana Oils do not stack, so each went up on its own
-- click with the wait for the last one in between. An item that cannot stack
-- and has no random suffix may now list every copy at once (one auction
-- each); a stackable item auction still lists one slot. A batch that comes
-- back with only one listed turns this off for the session.

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

maxStacks = {}
C_Item = {
    GetItemInfo = function(itemID)
        return "item", nil, 2, 1, 1, "Consumable", "", maxStacks[itemID] or 20
    end,
}

C_Container = {
    GetContainerItemLink = function(bag, slot)
        local entry = bags[bag] and bags[bag][slot]
        return entry and entry.link or nil
    end,
    GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local entry = bags[bag] and bags[bag][slot]
        if not entry then return nil end
        return { itemID = entry.itemID, stackCount = entry.stackCount, isLocked = false, hyperlink = entry.link }
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
ns.Cost.FindAnyRecipeForItem = ns.Cost.FindRecipeForItem

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

local LINEN, OIL, BAND, POTION = 2589, 20748, 7955, 929

local function Reset()
    Posting.chosenQuantity = {}
    Posting.manyRefused = false
    commodities = { [LINEN] = true }
    maxStacks = { [LINEN] = 200, [OIL] = 1, [BAND] = 1, [POTION] = 5 }
    prices = { [LINEN] = { market = 40 }, [OIL] = { market = 30000 },
        [BAND] = { market = 4000 }, [POTION] = { market = 1000 } }
    bags = {
        [0] = {
            { itemID = OIL, stackCount = 1 },
            { itemID = OIL, stackCount = 1 },
            { itemID = OIL, stackCount = 1 },
            { itemID = POTION, stackCount = 5 },
            { itemID = POTION, stackCount = 3 },
            { itemID = BAND, stackCount = 1, link = "|cff1eff00|Hitem:7955::::::763:::::|h[Lead Band of the Wolf]|h|r" },
            { itemID = BAND, stackCount = 1, link = "|cff1eff00|Hitem:7955::::::763:::::|h[Lead Band of the Wolf]|h|r" },
        },
    }
end

print("")
print("what can go up together")

Reset()
check("every Mana Oil in one click", LineFor(OIL).maxQuantity, 3)
check("and all of them unless told otherwise", LineFor(OIL).postQuantity, 3)
check("a stackable item auction still lists one slot", LineFor(POTION).maxQuantity, 5)
check("a commodity is untouched", LineFor(LINEN), nil)

check("the link names a suffix", ns.Util.LinkSuffix(bags[0][6].link) ~= nil, true)
check("random suffix gear goes one at a time", LineFor(BAND).maxQuantity, 1)

print("")
print("when the auction house takes only one")

Reset()
Posting.pending = { itemID = OIL, quantity = 3, many = true, postedBefore = 0, idsBefore = {} }
Posting:ResolvePending(3, true)
check("all three listed: keeps listing together", Posting.manyRefused, false)

Posting.pending = { itemID = OIL, quantity = 3, many = true, postedBefore = 0, idsBefore = {} }
Posting:ResolvePending(1, true)
check("one of three: back to one at a time", Posting.manyRefused, true)
check("so the oils go up one per click", LineFor(OIL).maxQuantity, 1)

Reset()
Posting.pending = { itemID = OIL, quantity = 3, many = true, postedBefore = 0, idsBefore = {} }
Posting:ResolvePending(0, false)
check("none listed: back to one at a time", Posting.manyRefused, true)

Reset()
Posting.pending = { itemID = OIL, quantity = 1, many = false, postedBefore = 0, idsBefore = {} }
Posting:ResolvePending(0, false)
check("a single listing failing changes nothing", Posting.manyRefused, false)

-- Every suite shares one Lua state; leave no item lookup behind for the next.
C_Item, maxStacks = nil, nil

print("")
if failures > 0 then
    print(("FAIL -- %d check(s) failed"):format(failures))
    os.exit(1)
end

print("PASS -- copies of an item that does not stack list in one click")
