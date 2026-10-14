-- Logic/Butler.lua's SearchAuctions outside WoW.
--
-- Butler's "For your quests" line has a Search button at the auction house
-- (2026-10-14). What must hold:
--   1. Away from the auction house, mid-scan or with nothing to look for,
--      nothing is searched and it says why.
--   2. Several items go in one search (ShoppingLists:SearchMany): "all".
--   3. Where the game takes one a search, the first is searched with its
--      count (UI:SearchAuctionHouse): "one", so Butler sends the rest next.
--   4. One item is searched with its count: "all".
--   5. Items of the wrong shape are skipped, and it never raises.

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end

local many, single = {}, {}
local manyAnswer = { true }
ns.Scanner = { isAuctionHouseOpen = false, isScanning = false }
ns.ShoppingLists = { SearchMany = function(_, ids)
  many[#many + 1] = ids
  return manyAnswer[1], manyAnswer[2]
end }
ns.UI = { SearchAuctionHouse = function(_, itemID, quantity)
  single[#single + 1] = { itemID = itemID, quantity = quantity }
  return true
end }

local chunk = assert(loadfile(lfs_cwd .. "/Logic/Butler.lua"))
chunk("Blackthornes_TS", ns)
local Butler = ns.Butler

local failures = 0
local function check(label, got, want)
  if got == want then
    print("  ok   " .. label)
  else
    failures = failures + 1
    print(("  FAIL %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
  end
end

local items = { { itemID = 730, count = 5 }, { itemID = 731, count = 3 } }

-- 1.
local ok, why = Butler:SearchAuctions(items)
check("away from the auction house nothing is searched", ok, false)
check("and it says so", why, "open the auction house first")
ns.Scanner.isAuctionHouseOpen = true
ns.Scanner.isScanning = true
ok, why = Butler:SearchAuctions(items)
check("not mid-scan", ok, false)
check("and it says why", why, "a scan is running; search again once it finishes")
ns.Scanner.isScanning = false
ok, why = Butler:SearchAuctions({})
check("nothing to look for", ok, false)
check("no search sent", #many + #single, 0)

-- 2.
local how
ok, how = Butler:SearchAuctions(items)
check("several in one search", ok, true)
check("all of them", how, "all")
check("both IDs sent", many[1] and #many[1], 2)

-- 3.
manyAnswer = { false, "single" }
ok, how = Butler:SearchAuctions(items)
check("one a search", ok, true)
check("says one", how, "one")
check("the first item", single[1] and single[1].itemID, 730)
check("with its count", single[1] and single[1].quantity, 5)

manyAnswer = { false, "the auction house stayed busy" }
ok, why = Butler:SearchAuctions(items)
check("a refused search says why", why, "the auction house stayed busy")

-- 4.
ok, how = Butler:SearchAuctions({ { itemID = 731, count = 3 } })
check("one item is all", how, "all")
check("searched with its count", single[2] and single[2].quantity, 3)

-- 5.
ok, how = Butler:SearchAuctions({ "junk", { itemID = "x" }, { itemID = 732 } })
check("only the good item", single[3] and single[3].itemID, 732)
check("a missing count is one", single[3] and single[3].quantity, 1)
ns.UI.SearchAuctionHouse = function() error("boom") end
ok = Butler:SearchAuctions({ { itemID = 732 } })
check("never raises", ok, false)

print("")
if failures > 0 then
  error(string.format("%d Butler search check(s) failed", failures))
end
print("  all Butler search checks passed")
print("")
