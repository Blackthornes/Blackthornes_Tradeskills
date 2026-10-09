-- Craft time and gold per hour (asked 2026-10-09): how long one of a craft
-- takes, counting the sub-crafts the addon would make for it, and the
-- profit that makes an hour, for crafts and for disenchanting.
--
-- What must hold:
--   * a cast's length the player was seen casting beats the game's spell
--     data, and with neither the time is unknown, never guessed;
--   * only crafts and Disenchant are kept, only the player's, and a value
--     the game will not let the addon touch is skipped, not an error;
--   * a craft's time adds each sub-craft as often as its materials need it,
--     fewer times when a sub-craft makes more than one;
--   * one unknown cast anywhere leaves the whole time unknown;
--   * the Profit tab's analysis carries the time and gold per hour, with a
--     disenchant cast added when the profit is for disenchanting.

local GLOBALS = { "CreateFrame", "GetTime", "time", "C_Item", "C_Spell", "GetSpellInfo",
    "UnitCastingInfo" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

CreateFrame = function()
    return setmetatable({}, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
end
GetTime = function() return 1000 end
time = function() return 100000 end
C_Spell, GetSpellInfo = nil, nil

local BELT, BOLT, LINEN = 5000, 2996, 2589
local BELT_RECIPE, BOLT_RECIPE, DE = 300, 301, 13262

-- Nothing is sold to a vendor here.
C_Item = { GetItemInfo = function(itemID)
    return "item " .. itemID, "link", 2, 1, 1, "", "", 1, "", "", 0
end }

local recipes = {
    [BELT_RECIPE] = { recipeID = BELT_RECIPE, name = "Linen Belt", outputItemID = BELT,
        quantityMin = 1, quantityMax = 1, reagents = { { itemID = BOLT, quantity = 2 } } },
    [BOLT_RECIPE] = { recipeID = BOLT_RECIPE, name = "Bolt of Linen Cloth", outputItemID = BOLT,
        quantityMin = 1, quantityMax = 1, reagents = { { itemID = LINEN, quantity = 2 } } },
}

local settings = { undercutCopper = 1, auctionCut = 0.05, expectedRelists = 1, minProfit = 0,
    staleAfterSeconds = 48 * 3600, valueOwnedMaterials = true, unscannedMarkupPercent = 50,
    priceUnscannedCrafts = true }

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
local events = {}
ns.RegisterEvent = function(owner, event, fn) events[event] = function(...) return fn(owner, event, ...) end end
ns.RegisterCommand = noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.db = {}

local priceTable = {}
ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return "Me" end,
    GetPriceTable = function() return priceTable end,
}
ns.Recipes = {
    GetAll = function() return recipes end,
    Get = function(_, id) return recipes[id] end,
    GetAny = function(_, id) return recipes[id], recipes[id] and "Me" or nil end,
    GetAccountWide = function() return recipes end,
    GetCharacterName = function() return "Me" end,
    IsDropped = function() return false end,
    GetDisplayLink = function() return "[Linen Belt]" end,
}
ns.Inventory = {
    GetBagCount = function() return 0 end, GetCharacterBagCount = function() return 0 end,
    GetBankCount = function() return 0 end, GetOwnedCount = function() return 0 end,
    GetAltTotal = function() return 0 end,
}
ns.Vendor = { GetUnitPrice = function() return nil end }
ns.Scanner = { GetCommodityStatus = function() return true end }
ns.Auctions = { GetRoom = function() return nil, 0, 0, 0, 0, 0 end }
ns.Posting = { GetCachedUnitDeposit = function() return 0 end }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/CraftTime.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)

local CraftTime, Profit = ns.CraftTime, ns.Profit
CraftTime:OnEnable()

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

print("")
print("one cast")

check("nothing seen and no spell data: unknown", CraftTime:GetCast(BELT_RECIPE), nil)

C_Spell = { GetSpellInfo = function(id) return { castTime = id == BELT_RECIPE and 5000 or 0 } end }
local seconds, source = CraftTime:GetCast(BELT_RECIPE)
check("the game's spell data, in seconds", seconds, 5)
check("said to be the game's", source, "game")
check("a cast time of 0 from the game is not believed", CraftTime:GetCast(BOLT_RECIPE), nil)

C_Spell = nil
GetSpellInfo = function(id) return "Bolt", nil, nil, id == BOLT_RECIPE and 2000 or 0 end
check("or the old GetSpellInfo's fourth return", CraftTime:GetCast(BOLT_RECIPE), 2)

CraftTime:NoteCast(BELT_RECIPE, 4.96)
seconds, source = CraftTime:GetCast(BELT_RECIPE)
check("a cast seen beats the game, to a tenth", seconds, 5)
check("and says it was seen", source, "seen")
CraftTime:NoteCast(BOLT_RECIPE, 0)
check("a cast of no length is not kept", ns.db.castTimes[BOLT_RECIPE], nil)

print("")
print("watching casts")

local casting
UnitCastingInfo = function() return "Bolt of Linen Cloth", "", nil, 10000, 11500 end
GetSpellInfo = nil

events.UNIT_SPELLCAST_START("player", "guid", BOLT_RECIPE)
check("a craft the player casts is kept", ns.db.castTimes[BOLT_RECIPE], 1.5)

events.UNIT_SPELLCAST_START("player", "guid", 8690)
check("a spell that is no craft is not", ns.db.castTimes[8690], nil)

events.UNIT_SPELLCAST_START("party1", "guid", DE)
check("someone else's cast is not", ns.db.castTimes[DE], nil)

UnitCastingInfo = function() return "Disenchant", "", nil, 10000, 13000 end
events.UNIT_SPELLCAST_START("player", "guid", DE)
check("Disenchant is kept", ns.db.castTimes[DE], 3)

-- A value the game will not let the addon touch raises when used.
local secret = setmetatable({}, { __add = function() error("secret") end,
    __eq = function() error("secret") end, __sub = function() error("secret") end })
ns.db.castTimes[DE] = nil
local ok = pcall(events.UNIT_SPELLCAST_START, "player", "guid", secret)
check("a secret spell ID is skipped, not an error", ok, true)
UnitCastingInfo = function() return "Disenchant", "", nil, secret, secret end
ok = pcall(events.UNIT_SPELLCAST_START, "player", "guid", DE)
check("a secret cast time too", ok, true)
check("and nothing is kept from it", ns.db.castTimes[DE], nil)

print("")
print("a whole craft")

-- Linen at 10c and bolts at 60c: making a bolt (20c) beats buying one.
ns.Prices:Record(LINEN, 10, 10, 500, time(), 10, nil)
ns.Prices:Record(BOLT, 60, 60, 50, time(), 60, nil)
ns.Prices:Record(BELT, 300, 300, 5, time(), 300, nil)

local cost = ns.Cost:GetCraftCost(BELT_RECIPE)
check("the bolts are made, not bought", cost.reagents[1].crafted, true)
check("two of them", cost.reagents[1].toMake, 2)

-- The belt 5s, each bolt 1.5s.
local timing = CraftTime:ForCost(BELT_RECIPE, cost)
check("5s for the belt, 1.5s for each of two bolts", timing.seconds, 8)
check("three casts", timing.casts, 3)
check("all seen", timing.source, "seen")

-- A bolt recipe making two at a time is cast once for two bolts.
recipes[BOLT_RECIPE].quantityMin, recipes[BOLT_RECIPE].quantityMax = 2, 2
cost = ns.Cost:GetCraftCost(BELT_RECIPE)
timing = CraftTime:ForCost(BELT_RECIPE, cost)
check("two bolts made at once: one bolt cast", timing.seconds, 6.5)
recipes[BOLT_RECIPE].quantityMin, recipes[BOLT_RECIPE].quantityMax = 1, 1

-- Bolts already in the bags (and the cash view on): none to make.
settings.valueOwnedMaterials = false
ns.Inventory.GetBagCount = function(_, itemID) return itemID == BOLT and 2 or 0 end
cost = ns.Cost:GetCraftCost(BELT_RECIPE)
check("bolts in the bags are not made again", CraftTime:ForCost(BELT_RECIPE, cost).seconds, 5)
settings.valueOwnedMaterials = true
ns.Inventory.GetBagCount = function() return 0 end

ns.db.castTimes[BOLT_RECIPE] = nil
cost = ns.Cost:GetCraftCost(BELT_RECIPE)
timing = CraftTime:ForCost(BELT_RECIPE, cost)
check("a sub-craft never cast: the whole time is unknown", timing.seconds, nil)
ns.db.castTimes[BOLT_RECIPE] = 1.5

print("")
print("the Profit tab")

local a = Profit:Analyse(BELT_RECIPE, nil, "auction")
check("the time is on the analysis", a.craftSeconds, 8)
-- Sold at 299 less a 5% cut, less 40c of linen: 244c a belt, 450 belts an hour.
check("gold an hour is the profit over that time", a.goldPerHour, a.profit * 3600 / 8)
check("which is about 10g 98s", math.floor(a.goldPerHour / 100), 1098)

-- Disenchanted, each belt is a 3s disenchant more.
ns.db.castTimes[DE] = 3
ns.Disenchant = {
    IsDisenchantable = function() return true end,
    GetValue = function() return 400, nil, { outcomes = {} } end,
    GetBestEnchanter = function() return 100, "Ana" end,
    GetItemFacts = function() return { skill = 1 } end,
}
a = Profit:Analyse(BELT_RECIPE, nil, "disenchant")
check("disenchanted, the time takes in the disenchant", a.timeSeconds, 11)
check("and gold an hour is over that", a.goldPerHour, a.profit * 3600 / 11)

ns.db.castTimes[DE] = nil
a = Profit:Analyse(BELT_RECIPE, nil, "disenchant")
check("a disenchant of unknown length: no gold an hour", a.goldPerHour, nil)
ns.Disenchant = nil

print("")
print("written short")

check("3 seconds", CraftTime.Format(3), "3s")
check("1.5 seconds", CraftTime.Format(1.5), "1.5s")
check("45 seconds", CraftTime.Format(45), "45s")
check("65 seconds", CraftTime.Format(65), "1m 05s")
check("an hour and five minutes", CraftTime.Format(3900), "1h 05m")
check("unknown", CraftTime.Format(nil), "?")
check("no gold an hour without a time", CraftTime.PerHour(100, nil), nil)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then error(("%d check(s) failed"):format(failed)) end
