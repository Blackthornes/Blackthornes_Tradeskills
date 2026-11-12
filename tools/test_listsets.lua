-- Buy Sets (Logic/ListSets.lua, 2026-11-12).
--
-- What must hold:
--   1. Fit keeps the list's ratio: 2 of one to 1 of another buys 2n and n.
--   2. Listings over Most I'll Pay and the player's own don't count.
--   3. When one item runs short, every row drops to match it, and that row
--      is marked short.
--   4. Nothing fits under a limit of 0 or below the price of one set.
--   5. Start needs a limit and an open auction house; it reads each item,
--      then works out the sets.
--   6. Buy asks, Confirm pays; a price past the limit stops the run and
--      nothing is paid.
--   7. A buy that goes through is Got; the next row is the active one.
--   8. Stop and the auction house closing end the run.
--   9. The Lists view: a foot row under a user list with wants, none under
--      the craft queue's list; while a run is ready the rows are the sets.

local function noop() end

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn; return true end
local said = {}
ns.Notice = { Show = function(_, text) said[#said + 1] = text end }
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.L = setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local functions = {}
ns.Util = {
    HasFunction = function(path) return functions[path] == true end,
    FormatMoney = function(c) return tostring(c) end,
}

local timers = {}
local oldTimer = C_Timer
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function Flush()
    local list = timers
    timers = {}
    for _, fn in ipairs(list) do fn() end
end

assert(loadfile(lfs_cwd .. "/Logic/ListSets.lua"))("Blackthornes_TS", ns)
local ListSets = ns.ListSets
ListSets:Init()

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\nbuy sets")

local HERB, VIAL, OIL = 2447, 3371, 2678

-- 1. The ratio.
do
    local fit = ListSets.Fit(
        { { itemID = HERB, ratio = 2 }, { itemID = VIAL, ratio = 1 } },
        { [HERB] = { { unitPrice = 10, quantity = 100 } }, [VIAL] = { { unitPrice = 5, quantity = 100 } } },
        250)
    -- one set is 2 x 10 + 5 = 25, so 10 sets.
    check("2 to 1 fits 10 sets in 250", fit.sets == 10 and fit.total == 250)
    check("each row buys its share", fit.rows[1].buy == 20 and fit.rows[2].buy == 10)
    check("nothing is short when gold holds it back", not fit.rows[1].short and not fit.rows[2].short)
end

-- Cheapest first, across several listings.
do
    local fit = ListSets.Fit({ { itemID = HERB, ratio = 1 } },
        { [HERB] = { { unitPrice = 20, quantity = 5 }, { unitPrice = 10, quantity = 2 } } }, 40)
    -- 2 at 10, then 1 at 20 = 40.
    check("cheapest listings go first", fit.sets == 3 and fit.total == 40)
end

-- 2. Most I'll Pay and own listings.
do
    local fit = ListSets.Fit({ { itemID = HERB, ratio = 1, maxPay = 15 } },
        { [HERB] = { { unitPrice = 10, quantity = 4, own = 1 }, { unitPrice = 16, quantity = 50 } } }, 10000)
    check("over Most I'll Pay and your own don't count", fit.sets == 3 and fit.rows[1].avail == 3)
    check("and the short row says so", fit.rows[1].short == true)
end

-- 3. One item short: every row drops to match it.
do
    local fit = ListSets.Fit(
        { { itemID = HERB, ratio = 2 }, { itemID = VIAL, ratio = 1 }, { itemID = OIL, ratio = 1 } },
        { [HERB] = { { unitPrice = 1, quantity = 100 } },
          [VIAL] = { { unitPrice = 1, quantity = 4 } },
          [OIL] = { { unitPrice = 1, quantity = 100 } } },
        100000)
    check("a short item holds every row to 4 sets", fit.sets == 4
        and fit.rows[1].buy == 8 and fit.rows[2].buy == 4 and fit.rows[3].buy == 4)
    check("only the short item is marked", fit.rows[2].short and not fit.rows[1].short and not fit.rows[3].short)
end

-- Nothing up at all.
do
    local fit = ListSets.Fit({ { itemID = HERB, ratio = 1 }, { itemID = VIAL, ratio = 1 } },
        { [HERB] = { { unitPrice = 1, quantity = 10 } }, [VIAL] = {} }, 100)
    check("an item with nothing up fits no sets, and is short", fit.sets == 0 and fit.rows[2].short)
end

-- 4. No gold, no sets.
do
    local listings = { [HERB] = { { unitPrice = 10, quantity = 10 } } }
    check("a limit of 0 fits nothing", ListSets.Fit({ { itemID = HERB, ratio = 1 } }, listings, 0).sets == 0)
    local fit = ListSets.Fit({ { itemID = HERB, ratio = 1 } }, listings, 9)
    check("under one set fits nothing, and nothing is short", fit.sets == 0 and not fit.rows[1].short)
end

-- 5. Start, read, fit.
local lines = {
    { itemID = HERB, want = 2 },
    { itemID = VIAL, want = 1, maxPay = 6 },
}
ns.ShoppingLists = {
    Get = function(_, key) return key == 1 and { name = "Potions" } or nil end,
    Lines = function(_, key) return key == 1 and lines or {} end,
}
local requests = {}
ns.AHQueue = { PRIORITY = { urgent = 10 },
    Request = function(_, req) requests[#requests + 1] = req; return true end,
    Cancel = noop }
local book = {
    [HERB] = { { unitPrice = 10, quantity = 30, numOwnerItems = 0 } },
    [VIAL] = { { unitPrice = 5, quantity = 8, numOwnerItems = 0 }, { unitPrice = 7, quantity = 50 } },
}
local started, confirmed, cancelled = {}, {}, 0
C_AuctionHouse = {
    MakeItemKey = function(id) return { itemID = id } end,
    SendSearchQuery = noop,
    GetNumCommoditySearchResults = function(id) return #(book[id] or {}) end,
    GetCommoditySearchResultInfo = function(id, i) return book[id][i] end,
    StartCommoditiesPurchase = function(id, n) started[#started + 1] = { id, n } end,
    ConfirmCommoditiesPurchase = function(id, n) confirmed[#confirmed + 1] = { id, n } end,
    CancelCommoditiesPurchase = function() cancelled = cancelled + 1 end,
}
for _, name in ipairs({ "MakeItemKey", "SendSearchQuery", "GetNumCommoditySearchResults",
    "GetCommoditySearchResultInfo", "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase",
    "CancelCommoditiesPurchase" }) do
    functions["C_AuctionHouse." .. name] = true
end
local money = 1000000
GetMoney = function() return money end

ns.Scanner = { isAuctionHouseOpen = false }
ListSets:Start(1, 200)
check("a closed auction house starts nothing", ListSets.run == nil and #said == 1)
ns.Scanner.isAuctionHouseOpen = true
ListSets:Start(1, 0)
check("a limit of 0 starts nothing", ListSets.run == nil)

ListSets:Start(1, 200)
check("Start reads the first item", ListSets.run and ListSets.run.phase == "reading" and #requests == 1)
requests[1].send()
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, VIAL)
check("another item's results are not taken", ListSets.run.reading.itemID == HERB)
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, HERB)
check("then reads the next", #requests == 2 and ListSets.run.reading.itemID == VIAL)
requests[2].send()
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, VIAL)
local run = ListSets.run
-- One set is 2 x 10 + 5 = 25; 8 sets is 200. Vials over 6 don't count, so
-- only 8 are up, and gold would buy exactly 8: none short.
check("the sets are worked out", run.phase == "ready" and run.sets == 8 and run.total == 200)
check("rows wait to be bought", run.rows[1].state == "todo" and run.rows[2].state == "todo")
check("the first row is the active one", ListSets:Active() == 1)

-- 6. Buy, Confirm, and a price that climbs.
ListSets:Press(1)
check("Buy asks the game for the real price", started[1][1] == HERB and started[1][2] == 16
    and run.rows[1].state == "asking")
ListSets:Press(1)
check("a second press while asking does nothing", #started == 1)
handlers.COMMODITY_PRICE_UPDATED(nil, nil, 10, 160)
check("the price comes in", run.rows[1].state == "quoted" and run.rows[1].quote == 160)
money = 100
ListSets:Press(1)
check("short of gold, nothing is paid", #confirmed == 0 and #printed == 1)
money = 1000000
ListSets:Press(1)
check("Confirm pays", confirmed[1][1] == HERB and run.rows[1].state == "buying")
handlers.COMMODITY_PURCHASE_SUCCEEDED()
check("the row is Got and the spend counted", run.rows[1].state == "got" and run.spent == 160)
check("the next row is active", ListSets:Active() == 2)

ListSets:Press(2)
handlers.COMMODITY_PRICE_UPDATED(nil, nil, 6, 48)   -- 160 + 48 > 200
check("a price past the limit stops the run", ListSets.run == nil and #confirmed == 1 and cancelled >= 1)
check("and says so", said[#said] == "Prices exceed your spend limit.")

-- A quote that never comes gives the row back.
ListSets:Start(1, 200)
requests[#requests].send()
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, HERB)
requests[#requests].send()
handlers.COMMODITY_SEARCH_RESULTS_UPDATED(nil, nil, VIAL)
run = ListSets.run
timers = {}
ListSets:Press(1)
Flush()
check("no answer from the game gives the row back", run.rows[1].state == "todo")

-- Snipe talking to the game makes Buy Sets wait.
ns.Snipe = { pending = { phase = "asking" } }
local before = #started
ListSets:Press(1)
check("Buy waits while Snipe is buying", #started == before and run.rows[1].state == "todo")
ns.Snipe.pending = { phase = "planned" }
ListSets:Press(1)
check("a quiet plan of Snipe's doesn't hold it", #started == before + 1)
handlers.COMMODITY_PRICE_UNAVAILABLE()
check("no price lets the row go", run.rows[1].state == "todo")
ns.Snipe = nil

-- 8. Closing ends it.
handlers.AUCTION_HOUSE_CLOSED()
check("the auction house closing stops the run", ListSets.run == nil)

-- 9. The view's entries.
do
    local L = ns.L
    ns.COLORS = { accent = "ffc8a44d" }
    local function Stub()
        return setmetatable({}, { __index = function(self, key) rawset(self, key, noop); return noop end })
    end
    CreateFrame = function() return Stub() end
    ns.Theme = { CreateLabel = Stub, CreatePanel = Stub, CreateItemIcon = Stub, SetItemIcon = noop,
        Unpack = function() return 1, 1, 1, 1 end, FONT = "f", sizes = { small = 11 } }
    ns.Widgets = { CreateButton = Stub, CreateNumberBox = Stub, CreateScrollList = Stub, ShowItemTooltip = noop }
    ns.Prices = { GetValue = function() return 30 end }
    ns.Inventory = { GetOwnedCount = function() return 0 end }
    ns.Vendor = { GetUnitPrice = noop, IsLimited = noop, KeepsInStock = function() return false end }
    ns.Queue = { GetShoppingList = function() return {} end }
    ns.db = {}
    GetTime = function() return 100 end
    local savedLists = ns.ShoppingLists
    ns.ShoppingLists = nil
    ns.NewModule = function(name) local m = ns[name] or {}; ns[name] = m; return m end
    assert(loadfile(lfs_cwd .. "/Logic/ShoppingLists.lua"))("Blackthornes_TS", ns)
    assert(loadfile(lfs_cwd .. "/UI/ShoppingListsView.lua"))("Blackthornes_TS", ns)
    local Lists, View = ns.ShoppingLists, ns.ShoppingListsView
    local key = Lists:Make("Potions")
    Lists:Add(key, HERB, 2)
    Lists:Add(key, VIAL, 1)
    View.open = key
    local kinds = {}
    for _, e in ipairs(View:Entries()) do kinds[#kinds + 1] = e.kind end
    local joined = table.concat(kinds, ",")
    check("an open list ends with the Buy Sets row", joined == "list,list,tools,item,item,sets")
    View.open = "queue"
    local queue = {}
    for _, e in ipairs(View:Entries()) do queue[#queue + 1] = e.kind end
    check("the craft queue's list has none", not table.concat(queue, ","):find("sets"))

    -- A run that is ready shows the sets instead.
    View.open = key
    ListSets.run = { key = key, phase = "ready", sets = 4, total = 100,
        rows = { { itemID = HERB, buy = 8, cost = 80, state = "got" },
                 { itemID = VIAL, buy = 4, cost = 20, state = "todo", short = true } } }
    kinds = {}
    local active
    for _, e in ipairs(View:Entries()) do
        kinds[#kinds + 1] = e.kind
        if e.kind == "setitem" and e.active then active = e.index end
    end
    check("a ready run shows the result and each row", table.concat(kinds, ",") == "list,list,result,setitem,setitem")
    check("the row to buy next is lit", active == 2)
    ListSets.run.phase = "reading"
    kinds = {}
    for _, e in ipairs(View:Entries()) do kinds[#kinds + 1] = e.kind end
    check("while reading, the items show and no tools or foot row", table.concat(kinds, ",") == "list,list,item,item")
    ListSets.run = nil
    ns.ShoppingLists = savedLists
    local _ = L
end

C_Timer = oldTimer
print(("%d check(s) passed"):format(checks))
