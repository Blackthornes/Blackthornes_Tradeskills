-- Forever's 1 silver minimum deposit (its news, 2026-11-06): a listing
-- pays at least 1s, one item or a whole stack. The game takes the right
-- amount when you post; these checks are about the guesses Tradeskills
-- makes away from the auction house, for profit.

local GLOBALS = { "CreateFrame", "GetTime", "time" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end
CreateFrame = function()
    return setmetatable({}, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
end
GetTime = function() return 1000 end
time = function() return 100000 end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = noop, noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop

local settings = { auctionCut = 0.05, expectedRelists = 2 }
ns.Config = { Get = function(_, key) return settings[key] end }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)
local Util, Profit = ns.Util, ns.Profit

local cached = {}
ns.db = { deposits = {} }
ns.Posting = {
    MIN_DEPOSIT = 100,
    GetCachedUnitDeposit = function(_, itemID) return cached[itemID] end,
}

local BAG, CLOTH, NEW = 7955, 2589, 4242
Util.GetMaxStackSize = function(itemID)
    if itemID == CLOTH then return 200 end
    if itemID == BAG then return 1 end
end

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end
local function Tenths(v) return math.floor(v * 10 + 0.5) end

print("")
print("one item a listing")
cached[BAG] = 5
check("a 5c share still loses the whole 1s", Profit.LostDepositEach(BAG), 100)
check("so 3s pays 3s less the cut less 1s", Tenths(Profit:NetFromListing(BAG, 300)), 1850)

print("")
print("a stack")
cached[CLOTH] = 0.1
ns.db.deposits[CLOTH] = { unit = 0.1, quantity = 20 }
check("20 a listing: 5c each", Profit.LostDepositEach(CLOTH), 5)
ns.db.deposits[CLOTH] = nil
check("no listing seen: a full stack of 200 shares it", Profit.LostDepositEach(CLOTH), 0.5)
cached[CLOTH] = 2
check("a bigger share each wins over the floor", Profit.LostDepositEach(CLOTH), 2)

print("")
print("nothing known")
check("an item never listed costs the 1s", Profit.LostDepositEach(NEW), 100)

print("")
print("the deposit comes back on a sale")
settings.expectedRelists = 1
check("sold first time, nothing is lost", Tenths(Profit:NetFromListing(BAG, 300)), 2850)
settings.expectedRelists = 2

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "minimum deposit checks failed")
