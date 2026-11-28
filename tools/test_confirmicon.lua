-- The posting confirmation's words.
--
-- The house rule is that the question says exactly "Average Market Value",
-- "Lowest Market Posting", "Posting at" and "List it at this price, or skip
-- it.", with the item's icon beside them, not as a line of its own.

local ns = {}
ns.COLORS = setmetatable({ accent = "ffc8a44d" }, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() return true end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

ns.Util = {
    Clamp = function(v, l, h) return math.max(l, math.min(h, v)) end,
    Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
    Comma = tostring,
    FormatMoney = function(c) return tostring(c) end,
    FormatAge = function() return "" end,
    FormatAgeAgo = function() return "" end,
    GetItemLabel = function(i) return "item" .. tostring(i) end,
    GetItemIcon = function(i) if i == 2589 then return 132889 end return nil end,
    GetMaxStackSize = function() return 20 end,
    UnitPriceFromStack = function(_, buyout, quantity) return math.floor(buyout / (quantity or 1)) end,
    HasFunction = function() return false end,
    ItemAuctionPrice = function(p) if p < 100 then return 100 end return math.floor(p / 100) * 100 end,
    IsItemAuctionPrice = function(p) return p >= 100 and p % 100 == 0 end,
    WhenAuctionReady = function(action) action() end,
}

local priceTable = {}
ns.Config = {
    Get = function() return nil end,
    GetPriceTable = function() return priceTable end,
    GetRealmKey = function() return "TestRealm" end,
}
ns.db = {}
ns.Cost = { FindRecipeForItem = function() return nil end }
ns.Cost.FindAnyRecipeForItem = ns.Cost.FindRecipeForItem
ns.Auctions = { GetPostedCount = function() return 0 end }
ns.AHQueue = { PRIORITY = { urgent = 10, normal = 50, scan = 90 } }

time = time or os.time
GetTime = function() return 100 end
Enum = { ItemCommodityStatus = { Commodity = 2 }, BagIndex = {} }
UnitName = function() return "Tester" end
GetRealmName = function() return "TestRealm" end
C_Timer = {
    NewTimer = function() return { Cancel = function() end } end,
    After = function() end,
    NewTicker = function() return { Cancel = function() end } end,
}

assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Scanner.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Posting.lua"))("Blackthornes_TS", ns)

local Prices, Posting = ns.Prices, ns.Posting

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function lines(text)
    local out = {}
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then out[#out + 1] = line end
    end
    return out
end

print("\nthe posting confirmation's words")

-- What the question window was handed (tools/test_postconfirm.lua checks the
-- window itself: the icon, the buttons, Escape).
local asked
ns.PostConfirm = { Show = function(_, ask) asked = ask; return true end }

Prices:Record(2589, 500, 450, 20, time(), 450, nil)
Posting:Confirm(2589, 1, 400, { state = "fresh" })

check("the item goes along for its icon", asked and asked.itemID == 2589)
local l = lines(asked.text)
check("the text is still exactly four lines", #l == 4
    and l[1] == "Average Market Value: 500"
    and l[2] == "Lowest Market Posting: 450"
    and l[3] == "Posting at: 400, item2589"
    and l[4] == "List it at this price, or skip it.")

ns.PostConfirm = nil

print(("\n%d check(s) passed\n"):format(checks))
