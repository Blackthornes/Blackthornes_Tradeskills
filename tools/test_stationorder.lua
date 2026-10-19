-- Bars are smelted all at once, outside WoW (a player's report, 2026-10-19:
-- the queue went bars, a craft, then more bars, so it was forge, anvil and
-- back to the forge).
--
-- What must hold:
--   1. A material needed at two levels is one queue row, at the deeper
--      level, not two rows with a craft between them.
--   2. What you hold of it is counted once across the levels, so enough
--      is queued the first time.
--   3. Sub-crafts are grouped by profession, the one that feeds another
--      first: every bar before the Blacksmithing parts.
--   4. Craft next stays with that first group while it has something
--      ready, even when a part from the next group frees more bag space.
--   5. A craft never comes before a sub-craft of its own.

local GLOBALS = { "GetTime", "time", "C_Timer" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end
GetTime = function() return 100 end
time = function() return 100000 end
C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.RegisterEvent = noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.Util = { HasFunction = function() return false end, IsBoundOnPickup = function() return false end }
local config = {}
ns.Config = { Get = function(_, key) return config[key] end, GetCharacterKey = function() return "me" end }

local MINING, BS, ENG = 2946, 2938, 2941

-- Items.
local ORE, BAR, BOLTS, MODULATOR = 1, 2, 3, 4
local IRON_ORE, IRON, COAL, STEEL, BUCKLE, BELT = 11, 12, 13, 14, 15, 16
local STONE, GRIT, PLATE, HELM = 21, 22, 23, 24

local RECIPES = {
    -- Copper Modulator: bolts and a bar; the bolts need a bar too.
    [100] = { name = "Copper Bar", skillLineID = MINING, outputItemID = BAR,
        reagents = { { itemID = ORE, quantity = 1 } } },
    [101] = { name = "Copper Bolts", skillLineID = ENG, outputItemID = BOLTS,
        reagents = { { itemID = BAR, quantity = 1 } } },
    [102] = { name = "Copper Modulator", skillLineID = ENG, outputItemID = MODULATOR,
        reagents = { { itemID = BOLTS, quantity = 2 }, { itemID = BAR, quantity = 1 } } },

    -- A belt from a buckle and a steel bar; both need iron.
    [200] = { name = "Iron Bar", skillLineID = MINING, outputItemID = IRON,
        reagents = { { itemID = IRON_ORE, quantity = 1 } } },
    [201] = { name = "Steel Bar", skillLineID = MINING, outputItemID = STEEL,
        reagents = { { itemID = IRON, quantity = 1 }, { itemID = COAL, quantity = 1 } } },
    [202] = { name = "Iron Buckle", skillLineID = BS, outputItemID = BUCKLE,
        reagents = { { itemID = IRON, quantity = 1 } } },
    [203] = { name = "Belt", skillLineID = BS, outputItemID = BELT,
        reagents = { { itemID = BUCKLE, quantity = 1 }, { itemID = STEEL, quantity = 1 } } },

    -- A helm from a plate (made from grit, deeper) and an iron bar.
    [300] = { name = "Grit", skillLineID = BS, outputItemID = GRIT,
        reagents = { { itemID = STONE, quantity = 1 } } },
    [301] = { name = "Plate", skillLineID = BS, outputItemID = PLATE,
        reagents = { { itemID = GRIT, quantity = 1 } } },
    [302] = { name = "Helm", skillLineID = BS, outputItemID = HELM,
        reagents = { { itemID = PLATE, quantity = 1 }, { itemID = IRON, quantity = 1 } } },
}
local MAKES = {}
for id, recipe in pairs(RECIPES) do MAKES[recipe.outputItemID] = id end

ns.Recipes = {
    GetAny = function(_, id) return RECIPES[id], "me" end,
    SKILL_LINE_PROFESSIONS = { [MINING] = "Mining", [BS] = "Blacksmithing", [ENG] = "Engineering" },
}

local bags = {}
ns.Inventory = {
    changes = 0,
    GetBagCount = function(_, id) return bags[id] or 0 end,
    GetOwnedCount = function(_, id) return bags[id] or 0 end,
    GetMailCount = function() return 0 end,
}
ns.Profit = {
    GetCraftableCount = function(_, id)
        local can = math.huge
        for _, r in ipairs(RECIPES[id].reagents) do
            can = math.min(can, math.floor((bags[r.itemID] or 0) / r.quantity))
        end
        return can
    end,
}
ns.BagsFull = { MaxStack = function() return 20 end }
ns.Cost = {
    GetCraftCost = function(_, id)
        local reagents = {}
        for _, r in ipairs(RECIPES[id].reagents) do
            reagents[#reagents + 1] = { itemID = r.itemID, quantity = r.quantity,
                crafted = MAKES[r.itemID] ~= nil }
        end
        return { reagents = reagents }
    end,
    FindRecipeForItem = function(_, itemID) return MAKES[itemID] end,
}
ns.db = { queue = {} }

assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Crafting.lua"))("Blackthornes_TS", ns)
local Queue, Crafting = ns.Queue, ns.Crafting
Queue.Notify = noop
Queue.GetAll = function() return ns.db.queue end
Crafting.GetReadiness = function(_, id) return ns.Profit:GetCraftableCount(id) > 0 end

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-62s %-28s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Order()
    local names = {}
    for _, entry in ipairs(ns.db.queue) do
        names[#names + 1] = RECIPES[entry.recipeID].name .. " x" .. entry.quantity
    end
    return table.concat(names, ", ")
end

local function Queued(id, quantity)
    ns.db.queue = { { recipeID = id, quantity = quantity } }
    Queue:RebuildDependencies()
end

local function Count(id)
    local rows = 0
    for _, entry in ipairs(ns.db.queue) do if entry.recipeID == id then rows = rows + 1 end end
    return rows
end

print("a bar needed at two levels")
bags = {}
Queued(102, 1)
check("one Copper Bar row", Count(100), 1)
check("bars first, then bolts, then the modulator", Order(),
    "Copper Bar x3, Copper Bolts x2, Copper Modulator x1")

print("bars you hold are counted once")
bags = { [BAR] = 2 }
Queued(102, 1)
check("one more bar to smelt", Order(), "Copper Bar x1, Copper Bolts x2, Copper Modulator x1")

print("every bar before the anvil")
bags = {}
Queued(203, 1)
check("iron, steel, then the buckle", Order(),
    "Iron Bar x2, Steel Bar x1, Iron Buckle x1, Belt x1")

print("Craft next stays at the forge")
-- The buckle joins a stack you have and the steel takes a new slot, so
-- bag space alone would pick the buckle.
bags = { [IRON] = 2, [COAL] = 2, [BUCKLE] = 1 }
ns.Inventory.changes = ns.Inventory.changes + 1
-- Queue as it stood before the bars were made.
ns.db.queue = {
    { recipeID = 200, quantity = 2, isDependency = true, forRecipes = { [201] = true, [202] = true }, depth = 1 },
    { recipeID = 201, quantity = 1, isDependency = true, forRecipes = { [203] = true }, depth = 0 },
    { recipeID = 202, quantity = 1, isDependency = true, forRecipes = { [203] = true }, depth = 0 },
    { recipeID = 203, quantity = 1 },
}
local entry = Crafting:GetNextReady()
check("steel next, not the buckle", entry and RECIPES[entry.recipeID].name, "Steel Bar")
config.craftFreesSpaceFirst = false
entry = Crafting:GetNextReady()
check("in queue order too", entry and RECIPES[entry.recipeID].name, "Steel Bar")
config.craftFreesSpaceFirst = nil

print("a bar before deeper parts of another profession")
bags = {}
Queued(302, 1)
check("iron first, then grit and plate", Order(), "Iron Bar x1, Grit x1, Plate x1, Helm x1")

print("never before its own sub-craft")
local seen, fine = {}, true
for _, row in ipairs(ns.db.queue) do
    for _, r in ipairs(RECIPES[row.recipeID].reagents) do
        local maker = MAKES[r.itemID]
        if maker and not seen[maker] and Count(maker) > 0 then fine = false end
    end
    seen[row.recipeID] = true
end
check("every part comes after what it is made from", fine, true)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then error(failed .. " station order check(s) failed") end
