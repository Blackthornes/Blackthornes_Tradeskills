-- The one-second auction house ticker, outside WoW.
--
-- It used to rebuild the sell lists every second the auction house was open,
-- walking the bags and pricing every stack three times over even when
-- nothing had moved: the kind of timer the smooth-play rule forbids. Now it
-- rebuilds only when something the lists are made from changed, and the
-- quiet seconds only put the panel back in place.

local GLOBALS = { "CreateFrame", "UIParent", "C_Timer", "Minimap", "GetTime", "time" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end
local function NewFrame()
    return setmetatable({}, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
end
CreateFrame = function() return NewFrame() end
UIParent = NewFrame()
Minimap = nil
GetTime = function() return 0 end
time = function() return 100000 end

local tickers = {}
C_Timer = {
    After = noop,
    NewTicker = function(interval, fn)
        local ticker = { interval = interval, fn = fn, Cancel = noop }
        tickers[#tickers + 1] = ticker
        return ticker
    end,
}

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop

local handlers = {}
ns.RegisterEvent = function(owner, event, fn)
    handlers[event] = handlers[event] or {}
    handlers[event][#handlers[event] + 1] = { owner = owner, fn = fn }
    return true
end
local function Fire(event, ...)
    for _, entry in ipairs(handlers[event] or {}) do entry.fn(entry.owner, event, ...) end
end

ns.db = {}
local queue = {}
ns.Queue = { GetAll = function() return queue end }
ns.Inventory, ns.Prices, ns.Config, ns.Auctions = {}, {}, {}, {}
ns.Scanner = { isAuctionHouseOpen = true, isScanning = false }
local throttled = false
ns.Posting = {
    IsBlocked = function() return false end,
    IsThrottled = function() return throttled end,
}
ns.Theme, ns.Widgets = {}, {}

local placed = 0
ns.PostPanel = { Refresh = noop, Place = function() placed = placed + 1 end }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/Main.lua"))("Blackthornes_TS", ns)

local UI = ns.UI
for _, name in ipairs({ "Build", "BuildMinimapButton", "HookAltClickSearch", "UpdateHeader",
    "AttachToAuctionHouse", "OpenWithShop", "CloseWithShop", "RestorePosition",
    "UpdateWaitLabels", "RefreshActiveTab", "RepositionMinimapButton" }) do
    UI[name] = noop
end

local builds = 0
UI.UpdatePostButton = function() builds = builds + 1 end

UI:OnEnable()
Fire("AUCTION_HOUSE_SHOW")

local postTicker
for _, ticker in ipairs(tickers) do
    if ticker.interval == 1 then postTicker = ticker end
end
assert(postTicker, "no one-second ticker at the auction house")

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-6s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Tick(times)
    for _ = 1, times or 1 do postTicker.fn() end
end

print("")
print("the sell lists at the auction house")

Tick()
check("the first second builds them", builds, 1)
Tick(10)
check("ten quiet seconds build nothing more", builds, 1)
check("but the panel is put back in place each second", placed, 10)

ns.Inventory.changes = 1
Tick()
check("a bag change rebuilds them", builds, 2)

ns.Prices.changes = 1
Tick()
check("a new price does", builds, 3)

queue[1] = { recipeID = 1, quantity = 2 }
Tick()
check("a craft queued does", builds, 4)
queue[1].quantity = 3
Tick()
check("and one more of it", builds, 5)

throttled = true
Tick()
check("the auction house going busy does", builds, 6)
throttled = false
Tick()
check("and coming free again", builds, 7)

ns.Posting.pending = { itemID = 2589 }
Tick()
check("a listing being confirmed does", builds, 8)

Fire("GET_ITEM_INFO_RECEIVED", 2589, true)
Tick()
check("item data arriving does", builds, 9)

Tick(5)
check("and then quiet again", builds, 9)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then error(failed .. " sell ticker check(s) failed") end
