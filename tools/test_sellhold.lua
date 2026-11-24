-- The Sell list holds still under the mouse.
--
-- A player's report (2026-11-24): while a scan ran, rows on Sell moved and
-- went away, so the second click of Check Price then List landed on another
-- item. A scan writes prices a few items a frame, and the list, sorted by
-- worth, was sorted again each second. Under the mouse the rows now keep
-- their order; once the mouse leaves, the list is sorted again.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
ns.Print, ns.Debug, ns.Warn = function() end, function() end, function() end

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

CreateFrame = function() return Stub() end
C_Timer = { After = function() end, NewTicker = function() return Stub() end }
ns.Theme = setmetatable({}, { __index = function() return function() return Stub() end end })
ns.Widgets = setmetatable({}, { __index = function() return function() return Stub() end end })
ns.Util = { FormatMoney = function(c) return tostring(c) end }
ns.COLORS = {}

local settings = {}
ns.Config = { Get = function(_, key) return settings[key] end }

local PostPanel
local realNew = ns.NewModule
ns.NewModule = function(name) local m = realNew(name); PostPanel = m; return m end
assert(loadfile(lfs_cwd .. "/UI/PostPanel.lua"))("Blackthornes_TS", ns)

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function Order(lines)
    local ids = {}
    for i, line in ipairs(lines) do ids[i] = line.itemID end
    return table.concat(ids, ",")
end

-- What the bags hold, sorted by worth as Posting sorts it.
local worth = { [1] = 300, [2] = 200, [3] = 100 }
local losses = {}
local function Postable()
    local lines = {}
    for id, total in pairs(worth) do
        lines[#lines + 1] = { itemID = id, total = total, atALoss = losses[id] }
    end
    table.sort(lines, function(a, b) return a.total > b.total end)
    return lines, 0
end
ns.Posting = { GetPostable = Postable }

local over = false
PostPanel.list = Stub({ IsShown = function() return true end, IsMouseOver = function() return over end })
PostPanel.view = "sell"

local refreshed = 0
-- One look at the list, as Refresh takes it.
local function Look()
    local lines = PostPanel:ShownLines()
    PostPanel.shownLines = lines
    return lines
end

check("first look is sorted by worth", Order(Look()) == "1,2,3")

-- The mouse is on the list and a scan writes new prices.
over = true
worth[3] = 900
worth[1] = 50
local lines = Look()
check("under the mouse, the rows keep their places", Order(lines) == "1,2,3")
check("each row has its new price", lines[1].total == 50 and lines[3].total == 900)

-- A price makes item 2 a loss, with Hide losses ticked.
settings.postHideLosses = true
losses[2] = true
check("a row that turned into a loss stays put under the mouse", Order(Look()) == "1,2,3")

-- A new item lands in the bags; one is listed and leaves them.
worth[4] = 10000
worth[1] = nil
check("an item gone from the bags goes, a new one joins at the bottom", Order(Look()) == "2,3,4")

-- The mouse leaves: sorted again on the next second's look.
PostPanel.Refresh = function() refreshed = refreshed + 1 end
PostPanel:LetGoOfOrder()
check("while the mouse stays, nothing sorts again", refreshed == 0)
over = false
PostPanel:LetGoOfOrder()
check("once the mouse leaves, the list is redrawn", refreshed == 1)
check("and sorted by worth, the loss hidden", Order(Look()) == "4,3")
PostPanel:LetGoOfOrder()
check("only once", refreshed == 1)

-- A list that will not say where the mouse is never holds.
over = true
PostPanel.list.IsMouseOver = function() error("secret") end
check("an error reading the mouse sorts as usual", PostPanel:HoldsOrder() == false)

check("nothing shown before, nothing to hold",
    Order(PostPanel.HoldOrder(nil, { { itemID = 5 } }, {})) == "5")

local main = assert(io.open(lfs_cwd .. "/UI/Main.lua")):read("*a")
check("the one-second look lets go of the order", main:find("PostPanel:LetGoOfOrder()", 1, true) ~= nil)

print(("\n%d check(s) passed\n"):format(checks))
