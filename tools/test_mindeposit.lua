-- Forever's minimum deposit: 1 silver from 2026-11-06, 1 copper since
-- the 2026-11-10 patch. A listing pays at least that, one item or a
-- whole stack. The game takes the right
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
    MIN_DEPOSIT = 1,
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
check("a 5c share loses its own 5c", Profit.LostDepositEach(BAG), 5)
check("so 3s pays 3s less the cut less 5c", Tenths(Profit:NetFromListing(BAG, 300)), 2800)
cached[BAG] = 0.2
check("a share under 1c still loses the 1c least", Profit.LostDepositEach(BAG), 1)

print("")
print("a stack")
cached[CLOTH] = 0.1
ns.db.deposits[CLOTH] = { unit = 0.1, quantity = 20 }
check("20 a listing: its own share each", Profit.LostDepositEach(CLOTH), 0.1)
ns.db.deposits[CLOTH] = nil
check("no listing seen: a 1c floor shared by 200 is under the share", Profit.LostDepositEach(CLOTH), 0.1)
cached[CLOTH] = 2
check("a bigger share each wins over the floor", Profit.LostDepositEach(CLOTH), 2)

print("")
print("nothing known")
check("an item never listed costs the 1c", Profit.LostDepositEach(NEW), 1)

print("")
print("the deposit comes back on a sale")
settings.expectedRelists = 1
cached[BAG] = 5
check("sold first time, nothing is lost", Tenths(Profit:NetFromListing(BAG, 300)), 2850)
settings.expectedRelists = 2

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "minimum deposit checks failed")
