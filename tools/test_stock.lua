-- What counts as stock, and what is just something you are wearing.
--
-- The bug: four Linen Bags being used as bags read as four Linen Bags in
-- hand, so the Profit tab decided the shelf was full and stopped recommending
-- the recipe. `C_Item.GetItemCount` counts an equipped container as one of
-- that container, and the addon took its word for "in bags".
--
-- Equipped things are not stock. You cannot sell the bag your reagents are
-- sitting in, and a crafted sword in your hand is not inventory either. The
-- containers are the one source that cannot confuse the two, so the bag count
-- is walked rather than asked for.
--
-- Which then broke the other way: the walk stopped at the fourth bag, so a
-- reagent bag -- a sixth container, past the ordinary four -- was never opened,
-- and reagents kept where the game most encourages you to keep them counted as
-- reagents you do not own. The second half of this file is about which
-- containers get walked, and about not walking into the bank by mistake.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

--------------------------------------------------------------------------------
-- A character with bags, a bank and things worn
--------------------------------------------------------------------------------

local bags = {}
local bank = {}
local equipped = {}
local record

-- Wound forward by hand: the walk is cached for a fraction of a second, and a
-- test that never moves would read a stale count and prove nothing.
local clock = 0
GetTime = function() return clock end

local function Tick() clock = clock + 10 end

C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local entry = bags[bag] and bags[bag][slot]
        if not entry then return nil end
        return { itemID = entry.itemID, stackCount = entry.stackCount, isLocked = false }
    end,
}

--- Stands in for a client that counts a worn bag as one of that bag, which is
--- the misreport this whole file is about.
local function ClientBagCount(itemID)
    local total = equipped[itemID] or 0
    for _, slots in pairs(bags) do
        for _, entry in ipairs(slots) do
            if entry.itemID == itemID then total = total + entry.stackCount end
        end
    end
    return total
end

C_Item = {
    GetItemCount = function(itemID, includeBank)
        local total = ClientBagCount(itemID)
        if includeBank then total = total + (bank[itemID] or 0) end
        return total
    end,
}

GetInventoryItemID = function(_, slot)
    -- Slots are handed out in order; only the count matters here.
    local seen = 0
    for itemID, howMany in pairs(equipped) do
        for _ = 1, howMany do
            seen = seen + 1
            if seen == slot then return itemID end
        end
    end
    return nil
end

ns.Util = {
    Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
    HasFunction = function(path)
        return path == "C_Item.GetItemCount" or path == "GetInventoryItemID"
    end,
}

CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize" }) do
        frame[name] = function() end
    end
    return frame
end

C_Timer = { NewTimer = function() return { Cancel = function() end } end }

time = time or os.time

ns.db = {}
ns.Config = { Get = function() return nil end }
ns.Recipes = { GetCharacterRecord = function() return nil end }
ns.Auctions = { GetPostedCount = function() return 0 end }
ns.Profit = { Resolve = function() return nil, "no" end }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Inventory.lua"))("Blackthornes_TS", ns)

local Inventory = ns.Inventory

--------------------------------------------------------------------------------

local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-52s %-8s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

local LINEN_BAG, CLOTH = 4238, 2589

print("")
print("four bags worn and none to sell")

bags = { [0] = { { itemID = CLOTH, stackCount = 20 } } }
bank, equipped = {}, { [LINEN_BAG] = 4 }
Tick()

check("the client counts the worn bags",     C_Item.GetItemCount(LINEN_BAG), 4)
check("we do not",                           Inventory:GetBagCount(LINEN_BAG), 0)
check("and say plainly what is worn",        Inventory:GetEquippedCount(LINEN_BAG), 4)
check("so nothing is held",                  Inventory:GetOwnedCount(LINEN_BAG), 0)

print("")
print("four worn and two in the bags to sell")

bags = { [0] = { { itemID = LINEN_BAG, stackCount = 1 }, { itemID = LINEN_BAG, stackCount = 1 } } }
Tick()

check("only the loose ones count",           Inventory:GetBagCount(LINEN_BAG), 2)
check("the worn ones are still reported",    Inventory:GetEquippedCount(LINEN_BAG), 4)
check("and held is the loose ones",          Inventory:GetOwnedCount(LINEN_BAG), 2)

print("")
print("the bank still counts")

bank = { [LINEN_BAG] = 3 }
Tick()

-- The bank figure is a difference of two client counts, so whatever the client
-- miscounts appears in both and cancels. Four worn bags must not land here.
check("the bank is read through the miscount", Inventory:GetBankCount(LINEN_BAG), 3)
check("bags plus bank, and nothing worn",      Inventory:GetOwnedCount(LINEN_BAG), 5)
check("and the total agrees",                  Inventory:GetTotalCount(LINEN_BAG), 5)

print("")
print("ordinary items are unaffected")

check("cloth in the bags",                   Inventory:GetBagCount(CLOTH), 0)

bags[0][3] = { itemID = CLOTH, stackCount = 20 }
Tick()

check("cloth counted once added",            Inventory:GetBagCount(CLOTH), 20)
check("nobody wears cloth",                  Inventory:GetEquippedCount(CLOTH), 0)
check("an item nowhere at all",              Inventory:GetBagCount(99999), 0)
check("and no item at all",                  Inventory:GetBagCount(nil), 0)

print("")
print("one walk answers for everything")

bags = { [0] = {
    { itemID = CLOTH, stackCount = 20 },
    { itemID = CLOTH, stackCount = 12 },
    { itemID = LINEN_BAG, stackCount = 1 },
} }
Tick()

local counts = Inventory:GetBagCounts()
check("stacks of one item add up",           counts[CLOTH], 32)
check("a second item is kept apart",         counts[LINEN_BAG], 1)

print("")
print("a bag event drops the cached walk")

-- No tick this time: without the event the old walk would still be standing.
bags[0][1].stackCount = 5
check("stale until told otherwise",          Inventory:GetBagCount(CLOTH), 32)

Inventory:OnBagChanged()
check("and current once told",               Inventory:GetBagCount(CLOTH), 17)

print("")
print("a reagent bag is a container like any other")

-- Retail's layout: the backpack, four bags, then the reagent bag at 5.
Enum = { BagIndex = { ReagentBag = 5, BankBag_1 = 6 } }
Inventory:InvalidateBagLayout()

bags = {
    [0] = { { itemID = CLOTH, stackCount = 20 } },
    [5] = { { itemID = CLOTH, stackCount = 40 } },
}
bank, equipped = {}, {}
Tick()

check("the reagent bag is walked",           Inventory:GetReagentBag(), 5)
check("and its contents counted",            Inventory:GetBagCount(CLOTH), 60)
check("which is what the client says too",   C_Item.GetItemCount(CLOTH), 60)
check("so nothing looks unaccounted for",    Inventory:GetOwnedCount(CLOTH), 60)

-- The bug as reported: everything is in the reagent bag and nothing anywhere
-- else, so the old walk found a count of zero and the recipe looked unmakeable.
bags = { [5] = { { itemID = CLOTH, stackCount = 40 } } }
Tick()

check("a reagent bag on its own still counts", Inventory:GetBagCount(CLOTH), 40)

print("")
print("and it reaches the snapshot alts are read from")

ns.Recipes = { GetCharacterRecord = function() return record end }
record = {}
Inventory:Snapshot()

check("the snapshot sees it as well",        record.inventory[CLOTH], 40)

print("")
print("a client that only counts its bag slots")

-- No enum to read, but the client still says it equips more bag slots than the
-- four ordinary ones, and the extra one is the reagent bag.
Enum = nil
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
Inventory:InvalidateBagLayout()
Tick()

check("found without an enum",               Inventory:GetReagentBag(), 5)
check("and counted",                         Inventory:GetBagCount(CLOTH), 40)

print("")
print("a client with no reagent bag at all")

-- Nothing says the slot exists, so it is not walked. This matters more than it
-- looks: where there is no reagent bag, container 5 is the first bank bag, and
-- counting the bank as bags would say you can craft things you cannot reach.
Enum = nil
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
Inventory:InvalidateBagLayout()
Tick()

check("no reagent bag is claimed",           Inventory:GetReagentBag(), nil)
check("and container 5 is left alone",       Inventory:GetBagCount(CLOTH), 0)

print("")
print("and an index that would reach the bank is refused")

Enum = { BagIndex = { ReagentBag = 6, BankBag_1 = 6 } }
NUM_TOTAL_EQUIPPED_BAG_SLOTS = nil
Inventory:InvalidateBagLayout()

bags = { [6] = { { itemID = CLOTH, stackCount = 40 } } }
Tick()

check("the bank is not a bag",               Inventory:GetReagentBag(), nil)
check("so its contents are not in hand",     Inventory:GetBagCount(CLOTH), 0)

print("")
print("each container is reportable on its own")

Enum = { BagIndex = { ReagentBag = 5, BankBag_1 = 6 } }
Inventory:InvalidateBagLayout()

bags = {
    [0] = { { itemID = CLOTH, stackCount = 20 }, { itemID = LINEN_BAG, stackCount = 1 } },
    [5] = { { itemID = CLOTH, stackCount = 40 } },
}
Tick()

local walked = Inventory:GetCarriedBags()
check("six containers carried",              #walked, 6)
check("the last of them is the reagent bag", walked[#walked], 5)

local inBackpack, backpackSlots = Inventory:CountInBag(0, CLOTH)
local inReagent = Inventory:CountInBag(5, CLOTH)

check("counted in the backpack",             inBackpack, 20)
check("with its size reported",              backpackSlots, 2)
check("and counted in the reagent bag",      inReagent, 40)
check("an empty container reports zero",     Inventory:CountInBag(1, CLOTH), 0)

print("")

if failures > 0 then
    print(("FAIL -- %d check(s) failed"):format(failures))
    os.exit(1)
end

print("PASS -- every container you carry is counted, and only those")
print("")
