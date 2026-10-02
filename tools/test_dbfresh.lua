-- /bts db fresh, outside WoW.
--
-- The account-wide saved file came back empty, the player was warned, and he
-- typed /bts db fresh as the warning says. What must hold:
--   1. The warning stops for every character, not only the one he typed it
--      on. It used to come back, sound and all, on each other character
--      until the new file had more sessions than that character remembered.
--   2. A later loss still warns, on every character.
--   3. A second fresh start after a second loss is taken by every character
--      too.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "BlackthornesTSCharDB", "time" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local clock = 100000
time = function() return clock end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = { moduleName = name }; ns[name] = m; return m end
ns.RegisterEvent = noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.Util = {}

local commands = {}
ns.RegisterCommand = function(name, _, fn) commands[name] = fn end

assert(loadfile(lfs_cwd .. "/Core/Config.lua"))("Blackthornes_TS", ns)
local Config = ns.Config

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-6s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local account
local characters = { A = {}, B = {}, C = {} }

-- One login: the account file counts a session, and the character compares
-- it with what it remembers. True when the warning is raised.
local function Login(who)
    clock = clock + 60
    account.probe.loadCount = account.probe.loadCount + 1
    BlackthornesTSCharDB = characters[who]
    ns.db = account
    Config.accountDataLost = nil
    Config:CheckAccountDataLost(account)
    return Config.accountDataLost ~= nil
end

print("")
print("starting fresh after a loss")

account = { probe = { loadCount = 0 } }
for _ = 1, 3 do Login("A"); Login("B") end
check("normal play warns nobody", Login("A") or Login("B"), false)

-- The account file comes back empty.
account = { probe = { loadCount = 0 } }
check("the loss warns on A", Login("A"), true)
commands.db("fresh")
check("/bts db fresh clears it", Config.accountDataLost, nil)
check("A's next login is quiet", Login("A"), false)
check("B's next login is quiet too", Login("B"), false)
check("and B's after that", Login("B"), false)
check("a new character is quiet", Login("C"), false)

print("")
print("a later loss still warns")

local before = account
account = { probe = { loadCount = 0 } }
check("on A", Login("A"), true)
check("on B", Login("B"), true)

-- The file older than B remembers, with the fresh start still in it.
account = before
account.probe.loadCount = account.probe.loadCount - 3
check("an older copy of the fresh file warns on B", Login("B"), true)

print("")
print("a second fresh start")

account = { probe = { loadCount = 0 } }
check("the second loss warns on A", Login("A"), true)
commands.db("fresh")
check("B takes the second fresh start too", Login("B"), false)
check("and C", Login("C"), false)

print("")
print("the old file coming back")

local restored = { probe = { loadCount = 500 } }
account = restored
check("a restored file with more sessions warns nobody", Login("A") or Login("B") or Login("C"), false)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end
ns.db = nil

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "fresh start checks failed")
