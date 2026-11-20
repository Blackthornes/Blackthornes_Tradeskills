-- A player on Discord (2026-11-20): an alchemist who knows Iron to Gold saw
-- every craft with a Gold Bar priced as if the bars cost their iron, and
-- the queue planned as many transmutes as it liked, though each has a
-- cooldown. A craft with a cooldown is now left out of the character
-- playing's sub-crafts, as it already was for alts: its item is priced at
-- what buying it costs, and the queue buys it. Set to Make on the Level Up
-- tab, it is still made.
--
-- Drives the real Cost.lua, Queue.lua and Cooldowns.lua.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.L = setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

time = function() return 1000000 end

local ROD, GOLD, IRON, STONE, HAMMER, BAR, COPPER = 6000, 3577, 3575, 2835, 6100, 6200, 2840
local ME = "Player-ME"

ns.BagsFull = { MaxStack = function() return 20 end }
ns.Util = { IsBoundOnPickup = function() return false end }

local settings = { valueOwnedMaterials = true, queueAltCrafting = false }
ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return ME end,
}

local ROD_RECIPE = { recipeID = 10, name = "Golden Rod", outputItemID = ROD,
    quantityMin = 1, quantityMax = 1,
    reagents = { { itemID = GOLD, quantity = 1 }, { itemID = STONE, quantity = 2 } } }
local TRANSMUTE = { recipeID = 11479, name = "Transmute: Iron to Gold", outputItemID = GOLD,
    quantityMin = 1, quantityMax = 1, reagents = { { itemID = IRON, quantity = 1 } } }
-- A craft Forever put on a cooldown, known only because it was seen waiting.
local HAMMER_RECIPE = { recipeID = 40, name = "Hammer", outputItemID = HAMMER,
    quantityMin = 1, quantityMax = 1, reagents = { { itemID = BAR, quantity = 1 } } }
local BAR_RECIPE = { recipeID = 50, name = "Seen Bar", outputItemID = BAR,
    quantityMin = 1, quantityMax = 1, reagents = { { itemID = COPPER, quantity = 1 } } }

local function fresh()
    ns.db = { characters = {
        [ME] = { name = "Ana Lyst", realm = "Forever", faction = "Horde",
            recipes = { [10] = ROD_RECIPE, [11479] = TRANSMUTE, [40] = HAMMER_RECIPE, [50] = BAR_RECIPE } },
    }, professionCooldowns = {} }
    ns.Cost:InvalidateIndex()
end

ns.Recipes = {
    GetAll = function() return ns.db.characters[ME].recipes end,
    Get = function(self, id) return self:GetAll()[id] end,
    GetAny = function(self, id) return self:GetAll()[id], ME end,
    GetAccountWide = function(self) return self:GetAll() end,
    GetCharacterName = function(_, key) return ns.db.characters[key].name end,
}

ns.Inventory = {
    GetBagCount = function() return 0 end,
    GetBankCount = function() return 0 end,
    GetOwnedCount = function() return 0 end,
}

local auction = { [GOLD] = 28000, [IRON] = 4500, [STONE] = 60, [BAR] = 9000, [COPPER] = 100 }
ns.Prices = { GetValue = function(_, id) return auction[id] end }
ns.Vendor = {
    GetUnitPrice = function() return nil end,
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

print("\na transmute is not a cheap way to a Gold Bar")

fresh()
local gold, cost = line(10, GOLD)
check("the bar is priced at what it costs to buy", gold.unitCost == 28000)
check("it is bought, not a sub-craft", gold.source == "buy" and not gold.crafted)
check("the rod costs the bar and the stone", cost.total == 28000 + 2 * 60)
check("no sub-craft offered for the bar", Cost:FindRecipeForItem(GOLD) == nil)
check("the transmute is still priced as itself", Cost:GetCraftCost(11479).total == 4500)
check("and still names what makes a Gold Bar for selling", Cost:FindAnyRecipeForItem(GOLD) == 11479)

print("\na craft seen waiting on a cooldown is left out too")

fresh()
local bar = line(40, BAR)
check("before it is seen, the bar is made", bar.crafted == true and bar.unitCost == 100)
ns.db.professionCooldowns[ME] = { ["spell:50"] = { recipeID = 50, seen = true } }
Cost:InvalidateIndex()
bar = line(40, BAR)
check("once seen, it is bought", not bar.crafted and bar.unitCost == 9000)

print("\nset to Make on the Level Up tab, it is still made")

fresh()
Cost:SetSubCraftChoice(11479, "make", "Transmute: Iron to Gold")
gold = line(10, GOLD)
check("the bar is made from its iron", gold.crafted == true and gold.unitCost == 4500)
check("and offered as a sub-craft", Cost:FindRecipeForItem(GOLD) == 11479)

print(("\n%d checks passed"):format(checks))
