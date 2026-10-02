-- The Profit tab's queue box, profession dropdown and detail summary, drawn
-- without a game client.
--
-- What must hold:
--   1. After Add to queue the box suggests again from what is now queued. It
--      kept the old amount, because the redraw Queue:Add makes runs before
--      the click handler finishes, and a second click queued it all again
--      over Keep in stock.
--   2. At "room for 0" the box says 0, as Max does, not 1. Add then queues
--      nothing rather than one past the limit.
--   3. The profession dropdown names "All professions" when the tab opens.
--      Its face stayed blank until something was picked.
--   4. A craft valued at what a vendor pays says so: "Vendor pays", no
--      auction cut, no deposit.
--   5. Hidden summary rows ("Your listing" with nothing listed) leave no
--      blank line between the rows shown.
--   6. An unpriced row keeps its STOCK count.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "CreateFrame", "UIParent", "GameTooltip", "C_Timer", "GetTime" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

-- Frames whose methods do nothing unless named here; fields read as nil.
local function NewFrame(kind)
    local f = { kind = kind, scripts = {}, shown = true, text = "", points = {} }

    setmetatable(f, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })

    f.SetScript = function(self, n, fn) self.scripts[n] = fn end
    f.GetScript = function(self, n) return self.scripts[n] end
    f.HookScript = function(self, n, fn)
        local old = self.scripts[n]
        self.scripts[n] = function(...) if old then old(...) end fn(...) end
    end
    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.SetShown = function(self, v) self.shown = v and true or false end
    f.IsShown = function(self) return self.shown end
    f.IsVisible = function(self) return self.shown end
    f.SetText = function(self, t) self.text = t end
    f.GetText = function(self) return self.text end
    f.SetTextColor = function(self, color) self.color = color end
    f.SetWordWrap = function(self, wrap) self.wrap = wrap end
    f.GetStringWidth = function(self) return #tostring(self.text or "") * 6 end
    f.CreateTexture = function() return NewFrame() end
    f.CreateFontString = function() return NewFrame() end
    -- Each anchor point remembers where it was last put.
    f.SetPoint = function(self, point, ...) self.points[point] = { ... } end
    f.ClearAllPoints = function(self) self.points = {} end
    f.GetParent = function() return NewFrame() end
    f.HasFocus = function() return false end
    return f
end

CreateFrame = function(kind) return NewFrame(kind) end
UIParent = NewFrame()
GameTooltip = NewFrame()
C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }
GetTime = function() return 1000 end

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-62s %-14s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = noop, noop
local said = {}
ns.Print = function(text) said[#said + 1] = text end
ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop

-- Every label, with the frame it was made on; the detail pane is the one
-- panel made as a "window".
local labels, detail = {}, nil
ns.Theme = setmetatable({
    FONT = "font",
    sizes = { tiny = 10, small = 11, normal = 12, large = 14, title = 16 },
    CreateLabel = function(parent)
        local label = NewFrame("FontString")
        label.parent = parent
        labels[#labels + 1] = label
        return label
    end,
    CreatePanel = function(_, background)
        local panel = NewFrame("Frame")
        if background == "window" then detail = panel end
        return panel
    end,
    Unpack = function(key) return key end,
    ProfitColor = function(value) return (value or 0) >= 0 and "profit" or "loss" end,
    CreateHeading = function() local h = NewFrame(); h.rule = NewFrame(); return h end,
}, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return function() return NewFrame() end end
end })

ns.Config = { Get = function() return nil end }
ns.Util = {
    GetItemQualityColor = noop,
    FormatMoney = function(copper) return tostring(copper or 0) end,
    FormatAge = function() return "1h" end,
    GetItemLabel = function(itemID) return "item" .. tostring(itemID) end,
    HasFunction = function() return false end,
}

assert(loadfile(lfs_cwd .. "/UI/Widgets.lua"))("Blackthornes_TS", ns)
-- The real Profit module, for MaxCrafts; the list and the analyses are
-- this test's own.
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)

local dropdowns, buttons, list = {}, {}, nil
local realDropdown, realButton = ns.Widgets.CreateDropdown, ns.Widgets.CreateButton
ns.Widgets.CreateDropdown = function(...)
    local dropdown = realDropdown(...)
    dropdowns[#dropdowns + 1] = dropdown
    return dropdown
end
ns.Widgets.CreateButton = function(parent, text, onClick, opts)
    buttons[text] = onClick
    return realButton(parent, text, onClick, opts)
end
ns.Widgets.CreateScrollList = function(_, opts)
    list = NewFrame()
    list.opts = opts
    list.SetData = function(self, data) self.data = data end
    return list
end

-- One craft: Keep in stock 5, nothing held, materials for 10 crafts.
local LIMIT, queued = 5, 0
local extra = {}
local function Analysis(recipeID)
    local room = math.max(0, LIMIT - queued)
    local analysis = { recipeID = recipeID or 1, name = "Linen Bag", outputItemID = 11, priceable = true,
        totalCost = 90, revenue = 700, unitRevenue = 700, cut = 35, profit = 575, margin = 0.8,
        craftableNow = 10, cost = { reagents = {} }, stock = 0, posted = 0, onHand = 0, inMail = 0,
        queuedElsewhere = queued, postLimit = LIMIT, postRoom = room, roomInCrafts = room,
        atPostLimit = room <= 0, priceBasis = "market", depositKnown = true, deposit = 6 }
    for key, value in pairs(extra) do analysis[key] = value end
    return analysis
end

local tabs = {}
ns.UI = setmetatable({ RegisterTab = function(_, tab) tabs[tab.key] = tab end },
    { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return noop end end })

ns.Profit.GetRanked = function() return { Analysis() } end
ns.Profit.Analyse = function(_, recipeID) return Analysis(recipeID) end
ns.Recipes = { Count = function() return 1 end, GetAll = function() return {} end,
    GetAccountWide = function() return {} end, IsDropped = function() return false end }
ns.Prices = { Count = function() return 1 end }
ns.Auctions = { SetLimit = noop }
ns.db = { characters = {} }

-- Queue:Add redraws the tab before it returns, as Logic/Queue.lua does:
-- Queue:Notify, UI:OnQueueUpdated, UI:RefreshActiveTab, the tab's refresh.
ns.Queue = { Add = function(_, _, count)
    queued = queued + count
    tabs.profit.refresh()
    return true
end }

assert(loadfile(lfs_cwd .. "/UI/Tab_Profit.lua"))("Blackthornes_TS", ns)

tabs.profit.build(NewFrame())
-- Opening the tab: onShow, then refresh, as UI:SelectTab does.
tabs.profit.onShow()
tabs.profit.refresh()

local box = detail.quantity
local function Add() buttons["Add to queue"]() end

print("")
print("the queue box")

list.opts.onClick(Analysis(), 1, "LeftButton")
check("a craft with room for 5 suggests 5", box:GetText(), "5")
Add()
check("Add queues 5", queued, 5)
check("and the box then says 0, the room left", box:GetText(), "0")
Add()
check("a second click queues nothing more", queued, 5)
tabs.profit.refresh()
check("a later redraw keeps 0", box:GetText(), "0")
list.opts.onClick(Analysis(2), 1, "LeftButton")
check("another craft already at its limit starts at 0", box:GetText(), "0")
Add()
check("and Add queues none of it", queued, 5)

queued = 3
list.opts.onClick(Analysis(3), 1, "LeftButton")
check("room for 2 suggests 2", box:GetText(), "2")

print("")
print("the profession dropdown")

local face
for _, label in ipairs(labels) do
    if label.parent == dropdowns[1] then face = label break end
end
check("it names All professions when the tab opens", face and face.text, "All professions")

print("")
print("valued at what a vendor pays")

local function Row(name)
    for _, row in ipairs(detail.summaryRows) do
        if row.label.text == name then return row end
    end
end

extra = { priceBasis = "vendor", unitRevenue = 80, cut = 0, deposit = 0 }
list.opts.onClick(Analysis(4), 1, "LeftButton")
check("the price row says Vendor pays", Row("Vendor pays") ~= nil, true)
check("with the vendor's price", Row("Vendor pays") and Row("Vendor pays").value.text, "80")
check("no auction cut", Row("Auction cut").value.text, "none")
check("no deposit", Row("Deposit").value.text, "none")

extra = {}
list.opts.onClick(Analysis(5), 1, "LeftButton")
check("a listing says You post at again", Row("You post at") ~= nil, true)
check("with the cut taken", Row("Auction cut").value.text, "-35")
check("and the deposit", Row("Deposit").value.text, "-6")

print("")
print("the summary rows")

-- Rows by place: materials, rival, your listing, price, cut, deposit,
-- profit, disenchant value.
local RIVAL, OWN, PRICE, PROFIT = 2, 3, 4, 7
local function Top(index) return detail.summaryRows[index].label.points.TOPLEFT[2] end

-- Nothing of yours listed and nothing to disenchant: two rows hidden.
check("Your listing is hidden", detail.summaryRows[OWN].label.shown, false)
check("the rows shown sit together: rival, then price", Top(RIVAL) - Top(PRICE), 17)
check("and they sit at the bottom, where the hidden ones were", Top(PROFIT), -119)

extra = { ownListing = 650, disenchantable = true }
list.opts.onClick(Analysis(6), 1, "LeftButton")
check("with a listing of yours, its row shows", detail.summaryRows[OWN].label.shown, true)
check("between the rival and the price", Top(OWN) - Top(PRICE), 17)
check("and every row is in its place", Top(1), 0)

print("")
print("an unpriced row")

local row = NewFrame()
list.opts.createRow(row)
list.opts.updateRow(row, { recipeID = 7, name = "Odd Kit", outputItemID = 12, priceable = false,
    reason = "output has no price data", stock = 3, postLimit = 5 })
check("keeps its STOCK count", row.cells.posted.text, "3/5")
check("and says why it has no profit", row.cells.profit.text, "no price")

print("")
print("text that would not fit on one line wraps")

check("the subtitle", detail.subtitle.wrap, true)
check("the Keep in stock hint", detail.limitHint.wrap, true)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "Profit tab checks failed")
