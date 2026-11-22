-- Minimums by profession (the owner said build it, 2026-11-17, from a
-- mockup): each profession can have its own Minimum Profit and Minimum
-- Margin, saved account wide in professionMinimums.
--
-- What must hold:
--   * a profession's own number wins, an empty one uses the usual, and 0
--     shows everything for that profession;
--   * the Profit tab's list (and so Queue All) follows each craft's own
--     profession; numbers a caller passes still hold for every craft;
--   * Level Up's "worth it" pick checks the profession's Minimum Profit;
--   * Post at Minimum Profit and the undercut check use it and name the
--     profession;
--   * Deals stays on the usual numbers (it reads minProfit itself);
--   * Export and Import carry it, and an older code is not upset by it.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.L = setmetatable({ Format = string.format }, { __index = function(_, key) return key end })
time = time or os.time

ns.Util = {
    Count = function(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end,
    FormatMoney = function(c) return tostring(c) .. "c" end,
    ItemAuctionPrice = function(p) return math.max(1, math.floor(p)) end,
    ItemAuctionPriceUp = function(p) return math.max(1, math.ceil(p)) end,
}

local POTION, KIT, MEAT = 100, 200, 300
ns.db = {
    queue = {}, postLimits = {}, postedAuctions = {}, professionStockLimits = {},
    professionMinimums = {},
    characters = {
        alice = { recipesCachedAt = 1, recipes = {
            [1] = { recipeID = 1, outputItemID = POTION, skillLineID = 171 },   -- Alchemy
            [2] = { recipeID = 2, outputItemID = KIT, skillLineID = 165 },      -- Leatherworking
            [3] = { recipeID = 3, outputItemID = MEAT, skillLineID = 185 },     -- Cooking
        } },
    },
}

local settings = { minProfit = 500, minMarginPercent = 10, auctionCut = 0.05,
    undercutCopper = 0, postAtMinProfit = false, ignoreDeposit = true }
ns.Config = {
    Get = function(_, key) return settings[key] end,
    Set = function(_, key, value) settings[key] = value end,
    GetRealmKey = function() return "Test-Realm" end,
    GetPriceTable = function() return {} end,
    DEFAULTS = { settings = { minProfit = 0 } },
}
ns.UI = { RefreshActiveTab = function() end, UpdateHeader = function() end }

assert(loadfile(lfs_cwd .. "/Data/Recipes.lua"))("Blackthornes_TS", ns)
local recipesByID = ns.db.characters.alice.recipes
ns.Recipes.GetAny = function(_, id) return recipesByID[id] end
ns.Recipes.GetAll = function() return recipesByID end
ns.Recipes.IsDropped = function() return false end

ns.Inventory = {
    GetBagCount = function() return 0 end, GetBankCount = function() return 0 end,
    GetMailCount = function() return 0 end, GetOwnedCount = function() return 0 end,
}
ns.Queue = { GetAll = function() return ns.db.queue end, Find = function() end, Add = function() end }
assert(loadfile(lfs_cwd .. "/Data/Auctions.lua"))("Blackthornes_TS", ns)

local rival = 1000
ns.Prices = {
    GetValue = function() return rival end,
    GetMine = function() return nil end,
}
ns.Scanner = { GetCommodityStatus = function() return false end }
ns.Cost = {
    FindAnyRecipeForItem = function(_, itemID)
        for id, recipe in pairs(recipesByID) do if recipe.outputItemID == itemID then return id end end
    end,
    GetCraftCost = function() return { priceable = true, total = 1000, yield = 1 } end,
}

assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)
local Profit = ns.Profit

local failures = 0
local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(string.format("  %-62s %-12s %s", label, tostring(got),
        ok and "ok" or ("EXPECTED " .. tostring(expected))))
end

-- Nothing set: every craft uses the usual numbers.
local profit, margin, named = Profit:MinimumsFor(recipesByID[1])
check("nothing set: usual profit", profit, 500)
check("nothing set: usual margin", margin, 10)
check("nothing set: no profession named", named, nil)
check("nothing set: none have their own", Profit:HasProfessionMinimums(), false)

-- Alchemy asks for 1 s (100c), its margin left empty.
Profit:SetProfessionMinimum("Alchemy", "profit", 100)
profit, margin, named = Profit:MinimumsFor(recipesByID[1])
check("Alchemy's own profit wins", profit, 100)
check("Alchemy's empty margin uses the usual", margin, 10)
check("Alchemy is named", named, "Alchemy")
check("found by item too", (Profit:MinimumsFor(POTION)), 100)
check("found by name too", (Profit:MinimumsFor("Alchemy")), 100)
check("saved by English name", ns.db.professionMinimums.Alchemy.profit, 100)
check("now some have their own", Profit:HasProfessionMinimums(), true)

Profit:SetProfessionMinimum("Leatherworking", "profit", 1000)
Profit:SetProfessionMinimum("Leatherworking", "margin", 20)
Profit:SetProfessionMinimum("Cooking", "profit", 0)
Profit:SetProfessionMinimum("Cooking", "margin", 0)
profit, margin = Profit:MinimumsFor(recipesByID[3])
check("Cooking at 0 asks for nothing", profit == 0 and margin == 0, true)

-- The ranked list: each craft against its own profession.
local analyses = {
    [1] = { recipeID = 1, name = "Healing Potion", skillLineID = 171, priceable = true,
            profit = 240, margin = 0.18 },
    [2] = { recipeID = 2, name = "Thick Armor Kit", skillLineID = 165, priceable = true,
            profit = 800, margin = 0.31 },
    [3] = { recipeID = 3, name = "Spiced Wolf Meat", skillLineID = 185, priceable = true,
            profit = 35, margin = 0.09 },
}
Profit.Analyse = function(_, recipeID) return analyses[recipeID] end

local function Shown(opts)
    local names = {}
    for _, row in ipairs(Profit:GetRanked(opts or { ignoreStock = true })) do names[row.recipeID] = true end
    return names
end
local shown = Shown()
check("Healing Potion at 2s 40c shows under Alchemy's 1 s", shown[1] == true, true)
check("a Leatherworking craft at 8 s is hidden by its 10 s", shown[2] == nil, true)
check("Cooking at 0 shows Spiced Wolf Meat", shown[3] == true, true)

shown = Shown({ ignoreStock = true, minProfit = 0, minMargin = 0 })
check("numbers a caller passes hold for every craft", shown[1] and shown[2] and shown[3] and true, true)

Profit:SetProfessionMinimum("Leatherworking", "margin", 40)
check("a margin of its own hides too", Shown()[2] == nil, true)
Profit:SetProfessionMinimum("Leatherworking", "profit", nil)
Profit:SetProfessionMinimum("Leatherworking", "margin", nil)
check("both cleared, the record goes", ns.db.professionMinimums.Leatherworking, nil)
check("Leatherworking back on the usual shows the kit", Shown()[2] == true, true)

Profit:ClearProfessionMinimums("Cooking")
check("x clears both", ns.db.professionMinimums.Cooking, nil)
check("Cooking back on the usual hides the meat", Shown()[3] == nil, true)

-- Level Up's "worth it" pick.
local skillNS = setmetatable({ Profit = Profit }, { __index = ns })
local SkillUp = {}
skillNS.NewModule = function() return SkillUp end
local okSkill = pcall(function()
    assert(loadfile(lfs_cwd .. "/Logic/SkillUp.lua"))("Blackthornes_TS", skillNS)
end)
check("SkillUp loads", okSkill, true)
if okSkill and SkillUp.IsWorthIt then
    local craft = { priceable = true, profit = 240, skillLineID = 171, skillUp = { tier = "optimal" } }
    check("worth it under Alchemy's own 1 s", SkillUp:IsWorthIt(craft), true)
    Profit:SetProfessionMinimum("Alchemy", "profit", nil)
    check("not worth it under the usual 5 s", SkillUp:IsWorthIt(craft), false)
    Profit:SetProfessionMinimum("Alchemy", "profit", 100)
end

-- Post at Minimum Profit: costs 1000, 5% cut. Leatherworking asks 1000c.
settings.postAtMinProfit = true
Profit:SetProfessionMinimum("Leatherworking", "profit", 1000)
local price, basis, why = Profit:ChoosePostPrice(KIT, nil, nil, true)
check("lists at the least that makes Leatherworking's 1000c", price, 2106)
check("its basis is minprofit", basis, "minprofit")
check("why names the profession", why ~= nil and why:find("for Leatherworking", 1, true) ~= nil, true)

price, basis, why = Profit:ChoosePostPrice(MEAT, nil, nil, true)
check("Cooking with no number uses the usual 500c", price, 1579)
check("why stays as it is today", why ~= nil and why:find("profit for", 1, true) == nil, true)
settings.postAtMinProfit = false

-- The undercut check: item auctions undercut only above the minimum.
rival, settings.undercutCopper = 2000, 50
price, basis, why = Profit:ChoosePostPrice(KIT)
check("undercut would leave under Leatherworking's 1000c: match", basis, "match")
check("the chat line names the profession", why ~= nil and why:find("minimum for Leatherworking", 1, true) ~= nil, true)
price, basis = Profit:ChoosePostPrice(POTION)
check("Alchemy's 1 s lets the undercut go ahead", basis, "undercut")
rival, settings.undercutCopper = 1000, 0

-- Deals reads the usual numbers itself, never the profession's.
check("the usual Minimum Profit is untouched", settings.minProfit, 500)

-- Export and Import.
assert(loadfile(lfs_cwd .. "/Logic/Transfer.lua"))("Blackthornes_TS", ns)
local code = ns.Transfer:Export()
check("the code carries Alchemy, margin empty", code:find("MAlchemy:100:-", 1, true) ~= nil, true)
check("the code carries Leatherworking", code:find("MLeatherworking:1000:-", 1, true) ~= nil, true)
ns.db.professionMinimums = {}
local ok = ns.Transfer:Import(code)
check("import brings them back", ok and ns.db.professionMinimums.Alchemy
    and ns.db.professionMinimums.Alchemy.profit == 100
    and ns.db.professionMinimums.Alchemy.margin == nil
    and ns.db.professionMinimums.Leatherworking.profit == 1000, true)

-- The Disenchanting row (2026-11-22): buying gear to disenchant.
ns.db.professionMinimums = {}
local p, m, own = Profit:DisenchantMinimums()
check("Disenchanting blank: the usual profit", p, 500)
check("Disenchanting blank: the usual margin", m, 10)
check("Disenchanting blank: not its own", own, false)
Profit:SetProfessionMinimum(Profit.DISENCHANTING, "profit", 2000)
p, m, own = Profit:DisenchantMinimums()
check("Disenchanting's own profit wins", p, 2000)
check("its empty margin uses the usual", m, 10)
check("and says it is its own", own, true)
check("saved under Disenchanting", ns.db.professionMinimums.Disenchanting.profit, 2000)
check("crafts don't count it as a profession's own", Profit:HasProfessionMinimums(), false)
check("crafts keep the usual numbers", (Profit:MinimumsFor(recipesByID[1])), 500)
code = ns.Transfer:Export()
check("the code carries Disenchanting", code:find("MDisenchanting:2000:-", 1, true) ~= nil, true)
ns.db.professionMinimums = {}
ok = ns.Transfer:Import(code)
check("import brings Disenchanting back", ok and ns.db.professionMinimums.Disenchanting
    and ns.db.professionMinimums.Disenchanting.profit == 2000, true)
Profit:ClearProfessionMinimums(Profit.DISENCHANTING)
check("x puts Disenchanting back to the usual", (Profit:DisenchantMinimums()), 500)

if failures > 0 then
    error(string.format("%d minimums by profession check(s) failed", failures), 0)
end
print("PASS -- each profession can have its own minimums")
