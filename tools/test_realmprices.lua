-- Realm prices (the owner said build it, 2026-10-20): auction prices swapped
-- with players on your realm over a hidden chat channel.
--
-- What must hold:
--   1. Off by default: nothing joins, nothing goes out, nothing is taken.
--   2. On: the channel is joined, and its join and leave lines are hidden.
--   3. A scan goes out one message at a time, only on our channel.
--   4. One player's price is used (the owner, 2026-11-18); with several,
--      the middle is taken.
--   5. Names are never kept, only a hash of them.
--   6. A price under 5% or over 10 times the one you know (your own, even
--      old, else your guild's) is refused; your own fresh scan wins, and so
--      does a guild price.
--   7. Not shared again within the hour, or when 3 others covered the scan.
--   8. Whispers, the guild and other channels are not listened to.
--   9. Old prices are pruned.
--  10. When the channel refuses a send, the line is hidden, sending stops
--      a while (for good after three), and prices still come in.
--  11. The game's own channels keep /1, /2 and /3: ours waits for them at
--      login, never joins in a dungeon, and moves behind them when it got
--      in first (a player's report, 2026-11-21).

local saved = {}
for _, name in ipairs({ "time", "GetTime", "UnitName", "C_ChatInfo", "C_Timer", "InCombatLockdown",
                        "IsInGuild", "SendAddonMessage", "ERR_CHAT_PLAYER_NOT_FOUND_S", "GetChannelName",
                        "JoinTemporaryChannel", "JoinChannelByName", "LeaveChannelByName",
                        "ChatFrame_AddMessageEventFilter", "UnitFactionGroup", "GetChannelList",
                        "EnumerateServerChannels", "IsInInstance" }) do
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

local clock, uptime = 1790000000, 1000
time = function() return clock end
GetTime = function() return uptime end
C_Timer = {
    NewTicker = function() return { Cancel = function() end } end,
    After = function() end,
}
local fighting = false
InCombatLockdown = function() return fighting end
IsInGuild = function() return true end
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
SendAddonMessage = nil
UnitFactionGroup = function() return "Alliance" end

--------------------------------------------------------------------------------
-- Clients and the channel
--------------------------------------------------------------------------------

local network = {}       -- messages on their way: { from, text, channel, target }
local current            -- the client whose code is running
local filters = 0

C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, text, channel, target)
        assert(#text <= 255, "a message over 255 bytes went out")
        network[#network + 1] = { from = current.name, text = text, channel = channel, target = target }
        return 0
    end,
}
UnitName = function() return current.name end
GetChannelName = function(name)
    local id = current.channels[tostring(name):lower()]
    if id then return id, name end
    return 0, nil
end
JoinTemporaryChannel = function(name) current.channels[name:lower()] = 4 end
JoinChannelByName = JoinTemporaryChannel
LeaveChannelByName = function(name) current.channels[name:lower()] = nil end
ChatFrame_AddMessageEventFilter = function() filters = filters + 1 end

local function NewClient(name, realmKey)
    local ns = {}
    ns.VERSION = "1.0"
    ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
    ns.Util = {
        Comma = function(n) return tostring(n) end,
        FormatAgeAgo = function() return "just now" end,
    }
    ns.NewModule = function(module) local m = {}; ns[module] = m; return m end
    ns.RegisterCommand = function() end
    ns.RegisterEvent = function() end
    ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

    local settings = { linkNames = "", guildPrices = false }
    local priceTable = {}
    ns.db = { characters = {}, postedAuctions = {}, priceHistory = {} }
    ns.Config = {
        Get = function(_, key) return settings[key] end,
        Set = function(_, key, value) settings[key] = value end,
        GetRealmKey = function() return realmKey end,
        GetCharacterKey = function() return "Player-1-" .. name end,
        GetPriceTable = function() return priceTable end,
        ReadSurname = function() return nil end,
    }
    ns.Recipes = { ForgetCharacter = function() return true end }

    local client = { name = name, ns = ns, settings = settings, channels = {} }
    current = client
    for _, file in ipairs({ "Core/Serialize.lua", "Core/Comm.lua", "Data/Prices.lua",
                            "Data/PriceHistory.lua", "Logic/AccountLink.lua", "Logic/GuildPrices.lua",
                            "Logic/RealmPrices.lua" }) do
        assert(loadfile(lfs_cwd .. "/" .. file))("Blackthornes_TS", ns)
    end

    ns.Comm:OnEnable()
    ns.AccountLink:OnEnable()
    ns.GuildPrices:OnEnable()
    ns.RealmPrices:OnEnable()
    return client
end

local clients = {}
local sentToChannel = 0

--- Drip, send and deliver until everything has gone. A channel message
--- reaches everyone in the channel, the sender too, as the probe saw.
local function Run(rounds)
    for _ = 1, rounds or 600 do
        uptime = uptime + 3
        local busy = false
        for _, client in ipairs(clients) do
            current = client
            client.ns.RealmPrices:Drip()
            client.ns.Comm:Pump()
            if client.ns.Comm:Pending() > 0 or (client.ns.RealmPrices.outbox and #client.ns.RealmPrices.outbox > 0) then
                busy = true
            end
        end
        local batch = network
        network = {}
        for _, message in ipairs(batch) do
            if message.channel == "CHANNEL" then sentToChannel = sentToChannel + 1 end
            for _, client in ipairs(clients) do
                local shown
                for channelName, id in pairs(client.channels) do
                    if message.channel == "CHANNEL" and tostring(id) == message.target then shown = channelName end
                end
                if shown then
                    current = client
                    client.ns.Comm:CHAT_MSG_ADDON("CHAT_MSG_ADDON", "BTSshare", message.text, "CHANNEL",
                        message.from .. "-Realm", "4. " .. shown, 0, 4, shown)
                end
            end
        end
        if not busy and #batch == 0 then return end
    end
end

local function Scan(client, prices, at)
    current = client
    local table = client.ns.Prices:GetTable()
    for itemID, price in pairs(prices) do
        table[itemID] = { market = price, min = price - 10, rivalMin = price - 10, seen = at, scans = 1, history = {} }
    end
    client.ns.db.lastFullScanByRealm = { ["Forever-Alliance"] = at }
end

--------------------------------------------------------------------------------
print("\non by default, off when unticked")
--------------------------------------------------------------------------------

local ana = NewClient("Ana", "Forever-Alliance")
local bob = NewClient("Bob", "Forever-Alliance")
local carl = NewClient("Carl", "Forever-Alliance")
local dora = NewClient("Dora", "Forever-Alliance")
clients = { ana, bob, carl, dora }

check("the setting starts unset", ana.settings.realmPrices, nil)
check("unset reads as on", ana.ns.RealmPrices:IsOn(), true)
for _, client in ipairs(clients) do client.settings.realmPrices = false end
check("unticked reads as off", ana.ns.RealmPrices:IsOn(), false)
current = ana
check("off: joining does nothing", ana.ns.RealmPrices:Join(), false)
check("off: no channel joined", next(ana.channels), nil)
Scan(ana, { [2589] = 1000 }, clock - 60)
check("off: nothing is shared", select(2, ana.ns.RealmPrices:Share()), "off")
check("off: the status says so", ana.ns.RealmPrices:Describe(), "Realm prices are off.")
Run()
check("off: nothing went out", sentToChannel, 0)

--------------------------------------------------------------------------------
print("\nturned on")
--------------------------------------------------------------------------------

for _, client in ipairs(clients) do
    current = client
    client.ns.RealmPrices:SetOn(true)
end
check("the setting is saved", ana.settings.realmPrices, true)
check("the channel is named for the side", ana.ns.RealmPrices:ChannelName(), "BTSPricesA")
check("the channel is joined", ana.channels["btspricesa"], 4)
check("its join lines are hidden", filters > 0, true)
check("our notice is filtered", ana.ns.RealmPrices.FilterNotice(nil, "CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED",
    "", "", "4. BTSPricesA", "", 0, 4, "", "BTSPricesA"), true)
check("trade chat's is not", ana.ns.RealmPrices.FilterNotice(nil, "CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED",
    "", "", "2. Trade", "", 0, 2, "", "Trade"), false)
check("nothing heard yet", ana.ns.RealmPrices:Describe(),
    "Listening for prices from your realm. They fill in prices you don't have yet.")

--------------------------------------------------------------------------------
print("\nleft by hand, joined again")
--------------------------------------------------------------------------------

do
    current = ana
    local Realm = ana.ns.RealmPrices
    local later = {}
    local savedAfter = C_Timer.After
    C_Timer.After = function(_, fn) later[#later + 1] = fn end
    ana.channels["btspricesa"] = nil
    check("out of it, the status says so", Realm:Describe(),
        "You're not in the price channel right now. Tradeskills tries again every minute.")
    check("another channel's leave is ignored",
        Realm:OnNotice("YOU_LEFT", "2. Trade", "Trade"), false)
    check("our leave is heard", Realm:OnNotice("YOU_LEFT", "4. BTSPricesA", "BTSPricesA"), true)
    check("a join waits a moment", #later, 1)
    later[1]()
    check("then the channel is joined again", ana.channels["btspricesa"], 4)
    check("in it, a join has nothing to do", Realm:Join(), true)

    -- The temporary join does not take: the next try uses the other way in.
    local savedTemp = JoinTemporaryChannel
    local byName = 0
    JoinTemporaryChannel = function() end
    JoinChannelByName = function(name) byName = byName + 1; current.channels[name:lower()] = 4 end
    ana.channels["btspricesa"] = nil
    Realm:Join()
    check("the first try does not land", ana.channels["btspricesa"], nil)
    Realm:Join()
    check("the next try joins by name", byName, 1)
    check("and it is in again", ana.channels["btspricesa"], 4)
    JoinTemporaryChannel, JoinChannelByName = savedTemp, savedTemp

    ana.settings.realmPrices = false
    ana.channels["btspricesa"] = nil
    check("turned off, a leave is left alone", Realm:OnNotice("YOU_LEFT", "4. BTSPricesA", "BTSPricesA"), false)
    ana.settings.realmPrices = true
    Realm:Join()
    C_Timer.After = savedAfter
end

--------------------------------------------------------------------------------
print("\nthe game's channels keep their numbers")
--------------------------------------------------------------------------------

do
    current = ana
    local Realm = ana.ns.RealmPrices
    local savedFns = { GetChannelName = GetChannelName, JoinTemporaryChannel = JoinTemporaryChannel,
        JoinChannelByName = JoinChannelByName, LeaveChannelByName = LeaveChannelByName,
        After = C_Timer.After, Swap = C_ChatInfo.SwapChatChannelsByChannelIndex }
    -- The client's channel slots: a join takes the lowest free number.
    local slots = {}
    local function Number(name)
        for id, joined in pairs(slots) do
            if joined:lower() == tostring(name):lower() then return id end
        end
        return 0
    end
    local function JoinSlot(name)
        if Number(name) > 0 then return end
        local id = 1
        while slots[id] do id = id + 1 end
        slots[id] = name
    end
    GetChannelName = function(name) local id = Number(name) return id, id > 0 and name or nil end
    JoinTemporaryChannel = JoinSlot
    JoinChannelByName = JoinSlot
    LeaveChannelByName = function(name) local id = Number(name) if id > 0 then slots[id] = nil end end
    GetChannelList = function()
        local out = {}
        for id = 1, 10 do
            if slots[id] then out[#out + 1] = id; out[#out + 1] = slots[id]; out[#out + 1] = false end
        end
        return (table.unpack or unpack)(out)
    end
    EnumerateServerChannels = function() return "General", "Trade", "LocalDefense", "LookingForGroup" end
    local inside = false
    IsInInstance = function() return inside, inside and "party" or "none" end
    local later = {}
    C_Timer.After = function(_, fn) later[#later + 1] = fn end
    local function Login()
        for id in pairs(slots) do slots[id] = nil end
        later = {}
        Realm.stepAside, Realm.waitingForGame, Realm.triedTemporary = nil, nil, nil
        Realm.loginAt = uptime
    end
    local function GameJoins()
        JoinSlot("General - Elwynn Forest")
        JoinSlot("Trade - City")
        JoinSlot("LocalDefense - Elwynn Forest")
        Realm:OnNotice("YOU_JOINED", "1. General - Elwynn Forest", "General - Elwynn Forest")
    end

    -- Logging in: the timer fires before General, Trade and LocalDefense are in.
    Login()
    Realm:Join()
    check("before the game's channels, ours waits", Number("BTSPricesA"), 0)
    GameJoins()
    check("General keeps /1", slots[1], "General - Elwynn Forest")
    check("a game channel coming in starts a short wait", #later, 1)
    later[1]()
    check("then ours joins behind them", Number("BTSPricesA"), 4)

    -- In a dungeon General is left; ours never takes its number.
    Login()
    inside = true
    Realm:Join()
    check("in a dungeon ours waits", Number("BTSPricesA"), 0)
    inside = false
    GameJoins()
    Realm:Join()
    check("out again, it joins behind them", Number("BTSPricesA"), 4)

    -- Every game channel left by hand: ours joins after a while anyway.
    Login()
    Realm:Join()
    check("nothing in yet, ours waits", Number("BTSPricesA"), 0)
    uptime = uptime + Realm.GAME_CHANNELS_WAIT
    Realm:Join()
    check("after the wait it joins", Number("BTSPricesA"), 1)
    uptime = uptime - Realm.GAME_CHANNELS_WAIT

    -- A login from before this fix (or a remembered channel) left ours on /1.
    Login()
    slots[1] = "BTSPricesA"
    slots[2] = "General - Elwynn Forest"
    slots[3] = "Trade - City"
    slots[5] = "MyFriends"
    C_ChatInfo.SwapChatChannelsByChannelIndex = function(a, b) slots[a], slots[b] = slots[b], slots[a] end
    for _ = 1, 5 do Realm:Join() end
    check("General moves back to /1", slots[1], "General - Elwynn Forest")
    check("Trade moves back to /2", slots[2], "Trade - City")
    check("ours moves behind them", Number("BTSPricesA"), 3)
    check("a player's own channel behind it keeps its number", slots[5], "MyFriends")
    check("still in, sharing goes on", Realm:InChannel(), true)

    -- No way to move it: ours steps out for this session and stays out.
    Login()
    slots[1] = "BTSPricesA"
    slots[2] = "General - Elwynn Forest"
    C_ChatInfo.SwapChatChannelsByChannelIndex = nil
    Realm:Join()
    check("with no way to move it, ours steps out", Number("BTSPricesA"), 0)
    check("its leave does not join again", Realm:OnNotice("YOU_LEFT", "1. BTSPricesA", "BTSPricesA"), true)
    Realm:Join()
    check("and it stays out this session", Number("BTSPricesA"), 0)
    check("General keeps its number", slots[2], "General - Elwynn Forest")

    Login()
    GetChannelName, JoinTemporaryChannel = savedFns.GetChannelName, savedFns.JoinTemporaryChannel
    JoinChannelByName, LeaveChannelByName = savedFns.JoinChannelByName, savedFns.LeaveChannelByName
    C_Timer.After, C_ChatInfo.SwapChatChannelsByChannelIndex = savedFns.After, savedFns.Swap
    GetChannelList, EnumerateServerChannels, IsInInstance = nil, nil, nil
    Realm:Join()
end

--------------------------------------------------------------------------------
print("\nsharing a scan")
--------------------------------------------------------------------------------

Scan(ana, { [2589] = 1000, [2592] = 500 }, clock - 60)
Scan(carl, { [2589] = 1100, [2592] = 520 }, clock - 60)
Scan(dora, { [2589] = 900000 }, clock - 60)

current = ana
check("Ana shares her scan", (ana.ns.RealmPrices:Share()), true)
check("it waits in her outbox", #ana.ns.RealmPrices.outbox, 2)
current = ana
ana.ns.RealmPrices:Drip()
check("one message goes at a time", #ana.ns.RealmPrices.outbox, 1)
check("and only once the last has gone", ana.ns.Comm:Pending() <= 1, true)
fighting = true
ana.ns.Comm:Pump()
local waiting = #ana.ns.RealmPrices.outbox
ana.ns.RealmPrices:Drip()
check("nothing goes in a fight", #ana.ns.RealmPrices.outbox, waiting)
fighting = false
Run()
check("it went to the channel", sentToChannel >= 2, true)
check("every message was on the channel", (function()
    for _, client in ipairs(clients) do
        if client.ns.Comm:Pending() > 0 then return false end
    end
    return true
end)(), true)

current = bob
local Realm = bob.ns.RealmPrices
check("one player's price is used", (Realm:GetValue(2589)), 1000)
check("Bob heard Ana's announcement", Realm:Covering(clock - 60), 1)

current = carl
carl.ns.RealmPrices:Share()
current = dora
dora.ns.RealmPrices:Share()
Run()

current = bob
check("three players: the middle is used", (Realm:GetValue(2589)), 1100)
check("the cheapest listing comes too", (Realm:GetValue(2589, "lowest")), 1090)
check("two players: the middle of the two", (Realm:GetValue(2592)), 510)
check("rival is never answered", Realm:GetValue(2589, "rival"), nil)
check("Bob has no scan: GetValue uses the realm's", bob.ns.Prices:GetValue(2589), 1100)
-- Ana keeps Carl's price only: not her own echo, and Dora's is 900 times hers.
check("Ana does not keep her own echo", #ana.ns.db.realmPrices["Forever-Alliance"][2589] / 4, 1)
check("the status counts prices and players", Realm:Describe(), "2 realm prices kept, from 3 players.")

do
    -- Names are never kept: no string in the save holds one.
    local found
    local function Look(value)
        if type(value) == "string" then
            local lower = value:lower()
            for _, name in ipairs({ "ana", "carl", "dora", "realm" }) do
                if lower:find(name, 1, true) then found = value end
            end
        elseif type(value) == "table" then
            for key, inner in pairs(value) do Look(key) Look(inner) end
        end
    end
    Look(bob.ns.db.realmPrices["Forever-Alliance"])
    check("no names are kept", found, nil)
end

--------------------------------------------------------------------------------
print("\nwhen not to share")
--------------------------------------------------------------------------------

current = ana
check("not sent again within the hour", select(2, ana.ns.RealmPrices:Share()), "already shared")
Scan(bob, { [2589] = 1050 }, clock - 30)
current = bob
check("three others covered Bob's scan", select(2, Realm:Share()), "others shared one")
Realm.heard = nil
current = bob
bob.channels = {}
check("not in the channel: wait", select(2, Realm:Share()), "not in the channel")
bob.channels = { btspricesa = 4 }
Scan(bob, { [2589] = 1050 }, clock - 7200)
check("an old scan is not shared", select(2, Realm:Share()), "no recent scan")

--------------------------------------------------------------------------------
print("\nwho wins")
--------------------------------------------------------------------------------

bob.ns.Prices:GetTable()[2589] = nil
Scan(bob, { [2589] = 1500 }, clock)
current = bob
check("Bob's fresh scan wins", bob.ns.Prices:GetValue(2589), 1500)
do
    local asked, real = 0, Realm.GetValue
    Realm.GetValue = function(...) asked = asked + 1; return real(...) end
    bob.ns.Prices:GetValue(2589)
    check("with his own fresh price the realm's is not worked out", asked, 0)
    Realm.GetValue = real
end
Realm:OnPrices("Eve-Realm", bob.ns.Comm.ToBase36(clock) .. ":" .. bob.ns.Comm.ToBase36(2589) .. ","
    .. bob.ns.Comm.ToBase36(15000000) .. ";", "CHANNEL", "BTSPricesA", "4. BTSPricesA")
check("a price far from his own is refused", Realm:Players(), 3)

bob.settings.staleAfterSeconds = 3600
bob.ns.Prices:GetTable()[2589].seen = clock - 7200
check("once his is stale, the newer realm price wins", bob.ns.Prices:GetValue(2589), 1100)

bob.settings.guildPrices = true
bob.ns.GuildPrices.GetValue = function() return 1234, clock end
check("a guild price wins over the realm's", bob.ns.Prices:GetValue(2589), 1234)
bob.ns.GuildPrices.GetValue = function() return nil end
bob.settings.guildPrices = false

bob.settings.realmPrices = false
check("realm prices off: his own again", bob.ns.Prices:GetValue(2589), 1500)
bob.settings.realmPrices = true

do
    -- One player's price is guarded by the price you know, even an old one
    -- of your own (the owner, 2026-11-18): under 5% or over 10 times it is
    -- refused.
    local Comm = bob.ns.Comm
    local function Send(sender, itemID, value)
        Realm:OnPrices(sender, Comm.ToBase36(clock) .. ":" .. Comm.ToBase36(itemID) .. ","
            .. Comm.ToBase36(value) .. ";", "CHANNEL", "BTSPricesA", "4. BTSPricesA")
    end
    bob.ns.Prices:GetTable()[2600] = { market = 1000, minBuyout = 1000, seen = clock - 10 * 86400 }
    Send("Eve-Realm", 2600, 40)
    check("under 5% of his old price is refused", Realm:GetValue(2600), nil)
    Send("Eve-Realm", 2600, 60)
    check("a bit over 5% is taken", (Realm:GetValue(2600)), 60)
    Send("Fay-Realm", 2600, 12000)
    check("over 10 times his old price is refused", (Realm:GetValue(2600)), 60)
    check("his old price gives way to one player's newer one", bob.ns.Prices:GetValue(2600), 60)

    bob.ns.GuildPrices.GetValue = function(_, itemID) if itemID == 2601 then return 2000, clock end end
    Send("Eve-Realm", 2601, 50)
    check("with no price of his own, under 5% of the guild's is refused", Realm:GetValue(2601), nil)
    Send("Eve-Realm", 2601, 25000)
    check("and over 10 times it", Realm:GetValue(2601), nil)
    Send("Eve-Realm", 2601, 1500)
    check("a price near the guild's is kept", (Realm:GetValue(2601)), 1500)
    bob.ns.GuildPrices.GetValue = function() return nil end

    Send("Eve-Realm", 2602, 7)
    check("nothing known: one player's price fills the gap", bob.ns.Prices:GetValue(2602), 7)
end

--------------------------------------------------------------------------------
print("\nwhat is not listened to")
--------------------------------------------------------------------------------

do
    local Comm = bob.ns.Comm
    local before = Realm.version
    local body = Comm.ToBase36(clock) .. ":" .. Comm.ToBase36(7070) .. "," .. Comm.ToBase36(800) .. ";"
    Realm:OnPrices("Eve-Realm", body, "WHISPER", nil, "Bob")
    Realm:OnPrices("Eve-Realm", body, "GUILD")
    Realm:OnPrices("Eve-Realm", body, "CHANNEL", "Trade", "2. Trade")
    Realm:OnPrices("Eve-Realm", "zz$:1,2;", "CHANNEL", "BTSPricesA", "4. BTSPricesA")
    Realm:OnPrices("Eve-Realm", Comm.ToBase36(clock - 30 * 86400) .. ":" .. Comm.ToBase36(4) .. ",5;",
        "CHANNEL", "BTSPricesA", "4. BTSPricesA")
    check("whispers, guild, other channels and junk are not kept", Realm.version, before)
    current = bob
    Realm:OnPrices("Bob-Realm", body, "CHANNEL", "BTSPricesA", "4. BTSPricesA")
    check("nor his own echo", Realm.version, before)
    bob.settings.realmPrices = false
    Realm:OnPrices("Eve-Realm", body, "CHANNEL", "BTSPricesA", "4. BTSPricesA")
    check("nor anything while it is off", Realm.version, before)
    bob.settings.realmPrices = true
end

--------------------------------------------------------------------------------
print("\nthe channel says no")
--------------------------------------------------------------------------------

do
    -- A channel joined by name is still there at the next login, so no join
    -- happens and the filter has to go in at load.
    local before = filters
    local fay = NewClient("Fay", "Forever-Alliance")
    check("the filter goes in at load", filters - before >= 2, true)
    current = fay
    fay.settings.realmPrices = true
    fay.channels["btspricesa"] = 4
    local Fay = fay.ns.RealmPrices
    check("a notice about another player is filtered too", Fay.FilterNotice(nil, "CHAT_MSG_CHANNEL_NOTICE_USER",
        "PLAYER_ALREADY_MEMBER", "", "", "4. BTSPricesA", "", 0, 4, "", "BTSPricesA"), true)

    check("our own join line is no refusal", Fay:OnNotice("YOU_CHANGED", "4. BTSPricesA", "BTSPricesA"), false)
    check("and keeps no quiet", Fay:Quiet(), false)

    Scan(fay, { [2589] = 1000, [2592] = 500 }, clock - 60)
    check("Fay shares her scan", (Fay:Share()), true)
    Fay:Drip()
    check("one message went", Fay.lastSendAt ~= nil, true)
    check("a line in another channel is ignored", Fay:OnNotice("NOT_PERMITTED", "2. Trade", "Trade"), false)
    check("a refusal right after a send is heard",
        Fay:OnNotice("SOMETHING_NEW", "4. BTSPricesA", "BTSPricesA"), true)
    check("the rest of the share is dropped", Fay.outbox, nil)
    check("it keeps quiet", Fay:Quiet(), true)
    check("the status of a share says why", select(2, Fay:Share()), "channel said no")
    Fay.outbox = { { kind = "Y", text = "1" } }
    local sends = #network
    Fay:Drip()
    check("nothing is sent while quiet", #network, sends)
    check("and the outbox is let go", Fay.outbox, nil)

    -- The same send refused again counts once.
    Fay:OnRefused("NOT_PERMITTED")
    check("a repeat is counted once", Fay.refusals, 1)

    -- Listening goes on.
    local version = Fay.version
    local Comm = fay.ns.Comm
    Fay:OnPrices("Gus-Realm", Comm.ToBase36(clock) .. ":" .. Comm.ToBase36(7070) .. "," .. Comm.ToBase36(800)
        .. ";", "CHANNEL", "BTSPricesA", "4. BTSPricesA")
    check("prices from others still come in", Fay.version ~= version, true)

    uptime = uptime + Fay.BACK_OFF + 1
    check("after a while it may send again", Fay:Quiet(), false)
    check("a stray notice long after a send is no refusal",
        Fay:OnNotice("SOMETHING_NEW", "4. BTSPricesA", "BTSPricesA"), false)

    Fay:OnRefused("NOT_PERMITTED")
    check("a second refusal waits twice as long",
        Fay.quietUntil - uptime, Fay.BACK_OFF * 2)
    uptime = uptime + Fay.BACK_OFF * 2 + 1
    Fay:OnRefused("NOT_PERMITTED")
    check("a third stops it for the session", Fay.quietUntil, math.huge)
    uptime = uptime + 24 * 3600
    check("still quiet a day later", Fay:Quiet(), true)
    current = ana
end

--------------------------------------------------------------------------------
print("\nturned off, and later")
--------------------------------------------------------------------------------

current = bob
Realm:SetOn(false)
check("off again: the channel is left", bob.channels["btspricesa"], nil)
check("the prices stay in the save", Realm:Count() > 0, true)
Realm:SetOn(true)

clock = clock + 8 * 86400
check("a week later they are pruned", Realm:Prune() > 0, true)
check("and nothing is left", Realm:Count(), 0)

--------------------------------------------------------------------------------

do
    -- Farmer never gets this (the owner, 2026-10-20: guild at most).
    local farmer = io.open(lfs_cwd .. "/../Blackthornes_Farmer/Logic/RealmPrices.lua", "r")
    check("Farmer has no realm sharing", farmer, nil)
    if farmer then farmer:close() end
end

for name, value in pairs(saved) do _G[name] = value end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then error(("%d realm price check(s) failed"):format(failed)) end
