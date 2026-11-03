-- The Snipe tab's logic (2026-11-03).
--
-- What must hold:
--   1. A deal is a price at or under worth times Snipe Below.
--   2. Snipe Below stays between 10 and 95; the cap and watch read the setting.
--   3. Start refuses without a Spending Cap and never starts by itself.
--   4. A buy that reaches the cap stops the session and clears the finds.
--   5. The auction house closing stops a session.
--   6. The wheel (BuyNext) does nothing when not running.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Util = {}
ns.Print = function() end
local said = {}
ns.Notice = { Show = function(_, text) said[#said + 1] = text end }
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn; return true end
local settings = {}
ns.Config = { Get = function(_, k) return settings[k] end }

assert(loadfile(lfs_cwd .. "/Logic/Snipe.lua"))("Blackthornes_TS", ns)
local Snipe = ns.Snipe
Snipe:Init()

-- 1. Deals.
assert(Snipe.IsDeal(70, 100, 70) == true, "at the line is a deal")
assert(Snipe.IsDeal(71, 100, 70) == false, "over the line is not")
assert(Snipe.IsDeal(10, 0, 70) == false, "no worth, no deal")
assert(Snipe.Deal(50, 100) == 50, "half price is 50 under")

-- 2. Settings.
assert(Snipe:Percent() == 70, "default 70")
settings.snipePct = 3
assert(Snipe:Percent() == 10, "floor 10")
settings.snipePct = 200
assert(Snipe:Percent() == 95, "ceiling 95")
settings.snipeCap = 5000
assert(Snipe:Cap() == 5000)
assert(Snipe:Watch() == "priced")
settings.snipeWatch = "disenchant"
assert(Snipe:Watch() == "disenchant")
assert(Snipe:Enabled() == false)
settings.snipeTab = true
assert(Snipe:Enabled() == true)

-- 3. No cap, no start.
settings.snipeCap = 0
Snipe:Start()
assert(not Snipe:IsRunning(), "refuses without a cap")
assert(said[#said] == "Set a Spending Cap first.", "says why")

-- 6. Wheel does nothing when stopped.
Snipe:BuyNext()
assert(not Snipe:IsRunning())

-- 4. Cap reached.
settings.snipeCap = 1000
Snipe.running, Snipe.spent = true, 0
Snipe.finds = { { itemID = 1 }, { itemID = 2 } }
Snipe.pending = { itemID = 1, count = 1, total = 1000, phase = "buying" }
Snipe:Bought()
assert(Snipe:Spent() == 1000, "spent counts")
assert(not Snipe:IsRunning(), "cap stops the session")
assert(#Snipe:Finds() == 0, "finds cleared")
assert(said[#said] == "You've reached your Spending Cap. Snipe stopped.")

-- 5. Auction house closing.
Snipe.running = true
handlers.AUCTION_HOUSE_CLOSED()
assert(not Snipe:IsRunning(), "closing the auction house stops")

print("test_snipe: all passed")
