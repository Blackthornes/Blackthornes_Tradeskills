-- Favourites on the Prices tab (2026-10-06): star an item to keep an
-- eye on it, and tick Favourites only to see just the starred ones. Kept for
-- the whole account by item; a starred item with no price still shows.

local SPIDER_SILK, LINEN, WOOL, NEVER_PRICED = 3182, 2589, 2592, 4338

local db = { settings = {} }
local prices = {
    [SPIDER_SILK] = { market = 900 }, [LINEN] = { market = 20 }, [WOOL] = { market = 60 },
}

local ns = {
    Theme = {}, Widgets = {},
    Util = { HasFunction = function() return false end },
    UI = { RegisterTab = function() end },
    db = db,
    Config = {
        GetPriceTable = function() return prices end,
        Get = function(_, key) return db.settings[key] end,
    },
    Debug = function() end, Warn = function() end,
}

-- The real favourites code, from Data/Prices.lua.
ns.NewModule = function(name) local module = {}; ns[name] = module; return module end
ns.RegisterCommand = function() end
assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)

-- The tab only needs what it reads per row.
ns.Prices.GetAge = function() return 60 end
ns.Prices.GetSalesPerDay = function() return nil end

assert(loadfile(lfs_cwd .. "/UI/Columns.lua"))("Blackthornes_TS", ns)

assert(loadfile(lfs_cwd .. "/UI/Tab_Prices.lua"))("Blackthornes_TS", ns)

local failures = 0
local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-52s %-8s %s"):format(label, tostring(got), ok and "ok" or ("FAILED, expected " .. tostring(expected))))
end

local function Found(rows, itemID)
    for _, row in ipairs(rows) do if row.itemID == itemID then return true end end
    return false
end

print("favourites on the Prices tab")

check("nothing is starred at first",                    ns.Prices:IsFavourite(SPIDER_SILK), false)
check("Favourites only with none shows nothing",        #ns.UI._PricesList("", true), 0)

ns.Prices:SetFavourite(SPIDER_SILK, true, "Spider Silk")
check("a star sticks",                                   ns.Prices:IsFavourite(SPIDER_SILK), true)
check("kept by item, with its name",                     db.favouritePrices[SPIDER_SILK], "Spider Silk")

local only = ns.UI._PricesList("", true)
check("Favourites only shows the starred item",          Found(only, SPIDER_SILK), true)
check("and nothing else",                                #only, 1)
check("every item still shows without the tick",         #ns.UI._PricesList("", false), 3)

ns.Prices:SetFavourite(NEVER_PRICED, true, "Iron Buckle")
local unpriced = ns.UI._PricesList("", true)
check("a starred item with no price still shows",        Found(unpriced, NEVER_PRICED), true)
check("found by its saved name",                         #ns.UI._PricesList("buckle", true), 1)

-- Starring again without a name keeps the saved one.
ns.Prices:SetFavourite(SPIDER_SILK, true, nil)
check("starring again keeps the name",                   db.favouritePrices[SPIDER_SILK], "Spider Silk")

ns.Prices:SetFavourite(SPIDER_SILK, false)
check("a star comes off",                                ns.Prices:IsFavourite(SPIDER_SILK), false)
check("and the item leaves Favourites only",             Found(ns.UI._PricesList("", true), SPIDER_SILK), false)

-- A price pruned for age never takes the star with it.
prices[LINEN].seen = 0
ns.Prices:SetFavourite(LINEN, true, "Linen Cloth")
prices[LINEN] = nil
check("a pruned price keeps its star",                   ns.Prices:IsFavourite(LINEN), true)
check("and the item still shows",                        Found(ns.UI._PricesList("", true), LINEN), true)

ns.UI._PricesList("", false)

if failures > 0 then error(("%d favourites check(s) failed"):format(failures)) end
print("  favourites: all checks passed")
