-- The queue's Sort By and the queue done line and sound, outside WoW (the
-- owner said do it, 2026-11-26, from the ts-improve-10 mockup).
--
-- What must hold:
--   1. My Order (the default) leaves the queue's order and Craft Next as
--      they were.
--   2. Profit and Gold per Hour order the rows highest first, a part just
--      before the craft it feeds, and Craft Next follows that order.
--      Something that can't be told goes last. The stored queue never moves.
--   3. Gold per Hour is a craft's profit over its own casting time.
--   4. The last craft made says "Queue done. N crafts made." and plays our
--      own sound only when Queue Done Sound is ticked. Emptying the queue by
--      hand stays quiet.

local GLOBALS = { "GetTime", "time", "C_Timer", "C_TradeSkillUI", "GetZoneText",
    "GetSubZoneText", "UnitGUID" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end
GetTime = function() return 100 end
time = function() return 100000 end
C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }
GetZoneText = function() return "Elwynn Forest" end
GetSubZoneText = function() return "Goldshire" end
C_TradeSkillUI = {}

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.RegisterEvent = noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.Util = { HasFunction = function() return false end }
local config = {}
ns.Config = {
    Get = function(_, key) return config[key] end,
    Set = function(_, key, value) config[key] = value end,
    GetCharacterKey = function() return "me" end,
}
ns.BagsFull = { MaxStack = function() return 20 end }

local RECIPES = {
    [10] = { name = "Bolt", outputItemID = 2, reagents = { { itemID = 1, quantity = 1 } } },
    [20] = { name = "Shirt", outputItemID = 3, reagents = { { itemID = 1, quantity = 1 } } },
    [30] = { name = "Robe", outputItemID = 4, reagents = { { itemID = 2, quantity = 1 } } },
    [40] = { name = "Hat", outputItemID = 5, reagents = { { itemID = 1, quantity = 1 } } },
}
ns.Recipes = { GetAny = function(_, id) return RECIPES[id], "me" end }
ns.Inventory = { changes = 0, GetBagCount = function() return 10 end,
    GetOwnedCount = function(_, id) return id == 2 and 0 or 10 end }
ns.Profit = { GetCraftableCount = function() return 5 end }
ns.Cost = {
    GetCraftCost = function(_, id)
        if id == 30 then return { reagents = { { itemID = 2, quantity = 1, crafted = true } } } end
        return nil
    end,
    FindRecipeForItem = function(_, itemID) return itemID == 2 and 10 or nil end,
}
-- One cast each: the robe is quick, the shirt slow, the hat never cast.
local CASTS = { [10] = 2, [20] = 60, [30] = 1 }
ns.CraftTime = { GetCast = function(_, id) return CASTS[id] end }
local sounds = {}
ns.PlaySoundFile = function(file) sounds[#sounds + 1] = file; return true end
ns.db = { queue = {} }

assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Crafting.lua"))("Blackthornes_TS", ns)
local Queue, Crafting = ns.Queue, ns.Crafting
Crafting.isTradeSkillOpen = true

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-60s %-24s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Name(entry) return entry and RECIPES[entry.recipeID].name end
local function Next() return Name((Crafting:GetNextReady())) end
local function Names(list)
    local names = {}
    for i, entry in ipairs(list) do names[i] = Name(entry) end
    return table.concat(names, ",")
end
local function Row(name)
    for _, entry in ipairs(Queue:GetAll()) do
        if Name(entry) == name then return entry end
    end
end

-- A robe made from a bolt (a part), a shirt and a hat with no price.
config.craftFreesSpaceFirst = false
ns.db.queue = {
    { recipeID = 30, quantity = 2, crafter = "me" },
    { recipeID = 20, quantity = 3, crafter = "me" },
    { recipeID = 40, quantity = 1, crafter = "me" },
}
Queue:RebuildDependencies()
-- Profit for every time each is queued: robe 1g, shirt 6g, hat unknown.
local costs = { [Row("Robe")] = { profit = 10000 }, [Row("Shirt")] = { profit = 60000 } }
Queue.GetEntryCosts = function() return costs end

-- 1. My Order.
check("Sort By starts on My Order", Queue:SortBy(), "mine")
check("My Order shows the queue as it is", Names(Queue:Ordered()), "Bolt,Robe,Shirt,Hat")
check("Craft Next starts with the bolt", Next(), "Bolt")
config.queueSortBy = "nonsense"
check("an unknown Sort By reads as My Order", Queue:SortBy(), "mine")

-- 3. Gold per Hour.
local profit, perHour = Queue:EntryEarns(Row("Robe"))
check("the robe's profit", profit, 10000)
check("the robe's gold an hour (1g over 2 one-second casts)", perHour, 18000000)
local _, shirtHour = Queue:EntryEarns(Row("Shirt"))
check("the shirt's gold an hour (6g over 3 minutes)", shirtHour, 1200000)
check("a part earns nothing of its own", (Queue:EntryEarns(Row("Bolt"))), nil)
check("no price, no gold an hour", select(2, Queue:EntryEarns(Row("Hat"))), nil)

-- 2. Profit and Gold per Hour.
Queue:SetSortBy("profit")
check("Profit is saved", config.queueSortBy, "profit")
check("Profit: shirt, then the bolt before its robe, hat last",
    Names(Queue:Ordered()), "Shirt,Bolt,Robe,Hat")
check("Craft Next makes the shirt first", Next(), "Shirt")
check("the stored queue never moves", Names(Queue:GetAll()), "Bolt,Robe,Shirt,Hat")
Queue:SetSortBy("perHour")
check("Gold per Hour: the bolt and robe first", Names(Queue:Ordered()), "Bolt,Robe,Shirt,Hat")
check("Craft Next makes the bolt first", Next(), "Bolt")
check("a list given is ordered on its own",
    Names(Queue:Ordered({ Row("Hat"), Row("Shirt") })), "Shirt,Hat")
Queue:SetSortBy("bags")
check("Frees Bag Space is kept", Queue:SortBy(), "bags")
check("and lists every row", #Queue:Ordered(), 4)
Queue:SetSortBy("mine")

-- 4. Queue done.
Crafting:NoteQueueMade(3)
check("crafts left: no done line yet", Crafting:QueueDoneText(), nil)
ns.db.queue = {}
Crafting:NoteQueueMade(2)
check("the last craft says the queue is done", Crafting:QueueDoneText(), "Queue done. 5 crafts made.")
check("no sound while Queue Done Sound is off", #sounds, 0)

ns.db.queue = { { recipeID = 20, quantity = 1, crafter = "me" } }
check("something new queued drops the line", Crafting:QueueDoneText(), nil)
config.queueDoneSound = true
ns.db.queue = {}
Crafting:NoteQueueMade(1)
check("one craft reads as one", Crafting:QueueDoneText(), "Queue done. 1 craft made.")
check("ticked, our own sound plays", sounds[1], Crafting.QUEUE_DONE_SOUND)
check("from our own folder", (sounds[1] or ""):find("Media\\Sounds\\queue-done.ogg", 1, true) ~= nil, true)

-- Emptied by hand: counted crafts are let go, nothing plays.
ns.db.queue = { { recipeID = 20, quantity = 4, crafter = "me" } }
Crafting:NoteQueueMade(2)
ns.db.queue = {}
Crafting:OnQueueChanged()
check("cleared by hand forgets the count", Crafting.queueMade, 0)
check("and plays nothing more", #sounds, 1)

-- An alt's craft left on the queue doesn't hold this character's done.
ns.db.queue = { { recipeID = 20, quantity = 1, crafter = "alt", owner = "alt" } }
Crafting:NoteQueueMade(1)
check("only an alt's craft left still counts as done", Crafting:QueueDoneText(), "Queue done. 1 craft made.")

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then error(failed .. " failed") end
