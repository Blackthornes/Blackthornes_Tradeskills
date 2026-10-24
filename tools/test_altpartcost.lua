-- A part only an alt makes (2026-10-24): with "Alts Make Sub-Crafts"
-- ticked, Cost prices it at the alt's materials plus postage, not at what
-- buying it costs, and its line names the alt. A cooldown craft, one marked
-- never to make, an alt it can't mail and anything bound when picked up stay
-- at the buying price, and so does everything with the switch off.
--
-- Bob makes a Woolen Reagent Bag; his tailor Loom makes the bolts.
-- Drives the real Cost.lua, Queue.lua and Cooldowns.lua.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.L = setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

time = function() return 1000000 end

local BAG, BOLT, WOOL, DYE, THREAD, MOON, FEL = 5000, 2997, 2592, 3825, 2321, 14342, 14256
local BOB, LOOM, FARAWAY = "Player-BOB", "Player-LOOM", "Player-FAR"

local bound = {}
ns.BagsFull = { MaxStack = function() return 20 end }
ns.Util = { IsBoundOnPickup = function(itemID) return bound[itemID] == true end }

local settings = { valueOwnedMaterials = true, queueAltCrafting = true }
ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return BOB end,
}

local BAG_RECIPE = { recipeID = 10, name = "Woolen Reagent Bag", outputItemID = BAG,
    quantityMin = 1, quantityMax = 1,
    reagents = { { itemID = BOLT, quantity = 3 }, { itemID = DYE, quantity = 1 },
                 { itemID = THREAD, quantity = 1 } } }
local BOLT_RECIPE = { recipeID = 20, name = "Bolt of Woolen Cloth", outputItemID = BOLT,
    quantityMin = 1, quantityMax = 1, reagents = { { itemID = WOOL, quantity = 3 } } }
local ROBE_RECIPE = { recipeID = 30, name = "Mooncloth Robe", outputItemID = 6000,
    quantityMin = 1, quantityMax = 1, reagents = { { itemID = MOON, quantity = 4 } } }
local MOON_RECIPE = { recipeID = 18560, name = "Mooncloth", outputItemID = MOON,
    quantityMin = 1, quantityMax = 1, reagents = { { itemID = FEL, quantity = 2 } } }

local function fresh()
    ns.db = { characters = {
        [BOB] = { name = "Bob Wither", realm = "Forever", faction = "Horde",
            recipes = { [10] = BAG_RECIPE, [30] = ROBE_RECIPE } },
        [LOOM] = { name = "Loom Weaver", realm = "Forever", faction = "Horde",
            recipes = { [20] = BOLT_RECIPE, [18560] = MOON_RECIPE } },
    }, professionCooldowns = {} }
    bound = {}
    settings.queueAltCrafting = true
    ns.Cost:InvalidateIndex()
end

ns.Recipes = {
    GetAll = function() return ns.db.characters[BOB].recipes end,
    Get = function(self, id) return self:GetAll()[id] end,
    GetAny = function(self, id)
        local mine = self:GetAll()[id]
        if mine then return mine, BOB end
        for key, record in pairs(ns.db.characters) do
            if record.recipes[id] then return record.recipes[id], key end
        end
    end,
    GetCharacterName = function(_, key) return ns.db.characters[key].name end,
}

ns.Inventory = {
    GetBagCount = function() return 0 end,
    GetBankCount = function() return 0 end,
    GetOwnedCount = function() return 0 end,
}

local auction = { [BOLT] = 1030, [WOOL] = 295, [DYE] = 4885, [MOON] = 50000, [FEL] = 3000 }
ns.Prices = { GetValue = function(_, id) return auction[id] end }
ns.Vendor = {
    GetUnitPrice = function(_, id) return id == THREAD and 90 or nil end,
    IsLimited = function() return false end,
}

assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Cooldowns.lua"))("Blackthornes_TS", ns)

local Cost = ns.Cost

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function line(recipeID, itemID)
    local cost = Cost:GetCraftCost(recipeID)
    for _, reagent in ipairs((cost and cost.reagents) or {}) do
        if reagent.itemID == itemID then return reagent, cost end
    end
end

print("\nLoom's bolts are priced at their wool")

fresh()
local bolt = line(10, BOLT)
-- Three wool a bolt, and one stamp for the three bolts mailed over.
local expected = 3 * 295 + 30 / 3
check("each bolt costs its wool and its share of the stamp", math.abs(bolt.unitCost - expected) < 0.01)
check("it is a sub-craft", bolt.crafted == true and bolt.source == "craft")
check("made by Loom", bolt.madeBy == LOOM)
check("named whole", Cost.MadeByName(bolt.madeBy) == "Loom Weaver")

print("\nswitched off, nothing changes")

fresh()
settings.queueAltCrafting = false
bolt = line(10, BOLT)
check("the bolts are bought", bolt.unitCost == 1030 and not bolt.crafted and bolt.madeBy == nil)

print("\nMooncloth has a cooldown, so it stays at its price")

fresh()
local moon = line(30, MOON)
check("bought at the auction price", moon.unitCost == 50000 and moon.madeBy == nil)

print("\nnever made as a sub-craft")

fresh()
ns.db.neverSubCrafts = { [20] = "Bolt of Woolen Cloth" }
Cost:InvalidateIndex()
bolt = line(10, BOLT)
check("the bolts are bought", bolt.madeBy == nil and bolt.unitCost == 1030)
ns.db.neverSubCrafts = nil

print("\nan alt on the other side can't mail it")

fresh()
ns.db.characters[LOOM].faction = "Alliance"
Cost:InvalidateIndex()
check("the bolts are bought", line(10, BOLT).madeBy == nil)

print("\nbound when picked up")

fresh()
bound[BOLT] = true
check("the bolts are bought", line(10, BOLT).madeBy == nil)

print("\ndearer to make than to buy")

fresh()
auction[BOLT] = 500
check("the bolts are bought", line(10, BOLT).madeBy == nil and line(10, BOLT).unitCost == 500)
auction[BOLT] = 1030

print("\nBob learns the bolts himself")

fresh()
ns.db.characters[BOB].recipes[20] = BOLT_RECIPE
Cost:InvalidateIndex()
bolt = line(10, BOLT)
check("made here, no stamp", bolt.crafted and bolt.madeBy == nil and bolt.unitCost == 3 * 295)
ns.db.characters[BOB].recipes[20] = nil

print(("\n%d passed, 0 failed"):format(checks))
