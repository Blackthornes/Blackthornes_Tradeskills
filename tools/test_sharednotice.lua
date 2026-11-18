-- Chat Notice for shared prices (the owner said build it, 2026-11-18): one
-- chat line when prices come in from the guild or the realm.
--
-- What must hold:
--   1. Off by default: prices still come in, and nothing is said.
--   2. On: a guildmate's whole scan, sent in many messages, is one line,
--      said once they go quiet, naming them in full.
--   3. Realm prices from many players are one line that counts them and
--      never names them, at most once every ten minutes.
--   4. Nothing is said when nothing was taken.
--   5. Turned off while a batch waits: nothing is said.

local saved = {}
for _, name in ipairs({ "time", "GetTime", "UnitName", "C_ChatInfo", "C_Timer", "InCombatLockdown",
                        "IsInGuild", "SendAddonMessage", "GetChannelName", "JoinTemporaryChannel",
                        "JoinChannelByName", "LeaveChannelByName", "ChatFrame_AddMessageEventFilter",
                        "UnitFactionGroup" }) do
    saved[name] = _G[name]
end

local passed, failed = 0, 0
local function check(label, got, want)
    if got == want then
        passed = passed + 1
        print(("  ok    %-60s %s"):format(label, tostring(got)))
    else
        failed = failed + 1
        print(("  FAIL  %-60s got %s, want %s"):format(label, tostring(got), tostring(want)))
    end
end

local clock = 1790000000
local timers = {}
time = function() return clock end
GetTime = function() return 1000 end
C_Timer = {
    NewTicker = function() return { Cancel = function() end } end,
    After = function(delay, fn) timers[#timers + 1] = { at = clock + delay, fn = fn } end,
}
InCombatLockdown = function() return false end
IsInGuild = function() return true end
SendAddonMessage = nil
UnitFactionGroup = function() return "Alliance" end
UnitName = function() return "Bob" end
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function() return 0 end,
}
GetChannelName = function() return 0, nil end
JoinTemporaryChannel = function() end
JoinChannelByName = JoinTemporaryChannel
LeaveChannelByName = function() end
ChatFrame_AddMessageEventFilter = function() end

--- Move the clock on, running every timer that comes due on the way.
local function Wait(seconds)
    local stop = clock + seconds
    while true do
        table.sort(timers, function(a, b) return a.at < b.at end)
        local due = timers[1]
        if not due or due.at > stop then break end
        table.remove(timers, 1)
        clock = math.max(clock, due.at)
        due.fn()
    end
    clock = stop
end

local said = {}
local ns = {}
ns.VERSION = "1.0"
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Util = { Comma = function(n) return tostring(n) end, FormatAgeAgo = function() return "just now" end }
ns.NewModule = function(module) local m = {}; ns[module] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print = function(line) said[#said + 1] = line end
ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end
local settings = { linkNames = "", guildPrices = true, realmPrices = true }
local priceTable = {}
ns.db = { characters = {}, postedAuctions = {}, priceHistory = {} }
ns.Config = {
    Get = function(_, key) return settings[key] end,
    Set = function(_, key, value) settings[key] = value end,
    GetRealmKey = function() return "Realm-Alliance" end,
    GetCharacterKey = function() return "Player-1-Bob" end,
    GetPriceTable = function() return priceTable end,
    ReadSurname = function() return nil end,
}
ns.Recipes = { ForgetCharacter = function() return true end }
for _, file in ipairs({ "Core/Serialize.lua", "Core/Comm.lua", "Data/Prices.lua",
                        "Data/PriceHistory.lua", "Logic/AccountLink.lua", "Logic/GuildPrices.lua",
                        "Logic/RealmPrices.lua" }) do
    assert(loadfile(lfs_cwd .. "/" .. file))("Blackthornes_TS", ns)
end
local Comm, Guild, Realm = ns.Comm, ns.GuildPrices, ns.RealmPrices
timers = {}

local function Body(from, count)
    local parts = { Comm.ToBase36(clock), ":" }
    for id = from, from + count - 1 do
        parts[#parts + 1] = Comm.ToBase36(id) .. "," .. Comm.ToBase36(1000 + id) .. ";"
    end
    return table.concat(parts)
end
local function FromGuild(sender, from, count) Guild:OnPrices(sender, Body(from, count), "GUILD") end
local function FromRealm(sender, from, count)
    Realm:OnPrices(sender, Body(from, count), "CHANNEL", "BTSPricesA", "4. BTSPricesA")
end

--------------------------------------------------------------------------------
print("\noff by default")
check("Chat Notice starts off", settings.sharedChatNotice, nil)
FromGuild("Ana Smith-Realm", 100, 10)
FromRealm("Cal Jones-Realm", 500, 10)
Wait(3600)
check("prices still come in from the guild", Guild:Count() > 0, true)
check("nothing is said", #said, 0)

--------------------------------------------------------------------------------
print("\nturned on: a guildmate's scan is one line")
settings.sharedChatNotice = true
FromGuild("Ana Smith-Realm", 1000, 20)
Wait(10)
FromGuild("Ana Smith-Realm", 1020, 20)
Wait(10)
FromGuild("Ana Smith-Realm", 1030, 15)   -- 5 sent twice, counted once
Wait(20)
check("nothing said while the scan still comes", #said, 0)
Wait(15)
check("one line once they go quiet", #said, 1)
check("it names them in full and counts items once", said[1],
    "Got prices for 45 items from Ana Smith in your guild.")
Wait(600)
check("and only once", #said, 1)

--------------------------------------------------------------------------------
print("\ntwo guildmates at once")
said = {}
FromGuild("Ana Smith", 2000, 3)
FromGuild("Dee Brown", 3000, 4)
Wait(60)
check("one line each", #said, 2)

--------------------------------------------------------------------------------
print("\nrealm prices: many players, one line, no names")
said = {}
for i, name in ipairs({ "Cal Jones", "Eve Hart", "Fay Lin" }) do
    FromRealm(name .. "-Realm", 4000, 30)
    FromRealm(name .. "-Realm", 4030 + i, 1)
    Wait(3)
end
Wait(60)
check("one line", #said, 1)
check("it counts items and players", said[1], "Got prices for 33 items from 3 players on your realm.")
check("no name is in it", said[1] and (said[1]:find("Cal") or said[1]:find("Eve") or said[1]:find("Fay")), nil)

FromRealm("Gus Moon-Realm", 5000, 7)
Wait(60)
check("the next is held back", #said, 1)
Wait(600)
check("said after ten minutes", #said, 2)
check("one player reads right", said[2], "Got prices for 7 items from 1 player on your realm.")

--------------------------------------------------------------------------------
print("\nnothing taken, nothing said")
said = {}
Guild:OnPrices("Ana Smith", Comm.ToBase36(clock) .. ":" .. Comm.ToBase36(20000000) .. ",5;", "GUILD")
Guild:OnPrices("Bob", Body(6000, 5), "GUILD")   -- our own echo
Wait(120)
check("a refused price or our own echo says nothing", #said, 0)

--------------------------------------------------------------------------------
print("\nturned off while a batch waits")
FromGuild("Ana Smith", 7000, 5)
FromRealm("Hal Kerr", 7000, 5)
settings.sharedChatNotice = false
Wait(1200)
check("nothing is said", #said, 0)

for name, value in pairs(saved) do _G[name] = value end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then error(("%d chat notice check(s) failed"):format(failed)) end
