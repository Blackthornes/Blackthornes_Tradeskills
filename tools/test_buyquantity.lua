-- UI/BuyQuantity.lua: a Buy list search fills the auction house's quantity
-- box with what the queue still needs, and nothing else does.
--
-- Blizzard's commodity buy window is faked with the parts retail has
-- (CommoditiesBuyFrame.BuyDisplay, SetQuantitySelected, QuantityInput).

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.RegisterEvent = function() end

local settings = {}
ns.Config = { Get = function(_, key) return settings[key] end }

local shortfalls = { [2589] = 20 }
ns.Queue = {
    GetShoppingList = function()
        local lines = {}
        for itemID, shortfall in pairs(shortfalls) do
            lines[#lines + 1] = { itemID = itemID, shortfall = shortfall }
        end
        return lines
    end,
}

local savedFrame, savedHook, savedTimer = AuctionHouseFrame, hooksecurefunc, C_Timer

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers()
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
end

-- hooksecurefunc on a table: run the hook after the original.
hooksecurefunc = function(t, method, hook)
    local original = t[method]
    t[method] = function(...)
        local a, b, c = original(...)
        hook(...)
        return a, b, c
    end
end

local function MakeBuyWindow(opts)
    opts = opts or {}
    local display = { quantity = 1 }
    function display:GetItemID() return self.itemID end
    if not opts.noSetter then
        function display:GetQuantitySelected() return self.quantity end
        function display:SetQuantitySelected(n) self.quantity = n end
    end
    if opts.inputOnly then
        display.QuantityInput = {
            InputBox = {
                GetNumber = function() return display.quantity end,
                SetNumber = function(_, n) display.quantity = n end,
            },
        }
    end

    local frame = { BuyDisplay = display, onShow = {} }
    function frame:SetItemIDAndPrice(itemID)
        -- Blizzard opens at 1 for each item it is set to.
        self.BuyDisplay.itemID = itemID
        self.BuyDisplay.quantity = 1
    end
    function frame:HookScript(script, fn) self.onShow[#self.onShow + 1] = fn end
    function frame:Show() for _, fn in ipairs(self.onShow) do fn(self) end end

    AuctionHouseFrame = { CommoditiesBuyFrame = frame }
    return frame, display
end

assert(loadfile(lfs_cwd .. "/UI/BuyQuantity.lua"))("Blackthornes_TS", ns)
local BQ = ns.BuyQuantity

-- Before the auction UI exists: nothing to hook, the probe says so.
AuctionHouseFrame = nil
assert(BQ:Hook() == false)
assert(BQ:ProbeText():find("open the auction house"), BQ:ProbeText())

local frame, display = MakeBuyWindow()
assert(BQ:Hook() == true)
assert(BQ:Hook() == false, "a frame is hooked once")
assert(BQ:ProbeText() == "yes", BQ:ProbeText())

-- A Buy list search for Copper Ore (20 short), then picking it: filled.
BQ:Want(2589, 20)
frame:SetItemIDAndPrice(2589, 100)
assert(display.quantity == 20, "filled with the shortfall, got " .. tostring(display.quantity))
assert(BQ:ProbeText() == "yes, last: filled 20", BQ:ProbeText())

-- Blizzard puts it back to 1 as its results arrive: the second look fills again.
display.quantity = 1
RunTimers()
assert(display.quantity == 20)

-- A number the player typed is left alone.
display.quantity = 7
RunTimers()
BQ:Fill()
assert(display.quantity == 7, "never write over the player's number")

-- Another item picked in the results: not the one searched for, left at 1.
frame:SetItemIDAndPrice(2770, 50)
assert(display.quantity == 1)

-- Bought 12 since: picking it again asks the queue now, and says 8.
shortfalls[2589] = 8
frame:SetItemIDAndPrice(2589, 100)
assert(display.quantity == 8, "the live shortfall, got " .. tostring(display.quantity))

-- Off the list now (bought it all): nothing still needed, nothing filled.
shortfalls[2589] = 0
frame:SetItemIDAndPrice(2589, 100)
assert(display.quantity == 1)
shortfalls[2589] = 20

-- Not on the list at all: the number the search had stands in.
BQ:Want(4306, 15)
frame:SetItemIDAndPrice(4306, 100)
assert(display.quantity == 15)

-- A search from anywhere else (no quantity) forgets: nothing filled.
BQ:Want(2589, nil)
frame:SetItemIDAndPrice(2589, 100)
assert(display.quantity == 1)
assert(BQ.want == nil)

-- Turned off in Settings: nothing filled.
settings.fillBuyQuantity = false
BQ:Want(2589, 20)
frame:SetItemIDAndPrice(2589, 100)
assert(display.quantity == 1)
settings.fillBuyQuantity = nil

-- Shown some other way than SetItemIDAndPrice: the OnShow hook fills it.
display.itemID, display.quantity = 2589, 1
frame:Show()
assert(display.quantity == 20)

-- A client with only the input box still gets the number.
local frame2, display2 = MakeBuyWindow({ noSetter = true, inputOnly = true })
assert(BQ:Hook() == true)
assert(BQ:HasQuantityBox())
BQ:Want(2589, 20)
frame2:SetItemIDAndPrice(2589, 100)
assert(display2.quantity == 20, "set through the input box, got " .. tostring(display2.quantity))

-- No quantity box at all: nothing raises, the probe says so.
local frame3 = MakeBuyWindow({ noSetter = true })
BQ:Hook()
BQ:Want(2589, 20)
frame3:SetItemIDAndPrice(2589, 100)
assert(not BQ:HasQuantityBox())
assert(BQ:ProbeText():find("no quantity box"), BQ:ProbeText())

-- A frame whose parts raise when touched: still no error.
AuctionHouseFrame = setmetatable({}, { __index = function() error("secret") end })
assert(BQ:Fill(2589) == false)
assert(BQ:Hook() == false)

AuctionHouseFrame, hooksecurefunc, C_Timer = savedFrame, savedHook, savedTimer
print("test_buyquantity: ok")
