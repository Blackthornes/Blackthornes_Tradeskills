-- Tests for the favor goal (Logic/MerchantsFavor.lua) and the auction house
-- drawer's Favors view (UI/FavorsView.lua): the plan, its steps, the chime
-- each tenth, the shopping list and Buy Next, one listing a click.


local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
local handlers = {}
ns.RegisterEvent = function(_, event, fn) handlers[event] = handlers[event] or {}; table.insert(handlers[event], fn) end
local function Fire(event, ...)
    for _, fn in ipairs(handlers[event] or {}) do fn(nil, event, ...) end
end

local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end

-- Put back at the end: every suite shares one Lua runtime.
local saved = { C_Item = C_Item, GetTime = GetTime, CreateFrame = CreateFrame, GameTooltip = GameTooltip,
                C_Timer = C_Timer, C_CurrencyInfo = C_CurrencyInfo, GetMoney = GetMoney }

local clock = 100
GetTime = function() return clock end
time = time or os.time

local later = {}
C_Timer = { After = function(_, fn) later[#later + 1] = fn end }
local function Flush()
    local run = later
    later = {}
    for _, fn in ipairs(run) do fn() end
end

local LINEN, LEATHER, PEACEBLOOM, SILVERLEAF = 2589, 2318, 2447, 765
local TEXTILES, HERBS, SEALED, SOMETHING = 248684, 248690, 249000, 248600

-- itemID -> name, max stack
local items = {
    [TEXTILES] = { "Waylaid Crate: Apprentice Textiles", 5 },
    [HERBS] = { "Waylaid Crate: Apprentice Herbs", 5 },
    [SOMETHING] = { "Some Other Forever Item", 1 },
    [SEALED] = { "Sealed Apprentice Crate", 5 },
    [LINEN] = { "Linen Cloth", 20 },
    [LEATHER] = { "Light Leather", 20 },
    [PEACEBLOOM] = { "Peacebloom", 20 },
    [SILVERLEAF] = { "Silverleaf", 20 },
}

local asked = {}
C_Item = {
    GetItemInfo = function(itemID)
        local item = items[itemID]
        if not item then return nil end
        return item[1], "link" .. itemID, 1, 10, 1, "Trade Goods", "Cloth", item[2]
    end,
    RequestLoadItemDataByID = function(itemID) asked[itemID] = true end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)

-- Copper for one, the cheapest listing.
local prices = {
    [TEXTILES] = 2000,
    [HERBS] = 1000,
    [LINEN] = 30,
    [LEATHER] = 80,
    [PEACEBLOOM] = 10,
    [SILVERLEAF] = 5,
}

local config = {}
ns.Config = {
    Get = function(_, key) return config[key] end,
    Set = function(_, key, value) config[key] = value end,
}
-- Items whose record says none are listed now.
local noneListed = {}
ns.Prices = {
    GetValue = function(_, itemID) return prices[itemID] end,
    ListedNow = function(_, itemID)
        if noneListed[itemID] then return nil, true end
        return prices[itemID], false
    end,
    ListedCounts = function(_, itemID)
        if noneListed[itemID] then return nil, nil end
        return 4, 9
    end,
    Count = function() return 6 end,
}
-- Shops, as Cost prices them: a vendor's price beats the auction house's.
-- itemID -> { price, limited }
local shops = {}
local makes = {}
ns.Cost = {
    GetReagentUnitCost = function(_, itemID)
        if shops[itemID] then return shops[itemID][1], "vendor" end
        return prices[itemID], "buy"
    end,
    -- Made from bought materials: itemID -> { recipeID, copper for one }.
    FindAnyRecipeForItem = function(_, itemID) return makes[itemID] and makes[itemID][1] end,
    GetMaterialValue = function(_, recipeID)
        for _, make in pairs(makes) do
            if make[1] == recipeID then return make[2] end
        end
    end,
}
ns.Vendor = { IsLimited = function(_, itemID) return shops[itemID] ~= nil and shops[itemID][2] == true end }

local bags = {}
ns.Inventory = {
    GetBagCounts = function() return bags end,
    GetBagCount = function(_, itemID) return bags[itemID] or 0 end,
}

ns.db = {}

assert(loadfile(lfs_cwd .. "/Data/WaylaidCrates.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/MerchantsFavor.lua"))("Blackthornes_TS", ns)

local saved2 = { C_AuctionHouse = C_AuctionHouse, PlaySound = PlaySound }
local MerchantsFavor = ns.MerchantsFavor

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

-- Merchant's Favor as the game lists it, before its ID is known.
local favor = 40
C_CurrencyInfo = {
    GetCurrencyListSize = function() return 2 end,
    GetCurrencyListInfo = function(index)
        if index == 1 then return { name = "Other", isHeader = true } end
        return { name = "Merchant's Favor", quantity = favor }
    end,
}
local sounds = {}
PlaySound = function(id) sounds[#sounds + 1] = id; return true end

--------------------------------------------------------------------------------
print("\nthe goal")

check("no goal to start", MerchantsFavor.Goal() == nil and MerchantsFavor:GetPlan() == nil)
MerchantsFavor:SetGoal("100.7")
check("a typed goal is a whole number", MerchantsFavor.Goal() == 100 and config.favorGoal == 100)
MerchantsFavor:SetGoal(0)
check("0 clears it", MerchantsFavor.Goal() == nil and config.favorGoal == nil)
MerchantsFavor:SetGoal(100)
check("favor is read from the currency list by name", MerchantsFavor:FavorHave() == 40)

--------------------------------------------------------------------------------
print("\nthe plan")

local plan = MerchantsFavor:GetPlan()
local best = plan.best
check("60 still to go", plan.goal == 100 and plan.have == 40 and plan.need == 60 and not plan.reached)
check("the cheapest favor is the crate picked",
    best == MerchantsFavor:GetRows({ skipOverStack = true })[1] or best.key == MerchantsFavor:GetRows({ skipOverStack = true })[1].key)
check("enough crates for the favor", plan.crates == math.ceil(60 / best.favor))
local each = best.cratePrice + best.best.cost - best.money
check("gold is a crate and a bundle each, less the silver back", plan.gold == plan.crates * each)

bags[best.itemID] = 2
bags[best.best.itemID] = best.best.count * 3
plan = MerchantsFavor:GetPlan()
check("crates and materials held come off the gold", plan.cratesHave == 2 and plan.bundlesHave == 3
    and plan.gold == plan.crates * each - 2 * best.cratePrice - 3 * best.best.cost)

local steps, left = MerchantsFavor.Steps(plan)
check("a crate and a bundle a step", #steps == plan.crates * 2 and steps[1].crate and not steps[2].crate)
check("what is held is done", steps[1].done and steps[3].done and not steps[5].done
    and steps[2].done and steps[4].done and steps[6].done and not steps[8].done)
check("and the rest is left", left == (plan.crates - 2) + (plan.crates - 3))
check("a bundle step buys the whole bundle", steps[2].count == best.best.count
    and steps[2].price == (best.best.buy or best.best.cost))
bags[best.itemID], bags[best.best.itemID] = nil, nil

favor = 100
plan = MerchantsFavor:GetPlan()
check("at the goal it is reached and needs nothing", plan.reached and plan.need == 0 and not plan.best)
check("no steps then", #MerchantsFavor.Steps(plan) == 0)
favor = 40

--------------------------------------------------------------------------------
print("\nthe chime")

MerchantsFavor.goalFor, MerchantsFavor.goalTenth = nil, nil
check("the first look only notes where it stands", MerchantsFavor:CheckGoal() == nil and #sounds == 0)
check("nothing new, no sound", MerchantsFavor:CheckGoal() == nil and #sounds == 0)
favor = 52
check("a new tenth chimes", MerchantsFavor:CheckGoal() == "tenth" and sounds[1] == MerchantsFavor.SOUNDS.tenth[1])
favor = 30
check("a dip plays nothing", MerchantsFavor:CheckGoal() == nil and #sounds == 1)
favor = 55
check("climbing back to a tenth heard plays nothing", MerchantsFavor:CheckGoal() == nil and #sounds == 1)
for k in pairs(printed) do printed[k] = nil end
favor = 104
check("the goal cheers", MerchantsFavor:CheckGoal() == "goal" and sounds[2] == MerchantsFavor.SOUNDS.goal[1]
    and printed[1] == "Favor goal reached!")
check("once", MerchantsFavor:CheckGoal() == nil and #sounds == 2)
MerchantsFavor:SetGoal(200)
check("a new goal starts quiet", MerchantsFavor:CheckGoal() == nil and #sounds == 2)
MerchantsFavor:SetGoal(100)
favor = 40

--------------------------------------------------------------------------------
print("\nadd to a list")

check("without shopping lists it says so", select(2, MerchantsFavor:AddToList()) == "Shopping lists aren't ready yet.")
local made = {}
ns.ShoppingLists = {
    All = function() return made end,
    Make = function(_, name) made[#made + 1] = { name = name, items = {} }; return #made end,
    Add = function(_, index, itemID, want) table.insert(made[index].items, { id = itemID, want = want }) end,
    SetWant = function(_, index, itemID, want)
        for _, item in ipairs(made[index].items) do
            if item.id == itemID then item.want = want; return true end
        end
        return false
    end,
}
plan = MerchantsFavor:GetPlan()
local index = MerchantsFavor:AddToList(plan)
local list = made[index]
check("a Merchant's Favor list", list and list.name == "Merchant's Favor" and #list.items == 2)
check("with the crates and the material", list.items[1].id == best.itemID and list.items[1].want == plan.crates
    and list.items[2].id == best.best.itemID and list.items[2].want == plan.crates * best.best.count)
check("a second click fills the same list, never doubles", MerchantsFavor:AddToList(plan) == index
    and #made == 1 and #list.items == 2 and list.items[1].want == plan.crates)

--------------------------------------------------------------------------------
print("\nthe crate tooltip's row")

check("a crate has its row", MerchantsFavor:RowForItem(best.itemID).key == best.key)
check("anything else has none", MerchantsFavor:RowForItem(LINEN) == nil and MerchantsFavor:RowForItem(nil) == nil)

--------------------------------------------------------------------------------
print("\nBuy Next")

local searched, started, confirmed, cancelled = {}, {}, {}, 0
ns.UI = { SearchAuctionHouse = function(_, itemID, count) searched[#searched + 1] = { itemID, count } end }
C_AuctionHouse = {
    StartCommoditiesPurchase = function(itemID, count) started[#started + 1] = { itemID, count } end,
    ConfirmCommoditiesPurchase = function(itemID, count) confirmed[#confirmed + 1] = { itemID, count } end,
    CancelCommoditiesPurchase = function() cancelled = cancelled + 1 end,
    GetItemCommodityStatus = function() return 2 end,
}
local money = 1000000
GetMoney = function() return money end
assert(loadfile(lfs_cwd .. "/UI/FavorsView.lua"))("Blackthornes_TS", ns)
local View = ns.FavorsView

View:BuyNext()
check("the first step is a crate, found by a search", #searched == 1 and searched[1][1] == best.itemID
    and searched[1][2] == 1 and #started == 0)

bags[best.itemID] = 1
View:BuyNext()
check("with the crate held, the bundle is bought as a stack", #started == 1
    and started[1][1] == best.best.itemID and started[1][2] == best.best.count and View.pending.phase == "asking")
View:BuyNext()
check("a second click before the price comes does nothing", #started == 1 and #confirmed == 0)
View:PriceUpdated(1234)
check("the price comes in", View.pending.phase == "quoted" and View.pending.total == 1234)
money = 1000
View:BuyNext()
check("short of gold, Pay buys nothing", #confirmed == 0 and View.pending.phase == "quoted")
money = 1000000
View:BuyNext()
check("Pay buys that one listing", #confirmed == 1 and confirmed[1][1] == best.best.itemID
    and View.pending.phase == "buying")
View:Succeeded()
check("bought, it counts toward the steps before it shows in the bags",
    View.pending == nil and View:Extra(best.best.itemID) == best.best.count)
local viewSteps = View:Steps()
check("so the next step is the second crate", View.NextStep(viewSteps) == viewSteps[3])
bags[best.best.itemID] = best.best.count
check("once it arrives it is not counted twice", View:Extra(best.best.itemID) == 0)

C_AuctionHouse.GetItemCommodityStatus = function() return 1 end
check("an item sold one at a time is searched for", View.Kind({ itemID = LINEN, count = 20 }) == "search")
C_AuctionHouse.GetItemCommodityStatus = function() return 2 end

bags[best.itemID] = 2
View:BuyNext()
View:Unavailable()
check("nobody selling lets the buy go", View.pending == nil
    and printed[#printed]:find("Nobody is selling", 1, true) ~= nil)
View:BuyNext()
View:PriceUpdated(500)
View:Cancel()
check("Cancel tells the game", View.pending == nil and cancelled == 1)

bags[best.itemID], bags[best.best.itemID] = nil, nil
MerchantsFavor:SetGoal(nil)
check("with no goal there are no steps", #View:Steps() == 0)

for _, key in ipairs({ "C_Item", "GetTime", "CreateFrame", "GameTooltip", "C_Timer", "C_CurrencyInfo", "GetMoney" }) do
    _G[key] = saved[key]
end
C_AuctionHouse, PlaySound = saved2.C_AuctionHouse, saved2.PlaySound
ns.ShoppingLists, ns.UI = nil, nil

print(("\n%d checks passed"):format(checks))
