-- The Browse tab of our auction house window (Logic/Browse.lua,
-- UI/AuctionBrowse.lua), without a game client.
--
-- The search waits its turn in the shared queue, reads its answer and asks
-- for more through the queue too, prices each row against the usual price,
-- and never sends anything while the auction house is closed. Then the
-- tab's words and a build of the tab over a widget layer that only
-- remembers what was written to it.

local failures = 0
local function check(name, ok)
    if ok then print("  ok   " .. name) else failures = failures + 1; print("  FAIL " .. name) end
end

--------------------------------------------------------------------------------
-- The pretend game and queue
--------------------------------------------------------------------------------

local sent, more, results, full = {}, 0, {}, true
local names = { [10] = "Wool Cloth", [11] = "Copper Ore", [12] = "Silk Cloth" }
local hooks = {}

-- Timers wait until the test lets time pass, so a wait can be told from
-- an answer.
local timers = {}
_G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds, fn } end }
local function Tick(upTo)
    upTo = upTo or 1
    local ran = true
    while ran do
        ran = false
        for index, timer in ipairs(timers) do
            if timer[1] <= upTo then
                table.remove(timers, index)
                timer[2]()
                ran = true
                break
            end
        end
    end
end
_G.GetTime = function() return 100 end
_G.GetMoney = function() return 12345 end
_G.time = os.time
_G.Enum = { AuctionHouseFilter = {
    PoorQuality = 4, CommonQuality = 5, UncommonQuality = 6, RareQuality = 7, EpicQuality = 8,
    UsableOnly = 2,
} }
for quality, word in pairs({ [0] = "Poor", "Common", "Uncommon", "Rare", "Epic" }) do
    _G["ITEM_QUALITY" .. quality .. "_DESC"] = word
end
_G.AuctionCategories = {
    { name = "Weapons", filters = { { classID = 2 } }, subCategories = {
        { name = "Swords", filters = { { classID = 2, subClassID = 7 } } },
        { name = "Staves", filters = { { classID = 2, subClassID = 10 } } },
    } },
    { name = "Trade Goods", filters = { { classID = 7 } } },
    { name = "Token" },
}
_G.C_AuctionHouse = {
    SendBrowseQuery = function(query)
        sent[#sent + 1] = query
        for _, hook in ipairs(hooks) do hook() end
    end,
    GetBrowseResults = function() return results end,
    HasFullBrowseResults = function() return full end,
    RequestMoreBrowseResults = function() more = more + 1 end,
    GetItemKeyInfo = function(key)
        local name = names[key.itemID]
        if name then return { itemName = name, quality = 1, iconFileID = 1 } end
        return nil
    end,
}
_G.hooksecurefunc = function(_, _, fn) hooks[#hooks + 1] = fn end

local events, warned = {}, 0
local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterEvent = function(_, event, fn) events[event] = fn return true end
ns.Warn = function() warned = warned + 1 end
ns.L = setmetatable({ Format = function(key, ...) return key:format(...) end },
    { __index = function(_, key) return key end })

-- A queue that only keeps what was asked, so the test says when it goes.
local queued = {}
ns.AHQueue = {
    PRIORITY = { urgent = 1, normal = 2, scan = 3 },
    Request = function(_, request) queued[request.key] = request end,
    Cancel = function(_, key) queued[key] = nil end,
    IsFlushing = function() return false end,
}
local function Run(key)
    local request = queued[key]
    queued[key] = nil
    return request and request.send()
end

local usual = { [10] = 100, [11] = 200 }
ns.Prices = {
    GetValue = function(_, itemID) return usual[itemID] end,
    GetLastScan = function() return os.time() - 240 end,
}
ns.Util = {
    GetItemName = function(itemID) return "item " .. itemID end,
    FormatMoney = function(copper) return copper .. "c" end,
}

local function Result(itemID, price, count)
    return { itemKey = { itemID = itemID }, minPrice = price, totalQuantity = count or 1 }
end

assert(loadfile("Logic/Browse.lua"))("Blackthornes_TS", ns)
local Browse = ns.Browse
Browse:OnEnable()

print("")
print("the Browse search")

--------------------------------------------------------------------------------
-- What goes to the game
--------------------------------------------------------------------------------

local query = Browse:BuildQuery()
check("every level is no level filter", query.minLevel == 0 and query.maxLevel == 0)
check("nothing picked filters nothing",
    #query.filters == 0 and #query.itemClassFilters == 0 and query.searchString == "")

Browse.query.minLevel, Browse.query.maxLevel = 40, 20
Browse.query.quality, Browse.query.usable, Browse.query.text = 2, true, "cloth"
query = Browse:BuildQuery()
check("levels the wrong way round are swapped", query.minLevel == 20 and query.maxLevel == 40)
check("rarity and Usable Only are the game's filters",
    #query.filters == 2 and query.filters[1] == 6 and query.filters[2] == 2)
check("the words go as typed", query.searchString == "cloth")
Browse.query.minLevel, Browse.query.maxLevel = -5, 900
query = Browse:BuildQuery()
check("levels stay inside 1 to 60", query.minLevel == 0 and query.maxLevel == 0)

check("five rarities are offered", #Browse:Qualities() == 5 and Browse:Qualities()[3].name == "Uncommon")

--------------------------------------------------------------------------------
-- Categories
--------------------------------------------------------------------------------

local lines = Browse:CategoryLines()
check("the game's categories show, the empty one left out",
    #lines == 2 and lines[1].name == "Weapons" and lines[2].name == "Trade Goods")
Browse:PickCategory({ 1 })
lines = Browse:CategoryLines()
check("a picked category opens its children",
    #lines == 4 and lines[1].selected and lines[2].name == "Swords" and lines[2].depth == 1)
Browse:PickCategory({ 1, 2 })
query = Browse:BuildQuery()
check("the picked category is the search's class filter",
    #query.itemClassFilters == 1 and query.itemClassFilters[1].classID == 2
    and query.itemClassFilters[1].subClassID == 10)
Browse:PickCategory({ 1, 2 })
check("the same one again steps back out", #Browse.query.path == 1 and Browse.query.path[1] == 1)
Browse:PickCategory({ 1 })
check("and again clears it", Browse.query.path == nil)

--------------------------------------------------------------------------------
-- Deals
--------------------------------------------------------------------------------

check("a price under the usual one is a deal", Browse.Deal(81, 100) == -19)
check("a price over it is not", Browse.Deal(106, 100) == 6)
check("no usual price is no deal", Browse.Deal(81, nil) == nil and Browse.Deal(0, 100) == nil)
check("the deal's words",
    Browse.DealText(-19) == "-19%" and Browse.DealText(6) == "+6%"
    and Browse.DealText(0) == "Same" and Browse.DealText(nil) == "--")

--------------------------------------------------------------------------------
-- A search
--------------------------------------------------------------------------------

check("closed, nothing is asked", Browse:Search() == false and next(queued) == nil)

events.AUCTION_HOUSE_SHOW()
Tick()
local changes = 0
Browse.onChange = function() changes = changes + 1 end
Browse:Clear()

check("a search waits in the shared queue",
    Browse:Search() == true and Browse.status == "waiting" and #sent == 0)
local request = queued["ui-browse"]
check("it goes ahead of scans, as the player is watching",
    request and request.priority == ns.AHQueue.PRIORITY.urgent)

results = { Result(11, 150, 4), Result(10, 81, 20), Result(12, 500, 1), Result(99, 5, 1) }
full = false
Run("ui-browse")
check("its turn sends it once", #sent == 1 and Browse.status == "searching")

events.AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
Tick()
check("the answer is read", #Browse.rows == 4)
check("more is asked for through the queue, behind the player's clicks",
    queued["ui-browse-more"] and queued["ui-browse-more"].priority == ns.AHQueue.PRIORITY.normal
    and more == 0 and Browse.status == "searching")

local shown = Browse:Shown()
check("rows are A to Z", shown[1].name == "Copper Ore" and shown[3].name == "Silk Cloth")
check("each row has its usual price and deal",
    shown[1].usual == 200 and shown[1].deal == -25 and shown[3].usual == nil and shown[3].deal == nil)
check("a name not loaded yet waits", shown[2].pending == true and shown[2].name == "item 99")

names[99] = "Zesty Clam"
events.ITEM_KEY_ITEM_INFO_RECEIVED()
Tick()
check("and is filled in when it comes", Browse:Shown()[4].name == "Zesty Clam" and Browse.pending == 0)

results[#results + 1] = Result(10, 300, 2)
full = true
Run("ui-browse-more")
check("the next page is asked for once", more == 1)
events.AUCTION_HOUSE_BROWSE_RESULTS_ADDED()
Tick()
check("the new rows join and the search is done", #Browse.rows == 5 and Browse.status == "done")

local before = #sent
Browse:SetDealsOnly(true)
shown = Browse:Shown()
check("Deals Only keeps what is under the usual price", #shown == 2 and shown[1].deal < 0 and shown[2].deal < 0)
check("and needs no new search", #sent == before and next(queued) == nil)
Browse:SetDealsOnly(false)
check("the list told the tab it moved", changes > 0)

-- Someone else's search takes the game's list.
results, full = { Result(10, 81, 1) }, false
Browse:Search()
Run("ui-browse")
events.AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
Tick()
check("paging is under way", queued["ui-browse-more"] ~= nil)
_G.C_AuctionHouse.SendBrowseQuery({})
check("another search stops ours asking for more",
    queued["ui-browse-more"] == nil and Browse.status == "done" and #Browse.rows == 1)

-- A search for everything.
results = {}
for index = 1, Browse.MAX_ROWS + 50 do results[index] = Result(1000 + index, index, 1) end
full = false
Browse:Search()
Run("ui-browse")
events.AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
Tick()
check("a huge answer stops at the most rows kept",
    #Browse.rows == Browse.MAX_ROWS and Browse.status == "done" and queued["ui-browse-more"] == nil)

-- A search the queue never got to.
Browse:Search()
request = queued["ui-browse"]
queued["ui-browse"] = nil
request.onGiveUp()
check("a search never sent says so and is done", Browse.status == "done" and warned == 1)

-- No answer at all.
results, full = {}, true
Browse:Search()
Run("ui-browse")
check("it waits for an answer first", Browse.status == "searching")
Tick(Browse.ANSWER_WAIT)
check("no answer is an empty list, done", Browse.status == "done" and #Browse.rows == 0)

Browse:Search()
events.AUCTION_HOUSE_CLOSED()
Tick()
check("leaving drops what waited", next(queued) == nil and Browse.status == "idle" and #Browse.rows == 0)
before = #sent
check("and nothing more is sent", Browse:Search() == false and #sent == before)

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

local function Stub(fields)
    local frame = fields or {}
    return setmetatable(frame, { __index = function(self, key)
        if key == "barWidth" then return nil end
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

local function Label()
    return Stub({
        text = "",
        SetText = function(self, value) self.text = tostring(value) end,
        SetShown = function(self, on) self.shown = on and true or false end,
    })
end

local function List()
    return Stub({ data = {}, SetData = function(self, data) self.data = data end })
end

ns.Theme = setmetatable({
    CreateLabel = function() return Label() end,
    TextWidth = function() return 50 end,
    Unpack = function() return 1, 1, 1, 1 end,
}, { __index = function() return function() return Stub() end end })

local listOpts = {}
ns.Widgets = setmetatable({
    SEARCH_WIDTH = 180,
    CreateScrollList = function(_, opts)
        listOpts[#listOpts + 1] = opts
        return List()
    end,
    CreateButton = function() return Stub({ label = Label() }) end,
    SortableHeadings = function() return Stub({ Sort = function(_, rows) return rows end }) end,
    FitColumns = function() end,
    EmptyAction = function(_, text) ns.emptyAction = text end,
}, { __index = function() return function() return Stub() end end })

assert(loadfile("UI/AuctionBrowse.lua"))("Blackthornes_TS", ns)
local Tab = ns.AuctionBrowse
Tab:OnEnable()

print("")
print("the Browse tab")

check("how long ago",
    Tab.Ago(30) == "just now" and Tab.Ago(60) == "1 minute ago" and Tab.Ago(240) == "4 minutes ago"
    and Tab.Ago(3600) == "1 hour ago" and Tab.Ago(7200) == "2 hours ago"
    and Tab.Ago(86400) == "1 day ago" and Tab.Ago(3 * 86400) == "3 days ago")
check("the footer counts the results", Tab.Summary(1) == "1 result." and Tab.Summary(214) == "214 results.")
check("and says how old the prices are",
    Tab.Summary(214, 1000, 1240) == "214 results. Prices are from a scan 4 minutes ago.")

local text, clear = Tab.EmptyText("searching", 0)
check("an empty list says it is waiting", text == "Waiting for the auction house..." and clear == false)
text, clear = Tab.EmptyText("done", 0)
check("nothing found offers Clear Search", text == "Nothing found. Try other words." and clear == true)
check("a list with rows, or no search yet, says nothing",
    Tab.EmptyText("done", 3) == nil and Tab.EmptyText("idle", 0) == nil)

check("a deal is green, over the usual price red, the rest quiet",
    Tab.DealColor(-19) == "profit" and Tab.DealColor(6) == "loss"
    and Tab.DealColor(0) == "muted" and Tab.DealColor(nil) == "muted")

local placed = {}
local count = Tab.Flow({
    { width = 100 }, { width = 40, glue = true }, { width = 60 }, { width = 80 },
}, 220, function(item, x, line) placed[#placed + 1] = { item = item, x = x, line = line } end)
check("the bar wraps onto a new line when it runs out of room", count == 2 and placed[4].line == 1)
check("a label stays with what it names",
    placed[2].line == placed[3].line and placed[3].x == placed[2].x + 44)
check("one line when it all fits",
    Tab.Flow({ { width = 10 }, { width = 10 } }, 500, function() end) == 1)

-- Build it at the auction house, with a search's rows in.
events.AUCTION_HOUSE_SHOW()
Tick()
results, full = { Result(11, 150, 4), Result(10, 81, 20) }, true
Browse:Search()
Run("ui-browse")
events.AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
Tick()

local well = Stub({ IsVisible = function() return true end })
Tab:Build(well)
local widgets = Tab.widgets
check("the tab builds", widgets.well == well and widgets.list ~= nil and widgets.categories ~= nil)
check("the list has the search's rows", #widgets.list.data == 2)
check("the categories are down the side", #widgets.categories.data == 2)
check("the footer counts them and shows your gold",
    widgets.summary.text:find("^2 results%.") ~= nil and widgets.gold.text == "Your Gold: 12345c")
check("a full list shows no empty words", widgets.empty.shown == false)

Tab:Build(Stub())
check("building again changes nothing", widgets.well == well)

results = {}
Browse:Search()
Run("ui-browse")
Tick(Browse.ANSWER_WAIT)
check("an empty answer says nothing was found and offers Clear Search",
    widgets.empty.text == "Nothing found. Try other words." and ns.emptyAction == "Clear Search")

Tab:Clear()
Tick()
check("Clear Search empties the tab",
    Browse.status == "idle" and widgets.summary.text == "" and widgets.empty.shown == false)

check("no row has a buy or bid click yet", (function()
    for _, opts in ipairs(listOpts) do
        if opts.rowHeight == 22 and opts.onClick then return false end
    end
    return true
end)())

print("")
if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("all checks passed")
