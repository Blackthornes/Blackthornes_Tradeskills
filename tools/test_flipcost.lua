-- Bought stock is costed at what you paid, not the last craft (a player's
-- report, 2026-11-26: Medium Leather bought at 1s 15c and sold at 1s 52c
-- showed as a Leatherworking loss against a 4s 60c craft cost).
--
--   1. A sale recorded after a buy that is newer than the last craft takes
--      the buy price and counts as Flipped; one made after the buy stays
--      Crafted at the craft cost.
--   2. A sale recorded before this fix (craft cost on it, no buy flag) is
--      read again: a buy between the craft and the sale makes it a flip.
--   3. A sale with no cost on it takes a buy before it ahead of today's
--      material estimate.
--   4. "Never Below What I Paid" leaves bought stock alone; it still holds
--      back a craft.
--
-- Real Logic/CraftedCost.lua and Logic/MethodProfit.lua together.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.RegisterEvent = function() return true end

local now = 50000000
time = function() return now end
local DAY = 86400

local settings = { auctionCut = 0.05 }
ns.Config = {
  Get = function(_, key) return settings[key] end,
  GetRealmKey = function() return "Realm-A" end,
}
ns.db = {}
ns.Util = {
  FormatMoney = function(c) return tostring(c) .. "c" end,
  FormatAgeAgo = function(s) return tostring(s) .. "s ago" end,
  GetItemLabel = function(id) return "item" .. tostring(id) end,
  IsBoundOnPickup = function() return false end,
}

local LEATHER, SHIRT = 2319, 200
ns.Recipes = {
  GetAny = function(_, recipeID)
    if recipeID == 1 then return { outputItemID = LEATHER } end
    if recipeID == 2 then return { outputItemID = SHIRT } end
  end,
  GetAccountWide = function() return {} end,
}
-- What one costs to make, as the craft is cast and as today's estimate.
local makeCost = { [1] = 376, [2] = 900 }
ns.Cost = {
  GetCraftCost = function(_, recipeID)
    return { priceable = true, perUnit = makeCost[recipeID] }
  end,
  FindAnyRecipeForItem = function(_, itemID)
    if itemID == LEATHER then return 1 elseif itemID == SHIRT then return 2 end
  end,
}

local ledger = { entries = {} }
ns.Mail = {
  GetLedger = function() return ledger end,
  Entries = function() return ledger.entries end,
  NameIndex = function() return {} end,
}
ns.GoldLog = {
  sessionStart = now - 600,
  DayStart = function(t) return t - (t % DAY) end,
  KeyStart = function(k) return k end,
}

assert(loadfile(lfs_cwd .. "/Logic/CraftedCost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/MethodProfit.lua"))("Blackthornes_TS", ns)
local CC, MP = ns.CraftedCost, ns.MethodProfit
local failures = 0

local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-58s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-58s %s", label, tostring(got)))
  end
end

-- The way Data/Mail.lua writes a sale down, at the moment it is read.
local function RecordSale(itemID, units, net)
  local entry = { t = now, kind = "sold", itemID = itemID, quantity = units, net = net }
  CC:CostTheSale(entry)
  ledger.entries[#ledger.entries + 1] = entry
  return entry
end

local function Group(summary, key, itemID)
  local group = summary.methods[key]
  for _, item in ipairs(group.list) do
    if item.itemID == itemID then return item end
  end
end

print("a buy after the last craft is a flip")
CC:NoteCraft(1)                                   -- made one at 3s 76c
now = now + DAY
makeCost[1] = 460                                 -- materials went up
now = now + DAY
MP:NoteBought(LEATHER, 345, 345 * 115)            -- bought 345 at 1s 15c
now = now + 960
local sale = RecordSale(LEATHER, 347, 347 * 144)  -- sold 347 at 1s 52c less the cut
check("costed at the buy price", sale.cost, 115)
check("marked bought", sale.bought, true)
local cost, source = CC:SaleCost(sale, LEATHER)
check("its cost reads as bought", source, "bought")
local summary = MP:Summary(now - 10 * DAY, now + 1)
local flipped = Group(summary, "flipped", LEATHER)
check("listed under Flipped", flipped and flipped.n, 347)
check("not under Crafted", Group(summary, "crafted", LEATHER), nil)
check("a profit, not a loss", flipped and flipped.profit, 347 * (144 - 115))

print("a craft after the buy is a craft")
now = now + 60
CC:NoteCraft(1)                                   -- made one again, at 4s 60c
now = now + 60
local made = RecordSale(LEATHER, 1, 480)
check("costed at the craft", made.cost, 460)
check("not marked bought", made.bought, nil)
check("its cost reads as made", select(2, CC:SaleCost(made, LEATHER)), "made")

print("an old sale with a craft cost on it is read again")
ledger.entries = {}
ns.db = {}
now = now + 10 * DAY
CC:NoteCraft(1)                                   -- craft at 4s 60c
now = now + DAY
MP:NoteBought(LEATHER, 100, 100 * 115)            -- then a buy
now = now + 600
local old = { t = now, kind = "sold", itemID = LEATHER, quantity = 100, net = 100 * 144, cost = 460 }
ledger.entries[1] = old
cost, source = CC:SaleCost(old, LEATHER)
check("cost is the buy", cost, 115)
check("source is bought", source, "bought")
summary = MP:Summary(now - DAY, now + 1)
check("old sale under Flipped", Group(summary, "flipped", LEATHER) and Group(summary, "flipped", LEATHER).n, 100)

print("crafted again since the old sale: a buy just before it still wins")
now = now + DAY
CC:NoteCraft(1)                                   -- the last craft is now newer than the sale
check("still bought", select(2, CC:SaleCost(old, LEATHER)), "bought")
local longAgo = { t = now - 20 * DAY, kind = "sold", itemID = LEATHER, quantity = 1, net = 480, cost = 460 }
check("no buy near it: stays made", select(2, CC:SaleCost(longAgo, LEATHER)), "made")

print("no cost on the sale: a buy beats today's estimate")
ns.db.characters = { ["Player-1"] = { recipes = { [2] = { outputItemID = SHIRT } } } }
local bare = { t = now, kind = "sold", itemID = SHIRT, quantity = 2, net = 2000 }
check("estimate when never bought", select(2, CC:SaleCost(bare, SHIRT)), "est")
MP:NoteBought(SHIRT, 2, 1000)
now = now + 60
bare.t = now
cost, source = CC:SaleCost(bare, SHIRT)
check("bought when bought", source, "bought")
check("at what was paid", cost, 500)

print("Never Below What I Paid")
settings.neverBelowCraftedCost = true
ns.db = {}
now = now + DAY
CC:NoteCraft(1)                                   -- made at 4s 60c
check("holds back a craft under its cost", CC:Refuses(LEATHER, 152) ~= nil, true)
check("the stock record is the craft", CC:ForStock(LEATHER) ~= nil, true)
now = now + 60
MP:NoteBought(LEATHER, 345, 345 * 115)
check("bought stock is not held back", CC:Refuses(LEATHER, 152), nil)
check("no craft cost for bought stock", CC:ForStock(LEATHER), nil)
now = now + 60
CC:NoteCraft(1)
check("made again: held back again", CC:Refuses(LEATHER, 152) ~= nil, true)

if failures > 0 then
  print(string.format("%d check(s) failed", failures))
  os.exit(1)
end
print("all flip cost checks passed")
