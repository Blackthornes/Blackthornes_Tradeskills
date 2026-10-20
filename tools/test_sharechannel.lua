-- The channel check (/bts share channel, 2026-10-20): before prices are
-- shared on a hidden chat channel, ask the client what it allows.
--
-- What must hold:
--   1. It joins the test channel, sends on it by the channel's number,
--      counts what comes back, finds where sends are refused, and leaves.
--   2. Lines printed after the first frame join the saved check.
--   3. The join and leave lines of the test channel are kept out of chat;
--      other channels' are not.
--   4. A client that will not join says so and sends nothing.
--   5. It never runs in a fight.

local saved = {}
for _, name in ipairs({ "GetTime", "UnitName", "C_ChatInfo", "C_Timer", "InCombatLockdown",
                        "JoinTemporaryChannel", "LeaveChannelByName", "GetChannelName",
                        "GetChannelList", "ChatFrame_AddMessageEventFilter" }) do
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

local timers = {}
C_Timer = {
    NewTicker = function() return { Cancel = function() end } end,
    After = function(_, fn) timers[#timers + 1] = fn end,
}
local function RunTimers()
    for _ = 1, 200 do
        if #timers == 0 then return end
        local batch = timers
        timers = {}
        for _, fn in ipairs(batch) do fn() end
    end
end

GetTime = function() return 100 end
UnitName = function() return "Ana" end
local fighting = false
InCombatLockdown = function() return fighting end

local joined, joinWorks, sendsBeforeThrottle, sends = false, true, 10, 0
local ns
local outbox = {}
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, text, channel, target)
        if #text > 255 then error("message too long") end
        sends = sends + 1
        if channel == "CHANNEL" and sends > sendsBeforeThrottle and text:sub(2, 2) == "A" then return 3 end
        outbox[#outbox + 1] = { prefix = prefix, text = text, channel = channel, target = target }
        return 0
    end,
}
JoinTemporaryChannel = function() if joinWorks then joined = true end end
LeaveChannelByName = function() joined = false end
GetChannelName = function() if joined then return 5, "BTSPriceTest" end return 0, nil end
GetChannelList = function() if joined then return 1, "General", false, 5, "BTSPriceTest", false end
    return 1, "General", false end
local filter
ChatFrame_AddMessageEventFilter = function(event, fn) if event == "CHAT_MSG_CHANNEL_NOTICE" then filter = fn end end

local printed
local function Load()
    ns = {}
    printed = {}
    ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
    ns.NewModule = function(module) local m = {}; ns[module] = m; return m end
    ns.RegisterEvent = function() end
    ns.Print = function(text) printed[#printed + 1] = text end
    ns.PrintRaw = ns.Print
    ns.Debug = function() end
    ns.db = { global = {} }
    ns.Serialize = {}
    assert(loadfile(lfs_cwd .. "/Core/Comm.lua"))("Blackthornes_TS", ns)
    ns.Comm:OnEnable()
    -- ns.KeepCheck as Core/Init.lua has it, in short.
    ns.db.global.lastProbe = { check = "share channel", lines = {} }
end

local function Deliver()
    local batch = outbox
    outbox = {}
    for _, message in ipairs(batch) do
        ns.Comm:CHAT_MSG_ADDON("CHAT_MSG_ADDON", message.prefix, message.text, "CHANNEL", "Ana",
            "BTSPriceTest", 0, 5, "BTSPriceTest")
    end
end

local function Has(fragment)
    for _, line in ipairs(printed) do
        if tostring(line):find(fragment, 1, true) then return true end
    end
    return false
end

print("1. joins, sends, counts, leaves")
Load()
ns.Comm:ChannelTest()
check("joined", joined, true)
-- Deliver after each round of timers, so echoes come back before counting.
for _ = 1, 100 do
    if #timers == 0 then break end
    Deliver()
    local batch = timers
    timers = {}
    for _, fn in ipairs(batch) do fn() end
end
check("left again", joined, false)
check("burst refused where the client said", ns.Comm.channelTest, nil)
check("first refusal reported", Has("first refused #10"), true)
check("burst echoes counted", Has("at once 9"), true)
check("paced all went", Has("20 went, 0 refused"), true)
check("paced echoes counted", Has("paced ones: 20"), true)
check("sent by channel number", Has("number 5"), true)
check("says done", Has("done."), true)
local saved_lines = ns.db.global.lastProbe.lines
check("late lines joined the saved check", #saved_lines > 5, true)

print("2. the test channel's notices are hidden, others' are not")
Load()
ns.Comm:ChannelTest()
check("our notice hidden", filter(nil, "CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", "", "", "5. BTSPriceTest",
    "", 0, 5, "", "BTSPriceTest"), true)
check("General left alone", filter(nil, "CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", "", "", "1. General",
    "", 0, 1, "", "General"), false)
joined = false
timers = {}
ns.Comm.channelTest = nil
check("nothing hidden while no check runs", filter(nil, "CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", "", "",
    "5. BTSPriceTest", "", 0, 5, "", "BTSPriceTest"), false)

print("3. a client that will not join")
Load()
joinWorks, sends = false, 0
ns.Comm:ChannelTest()
RunTimers()
check("said it could not join", Has("could not join"), true)
check("nothing sent", sends, 0)
joinWorks = true

print("4. never in a fight")
Load()
fighting = true
ns.Comm:ChannelTest()
check("not joined in a fight", joined, false)
check("said why", Has("out of a fight"), true)
fighting = false

for name, value in pairs(saved) do _G[name] = value end
print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then error(("%d check(s) failed"):format(failed)) end
