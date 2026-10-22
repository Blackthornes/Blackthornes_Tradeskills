-- Logic/Butler.lua's VendorOffer and BuyFromVendor outside WoW.
--
-- Butler's Buy from a vendor row has the Buy materials button's click
-- (2026-10-14). What must hold:
--   1. No vendor open, or its list not read yet: no offer.
--   2. The offer is the button's own answer (Vendor:GetNeeded): how many
--      materials, what they cost in all, each item, and how many were left
--      for the auction house.
--   3. While a run is going or settling it says so, and offers nothing.
--   4. BuyFromVendor is the button's click (Vendor:BuyNeeded), redraws the
--      button, says why with no vendor open, and never raises.

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end

local bought, redrawn = 0, 0
local buying = false
ns.Vendor = {
  isMerchantOpen = false,
  IsBuying = function() return buying end,
  GetNeeded = function()
    return { { itemID = 2320, index = 3, amount = 12, cost = 120, unitPrice = 10, stack = 1 },
      { itemID = 3371, index = 5, amount = 4, cost = 80, unitPrice = 20, stack = 1, short = true } }, 200, 1
  end,
  CanBuy = function(self)
    if not self.isMerchantOpen then return false, "no vendor is open" end
    return true
  end,
  BuyNeeded = function() bought = bought + 1 return true end,
}
ns.UI = { UpdateMerchantButton = function() redrawn = redrawn + 1 end }

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

check("no vendor open, no offer", Butler:VendorOffer(), nil)
ns.Vendor.isMerchantOpen = true
check("its list not read yet, no offer", Butler:VendorOffer(), nil)
ns.Vendor.merchantItems = {}

local offer = Butler:VendorOffer()
check("two materials", offer and offer.count, 2)
check("their cost in all", offer and offer.cost, 200)
check("one left for the auction house", offer and offer.cheaperElsewhere, 1)
check("the first item", offer and offer.items[1].itemID, 2320)
check("how many of it", offer and offer.items[1].amount, 12)
check("limited stock said", offer and offer.items[2].short, true)
check("not buying", offer and offer.buying, false)

buying = true
offer = Butler:VendorOffer()
check("buying says so", offer and offer.buying, true)
check("and offers nothing", offer and offer.count, 0)
buying = false

local ok, why = Butler:BuyFromVendor()
check("a click starts the run", ok, true)
check("through the button's own buy", bought, 1)
check("and redraws the button", redrawn, 1)

ns.Vendor.isMerchantOpen = false
ok, why = Butler:BuyFromVendor()
check("no vendor, no run", ok, false)
check("and says why", why, "no vendor is open")
check("nothing more bought", bought, 1)

ns.Vendor.isMerchantOpen = true
ns.Vendor.GetNeeded = function() error("boom") end
check("VendorOffer never raises", Butler:VendorOffer(), nil)
ns.Vendor.BuyNeeded = function() error("boom") end
ok, why = Butler:BuyFromVendor()
check("BuyFromVendor never raises", ok, false)

-- VendorPrice: Butler's tooltip line asks what a vendor charges for one.
ns.Vendor.GetUnitPrice = function(_, itemID)
  if itemID == 2320 then return 10 end
  if itemID == 666 then error("boom") end
  return nil
end
check("a vendor's price for one", Butler:VendorPrice(2320), 10)
check("an item no vendor sells has none", Butler:VendorPrice(4306), nil)
check("not an item, no price", Butler:VendorPrice("nope"), nil)
check("VendorPrice never raises", Butler:VendorPrice(666), nil)

print("")
if failures > 0 then
  error(string.format("%d Butler vendor check(s) failed", failures))
end
print("  all Butler vendor checks passed")
print("")
