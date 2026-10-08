-- A craft marked never to make as a sub-craft is bought instead.
--
-- Voldar on Discord (2026-10-07): scraps to light leather to medium to heavy
-- costs too much crafting time, and "Queue sub-crafts" is all or nothing.
-- Marking Cured Light Leather leaves the medium leather made, from bought
-- light leather, in the costs, the queue and the shopping list, on one
-- character and shared across characters. Allow brings it back.
--
-- Drives the real Cost.lua and Queue.lua.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end

local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end

time = function() return 1000000 end

local ARMOR, MEDIUM, LIGHT, SCRAP = 4000, 2319, 2318, 2934
local ME, ALT = "Player-ME", "Player-ALT"

ns.Util = { IsBoundOnPickup = function() return false end }

local settings = { valueOwnedMaterials = true }
ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return ME end,
}

local recipes = {
    [10] = { recipeID = 10, name = "Leather Vest", outputItemID = ARMOR, quantityMin = 1,
        reagents = { { itemID = MEDIUM, quantity = 2 } } },
    [20] = { recipeID = 20, name = "Cured Medium Leather", outputItemID = MEDIUM, quantityMin = 1,
        reagents = { { itemID = LIGHT, quantity = 4 } } },
    [30] = { recipeID = 30, name = "Cured Light Leather", outputItemID = LIGHT, quantityMin = 1,
        reagents = { { itemID = SCRAP, quantity = 3 } } },
}

ns.Recipes = {
    GetAll = function() return recipes end,
    Get = function(_, id) return recipes[id] end,
    GetAny = function(_, id) return recipes[id], ME end,
    GetCharacterName = function() return "Me" end,
}

local bags = {}
ns.Inventory = {
    GetBagCount = function(_, id) return bags[id] or 0 end,
    GetBankCount = function() return 0 end,
    GetMailCount = function() return 0 end,
    GetOwnedCount = function(_, id) return bags[id] or 0 end,
    GetAltTotal = function() return 0 end,
}

-- Scraps 10 each: light costs 30 to make, 100 to buy; medium 120 to make
-- from made light, 400 from bought light, 500 to buy.
local auction = { [SCRAP] = 10, [LIGHT] = 100, [MEDIUM] = 500 }
ns.Prices = { GetValue = function(_, id) return auction[id] end }
ns.Vendor = { GetUnitPrice = function() return nil end, IsLimited = function() return false end }

assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)

ns.Profit = { Analyse = function() return { priceable = false } end }

local Queue, Cost = ns.Queue, ns.Cost

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function entryFor(recipeID)
    for _, entry in ipairs(Queue:GetAll()) do
        if entry.recipeID == recipeID then return entry end
    end
end

local function row(itemID)
    for _, line in ipairs(Queue:GetShoppingList()) do
        if line.itemID == itemID then return line end
    end
end

local function start(characters)
    bags = {}
    printed = {}
    ns.db = { queue = {}, characters = characters
        or { [ME] = { name = "Me", realm = "Forever", recipes = recipes } } }
    Cost:InvalidateIndex()
    Queue:Add(10, 10)
end

print("\nthe cost engine")

start()
check("the vest costs made leather all the way down", Cost:GetCraftCost(10).total == 240)
check("nothing is marked", Cost:IsNeverSubCraft(30) == false and #Cost:GetNeverSubCrafts() == 0)
Cost:SetNeverSubCraft(30, true)
check("marked, the medium leather is made from bought light leather",
    Cost:GetCraftCost(20).total == 400 and not Cost:GetCraftCost(20).reagents[1].crafted)
check("so the vest costs 800", Cost:GetCraftCost(10).total == 800)
check("Settings lists it by name, with the item it makes", #Cost:GetNeverSubCrafts() == 1
    and Cost:GetNeverSubCrafts()[1].name == "Cured Light Leather"
    and Cost:GetNeverSubCrafts()[1].outputItemID == LIGHT)
check("the light leather says why it is bought", Cost:NeverMadeRecipeFor(LIGHT) == 30)
check("light leather can still be costed and queued on its own", Cost:GetCraftCost(30).total == 30)
check("saved by recipe, with its name", ns.db.neverSubCrafts[30] == "Cured Light Leather")
Cost:SetNeverSubCraft(30, false)
check("allowed again, made again", Cost:GetCraftCost(10).total == 240 and ns.db.neverSubCrafts[30] == nil)

for _, mode in ipairs({ "one character", "shared with alts" }) do
    settings.queueAltCrafting = mode == "shared with alts"

    print(("\nthe queue, %s"):format(mode))

    start()
    check("light leather is made at first", entryFor(30) and entryFor(30).quantity == 80)

    -- Marking it rebuilds the queue straight away.
    Cost:SetNeverSubCraft(30, true)
    check("marked, light leather leaves the queue", entryFor(30) == nil)
    check("medium leather is still made", entryFor(20) and entryFor(20).quantity == 20)
    check("light leather is on the shopping list", row(LIGHT) and row(LIGHT).shortfall == 80)
    check("no scraps are bought for it", row(SCRAP) == nil)
    Queue:RebuildDependencies()
    check("and it stays off", entryFor(30) == nil)

    print(("\nthe x on a queued sub-craft, %s"):format(mode))

    Cost:SetNeverSubCraft(30, false)
    check("allowed again, it comes back", entryFor(30) and entryFor(30).quantity == 80)
    check("the x never makes it", Queue:NeverMake(entryFor(30)) == true and entryFor(30) == nil)
    check("one line in chat says how to undo it",
        printed[#printed]:find("Never made as sub-crafts", 1, true) ~= nil)
    check("the x does nothing on a craft you queued", Queue:NeverMake(entryFor(10)) == false)
    Cost:SetNeverSubCraft(30, false)

    print(("\na kept sub-craft that is marked, %s"):format(mode))

    -- Kept after buying turned cheaper, then marked: it goes too.
    auction[MEDIUM] = 100
    Queue:RebuildDependencies()
    check("medium leather is kept, buying cheaper", entryFor(20) and entryFor(20).buyCheaper)
    Cost:SetNeverSubCraft(20, true)
    check("marked, it leaves with the light leather", entryFor(20) == nil and entryFor(30) == nil)
    check("medium leather is bought", row(MEDIUM) and row(MEDIUM).shortfall == 20)
    Cost:SetNeverSubCraft(20, false)
    auction[MEDIUM] = 500
end

print("\nanother character who could make it")

-- The alt knows the light leather too. Marked, it is not offered there
-- either: the mark is the recipe's, on every character.
settings.queueAltCrafting = false
local mine = { [10] = recipes[10], [20] = recipes[20] }
start({
    [ME] = { name = "Me", realm = "Forever", recipes = mine },
    [ALT] = { name = "Alt", realm = "Forever", recipes = { [30] = recipes[30] } },
})
local savedAll = ns.Recipes.GetAll
ns.Recipes.GetAll = function() return mine end
Cost:InvalidateIndex()
check("unmarked, the alt is suggested for the light leather",
    Queue:GetAltCraftOffer(LIGHT, 80, 100) ~= nil)
Cost:SetNeverSubCraft(30, true)
check("marked, it is not", Queue:GetAltCraftOffer(LIGHT, 80, 100) == nil)

settings.queueAltCrafting = true
Queue:RebuildDependencies()
check("nor handed to the alt when alts make sub-crafts", entryFor(30) == nil)
Cost:SetNeverSubCraft(30, false)
check("allowed, the alt makes it", entryFor(30) and entryFor(30).crafter == ALT)
ns.Recipes.GetAll = savedAll
settings.queueAltCrafting = nil

print(("\n%d checks passed"):format(checks))
