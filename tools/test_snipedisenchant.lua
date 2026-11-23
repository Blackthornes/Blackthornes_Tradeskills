-- Snipe, Watch: To Disenchant says "Nothing to snipe yet. Scan the auction
-- house first." even after a scan (a player's report, 1.40.0).
--
-- Two ways it happened:
--   * Disenchant reads no new item while the auction house is open, and
--     Snipe only runs there. Gear the scan found but nobody had read with
--     the auction house shut had no saved facts, so none of it was watched
--     and the pool was empty.
--   * A character who can't disenchant and has no disenchanter got the same
--     words, though no scan could help.
-- What must hold:
--   1. Gear the client already holds is read for Snipe with the auction
--      house open, and watched.
--   2. Gear the client does not hold is not asked for, and not watched.
--   3. Only a few items are read a frame.
--   4. With nobody to disenchant, Snipe says that, not "scan".
--   5. A scan with no gear worth breaking says so, not "scan".

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Print, ns.Debug, ns.Warn = function() end, function() end, function() end
local said = {}
ns.Notice = { Show = function(_, text) said[#said + 1] = text end }
ns.RegisterEvent = function() return true end
ns.RegisterCommand = function() end
local settings = { snipeCap = 100000, snipeWatch = "disenchant" }
ns.Config = { Get = function(_, k) return settings[k] end }
ns.db = {}

local saved = { C_Item = C_Item, C_Timer = C_Timer, GetTime = GetTime, frame = AuctionHouseFrame,
                C_AuctionHouse = C_AuctionHouse, IsPlayerSpell = IsPlayerSpell }
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers()
    for _ = 1, 50 do
        if #timers == 0 then return end
        local due = timers
        timers = {}
        for _, fn in ipairs(due) do fn() end
    end
end
GetTime = function() return 100 end
AuctionHouseFrame = nil

local STRANGE_DUST = 10940
-- itemID -> name, quality, item level, equip slot, class; `held` says the
-- client has the item's data already.
local items = {
    [2001] = { "Green Vest", 2, 22, "INVTYPE_CHEST", 4, held = true },
    [2002] = { "Green Legs", 2, 22, "INVTYPE_LEGS", 4, held = false },
    [2003] = { "Linen Cloth", 1, 5, "", 7, held = true },
}
for id = 3001, 3040 do items[id] = { "Green Belt " .. id, 2, 22, "INVTYPE_WAIST", 4, held = true } end
local asked, read = {}, 0
C_Item = {
    GetItemInfo = function(id)
        local item = items[id]
        if not (item and item.held) then return nil end
        read = read + 1
        return item[1], nil, item[2], item[3], nil, nil, nil, nil, item[4], nil, 100, item[5]
    end,
    GetItemInfoInstant = function(id)
        local item = items[id]
        if not item then return nil end
        return id, nil, nil, item[4], nil, item[5]
    end,
    GetItemQualityByID = function(id)
        local item = items[id]
        return item and item.held and item[2] or nil
    end,
    IsItemDataCachedByID = function(id) return items[id] ~= nil and items[id].held == true end,
    RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end,
}
ns.Util = {
    HasFunction = function(path)
        local at = _G
        for part in path:gmatch("[^.]+") do
            at = type(at) == "table" and at[part] or nil
        end
        return type(at) == "function"
    end,
    GetTooltipSellPrice = function() return nil end,
}

-- The scan's prices: every item above was seen, and dust has a price.
local table_ = { [STRANGE_DUST] = true }
for id in pairs(items) do table_[id] = true end
ns.Prices = {
    GetTable = function() return table_ end,
    GetValue = function(_, id) return id == STRANGE_DUST and 500 or 100 end,
    Get = function() return nil end,
    IsCredible = function() return true end,
}
ns.Scanner = { isAuctionHouseOpen = true }
ns.AHQueue = { PRIORITY = { urgent = 10, scan = 90 }, BUDGET_MAX = 8,
    RecentSendCount = function() return 0 end,
    Request = function() return true end, Cancel = function() return true end }
C_AuctionHouse = { MakeItemKey = function(id) return { itemID = id } end }

assert(loadfile(lfs_cwd .. "/Logic/Disenchant.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Snipe.lua"))("Blackthornes_TS", ns)
local Snipe = ns.Snipe
Snipe:Init()

-- The character can disenchant.
ns.Disenchanter = { Knows = function() return true end }

-- 1 and 2. A scan was run; Start, with the auction house open.
local stopped
local realStop = Snipe.Stop
Snipe.Stop = function(self, reason, clear) stopped = reason or stopped; return realStop(self, reason, clear) end
local watched = {}
local realWorth = Snipe.WorthOf
Snipe.WorthOf = function(self, id, mode)
    local worth = realWorth(self, id, mode)
    if worth then watched[id] = worth end
    return worth
end
Snipe:Start()
local firstFrame = read
RunTimers()
assert(Snipe:IsRunning(), "Snipe runs: " .. tostring(stopped))
assert(watched[2001], "gear the client holds is watched")
assert(not watched[2002], "gear the client does not hold is not")
assert(not watched[2003], "cloth is never watched")
assert(#asked == 0, "nothing is asked of the client with the auction house open")
-- 3. A few a frame, never the whole scan at once.
assert(firstFrame <= Snipe.READS_A_FRAME, "read " .. firstFrame .. " in the first frame")
assert(watched[3040], "and every one in the end")
Snipe:Stop()

-- 5. A scan with no gear worth breaking.
for id in pairs(items) do if id ~= 2003 then table_[id] = nil end end
stopped = nil
Snipe:Start()
RunTimers()
assert(not Snipe:IsRunning())
assert(stopped == "No gear worth disenchanting in your last scan.", tostring(stopped))

-- No scan at all still says to scan.
local kept = table_
table_ = {}
stopped = nil
Snipe:Start()
RunTimers()
assert(stopped == "Nothing to snipe yet. Scan the auction house first.", tostring(stopped))
table_ = kept

-- 4. Nobody to disenchant.
ns.Disenchanter = { Knows = function() return false end }
ns.QueueMail = { GetDisenchanter = function() return nil end }
stopped = nil
Snipe:Start()
RunTimers()
assert(not Snipe:IsRunning())
assert(stopped == "You need an enchanter for this. Learn Enchanting, or name yours in Settings.", tostring(stopped))

C_Item, C_Timer, GetTime, AuctionHouseFrame = saved.C_Item, saved.C_Timer, saved.GetTime, saved.frame
C_AuctionHouse, IsPlayerSpell = saved.C_AuctionHouse, saved.IsPlayerSpell
print("test_snipedisenchant: ok")
