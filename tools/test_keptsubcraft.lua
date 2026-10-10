-- A sub-craft already planned stays when buying turns cheaper.
--
-- On Discord (2026-10-05): ten crafts queued, the scraps bought, and
-- halfway through turning scraps into light leather, medium leather became
-- cheaper to buy than to make. The queue dropped the medium leather, and the
-- light leather with it, so the leather already made had nothing to go into
-- and the rest had to be queued by hand. Now the plan stays, the row says
-- buying is cheaper, and Buy instead takes it off.
--
-- Drives the real Cost.lua and Queue.lua, with sub-crafts planned for one
-- character and shared across characters.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end

local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end

time = function() return 1000000 end

local ARMOR, MEDIUM, LIGHT, SCRAP = 4000, 2319, 2318, 2934
local ME = "Player-ME"

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
    [40] = { recipeID = 40, name = "Leather Boots", outputItemID = 4001, quantityMin = 1,
        reagents = { { itemID = LIGHT, quantity = 2 } } },
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

-- Scraps 10 each: light costs 30 to make, medium 120. Both cost more to buy.
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

local function start()
    auction[MEDIUM], auction[LIGHT] = 500, 100
    bags = {}
    printed = {}
    ns.db = { queue = {}, characters = { [ME] = { name = "Me", realm = "Forever", recipes = recipes } } }
    Cost:InvalidateIndex()
    Queue:Add(10, 10)
end

for _, mode in ipairs({ "one character", "shared with alts" }) do
    settings.queueAltCrafting = mode == "shared with alts"

    print(("\nthe plan, %s"):format(mode))

    start()
    check("medium leather is made", entryFor(20) and entryFor(20).quantity == 20)
    check("light leather is made", entryFor(30) and entryFor(30).quantity == 80)
    check("neither says buying is cheaper", not entryFor(20).buyCheaper and not entryFor(30).buyCheaper)
    check("the scraps are on the list", row(SCRAP) and row(SCRAP).shortfall == 240)

    print(("\nhalfway, medium leather turns cheaper to buy, %s"):format(mode))

    -- 40 light made from 120 of the 240 scraps.
    bags = { [SCRAP] = 120, [LIGHT] = 40 }
    auction[MEDIUM] = 100
    Queue:RebuildDependencies()

    local medium = entryFor(20)
    check("medium leather stays on the queue", medium and medium.quantity == 20)
    check("and says buying is cheaper", medium.buyCheaper == true)
    check("the rest of the light leather stays", entryFor(30) and entryFor(30).quantity == 40)
    check("light leather is still cheaper to make", not entryFor(30).buyCheaper)
    check("medium leather is not on the shopping list", row(MEDIUM) == nil)
    check("nor is light leather to buy", row(LIGHT) == nil or row(LIGHT).shortfall == 0)
    check("the scraps already bought cover the rest", row(SCRAP) and row(SCRAP).shortfall == 0)
    check("one line in chat says so", #printed == 1 and printed[1]:find("now cheaper", 1, true))

    local buy, make = Queue:GetBuyOrMake(medium)
    check("the note can show both prices", buy == 100 and make == 120)

    Queue:RebuildDependencies()
    check("said once, not on every rebuild", #printed == 1)

    print(("\nBuy instead, %s"):format(mode))

    check("Buy instead takes it off", Queue:BuyInstead(entryFor(20)) == true)
    check("medium leather is gone", entryFor(20) == nil)
    check("and the light leather that only went into it", entryFor(30) == nil)
    check("medium leather is on the shopping list", row(MEDIUM) and row(MEDIUM).shortfall == 20)
    Queue:RebuildDependencies()
    check("and it does not come back", entryFor(20) == nil)
    check("the vest stays", entryFor(10) and entryFor(10).quantity == 10)

    print(("\nonly what was planned stays, %s"):format(mode))

    -- Queued when buying was already cheaper: bought, as before.
    auction[MEDIUM] = 100
    bags = {}
    ns.db.queue = {}
    Queue:Add(10, 10)
    check("medium leather is bought", entryFor(20) == nil and row(MEDIUM) and row(MEDIUM).shortfall == 20)

    -- Making turns cheaper again: made, and not marked.
    auction[MEDIUM] = 500
    Queue:RebuildDependencies()
    check("made again once cheaper", entryFor(20) and not entryFor(20).buyCheaper)

    print(("\nBuy instead on one of two rows of the same sub-craft, %s"):format(mode))

    -- Light leather goes into the medium leather and straight into the
    -- boots, so the queue holds two light leather rows at different depths.
    -- Buy instead on one took it off, but the other kept it planned and the
    -- rebuild put it straight back: the button seemed to do nothing.
    auction[MEDIUM], auction[LIGHT] = 500, 100
    bags = {}
    ns.db.queue = {}
    Cost:InvalidateIndex()
    Queue:Add(10, 10)
    Queue:Add(40, 5)
    local lightRows = 0
    for _, entry in ipairs(Queue:GetAll()) do
        if entry.recipeID == 30 then lightRows = lightRows + 1 end
    end
    check("light leather is planned", lightRows >= 1)

    auction[LIGHT] = 20
    Queue:RebuildDependencies()
    check("light leather says buying is cheaper", entryFor(30) and entryFor(30).buyCheaper == true)

    check("Buy instead takes it off", Queue:BuyInstead(entryFor(30)) == true)
    check("no light leather row is left", entryFor(30) == nil)
    check("light leather is on the shopping list", row(LIGHT) and row(LIGHT).shortfall > 0)
    Queue:RebuildDependencies()
    check("and it does not come back", entryFor(30) == nil)
    check("the medium leather stays", entryFor(20) ~= nil)

    -- A row clicked before its redraw holds the sub-craft from before the
    -- last rebuild; it still takes the queued one off.
    auction[LIGHT] = 100
    Queue:RebuildDependencies()
    auction[LIGHT] = 20
    Queue:RebuildDependencies()
    local stale = entryFor(30)
    check("light leather is back while making is planned", stale ~= nil)
    Queue:RebuildDependencies()
    check("a rebuild makes a new row", entryFor(30) ~= stale)
    check("Buy instead on the old row still works", Queue:BuyInstead(stale) == true)
    check("no light leather row is left after", entryFor(30) == nil)
end

print(("\n%d checks passed"):format(checks))
