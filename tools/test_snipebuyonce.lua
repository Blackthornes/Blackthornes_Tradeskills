-- A Snipe buy is counted once, and only when Snipe itself bought.
--
-- Snipe's events were never heard in the game until 2026-11-26, so what
-- they do beside the rest of the addon had never run there. Two things
-- went wrong once they were heard:
--
--   * AHBuys watches every stack buy itself (it hooks the game's
--     ConfirmCommoditiesPurchase and hears the purchase event), and Snipe
--     wrote the same buy down again. The shopping lists then counted twice
--     what was on its way in the mail, and Snipe on My Lists stopped at
--     half of what was needed.
--   * Snipe took any stack buy's "it went through" as its own. A deal it
--     had readied in the background (waiting for the click) was marked
--     bought, and its cost counted against the Spending Cap, when the
--     player bought something else at the auction house.
--
-- What must hold:
--   1. A stack bought through Snipe is put down once as waiting in the mail.
--   2. A purchase event while Snipe's buy is only readied, not paid for,
--      leaves the buy, the find and the amount spent alone.
--   3. A failed purchase of the player's own does not let a readied buy go.

local GLOBALS = { "time", "GetMoney", "C_AuctionHouse", "hooksecurefunc" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local clock = 200000
time = function() return clock end
local money = 100000
GetMoney = function() return money end

-- The game's own: the hook runs after the call it watches.
hooksecurefunc = function(owner, name, fn)
    local was = owner[name]
    owner[name] = function(...)
        local a, b, c = was(...)
        fn(...)
        return a, b, c
    end
end

C_AuctionHouse = {
    GetItemCommodityStatus = function() return 2 end,
    MakeItemKey = function(id) return { itemID = id } end,
    SendSearchQuery = function() return true end,
    StartCommoditiesPurchase = function() end,
    CancelCommoditiesPurchase = function() end,
    ConfirmCommoditiesPurchase = function() end,
    PlaceBid = function() end,
}

local ns = {}
ns.NewModule = function(name) local m = { moduleName = name }; ns[name] = m; return m end
ns.Util = { HasFunction = function() return true end, FormatMoney = tostring }
ns.Print, ns.Debug, ns.RegisterCommand = function() end, function() end, function() end
ns.Notice = { Show = function() end }
local settings = { snipeCap = 5000, snipeWatch = "priced" }
ns.Config = { Get = function(_, k) return settings[k] end }
local record = {}
ns.Recipes = { GetCharacterRecord = function() return record end }

-- Every module's handler of an event runs, as in Core/Init.lua.
local handlers = {}
ns.RegisterEvent = function(owner, event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], { owner = owner, fn = fn })
    return true
end
local function Fire(event, ...)
    for _, entry in ipairs(handlers[event] or {}) do entry.fn(entry.owner, event, ...) end
end

assert(loadfile(lfs_cwd .. "/Logic/AHBuys.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Snipe.lua"))("Blackthornes_TS", ns)
local AHBuys, Snipe = ns.AHBuys, ns.Snipe
AHBuys:OnEnable()
Snipe:OnEnable()

local function Waiting(itemID)
    local total = 0
    for _, buy in ipairs(record.ahBuys or {}) do
        if buy.itemID == itemID then total = total + buy.quantity end
    end
    return total
end

local HERB, ORE = 2447, 2770

-- 1. One stack buy, written down once.
local herb = { itemID = HERB, kind = "priced", price = 90, worth = 200, qty = 3 }
Snipe.running, Snipe.spent, Snipe.finds = false, 0, { herb }
Snipe.pending = { itemID = HERB, count = 3, phase = "quoted", total = 270, expected = 270,
    find = herb, stack = true }
assert(Snipe:Pay() == true, "the click pays the quote")
money = money - 270
Fire("PLAYER_MONEY")
Fire("COMMODITY_PURCHASE_SUCCEEDED")
assert(Snipe.pending == nil and Snipe.spent == 270, "Snipe counts its buy")
assert(Waiting(HERB) == 3, "3 bought, but " .. Waiting(HERB) .. " put down as waiting in the mail")
print("ok 1 a Snipe stack buy is put down once")

-- 2. A readied deal is not bought by the player's own buy of something else.
record.ahBuys = {}
clock = clock + 100
local ready = { itemID = HERB, kind = "priced", price = 90, worth = 200, qty = 3 }
Snipe.spent, Snipe.finds = 0, { ready }
local quote = { itemID = HERB, count = 3, phase = "quoted", total = 270, expected = 270,
    find = ready, stack = true, auto = true }
Snipe.pending = quote
C_AuctionHouse.ConfirmCommoditiesPurchase(ORE, 5)
money = money - 500
Fire("PLAYER_MONEY")
Fire("COMMODITY_PURCHASE_SUCCEEDED")
assert(Snipe.pending == quote, "the readied buy is still there")
assert(Snipe.spent == 0, "nothing of Snipe's was spent, but it counts " .. Snipe.spent)
assert(#Snipe.finds == 1, "the find stays on the list")
assert(Waiting(ORE) == 5 and Waiting(HERB) == 0, "only the player's own buy is waiting in the mail")
print("ok 2 another buy going through leaves a readied Snipe buy alone")

-- 3. Nor does the player's own failed buy let it go.
C_AuctionHouse.ConfirmCommoditiesPurchase(ORE, 5)
Fire("COMMODITY_PURCHASE_FAILED")
assert(Snipe.pending == quote, "a failed buy of something else keeps the readied buy")
print("ok 3 another buy failing leaves a readied Snipe buy alone")

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end
