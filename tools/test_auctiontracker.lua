-- Logic/AuctionTracker.lua outside WoW.
--
--   1. The rows are your own auctions only, soonest to end first, from the
--      live read while there is one, else the saved listings of the
--      character playing.
--   2. A sale takes its row off, cheapest first when two match, and adds
--      the listing's price less the 5% cut to Sold Today.
--   3. Part of a stack sold keeps the row with fewer.
--   4. A sale with no row of yours makes up no gold.
--   5. Sold Today starts again on a new day; a new read forgets this
--      session's word on each row.

local now = 10000
time = function() return now end
local today = "2026-11-11"
local realDate = date
date = function(fmt, t) if fmt == "%Y-%m-%d" then return today end return realDate(fmt, t) end

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.RegisterEvent = function() return true end
local settings = {}
ns.Config = {
  Get = function(_, k) return settings[k] end,
  Set = function(_, k, v) settings[k] = v end,
  GetCharacterKey = function() return "Player-1" end,
}
ns.db = {}
local names = { [2589] = "Linen Cloth", [2592] = "Wool Cloth", [818] = "Tigerseye" }
ns.Util = { GetItemName = function(id) return names[id] end }

local chunk = assert(loadfile(lfs_cwd .. "/Logic/AuctionTracker.lua"))
chunk("Blackthornes_TS", ns)
local AT = ns.AuctionTracker
local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-52s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-52s %s", label, tostring(got)))
  end
end

print("\nsettings")
check("off until ticked", AT:IsOn(), false)
AT:SetOn(true)
check("ticked, it is on", AT:IsOn(), true)
check("effects full by default", AT:EffectsLevel(), "full")
settings.auctionTrackerEffects = "subtle"
check("subtle when picked", AT:EffectsLevel(), "subtle")
ns.Motion = { Level = function() return "off" end }
check("never more than the Effects setting", AT:EffectsLevel(), "off")
ns.Motion, settings.auctionTrackerEffects = nil, nil

print("\nsaved listings, away from the auction house")
ns.Auctions = { GetListings = function() return {
  { itemID = 2589, quantity = 20, unit = 100, ends = now + 7200, who = "Player-1" },
  { itemID = 818, quantity = 1, unit = 5000, ends = now + 600, who = "Player-1" },
  { itemID = 2592, quantity = 5, unit = 300, ends = now + 900, who = "Alt-2" },
  { itemID = 2592, quantity = 5, unit = 300, ends = now - 5, who = "Player-1" },
  { itemID = 2592, quantity = 5, unit = 300, ends = now + 100, who = "Player-1", ended = true },
} end }
local rows = AT:Rows()
check("only yours that are still up", #rows, 2)
check("soonest first", rows[1].itemID, 818)

print("\nthe live read wins")
ns.Auctions.ownedIDs = {}
ns.Auctions.liveAt = now
ns.Auctions.live = {
  { auctionID = 1, itemID = 2589, quantity = 20, unit = 120, ends = now + 3600 },
  { auctionID = 2, itemID = 2589, quantity = 20, unit = 100, ends = now + 7200 },
  { auctionID = 3, itemID = 2592, quantity = 10, unit = 300, band = 1 },
}
rows = AT:Rows()
check("three live rows", #rows, 3)
check("a band gives a rough end", rows[3].roughEnd == true or rows[2].roughEnd == true, true)

print("\na sale")
local v0 = AT.version
local row, net, partial = AT:Sold("Linen Cloth")
check("the cheapest of two leaves", row and row.key, "a:2")
check("price less the cut", net, math.floor(100 * 20 * 0.95))
check("whole stack", partial, false)
check("version moved", AT.version > v0, true)
check("row gone", #AT:Rows(), 2)
local copper, count = AT:SoldToday()
check("Sold Today copper", copper, 1900)
check("Sold Today count", count, 1)

print("\npart of a stack")
row, net, partial = AT:Sold("Wool Cloth (4)")
check("partial", partial, true)
check("net for four", net, math.floor(300 * 4 * 0.95))
local wool
for _, r in ipairs(AT:Rows()) do if r.itemID == 2592 then wool = r end end
check("row stays with fewer", wool and wool.quantity, 6)

print("\nno row of yours")
check("no gold made up", AT:Sold("Copper Ore"), nil)
copper = AT:SoldToday()
check("Sold Today unchanged", copper, 1900 + 1140)

print("\nby item ID")
row = AT:Sold("whatever", 2589)
check("matched by ID", row and row.key, "a:1")

print("\na new read")
AT:OnRead()
check("the read is the truth again", #AT:Rows(), 3)

print("\na new day")
today = "2026-11-12"
copper, count = AT:SoldToday()
check("starts again", copper, 0)
check("count starts again", count, 0)

print("\nparse")
local plain, n = AT.ParseItem("Linen Cloth x5")
check("x count", n, 5)
plain, n = AT.ParseItem("|cffffffffLinen Cloth|r (3)")
check("bracket count through colour", n, 3)
date = realDate

print("")
if failures > 0 then error(string.format("%d auction tracker check(s) failed", failures)) end
print("  all auction tracker checks passed")
print("")
