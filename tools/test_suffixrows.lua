-- The Prices tab shows each random suffix as a row under its item (a
-- player's report, the owner said build it, 2026-11-20): a search for
-- "cabalist chestpiece" listed only the plain item, though "of the Bear"
-- and "of the Eagle" each had a price of their own.
--
-- What must hold:
--   1. With no search an item with suffixes stays closed, saying how many.
--   2. A search opens it, its suffixes under it, sorted like the list.
--   3. A search for a suffix's name finds the item, showing only that suffix,
--      also when it runs from the item's name into the suffix's.
--   4. Closed by hand it stays closed; opened by hand it stays open.
--   5. An item without suffixes is untouched; unknown names read "Suffix N".

local CHEST, LEATHER = 7531, 4304
local BEAR, EAGLE, BOAR, ODD = 14322, 14330, 14340, 14999
local now = 1000000
time = function() return now end

local function Fresh(market, quantity) return { market = market, min = market, quantity = quantity, seen = now - 60 } end

local priceTable = {
    [CHEST] = { market = 12399, min = 12100, quantity = 13, seen = now,
                suffixes = { [BEAR] = Fresh(22150, 1), [EAGLE] = Fresh(32400, 1),
                             [BOAR] = Fresh(22150, 2), [ODD] = Fresh(5000, 1) } },
    [LEATHER] = { market = 1840, min = 1795, quantity = 212, seen = now },
}
local tails = { [BEAR] = " of the Bear", [EAGLE] = " of the Eagle", [BOAR] = " of the Boar" }
local asked = 0

local ns = {
    Theme = {}, Widgets = {},
    Util = { HasFunction = function() return false end },
    UI = { RegisterTab = function() end },
    Prices = {
        GetTable = function() return priceTable end,
        GetAge = function() return 60 end,
        GetSalesPerDay = function() return nil end,
        SuffixTails = function() return tails end,
        SuffixCount = function(_, itemID)
            local n = 0
            for _ in pairs(priceTable[itemID].suffixes or {}) do n = n + 1 end
            return n
        end,
        SuffixRows = function(_, itemID)
            asked = asked + 1
            local rows = {}
            for suffix, entry in pairs(priceTable[itemID].suffixes) do
                rows[#rows + 1] = { suffix = suffix, market = entry.market, min = entry.min,
                    quantity = entry.quantity, seen = entry.seen,
                    name = tails[suffix] and ("Cabalist Chestpiece" .. tails[suffix]) or nil }
            end
            return rows
        end,
    },
    Mail = { GetLedger = function()
        return { entries = { { itemID = CHEST, name = "Cabalist Chestpiece" },
                             { itemID = LEATHER, name = "Thick Leather" } } }
    end },
    db = { characters = {} },
}

assert(loadfile(lfs_cwd .. "/UI/Columns.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/Tab_Prices.lua"))("Blackthornes_TS", ns)

local failures = 0
local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-56s %-22s %s"):format(label, tostring(got), ok and "ok" or ("FAILED, expected " .. tostring(expected))))
end

local function Names(rows)
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = row.kid and ("  " .. row.name) or tostring(row.itemID) end
    return table.concat(out, ",")
end

local _, state = ns.UI._PricesWidgets()

print("suffix rows on the Prices tab")

local rows = ns.UI._PricesList("")
check("no search: items only", Names(rows), CHEST .. "," .. LEATHER)
check("the item says how many suffixes", rows[1].suffixCount, 4)
check("and is closed", rows[1].open, false)
check("no suffix names asked for while closed", asked, 0)
check("an item without suffixes has none", rows[2].suffixCount, 0)

rows = ns.UI._PricesList("cabalist chestpiece")
check("a search opens the item, dearest first",
    Names(rows), CHEST .. ",  of the Eagle,  of the Bear,  of the Boar,  Suffix " .. ODD)
check("a suffix row keeps its own price", rows[2].market, 32400)
check("and its own listed count", rows[4].quantity, 2)
check("and knows its item", rows[2].itemID, CHEST)

rows = ns.UI._PricesList("of the bear")
check("a suffix's name finds its item, only that suffix", Names(rows), CHEST .. ",  of the Bear")

rows = ns.UI._PricesList("chestpiece of the b")
check("a search from the item's name into the suffix's", Names(rows), CHEST .. ",  of the Bear,  of the Boar")

check("a suffix name finds nothing else", #ns.UI._PricesList("of the whale"), 0)
check("other items search as before", Names(ns.UI._PricesList("leather")), tostring(LEATHER))

for id = 1, 40 do priceTable[50000 + id] = { market = id, suffixes = { [BEAR] = Fresh(id, 1) } } end
ns.Mail.GetLedger = function()
    local entries = { { itemID = CHEST, name = "Cabalist Chestpiece" } }
    for id = 1, 40 do entries[#entries + 1] = { itemID = 50000 + id, name = "Cabalist Boots " .. id } end
    return { entries = entries }
end
asked = 0
rows = ns.UI._PricesList("cabalist")
check("a broad search leaves its items closed", #rows, 41)
check("and asks for no suffix names", asked, 0)
for id = 1, 40 do priceTable[50000 + id] = nil end

state.open[CHEST] = false
check("closed by hand stays closed while searching", Names(ns.UI._PricesList("chestpiece")), tostring(CHEST))
state.open[CHEST] = true
rows = ns.UI._PricesList("")
check("opened by hand stays open with no search", #rows, 6)
state.open[CHEST] = nil

print("drawing the rows")

ns.Theme.SetRowName = function(label, text) label.text = text end
ns.Theme.SetItemIcon = function() end
ns.Theme.Unpack = function(key) return key end
ns.Theme.SetMoneyText = function(label, value) label.text = tostring(value) end
ns.Util.GetItemLabel = function() return "|cff1eff00[Cabalist Chestpiece]|r" end
ns.Util.Comma = function(n) return tostring(n) end
ns.Util.FormatAge = function() return "1m" end
ns.Prices.IsStale = function() return false end
ns.COLORS = { muted = "ff7a8089", warn = "ffe8c15a" }

local function Label()
    return { text = "", SetText = function(self, t) self.text = t end,
             SetTextColor = function(self, c) self.color = c end }
end
local function Part()
    return { SetShown = function(self, on) self.shown = on end }
end
local function Row()
    local row = { name = Label(), icon = Part(), star = Part(), fold = Part(), cells = {} }
    row.star.SetItem = function() end
    row.name.SetPoint = function(self, _, x) self.x = x end
    row.fold.text = Label()
    for _, key in ipairs({ "market", "min", "quantity", "liquidity", "trend", "age" }) do row.cells[key] = Label() end
    row.columnsVersion = ns.Columns.version
    return row
end

local _, _, updateRow = ns.UI._PricesWidgets()
rows = ns.UI._PricesList("cabalist chestpiece")
local itemRow, bearRow = Row(), Row()
updateRow(itemRow, rows[1])
updateRow(bearRow, rows[3])
check("the item row says how many", itemRow.name.text:find("4 suffixes", 1, true) ~= nil, true)
check("and shows a -, being open", itemRow.fold.shown and itemRow.fold.text.text, "-")
check("a suffix row has no star or icon", (bearRow.star.shown or bearRow.icon.shown) and true or false, false)
check("nor a + of its own", bearRow.fold.shown, false)
check("it sits past the item's +", bearRow.name.x, 60)
check("in the item's colour", bearRow.name.text, "|cff1eff00of the Bear|r")
check("its own market", bearRow.cells.market.text, "22150")
check("movement is the item's: --", bearRow.cells.liquidity.text, "--")
check("so is the trend", bearRow.cells.trend.text, "--")
rows = ns.UI._PricesList("")
updateRow(itemRow, rows[1])
check("closed, it shows a +", itemRow.fold.text.text, "+")
local leatherRow = Row()
updateRow(leatherRow, rows[2])
check("an item without suffixes has no +", leatherRow.fold.shown, false)
check("and its name where it always was", leatherRow.name.x, 46)

if failures > 0 then error(("%d suffix row check(s) failed"):format(failures)) end
print("  suffix rows: all checks passed")
