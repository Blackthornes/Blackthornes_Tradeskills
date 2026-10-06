-- Logic/CraftedCost.lua outside WoW: what a craft cost when it was made.
--
--   1. A cast of a recipe writes down what one of its item cost then, and a
--      later craft replaces it; a craft with an unpriced material does not.
--   2. A listing writes down its price.
--   3. "Never below what I paid" is off by default; on, it refuses a price
--      that brings in less than the cost after the auction house's cut.
--   4. The tooltip lines say what it was made for, last posted at, and the
--      profit now, and nothing for an item never crafted.
--   5. Kept per realm.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {} ns[name] = m return m end

local now = 1000000
time = function() return now end

local settings = { auctionCut = 0.05 }
local realm = "Realm-A"
ns.Config = {
  Get = function(_, key) return settings[key] end,
  GetRealmKey = function() return realm end,
}

ns.Util = {
  FormatMoney = function(c) return tostring(c) .. "c" end,
  FormatAgeAgo = function(s) return tostring(s) .. "s ago" end,
  GetItemLabel = function(id) return "item" .. tostring(id) end,
  IsBoundOnPickup = function(id) return id == 900 end,
}

local BOLT, SHIRT, SWORD = 100, 200, 900
ns.Recipes = {
  GetAny = function(_, recipeID)
    if recipeID == 1 then return { outputItemID = BOLT } end
    if recipeID == 2 then return { outputItemID = SHIRT } end
    if recipeID == 3 then return { outputItemID = SWORD } end
    if recipeID == 4 then return { } end
  end,
}

local costs = { [1] = { priceable = true, perUnit = 1000 }, [2] = { priceable = false } ,
                [3] = { priceable = true, perUnit = 50 } }
ns.Cost = {
  GetCraftCost = function(_, recipeID, _, _, opts)
    assert(opts and opts.valueOwned, "materials are valued at worth")
    return costs[recipeID]
  end,
}

local postPrice = {}
ns.Posting = {
  GetPostPrice = function(_, itemID) local p = postPrice[itemID] if p then return p[1], p[2] end end,
}

ns.db = {}

local chunk = assert(loadfile(lfs_cwd .. "/Logic/CraftedCost.lua"))
chunk("Blackthornes_TS", ns)

local CC = ns.CraftedCost
local failures = 0

local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-52s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-52s %s", label, tostring(got)))
  end
end

print("\nremembering crafts")
check("nothing known before a craft", CC:Get(BOLT), nil)
check("a cast writes the cost of one", CC:NoteCraft(1), 1000)
check("and it reads back", CC:Get(BOLT).cost, 1000)
check("with when", CC:Get(BOLT).at, now)
check("an unpriced material writes nothing", CC:NoteCraft(2), nil)
check("so the shirt stays unknown", CC:Get(SHIRT), nil)
check("soulbound gear is not kept", CC:NoteCraft(3), nil)
check("a craft making no item is not kept", CC:NoteCraft(4), nil)
now = now + 60
costs[1].perUnit = 1200.4
check("a later craft replaces the cost", CC:NoteCraft(1), 1200)
check("rounded to a copper", CC:Get(BOLT).cost, 1200)

print("\nremembering listings")
check("nothing posted yet", CC:GetLastPosted(BOLT), nil)
CC:NotePosted(BOLT, 1500)
check("a listing writes its price", CC:GetLastPosted(BOLT).price, 1500)
CC:NotePosted(BOLT, 0)
check("a zero price is not written", CC:GetLastPosted(BOLT).price, 1500)

print("\nthe guard")
check("off by default: never refuses", CC:Refuses(BOLT, 1), nil)
settings.neverBelowCraftedCost = true
check("on: 1263 brings in 1199, under 1200", CC:Refuses(BOLT, 1263), 1200)
check("on: 1264 brings in 1200, allowed", CC:Refuses(BOLT, 1264), nil)
check("on: an item never crafted is allowed", CC:Refuses(SHIRT, 1), nil)
settings.neverBelowCraftedCost = false

print("\ntooltip lines")
check("nothing for an item never crafted", #CC:Lines(SHIRT), 0)
postPrice[BOLT] = { 2000, "undercut" }
local lines = CC:Lines(BOLT)
check("three lines", #lines, 3)
check("made for", lines[1][1], "Made for")
check("last posted", lines[2][1], "Last posted")
check("profit now", lines[3][1], "Profit now")
check("profit after the cut", lines[3][2], "+700c at 2000c")
check("in profit green", lines[3].color, "profit")
lines = CC:Lines(BOLT, 1000)
check("a given price at a loss", lines[3][2], "-250c at 1000c")
check("in loss red", lines[3].color, "loss")
postPrice[BOLT] = { 2000, "derived" }
check("no profit on an estimate", #CC:Lines(BOLT), 2)

print("\nwhat a sale made")
-- BOLT was last made for 1200 at `now`.
local HAT = 300
costs[5] = { priceable = true, perUnit = 333.4 }
ns.db.characters = {
  ["Ana-Realm-A"] = { recipes = { [5] = { recipeID = 5, outputItemID = HAT },
                                   [2] = { recipeID = 2, outputItemID = SHIRT } } },
}
local cache = CC:NewSaleCache()
local sale = { kind = "sold", t = now + 10, itemID = BOLT, net = 2100, deposit = 100 }
local profit, cost, source = CC:SaleProfit(sale, nil, cache)
check("sold after the craft: its cost", cost, 1200)
check("from the craft", source, "made")
check("profit leaves the deposit out", profit, 800)
sale.cost = 900
profit, cost = CC:SaleProfit(sale, nil, cache)
check("a cost written on the sale wins", cost, 900)
check("and the profit follows it", profit, 1100)
sale = { kind = "sold", t = now - 10, itemID = BOLT, net = 1000 }
profit, cost, source = CC:SaleProfit(sale, nil, cache)
check("sold before the craft: no craft cost", source, nil)
check("and no recipe makes it on record, so none", profit, nil)
sale = { kind = "sold", t = now, itemID = HAT, net = 500, quantity = 2 }
profit, cost, source = CC:SaleProfit(sale, nil, cache)
check("never crafted: today's estimate", source, "est")
check("rounded, times the quantity", cost, 666)
check("loss", profit, -166)
check("an unpriced recipe has no cost", CC:SaleProfit({ kind = "sold", itemID = SHIRT, net = 5 }, nil, cache), nil)
check("an id passed in wins over none", (select(2, CC:SaleProfit({ kind = "sold", net = 900 }, HAT, cache))), 333)
check("an expiry made nothing", CC:SaleProfit({ kind = "expired", itemID = BOLT }, nil, cache), nil)
ns.db.characters = nil

print("\nper realm")
realm = "Realm-B"
check("another realm knows nothing", CC:Get(BOLT), nil)
realm = "Realm-A"
check("and this one still does", CC:Get(BOLT).cost, 1200)

if failures > 0 then error(failures .. " failure(s)") end
