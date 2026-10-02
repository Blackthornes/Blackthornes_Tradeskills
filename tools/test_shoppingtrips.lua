-- Where the shopping list sends you, and how often it is built.
--
-- What must hold:
--   1. Bolts a sub-craft leaves over that are waiting in the mailbox read
--      "in mail", not "in bank": the bank had none of them.
--   2. Bolts in the bank still read "in bank".
--   3. The totals are worked out from a list already built. The Buy view's
--      summary built the whole list again on every one-second tick at the
--      auction house, and the craft pane built it twice on every queue click.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "time" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

time = function() return 100000 end

local CLOTH, BOLT, BAG = 2589, 2996, 4240
local BOLT_RECIPE, BAG_RECIPE = 2963, 3755

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand, ns.RegisterEvent = noop, noop
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Util = { HasFunction = function() return false end }

local settings = { valueOwnedMaterials = true, autoQueueSubCrafts = true,
    suggestOtherCharacters = false }
ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return "me" end,
}

local RECIPES = {
    [BOLT_RECIPE] = { recipeID = BOLT_RECIPE, name = "Bolt of Linen Cloth", outputItemID = BOLT,
        quantityMin = 1, quantityMax = 1, reagents = { { itemID = CLOTH, quantity = 2 } } },
    [BAG_RECIPE] = { recipeID = BAG_RECIPE, name = "Linen Bag", outputItemID = BAG,
        quantityMin = 1, quantityMax = 1, reagents = { { itemID = BOLT, quantity = 3 } } },
}
ns.Recipes = {
    GetAny = function(_, id) return RECIPES[id], "me" end,
    GetAll = function() return RECIPES end,
}

local bags, bank, mail = {}, {}, {}
ns.Inventory = {
    GetBagCount = function(_, id) return bags[id] or 0 end,
    GetBankCount = function(_, id) return bank[id] or 0 end,
    GetMailCount = function(_, id) return mail[id] or 0 end,
    GetOwnedCount = function(_, id) return (bags[id] or 0) + (bank[id] or 0) + (mail[id] or 0) end,
    GetAltTotal = function() return 0 end,
}

local LOWEST = { [CLOTH] = 10, [BOLT] = 50 }
ns.Prices = { GetValue = function(_, id) return LOWEST[id] end }
ns.Vendor = { GetUnitPrice = function() return nil end, IsLimited = function() return false end }
ns.Profit = { Analyse = function() return nil end }
ns.db = { queue = {} }

assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)
local Queue = ns.Queue

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

print("bolts another character mailed you")

do
    -- Five bolts in the mailbox; five bags need fifteen, so ten are made.
    bags, bank, mail = { [CLOTH] = 20 }, {}, { [BOLT] = 5 }
    ns.db.queue = {}
    Queue:Add(BAG_RECIPE, 5)

    local line = Line(BOLT)
    check("the five still owed are covered", line.shortfall, 0)
    check("by the mailbox", line.inMail, 5)
    check("which is where the row sends you", line.needsMailTrip, true)
    check("not the bank, which has none", line.needsBankTrip, false)
end

print("")
print("bolts in the bank")

do
    bags, bank, mail = { [CLOTH] = 20 }, { [BOLT] = 5 }, {}
    ns.db.queue = {}
    Queue:Add(BAG_RECIPE, 5)

    local line = Line(BOLT)
    check("covered by the bank", line.needsBankTrip, true)
    check("with no trip to the mailbox", line.needsMailTrip, false)
end

print("")
print("bolts already in the bags")

do
    bags, bank, mail = { [CLOTH] = 20, [BOLT] = 5 }, {}, {}
    ns.db.queue = {}
    Queue:Add(BAG_RECIPE, 5)

    local line = Line(BOLT)
    check("no trip to the bank", line.needsBankTrip, false)
    check("nor to the mailbox", line.needsMailTrip, false)
end

print("")
print("the totals use the list in hand")

local built = 0
local realList = Queue.GetShoppingList
Queue.GetShoppingList = function(self, ...)
    built = built + 1
    return realList(self, ...)
end

do
    bags, bank, mail = {}, {}, {}
    ns.db.queue = {}
    Queue:Add(BAG_RECIPE, 2)

    local lines = Queue:GetShoppingList()
    built = 0
    local total, unknown = Queue:GetShoppingTotal(lines)
    check("the total from a list given to it", total, 12 * 10)
    check("with nothing unpriced", unknown, 0)
    check("builds no list of its own", built, 0)

    Queue:GetGatherSummary(lines)
    check("nor does the Gather tab's summary", built, 0)

    Queue:GetShoppingTotal()
    check("asked with no list, it still builds one", built, 1)
end

do
    -- The Buy view's summary line, as its one-second ticker draws it.
    local PostPanel
    local realNew = ns.NewModule
    ns.Theme, ns.Widgets = {}, {}
    ns.Util.FormatMoney = function(copper) return tostring(copper) .. "c" end
    ns.NewModule = function(name) local m = realNew(name); PostPanel = m; return m end
    assert(loadfile(lfs_cwd .. "/UI/PostPanel.lua"))("Blackthornes_TS", ns)
    ns.NewModule = realNew

    local lines = Queue:GetShoppingList()
    built = 0
    local text = PostPanel:ShoppingSummary(lines)
    check("the Buy view's summary builds no list of its own", built, 0)
    check("and still says what it costs", text, "1 material to buy, about 120c")
end

do
    -- The craft pane's To buy line.
    local CraftPanel
    local realNew = ns.NewModule
    ns.NewModule = function(name) local m = realNew(name); CraftPanel = m; return m end
    assert(loadfile(lfs_cwd .. "/UI/CraftPanel.lua"))("Blackthornes_TS", ns)
    ns.NewModule = realNew

    local lines = Queue:GetShoppingList()
    built = 0
    check("the craft pane's To buy line", CraftPanel:ShoppingTotalText(lines), "To buy 120c")
    check("builds no list of its own", built, 0)
end

Queue.GetShoppingList = realList
ns.db.queue = {}
for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
if failed > 0 then
    error(string.format("FAIL -- %d of %d shopping trip checks wrong", failed, passed + failed))
end
print(string.format("PASS -- the shopping list sends you to the right place (%d checks)", passed))
