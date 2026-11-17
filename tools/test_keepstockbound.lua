-- Keep in Stock counts only what could be sold.
--
-- The bug: a crafted belt the player made and put on stayed in the Keep in
-- Stock count, so with Keep in Stock at 1 the recipe read "1/1" and was
-- never suggested or queued again. A worn copy, or a soulbound copy back in
-- the bags or bank, can never be listed, so neither is stock. Crafting still
-- counts bound copies in the bags: a bound reagent works in a recipe.
--
-- Drives the real Data/Inventory.lua and Auctions:GetRoom.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

local bags, bankSlots, bank, equipped = {}, {}, {}, {}
local record = {}

local clock = 0
GetTime = function() return clock end
local function Tick() clock = clock + 10 end

local BANK_BAG = -1
C_Container = {
    GetContainerNumSlots = function(bag)
        if bag == BANK_BAG then return #bankSlots end
        return bags[bag] and #bags[bag] or 0
    end,
    GetContainerItemInfo = function(bag, slot)
        local entry
        if bag == BANK_BAG then entry = bankSlots[slot] else entry = bags[bag] and bags[bag][slot] end
        if not entry then return nil end
        return { itemID = entry.itemID, stackCount = entry.stackCount, isBound = entry.isBound }
    end,
}

-- A client that counts worn gear in both of its answers, like Retail.
local function Carried(itemID)
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
        local total = Carried(itemID)
        if includeBank then total = total + (bank[itemID] or 0) end
        return total
    end,
}
GetInventoryItemID = function(_, slot)
    local seen = 0
    for itemID, howMany in pairs(equipped) do
        for _ = 1, howMany do
            seen = seen + 1
            if seen == slot then return itemID end
        end
    end
    return nil
end

Enum = { BagIndex = { Bank = BANK_BAG, Reagentbank = -3, BankBag_1 = 6 } }
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4

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
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize", "RegisterEvent" }) do
        frame[name] = function() end
    end
    return frame
end
C_Timer = { NewTimer = function() return { Cancel = function() end } end, After = function() end }
time = time or os.time

local config = { maxPostedPerItem = 1 }
ns.db = {}
ns.Config = {
    Get = function(_, key) return config[key] end,
    GetRealmKey = function() return "Test-Realm" end,
    GetCharacterKey = function() return "me" end,
}
ns.Recipes = {
    GetCharacterRecord = function() return record end,
    GetAny = function() return nil end,
}
ns.Queue = { GetAll = function() return {} end }
ns.Mail = { GetCount = function() return 0 end }
ns.Profit = { Resolve = function() return nil, "no" end }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Inventory.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Auctions.lua"))("Blackthornes_TS", ns)
ns.Auctions.GetPostedCount = function() return 0 end

local Inventory, Auctions = ns.Inventory, ns.Auctions

local failures = 0
local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-52s %-8s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end
local function Room(itemID)
    local room, _, onHand = Auctions:GetRoom(itemID)
    return room, onHand
end

local BELT, CLOTH = 6466, 2589

print("")
print("a belt you made and wear")
bags = { [0] = { { itemID = CLOTH, stackCount = 5 } } }
equipped = { [BELT] = 1 }
Tick()
local room, onHand = Room(BELT)
check("is not on hand",                          onHand, 0)
check("so Keep in Stock 1 leaves room for one",  room, 1)

print("")
print("the same belt, taken off and back in the bags")
bags = { [0] = { { itemID = BELT, stackCount = 1, isBound = true } } }
equipped = {}
Tick()
check("crafting still sees it",                  Inventory:GetBagCount(BELT), 1)
check("but it cannot be sold",                   Inventory:GetSellableBagCount(BELT), 0)
room, onHand = Room(BELT)
check("so it is not on hand",                    onHand, 0)
check("and there is room for one",               room, 1)

print("")
print("a belt not yet bound still counts")
bags = { [0] = { { itemID = BELT, stackCount = 1 }, { itemID = BELT, stackCount = 1, isBound = true } } }
Tick()
room, onHand = Room(BELT)
check("one free copy is on hand",                onHand, 1)
check("and the shelf is full",                   room, 0)

print("")
print("the bank, read this session")
bags, equipped = { [0] = {} }, {}
bankSlots = { { itemID = BELT, stackCount = 1, isBound = true }, { itemID = CLOTH, stackCount = 20 } }
bank = { [BELT] = 1, [CLOTH] = 20 }
Inventory:SnapshotBank()
Tick()
check("the bound belt there is not stock",       Inventory:GetSellableBankCount(BELT), 0)
check("cloth there still is",                    Inventory:GetSellableBankCount(CLOTH), 20)
check("the bank count itself is unchanged",      Inventory:GetBankCount(BELT), 1)
room = Room(BELT)
check("so there is room for one",                room, 1)

print("")
print("the bank not read this session, belt worn")
Inventory.readThisSession = nil
record.bank, record.bankFree = nil, nil
bankSlots, bank = {}, {}
equipped = { [BELT] = 1 }
-- A client that counts worn gear only when asked about the bank.
local plain = C_Item.GetItemCount
C_Item.GetItemCount = function(itemID, includeBank)
    if includeBank then return plain(itemID, true) end
    return plain(itemID, false) - (equipped[itemID] or 0)
end
Tick()
check("the worn belt is not read as banked",     Inventory:GetSellableBankCount(BELT), 0)
room, onHand = Room(BELT)
check("so it is not on hand",                    onHand, 0)
C_Item.GetItemCount = plain

print("")
if failures > 0 then
    print(("FAIL -- %d check(s) failed"):format(failures))
    os.exit(1)
end
print("PASS -- Keep in Stock counts only copies you could sell")
print("")
