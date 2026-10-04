-- The Buy materials button on the vendor window, outside WoW.
--
-- What must hold:
--   1. A vendor closed inside the 0.2s wait after it opened leaves no button
--      behind. It used to come back over the game world, reading "Nothing
--      needed here", until the next vendor was closed.
--   2. Nothing shows the button once the vendor has closed, whoever asks.
--   3. A cost too long for the button widens it, to the left, so the label
--      is never cut to "...". It goes back to its own width for "Nothing
--      needed here" and "Buying...".
--   4. The tooltip's first line carries the total.
--   5. After buying, the button waits for the bags to hold what was bought,
--      then reads "Nothing needed here". It used to redraw from the old
--      counts the moment the run ended and offer the same materials again
--      (2026-10-03: 12 Coarse Thread bought, "Buy materials 1s 8c"
--      still showing). A bag update at the vendor redraws it too.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "CreateFrame", "UIParent", "MerchantFrame", "C_Timer", "C_MerchantFrame",
    "GetMerchantNumItems", "GetMerchantItemLink", "time", "BuyMerchantItem", "GetMoney" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

-- Frames whose methods do nothing unless named here; fields read as nil.
-- A label is as wide as its words, 7 pixels a letter, colour codes taking
-- no room, however narrow the button holding it.
local function NewFrame()
    local f = { shown = true, text = "", width = 0, height = 0, points = {} }
    setmetatable(f, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })

    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.IsShown = function(self) return self.shown end
    f.SetText = function(self, t) self.text = t end
    f.GetText = function(self) return self.text end
    f.SetWidth = function(self, w) self.width = w end
    f.GetWidth = function(self) return self.width end
    f.SetSize = function(self, w, h) self.width, self.height = w, h end
    f.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
    f.ClearAllPoints = function(self) self.points = {} end
    f.GetStringWidth = function(self)
        local plain = tostring(self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return #plain * 7
    end
    return f
end

CreateFrame = function() return NewFrame() end
UIParent = NewFrame()
MerchantFrame = NewFrame()
time = function() return 100000 end

local timers = {}
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
local function RunTimers()
    local due = timers
    timers = {}
    for _, timer in ipairs(due) do timer.fn() end
end

-- Every timer under a second, and the ones they start, leaving the longer
-- waits for later: a whole purchase run, with nothing given time to arrive.
local function RunShortTimers()
    for _ = 1, 100 do
        local due, kept = {}, {}
        for _, timer in ipairs(timers) do
            if timer.delay < 1 then due[#due + 1] = timer else kept[#kept + 1] = timer end
        end
        if #due == 0 then return end
        timers = kept
        for _, timer in ipairs(due) do timer.fn() end
    end
end

-- One vendor selling thread at 1g 50s 50c, so the cost on the button is
-- long enough to need the room.
local THREAD = 2320
local vendorOpen = false
C_MerchantFrame = {
    GetItemInfo = function(index)
        if vendorOpen and index == 1 then
            return { price = 15050, stackCount = 1, numAvailable = -1, hasExtendedCost = false }
        end
    end,
}
GetMerchantNumItems = function() return vendorOpen and 1 or 0 end
GetMerchantItemLink = function(index)
    if vendorOpen and index == 1 then return ("|cffffffff|Hitem:%d|h[Thread]|h|r"):format(THREAD) end
end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop

local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn; return true end
local function Fire(event) handlers[event](event) end

ns.db = {}
local shortfall = 1
ns.Queue = {
    GetShoppingList = function() return { { itemID = THREAD, shortfall = shortfall } } end,
    Count = function() return 1 end,
}
ns.Cost = { InvalidateIndex = noop }

-- The game's look is not under test: a button is a frame with a label, as
-- Widgets.CreateButton makes it.
ns.Theme = { AddGameOutline = noop }
ns.Widgets = {
    CreateButton = function(_, text, onClick, opts)
        local button = NewFrame()
        button:SetSize(opts.width or 90, opts.height or 22)
        button.label = NewFrame()
        button.label:SetText(text)
        button.SetText = function(self, value) self.label:SetText(value) end
        button.SetEnabledState = function(self, enabled) self.disabled = not enabled end
        button.onClick = onClick
        return button
    end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Vendor.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/Main.lua"))("Blackthornes_TS", ns)

local Vendor, UI = ns.Vendor, ns.UI
Vendor:OnEnable()

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-62s %-8s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Shown()
    return UI.merchantButton ~= nil and UI.merchantButton:IsShown()
end

local function Open()
    vendorOpen = true
    Fire("MERCHANT_SHOW")
    RunTimers()
end

local function Close()
    vendorOpen = false
    Fire("MERCHANT_CLOSED")
end

print("")
print("a vendor closed inside the wait")

vendorOpen = true
Fire("MERCHANT_SHOW")
Close()
RunTimers()
check("no button comes up after it closed", Shown(), false)

vendorOpen = true
Fire("MERCHANT_UPDATE")
Close()
RunTimers()
check("an update after it closed reads nothing", Vendor.merchantItems, nil)

print("")
print("nothing shows the button once the vendor has closed")

UI:AttachToMerchant()
check("attaching with no vendor open makes no button", UI.merchantButton, nil)

Open()
check("opening a vendor shows it", Shown(), true)
Vendor.isMerchantOpen = false
UI:AttachToMerchant()
check("attaching once it has closed hides it", Shown(), false)
Close()

print("")
print("the cost fits on the button")

Open()
local button = UI.merchantButton
local label = button.label
check("it reads the whole cost", label:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""),
    "Buy materials  1g 50s 50c")
check("too long for 170 at rest", label:GetStringWidth() + 8 > 170, true)
check("so the button is wider than 170", button:GetWidth() > 170, true)
check("with room for the label inside its insets", button:GetWidth() - 8 >= label:GetStringWidth(), true)
check("hung by its right corner, so it grows to the left", button.points[1] and button.points[1][1], "BOTTOMRIGHT")
check("the tooltip opens with the total",
    (button.tooltipText or ""):match("^[^\n]*"), "Buys 1 material for your queue, 1g 50s 50c in all:")

shortfall = 0
UI:UpdateMerchantButton()
check("nothing needed: back to 170", button:GetWidth(), 170)
check("reading Nothing needed here", label:GetText(), "Nothing needed here")

shortfall = 1
UI:UpdateMerchantButton()
check("needed again: wide again", button:GetWidth() > 170, true)

Vendor.buying = true
UI:UpdateMerchantButton()
check("buying: back to 170", button:GetWidth(), 170)
check("reading Buying...", label:GetText(), "Buying...")
Vendor.buying = nil

print("")
print("after buying, it waits for the bags")

-- The shortfall follows the bags, as the real shopping list does, and the
-- bags only fill when the test says the purchase has arrived.
local inBags, needed, bought = 0, 12, 0
ns.Inventory = {
    GetBagCount = function() return inBags end,
    InvalidateBagCounts = noop,
}
ns.Queue.GetShoppingList = function()
    return { { itemID = THREAD, shortfall = math.max(0, needed - inBags) } }
end
BuyMerchantItem = function(_, amount) bought = bought + amount end
GetMoney = function() return 10000000 end
UI.RefreshActiveTab = noop

UI:UpdateMerchantButton()
check("12 short: offers to buy", label:GetText():match("^Buy materials") ~= nil, true)

button.onClick()
RunShortTimers()
check("bought all 12", bought, 12)
check("bags not caught up: still reads Buying...", label:GetText(), "Buying...")
check("and cannot be clicked again", button.disabled, true)

inBags = 12
Fire("BAG_UPDATE_DELAYED")
check("bags caught up: Nothing needed here", label:GetText(), "Nothing needed here")

print("")
print("a purchase that never arrives")

inBags, bought = 0, 0
UI:UpdateMerchantButton()
button.onClick()
RunShortTimers()
check("still waiting", label:GetText(), "Buying...")
RunTimers()
check("the wait ends: drawn from the bags as they are", label:GetText():match("^Buy materials") ~= nil, true)

print("")
print("bags change at the vendor")

inBags = 12
Fire("BAG_UPDATE_DELAYED")
check("the button redraws", label:GetText(), "Nothing needed here")

Close()
check("closing the vendor hides it", Shown(), false)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "merchant button checks failed")
