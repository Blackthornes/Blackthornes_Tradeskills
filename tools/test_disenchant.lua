-- Disenchant values, on the Profit tab and the Enchanting tab.
--
-- A player asked for disenchant values on the Profit tab (2026-09-27), and
-- Trent thought a tab of its own would help. The game does not tell addons
-- what an item breaks into, so Logic/Disenchant.lua carries the Classic
-- table. What this pins down:
--   * which items can be disenchanted at all;
--   * the expected value, including a weapon giving mostly essence;
--   * a material with no price leaves the value partial, and none priced
--     leaves no value rather than a zero;
--   * the Profit tab says when disenchanting beats selling, without the
--     ranking moving;
--   * the Enchanting tab's craft and bag lists, soulbound crafts included.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn =
    function() end, function() end, function() end, function() end

-- Put back at the end: every suite shares one Lua runtime.
local saved = { C_Item = C_Item, GetTime = GetTime, CreateFrame = CreateFrame }

-- Core/Util.lua builds a worker frame at load time; it only has to exist.
CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize" }) do
        frame[name] = function() end
    end
    return frame
end

GetTime = function() return 1 end
time = time or os.time

local STRANGE_DUST, LESSER_ASTRAL, SMALL_GLIMMERING = 10940, 10998, 10978
local SMALL_GLOWING, NEXUS = 11138, 20725

-- itemID -> quality, itemLevel, equipLoc, classID, bindType, sellPrice
local items = {
    [1001] = { 2, 22, "INVTYPE_CHEST", 4, 2, 50 },    -- green armour
    [1002] = { 2, 22, "INVTYPE_WEAPON", 2, 2, 50 },   -- green weapon
    [1003] = { 3, 33, "INVTYPE_FEET", 4, 2, 50 },     -- blue armour
    [1004] = { 4, 58, "INVTYPE_HEAD", 4, 1, 50 },     -- epic
    [1005] = { 1, 22, "INVTYPE_CHEST", 4, 0, 50 },    -- white: cannot
    [1006] = { 2, 22, "INVTYPE_BODY", 4, 2, 50 },     -- a shirt: cannot
    [1007] = { 2, 22, "", 7, 0, 50 },                 -- trade goods: cannot
    [1008] = { 2, 22, "INVTYPE_CHEST", 4, 1, 500 },   -- green, bind on pickup
    [1009] = { 2, 20, "INVTYPE_RANGEDRIGHT", 2, 0, 50 }, -- a green wand from a mob: can
    [11288] = { 2, 21, "INVTYPE_RANGEDRIGHT", 2, 0, 50, "Greater Magic Wand" },
    [1010] = { 2, 31, "INVTYPE_RANGEDRIGHT", 2, 0, 50, "Lesser Mystic Wand" },
}

C_Item = {
    GetItemInfo = function(itemID)
        local item = items[itemID]
        if not item then return nil end
        return item[7] or ("item" .. itemID), nil, item[1], item[2], 1, "Armor", "Cloth", 1,
            item[3], 1, item[6], item[4], 1, item[5]
    end,
}

local prices = {
    [STRANGE_DUST] = 100, [LESSER_ASTRAL] = 1000, [SMALL_GLIMMERING] = 2000,
    [1001] = 700,    -- worth less sold than disenchanted (800)
    [1002] = 5000,   -- worth more sold than disenchanted (1400)
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)

local recipes = {}
for _, itemID in ipairs({ 1001, 1002, 1005, 1008 }) do
    recipes[itemID] = { recipeID = itemID, name = "craft" .. itemID, outputItemID = itemID,
                        reagents = {}, quantityMin = 1 }
end

ns.Config = {
    Get = function(_, key)
        if key == "auctionCut" then return 0.05 end
        if key == "minProfit" then return 0 end
        return nil
    end,
    GetCharacterKey = function() return "Tester-Realm" end,
}
ns.Recipes = {
    GetAll = function() return recipes end,
    GetAny = function(_, recipeID) return recipes[recipeID], "Tester-Realm" end,
    GetCharacterName = function() return "Tester" end,
    Count = function() return 4 end,
}
ns.Cost = {
    GetCraftCost = function() return { priceable = true, total = 100, perUnit = 100, yield = 1 } end,
    FindRecipeForItem = function(_, itemID) return itemID end,
    GetMaterialValue = function() return nil end,
}
ns.Prices = {
    GetValue = function(_, itemID, which)
        -- Materials are priced at their lowest posting.
        if ns.Disenchant and ns.Disenchant:IsMaterial(itemID) then assert(which == "lowest", which) end
        return prices[itemID]
    end,
    Get = function(_, itemID) return prices[itemID] and { min = prices[itemID] } or nil end,
    HoldsLowest = function() return false end,
    GetConfidence = function() return 1 end,
    GetLiquidity = function() return nil end,
    IsStale = function() return false end,
    GetAge = function() return 0 end,
}
ns.Scanner = { GetCommodityStatus = function() return true end }
ns.Posting = { GetCachedUnitDeposit = function() return nil end }
ns.Auctions = { GetRoom = function() return nil, 0, 0, 0, nil, 0 end }

local bags = { [1001] = 2, [1002] = 1, [1005] = 3, [STRANGE_DUST] = 7 }
ns.Inventory = {
    GetCharacterBagCount = function() return 0 end,
    GetBagCounts = function() return bags end,
    GetBagCount = function(_, itemID) return bags[itemID] or 0 end,
}

assert(loadfile(lfs_cwd .. "/Logic/SkillUp.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Disenchant.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)

ns.SkillUp.GetForRecipe = function() return nil end

local Disenchant, Profit = ns.Disenchant, ns.Profit

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\nwhat can be disenchanted")

check("green armour can", Disenchant:IsDisenchantable(1001) == true)
check("a green weapon can", Disenchant:IsDisenchantable(1002) == true)
check("blue and purple can", Disenchant:IsDisenchantable(1003) and Disenchant:IsDisenchantable(1004))
check("a white item cannot", Disenchant:IsDisenchantable(1005) == false)
check("a shirt cannot", Disenchant:IsDisenchantable(1006) == false)
check("trade goods cannot", Disenchant:IsDisenchantable(1007) == false)
check("a wand from a mob can", Disenchant:IsDisenchantable(1009) == true)
check("a wand made by Enchanting cannot", Disenchant:IsDisenchantable(11288) == false)
check("nor one the client numbers differently", Disenchant:IsDisenchantable(1010) == false)
check("so it has no disenchant value", Disenchant:GetValue(11288) == nil)
check("an uncached item is unknown, not false", Disenchant:IsDisenchantable(99999) == nil)

print("\nwhat it breaks into")

local armour, facts = Disenchant:GetOutcomes(1001)
check("level 22 green armour gives three things", #armour == 3)
check("mostly Strange Dust, 4 to 6", armour[1].itemID == STRANGE_DUST and armour[1].chance == 0.75
    and armour[1].min == 4 and armour[1].max == 6)
check("then Lesser Astral Essence", armour[2].itemID == LESSER_ASTRAL and armour[2].chance == 0.15)
check("then a Small Glimmering Shard", armour[3].itemID == SMALL_GLIMMERING and armour[3].chance == 0.10)
check("and needs Enchanting 25", facts.skill == 25)

local weapon = Disenchant:GetOutcomes(1002)
check("a weapon gives mostly essence", weapon[1].itemID == LESSER_ASTRAL and weapon[1].chance == 0.75)
check("and dust less often", weapon[2].itemID == STRANGE_DUST and weapon[2].chance == 0.15)

local blue = Disenchant:GetOutcomes(1003)
check("a level 33 blue gives a Small Glowing Shard", #blue == 1 and blue[1].itemID == SMALL_GLOWING)

local epic = Disenchant:GetOutcomes(1004)
check("a level 58 epic gives a Nexus Crystal", epic[1].itemID == NEXUS)

print("\nvalue")

-- 0.75 * 5 * 100 + 0.15 * 1.5 * 1000 + 0.10 * 1 * 2000
local value, partial = Disenchant:GetValue(1001)
check("armour is worth 800 copper disenchanted", value == 800)
check("with every material priced", partial == nil)

-- 0.75 * 1.5 * 1000 + 0.15 * 5 * 100 + 0.10 * 1 * 2000
check("the weapon is worth 1400", Disenchant:GetValue(1002) == 1400)

prices[SMALL_GLIMMERING] = nil
value, partial = Disenchant:GetValue(1001)
check("an unpriced shard leaves the priced part", value == 600)
check("and says the value is partial", partial == true)
prices[SMALL_GLIMMERING] = 2000

check("nothing priced is no value, not zero", Disenchant:GetValue(1003) == nil)
check("an item that cannot be disenchanted has no value", Disenchant:GetValue(1005) == nil)

print("\nthe Profit tab")

local cheap = Profit:Analyse(1001)
check("the craft carries its disenchant value", cheap.disenchantValue == 800)
check("and knows it can be disenchanted", cheap.disenchantable == true)
check("it sells for less than that", cheap.unitRevenue < 800)
check("so disenchanting beats selling", cheap.disenchantBeatsSale == true)

local dear = Profit:Analyse(1002)
check("the weapon sells for more than it disenchants", dear.disenchantBeatsSale == nil)
check("a white craft has no disenchant value", Profit:Analyse(1005).disenchantable == nil)

local soulbound = Profit:Analyse(1008)
check("a soulbound craft still shows its disenchant value", soulbound.soulbound
    and soulbound.disenchantValue == 800)

-- The ranking is profit, whatever disenchanting is worth.
local ranked = Profit:GetRanked({})
check("the list is still ranked on profit", ranked[1].recipeID == 1002 and ranked[2].recipeID == 1001)

print("\nthe Enchanting tab")

local crafts = Disenchant:GetCraftRows({ beatsOnly = true })
local byID = {}
for _, row in ipairs(crafts) do byID[row.itemID] = row end
check("crafts worth more disenchanted are listed", byID[1001] ~= nil)
check("a soulbound craft is listed against its vendor price", byID[1008]
    and byID[1008].sells == 500 and byID[1008].sellsAt == "vendor")
check("one worth more sold is not", byID[1002] == nil)
check("nor one that cannot be disenchanted", byID[1005] == nil)
-- 800 of materials, less the 5% auction cut when they are sold: 760. Less
-- the 100 the craft costs: 660, the same sum the Disenchanting tab does.
check("the auction cut comes off the disenchant value", byID[1001].net == 760)
check("profit is that less materials", byID[1001].gain == 660)

check("unticked, every disenchantable craft shows",
    #Disenchant:GetCraftRows({ beatsOnly = false }) == 3)

local bagRows = Disenchant:GetBagRows({ beatsOnly = false })
local bagByID = {}
for _, row in ipairs(bagRows) do bagByID[row.itemID] = row end
check("bag items that can be disenchanted are listed", bagByID[1001] and bagByID[1002])
check("with how many you carry", bagByID[1001].count == 2)
check("materials and white items are not", bagByID[STRANGE_DUST] == nil and bagByID[1005] == nil)
check("the chest is worth more disenchanted", bagByID[1001].beatsSale == true)
check("the weapon is worth more sold", bagByID[1002].beatsSale == false)
check("ticked, only the chest is left", #Disenchant:GetBagRows({ beatsOnly = true }) == 1)

local materials = Disenchant:GetMaterialRows()
check("every enchanting material is listed", #materials == #Disenchant.MATERIALS)
check("with its price and what you carry", materials[1].itemID == STRANGE_DUST
    and materials[1].price == 100 and materials[1].have == 7)

C_Item, GetTime, CreateFrame = saved.C_Item, saved.GetTime, saved.CreateFrame

print(("\n%d check(s) passed\n"):format(checks))
