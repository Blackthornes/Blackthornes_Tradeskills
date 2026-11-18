-- A sale is a sale: two things the owner saw in game (2026-11-18).
--
--  * The debug line said "you just cancelled an auction" when one sold. The
--    game sends AUCTION_CANCELED for a sale too, and AHQueue took every one
--    as the player's own cancel.
--  * A sale of something kept in stock always said "nothing queued, you
--    still have as many as you keep", even with none left. The reading of
--    your auctions only changes at the auction house, so the listing that
--    just sold was still counted as listed.
--
-- Drives the real Core/AHQueue.lua, Data/Auctions.lua, Data/Mail.lua's
-- heard sales, Logic/Queue.lua and the sale alarm's Restock.

local GLOBALS = { "GetTime", "time", "C_Timer", "C_AuctionHouse", "hooksecurefunc" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end
local clock = 1000
local NOW = 2000000
GetTime = function() return clock end
time = function() return NOW end
C_Timer = { After = noop, NewTimer = function() return { Cancel = noop } end,
    NewTicker = function() return { Cancel = noop } end }

local cancelsSent = 0
C_AuctionHouse = { CancelAuction = function() cancelsSent = cancelsSent + 1 end }
hooksecurefunc = function(tbl, key, post)
    local original = tbl[key]
    tbl[key] = function(...) local r = original(...); post(...); return r end
end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = noop
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn; return true end
local printed, debug = {}, {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.Debug = function(...) debug[#debug + 1] = table.concat({ ... }, " ") end
ns.PrintRaw, ns.Warn = noop, noop
ns.Util = { HasFunction = function() return false end }
ns.db = { queue = {}, postLimits = {}, postedAuctions = {}, heardSales = {} }

local config = { maxPostedPerItem = 0, autoQueueSubCrafts = false }
ns.Config = {
    Get = function(_, key) return config[key] end,
    GetRealmKey = function() return "Test-Realm" end,
    GetCharacterKey = function() return "me" end,
}

local checks = 0
local function check(label, condition, detail)
    checks = checks + 1
    if not condition then error(("FAILED: %s %s"):format(label, tostring(detail or "")), 2) end
    print(("  ok  %s"):format(label))
end

local ok, err = pcall(function()
    ---------------------------------------------------------------------------
    -- 1. AUCTION_CANCELED after a sale is not your cancel.
    ---------------------------------------------------------------------------
    assert(loadfile(lfs_cwd .. "/Core/AHQueue.lua"))("Blackthornes_TS", ns)
    local AHQueue = ns.AHQueue
    AHQueue:OnEnable()
    check("the queue listens for AUCTION_CANCELED", handlers.AUCTION_CANCELED ~= nil)

    local function said(word)
        for _, line in ipairs(debug) do if line:find(word, 1, true) then return true end end
        return false
    end

    handlers.AUCTION_CANCELED()
    check("a sale is not called a cancel", not said("cancelled"), table.concat(debug, " | "))
    check("the debug line says it sold or ran out", said("sold or ran out"))

    debug = {}
    C_AuctionHouse.CancelAuction(42)
    check("the real cancel still reaches the game", cancelsSent == 1)
    clock = clock + 1
    handlers.AUCTION_CANCELED()
    check("a cancel you asked for is still a cancel", said("you just cancelled"), table.concat(debug, " | "))

    debug = {}
    clock = clock + 60
    handlers.AUCTION_CANCELED()
    check("a sale a minute later is not that cancel again", not said("cancelled"))

    ---------------------------------------------------------------------------
    -- 2. A sale takes the listing off Keep in stock before the next visit.
    ---------------------------------------------------------------------------
    local SHIRT = 200
    local recipes = { [2] = { recipeID = 2, outputItemID = SHIRT, quantityMin = 1 } }
    ns.Recipes = {
        Get = function(_, id) return recipes[id] end,
        GetAny = function(_, id) return recipes[id] end,
        GetAll = function() return recipes end,
        GetAccountWideOutputs = function() return {} end,
    }
    ns.Inventory = {
        GetBagCount = function() return 0 end,
        GetBankCount = function() return 0 end,
        GetMailCount = function() return 0 end,
        GetOwnedCount = function() return 0 end,
    }
    ns.Profit = {
        RoomInCrafts = function(room) return room end,
        Analyse = function() return { totalCost = 10, profit = 5 } end,
    }
    ns.UI = { OnQueueUpdated = noop }

    assert(loadfile(lfs_cwd .. "/Data/Auctions.lua"))("Blackthornes_TS", ns)
    -- The real Mail.lua is big; take only its heard-sale half from it.
    ns.Mail = { GetLedger = function() return { entries = {} } end,
        ResolveItemName = function(_, name) return name:find("Shirt") and SHIRT or nil end }
    local chunk = assert(loadfile(lfs_cwd .. "/Data/Mail.lua"))
    local mailNs = setmetatable({ Mail = nil }, { __index = ns })
    mailNs.NewModule = function() return ns.Mail end
    chunk("Blackthornes_TS", mailNs)
    local ledger = { entries = {} }
    ns.Mail.GetLedger = function() return ledger end
    ns.Mail.ResolveItemName = function(_, name) return name:find("Shirt") and SHIRT or nil end

    assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)
    assert(loadfile(lfs_cwd .. "/Logic/SaleAlarm.lua"))("Blackthornes_TS", ns)
    local Auctions, Queue, SaleAlarm = ns.Auctions, ns.Queue, ns.SaleAlarm

    -- Keep 1 shirt. The last look at the auction house saw your 1 listed.
    ns.db.postLimits[SHIRT] = 1
    local record = Auctions:GetTable()
    record.byCharacter = { me = { items = { [SHIRT] = 1 }, updatedAt = NOW - 600,
        listings = { { itemID = SHIRT, quantity = 1, unit = 500, ends = NOW + 3600 } } } }
    check("before the sale, 1 is listed", Auctions:GetPostedCount(SHIRT) == 1)

    NOW = NOW + 60
    SaleAlarm.unpaired = nil
    SaleAlarm:LogHeard("Shirt", "chat")
    local _, entry = Queue:Find(2, true)
    check("the sold shirt is no longer counted as listed", Auctions:GetPostedCount(SHIRT) == 0,
        Auctions:GetPostedCount(SHIRT))
    check("a sale with none left queues another", entry and entry.quantity == 1,
        printed[#printed])
    check("and chat says so", printed[#printed] == "Shirt sold: queued another to keep your stock up.",
        printed[#printed])

    -- Its mail is read later: still the same one sale, never two.
    NOW = NOW + 3600
    ledger.entries[#ledger.entries + 1] = { kind = "sold", itemID = SHIRT, name = "Shirt",
        quantity = 1, who = "me", t = NOW, sent = NOW - 10 }
    check("the mail before pairing is the same sale", Auctions:GetPostedCount(SHIRT) == 0)
    ns.Mail:SettleHeard()
    check("the heard sale found its mail", #ns.Mail:GetHeardList() == 0)
    check("the mail keeps when it sold", ledger.entries[1].heardAt ~= nil)

    -- A second listing of 2, read again later: the old sale counts no more.
    record.byCharacter.me = { items = { [SHIRT] = 2 }, updatedAt = NOW + 5 }
    NOW = NOW + 10
    check("a new reading is the truth again", Auctions:GetPostedCount(SHIRT) == 2,
        Auctions:GetPostedCount(SHIRT))

    -- A stack sold: the line carries its count.
    SaleAlarm.unpaired = nil
    SaleAlarm:LogHeard("Shirt (2)", "chat")
    check("a stack of 2 sold takes 2 off", Auctions:GetPostedCount(SHIRT) == 0,
        Auctions:GetPostedCount(SHIRT))

    -- Sold while you were away: a sold mail sent an hour after a reading is
    -- a sale after it. One sent soon after could be from before it.
    record.byCharacter.me = { items = { [SHIRT] = 3 }, updatedAt = NOW + 5 }
    ns.db.heardSales = {}
    NOW = NOW + 10
    ledger.entries[#ledger.entries + 1] = { kind = "sold", itemID = SHIRT, quantity = 1,
        who = "me", t = NOW, sent = NOW - 60 }
    check("a sold mail sent right after the reading is not taken off", Auctions:GetPostedCount(SHIRT) == 3)
    NOW = NOW + 7200
    ledger.entries[#ledger.entries + 1] = { kind = "sold", itemID = SHIRT, quantity = 1,
        who = "me", t = NOW, sent = NOW - 60 }
    check("one sent over an hour after is taken off", Auctions:GetPostedCount(SHIRT) == 2,
        Auctions:GetPostedCount(SHIRT))

    -- An alt's sale never takes off your listing.
    ns.db.heardSales["Test-Realm"] = { { t = NOW + 1, itemID = SHIRT, who = "alt", quantity = 1 } }
    NOW = NOW + 5
    check("another character's sale leaves yours alone", Auctions:GetPostedCount(SHIRT) == 2)
end)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end
if not ok then error(err, 0) end
print(("test_soldnotcancelled: %d checks passed"):format(checks))
