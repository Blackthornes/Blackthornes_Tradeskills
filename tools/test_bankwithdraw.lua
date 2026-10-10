-- The bank snapshot has to follow what leaves the bank.
--
-- The bug: the bank was read once, when its window opened, and never again.
-- Taking twenty bolts out of a purchased bank bag fires BAG_UPDATE for that
-- bag and nothing else -- PLAYERBANKSLOTS_CHANGED covers only the main bank
-- window -- so the snapshot kept saying twenty were in the bank while the
-- walked bag count said twenty were in the bags. Forty held, from twenty
-- bolts, until the next bank visit: enough to push a craft down the Profit
-- list for stock the player did not have.
--
-- The fix takes the snapshot again whenever a bank container changes while
-- the bank is open, and leaves it alone once the bank is shut, because a
-- closed bank reads as empty and an empty read must never replace a good one.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

-- Every handler the module registers, so the test can fire events the way
-- the client would: handler(owner, event, ...).
local handlers = {}
ns.RegisterEvent = function(owner, event, fn)
    handlers[event] = handlers[event] or {}
    handlers[event][#handlers[event] + 1] = { owner = owner, fn = fn }
    return true
end

local function Fire(event, ...)
    for _, entry in ipairs(handlers[event] or {}) do
        entry.fn(entry.owner, event, ...)
    end
end

--------------------------------------------------------------------------------
-- A character with bags and a bank
--------------------------------------------------------------------------------

-- containers[bag][slot] = { itemID, stackCount }. Without Enum.BagIndex the
-- module falls back to the classic layout: -1 is the main bank, 6 onwards
-- the purchased bank bags.
local containers = {}
local bankReadable = false

local function IsBank(bag) return bag == -1 or bag == -3 or bag >= 6 end

C_Container = {
    -- A container has its slots whether or not anything is in them; only a
    -- bank that is shut reports none.
    GetContainerNumSlots = function(bag)
        if IsBank(bag) and not bankReadable then return 0 end
        return containers[bag] and 16 or 0
    end,
    GetContainerItemInfo = function(bag, slot)
        if IsBank(bag) and not bankReadable then return nil end
        local entry = containers[bag] and containers[bag][slot]
        if not entry then return nil end
        return { itemID = entry.itemID, stackCount = entry.stackCount, isLocked = false }
    end,
}

local function CountIn(itemID, predicate)
    local total = 0
    for bag, slots in pairs(containers) do
        if predicate(bag) then
            for _, entry in ipairs(slots) do
                if entry.itemID == itemID then total = total + entry.stackCount end
            end
        end
    end
    return total
end

-- The client knows the bank's contents once it has been seen this session.
C_Item = {
    GetItemCount = function(itemID, includeBank)
        local total = CountIn(itemID, function(bag) return not IsBank(bag) end)
        if includeBank then
            total = total + CountIn(itemID, IsBank)
        end
        return total
    end,
}

GetInventoryItemID = function() return nil end
GetMoney = function() return 0 end

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

local clock = 0
GetTime = function() return clock end
local function Tick() clock = clock + 10 end

time = time or os.time

ns.db = {}
ns.Config = { Get = function() return nil end }

local record = { recipes = {}, inventory = {} }
ns.Recipes = { GetCharacterRecord = function() return record end }
ns.Auctions = { GetPostedCount = function() return 0 end }
ns.Profit = { Resolve = function() return nil, "no" end }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Inventory.lua"))("Blackthornes_TS", ns)

local Inventory = ns.Inventory
Inventory:OnEnable()

--------------------------------------------------------------------------------

local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-56s %-8s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

local BOLT = 2996

print("")
print("twenty bolts in a bank bag, five in the main bank")

containers = {
    [0] = {},
    [-1] = { { itemID = BOLT, stackCount = 5 } },
    [6] = { { itemID = BOLT, stackCount = 20 } },
}
bankReadable = true
Fire("BANKFRAME_OPENED")
Tick()

check("the snapshot holds all twenty-five",     Inventory:GetBankCount(BOLT), 25)
check("nothing in the bags",                    Inventory:GetBagCount(BOLT), 0)
check("so twenty-five held",                    Inventory:GetOwnedCount(BOLT), 25)

print("")
print("the twenty are taken out of the bank bag")

containers[6] = {}
containers[0] = { { itemID = BOLT, stackCount = 20 } }
Fire("BAG_UPDATE", 6)
Fire("BAG_UPDATE", 0)
Tick()

check("the bags now hold twenty",               Inventory:GetBagCount(BOLT), 20)
check("the bank count follows them out",        Inventory:GetBankCount(BOLT), 5)
check("and nothing is counted twice",           Inventory:GetOwnedCount(BOLT), 25)

print("")
print("the bank is shut and something in the bags moves")

Fire("BANKFRAME_CLOSED")
bankReadable = false
containers[0] = { { itemID = BOLT, stackCount = 10 }, { itemID = BOLT, stackCount = 10 } }
Fire("BAG_UPDATE", 0)
Fire("BAG_UPDATE", 6)
Tick()

check("a closed bank keeps its last good snapshot", Inventory:GetBankCount(BOLT), 5)
check("bags are still live",                       Inventory:GetBagCount(BOLT), 20)

print("")
print("the main bank window is changed through its own event")

bankReadable = true
Fire("BANKFRAME_OPENED")
containers[-1] = {}
containers[0][3] = { itemID = BOLT, stackCount = 5 }
Fire("PLAYERBANKSLOTS_CHANGED", 1)
Fire("BAG_UPDATE", 0)
Tick()

check("the main bank empties too",              Inventory:GetBankCount(BOLT), 0)
check("and everything is in the bags",          Inventory:GetOwnedCount(BOLT), 25)

print("")
print("the bank shuts, and its slot events fire with no banker in sight")

Fire("BANKFRAME_CLOSED")
local seenAt = record.bankAt - 3600
record.bankAt = seenAt
Inventory.readThisSession = false

-- On a retail engine a shut bank still answers with its slot count, just
-- with nothing in the slots.
local shutBankSlots = function(bag)
    return containers[bag] and 16 or 0
end
local readable = C_Container.GetContainerNumSlots
C_Container.GetContainerNumSlots = shutBankSlots
bankReadable = false
local snapshot = record.bank
Fire("PLAYERBANKSLOTS_CHANGED", 1)
Fire("PLAYERREAGENTBANKSLOTS_CHANGED", 1)
Fire("BAG_UPDATE", 6)
Tick()
C_Container.GetContainerNumSlots = readable

check("the time the bank was seen stays put",   record.bankAt, seenAt)
check("the snapshot is not retaken",            record.bank == snapshot, true)
check("the bank is not called read this session", Inventory:HasReadBankThisSession(), false)

print("")
print("a bank container is told apart from a bag")

check("the main bank",                          Inventory.IsBankContainer(-1), true)
check("the reagent bank",                       Inventory.IsBankContainer(-3), true)
check("the first bank bag",                     Inventory.IsBankContainer(6), true)
check("the backpack is not",                    Inventory.IsBankContainer(0), false)
check("nor the fourth bag",                     Inventory.IsBankContainer(4), false)
check("nor nothing at all",                     Inventory.IsBankContainer(nil), false)

print("")
if failures > 0 then
    error(("%d bank withdrawal check(s) failed"):format(failures))
end
print("  bank withdrawal: all checks passed")
