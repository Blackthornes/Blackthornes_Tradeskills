-- What the Snipe view says for a deal made ready before the click
-- (UI/SnipeView.lua BuyState, SetShown, BuyTop).

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
    GetItemLabel = function(id) return id == 2589 and "Linen Cloth" or nil end,
}
local readied, paid, asked = 0, 0, nil
local finds = { { itemID = 2589, qty = 20, price = 6 }, { itemID = 2592, qty = 1, price = 50 } }
ns.Snipe = {
    ReadySoon = function() readied = readied + 1 end,
    BuyNext = function(self)
        local p = self.pending
        if p then
            if p.phase == "quoted" or p.phase == "planned" then paid = paid + 1 end
            return
        end
        asked = self.topFn and self.topFn()
    end,
}
assert(loadfile("UI/SnipeView.lua"))("Blackthornes_TS", ns)
local View = ns.SnipeView
View.SortedFinds = function() return finds end

print("")
print("snipe: ready before the click")

View:SetShown(true)
check("the list showing lets Snipe ready deals", ns.Snipe.viewShown == true)
check("and readies the top soon", readied == 1)
check("Snipe's top is the list's top", ns.Snipe.topFn and ns.Snipe.topFn() == finds[1])

local label, can = View:BuyState()
check("nothing ready yet: Buy It", label == "Buy It" and can)

ns.Snipe.pending = { itemID = 2589, find = finds[1], phase = "asking", auto = true, stack = true, count = 20 }
label, can = View:BuyState()
check("while it readies: Checking..., not clickable", label == "Checking..." and not can)

ns.Snipe.pending.phase = "quoted"
ns.Snipe.pending.total = 120
label, can = View:BuyState()
check("ready: says what one click buys", label == "Buy Linen Cloth x20 for 120c" and can)

ns.Snipe.pending.phase = "planned"
ns.Snipe.pending.total, ns.Snipe.pending.expected = nil, 118
label = View:BuyState()
check("planned: the price the listings showed", label == "Buy Linen Cloth x20 for 118c")

View:BuyTop()
check("Buy It pays for what's ready", paid == 1)

ns.Snipe.armed = ns.Snipe.pending
label = View:BuyState()
check("over Double Check Over: Confirm", label == "Confirm")
ns.Snipe.armed = nil

ns.Snipe.pending = { itemID = 2592, find = finds[2], phase = "quoted", auto = true, item = true, total = 50 }
label = View:BuyState()
check("an item with no name loaded still reads", label == "Buy that item x1 for 50c")

ns.Snipe.pending = nil
View:BuyTop()
check("nothing ready: Buy It asks for the list's top", asked == finds[1])

View:SetShown(false)
check("hidden: no more readying for the view", ns.Snipe.viewShown == false and ns.Snipe.topFn == nil)

if failures > 0 then error(failures .. " check(s) failed") end
