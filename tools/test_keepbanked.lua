-- Keep on This Character holds items in the bank too (a player, 2026-11-28).
--
-- They kept 3 Gold Power Cores, all in the bank. The queue still counted
-- them as there to craft with, and Butler took one out of the bank for a
-- craft. What must hold:
--   1. KeepHere:Spare takes the keep out of the bank first, then the bags,
--      then the mail, and the bigger of Tradeskills' and Butler's numbers wins.
--   2. The shopping list counts only what is past the keep: the kept cores
--      are not "have", and the row does not send you to the bank for them.
--   3. A sub-craft is queued for what the keep leaves short.
--   4. With no keep, nothing changes.

local function noop() end

local CORE, BAR, SCOPE = 10558, 3577, 10546
local CORE_RECIPE, SCOPE_RECIPE = 12584, 12597

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = noop, noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Util = { HasFunction = function(name) return type(_G[name]) == "function" end }

local settings = { valueOwnedMaterials = true, autoQueueSubCrafts = true,
    suggestOtherCharacters = false, countMailAsStock = true }
local ME = "Player-1-0000001"
ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return ME end,
}

local RECIPES = {
    [CORE_RECIPE] = { recipeID = CORE_RECIPE, name = "Gold Power Core", outputItemID = CORE,
        quantityMin = 1, quantityMax = 1, reagents = { { itemID = BAR, quantity = 1 } } },
    [SCOPE_RECIPE] = { recipeID = SCOPE_RECIPE, name = "Scope", outputItemID = SCOPE,
        quantityMin = 1, quantityMax = 1, reagents = { { itemID = CORE, quantity = 1 } } },
}
local record = {}
ns.Recipes = {
    GetAny = function(_, id) return RECIPES[id], ME end,
    GetAll = function() return RECIPES end,
    GetCharacterRecord = function() return record end,
}

local bags, bank, mail = {}, {}, {}
ns.Inventory = {
    GetBagCount = function(_, id) return bags[id] or 0 end,
    GetBankCount = function(_, id) return bank[id] or 0 end,
    GetMailCount = function(_, id) return mail[id] or 0 end,
    GetOwnedCount = function(_, id) return (bags[id] or 0) + (bank[id] or 0) + (mail[id] or 0) end,
    GetAltTotal = function() return 0 end,
}

-- A core costs far more to buy than its bar, so the queue makes one.
local PRICES = { [CORE] = 5000, [BAR] = 100, [SCOPE] = 20000 }
ns.Prices = { GetValue = function(_, id) return PRICES[id] end }
ns.Vendor = { GetUnitPrice = function() return nil end, IsLimited = function() return false end }
ns.Profit = { Analyse = function() return nil end }
ns.db = { queue = {} }

assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/KeepHere.lua"))("Blackthornes_TS", ns)
local Queue, KeepHere = ns.Queue, ns.KeepHere

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-60s %-8s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Line(itemID)
    for _, line in ipairs(Queue:GetShoppingList()) do
        if line.itemID == itemID then return line end
    end
end

local function Queued(recipeID)
    for _, entry in ipairs(Queue:GetAll()) do
        if entry.recipeID == recipeID then return entry.quantity end
    end
    return 0
end

local function Reset()
    bags, bank, mail = {}, {}, {}
    ns.db.queue = {}
    ns.db.keepOnCharacter = nil
    _G.BlackthornesButler = nil
end

print("what is spare past the keep")
do
    Reset()
    KeepHere:Set(CORE, 3)
    local b, k, m = KeepHere:Spare(CORE, 0, 3, 0)
    check("three in the bank, keep 3: none spare in the bank", k, 0)
    check("and none in the bags", b, 0)
    b, k, m = KeepHere:Spare(CORE, 2, 2, 1)
    check("the bank goes first", k, 0)
    check("then the bags", b, 1)
    check("the mail is left alone", m, 1)
    KeepHere:Set(CORE, 0)
    _G.BlackthornesButler = { KeepHere = { Count = function(_, id) return id == CORE and 4 or nil end } }
    check("Butler's number counts", KeepHere:Kept(CORE), 4)
    KeepHere:Set(CORE, 2)
    check("the bigger one wins", KeepHere:Kept(CORE), 4)
    _G.BlackthornesButler = { KeepHere = { Count = function() error("boom") end } }
    check("Butler raising is skipped", KeepHere:Kept(CORE), 2)
end

print("")
print("the queue with three cores kept in the bank")
do
    Reset()
    settings.autoQueueSubCrafts = false
    bank[CORE] = 3
    Queue:Add(SCOPE_RECIPE, 1)
    local line = Line(CORE)
    check("no keep: the bank's cores cover it", line and line.shortfall, 0)
    check("and the row sends you to the bank", line and line.needsBankTrip, true)

    KeepHere:Set(CORE, 3)
    line = Line(CORE)
    check("kept: one still to get", line and line.shortfall, 1)
    check("the kept cores are not counted as had", line and line.have, 0)
    check("nor shown as in the bank", line and line.inBank, 0)
    check("so no trip to the bank for them", line and line.needsBankTrip, false)

    bank[CORE] = 4
    line = Line(CORE)
    check("one past the keep: that one is used", line and line.shortfall, 0)
    check("and it is in the bank", line and line.inBank, 1)

    KeepHere:Set(CORE, KeepHere.MOST)
    check("Keep All: none used", Line(CORE).shortfall, 1)
    settings.autoQueueSubCrafts = true
end

print("")
print("a sub-craft for what the keep leaves short")
do
    Reset()
    bank[CORE] = 3
    Queue:Add(SCOPE_RECIPE, 1)
    check("no keep: no core to make", Queued(CORE_RECIPE), 0)
    KeepHere:Set(CORE, 3)
    Queue:RebuildDependencies()
    check("kept: one core queued to make", Queued(CORE_RECIPE), 1)
end

_G.BlackthornesButler = nil
ns.db.keepOnCharacter = nil

if failed > 0 then
    error(string.format("FAIL -- %d of %d keep in the bank checks wrong", failed, passed + failed))
end
print(string.format("PASS -- Keep on This Character holds the bank too (%d checks)", passed))
