-- An empty realm name (Forever 1.60.1, 2026-11-20).
--
-- Forever's hotfix makes GetRealmName hand back "" for good. Prices, price
-- history, sales, the gold log and guild and realm prices are all filed
-- under the realm, so a blank one opened a new empty "UnknownRealm" bucket:
-- every price and sale looked gone. And "" read as a realm made every one
-- of your own listings look like a rival's, so you undercut yourself.
-- What must hold:
--   1. While the client still names the realm, nothing changes, and the
--      name is remembered in the character's own file.
--   2. With a blank realm, the key is the realm this character was on: its
--      own file, then its record, then the realm this account's characters
--      on the same server are on (a character from a linked account never
--      counts). A character on a server none of the others are on gets no
--      realm rather than another realm's.
--   3. Nothing saved is moved, renamed or deleted.
--   4. A new character's record takes the remembered realm, not "?".
--   5. Your own listings stay yours with a blank realm.

local failures = 0
local function Check(name, ok, detail)
    print(string.format("  %-62s %s", name, ok and "ok" or ("FAIL " .. tostring(detail))))
    if not ok then failures = failures + 1 end
end

local realmName = "CAMWOW US2 Realm 7 PvE"
local playerGUID = "Player-6933-A"

local function Stub()
    UnitName = function() return "Ana" end
    UnitGUID = function() return playerGUID end
    UnitClass = function() return "Mage", "MAGE" end
    UnitLevel = function() return 30 end
    UnitFactionGroup = function() return "Alliance" end
    GetRealmName = function() return realmName end
    time = function() return 1000 end
end

local function Load(db, charDb)
    local ns = {}
    ns.NewModule = function(name) local m = { moduleName = name } ns[name] = m return m end
    ns.RegisterCommand = function() end
    ns.RegisterEvent = function() end
    ns.Warn, ns.Print, ns.PrintRaw, ns.Debug = function() end, function() end, function() end, function() end
    ns.COLORS = {}
    ns.Util = {
        Count = function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end,
        CopyDeep = function(t) return t end,
    }
    ns.Cost = { InvalidateIndex = function() end }
    ns.Compat = { Get = function() return { tradeskill = {} } end }
    loadfile(lfs_cwd .. "/Core/Config.lua")("Blackthornes_TS", ns)
    loadfile(lfs_cwd .. "/Data/Recipes.lua")("Blackthornes_TS", ns)
    ns.db = db
    ns.charDb = charDb
    return ns
end

local function Copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = Copy(v) end
    return c
end

local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

Stub()

print("realm blank: today, with the realm named")
do
    realmName = "CAMWOW US2 Realm 7 PvE"
    local charDb = {}
    local ns = Load({ characters = {} }, charDb)
    Check("the key is the realm and side", ns.Config:GetRealmKey() == "CAMWOW US2 Realm 7 PvE-Alliance",
        ns.Config:GetRealmKey())
    Check("the realm is remembered in the character's file", charDb.realmName == "CAMWOW US2 Realm 7 PvE",
        charDb.realmName)
end

print("realm blank: the realm remembered in the character's file")
do
    realmName = ""
    local charDb = { realmName = "CAMWOW US2 Realm 7 PvE", guid = playerGUID }
    local db = { characters = {}, prices = { ["CAMWOW US2 Realm 7 PvE-Alliance"] = { [2589] = { market = 50 } } } }
    local before = Copy(db)
    local ns = Load(db, charDb)
    Check("the key is the old realm's", ns.Config:GetRealmKey() == "CAMWOW US2 Realm 7 PvE-Alliance",
        ns.Config:GetRealmKey())
    Check("old prices are found", (ns.Config:GetPriceTable()[2589] or {}).market == 50)
    Check("no UnknownRealm bucket is made", db.prices["UnknownRealm-Alliance"] == nil)
    Check("nothing saved changed", Same(before, db))
    Check("RealmName gives the old name", ns.Config:RealmName() == "CAMWOW US2 Realm 7 PvE", ns.Config:RealmName())
end

print("realm blank: the character's record")
do
    realmName = ""
    local db = { characters = { [playerGUID] = { name = "Ana", realm = "CAMWOW US2 Realm 3 PvE" } } }
    local ns = Load(db, { guid = playerGUID })
    Check("the key is the record's realm", ns.Config:GetRealmKey() == "CAMWOW US2 Realm 3 PvE-Alliance",
        ns.Config:GetRealmKey())
end

print("realm blank: a new character takes the account's realm")
do
    realmName = ""
    local db = { characters = {
        ["Player-6933-B"] = { name = "Bo", realm = "Forever PvE" },
        ["Player-6933-C"] = { name = "Cy", realm = "Forever PvE" },
        ["Player-6933-D"] = { name = "Di", realm = "Forever PvP" },
        ["Player-6929-E"] = { name = "Ed", realm = "Linked Realm", linkedFrom = "Ed" },
        ["Player-6929-F"] = { name = "Fi", realm = "Linked Realm", linkedFrom = "Ed" },
        ["Player-6929-G"] = { name = "Gu", realm = "Linked Realm", linkedFrom = "Ed" },
        ["Player-6933-H"] = { name = "Ho", realm = "?" },
    } }
    local ns = Load(db, {})
    Check("most of the account's characters' realm", ns.Config:GetRealmKey() == "Forever PvE-Alliance",
        ns.Config:GetRealmKey())
    local record = ns.Recipes:GetCharacterRecord(true)
    Check("the new record's realm is the remembered one", record and record.realm == "Forever PvE",
        record and record.realm)
end

print("realm blank: nothing to go on")
do
    realmName = ""
    local ns = Load({ characters = {} }, {})
    Check("still UnknownRealm, and not kept", ns.Config:GetRealmKey() == "UnknownRealm-Alliance"
        and ns.Config.realmKey == nil, ns.Config:GetRealmKey())
    Check("RealmName is nil", ns.Config:RealmName() == nil, ns.Config:RealmName())
end

print("realm blank: your own listings")
do
    realmName = ""
    local ns = {}
    ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
    ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
    ns.RegisterCommand = function() end
    ns.RegisterEvent = function() return true end
    ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
    ns.Util = { GetItemLabel = function(i) return "item" .. tostring(i) end, HasFunction = function() return false end }
    local surname = "Thorn"
    ns.Config = { Get = function() return nil end, GetRealmKey = function() return "x" end,
        ReadSurname = function() return surname end }
    ns.db = {}
    ns.AHQueue = { PRIORITY = { urgent = 10, normal = 50, scan = 90 } }
    GetTime = function() return 100 end
    Enum = Enum or { ItemCommodityStatus = { Commodity = 2 }, BagIndex = {} }
    C_Timer = C_Timer or { After = function() end, NewTimer = function() return { Cancel = function() end } end }
    assert(loadfile(lfs_cwd .. "/Data/Scanner.lua"))("Blackthornes_TS", ns)
    local Scanner = ns.Scanner
    Scanner.playerName, Scanner.playerFullName, Scanner.playerSurname, Scanner.playerRealm = nil, nil, nil, nil
    Check("whole name with a realm is still you", Scanner:IsOwnAuction(nil, "Ana Thorn-CAMWOWUS2Realm7PvE"))
    Check("a rival is still not you", not Scanner:IsOwnAuction(nil, "Ana Stone-CAMWOWUS2Realm7PvE"))
    surname = nil
    Scanner.playerName, Scanner.playerFullName, Scanner.playerSurname, Scanner.playerRealm = nil, nil, nil, nil
    Check("no last name: the first name is still you", Scanner:IsOwnAuction("Ana", "Ana-CAMWOWUS2Realm7PvE"))
end

-- 6. What 1.35.3 filed under "UnknownRealm-<side>" comes home, once, only
--    adding, and the stranded bucket is left as it was.
print("realm blank: the 1.35.3 bucket folds back into the realm")
do
    realmName = ""
    local R, U = "Forever PvE-Alliance", "UnknownRealm-Alliance"
    local db = {
        characters = {
            [playerGUID] = { name = "Ana", realm = "Forever PvE", faction = "Alliance" },
            ["Player-6933-B"] = { name = "Bo", realm = "Forever PvE", faction = "Alliance" },
            ["Player-6933-H"] = { name = "Ho", realm = "Forever PvP", faction = "Horde" },
            ["Player-6929-E"] = { name = "Ed", realm = "Linked", faction = "Alliance", linkedFrom = "Ed" },
        },
        prices = {
            [R] = { [2589] = { market = 50, seen = 10 } },
            [U] = { [2589] = { market = 70, seen = 20 }, [4306] = { market = 300, seen = 20 } },
        },
        priceHistory = {
            [R] = { [2589] = { 100, 50, 101, 52 } },
            [U] = { [2589] = { 101, 99, 105, 70 }, [4306] = { 105, 300 } },
        },
        mailLedger = {
            [R] = { entries = {
                { t = 500, who = playerGUID, kind = "sold", name = "Linen Cloth", itemID = 2589, net = 400 },
            }, seen = { a = true } },
            [U] = { entries = {
                { t = 900, who = playerGUID, kind = "sold", name = "Linen Cloth", itemID = 2589, net = 400 },
                { t = 950, who = playerGUID, kind = "sold", name = "Silk Cloth", itemID = 4306, net = 900 },
            }, seen = { a = false, b = true } },
        },
        goldLog = {
            [R] = { hours = { [36] = { auction = { i = 100, o = 0 } } }, days = { [20261120] = { auction = { i = 100, o = 5 } } } },
            [U] = { hours = { [40] = { auction = { i = 900, o = 0 } } }, days = { [20261120] = { auction = { i = 900, o = 1 }, vendor = { i = 7, o = 0 } } } },
        },
        postedAuctions = { [R] = { items = { [2589] = { 1 } } }, [U] = { items = { [4306] = { 2 } } } },
        lastFullScanByRealm = { [R] = 10, [U] = 20 },
    }
    local strandedBefore = {}
    for root, value in pairs(db) do
        if type(value) == "table" and value[U] then strandedBefore[root] = Copy(value[U]) end
    end
    local ns = Load(db, { guid = playerGUID })
    Check("the home is the one realm on that side", ns.Config:BlankRealmHome(U) == R, ns.Config:BlankRealmHome(U))
    ns.Config:FoldBlankRealm()

    Check("a price only the blank bucket had comes home", (db.prices[R][4306] or {}).market == 300)
    Check("a price the realm had is kept", db.prices[R][2589].market == 50)
    Check("the Prices tab's table now has it", (ns.Config:GetPriceTable()[4306] or {}).market == 300)
    Check("history: missing hours added in order", Same(db.priceHistory[R][2589], { 100, 50, 101, 52, 105, 70 }),
        table.concat(db.priceHistory[R][2589], ","))
    Check("history: a new item comes home", Same(db.priceHistory[R][4306], { 105, 300 }))
    local entries = db.mailLedger[R].entries
    Check("mail: the sale written twice is kept once, the new one added", #entries == 2, #entries)
    Check("mail: the new sale is the silk", entries[2] and entries[2].net == 900)
    Check("mail: seen marks only added", db.mailLedger[R].seen.a == true and db.mailLedger[R].seen.b == true)
    Check("gold: a new hour comes home", db.goldLog[R].hours[40].auction.i == 900)
    Check("gold: the same day adds up", db.goldLog[R].days[20261120].auction.i == 1000
        and db.goldLog[R].days[20261120].auction.o == 6)
    Check("gold: a new source that day comes home", db.goldLog[R].days[20261120].vendor.i == 7)
    Check("posted auctions fill in", db.postedAuctions[R].items[4306] ~= nil and db.postedAuctions[R].items[2589] ~= nil)
    Check("a plain stamp the realm had is kept", db.lastFullScanByRealm[R] == 10)
    local untouched = true
    for root, copy in pairs(strandedBefore) do
        if not Same(copy, db[root][U]) then untouched = false end
    end
    Check("the stranded bucket is left as it was", untouched)
    Check("the fold is written down", db.blankRealmFolded[U] and db.blankRealmFolded[U].into == R)

    local after = Copy(db)
    ns.Config:FoldBlankRealm()
    Check("a second login folds nothing again", Same(after, db))
end

print("realm blank: two realms on one side, nothing is guessed")
do
    realmName = ""
    local U = "UnknownRealm-Alliance"
    local db = {
        characters = {
            [playerGUID] = { name = "Ana", realm = "Forever PvE", faction = "Alliance" },
            ["Player-6933-B"] = { name = "Bo", realm = "Forever PvP", faction = "Alliance" },
        },
        prices = { ["Forever PvE-Alliance"] = {}, [U] = { [4306] = { market = 300 } } },
    }
    local before = Copy(db)
    local ns = Load(db, { guid = playerGUID })
    Check("no home can be told", ns.Config:BlankRealmHome(U) == nil)
    ns.Config:FoldBlankRealm()
    Check("nothing saved changed", Same(before, db))
end

print("realm blank: the fold runs as the addon loads")
do
    local src = io.open(lfs_cwd .. "/Core/Config.lua"):read("*a")
    local boot = src:match("function Config:Bootstrap%(%).-\nend\n")
    Check("Bootstrap folds the blank realm", boot and boot:find("FoldBlankRealm", 1, true) ~= nil)
end

-- 7. A character made on another realm after the realm went blank is not
--    given the account's realm (a player's PvP and RP characters all read
--    "Realm 3 PvE", 2026-11-25). The server in the character's key tells
--    realms apart: one account's characters on one realm share it.
print("realm blank: a new character on another server gets no other realm")
do
    realmName = ""
    playerGUID = "Player-7000-Z"
    local db = { characters = {
        ["Player-6933-B"] = { name = "Bo", realm = "CAMWOW US2 Realm 3 PvE" },
        ["Player-6933-C"] = { name = "Cy", realm = "CAMWOW US2 Realm 3 PvE" },
    } }
    local ns = Load(db, {})
    Check("no realm is guessed", ns.Config:RealmName() == nil, ns.Config:RealmName())
    Check("the key is not the other realm's", ns.Config:GetRealmKey() == "UnknownRealm-Alliance",
        ns.Config:GetRealmKey())
    local record = ns.Recipes:GetCharacterRecord(true)
    Check("the new record does not take the other realm", record and record.realm == "?", record and record.realm)
    playerGUID = "Player-6933-A"
end

print("realm blank: a new character takes its own server's realm")
do
    realmName = ""
    playerGUID = "Player-7000-Z"
    local db = { characters = {
        ["Player-6933-B"] = { name = "Bo", realm = "CAMWOW US2 Realm 3 PvE" },
        ["Player-6933-C"] = { name = "Cy", realm = "CAMWOW US2 Realm 3 PvE" },
        ["Player-7000-D"] = { name = "Di", realm = "CAMWOW US2 Realm 5 PvP" },
    } }
    local ns = Load(db, {})
    Check("the realm of a character on the same server", ns.Config:RealmName() == "CAMWOW US2 Realm 5 PvP",
        ns.Config:RealmName())
    playerGUID = "Player-6933-A"
end

print("realm blank: realms guessed from another server are put right")
do
    realmName = ""
    local P = "CAMWOW US2 Realm 3 PvE"
    local db = { characters = {
        ["Player-6933-A"] = { name = "Ana", realm = P },
        ["Player-6933-B"] = { name = "Bo", realm = P },
        ["Player-6933-C"] = { name = "Cy", realm = P },
        ["Player-7000-D"] = { name = "Di", realm = P },
        ["Player-7000-E"] = { name = "Ed", realm = "CAMWOW US2 Realm 5 PvP" },
        ["Player-7100-F"] = { name = "Fi", realm = P },
        ["Player-6929-G"] = { name = "Gu", realm = P, linkedFrom = "Gu" },
    } }
    playerGUID = "Player-7100-F"
    local ns = Load(db, { guid = playerGUID })
    Check("playing one: the guessed realm is not used", ns.Config:RealmName() == nil, ns.Config:RealmName())
    Check("two guesses are put right", ns.Config:MendGuessedRealms() == 2)
    local c = db.characters
    Check("one on a server with a realm takes it", c["Player-7000-D"].realm == "CAMWOW US2 Realm 5 PvP",
        c["Player-7000-D"].realm)
    Check("one on a server with none reads no realm", c["Player-7100-F"].realm == "?", c["Player-7100-F"].realm)
    Check("the guess is kept beside it", c["Player-7100-F"].realmGuessed == P)
    Check("the realm's own characters keep it", c["Player-6933-A"].realm == P and c["Player-6933-C"].realm == P
        and c["Player-6933-A"].realmGuessed == nil)
    Check("a linked account's character is left alone", c["Player-6929-G"].realm == P
        and c["Player-6929-G"].realmGuessed == nil)
    local after = Copy(db)
    Check("a second run changes nothing", ns.Config:MendGuessedRealms() == 0 and Same(after, db))
    playerGUID = "Player-6933-A"
end

print("realm blank: one each, nothing is changed")
do
    realmName = ""
    local db = { characters = {
        ["Player-6933-A"] = { name = "Ana", realm = "Forever PvE" },
        ["Player-7000-B"] = { name = "Bo", realm = "Forever PvE" },
    } }
    local before = Copy(db)
    local ns = Load(db, { guid = "Player-6933-A" })
    Check("a tie cannot be told", ns.Config:MendGuessedRealms() == 0 and Same(before, db))
end

print("realm blank: a stranded bucket a new realm's character may own stays put")
do
    realmName = ""
    local U = "UnknownRealm-Alliance"
    local db = {
        characters = {
            ["Player-6933-A"] = { name = "Ana", realm = "Forever PvE", faction = "Alliance" },
            ["Player-7000-B"] = { name = "Bo", realm = "?", faction = "Alliance" },
        },
        prices = { ["Forever PvE-Alliance"] = {}, [U] = { [4306] = { market = 300 } } },
    }
    local before = Copy(db)
    local ns = Load(db, { guid = "Player-6933-A" })
    Check("no home can be told", ns.Config:BlankRealmHome(U) == nil, ns.Config:BlankRealmHome(U))
    ns.Config:FoldBlankRealm()
    Check("nothing saved changed", Same(before, db))
end

print("realm blank: guessed realms are put right as the addon loads")
do
    local src = io.open(lfs_cwd .. "/Core/Config.lua"):read("*a")
    local boot = src:match("function Config:Bootstrap%(%).-\nend\n")
    Check("Bootstrap mends guessed realms", boot and boot:find("MendGuessedRealms", 1, true) ~= nil)
end

realmName = "Forever PvE"
if failures > 0 then error(failures .. " realm blank check(s) failed") end
print("all checks passed")
