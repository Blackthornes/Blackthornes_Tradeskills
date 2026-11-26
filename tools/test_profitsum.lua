-- How This Profit Adds Up (the owner said build it, 2026-11-26): one
-- profit sum everywhere. Profit:Sum lays out Analyse's parts and they add
-- up to its profit; the Queue and the craft pane count as the Profit tab
-- does (Profit:Counted); the tooltip's Profit Now counts the deposit and a
-- vendor that pays more; the profession window takes the same number
-- (CraftProfit.TakeCounted); a craft with random rolls has a range.
-- The setup is test_profitways.lua's.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "CreateFrame", "GetTime", "time", "C_Item", "UIParent" }
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

local BELT, LINEN, RECIPE, DUST, ESSENCE = 5000, 2589, 300, 10940, 10938

-- What a vendor pays is the eleventh return: 80c for the belt.
C_Item = { GetItemInfo = function(itemID)
    return "item " .. itemID, "link", 1, 1, 1, "", "", 1, "", "", itemID == BELT and 80 or 1
end }

local recipe = { recipeID = RECIPE, name = "Linen Belt", outputItemID = BELT,
    quantityMin = 1, quantityMax = 1, reagents = { { itemID = LINEN, quantity = 7 } } }

-- Two listings to sell: the first runs out and keeps its deposit, so one
-- deposit counts. A sale hands the deposit back (see the end).
local settings = { undercutCopper = 1, auctionCut = 0.05, expectedRelists = 2, minProfit = 0,
    staleAfterSeconds = 48 * 3600, valueOwnedMaterials = true, unscannedMarkupPercent = 50,
    priceUnscannedCrafts = true }

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterEvent = noop
local commands, printed = {}, {}
ns.RegisterCommand = function(name, _, fn) commands[name] = fn end
ns.Print = function(text) printed[#printed + 1] = text end
ns.PrintRaw = function(text) printed[#printed + 1] = text end
ns.Debug, ns.Warn = noop, noop

local priceTable = {}
ns.Config = {
    Get = function(_, key) return settings[key] end,
    GetCharacterKey = function() return "Me" end,
    GetPriceTable = function() return priceTable end,
}
ns.Recipes = {
    GetAll = function() return { [RECIPE] = recipe } end,
    Get = function() return recipe end,
    GetAny = function() return recipe, "Me" end,
    GetAccountWide = function() return { [RECIPE] = recipe } end,
    GetCharacterName = function() return "Me" end,
    IsDropped = function() return false end,
    Find = function() return { recipe } end,
    GetDisplayLink = function() return "[Linen Belt]" end,
}
ns.Inventory = {
    GetBagCount = function() return 0 end, GetCharacterBagCount = function() return 0 end,
    GetBankCount = function() return 0 end, GetOwnedCount = function() return 0 end,
    GetAltTotal = function() return 0 end,
}
ns.Vendor = { GetUnitPrice = function() return nil end }
ns.Scanner = { GetCommodityStatus = function() return true end }
ns.Auctions = { GetRoom = function() return nil, 0, 0, 0, 0, 0 end }

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Cost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)

-- A deposit of 3c a belt is known from the last listing, but a listing on
-- Forever never pays less than 1s, so the 1s is what is held and lost.
-- These checks set a 1s least deposit (Forever's rule from 2026-11-06 to
-- 2026-11-10) to test the floor; the 1c rule now is in test_mindeposit.lua.
ns.Posting = { MIN_DEPOSIT = 100, GetCachedUnitDeposit = function() return 3 end }

local Profit = ns.Profit

-- The belt disenchants to 2s of materials on average, and
-- needs Enchanting 50. Who can disenchant is set per check below.
local enchanterSkill
local disenchantable = true
ns.Disenchant = {
    IsDisenchantable = function() return disenchantable end,
    GetValue = function()
        if disenchantable then
            -- As Disenchant:GetValue hands them back since the value became
            -- an average: every outcome counted, the usual one marked likely.
            return 200, nil, { outcomes = {
                { itemID = DUST, counted = true, likely = true },
                { itemID = ESSENCE, counted = true, likely = false },
            } }
        end
    end,
    GetBestEnchanter = function() return enchanterSkill, enchanterSkill and "Ana" or nil end,
    GetItemFacts = function() return { skill = 50 } end,
}

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Printed(fragment)
    for _, line in ipairs(printed) do
        if tostring(line):find(fragment, 1, true) then return true end
    end
    return false
end

-- Linen at 10c: 70c of materials a belt. A rival lists it at 60c, under
-- the vendor's 80c, and a 3c deposit is known.
ns.Prices:Record(LINEN, 10, 10, 500, time(), 10, nil)
ns.Prices:Record(BELT, 65, 60, 4, time(), 60, nil)
ns.Prices:Record(DUST, 50, 50, 20, time() - 3 * 86400, 50, nil)

ns.Util.GetItemLabel = function(itemID) return "item " .. itemID end
assert(loadfile(lfs_cwd .. "/Logic/CraftedCost.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/CraftProfit.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/ProfitCard.lua"))("Blackthornes_TS", ns)
local Card = ns.ProfitCard

local function Adds(sum)
    local total = 0
    for _, line in ipairs(sum.lines) do total = total + line.amount end
    return total
end
local function Round(value) return math.floor(value + 0.5) end
local function Line(sum, label)
    for _, line in ipairs(sum.lines) do if line.label == label then return line end end
end

print("")
print("the parts add up to the profit, each way")

for _, method in ipairs({ "auction", "vendor", "disenchant" }) do
    enchanterSkill = 75
    local a = Profit:Analyse(RECIPE, nil, method)
    local sum = Profit:Sum(a)
    check(method .. ": the lines add up to the profit", Adds(sum), Round(a.profit))
    check(method .. ": the card's profit is the analysis's", sum.profit, a.profit)
end

local a = Profit:Analyse(RECIPE, nil, "auction")
local sum = Profit:Sum(a)
check("sold at the AH, it starts with Sells For", sum.lines[1].label, "Sells For")
check("which is the lowest posting", sum.lines[1].note, "The lowest posting right now")
check("the cut is 5% of the sale", Line(sum, "Auction Cut").note, "5% of the sale")
check("the deposit is there", Line(sum, "Deposit").amount, -100)
check("the linen is one line", Line(sum, "7 item 2589").amount, -70)
check("bought at today's price", Line(sum, "7 item 2589").note, "Bought, at today's price")
check("one craft makes one", Profit.YieldText(sum.yield), "1")

a = Profit:Analyse(RECIPE, nil, "vendor")
sum = Profit:Sum(a)
check("to a vendor: no cut", Line(sum, "Auction Cut"), nil)
check("and no deposit", Line(sum, "Deposit"), nil)
check("and it says a vendor pays it", sum.lines[1].note, "What a vendor pays")

check("a craft with no price has no sum", Profit:Sum({ priceable = false }), nil)

print("")
print("the card says what the sum says")

a = Profit:Analyse(RECIPE, nil, "auction")
local rows = Card.Rows(Profit:Sum(a))
check("its last row is the profit", rows[#rows].kind, "profit")
check("the profit shown is the analysis's", rows[#rows].value, Card.Signed(a.profit))
check("Makes comes before it", rows[#rows - 1].value, "1 a craft")
check("no range for a plain craft", rows[#rows].range, nil)

print("")
print("the Queue and the craft pane count as the Profit tab does")

settings.profitBy = "best"
enchanterSkill = 75
check("Best is counted as Best", Profit:CountedMethod(), "best")
check("so the Queue's profit is the Profit tab's", Profit:Counted(RECIPE).profit,
    Profit:Analyse(RECIPE, nil, Profit:GetMethod()).profit)
settings.profitBy = "auction"
check("Auction is counted as the sale", Profit:CountedMethod(), nil)
check("a vendor that pays more still counts", Profit:Counted(RECIPE).via, "vendor")
settings.profitBy = nil

print("")
print("the profession window shows the same number")

settings.profitBy = "auction"
local figures = ns.CraftProfit:For(RECIPE)
local counted = Profit:Counted(RECIPE)
check("its profit is the counted one", figures.profit, counted.profit)
check("Sells For less Mats Cost is the profit", figures.sells - figures.cost, counted.profit)
check("and it says so", figures.counted, true)
settings.profitBy = nil

print("")
print("Profit Now counts the deposit")

-- The belt at 2s from a rival, over what a vendor pays: the listing is the sale.
ns.Prices:Record(BELT, 205, 200, 4, time(), 200, nil)
local net = math.floor(Profit:NetFromListing(BELT, 200))
check("a listing at 2s brings in 2s less the cut and the deposit", net, 200 - 10 - 100)
check("Profit Now at 2s is that, less 70c", ns.CraftedCost:ProfitNowAt(BELT, 200), net - 70)
check("to a vendor, no cut or deposit", ns.CraftedCost:ProfitNowAt(BELT, 80, true), 10)
local tipLines = ns.CraftedCost:Lines(BELT)
local profitLine
for _, line in ipairs(tipLines) do if line[1] == "Profit now" then profitLine = line end end
check("the tooltip has its Profit Now line", profitLine ~= nil, true)
local sale = Profit:Analyse(RECIPE)
check("on the same price the Profit tab's sale counts",
    profitLine and profitLine[2]:find(ns.Util.FormatMoney(math.abs(Round(sale.profitPerUnit)),
        { short = true, noColor = true }), 1, true) ~= nil, true)

print("")
print("random rolls give a range")

ns.Prices:RecordSuffix(BELT, 1001, 150, 150, 150, 2, time())
ns.Prices:RecordSuffix(BELT, 1002, 900, 900, 900, 2, time())
a = Profit:Analyse(RECIPE, nil, "auction")
local low, high = Profit:RollRange(a)
check("the cheapest roll's profit", low and Round(low), Round(150 - 150 * 0.05 - a.deposit - a.totalCost))
check("the dearest roll's profit", high and Round(high), Round(900 - 900 * 0.05 - a.deposit - a.totalCost))
sum = Profit:Sum(a)
check("the sum carries it", sum.low, low)
rows = Card.Rows(sum)
check("and the card shows it under the profit", rows[#rows].range, Card.RangeText(Round(low), Round(high)))
a = Profit:Analyse(RECIPE, nil, "vendor")
check("sold to a vendor there is no range", Profit:RollRange(a), nil)


print("")
print("the card opens, in the fake game")

do
    local function Stub()
        local object = { shown = false, height = 0, text = "" }
        function object:Show() self.shown = true end
        function object:Hide() self.shown = false end
        function object:IsShown() return self.shown end
        function object:SetShown(on) self.shown = on and true or false end
        function object:SetHeight(h) self.height = h end
        function object:SetText(t) self.text = t end
        function object:GetStringHeight() return 12 end
        function object:CreateTexture() return Stub() end
        return setmetatable(object, { __index = function() return noop end })
    end
    local oldCreate, oldTheme, oldParent = CreateFrame, ns.Theme, UIParent
    CreateFrame = function() return Stub() end
    UIParent = Stub()
    local made = {}
    ns.Theme = setmetatable({
        CreateLabel = function() local l = Stub(); made[#made + 1] = l; return l end,
        Unpack = function() return 1, 1, 1, 1 end,
        TextWidth = function() return 60 end,
    }, { __index = function() return noop end })
    ns.ProfitCard = nil
    assert(loadfile(lfs_cwd .. "/UI/ProfitCard.lua"))("Blackthornes_TS", ns)
    local card = ns.ProfitCard
    a = Profit:Analyse(RECIPE, nil, "auction")
    check("a click opens the card", card:Show(a), true)
    check("and it shows", card:IsShown(), true)
    check("one row a line, plus Makes and Profit", #card.rows, #Profit:Sum(a).lines + 2)
    check("its title", card.title.text, "How This Profit Adds Up")
    check("it grows to its rows", card.frame.height > 100, true)
    check("an unpriced craft opens nothing", card:Show({ priceable = false }), false)
    card:Hide()
    check("and it closes", card:IsShown(), false)
    CreateFrame, ns.Theme, UIParent = oldCreate, oldTheme, oldParent
end

print("")
print("every profit click goes to the card")

local function Source(path)
    local file = assert(io.open(lfs_cwd .. "/" .. path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end
check("the Profit tab's rows", Source("UI/Tab_Profit.lua"):find("ns.ProfitCard:Show(fresh", 1, true) ~= nil, true)
check("the detail pane's Profit line", Source("UI/Tab_Profit.lua"):find("ns.ProfitCard:ShowRecipe(selected.recipeID", 1, true) ~= nil, true)
check("the Queue's rows", Source("UI/Tab_Queue.lua"):find("ns.ProfitCard:ShowRecipe(entry.recipeID", 1, true) ~= nil, true)
check("the card is in the TOC", Source("Blackthornes_TS.toc"):find("UI\\ProfitCard.lua", 1, true) ~= nil, true)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "profit sum checks failed")
