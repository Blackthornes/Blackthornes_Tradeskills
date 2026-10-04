-- Verifying that a listing actually went up, without waiting to be told.
--
-- Forever does fire OWNED_AUCTIONS_UPDATED, but not when a listing needs
-- confirming. The addon used to wait for that announcement and, when it did not
-- come, told the player "could not tell whether that listing went up" after
-- every single post -- while the auction sat in their Auctions tab perfectly
-- fine.
--
-- Reading owned auctions works on this client, so the answer is read back
-- directly instead. The case that needs guarding is timing: the server's reply
-- lands some unpredictable moment after the query, so a read taken too early
-- shows the old count. Reporting that as a failed listing would be worse than
-- the bug being fixed -- "it did not go up" is a much stronger claim than "I
-- could not tell", and it would be wrong.

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
}

ns.db = {}
ns.Config = { GetRealmKey = function() return "TestRealm" end }
ns.Scanner = { isAuctionHouseOpen = true }
ns.Inventory = { GetOwnedCount = function() return 0 end }
ns.Queue = { GetAll = function() return {} end }
ns.Recipes = { GetAny = function() return nil end }
ns.AHQueue = { PRIORITY = { urgent = 10, normal = 50, scan = 90 } }

time = time or os.time

--------------------------------------------------------------------------------
-- A client that answers a query only after a delay of our choosing
--------------------------------------------------------------------------------

local clock = 0
local timers = {}

C_Timer = {
    After = function(delay, fn)
        timers[#timers + 1] = { at = clock + delay, fn = fn }
    end,
}

--- Run every timer due up to `target`, in the order they come due.
local function RunUntil(target)
    while true do
        local nextIndex, nextAt

        for i = 1, #timers do
            local timer = timers[i]
            if timer and timer.at <= target and (not nextAt or timer.at < nextAt) then
                nextIndex, nextAt = i, timer.at
            end
        end

        if not nextIndex then break end

        local timer = timers[nextIndex]
        timers[nextIndex] = false
        clock = timer.at
        timer.fn()
    end

    clock = target
end

-- What the client currently reports. Each entry is one listing.
local listed = {}

C_AuctionHouse = {
    GetNumOwnedAuctions = function() return #listed end,
    GetOwnedAuctionInfo = function(index)
        local entry = listed[index]
        if not entry then return nil end
        return { itemKey = { itemID = entry.itemID }, quantity = entry.quantity, status = entry.status or 0,
            timeLeftSeconds = entry.seconds, timeLeft = entry.band, unitPrice = entry.unit }
    end,
    QueryOwnedAuctions = function() end,
}

-- WhenAuctionReady stands in for the queue: the send happens straight away, so
-- the test measures the reads rather than the pacing, which test_throttle covers.
ns.Util.WhenAuctionReady = function(action) action() end

assert(loadfile(lfs_cwd .. "/Data/Auctions.lua"))("Blackthornes_TS", ns)

local Auctions = ns.Auctions

--------------------------------------------------------------------------------
-- A stand-in for Posting that records how a listing was settled
--------------------------------------------------------------------------------

local resolved
ns.Posting = {
    pending = nil,
    ResolvePending = function(self, posted)
        resolved[#resolved + 1] = posted
        self.pending = nil
    end,
}

local function StartPending(itemID, postedBefore)
    resolved = {}
    ns.Posting.pending = {
        itemID = itemID,
        postedBefore = postedBefore or 0,
        verifying = true,
    }
end

--------------------------------------------------------------------------------

local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-52s %-8s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

print("")
print("a reply that lands while we are still reading")

clock, timers, listed = 0, {}, {}
ns.db.postedAuctions = nil
StartPending(2447, 0)

Auctions:Refresh({ force = true })

-- Two reads go by before the server answers.
RunUntil(2.0)
check("nothing claimed before the reply landed", #resolved, 0)

listed[1] = { itemID = 2447, quantity = 3 }

RunUntil(3.0)
check("settled once the listing could be read", #resolved, 1)
check("settled as listed, not as failed", resolved[1], 3)

RunUntil(10.0)
check("and not settled a second time", #resolved, 1)

print("")
print("a listing that genuinely did not go up")

clock, timers, listed = 0, {}, {}
ns.db.postedAuctions = nil
StartPending(2447, 0)

Auctions:Refresh({ force = true })

RunUntil(4.0)
check("no failure claimed while reads remain", #resolved, 0)

RunUntil(6.0)
check("reported once every read had its chance", #resolved, 1)
check("reported as not listed, not as unknown", resolved[1], 0)

print("")
print("posting a second of something already listed")

clock, timers, listed = 0, {}, {}
ns.db.postedAuctions = nil
listed[1] = { itemID = 2447, quantity = 3 }

-- The count it has to beat is what was already there, not zero.
StartPending(2447, 3)

Auctions:Refresh({ force = true })

RunUntil(2.0)
check("the auction already there settles nothing", #resolved, 0)

listed[2] = { itemID = 2447, quantity = 3 }

RunUntil(3.0)
check("settled once the new one appeared", #resolved, 1)
check("counted both listings", resolved[1], 6)

print("")
print("a newer query while an older sequence is still running")

clock, timers, listed = 0, {}, {}
ns.db.postedAuctions = nil
StartPending(2447, 0)

Auctions:Refresh({ force = true })
RunUntil(1.0)

-- Something else asks again: the first sequence must stand down rather than
-- settle the listing against a reading its own query never waited for.
Auctions:Refresh({ force = true })

RunUntil(5.2)
check("the stale sequence did not report a failure", #resolved, 0)

listed[1] = { itemID = 2447, quantity = 3 }
RunUntil(7.0)
check("the live sequence settled it", #resolved, 1)
check("settled as listed", resolved[1], 3)

print("")
print("a client that does announce the answer")

clock, timers, listed = 0, {}, {}
ns.db.postedAuctions = nil
StartPending(2447, 0)

-- No reply yet, and the client says owned auctions changed. That is the server
-- having answered, so it settles the listing immediately -- including as a
-- failure, which is the one case where saying so straight away is right.
Auctions:OnOwnedAuctionsUpdated()
check("the announcement settled it at once", #resolved, 1)
check("and settled it as not listed", resolved[1], 0)

print("")
print("reading owned auctions")

clock, timers, listed = 0, {}, {}
ns.db.postedAuctions = nil
ns.Posting.pending = nil
resolved = {}

listed[1] = { itemID = 2447, quantity = 3 }
listed[2] = { itemID = 2589, quantity = 20 }
listed[3] = { itemID = 2447, quantity = 5 }

Auctions:ReadOwned({ final = true })

check("quantities of one item add up", Auctions:GetPostedCount(2447), 8)
check("a second item is kept apart", Auctions:GetPostedCount(2589), 20)
check("an item with none listed reads zero", Auctions:GetPostedCount(9999), 0)

print("")
print("listings on more than one character")

-- The game shows each character only its own auctions. The alt's reading
-- used to replace the main's, and Keep in stock forgot the main's listings.
ns.db.postedAuctions = nil
local who = "Main"
ns.Config.GetCharacterKey = function() return who end
listed = { { itemID = 2447, quantity = 8 } }
Auctions:ReadOwned({ final = true })

who = "Alt"
listed = { { itemID = 2447, quantity = 2 } }
Auctions:ReadOwned({ final = true })

check("both characters' listings count", Auctions:GetPostedCount(2447), 10)
check("this character's own count stays its own", Auctions:GetOwnPostedCount(2447), 2)

who = "Main"
listed = {}
Auctions:ReadOwned({ final = true })
check("a character that sold out drops out of the total", Auctions:GetPostedCount(2447), 2)
ns.Config.GetCharacterKey = nil

-- A listing that expired since the reading: the stack is back in the mail,
-- so it is no longer listed. It used to count in both places until the next
-- auction house visit.
ns.db.postedAuctions = nil
who = "Main"
ns.Config.GetCharacterKey = function() return who end
listed = { { itemID = 2447, quantity = 8 } }
Auctions:ReadOwned({ final = true })
local readAt = Auctions:GetTable().byCharacter.Main.updatedAt
ns.Mail = { GetLedger = function() return { entries = {
    { t = readAt - 100, kind = "expired", who = "Main", itemID = 2447, quantity = 5 },
    { t = readAt + 60, kind = "expired", who = "Main", itemID = 2447, quantity = 3 },
    { t = readAt + 60, kind = "expired", who = "Alt", itemID = 2447, quantity = 4 },
} } end }
check("a stack back in the mail is no longer listed", Auctions:GetPostedCount(2447), 5)
check("verifying a listing still reads the raw count", Auctions:GetOwnPostedCount(2447), 8)
ns.Mail = nil

-- The Sales tab's Still listed view reads each listing as it stood.
print("")
print("still listed")
ns.db.postedAuctions = nil
who = "Main"
listed = {
    { itemID = 2447, quantity = 8, unit = 25, seconds = 3600 },
    { itemID = 2449, quantity = 1, band = 1 },
    { itemID = 2450, quantity = 2, status = 1 },
}
Auctions:ReadOwned({ final = true })
local rows, characters = Auctions:GetListings()
check("one row per active listing", #rows, 2)
check("one character read", characters, 1)
local first = rows[1].itemID == 2447 and rows[1] or rows[2]
local second = rows[1].itemID == 2447 and rows[2] or rows[1]
check("its price each is kept", first.unit, 25)
check("it ends when the client said", first.ends - first.readAt, 3600)
check("and has not ended", first.ended, false)
check("a band gives the latest it can end", second.ends - second.readAt, 7200)
check("which is marked as rough", second.roughEnd, true)
Auctions:GetTable().byCharacter.Main.updatedAt = time() - 25 * 3600
rows = Auctions:GetListings()
check("a reading older than any auction has ended", rows[1].ended, true)

ns.db.postedAuctions = { TestRealm = { items = {}, byCharacter = { Old = { items = { [2447] = 3 }, updatedAt = time() } } } }
rows, characters = Auctions:GetListings()
check("a reading saved before listings were kept shows none", #rows, 0)
check("and is not counted as read", characters, 0)
ns.Config.GetCharacterKey = nil

print("")

if failures > 0 then
    print(("FAIL -- %d check(s) failed"):format(failures))
    os.exit(1)
end

print("PASS -- a listing is settled by what we can read, never by waiting to be told")
print("")
