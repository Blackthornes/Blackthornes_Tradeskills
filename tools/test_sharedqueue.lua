-- The queue shared across characters (Trent, 2026-10-03): "the queue kept
-- up with the character that initiated the craft queue, and the other
-- characters that can craft the other subcrafts for cheaper then show the
-- other character they're crafting to help and when you go to the mail it
-- should allow you to auto send materials this character has to the one
-- that needs it".
--
-- Trent queues a Woolen Reagent Bag. He cannot make Bolt of Woolen Cloth;
-- his tailor Loom can, for less than buying them. So Loom is given the
-- bolts, Loom is told they are for Trent, Trent's mailbox offers Loom the
-- wool, and Loom's offers Trent the bolts.
--
-- Drives the real Cost.lua, Queue.lua and QueueMail.lua.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end

local clock = 1000000
time = function() return clock end

local BAG, BOLT, WOOL, DYE, THREAD = 5000, 2997, 2592, 3825, 2321
local TRENT, LOOM, FARAWAY = "Player-TRENT", "Player-LOOM", "Player-FAR"

local bound = {}
ns.Util = { IsBoundOnPickup = function(itemID) return bound[itemID] == true end }

local settings = { valueOwnedMaterials = true }
local currentKey = TRENT
ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return currentKey end,
}

local BAG_RECIPE = { recipeID = 10, name = "Woolen Reagent Bag", outputItemID = BAG,
    quantityMin = 1, quantityMax = 1,
    reagents = { { itemID = BOLT, quantity = 3 },
                 { itemID = DYE, quantity = 1 },
                 { itemID = THREAD, quantity = 1 } } }
local BOLT_RECIPE = { recipeID = 20, name = "Bolt of Woolen Cloth", outputItemID = BOLT,
    quantityMin = 1, quantityMax = 1,
    reagents = { { itemID = WOOL, quantity = 3 } } }

local function freshCharacters()
    return {
        [TRENT] = { name = "Trent", realm = "Forever", faction = "Horde", recipes = { [10] = BAG_RECIPE } },
        [LOOM] = { name = "Loom", realm = "Forever", faction = "Horde", recipes = { [20] = BOLT_RECIPE } },
    }
end

ns.Recipes = {
    GetAll = function()
        local record = ns.db.characters[currentKey]
        return record and record.recipes or {}
    end,
    Get = function(self, id) return self:GetAll()[id] end,
    GetAny = function(self, id)
        local mine = self:GetAll()[id]
        if mine then return mine, currentKey end
        for key, record in pairs(ns.db.characters) do
            if record.recipes[id] then return record.recipes[id], key end
        end
    end,
    GetCharacterName = function(_, key) return ns.db.characters[key].name end,
    GetCharacters = function(self)
        local list = {}
        for key in pairs(ns.db.characters) do
            list[#list + 1] = { key = key, name = self:GetCharacterName(key) }
        end
        return list
    end,
}

-- The bags of whoever is logged in; the others are their saved snapshots.
local bags = {}
ns.Inventory = {
    GetBagCount = function(_, id) return bags[id] or 0 end,
    GetBankCount = function() return 0 end,
    GetMailCount = function() return 0 end,
    GetOwnedCount = function(_, id) return bags[id] or 0 end,
    GetAltTotal = function() return 0 end,
}

local auction = { [BOLT] = 1030, [WOOL] = 295, [DYE] = 4885 }
ns.Prices = { GetValue = function(_, id) return auction[id] end }
ns.Vendor = {
    GetUnitPrice = function(_, id) return id == THREAD and 90 or nil end,
    IsLimited = function() return false end,
}

assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/QueueMail.lua"))("Blackthornes_TS", ns)

ns.Profit = { Analyse = function() return { priceable = false } end }

local Queue, Cost, QueueMail = ns.Queue, ns.Cost, ns.QueueMail

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function row(itemID)
    for _, line in ipairs(Queue:GetShoppingList()) do
        if line.itemID == itemID then return line end
    end
end

local function entryFor(recipeID)
    for _, entry in ipairs(Queue:GetAll()) do
        if entry.recipeID == recipeID then return entry end
    end
end

local function loginAs(key, carried)
    currentKey = key
    bags = carried or {}
    Cost:InvalidateIndex()
end

local function queueOneBag(characters)
    loginAs(TRENT, {})
    ns.db = { queue = {}, characters = characters or freshCharacters() }
    Queue:Add(10, 1)
end

local function delivery(to)
    for _, d in ipairs(QueueMail:GetDeliveries()) do
        if d.to == to then return d end
    end
end

local function sends(d, itemID)
    for _, item in ipairs((d and d.items) or {}) do
        if item.itemID == itemID then return item.count end
    end
    return 0
end

print("\nthe queue remembers who queued it")

queueOneBag()
local bagEntry = entryFor(10)
check("the bag is Trent's", bagEntry.owner == TRENT)
check("and Trent makes it", Queue:GetCrafter(bagEntry) == TRENT)

print("\nthe tailor is given the bolts")

local bolts = entryFor(20)
check("the bolts are queued", bolts ~= nil and bolts.isDependency)
check("three of them", bolts.quantity == 3)
check("made by Loom", Queue:GetCrafter(bolts) == LOOM)
check("for Trent", bolts.forCharacters[TRENT] == true and bolts.owner == TRENT)
check("Trent is not told to buy bolts", row(BOLT) == nil)
check("the wool for them is on the list", row(WOOL) and row(WOOL).shortfall == 9)
check("Trent reads who makes them", Queue:DescribeWho(bolts)[1] == "Loom makes this for you")
check("and nothing about his own bag", #Queue:DescribeWho(bagEntry) == 0)

print("\nwool Loom already holds is not Trent's to buy")

queueOneBag()
ns.db.characters[LOOM].inventory = { [WOOL] = 6 }
check("only the other three are", row(WOOL) and row(WOOL).needed == 3)
check("and it says Loom holds six", row(WOOL).othersHold == 6)

print("\nlogging into the tailor")

queueOneBag()
loginAs(LOOM, {})
Queue:RefreshForCharacter()
bolts = entryFor(20)
check("the bolts are still Loom's", bolts and Queue:GetCrafter(bolts) == LOOM and bolts.quantity == 3)
check("Loom reads who they are for", Queue:DescribeWho(bolts)[1] == "you make this for Trent")
local helping = Queue:GetHelping(LOOM)
check("Loom is helping with one craft", #helping == 1 and helping[1].recipients[1] == TRENT)
local said = false
for _, line in ipairs(printed) do
    if line:find("helping Trent: make 3 x Bolt of Woolen Cloth for Woolen Reagent Bag", 1, true) then said = true end
end
check("and is told so at login", said)
check("the bag reads as Trent's", Queue:DescribeWho(entryFor(10))[1] == "Trent's craft")

print("\nat Trent's mailbox")

queueOneBag()
bags = { [WOOL] = 12 }
local toLoom = delivery(LOOM)
check("Loom is sent the wool", toLoom and sends(toLoom, WOOL) == 9)
check("only what the bolts use", #toLoom.items == 1)
check("named for the mail", toLoom.name == "Loom")

QueueMail:NoteSent(LOOM, { { itemID = WOOL, count = 9 } })
bags = { [WOOL] = 3 }
check("once sent, it is not offered again", delivery(LOOM) == nil)
check("it counts as Loom's on its way", Queue:HeldBy(LOOM, WOOL) == 9)

clock = clock + 2 * 3600
ns.db.characters[LOOM].mailAt = clock
ns.db.characters[LOOM].inventory = { [WOOL] = 9 }
check("after Loom's mailbox is read, the bags count instead", Queue:HeldBy(LOOM, WOOL) == 9)

print("\nat Loom's mailbox, bolts made")

loginAs(LOOM, { [BOLT] = 3 })
Queue:RebuildDependencies()
check("the bolts are made, so none are left to make", entryFor(20) == nil)
local toTrent = delivery(TRENT)
check("Trent is sent the bolts", toTrent and sends(toTrent, BOLT) == 3)

print("\na craft only an alt knows goes back to whoever queued it")

queueOneBag()
QueueMail:NoteMadeFor(TRENT, BAG, 1)  -- as Trent: owed to himself, ignored
check("nothing is owed to yourself", next(QueueMail:GetOwed(TRENT)) == nil)
loginAs(LOOM, { [BAG] = 1 })
QueueMail:NoteMadeFor(TRENT, BAG, 1)
check("Loom owes Trent the bag", QueueMail:GetOwed(TRENT)[BAG] == 1)
check("and the mailbox offers it", sends(delivery(TRENT), BAG) == 1)
QueueMail:NoteSent(TRENT, { { itemID = BAG, count = 1 } })
check("sent, it is no longer owed", QueueMail:GetOwed(TRENT)[BAG] == nil)

print("\nwho cannot be given a sub-craft")

local characters = freshCharacters()
characters[LOOM].realm = "Elsewhere"
queueOneBag(characters)
check("a tailor on another realm is not", entryFor(20) == nil)
check("so the bolts are bought", row(BOLT) and row(BOLT).shortfall == 3)

characters = freshCharacters()
characters[LOOM].faction = "Alliance"
queueOneBag(characters)
check("nor one of the other faction", entryFor(20) == nil)

bound[BOLT] = true
queueOneBag()
check("nor one making something that binds when picked up", entryFor(20) == nil)
bound[BOLT] = nil

characters = freshCharacters()
characters[TRENT].recipes[20] = BOLT_RECIPE
queueOneBag(characters)
check("Trent makes his own bolts when he can", Queue:GetCrafter(entryFor(20)) == TRENT)
check("and nothing is mailed", delivery(LOOM) == nil)

print("\nsharing switched off")

settings.shareQueueWithAlts = false
queueOneBag()
check("Trent cannot make bolts, so none are queued", entryFor(20) == nil)
check("and the mailbox has nothing", #QueueMail:GetDeliveries() == 0)
settings.shareQueueWithAlts = nil

print("\nfinding a character by the name typed into a mail")

queueOneBag()
check("Loom by name", QueueMail:FindCharacter("Loom") == LOOM)
check("any case", QueueMail:FindCharacter("loom") == LOOM)
check("with the realm", QueueMail:FindCharacter("Loom-Forever") == LOOM)
check("not someone else's Loom elsewhere", QueueMail:FindCharacter("Loom-Elsewhere") == nil)
check("a stranger is nobody", QueueMail:FindCharacter("Stranger") == nil)

print(("\n%d passed, 0 failed"):format(checks))
