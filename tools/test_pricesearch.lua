-- The Prices tab search finds items the game has not loaded yet, by the name
-- the addon saved itself (sales history, what your recipes make). It must not
-- ask the game about every priced item to do it: the item cache is small.

local LINEN_BAG, SILK, MYSTERY = 4238, 4306, 9999

local ns = {
    Theme = {}, Widgets = {},
    Util = {
        -- The client holds nothing: every item is "not loaded".
        HasFunction = function() return false end,
    },
    UI = { RegisterTab = function() end },
    Prices = {
        GetTable = function()
            return { [LINEN_BAG] = { market = 100 }, [SILK] = { market = 50 }, [MYSTERY] = { market = 10 } }
        end,
        GetAge = function() return 60 end,
        GetSalesPerDay = function() return nil end,
    },
    Mail = {
        GetLedger = function()
            return { entries = { { kind = "sold", itemID = SILK, name = "Silk Cloth" } } }
        end,
    },
    db = { characters = {
        ["Tester-Realm"] = { recipes = { [1] = { name = "Linen Bag", outputItemID = LINEN_BAG } } },
    } },
}

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

print("the Prices tab search, items the game has not loaded")

local bag = ns.UI._PricesList("linen")
check("a recipe's output is found by its name",       Found(bag, LINEN_BAG), true)
check("and nothing else",                              #bag, 1)

local silk = ns.UI._PricesList("silk")
check("a sold item is found by its ledger name",       Found(silk, SILK), true)

check("an item with no saved name is not",             #ns.UI._PricesList("mystery"), 0)
check("an empty search shows everything",              #ns.UI._PricesList(""), 3)

ns.UI._PricesList("")

if failures > 0 then error(("%d price search check(s) failed"):format(failures)) end
print("  price search: all checks passed")
