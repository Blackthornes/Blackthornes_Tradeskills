-- The Today tab (the owner said build it, 2026-11-26, from a mockup).
--
-- What must hold:
--   1. Each line reads what another part already knows, in order: mail,
--      undercut, ready, sold out, profit, writs, road. A line about another
--      character, a craft already queued, a craft still in stock, a writ
--      done today or one that costs more than it pays is left out. One of
--      a thing reads as one ("1 sale is waiting in your mail").
--   2. A kind turned off in Settings is gone; ticking it back writes the
--      setting away again, and a box that did not change writes nothing.
--   3. Buttons only open or queue: Queue It asks for one, Queue N fills the
--      room in crafts, Show Them opens the tab.
--   4. The Profit ranking runs a few recipes a frame and is kept until a
--      price, the queue, a setting or the recipes change.
--   6. An item the game has not loaded yet shows a name the addon already
--      holds (the recipe's), never "item 5764", and the tab draws again
--      once the game sends the item.
--   5. The window opens on Today the first time it is opened by hand in a
--      session, and keeps the tab left after that. Docked, it does not.
--      With nothing to do it says so; a row whose line did not change keeps
--      what it drew.

local GLOBALS = { "CreateFrame", "UIParent", "GameTooltip", "GetCursorPosition", "C_Timer",
    "UISpecialFrames", "tinsert", "GetTime", "time", "BlackthornesWindow", "MailFrame", "C_Item" }
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

local function Region(parent)
    local region = { parent = parent, shown = true, width = 0, height = 0, scale = 1,
        points = {}, scripts = {}, frameLevel = 1, text = "" }
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
        self.points[#self.points + 1] = { point, relativeTo, relativePoint, x or 0, y or 0 }
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
    region.IsVisible = function(self)
        local at = self
        while at do
            if not at.shown then return false end
            at = at.parent
        end
        return true
    end
    region.SetText = function(self, text) self.text = text; self.sets = (self.sets or 0) + 1 end
    region.GetText = function(self) return self.text end
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

-- Frames run their timers when told: Flush runs what is waiting.
local timers = {}
local function Flush()
    local rounds = 0
    while #timers > 0 and rounds < 1000 do
        rounds = rounds + 1
        local now = timers
        timers = {}
        for _, fn in ipairs(now) do fn() end
    end
    return rounds
end

CreateFrame = function(_, _, parent) return Region(parent) end
UIParent = Region()
UIParent.width, UIParent.height = 1280, 720
GameTooltip = Region()
GetCursorPosition = function() return 0, 0 end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
UISpecialFrames = {}
tinsert = table.insert
GetTime = function() return 0 end
time = os.time

local settings = {}
local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = ns[name] or {}; ns[name] = m; return m end
ns.RegisterCommand = noop
local events = {}
ns.RegisterEvent = function(_, event, fn) events[event] = fn; return true end
-- Item names the game has loaded; one listed as false is not loaded yet.
local notLoaded, asked = {}, {}
C_Item = {
    GetItemInfo = function(itemID) if not notLoaded[itemID] then return "Item " .. itemID end end,
    RequestLoadItemDataByID = function(itemID) asked[itemID] = true end,
}
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop
ns.db = { global = {}, settings = settings, characters = { ME = { recipesCachedAt = 1 } },
    postLimits = { [100] = 4, [101] = 2 } }
local writes = 0
ns.Config = {
    DEFAULTS = { settings = { windowScale = 1 } },
    changes = 0,
    Get = function(_, key) return settings[key] end,
    Set = function(self, key, value) settings[key] = value; writes = writes + 1; self.changes = self.changes + 1 end,
    GetCharacterKey = function() return "ME" end,
}
ns.Scanner = { isAuctionHouseOpen = false, CanFullScan = function() return true end, StartFullScan = noop }
ns.Prices = { Count = function() return 0 end, GetLastScan = function() return os.time() - 720 end, scanCount = 1 }
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

-- What the other parts know.
ns.Characters = { IsPlaying = function(_, key) return key == "ME" end }
local heard = {
    { who = "ME", itemID = 5 }, { who = "ME", itemID = 6 }, { who = "ALT", itemID = 7 },
}
ns.Mail = { SettleHeard = function() return heard end }
local auctionRows = {
    { mine = true, state = "undercut", itemID = 100 },
    { mine = true, state = "undercut", itemID = 102 },
    { mine = true, state = "cheapest", itemID = 103 },
    { alt = true, state = "undercut", itemID = 104 },
}
ns.MyAuctions = { Rows = function() return auctionRows end }
ns.CraftProfit = {
    For = function(_, recipeID) return { profit = recipeID * 10 } end,
    SignedMoney = function(copper) return "+" .. copper end,
}
local readyList = {
    { key = "ME", recipeID = 31, itemID = 300, name = "Mooncloth" },
    { key = "ALT", recipeID = 32, itemID = 301 },
    { key = "ME", recipeID = 33, itemID = 302 },
}
local queued = { [33] = true }
local ensured, added = {}, {}
ns.Queue = {
    version = 1,
    Find = function(_, recipeID) if queued[recipeID] then return 1, {} end end,
    Ensure = function(_, recipeID, n) ensured[#ensured + 1] = recipeID .. "x" .. n; return true end,
    Add = function(_, recipeID, n) added[#added + 1] = recipeID .. "x" .. n; return true end,
    RecipeFor = function(_, itemID) return itemID + 1000, { quantityMin = 1, name = "Recipe " .. itemID } end,
}
ns.Cooldowns = { ReadyList = function() return readyList end }
ns.Auctions = {
    GetRoom = function(_, itemID)
        if itemID == 100 then return 4, 0, 0, 0, 4, 0 end
        return 1, 1, 0, 0, 2, 0   -- one still listed
    end,
}
ns.Profit = {
    RoomInCrafts = function(room) return math.ceil(room / 2) end,
}
local analysed = 0
local RECIPES = 50
function ns.Profit:BeginRanked()
    local items = {}
    for id = 1, RECIPES do items[id] = { recipeID = id } end
    return { items = items, results = {} }
end
function ns.Profit:RankOne(ranking, item)
    analysed = analysed + 1
    if item.recipeID % 10 == 0 then
        ranking.results[#ranking.results + 1] = { priceable = true, profit = item.recipeID * 100, outputItemID = item.recipeID }
    end
end
function ns.Profit:FinishRanked(ranking) return ranking.results end
local writRows = {
    { total = -300, itemID = 900 },
    { total = -15, itemID = 901, done = true },
    { total = 200, itemID = 902 },
    { total = -50, itemID = 903 },
}
ns.Writs = { GetRows = function() return writRows end }
ns.RoadPlan = {
    TARGET = 300, FISHING = 356,
    Professions = function() return { { name = "Tailoring", line = 197, skill = 262, max = 300 } } end,
    Get = function() return {
        current = 2,
        steps = {
            { kind = "craft", recipeID = 1, crafts = 9, cost = 1, done = true },
            { kind = "craft", recipeID = 7, crafts = 2, cost = 30, outputItemID = 700 },
            { kind = "craft", recipeID = 7, crafts = 1, cost = 24 },
            { kind = "craft", recipeID = 8, crafts = 5, cost = 99 },
        },
    } end,
}

local function Load(path) assert(loadfile(lfs_cwd .. path))("Blackthornes_TS", ns) end
_G.BlackthornesWindow = nil
Load("/Core/Util.lua")
Load("/UI/Theme.lua")
Load("/UI/Widgets.lua")
Load("/UI/SharedWindow.lua")
Load("/UI/Main.lua")
Load("/Logic/Today.lua")
Load("/UI/Tab_Today.lua")

local Today, UI = ns.Today, ns.UI
for index, key in ipairs({ "profit", "queue", "sales", "deals", "settings" }) do
    UI:RegisterTab({ key = key, text = key, order = index, build = noop })
end

local function Find(lines, kind)
    local out = {}
    for _, line in ipairs(lines) do if line.kind == kind then out[#out + 1] = line end end
    return out
end

--------------------------------------------------------------------------------
print("1. the lines")

do
    local lines = Today:Lines()
    check("the profit list is not ready on the first ask", #Find(lines, "profit"), 0)
    Flush()
    lines = Today:Lines()
    local kinds = {}
    for _, line in ipairs(lines) do kinds[#kinds + 1] = line.kind end
    check("in order", table.concat(kinds, ","), "mail,undercut,ready,soldout,profit,writs,road")

    local mail = Find(lines, "mail")[1]
    check("mail counts only the character playing's", mail.text, "2 sales are waiting in your mail")

    local under = Find(lines, "undercut")[1]
    check("undercut counts only your own auctions", under.text, "2 of your auctions were undercut")
    check("and names the first", under.detail, "Item 100 and 1 more")

    local ready = Find(lines, "ready")
    check("one cooldown line: not the alt's, not one queued", #ready, 1)
    check("named for what it makes", ready[1].text, "Item 300 is ready to make")
    check("with its profit each", ready[1].money, 310)

    local sold = Find(lines, "soldout")
    check("only the craft with nothing left", #sold, 1)
    check("says how many you keep", sold[1].text, "Item 100 sold out. You keep 4 listed.")
    check("and queues the room", sold[1].button, "Queue 4")

    local profit = Find(lines, "profit")[1]
    check("crafts that pay", profit.text, "5 crafts pay well right now")
    check("with the best", profit.money, 5000)

    local writs = Find(lines, "writs")[1]
    check("writs that pay back, not done today", writs.text, "2 writs are worth doing today")
    check("what they pay back", writs.money, 350)

    local road = Find(lines, "road")[1]
    check("the road to the next recipe", road.text, "Tailoring 262. 3 crafts to your next recipe.")
    check("and what that stretch costs", road.money, 54)

    heard = { { who = "ME", itemID = 5 } }
    auctionRows = { { mine = true, state = "undercut", itemID = 100 } }
    lines = Today:Lines()
    check("one sale reads as one", Find(lines, "mail")[1].text, "1 sale is waiting in your mail")
    check("one auction reads as one", Find(lines, "undercut")[1].text, "1 of your auctions was undercut")
    check("with no 'and more'", Find(lines, "undercut")[1].detail, "Item 100")
end

--------------------------------------------------------------------------------
print("2. turned off in Settings")

do
    writes = 0
    Today:SetShown("mail", true)
    check("a box that did not change writes nothing", writes, 0)
    Today:SetShown("mail", false)
    check("unticked is saved", settings.todayHide_mail, true)
    check("and the line is gone", #Find(Today:Lines(), "mail"), 0)
    Today:SetShown("mail", true)
    check("ticked again writes the setting away", settings.todayHide_mail, nil)
    check("and the line is back", #Find(Today:Lines(), "mail"), 1)
end

--------------------------------------------------------------------------------
print("3. the buttons")

UI:Show()

do
    Today:Lines()
    Flush()
    local lines = Today:Lines()
    check("Queue It asks for one", Today:Run(Find(lines, "ready")[1]), true)
    check("of that craft", ensured[1], "31x1")
    check("Queue N fills the room", Today:Run(Find(lines, "soldout")[1]), true)
    check("in crafts", added[1], "1100x2")
    Today:Run(Find(lines, "profit")[1])
    check("Show Them opens Profit", UI.activeTab, "profit")
    check("nothing was bought or posted", #printed, 0)
end

--------------------------------------------------------------------------------
print("4. the profit ranking")

do
    Today:Forget()
    analysed = 0
    check("not ready at once", Today:Ranked(), nil)
    check("nothing analysed in the asking frame", analysed, 0)
    local frames = Flush()
    check("all analysed", analysed, RECIPES)
    check("over several frames", frames > 1, true)
    Today:Ranked()
    Flush()
    check("kept while nothing changed", analysed, RECIPES)
    ns.Prices.scanCount = 2
    Today:Ranked()
    Flush()
    check("a new scan ranks again", analysed, 2 * RECIPES)
end

--------------------------------------------------------------------------------
print("5. the window")

do
    UI:Hide()
    UI.todayOpened, UI.activeTab = nil, nil
    UI:Show()
    check("opens on Today the first time", UI.activeTab, "today")
    UI:SelectTab("queue")
    UI:Hide()
    UI:Show()
    check("keeps the tab left after that", UI.activeTab, "queue")

    -- Docked at the auction house: that place's own tab, not Today.
    UI:Hide()
    UI.todayOpened, UI.activeTab = nil, nil
    ns.db.lastTab = "queue"
    ns.TSTabs.atAuction = true
    UI:Show()
    check("docked, it does not open on Today", UI.activeTab, "queue")
    ns.TSTabs.atAuction = false

    -- Opened by itself at the mailbox (not docked): the mail's tab, not Today.
    UI:Hide()
    UI.todayOpened, UI.activeTab = nil, nil
    _G.MailFrame = Region()
    UI:Show()
    check("at the mailbox, it does not open on Today", UI.activeTab, "queue")
    check("and Today is still to come", UI.todayOpened, nil)
    _G.MailFrame = saved.MailFrame

    local w = UI._TodayWidgets
    w.list.width, w.list.height = 600, 400
    UI:SelectTab("today")
    Flush()
    UI:RefreshActiveTab()
    check("lines show in the list", w.list:IsShown(), true)
    check("all caught up stays hidden", w.empty:IsShown(), false)
    local row = w.list.rows[1]
    local sets = row.text.sets
    UI:RefreshActiveTab()
    check("a row whose line did not change keeps what it drew", row.text.sets, sets)

    local oldLines = Today.Lines
    Today.Lines = function() return {} end
    UI:RefreshActiveTab()
    check("all caught up shows when nothing is left", w.empty:IsShown(), true)
    check("and the list goes", w.list:IsShown(), false)
    Today.Lines = oldLines
    UI:RefreshActiveTab()
    check("and comes back with the lines", w.list:IsShown(), true)
end

--------------------------------------------------------------------------------
print("6. names not loaded yet")

do
    notLoaded[100] = true
    local redrawn = 0
    local lines = Today:Lines(function() redrawn = redrawn + 1 end)
    local sold = Find(lines, "soldout")[1]
    check("a craft not loaded yet shows its recipe's name, not its number",
        sold.text, "Recipe 100 sold out. You keep 4 listed.")
    check("the game is asked for the item", asked[100], true)
    local key = sold.key

    notLoaded[100] = nil
    events.GET_ITEM_INFO_RECEIVED(nil, "GET_ITEM_INFO_RECEIVED", 999)
    check("another item's data draws nothing", redrawn, 0)
    events.GET_ITEM_INFO_RECEIVED(nil, "GET_ITEM_INFO_RECEIVED", 100)
    Flush()
    check("the tab draws again once the item comes in", redrawn, 1)
    events.GET_ITEM_INFO_RECEIVED(nil, "GET_ITEM_INFO_RECEIVED", 100)
    Flush()
    check("and only once", redrawn, 1)

    sold = Find(Today:Lines(), "soldout")[1]
    check("now with the item's own name", sold.text, "Item 100 sold out. You keep 4 listed.")
    check("and a new key, so its row draws again", sold.key ~= key, true)

    notLoaded[100] = true
    readyList[1].itemID = 100
    local ready = Find(Today:Lines(), "ready")[1]
    check("a cooldown not loaded yet keeps the name it came with", ready.text, "Mooncloth is ready to make")
    auctionRows = { { mine = true, state = "undercut", itemID = 100, link = "|cff1eff00|Hitem:100::::::::18:1485:::1:12722|h[Linked Name]|h|r" } }
    check("an auction not loaded yet reads its link's name",
        Find(Today:Lines(), "undercut")[1].detail, "Linked Name")
    notLoaded[100] = nil
end

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then error(failed .. " check(s) failed") end
