-- Keep in stock by profession (a player asked, the owner agreeing
-- 2026-10-13): an item's own number wins, else its profession's, else
-- Keep in stock per item. Drives the real Auctions:GetLimit and GetRoom,
-- and carries the numbers through Transfer's export code.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.Util = { Count = function(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end }

local POTION, SWORD, BOLT = 100, 200, 300
ns.db = {
    queue = {}, postLimits = {}, postedAuctions = {},
    characters = {
        alice = { recipesCachedAt = 1, recipes = {
            [1] = { recipeID = 1, outputItemID = POTION, skillLineID = 2937 },   -- Alchemy (modern line)
            [2] = { recipeID = 2, outputItemID = SWORD, skillLineID = 164 },     -- Blacksmithing
        } },
        bob = { recipesCachedAt = 1, recipes = {
            [3] = { recipeID = 3, outputItemID = BOLT, skillLineID = 197 },      -- Tailoring
        } },
    },
}

local config = { maxPostedPerItem = 3 }
ns.Config = {
    Get = function(_, key) return config[key] end,
    Set = function(_, key, value) config[key] = value end,
    GetRealmKey = function() return "Test-Realm" end,
    DEFAULTS = { settings = { maxPostedPerItem = 0 } },
}

assert(loadfile(lfs_cwd .. "/Data/Recipes.lua"))("Blackthornes_TS", ns)
local recipesByID = {}
for _, record in pairs(ns.db.characters) do
    for id, recipe in pairs(record.recipes) do recipesByID[id] = recipe end
end
ns.Recipes.GetAny = function(_, id) return recipesByID[id] end

local bags = {}
ns.Inventory = {
    GetBagCount = function(_, id) return bags[id] or 0 end,
    GetBankCount = function() return 0 end,
    GetMailCount = function() return 0 end,
    GetOwnedCount = function(_, id) return bags[id] or 0 end,
}
ns.Queue = { GetAll = function() return ns.db.queue end }

assert(loadfile(lfs_cwd .. "/Data/Auctions.lua"))("Blackthornes_TS", ns)
ns.Auctions.GetPostedCount = function() return 0 end

local A = ns.Auctions
local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

-- Nothing set by profession: the usual number, as before.
local limit, source = A:GetLimit(POTION)
check("no profession numbers: the usual 3", limit == 3 and source == "default")

check("an item's profession comes from the recipe that makes it",
    A:ProfessionOf(POTION) == "Alchemy" and A:ProfessionOf(SWORD) == "Blacksmithing"
        and A:ProfessionOf(BOLT) == "Tailoring" and A:ProfessionOf(999) == nil)

local list = A:StockProfessions()
check("Settings lists the professions that make things, sorted",
    #list == 3 and list[1] == "Alchemy" and list[2] == "Blacksmithing" and list[3] == "Tailoring")

-- Alchemy 10, Blacksmithing 2.
A:SetProfessionLimit("Alchemy", 10)
A:SetProfessionLimit("Blacksmithing", 2)
local profession
limit, source, profession = A:GetLimit(POTION)
check("a potion keeps Alchemy's 10", limit == 10 and source == "profession" and profession == "Alchemy")
check("a sword keeps Blacksmithing's 2", A:GetLimit(SWORD) == 2)
check("bolts, with no Tailoring number, keep the usual 3", A:GetLimit(BOLT) == 3)

bags[POTION] = 6
check("room under Alchemy's number", A:GetRoom(POTION) == 4)

-- An item's own number beats its profession's.
A:SetLimit(POTION, 20)
limit, source = A:GetLimit(POTION)
check("the item's own 20 wins", limit == 20 and source == "item")
check("room under the item's number", A:GetRoom(POTION) == 14)
A:SetLimit(POTION, nil)
check("clearing the item goes back to Alchemy's 10", A:GetLimit(POTION) == 10)

-- 0 for a profession is no limit for it, not "use the usual".
A:SetProfessionLimit("Blacksmithing", 0)
check("Blacksmithing at 0 is no limit", A:GetLimit(SWORD) == 0 and A:GetRoom(SWORD) == nil)
A:SetProfessionLimit("Blacksmithing", nil)
check("cleared, Blacksmithing uses the usual 3 again",
    A:GetLimit(SWORD) == 3 and A:GetProfessionLimit("Blacksmithing") == nil)

-- A profession given a number stays listed after its recipes are gone.
A:SetProfessionLimit("First Aid", 5)
list = A:StockProfessions()
check("a profession with a number stays listed", #list == 4 and list[3] == "First Aid")

-- New recipes are read in: the index follows.
ns.db.characters.bob.recipes[4] = { recipeID = 4, outputItemID = 400, skillLineID = 129 }
ns.db.characters.bob.recipesCachedAt = 2
check("a newly read recipe joins its profession", A:GetLimit(400) == 5)

-- Saved data is never renamed: the item numbers stay where they were.
check("item numbers stay in postLimits", ns.db.postLimits[POTION] == nil and type(ns.db.postLimits) == "table")
check("profession numbers saved by English name",
    ns.db.professionStockLimits.Alchemy == 10 and ns.db.professionStockLimits["First Aid"] == 5)

-- The export code carries them, spaces and all, and brings them back.
ns.L = setmetatable({ Format = string.format }, { __index = function(_, key) return key end })
assert(loadfile(lfs_cwd .. "/Logic/Transfer.lua"))("Blackthornes_TS", ns)
ns.Queue.Find = function() return nil end
ns.Queue.Add = function() end
A:SetLimit(SWORD, 7)
local code = ns.Transfer:Export()
check("the code names the professions", code:find("PAlchemy:10", 1, true) and code:find("PFirstAid:5", 1, true))
local _, _, limits = ns.Transfer:Describe()
check("Describe counts item and profession numbers", limits == 3)

ns.db.professionStockLimits = {}
ns.db.postLimits = {}
local ok = ns.Transfer:Import(code)
check("import brings them back",
    ok and A:GetProfessionLimit("Alchemy") == 10 and A:GetProfessionLimit("First Aid") == 5
        and A:GetLimit(SWORD) == 7)

print(("%d checks passed"):format(checks))
