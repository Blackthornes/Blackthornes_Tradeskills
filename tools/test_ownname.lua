-- Your own listings in a full scan, told apart by the whole name.
--
-- Forever lets any number of characters share a first name. Matching the
-- scan's seller by first name read a rival called "Bob Stone" as the
-- player "Bob Ash", so the rival's listing was never undercut. With a
-- last name known, only the whole name is the player's.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.Util = {
    GetItemLabel = function(i) return "item" .. tostring(i) end,
    HasFunction = function() return false end,
}

local surname = "Ash"
ns.Config = {
    Get = function() return nil end,
    GetRealmKey = function() return "Test Realm" end,
    ReadSurname = function() return surname end,
}
ns.db = {}
ns.AHQueue = { PRIORITY = { urgent = 10, normal = 50, scan = 90 } }

GetTime = function() return 100 end
Enum = { ItemCommodityStatus = { Commodity = 2 }, BagIndex = {} }
UnitName = function() return "Bob" end
GetRealmName = function() return "Test Realm" end
C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }

assert(loadfile(lfs_cwd .. "/Data/Scanner.lua"))("Blackthornes_TS", ns)
local Scanner = ns.Scanner

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function fresh()
    Scanner.playerName, Scanner.playerFullName = nil, nil
    Scanner.playerSurname, Scanner.playerRealm = nil, nil
end

print("\na character with a last name")
fresh()
check("your whole name is you", Scanner:IsOwnAuction("Bob Ash", nil))
check("your whole name with the realm is you", Scanner:IsOwnAuction(nil, "Bob Ash-TestRealm"))
check("a rival sharing your first name is not you", not Scanner:IsOwnAuction("Bob Stone", "Bob Stone-TestRealm"))
-- A row with only a first name cannot be told apart. It is read as you, so
-- your own listings are never undercut if Forever writes sellers that way.
check("a bare first name is still taken as you", Scanner:IsOwnAuction("Bob", "Bob-TestRealm"))
check("a bare other name is not you", not Scanner:IsOwnAuction("Grimble", "Grimble-TestRealm"))
check("the same name on another realm is not you", not Scanner:IsOwnAuction(nil, "Bob Ash-OtherRealm"))

print("\na character with no last name")
surname = nil
fresh()
check("the first name still matches", Scanner:IsOwnAuction("Bob", nil))
check("so does name and realm", Scanner:IsOwnAuction(nil, "Bob-TestRealm"))
check("someone else is not you", not Scanner:IsOwnAuction("Grimble", "Grimble-TestRealm"))

print(("\n%d check(s) passed\n"):format(checks))
