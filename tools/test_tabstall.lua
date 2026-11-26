-- Swapping tabs stalled for a moment at the auction house (the owner's
-- report, 2026-11-21). Picking a tab did all of its work in one frame.
--
-- What each pick did, and what it must do now (the smooth play rule):
--   1. Prices built a row for every priced item, read each one's stock
--      history and trend, and sorted them all. Now the sorted rows are kept
--      until the prices, a star, the filters or the sort change. Kept rows
--      read their age again, and a search is never kept, but it builds
--      only the rows it finds.
--   2. Profit analysed every recipe at once. Now, once it has drawn, a pick
--      keeps the rows it had and analyses a few recipes a frame, then draws
--      the same list an at-once refresh gives. Any other refresh answers at
--      once and drops a ranking under way. Leaving the tab drops it too.
--   3. A tab whose onShow is its refresh (Settings) drew twice. Now once.
--      And every pick builds the queue's costs once (Queue:Keeping).

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "ProfessionsFrame", "MailFrame", "CreateFrame", "UIParent", "GameTooltip",
    "GetCursorPosition", "C_Timer", "UISpecialFrames", "tinsert", "GetTime", "time",
    "AuctionHouseFrame", "BlackthornesWindow" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-64s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

--------------------------------------------------------------------------------
-- 1. Prices
--------------------------------------------------------------------------------

print("1. the Prices tab keeps its rows")

do
    local clock = 1000000
    time = function() return clock end

    local ITEMS = 300
    local prices = {}
    for itemID = 1, ITEMS do prices[itemID] = { market = itemID * 10, seen = clock - itemID } end

    -- built: rows built (each asks its age once). read: stock histories
    -- read for How fast it moves.
    local built, read, stars = 0, 0, {}
    local ns = {
        Theme = {}, Widgets = {},
        Util = {
            HasFunction = function() return false end,
            Count = function(tbl) local n = 0; for _ in pairs(tbl) do n = n + 1 end; return n end,
        },
        UI = { tabs = {}, RegisterTab = function(self, tab) self.tabs[tab.key] = tab end },
        Config = { changes = 0 },
        Mail = { GetLedger = function() return { entries = {} } end },
        db = { characters = {} },
    }
    ns.Prices = {
        changes = 0,
        GetTable = function() return prices end,
        GetAge = function(_, itemID)
            built = built + 1
            return prices[itemID] and clock - prices[itemID].seen or nil
        end,
        GetSalesPerDay = function() read = read + 1; return nil end,
        GetFavourites = function() return stars end,
    }

    assert(loadfile(lfs_cwd .. "/UI/Columns.lua"))("Blackthornes_TS", ns)
    assert(loadfile(lfs_cwd .. "/UI/Tab_Prices.lua"))("Blackthornes_TS", ns)
    local List = ns.UI._PricesList

    local first = List("")
    check("the first pick builds every row", built, ITEMS)
    -- Reading every item's stock history and trend was most of the first
    -- draw after a scan on a big auction house (2026-11-26). A row reads
    -- its own when it is first asked: on screen, or under a sort on it.
    check("and reads no item's stock history yet", read, 0)
    check("a row on screen reads its own", first[1].liquidity, nil)
    check("that one read", read, 1)
    local _ = first[1].liquidity
    check("and only once", read, 1)
    read = 0
    check("and lists them all", #first, ITEMS)
    check("dearest first", first[1].itemID, ITEMS)

    clock = clock + 60
    local again = List("")
    check("a second pick builds none again", built, ITEMS)
    check("and gives the same rows in the same order", again[1] == first[1] and again[ITEMS] == first[ITEMS], true)
    check("with their age read again", again[1].age, ITEMS + 60)

    -- A scan priced one item.
    prices[7].market = 99999
    ns.Prices.changes = ns.Prices.changes + 1
    local scanned = List("")
    check("a new price builds the list again", built, ITEMS * 2)
    check("and the item moves to the top", scanned[1].itemID, 7)

    -- A starred item with no price shows with dashes.
    stars[9001] = true
    ns.Prices.changes = ns.Prices.changes + 1
    check("a star on an unpriced item adds its row", #List(""), ITEMS + 1)
    stars[9001] = nil
    check("a star gone without a count still drops it", #List(""), ITEMS)

    -- A setting (the trend's days) and the day itself.
    local before = built
    ns.Config.changes = ns.Config.changes + 1
    List("")
    check("a changed setting builds again", built > before, true)
    before = built
    clock = clock + 86400
    List("")
    check("so does a new day", built > before, true)

    -- Searching wants names, which arrive late from the game: never kept.
    before = built
    List("zzz")
    List("zzz")
    check("a search that matches nothing builds no row", built, before)
    -- Names here are "~item N" (the game has none yet), so "item 12" finds
    -- 12 and 120 to 129, and only those rows are built, each time.
    List("item 12")
    List("item 12")
    check("a search is built each time, only the rows it finds", built, before + 11 * 2)
    check("and finds them", #List("item 12"), 11)

    before = built
    List("")
    check("and the plain list after it is the kept one still", built, before)
    check("with no stock history read along the way", read, 0)

    -- A search or a post at the auction house moves a price or two. When
    -- the prices say which items changed, only those rows are made again,
    -- each put back where the sort would put it (2026-11-26: every row was
    -- built and sorted again on the next pick).
    local touchedSince
    ns.Prices.TouchedSince = function() return touchedSince end
    local function Order(list)
        local ids = {}
        for index, row in ipairs(list) do ids[index] = row.itemID end
        return table.concat(ids, ",")
    end
    local function Change(itemID, market)
        if market then prices[itemID] = prices[itemID] or { seen = clock }; prices[itemID].market = market
        else prices[itemID] = nil end
        ns.Prices.changes = ns.Prices.changes + 1
        touchedSince = touchedSince or {}
        touchedSince[itemID] = true
    end
    local function FullBuild()
        ns.UI._PricesForget()
        local order = Order(List(""))
        return order
    end

    List("")
    before = built
    Change(40, 123456)     -- to the top
    Change(250, 5)         -- to the bottom
    Change(120, 1205)      -- a tie with item 120's neighbour is settled by item
    Change(9100, 777)      -- a new item
    Change(33, nil)        -- one pruned away
    local patched = List("")
    check("a few changed prices build only their rows", built - before, 4)
    check("the dearest is on top", patched[1].itemID, 40)
    check("the pruned one is gone", #patched, ITEMS)
    local patchedOrder = Order(patched)
    check("and the list is the one a full build gives", patchedOrder == FullBuild(), true)

    -- Under a sort by age the changed rows find their place too.
    touchedSince = nil
    ns.UI._PricesSort("age")
    List("")
    prices[200].seen = clock
    Change(200, 2000)
    prices[10].seen = clock - 5000
    Change(10, 100)
    patchedOrder = Order(List(""))
    check("the same under a sort by age", patchedOrder == FullBuild(), true)
    ns.UI._PricesSort("market")

    -- A change the prices cannot name (a guild's prices, a prune) builds all.
    touchedSince = nil
    List("")
    before = built
    ns.Prices.changes = ns.Prices.changes + 1
    List("")
    check("a change that names no item builds every row", built - before >= ITEMS, true)

    -- Picked after such a change (a full scan), the tab built and sorted
    -- every row in the pick's own frame (2026-11-26). Once rows are kept, it
    -- leaves them up, builds a few a frame, and then draws the list an
    -- at-once build gives.
    do
        local function Loose()
            return setmetatable({}, { __index = function(self, key)
                if key == "values" or key == "labels" then return {} end
                if key == "graph" then return nil end
                local child = Loose()
                rawset(self, key, child)
                return child
            end, __call = function() return nil end })
        end
        local widgets = ns.UI._PricesWidgets()
        local list = { sets = 0 }
        function list:SetData(data) self.data = data; self.sets = self.sets + 1 end
        widgets.list, widgets.emptyLabel, widgets.countLabel, widgets.detail = list, Loose(), Loose(), Loose()
        ns.Util.Comma = tostring
        ns.Prices.Count = function() return ITEMS end
        ns.UI.activeTab = "prices"

        -- A worker that does PER_FRAME items each time the test steps a frame.
        local PER_FRAME, workers = 40, {}
        ns.Util.NewWorker = function(opts)
            local worker = { index = 0, running = false }
            function worker:Start(items)
                self.items, self.index, self.running = items, 0, true
                workers[#workers + 1] = self
                return self
            end
            function worker:Cancel() self.running = false end
            function worker:Step()
                local done = 0
                while self.running and self.index < #self.items and done < PER_FRAME do
                    self.index = self.index + 1
                    done = done + 1
                    opts.onItem(self.items[self.index], self.index, self)
                end
                if self.running and self.index >= #self.items then
                    self.running = false
                    if opts.onDone then opts.onDone(self) end
                end
            end
            return worker
        end
        local function Frame()
            local stepped = false
            for _, worker in ipairs(workers) do
                if worker.running then worker:Step(); stepped = true end
            end
            return stepped
        end
        local function Frames()
            local count = 0
            while Frame() do count = count + 1 end
            return count
        end
        local Pick = ns.UI._PricesPicked
        local function Unnamed() touchedSince = nil; ns.Prices.changes = ns.Prices.changes + 1 end

        -- Enough items for several sorted runs to merge.
        local MANY = 2600
        for itemID = ITEMS + 1, MANY do
            prices[itemID] = { market = (itemID * 7919) % 1000, seen = clock - (itemID % 50) }
        end
        prices[9100] = nil

        ns.UI._PricesForget()
        before = built
        Pick()
        check("the first pick draws at once, never an empty list", #(list.data or {}), MANY - 1)
        check("every row built in that frame", built - before, MANY - 1)
        check("with no build left under way", ns.UI._PricesBuilding(), false)
        local firstRows = list.data

        before = built
        Pick()
        check("picked with nothing changed, it draws the kept rows at once", built - before, 0)
        check("and no build is under way", ns.UI._PricesBuilding(), false)

        Unnamed()
        prices[77].market = 999999
        stars[9200] = true
        before = built
        local sets = list.sets
        Pick()
        check("picked after a full scan, the pick itself builds no row", built - before, 0)
        check("and the rows it had stay up", list.sets == sets and list.data == firstRows, true)
        Frame()
        check("a frame later a few rows are built", built - before, PER_FRAME)
        check("the old rows still up", list.sets, sets)
        check("done over many frames", Frames() > 10, true)
        check("every priced item built once, and the starred one with no price", built - before, MANY)
        check("then the list is drawn", list.sets, sets + 1)
        check("the new price on top", list.data[1].itemID, 77)
        check("the starred one in it", #list.data, MANY)
        local spread = Order(list.data)
        check("the list is the one a full build gives", spread == FullBuild(), true)
        before = built
        Pick()
        check("and its rows are kept for the next pick", built - before, 0)

        -- Under a sort by age, with the clock ticking over while it builds:
        -- two rows of one scan must not swap.
        ns.UI._PricesSort("age")
        Pick()
        Unnamed()
        Pick()
        for _ = 1, 20 do Frame(); clock = clock + 1 end
        Frames()
        check("the same under a sort by age, as seconds pass", Order(list.data) == FullBuild(), true)
        ns.UI._PricesSort("market")
        Pick()

        -- A click or an event redraws while a build is under way.
        Unnamed()
        prices[78].market = 888888
        Pick()
        Frame()
        sets = list.sets
        ns.UI.tabs.prices.refresh()
        check("a refresh under way answers at once", list.sets, sets + 1)
        check("with what is true now", list.data[2].itemID, 78)
        before = built
        check("and the build under way is dropped", Frames(), 0)
        check("building nothing more", built - before, 0)

        -- Another tab picked before the build is done.
        Unnamed()
        prices[79].market = 777777
        Pick()
        Frame()
        sets, before = list.sets, built
        ns.UI.activeTab = "queue"
        Frames()
        check("leaving the tab stops the build", built - before, 0)
        check("and draws nothing behind the other tab", list.sets, sets)
        ns.UI.activeTab = "prices"
        Pick()
        Frames()
        check("coming back builds afresh", list.data[3].itemID, 79)

        -- A price that moves while the rows build is mended in the draw.
        Unnamed()
        Pick()
        Frame()
        touchedSince = nil
        Change(80, 666666)
        Frames()
        check("a price that moved while it built is in the list drawn", list.data[4].itemID, 80)
        check("which is the one a full build gives", Order(list.data) == FullBuild(), true)

        -- A search wants names and is never kept: at once, as before.
        Pick()
        Unnamed()
        local found = List("item 12")
        check("a search builds at once", #found > 0, true)
        ns.UI._PricesList("")

        stars[9200] = nil
        widgets.list, widgets.emptyLabel, widgets.countLabel, widgets.detail = nil, nil, nil, nil
        ns.UI.activeTab = nil
    end

    ns.UI._PricesForget()
end

--------------------------------------------------------------------------------
-- 2. Profit
--------------------------------------------------------------------------------

print("")
print("2. the Profit tab ranks a few recipes a frame when picked")

do
    local function NewFrame(kind)
        local f = { kind = kind, scripts = {}, shown = true, text = "", points = {} }
        setmetatable(f, { __index = function(_, k)
            if type(k) == "string" and k:match("^%u") then return noop end
        end })
        f.SetScript = function(self, n, fn) self.scripts[n] = fn end
        f.GetScript = function(self, n) return self.scripts[n] end
        f.Show = function(self) self.shown = true end
        f.Hide = function(self) self.shown = false end
        f.SetShown = function(self, v) self.shown = v and true or false end
        f.IsShown = function(self) return self.shown end
        f.IsVisible = function(self) return self.shown end
        f.SetText = function(self, t) self.text = t end
        f.GetText = function(self) return self.text end
        f.GetStringWidth = function(self) return #tostring(self.text or "") * 6 end
        f.CreateTexture = function() return NewFrame() end
        f.CreateFontString = function() return NewFrame() end
        f.GetParent = function() return NewFrame() end
        f.HasFocus = function() return false end
        return f
    end

    CreateFrame = function(kind) return NewFrame(kind) end
    UIParent = NewFrame()
    GameTooltip = NewFrame()
    C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }
    GetTime = function() return 1000 end

    local ns = {}
    ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
    ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
    ns.RegisterCommand, ns.RegisterEvent = noop, noop
    ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
    ns.Theme = setmetatable({
        FONT = "font",
        sizes = { tiny = 10, small = 11, normal = 12, large = 14, title = 16 },
        Unpack = function(key) return key end,
        ProfitColor = function(value) return (value or 0) >= 0 and "profit" or "loss" end,
        CreateHeading = function() local h = NewFrame(); h.rule = NewFrame(); return h end,
        FitText = function(label, texts) label:SetText(texts[1]); return texts[1] end,
        TextWidth = function() return nil end,
    }, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return function() return NewFrame() end end
    end })
    ns.Config = { Get = function() return nil end, GetCharacterKey = function() return "me" end }

    -- A worker that does PER_FRAME items each time the test steps a frame.
    local PER_FRAME, workers = 10, {}
    ns.Util = {
        GetItemQualityColor = noop,
        FormatMoney = function(copper) return tostring(copper or 0) end,
        FormatAge = function() return "1h" end,
        GetItemLabel = function(itemID) return "item" .. tostring(itemID) end,
        HasFunction = function() return false end,
        NewWorker = function(opts)
            local worker = { index = 0, running = false }
            function worker:Start(items)
                self.items, self.index, self.running = items, 0, true
                workers[#workers + 1] = self
                return self
            end
            function worker:Cancel() self.running = false end
            function worker:Step()
                local done = 0
                while self.running and self.index < #self.items and done < PER_FRAME do
                    self.index = self.index + 1
                    done = done + 1
                    opts.onItem(self.items[self.index], self.index, self)
                end
                if self.running and self.index >= #self.items then
                    self.running = false
                    if opts.onDone then opts.onDone(self) end
                end
            end
            return worker
        end,
    }
    local function Frame()
        local stepped = false
        for _, worker in ipairs(workers) do
            if worker.running then worker:Step(); stepped = true end
        end
        return stepped
    end
    local function Frames()
        local count = 0
        while Frame() do count = count + 1 end
        return count
    end

    assert(loadfile(lfs_cwd .. "/UI/Widgets.lua"))("Blackthornes_TS", ns)
    assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)

    -- The search box's own change call, to type into it.
    local typeSearch
    local makeSearch = ns.Widgets.CreateSearchBox
    ns.Widgets.CreateSearchBox = function(parent, hint, onChange)
        if hint == "Search crafts" then typeSearch = onChange end
        return makeSearch(parent, hint, onChange)
    end

    local list
    ns.Widgets.CreateScrollList = function(_, opts)
        list = NewFrame()
        list.opts = opts
        list.SetData = function(self, data) self.data = data; self.sets = (self.sets or 0) + 1 end
        return list
    end

    -- Fifty crafts, each worth its number; `boost` lifts one, as a new price would.
    local RECIPES, analysed, boost = 50, 0, {}
    local recipes = {}
    for recipeID = 1, RECIPES do recipes[recipeID] = { name = "Craft " .. recipeID } end
    ns.Profit.Analyse = function(_, recipeID)
        analysed = analysed + 1
        local profit = recipeID * 10 + (boost[recipeID] or 0)
        return { recipeID = recipeID, name = "Craft " .. recipeID, outputItemID = recipeID, priceable = true,
            totalCost = 10, revenue = profit + 10, unitRevenue = profit + 10, cut = 0, profit = profit,
            margin = 0.5, craftableNow = 1, cost = { reagents = {} }, stock = 0, posted = 0, onHand = 0,
            inMail = 0, queuedElsewhere = 0, postRoom = 9, roomInCrafts = 9, atPostLimit = false,
            priceBasis = "market", depositKnown = true, deposit = 0 }
    end
    ns.Recipes = { Count = function() return RECIPES end, GetAll = function() return recipes end,
        GetAccountWide = function() return recipes end, IsDropped = function() return false end,
        GetAny = function(_, recipeID) return recipes[recipeID], "me" end }
    ns.Prices = { Count = function() return 1 end }
    ns.Auctions = { SetLimit = noop }
    ns.db = { characters = {} }
    ns.Queue = { Add = function() return true end }

    local tabs = {}
    ns.UI = setmetatable({ activeTab = "profit", RegisterTab = function(_, tab) tabs[tab.key] = tab end },
        { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return noop end end })

    assert(loadfile(lfs_cwd .. "/UI/Columns.lua"))("Blackthornes_TS", ns)
    assert(loadfile(lfs_cwd .. "/UI/Tab_Profit.lua"))("Blackthornes_TS", ns)

    local function Order(data)
        local ids = {}
        for index, analysis in ipairs(data) do ids[index] = analysis.recipeID end
        return table.concat(ids, ",")
    end
    -- What UI:SelectTab does with the tab.
    local function Pick()
        tabs.profit.onShow()
        tabs.profit.refreshPicked()
    end

    check("the tab has a redraw for when it is picked", type(tabs.profit.refreshPicked), "function")

    tabs.profit.build(NewFrame())
    Pick()
    check("the first pick draws at once, never an empty list", #(list.data or {}), RECIPES)
    check("every recipe analysed in that frame", analysed, RECIPES)
    check("the best craft on top", list.data[1].recipeID, RECIPES)
    local firstRows = list.data

    -- Picked again: the rows stay, and the work is spread.
    analysed = 0
    Pick()
    check("picked again, the pick itself analyses nothing", analysed, 0)
    check("and the rows it had stay up", list.data == firstRows, true)
    Frame()
    check("a frame later a few recipes are done", analysed, PER_FRAME)
    check("the old rows still up", list.data == firstRows, true)
    local frames = Frames() + 1
    check("done over several frames", frames, RECIPES / PER_FRAME)
    check("then the list is drawn", list.data ~= firstRows, true)
    local spreadOrder = Order(list.data)
    tabs.profit.onShow()
    tabs.profit.refresh()
    check("the same list an at-once refresh gives", Order(list.data), spreadOrder)

    -- A price changed while the tab was away: the spread ranking shows it.
    boost[3] = 100000
    Pick()
    Frames()
    check("a craft worth more now is on top after the frames", list.data[1].recipeID, 3)

    -- A click or an event refreshes while a ranking is under way.
    boost[3], boost[5] = nil, 100000
    Pick()
    Frame()
    local sets = list.sets
    tabs.profit.refresh()
    check("a refresh under way answers at once", list.sets, sets + 1)
    check("with what is true now", list.data[1].recipeID, 5)
    analysed = 0
    check("and the ranking under way is dropped", Frames(), 0)
    check("analysing nothing more", analysed, 0)

    -- Another tab picked before the ranking is done.
    Pick()
    Frame()
    sets, analysed = list.sets, 0
    ns.UI.activeTab = "queue"
    Frames()
    check("leaving the tab stops the ranking", analysed, 0)
    check("and draws nothing behind the other tab", list.sets, sets)
    ns.UI.activeTab = "profit"
    Pick()
    Frames()
    check("coming back ranks afresh", list.data[1].recipeID, 5)

    -- Typing in the search narrows the ranking already worked out.
    analysed = 0
    typeSearch("Craft 4")
    check("a search analyses no recipe again (the picked row aside)", analysed <= 1, true)
    check("and shows the crafts that match, best first", Order(list.data), "49,48,47,46,45,44,43,42,41,40,4")
    local narrowed = Order(list.data)
    tabs.profit.refresh()
    check("the same list an at-once refresh gives", Order(list.data), narrowed)
    analysed = 0
    typeSearch("Craft 49")
    check("a longer search analyses nothing either", analysed <= 1, true)
    check("and narrows further", Order(list.data), "49")
    analysed = 0
    typeSearch("no such craft")
    check("a search that matches nothing analyses nothing", analysed <= 1, true)
    check("and the list is empty", #list.data, 0)
    typeSearch("")
    check("cleared, every craft is back", #list.data, RECIPES)

    -- A price moved since: the search works it all out afresh.
    ns.Prices.changes = 1
    boost[5], boost[7] = nil, 100000
    analysed = 0
    typeSearch("Craft")
    check("after a price change a search analyses every recipe", analysed >= RECIPES, true)
    check("and shows what is true now", list.data[1].recipeID, 7)
    typeSearch("")

    -- A row held in place past its listing limit leaves on a new search.
    do
        local kept = { { recipeID = 1, name = "a", priceable = true, atPostLimit = true, profit = 5 },
            { recipeID = 2, name = "b", priceable = true, profit = 9 } }
        check("RankAgain drops a row past its limit that is not held",
            Order(ns.Profit:RankAgain(kept, {})), "2")
        check("keeps it when the list ignores the limit",
            Order(ns.Profit:RankAgain(kept, { ignorePostLimit = true })), "2,1")
        check("and leaves the list it was given alone", #kept, 2)
    end

    -- GetRanked is its three steps run straight through.
    local opts = { includeUnpriceable = true }
    local steps = ns.Profit:BeginRanked(opts)
    for _, item in ipairs(steps.items) do ns.Profit:RankOne(steps, item) end
    check("the three steps give GetRanked's list",
        Order(ns.Profit:FinishRanked(steps)), Order(ns.Profit:GetRanked(opts)))
end

--------------------------------------------------------------------------------
-- 3. Picking a tab
--------------------------------------------------------------------------------

print("")
print("3. picking a tab")

do
    local function Region(parent)
        local region = { parent = parent, shown = true, width = 0, height = 0, scale = 1,
            points = {}, scripts = {}, frameLevel = 1 }
        region.SetParent = function(self, p) self.parent = p end
        region.GetParent = function(self) return self.parent end
        region.SetSize = function(self, w, h) self.width, self.height = w, h end
        region.SetWidth = function(self, w) self.width = w end
        region.SetHeight = function(self, h) self.height = h end
        region.GetWidth = function(self) return self.width end
        region.GetHeight = function(self) return self.height end
        region.SetScale = function(self, s) self.scale = s end
        region.GetScale = function(self) return self.scale end
        region.GetEffectiveScale = function(self) return self.scale end
        region.SetPoint = function(self, point, relativeTo, relativePoint, x, y)
            if type(relativeTo) ~= "table" then
                relativeTo, relativePoint, x, y = self.parent, point, relativeTo, relativePoint
            end
            self.points = { { point, relativeTo, relativePoint, x or 0, y or 0 } }
        end
        region.ClearAllPoints = function(self) self.points = {} end
        region.GetPoint = function(self)
            local p = self.points[1]
            if not p then return nil end
            return p[1], p[2], p[3], p[4], p[5]
        end
        region.Show = function(self) self.shown = true end
        region.Hide = function(self) self.shown = false end
        region.SetShown = function(self, on) self.shown = on and true or false end
        region.IsShown = function(self) return self.shown end
        region.SetScript = function(self, name, fn) self.scripts[name] = fn end
        region.GetScript = function(self, name) return self.scripts[name] end
        region.HookScript = function(self, name, fn) self.scripts[name] = fn end
        region.GetRegions = function() end
        region.GetFrameLevel = function(self) return self.frameLevel end
        region.SetFrameLevel = function(self, level) self.frameLevel = level end
        region.CreateTexture = function(self) return Region(self) end
        region.CreateFontString = function(self) return Region(self) end
        region.GetStringWidth = function() return 40 end
        region.GetUnboundedStringWidth = function() return 40 end
        region.GetStringHeight = function() return 12 end
        return setmetatable(region, { __index = function(_, key)
            if type(key) == "string" and key:match("^%u") then return noop end
        end })
    end

    CreateFrame = function(_, _, parent) return Region(parent) end
    UIParent = Region()
    UIParent.width, UIParent.height = 1280, 720
    GameTooltip = Region()
    GetCursorPosition = function() return 0, 0 end
    C_Timer = { After = noop }
    UISpecialFrames = {}
    tinsert = table.insert
    GetTime = function() return 0 end
    time = os.time

    local settings = {}
    local ns = {}
    ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
    ns.NewModule = function(name) local m = ns[name] or {}; ns[name] = m; return m end
    ns.RegisterCommand = noop
    ns.RegisterEvent = function() return true end
    ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
    ns.db = { global = {}, settings = settings }
    ns.Config = {
        DEFAULTS = { settings = { windowScale = 1 } },
        Get = function(_, key) return settings[key] end,
        Set = function(_, key, value) settings[key] = value end,
    }
    ns.Scanner = { isAuctionHouseOpen = false, CanFullScan = function() return true end, StartFullScan = noop }
    ns.Prices = { Count = function() return 0 end, GetLastScan = noop }
    ns.Recipes = { Count = function() return 0 end }
    ns.VersionLabel = function() return "v1.4.0" end
    ns.Titanforged = {
        Dress = function(_, frame)
            local trim = Region(frame)
            trim.closeButton = Region(trim)
            frame.titan = trim
            return trim
        end,
        Reach = function() return 0, 0, 0, 0 end,
        Opened = noop,
    }
    ns.FoldWindow = {
        Add = function(_, frame)
            local button = Region(frame.titan)
            frame.blackthornesFold = { button = button }
            return button
        end,
        Unfold = noop,
    }

    local function Load(path) assert(loadfile(lfs_cwd .. path))("Blackthornes_TS", ns) end
    _G.BlackthornesWindow = nil
    Load("/Core/Util.lua")
    Load("/UI/Theme.lua")
    Load("/UI/Widgets.lua")
    Load("/UI/SharedWindow.lua")
    Load("/UI/Main.lua")

    local UI = ns.UI

    -- The queue's costs are built once for a whole redraw inside Keeping.
    local keeping, builds, kept = 0, 0, nil
    ns.Queue = {
        Keeping = function(_, fn, ...)
            keeping = keeping + 1
            local ok, err = pcall(fn, ...)
            keeping = keeping - 1
            if keeping == 0 then kept = nil end
            if not ok then error(err, 0) end
        end,
        GetEntryCosts = function()
            if keeping == 0 then builds = builds + 1; return {} end
            if not kept then builds = builds + 1; kept = {} end
            return kept
        end,
    }

    local drawn = { settings = 0, profitPlain = 0, profitPicked = 0, shown = 0 }
    local order = {}
    UI:RegisterTab({ key = "profit", text = "Profit", order = 1, build = noop,
        onShow = function() order[#order + 1] = "show" end,
        refresh = function() drawn.profitPlain = drawn.profitPlain + 1 end,
        refreshPicked = function() drawn.profitPicked = drawn.profitPicked + 1; order[#order + 1] = "draw" end })
    UI:RegisterTab({ key = "queue", text = "Queue", order = 2, build = noop,
        refresh = function()
            -- The rows, the totals and the shopping list each ask.
            ns.Queue:GetEntryCosts(); ns.Queue:GetEntryCosts(); ns.Queue:GetEntryCosts()
        end })
    local function SettingsRefresh() drawn.settings = drawn.settings + 1 end
    UI:RegisterTab({ key = "settings", text = "Settings", order = 99, build = noop,
        onShow = SettingsRefresh, refresh = SettingsRefresh })
    UI:RegisterTab({ key = "broken", text = "Broken", order = 50, build = noop,
        refresh = function() error("this tab broke") end })

    ns.SharedMinimap = { Join = noop }
    UI.minimapButton = {}
    UI:JoinSharedMinimap()
    UI:Show()

    drawn.settings = 0
    UI:SelectTab("settings")
    check("Settings draws once when picked, not twice", drawn.settings, 1)

    builds = 0
    UI:SelectTab("queue")
    check("Queue builds its costs once when picked", builds, 1)
    check("and nothing is kept past the pick", keeping, 0)

    drawn.profitPlain, drawn.profitPicked, order = 0, 0, {}
    UI:SelectTab("profit")
    check("Profit takes its lighter redraw when picked", drawn.profitPicked, 1)
    check("and not the at-once one as well", drawn.profitPlain, 0)
    check("after its onShow", table.concat(order, ","), "show,draw")
    UI:RefreshActiveTab()
    check("any other refresh is the at-once one", drawn.profitPlain, 1)

    local ok, err = pcall(UI.SelectTab, UI, "broken")
    check("a tab that breaks still says so", ok, false)
    check("in its own words", tostring(err):find("this tab broke", 1, true) ~= nil, true)
    check("and leaves nothing kept", keeping, 0)
end

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
if failed > 0 then error(("%d tab stall check(s) failed"):format(failed)) end
print(("  tab stall: all %d checks passed"):format(passed))
