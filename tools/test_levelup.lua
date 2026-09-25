-- The Level Up tab's order: skill up colour first, material cost second.
--
-- Orange (a point for certain) before yellow before green, a recipe whose
-- colour was never read after green, grey last and only when asked for.
-- Within a colour, the cheapest craft first, and one whose materials have no
-- price after every priced one.
--
-- Drives the real Cost.lua and SkillUp.lua, so the cost ranked on is the same
-- number the Profit tab shows, bolt-or-wool rule included.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.Util = { HasFunction = function() return false end }

time = time or os.time

ns.Config = { Get = function(_, key)
    if key == "valueOwnedMaterials" then return true end
    return nil
end }

local LINEN, BOLT, WOOL, THREAD, MYSTERY = 2589, 2996, 2592, 2320, 9999
local TAILORING, TAILORING_OLD, LEATHER = 2941, 197, 2945

-- Wool buys at 3s a cloth, so a bolt made from 3 is 9s; buying a bolt costs 20s.
local auction = { [LINEN] = 100, [BOLT] = 2000, [WOOL] = 300 }
ns.Prices = { GetValue = function(_, id) return auction[id] end }
ns.Vendor = { GetUnitPrice = function(_, id) return id == THREAD and 50 or nil end }

local bags = { [LINEN] = 4, [THREAD] = 2 }
ns.Inventory = {
    GetBagCount = function(_, id) return bags[id] or 0 end,
    GetBankCount = function() return 0 end,
}

local function R(id, name, tier, skillLine, reagents, output)
    return { recipeID = id, name = name, skillLineID = skillLine or TAILORING,
             outputItemID = output or (5000 + id), quantityMin = 1, quantityMax = 1,
             skillUp = tier and { tier = tier } or nil, reagents = reagents }
end

local recipes = {
    -- Orange, 3s: 2 linen at 1s and 2 vendor thread at 50c.
    [1] = R(1, "Linen Belt", "optimal", nil, { { itemID = LINEN, quantity = 2 }, { itemID = THREAD, quantity = 2 } }),
    -- Orange, 9s via the bolt it makes cheaper than it buys.
    [2] = R(2, "Woolen Cape", "optimal", TAILORING_OLD, { { itemID = BOLT, quantity = 1 } }),
    -- The bolt itself: yellow, 9s.
    [3] = R(3, "Bolt of Woolen Cloth", "medium", nil, { { itemID = WOOL, quantity = 3 } }, BOLT),
    -- Yellow and cheap: 1s. Must still sit below every orange.
    [4] = R(4, "Linen Bandana", "medium", nil, { { itemID = LINEN, quantity = 1 } }),
    -- Orange, no price for one material: after the priced orange ones.
    [5] = R(5, "Odd Gloves", "optimal", nil, { { itemID = MYSTERY, quantity = 1 } }),
    -- Green, and never-read, and grey.
    [6] = R(6, "Simple Kilt", "easy", nil, { { itemID = LINEN, quantity = 5 } }),
    [7] = R(7, "Unread Shirt", nil, nil, { { itemID = LINEN, quantity = 1 } }),
    [8] = R(8, "Grey Rag", "trivial", nil, { { itemID = LINEN, quantity = 1 } }),
    -- Same colour, same cost as the belt: the name decides.
    [9] = R(9, "Aaa Belt", "optimal", nil, { { itemID = LINEN, quantity = 2 }, { itemID = THREAD, quantity = 2 } }),
    -- Another profession.
    [10] = R(10, "Leather Strip", "optimal", LEATHER, { { itemID = LINEN, quantity = 1 } }),
}

ns.Recipes = {
    Get = function(_, id) return recipes[id] end,
    GetAny = function(_, id) return recipes[id] end,
    GetAll = function() return recipes end,
}

assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/SkillUp.lua"))("Blackthornes_TS", ns)

-- Profit.lua is the Profit tab's; only the craftable count is read here.
ns.Profit = { GetCraftableCount = function(_, recipeID)
    local most = math.huge
    for _, reagent in ipairs(recipes[recipeID].reagents) do
        most = math.min(most, math.floor((bags[reagent.itemID] or 0) / reagent.quantity))
    end
    return most
end }

local chunk = loadfile(lfs_cwd .. "/Logic/LevelUp.lua")
if not chunk then error("FAILED: Logic/LevelUp.lua is missing, so there is no levelling order") end
chunk("Blackthornes_TS", ns)

local LevelUp = ns.LevelUp

local function check(label, condition)
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function names(rows)
    local out = {}
    for i, row in ipairs(rows) do out[i] = row.name end
    return table.concat(out, ", ")
end

print("\nlevelling order")

local tailoring = { [TAILORING] = true, [TAILORING_OLD] = true }
local rows = LevelUp:GetRanked({ skillLines = tailoring })

print("  " .. names(rows))

check("orange first, cheapest first, name breaks a tie, unpriced last in its colour",
    names(rows) == "Aaa Belt, Linen Belt, Woolen Cape, Odd Gloves, "
        .. "Linen Bandana, Bolt of Woolen Cloth, Simple Kilt, Unread Shirt")

check("a cheap yellow never jumps an orange", rows[5].name == "Linen Bandana")
check("grey is left out unless asked for", rows[#rows].name ~= "Grey Rag")
check("both of Forever's IDs for one profession are kept", rows[3].skillLineID == TAILORING_OLD)
check("the other profession is left out", not names(rows):find("Leather Strip"))

print("\nthe cost is the Profit tab's cost")

local cape = rows[3]
check("the bolt counts at the cheaper of make (9s) or buy (20s)", cape.cost == 900)
check("it is the same number Cost.lua gives the Profit tab",
    cape.cost == ns.Cost:GetCraftCost(2).total)
check("a material with no price leaves the cost unknown, not free", rows[4].cost == nil)
check("belt: 2 linen at 1s and 2 vendor thread at 50c", rows[2].cost == 300)

print("\nfilters")

local withGrey = LevelUp:GetRanked({ skillLines = tailoring, includeTrivial = true })
check("grey goes last when shown", withGrey[#withGrey].name == "Grey Rag")

local craftable = LevelUp:GetRanked({ skillLines = tailoring, craftableOnly = true })
check("craftable only keeps what the bags make", names(craftable)
    == "Aaa Belt, Linen Belt, Linen Bandana, Unread Shirt")
check("the craftable count is carried on the row", craftable[1].craftableNow == 1 and craftable[3].craftableNow == 4)

local searched = LevelUp:GetRanked({ search = "BELT" })
check("search matches any case, across professions", names(searched) == "Aaa Belt, Linen Belt")

local everything = LevelUp:GetRanked({})
check("no profession given lists every profession", #everything == 9)

print("\nties never reshuffle")

local a = { name = "Same", tier = "optimal", cost = 100, recipeID = 1 }
local b = { name = "Same", tier = "optimal", cost = 100, recipeID = 2 }
check("recipe ID settles a full tie", LevelUp.Compare(a, b) and not LevelUp.Compare(b, a))
check("a row is never before itself", not LevelUp.Compare(a, a))

print("\n  all level up checks passed\n")
