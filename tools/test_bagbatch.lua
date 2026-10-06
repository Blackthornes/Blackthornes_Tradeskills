-- Batches that fit the bags (Ezmode, 2026-10-05).
--
-- A thousand Lesser Magic Wands is a thousand Simple Wood (20 a stack) and a
-- thousand Lesser Magic Essence (10 a stack): 150 slots. With 30 free and 5
-- kept spare, Buy materials buys what fits, in step, so it makes whole
-- crafts; and Take next batch at the mailbox takes the essence the same way.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn =
    function() end, function() end, function() end, function() end
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
ns.Util = {
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    FormatMoney = function(c) return tostring(c) end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
    HasFunction = function(path) return path == "BuyMerchantItem" end,
}

local passed, failed = 0, 0
local function expect(label, got, want)
    if got == want then
        passed = passed + 1
        print(("  ok    %s"):format(label))
    else
        failed = failed + 1
        print(("  FAIL  %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local WOOD, ESSENCE = 4470, 10938
local STACKS = { [WOOD] = 20, [ESSENCE] = 10 }
C_Item = { GetItemMaxStackByID = function(itemID) return STACKS[itemID] end }

local settings = { bagSpareSlots = 5, mailBatchTake = true }
ns.Config = { Get = function(_, key) return settings[key] end }

local free = 30
ns.Inventory = { GetCarriedBags = function() return { 0 } end }
C_Container = { GetContainerNumFreeSlots = function() return free, 0 end }

local bags = { [WOOD] = 0, [ESSENCE] = 0 }
local NEEDED = 1000
ns.Queue = {
    Count = function() return 1 end,
    GetShoppingList = function()
        return {
            { itemID = WOOD, needed = NEEDED, inBags = bags[WOOD], shortfall = NEEDED - bags[WOOD] },
            { itemID = ESSENCE, needed = NEEDED, inBags = bags[ESSENCE], shortfall = NEEDED - bags[ESSENCE] },
        }
    end,
}

assert(loadfile(lfs_cwd .. "/Logic/BagsFull.lua"))("Blackthornes_TS", ns)
local BagsFull = ns.BagsFull

print("")
print("Planning a batch")

expect("a part stack is topped up before a new slot", BagsFull.SlotsFor(WOOD, 25, 15), 1)
expect("a full stack in the bags takes nothing off", BagsFull.SlotsFor(WOOD, 25, 20), 2)
expect("an item the game says nothing about is one a slot", BagsFull.SlotsFor(1, 3, 0), 3)

local plan = BagsFull:PlanBatch(ns.Queue:GetShoppingList(), 25)
expect("1000 wands' worth needs 150 slots", plan.slots, 150)
expect("wood and essence come in step", plan.bring[WOOD], plan.bring[ESSENCE])
expect("as many as fit in 25 slots", plan.bring[WOOD], 160)
expect("about six batches", plan.batches, 6)

local all = BagsFull:PlanBatch(ns.Queue:GetShoppingList(), 200)
expect("everything fits: all of it", all.share, 1)
expect("everything fits: all the essence", all.bring[ESSENCE], 1000)

--------------------------------------------------------------------------------
print("")
print("Buying at the vendor")

local purchases = {}
BuyMerchantItem = function(index, amount) purchases[#purchases + 1] = { index = index, amount = amount } end
GetMoney = function() return 10000000 end
C_Timer = { After = function(_, fn) fn() end }
ns.Cost = { InvalidateIndex = function() end }
ns.Prices = { Get = function() return nil end }

assert(loadfile(lfs_cwd .. "/Data/Vendor.lua"))("Blackthornes_TS", ns)
local Vendor = ns.Vendor
Vendor.isMerchantOpen = true
Vendor.merchantItems = {
    [WOOD] = { index = 1, price = 38, stack = 1, numAvailable = -1, extendedCost = false },
}

-- Vendor buys are not held to the bags (taken out 2026-10-06), even when
-- the bags could not hold it all.
local lines, _, _, batch = Vendor:GetNeeded()
expect("only the wood is bought here", #lines, 1)
expect("the whole shortfall", lines[1].amount, 1000)
expect("no batch", batch, nil)

-- A save that still says fitBuysToBags = true changes nothing.
settings.fitBuysToBags = true
free = 5
lines = Vendor:GetNeeded()
expect("an old saved setting is ignored", lines[1].amount, 1000)
settings.fitBuysToBags = nil

--------------------------------------------------------------------------------
print("")
print("Taking from the mail")

bags[ESSENCE] = 0
free = 30

-- Ten mails of ten stacks of ten essence, and one COD mail of essence.
local inbox = {}
for _ = 1, 10 do
    local items = {}
    for slot = 1, 10 do items[slot] = { itemID = ESSENCE, count = 10 } end
    inbox[#inbox + 1] = { items = items }
end
inbox[#inbox + 1] = { cod = 500, items = { { itemID = ESSENCE, count = 10 } } }

ATTACHMENTS_MAX_RECEIVE = 16
GetInboxNumItems = function() return #inbox end
GetInboxHeaderInfo = function(index)
    local mail = inbox[index]
    local count = 0
    for _ in pairs(mail.items) do count = count + 1 end
    return nil, nil, "Alt", "Essence", 0, mail.cod or 0, 30, count
end

ns.Mail = {
    isOpen = true,
    ReadAttachment = function(_, index, slot)
        local item = inbox[index] and inbox[index].items[slot]
        if item then return item.itemID, item.count end
    end,
}

local takes = 0
TakeInboxItem = function(index, slot)
    local item = inbox[index].items[slot]
    inbox[index].items[slot] = nil
    bags[item.itemID] = bags[item.itemID] + item.count
    free = free - 1
    takes = takes + 1
    if next(inbox[index].items) == nil then table.remove(inbox, index) end
end

assert(loadfile(lfs_cwd .. "/Logic/QueueMail.lua"))("Blackthornes_TS", ns)
local QueueMail = ns.QueueMail

local offer = QueueMail:GetMailBatch()
expect("the mail offers essence", offer and offer.items[1].itemID, ESSENCE)
expect("as much as matches the batch", offer and offer.units, 160)

local took
QueueMail:TakeBatch(function(units) took = units end)
expect("took the batch", took, 160)
expect("one stack at a time", takes, 16)
expect("the spare slots stay free", free >= 5, true)

for _, mail in ipairs(inbox) do
    if mail.cod then expect("the COD mail is left alone", mail.items[1] ~= nil, true) end
end

settings.mailBatchTake = false
expect("setting off: nothing offered", QueueMail:GetMailBatch(), nil)

print("")
print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then error("bag batch tests failed") end
