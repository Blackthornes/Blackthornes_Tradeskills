-- The Sales tab: what the ledger says actually happened.
--
-- Three things here are easy to get wrong and expensive to get wrong in game.
--
-- The first is a sale that paid nothing. The ledger already recorded one of
-- those once -- a Linen Reagent Bag "sold for 0c", because the auction house
-- holds the gold for a while and the mail's money field reads zero until it is
-- released. A tab that prints a bare 0c next to an expiry is that same bug
-- shown back to the player, so an expiry shows no amount at all and a sale
-- still being paid out says so.
--
-- The second is quantity. A sale leaves no attachment behind, so nothing in
-- the ledger knows whether a stack of twenty sold or a single item did. The
-- tab must not print "1" as though it did know.
--
-- The third is carried-over history. What survives a client restart is a
-- per-item rollup, not the individual sales, so it can appear in the By item
-- view and in the totals but can never appear in a list of events. The tab has
-- to say so rather than let the footer and the list disagree.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn =
    function() end, function() end, function() end, function() end

local registeredEvents = {}
ns.RegisterEvent = function(_, event, fn)
    registeredEvents[event] = fn
    return true
end

time = time or os.time
local NOW = time()

--------------------------------------------------------------------------------
-- A widget layer that only remembers what was written to it
--------------------------------------------------------------------------------

local function Stub(fields)
    local frame = fields or {}

    frame.GetParent = frame.GetParent or function() return Stub() end
    frame.IsVisible = frame.IsVisible or function() return true end

    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

local function Label()
    return Stub({
        text = "",
        color = nil,
        shown = true,
        SetText = function(self, value) self.text = tostring(value) end,
        SetTextColor = function(self, a, b, c) self.color = { a, b, c } end,
        SetShown = function(self, value) self.shown = value and true or false end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
    })
end

CreateFrame = function() return Stub() end
C_Timer = { After = function() end, NewTicker = function() return Stub() end }

-- Every label the tab builds, in creation order, so an assertion can reach the
-- summary and the carried-over note without the tab having to expose them.
local labels = {}

ns.Theme = {
    FONT = "font",
    sizes = { tiny = 10, small = 11, normal = 12, large = 14, title = 16 },
    CreateLabel = function()
        local label = Label()
        labels[#labels + 1] = label
        return label
    end,
    CreatePanel = function() return Stub() end,
    CreateDivider = function() return Stub() end,
    Unpack = function(key) return key end,
    ProfitColor = function(value) return (value or 0) >= 0 and "profit" or "loss" end,

    -- The house trim: drawn, never asserted on.
    AccentStripe = function() return Stub() end,
    CreateItemIcon = function() return Stub() end,
    SetItemIcon = function() end,
}

-- The tab's only way to change view is the dropdown's callback, so the stub
-- keeps hold of it.
local selectView

ns.Widgets = {
    CreateSearchBox = function() return Stub() end,
    CreateDropdown = function(_, _, onSelect)
        selectView = onSelect
        return Stub()
    end,
    CreateCheckbox = function() return Stub() end,
    CreateNumberBox = function() return Stub() end,
    CreateButton = function() return Stub() end,
}

--------------------------------------------------------------------------------
-- What the client knows
--------------------------------------------------------------------------------

local BLUE = { 0.00, 0.44, 0.87 }
local quality = {}

ns.Util = {
    -- An old "Name-Realm" key reads as the name (Core/Util.lua).
    CharacterName = function(key) return (key or ""):match("^([^%-]+)") or "" end,
    GetItemQualityColor = function(itemID)
        local color = quality[itemID]
        if not color then return end
        return color[1], color[2], color[3]
    end,

    GetItemLabel = function(itemID) return "item" .. tostring(itemID) end,

    -- Copper, plainly, so an assertion can say what a cell holds.
    FormatMoney = function(copper) return tostring(copper or 0) .. "c" end,
    FormatAge = function() return "1h" end,
    FormatAgeAgo = function(seconds) return seconds and "1h ago" or "never" end,
    HasFunction = function() return false end,
    Count = function(tbl)
        local n = 0
        for _ in pairs(tbl or {}) do n = n + 1 end
        return n
    end,
    SortedKeys = function() return {} end,
}

ns.Config = {
    Get = function() return nil end,
    GetRealmKey = function() return "Realm" end,
    GetCharacterKey = function() return "Bob-Realm" end,
}

ns.Recipes = {
    GetAll = function() return {} end,
    GetAccountWide = function() return {} end,
    GetCharacterRecord = function() return { mail = {} } end,
}

ns.Profit = { Analyse = function() return nil end }

-- Set per case. nil means nothing was carried over from before the restart.
local restoredRollup

ns.db = { mailLedger = {} }

--------------------------------------------------------------------------------
-- Load the real Mail module, then the tab
--------------------------------------------------------------------------------

do
    local chunk = assert(loadfile(lfs_cwd .. "/Data/Mail.lua"))
    chunk("Blackthornes_TS", ns)
end

-- The carried-over history is read from the saved database; stand in for it.
ns.Mail.GetRestoredRollup = function() return restoredRollup end

local createRow, updateRow, listData

ns.Widgets.CreateScrollList = function(_, opts)
    createRow, updateRow = opts.createRow, opts.updateRow

    return Stub({
        SetData = function(_, data) listData = data end,
        IsVisible = function() return true end,
    })
end

local tab
ns.UI = Stub({
    RegisterTab = function(_, registered) tab = registered end,
})

do
    local chunk = assert(loadfile(lfs_cwd .. "/UI/Tab_Sales.lua"))
    chunk("Blackthornes_TS", ns)
end

assert(tab, "Tab_Sales did not register a tab")
assert(tab.key == "sales", "the tab did not register under the key 'sales'")

tab.build(Stub())
assert(updateRow, "Tab_Sales did not hand over its row callbacks")

local function Row(data)
    local row = Stub()
    createRow(row)
    updateRow(row, data)
    return row
end

--- Replace the ledger, and whatever survived the last restart, then redraw.
local function Given(entries, rollup)
    ns.db.mailLedger = { Realm = { entries = entries, seen = {} } }
    restoredRollup = rollup
    tab.refresh()
end

--- The text of a label the tab built, found by what it starts with.
local function LabelStartingWith(prefix)
    for _, label in ipairs(labels) do
        if type(label.text) == "string" and label.text:sub(1, #prefix) == prefix then
            return label
        end
    end
end

--------------------------------------------------------------------------------

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-14s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function contains(label, haystack, needle)
    -- Colour codes left out, so a coloured figure reads as its text.
    local plain = tostring(haystack):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    check(label, (plain:find(needle, 1, true) ~= nil), true)
end

--------------------------------------------------------------------------------

print("")
print("A sale the auction house has paid out")

local row = Row({
    kind = "sold", t = NOW, itemID = 2589, name = "Bolt of Linen Cloth",
    net = 3400, gross = 4000, cut = 600, deposit = 0,
})

check("the amount is what landed, not what was bid", row.amount.text, "3400c")
check("and it is coloured as money coming in", row.amount.color[1], "profit")
contains("the line says it sold", row.detail.text, "sold")
contains("and names the auction house's cut", row.detail.text, "cut 600c")

print("")
print("A sale whose gold is still being held")

row = Row({
    kind = "sold", t = NOW, itemID = 2589, name = "Bolt of Linen Cloth",
    net = 3400, estimated = true,
})

check("the figure is shown rather than withheld", row.amount.text, "3400c")
contains("and it says the gold has not landed yet", row.detail.text, "still held")
check("in the colour that asks to be read again later", row.detail.color[1], "warn")

print("")
print("A listing that expired")

row = Row({ kind = "expired", t = NOW, itemID = 2589, quantity = 5 })

check("earns nothing, so the money column is empty, not 0c", row.amount.text, "")
contains("the line says nobody bought it", row.detail.text, "nobody bought")
contains("and how many came back", row.detail.text, "5x")
check("coloured as a loss", row.detail.color[1], "loss")

print("")
print("A listing you cancelled yourself")

row = Row({ kind = "removed", t = NOW, itemID = 2589, quantity = 1 })

contains("is described as your doing", row.detail.text, "you cancelled")
check("and is not painted as a market failure", row.detail.color[1], "muted")

print("")
print("Quantity, which a sale does not carry")

row = Row({ kind = "sold", t = NOW, itemID = 2589, net = 100 })

check("no invented count on a sale of unknown size", row.detail.text:find("1 sold"), nil)

row = Row({ kind = "sold", t = NOW, itemID = 2589, net = 100, quantity = 20 })
contains("but a recorded stack is shown", row.detail.text, "20 sold")

print("")
print("Rarity, and an item the client has not sent yet")

quality[2589] = BLUE
row = Row({ kind = "sold", t = NOW, itemID = 2589, net = 100 })
check("the name carries the item's quality colour", row.name.color[1], BLUE[1])

row = Row({ kind = "sold", t = NOW, itemID = 99999, net = 100 })
check("an uncached item falls back to plain text", row.name.color[1], "text")
check("and the tab listens for it arriving",
    registeredEvents["GET_ITEM_INFO_RECEIVED"] ~= nil, true)

print("")
print("A sale of something with no recipe behind it")

row = Row({ kind = "sold", t = NOW, itemID = nil, name = "Mystery Tonic", net = 100 })
check("is still named rather than shown as a number", row.name.text, "Mystery Tonic")

--------------------------------------------------------------------------------

print("")
print("The ledger rolled up per item")

Given({
    { kind = "sold",    t = NOW - 300, itemID = 2589, net = 1000, cut = 100 },
    { kind = "sold",    t = NOW - 200, itemID = 2589, net = 2000, cut = 200 },
    { kind = "expired", t = NOW - 100, itemID = 2589, quantity = 1 },
    { kind = "removed", t = NOW - 50,  itemID = 2589, quantity = 1 },
    { kind = "sold",    t = NOW,       itemID = 6889, net = 500 },
})

local items = ns.Mail:GetItems()
check("one row per item, not per listing", #items, 2)

local linen
for _, item in ipairs(items) do
    if item.itemID == 2589 then linen = item end
end

check("sales are counted", linen.sold, 2)
check("the gold adds up", linen.net, 3000)
check("so does the auction house's cut", linen.cut, 100 + 200)
check("expiries are counted", linen.expired, 1)
check("cancellations are kept apart from them", linen.cancelled, 1)
check("sell-through leaves your own cancellation out", linen.sellThrough, 2 / 3)
check("and the item is dated by its most recent event", linen.lastAt, NOW - 50)

print("")
print("The By item view")

tab.refresh()  -- still in the Recent view: sales only
check("the event list shows only what sold", #listData, 3)

assert(selectView, "Tab_Sales did not hand over its view dropdown callback")

selectView("all")
check("'Recent, all' shows what came back as well", #listData, 5)

selectView("item")
check("'By item' shows one row per item", #listData, 2)
check("worth the most first", listData[1].itemID, 2589)

selectView("sales")

print("")
print("History carried over from before the client was closed")

Given({
    { kind = "sold", t = NOW, itemID = 2589, net = 1000 },
}, {
    [2589] = { sold = 4, soldUnits = 9, expired = 2, net = 8000, lastAt = NOW - 86400 },
})

items = ns.Mail:GetItems()
linen = items[1]

check("the rollup is folded in with this session's ledger", linen.sold, 5)
check("its units come with it", linen.soldUnits, 9 + 1)
check("and its gold", linen.net, 9000)
check("expiries from before the restart count too", linen.expired, 2)
check("and the row says where the figures came from", linen.restored, true)

local carried = LabelStartingWith("plus ")
check("the list says how many sales it cannot show",
    carried and carried.text or "(no note)",
    "plus 4 sales from before you last quit the game. See By item")
check("and only while there is something to say", carried.shown, true)

-- The count used to be worked out by subtracting this session's sales from
-- the per-item figures, which lost one for every item that sold this session
-- and had no history behind it. This is that case.
Given({
    { kind = "sold", t = NOW, itemID = 2589, net = 1000 },
    { kind = "sold", t = NOW, itemID = 6889, net = 700 },
}, {
    [2589] = { sold = 4, soldUnits = 9, expired = 2, net = 8000, lastAt = NOW - 86400 },
})

carried = LabelStartingWith("plus ")
contains("an item with no history behind it does not eat a carried sale",
    carried.text, "plus 4 sales")

print("")
print("Nothing carried over")

Given({ { kind = "sold", t = NOW, itemID = 2589, net = 1000 } }, nil)

carried = LabelStartingWith("plus ")
check("the note stays out of the way", carried.shown, false)

local summary = LabelStartingWith("1 sold")
check("the footer totals what is there",
    summary and summary.text or "(no footer)",
    "1 sold  ·  taken in 1000c  ·  100% sell-through")

print("")
print("An empty ledger")

Given({}, nil)

local empty = LabelStartingWith("Nothing recorded yet")
check("says where sales come from rather than showing a blank list",
    empty ~= nil, true)
contains("and names the mailbox", empty.text, "mailbox")

print("")
print("The Mailbox visits view")

local savedHaul = { t = NOW - 60, who = "Tester Surname-Realm", total = 52000, salesCount = 3,
    best = { name = "Bolt of Linen Cloth", itemID = 2589, amount = 30000 }, itemCount = 2 }
local reopened
ns.MailHaul = {
    GetHistory = function() return { { t = NOW - 7200, total = 900 }, savedHaul } end,
    Records = function() return 52000 end,
}
ns.MailReport = { Show = function(_, haul) reopened = haul end }

selectView("visits")
check("one row per visit", #listData, 2)
check("newest first", listData[1].total, 52000)
check("nothing is written into the saved visit", rawget(savedHaul, "haul"), nil)

local visitRow = Row(listData[1])
contains("says what was collected", visitRow.name.text, "Collected")
contains("names the best sale", visitRow.detail.text, "best Bolt of Linen Cloth")
contains("and the character, first name and all", visitRow.detail.text, "Tester Surname")

contains("the footer counts the visits", LabelStartingWith("2 visits").text, "best haul")

ns.MailHaul, ns.MailReport = nil, nil
selectView("sales")

--------------------------------------------------------------------------------

print("")
print("A sale heard in chat, before its mail is read")

ns.db.heardSales = {}
Given({})
ns.Mail:NoteHeardSale("Bolt of Linen Cloth")

row = Row(setmetatable({ kind = "heard" }, { __index = ns.Mail:GetHeard()[1] }))
check("the amount column says it sold", row.amount.text, "sold")
contains("and that the gold is in the mail", row.detail.text, "waiting in the mail")
contains("naming the character", row.detail.text, "Bob")

selectView("sales")
check("Recent sales lists it straight away", #listData, 1)
check("as a heard sale", listData[1].kind, "heard")
check("nothing is written onto the saved heard sale",
    rawget(ns.db.heardSales.Realm[1], "kind"), nil)
contains("the footer counts it as waiting", LabelStartingWith("0 sold").text, "1 waiting in the mail")

print("")
print("Its mail arrives")

local paid = { kind = "sold", t = NOW + 10, who = "Bob-Realm",
    name = "Bolt of Linen Cloth", net = 3400 }
Given({ paid })
check("the heard sale gives way to the real one", #listData, 1)
check("which is the ledger's entry", listData[1].kind, "sold")
check("the heard list is empty again", #ns.db.heardSales.Realm, 0)
check("the ledger entry is marked as heard", paid.heard, true)

ns.Mail:NoteHeardSale("Bolt of Linen Cloth")
tab.refresh()
check("an earlier sale's mail does not settle a newer one", #ns.Mail:GetHeard(), 1)
check("so both show", #listData, 2)

ns.db.heardSales.Realm = {}
Given({})

print("")
print("Still listed")

local listings = {
    { itemID = 2589, quantity = 20, unit = 30, ends = NOW + 7200, who = "Bob-Realm" },
    { itemID = 2590, quantity = 1, unit = 500, ended = true, who = "Alt-Realm" },
}
ns.Auctions = { GetListings = function() return listings, 2 end }

selectView("listed")
check("one row per listing", #listData, 2)
check("still up comes first", listData[1].itemID, 2589)
check("nothing is written onto the reading", rawget(listings[1], "listing"), nil)

row = Row(listData[1])
check("the amount is the whole listing", row.amount.text, "600c")
contains("says how many", row.detail.text, "20 listed")
contains("and the price each", row.detail.text, "30c each")
contains("and when it ends", row.when.text, "ends in")

row = Row(listData[2])
check("an ended listing says so", row.when.text, "ended")
contains("and where it went", row.detail.text, "sold or back in the mail")
contains("the footer counts both", LabelStartingWith("1 still listed").text, "1 ended since")

ns.Auctions = { GetListings = function() return {}, 0 end }
tab.refresh()
check("never read says to open the auction house", LabelStartingWith("Open the auction house") ~= nil, true)

ns.Auctions = nil
selectView("sales")

--------------------------------------------------------------------------------

print("")
print("Profit on each sale (asked by two players, 2026-10-06)")

do
    local chunk = assert(loadfile(lfs_cwd .. "/Logic/CraftedCost.lua"))
    chunk("Blackthornes_TS", ns)
end

-- Linen was made for 800 an hour before these sold; the potion never was.
ns.db.craftedCosts = { Realm = { [2589] = { cost = 800, at = NOW - 3600 } } }

Given({
    { kind = "sold", t = NOW - 300, itemID = 2589, net = 1000, cut = 100 },
    { kind = "sold", t = NOW - 200, itemID = 2589, net = 2100, cut = 200, deposit = 100 },
    { kind = "sold", t = NOW,       itemID = 6889, net = 500 },
})

row = Row(listData[3])
contains("a sale says what one cost", row.detail.text, "cost 800c")
contains("and what it made", row.detail.text, "profit +200c")
check("the cut gives way to the profit", row.detail.text:find("cut ", 1, true), nil)

row = Row(listData[2])
contains("the deposit handed back is not profit", row.detail.text, "profit +1200c")

row = Row(listData[1])
check("a sale with no cost shows no profit", row.detail.text:find("profit", 1, true), nil)
contains("and keeps its cut line when it has one", Row({ kind = "sold", t = NOW, itemID = 6889, net = 9, cut = 1 }).detail.text, "cut 1c")

items = ns.Mail:GetItems()
for _, item in ipairs(items) do
    if item.itemID == 2589 then linen = item end
end
check("the item adds its sales' profit", linen.profit, 1400)
check("both from a real craft cost", linen.costed, 2)

contains("the footer gives the total", LabelStartingWith("3 sold").text, "profit +1400c on 2")

row = Row(linen)
contains("the item row says it too", row.detail.text, "profit +1400c")

local loss = Row({ kind = "sold", t = NOW, itemID = 2589, net = 500 })
contains("a loss is shown signed", loss.detail.text, "profit -300c")

-- A sale written down with its own cost keeps it after a dearer craft.
ns.db.craftedCosts.Realm[2589] = { cost = 5000, at = NOW - 3600 }
row = Row({ kind = "sold", t = NOW, itemID = 2589, net = 1000, cost = 800 })
contains("the cost it sold at wins over the last craft", row.detail.text, "profit +200c")

ns.db.craftedCosts = nil

print("")
print(string.format("%d passed, %d failed", passed, failed))

if failed > 0 then
    error(string.format("test_sales: %d check(s) failed", failed))
end
