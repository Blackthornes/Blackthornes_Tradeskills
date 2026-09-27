-- "Suggest other characters": a material this character has to buy that one
-- of your other characters can make for less is pointed out, and nothing else
-- changes.
--
-- Trent's Woolen Reagent Bag again, but the tailor who knows Bolt of Woolen
-- Cloth is an alt. The character at the auction house cannot make bolts, so
-- the cost engine buys them at 10s 30c each. The alt can make one from 3 Wool
-- Cloth at 2s 95c, 8s 85c a bolt, so swapping saves 1s 45c a bolt.
--
-- Drives the real Cost.lua and Queue.lua.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

time = time or os.time

local BAG, BOLT, WOOL, DYE, THREAD = 5000, 2997, 2592, 3825, 2321

local bound = {}
ns.Util = { IsBoundOnPickup = function(itemID) return bound[itemID] == true end }

local settings = { valueOwnedMaterials = true, suggestOtherCharacters = false }
local currentKey = "Player-ME"
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
        ["Player-ME"] = { name = "Blackthornes", surname = "Wither", recipes = { [10] = BAG_RECIPE } },
        ["Player-ALT"] = { name = "Blackthornes", surname = "Loom", recipes = { [20] = BOLT_RECIPE } },
    }
end

ns.Recipes = {
    GetAll = function()
        local record = ns.db.characters[currentKey]
        return record and record.recipes or {}
    end,
    GetAny = function(self, id)
        local mine = self:GetAll()[id]
        if mine then return mine, currentKey end
        for key, record in pairs(ns.db.characters) do
            if record.recipes[id] then return record.recipes[id], key end
        end
    end,
    GetCharacterName = function(_, key)
        local record = ns.db.characters[key]
        return record.name .. " " .. record.surname
    end,
    GetCharacters = function(self)
        local list = {}
        for key in pairs(ns.db.characters) do
            list[#list + 1] = { key = key, name = self:GetCharacterName(key) }
        end
        return list
    end,
}

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

ns.Profit = { Analyse = function() return { priceable = false } end }

local Queue, Cost = ns.Queue, ns.Cost

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

local function queueOneBag()
    Cost:InvalidateIndex()
    ns.db = { queue = {}, characters = freshCharacters() }
    Queue:Add(10, 1)
end

print("\nsetting unticked")

queueOneBag()
check("the bolts are bought, as before", row(BOLT) and row(BOLT).shortfall == 3)
check("no swap is suggested", row(BOLT).altCraft == nil)

print("\nsetting on, the alt makes them for less")

settings.suggestOtherCharacters = true
queueOneBag()
local offer = row(BOLT) and row(BOLT).altCraft
check("a swap is suggested", offer ~= nil)
check("to the alt, by first and last name", offer.characterName == "Blackthornes Loom"
    and offer.characterKey == "Player-ALT")
check("for three bolt crafts", offer.crafts == 3 and offer.recipeID == 20)
check("at 8s 85c a bolt", offer.unitCost == 885)
check("saving 4s 35c on the three (got " .. tostring(offer.saving) .. ")", offer.saving == 435)
check("the shopping list still says buy them", row(BOLT).shortfall == 3
    and Queue:GetShoppingTotal() == 3090 + 4885 + 90)
check("no bolt craft is queued on this character", Queue:Find(20) == nil)
check("nothing is suggested for the wool, dye or thread",
    row(DYE).altCraft == nil and row(THREAD).altCraft == nil)

print("\nbuying is cheaper")

auction[WOOL] = 400
queueOneBag()
check("no swap is suggested when it would cost more", row(BOLT).altCraft == nil)
auction[WOOL] = 295

print("\nnobody sells bolts")

auction[BOLT] = nil
queueOneBag()
offer = row(BOLT).altCraft
check("the alt is still suggested, with no saving to quote", offer and offer.saving == nil)
auction[BOLT] = 1030

print("\nthe bolt binds on pickup")

bound[BOLT] = true
queueOneBag()
check("not suggested, since it could not be mailed", row(BOLT).altCraft == nil)
bound[BOLT] = nil

print("\nowned already")

bags[BOLT] = 3
queueOneBag()
check("nothing to buy, nothing suggested", row(BOLT).shortfall == 0 and row(BOLT).altCraft == nil)
bags[BOLT] = nil

print("\nthis character knows the bolt too")

Cost:InvalidateIndex()
ns.db = { queue = {}, characters = freshCharacters() }
ns.db.characters["Player-ME"].recipes[20] = BOLT_RECIPE
Queue:Add(10, 1)
check("the bolts are queued here instead, no swap needed", row(BOLT) == nil
    and Queue:Find(20) ~= nil)


print("\nnever touched, so on by default")

settings.suggestOtherCharacters = nil
queueOneBag()
check("a swap is suggested with the setting unset", row(BOLT).altCraft ~= nil)

print("\nlogging in on the tailor")

settings.suggestOtherCharacters = true
Cost:InvalidateIndex()
ns.db = { queue = {}, characters = freshCharacters() }
Queue:Add(10, 1)
check("on the bag maker, the bolts are to buy", row(BOLT) and row(BOLT).altCraft ~= nil
    and Queue:Find(20) == nil)

currentKey = "Player-ALT"
Cost:InvalidateIndex()
local added = Queue:RefreshForCharacter()
local _, bolts = Queue:Find(20)
check("the bolt crafts are queued on the tailor", bolts and bolts.isDependency and bolts.quantity == 3)
check("and announced as new", #added == 1 and added[1].recipeID == 20)
check("the wool to make them is on the shopping list", row(WOOL) and row(WOOL).shortfall == 9)
check("the bolts are not also to buy", row(BOLT) == nil)
check("the bag is still queued", Queue:Find(10, true) ~= nil)

check("a second refresh announces nothing", #Queue:RefreshForCharacter() == 0)

currentKey = "Player-ME"
Cost:InvalidateIndex()
Queue:RefreshForCharacter()
check("back on the bag maker, the bolt crafts are gone", Queue:Find(20) == nil)
check("and the bolts are to buy again, with the swap suggested", row(BOLT)
    and row(BOLT).shortfall == 3 and row(BOLT).altCraft ~= nil)

print(("\n%d check(s) passed\n"):format(checks))
