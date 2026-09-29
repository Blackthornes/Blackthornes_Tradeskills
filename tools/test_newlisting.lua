-- A listing that went up is settled as listed even when the count did not
-- rise, because one of your auctions of the same item sold since the last
-- read. The count alone said "did not appear in your auctions" and blamed
-- the auction house, for a listing sitting right there.
--
-- Also: a listing's own give-up timer must not settle the next listing.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return false end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

ns.Util = {
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    HasFunction = function(path)
        return path == "C_AuctionHouse.GetNumOwnedAuctions"
            or path == "C_AuctionHouse.GetOwnedAuctionInfo"
            or path == "C_AuctionHouse.QueryOwnedAuctions"
    end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
    WhenAuctionReady = function(action) action() end,
}

ns.db = {}
ns.Config = { GetRealmKey = function() return "TestRealm" end }
ns.Scanner = { isAuctionHouseOpen = true }
ns.Inventory = { GetOwnedCount = function() return 0 end }
ns.Queue = { GetAll = function() return {} end }
ns.Recipes = { GetAny = function() return nil end }
ns.AHQueue = { PRIORITY = { urgent = 10, normal = 50, scan = 90 } }

time = time or os.time

local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }

local listed = {}
C_AuctionHouse = {
    GetNumOwnedAuctions = function() return #listed end,
    GetOwnedAuctionInfo = function(index)
        local entry = listed[index]
        if not entry then return nil end
        return { auctionID = entry.id, itemKey = { itemID = entry.itemID },
                 quantity = entry.quantity, status = 0 }
    end,
    QueryOwnedAuctions = function() end,
}

assert(loadfile(lfs_cwd .. "/Data/Auctions.lua"))("Blackthornes_TS", ns)
local Auctions = ns.Auctions

local resolved
ns.Posting = {
    ResolvePending = function(self, posted, appeared)
        resolved = { posted = posted, appeared = appeared }
        self.pending = nil
    end,
}

local failures = 0
local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-58s %-8s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

print("\na listing that went up while another of the same item sold")

-- Three bags listed, read at the auction house.
listed = {
    { id = 101, itemID = 4240, quantity = 1 },
    { id = 102, itemID = 4240, quantity = 1 },
    { id = 103, itemID = 4240, quantity = 1 },
}
Auctions:ReadOwned({})
check("three listed at the last read", Auctions:GetPostedCount(4240), 3)

-- One sells; nothing re-reads. Then one more is listed.
ns.Posting.pending = {
    itemID = 4240,
    postedBefore = Auctions:GetPostedCount(4240),
    idsBefore = Auctions.GetOwnedIDs and Auctions:GetOwnedIDs(4240) or nil,
    verifying = true,
}
listed = {
    { id = 102, itemID = 4240, quantity = 1 },
    { id = 103, itemID = 4240, quantity = 1 },
    { id = 104, itemID = 4240, quantity = 1 },
}

resolved = nil
Auctions:ReadOwned({})
check("settled on the first read", resolved ~= nil, true)
check("and as listed, since a new auction is there",
    resolved and (resolved.appeared or resolved.posted > 3) or false, true)

print("\nthe same count and no new auction is still not settled early")

ns.Posting.pending = {
    itemID = 4240, postedBefore = 3,
    idsBefore = Auctions:GetOwnedIDs(4240), verifying = true,
}
resolved = nil
Auctions:ReadOwned({})
check("an early read with nothing new waits", resolved, nil)

print("")
if failures > 0 then
    error(("%d new-listing check(s) failed"):format(failures))
end
print("all new-listing checks passed")
