-- Each Snipe row's own Buy button (UI/SnipeView.lua RowBuyState, RowBuy).

local failures = 0
local function check(name, ok)
    if ok then print("  ok   " .. name) else failures = failures + 1; print("  FAIL " .. name) end
end

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Theme = {}
ns.Widgets = {}
ns.Util = {
    FormatMoney = function(c) return tostring(c) .. "c" end,
    GetItemLabel = function() return nil end,
}
local log = {}
local finds = { { itemID = 2589, qty = 20, price = 6 }, { itemID = 2592, qty = 1, price = 50 } }
ns.Snipe = {
    Buy = function(self, find) log[#log + 1] = "buy"; self.pending = { find = find, phase = "asking" } end,
    CancelBuy = function(self) log[#log + 1] = "cancel"; self.pending = nil; self.armed = nil end,
    Pay = function() log[#log + 1] = "pay" end,
}
assert(loadfile("UI/SnipeView.lua"))("Blackthornes_TS", ns)
local View = ns.SnipeView
View.Changed = function() end
local snipe = ns.Snipe

print("")
print("snipe: a Buy button on each row")

local text, can = View.RowBuyState(finds[1])
check("nothing pending: Buy, clickable", text == "Buy" and can)

View:RowBuy(finds[1])
check("a click asks for that row right away", log[1] == "buy" and snipe.pending.find == finds[1])
text, can = View.RowBuyState(finds[1])
check("while it asks: Checking..., not clickable", text == "Checking..." and not can)
text, can = View.RowBuyState(finds[2])
check("another row waits while one is asked for by hand", text == "Buy" and not can)
log = {}
View:RowBuy(finds[2])
check("a click there does nothing", #log == 0 and snipe.pending.find == finds[1])

snipe.pending = { find = finds[1], phase = "quoted", count = 20, total = 120 }
text, can = View.RowBuyState(finds[1])
check("price known: says how many and the cost", text == "Buy 20 for 120c" and can)
snipe.pending.phase, snipe.pending.total, snipe.pending.expected = "planned", nil, 118
text = View.RowBuyState(finds[1])
check("planned: the price the listings showed", text == "Buy 20 for 118c")
View:RowBuy(finds[1])
check("a click on a known price pays", log[1] == "pay")

snipe.armed = snipe.pending
text, can = View.RowBuyState(finds[1])
check("over Double Check Over: Confirm", text == "Confirm" and can)
text, can = View.RowBuyState(finds[2])
check("an armed buy is never taken over", not can)
snipe.armed = nil

-- A quiet ready on another row gives way to the row clicked.
log = {}
snipe.pending = { find = finds[1], phase = "quoted", auto = true, count = 20, total = 120 }
text, can = View.RowBuyState(finds[2])
check("a quiet ready elsewhere: still Buy, clickable", text == "Buy" and can)
View:RowBuy(finds[2])
check("the click takes over the quiet ready", log[1] == "cancel" and log[2] == "buy" and snipe.pending.find == finds[2])

log = {}
snipe.pending = { find = finds[1], phase = "buying", auto = true }
text, can = View.RowBuyState(finds[2])
check("never takes over a buy under way", not can)
View:RowBuy(finds[2])
check("and a click there does nothing", #log == 0)

log = {}
snipe.pending = { find = finds[1], phase = "listing", auto = true }
text, can = View.RowBuyState(finds[1])
check("its own quiet ready still checking: Checking...", text == "Checking..." and not can)
View:RowBuy(finds[1])
check("never buys before the price is known", #log == 0)

if failures > 0 then error(failures .. " snipe buy row checks failed") end
