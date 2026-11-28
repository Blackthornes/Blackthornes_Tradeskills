-- Shift-click List on the Sell list (the owner said build it, 2026-11-28).
--
-- "Bypass Disallowed Postings:" for one listing: the Shift-click lists that
-- item past the floor, the cost guards and every keep, and nothing else.
--   * the setting stays off, and the list itself still holds every row;
--   * only that item's listing steps past the floor and the early refusal;
--   * a plain click on it, a listing of it, or two minutes end it;
--   * a refusal at the open Sell list says how to list it anyway;
--   * the whole stack is what it lists.
local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end

--------------------------------------------------------------------------------
-- A player with bags
--------------------------------------------------------------------------------

-- bags[bag][slot] = { itemID, stackCount, isLocked }
local bags = {}
local commodities = {}
local prices = {}
local bindTypes = {}
local reserved = {}
local recipes = {}

C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local entry = bags[bag] and bags[bag][slot]
        if not entry then return nil end
        return {
            itemID = entry.itemID,
            stackCount = entry.stackCount,
            isLocked = entry.isLocked and true or false,
        }
    end,
}

-- The client's own item data, in the order C_Item.GetItemInfo returns it.
-- bindType is the fourteenth, which is the one under test here; the vendor
-- price is deliberately zero so no loss floor muddies these rows.
C_Item = {
    GetItemInfo = function(itemID)
        return ("item%d"):format(itemID),  -- name
            nil,                            -- link
            1,                              -- quality
            1, 1, "Trade Goods", "Cloth",   -- ilvl, minLevel, type, subType
            20,                             -- maxStack
            "", "",                         -- equipLoc, texture
            0,                              -- sellPrice
            0, 0,                           -- classID, subclassID
            bindTypes[itemID] or 0          -- bindType
    end,
    RequestLoadItemDataByID = function() end,
}

ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot)
        return { bag = bag, slot = slot, IsValid = function() return true end }
    end,
}

CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize" }) do
        frame[name] = function() end
    end
    return frame
end

GetTime = function() return os.clock() end
time = time or os.time

ns.db = {}
sisterKeepsOn = true
altUpgradesOn = true
ns.Config = {
    Get = function(_, k)
        if k == "undercutCopper" then return 1 end
        if k == "staleAfterSeconds" then return 48 * 3600 end
        if k == "postDuration" then return 2 end
        if k == "allowPostingAtALoss" then return false end
        if k == "sellHoldsSisterKeeps" then return sisterKeepsOn end
        if k == "sellHoldsAltUpgrades" then return altUpgradesOn end
        if k == "postAnyway" then return postAnyway end
        return nil
    end,
    GetPriceTable = function() return {} end,
    GetCharacterKey = function() return playerKey end,
}
playerKey = "Player-1-ME"

ns.Scanner = {
    isAuctionHouseOpen = false,
    IsCommodity = function(_, itemID) return commodities[itemID] == true end,
}

ns.Prices = {
    GetValue = function(_, itemID, key)
        local entry = prices[itemID]
        return entry and entry[key] or nil
    end,
}

ns.Inventory = {
    GetCarriedBags = function() return { 0, 1, 2, 3, 4, 5 } end,

    -- Locked slots still hold stock: the count is what is there, and whether
    -- any of it can be listed right now is a separate question.
    GetBagCount = function(_, itemID)
        local total = 0
        for _, slots in pairs(bags) do
            for _, entry in ipairs(slots) do
                if entry.itemID == itemID then total = total + entry.stackCount end
            end
        end
        return total
    end,
}

ns.Recipes = {
    GetAccountWide = function() return recipes end,
    GetCharacterName = function(_, key) return key == "Player-1-ALT" and "Ana Stormwood" or "?" end,
}
ns.FarmerGoals = { ItemName = function(itemID) return ("item%d"):format(itemID) end }

ns.Queue = {
    GetShoppingList = function()
        local list = {}
        for itemID in pairs(reserved) do list[#list + 1] = { itemID = itemID } end
        return list
    end,
}

ns.Cost = { FindRecipeForItem = function() return nil end }
ns.Cost.FindAnyRecipeForItem = ns.Cost.FindRecipeForItem

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Profit.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Posting.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/KeepHere.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/SisterKeeps.lua"))("Blackthornes_TS", ns)

local Posting = ns.Posting

-- What a craft cost is not what this file is about, and the real Analyse wants
-- a whole recipe tree to answer. A flat figure keeps the crafted rows honest
-- without dragging costing into a test about which rows appear at all.
ns.Profit.Analyse = function(_, recipeID)
    return recipeID and { costPerUnit = 1 } or nil
end

local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-52s %-30s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

local GOAL, UPGRADE, ALTGEAR, FOOD, KEEP, SET, QUEST, CLAM, PLAIN =
    2589, 7955, 7956, 4536, 3466, 6948, 4306, 7973, 2770
local MAILHERE, MAILAWAY = 4655, 5503

local function LineFor(lines, itemID)
    for _, line in ipairs(lines) do
        if line.itemID == itemID then return line end
    end
end

local function Sisters()
    BlackthornesFarmer = {
        Butler = { Advise = function(_, id)
            if id == GOAL then return { goal = "item2589", have = 20, target = 12, need = 0 } end
        end },
        Value = { Contents = function(_, name) if name == "item7973" then return 4400 end end },
    }
    BlackthornesEquipment = {
        Butler = { Advise = function(_, item)
            if item == UPGRADE then return { upgrade = "now", gain = 6.2 } end
            if item == ALTGEAR then return { alt = { key = "Player-1-ALT", gain = 9 } } end
        end },
    }
    BlackthornesPets = {
        Butler = { Advise = function(_, id) if id == FOOD then return { eats = true, buff = false } end end },
    }
    BlackthornesButler = {
        Verdicts = {
            Choice = function(_, id)
                if id == KEEP then return "keep" end
                if id == MAILHERE then return "mail", "Ana Stormwood" end
                if id == MAILAWAY then return "mail", "Bo Ashgrove" end
            end,
            IsMe = function(_, name) return name == "Ana Stormwood" end,
            InSet = function(_, id) if id == SET then return "Tank" end end,
        },
        Quests = { Reason = function(_, id) if id == QUEST then return "Spider's Silk needs 4 more" end end },
    }
end

local ALL = { GOAL, UPGRADE, ALTGEAR, FOOD, KEEP, SET, QUEST, CLAM, PLAIN }

local function Reset(on)
    postAnyway = on
    Posting.chosenQuantity = {}
    ns.SisterKeeps:Forget()
    sisterKeepsOn = true
    altUpgradesOn = true
    commodities = { [GOAL] = true, [FOOD] = true, [KEEP] = true, [QUEST] = true, [CLAM] = true, [PLAIN] = true }
    reserved, recipes, bindTypes = { [PLAIN] = true }, {}, {}
    prices = {}
    for _, id in ipairs(ALL) do prices[id] = { market = 1000 } end
    bags = { [0] = {} }
    for _, id in ipairs(ALL) do
        table.insert(bags[0], { itemID = id, stackCount = (id == GOAL and 20) or ((id == UPGRADE or id == ALTGEAR or id == SET) and 1) or 3 })
    end
    Sisters()
end

local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
local function Said(text)
    for _, line in ipairs(printed) do if line == text then return true end end
    return false
end
local now = 1000
GetTime = function() return now end
local HINT = "Shift-click List to list it anyway."

print("\nthe setting off, one Shift-click")
Reset(nil)
do
    check("nothing lists anyway before the click", Posting:PostsAnyway(PLAIN), false)
    check("the price floor holds a cheap one", Posting:RefusesEarly(PLAIN, 1, false), true)
    Posting:ListAnywayOnce(PLAIN)
    check("that item lists anyway", Posting:PostsAnyway(PLAIN), true)
    check("another item does not", Posting:PostsAnyway(GOAL), false)
    check("the setting still reads off", Posting:PostsAnyway(), false)
    check("its early refusal steps aside", Posting:RefusesEarly(PLAIN, 1, false), false)
    local lines = Posting:GetPostable({ includeAll = true, showHeld = true })
    check("the list still holds the upgrade", LineFor(lines, UPGRADE) and LineFor(lines, UPGRADE).held, "An upgrade for you, +6%")
    check("and keeps the goal's target", LineFor(lines, GOAL) and LineFor(lines, GOAL).count, 8)
    check("and the queued craft's material", LineFor(lines, PLAIN), nil)
    check("List all counts only the goal's spare", (Posting:GetSummary(nil, lines)), 1)
    check("another item's does not", Posting:RefusesEarly(GOAL, 1, false), true)
    check("the Far Under ask is not skipped", Posting:IsUnderFloor({ itemID = PLAIN, unitPrice = 1 }), true)
end

print("\nwhat ends it")
Reset(nil)
do
    Posting:Request(PLAIN, 3, 1, { anyway = true })
    check("a Shift-click starts it", Posting:PostsAnyway(PLAIN), true)
    Posting:Request(GOAL, 1, 1000)
    check("a plain click on another item leaves it", Posting:PostsAnyway(PLAIN), true)
    Posting:Request(PLAIN, 3, 1)
    check("a plain click on the item ends it", Posting:PostsAnyway(PLAIN), false)

    Posting:ListAnywayOnce(PLAIN)
    now = now + Posting.ANYWAY_ONCE_SECONDS + 1
    check("two minutes on, it is over", Posting:PostsAnyway(PLAIN), false)

    Posting:ListAnywayOnce(PLAIN)
    Posting:EndAnywayOnce(PLAIN)
    check("listing it ends it", Posting:PostsAnyway(PLAIN), false)
end

print("\nthe whole stack")
Reset(nil)
do
    check("every goal copy, kept ones too", Posting:WholeStack(GOAL), 20)
    check("all the queued craft's material", Posting:WholeStack(PLAIN), 3)
    check("one piece of gear", Posting:WholeStack(UPGRADE), 1)
    check("a row nothing keeps back says none kept", LineFor(Posting:GetPostable({ includeAll = true }), GOAL).queueKept, nil)
    ns.Queue.GetReservedItems = function() return { [PLAIN] = 1 } end
    local plain = LineFor(Posting:GetPostable({ includeAll = true }), PLAIN)
    check("the queue keeps one of three", plain and plain.count, 2)
    check("and the row says some are kept", plain and plain.queueKept, true)
    check("a Shift-click still lists all three", Posting:WholeStack(PLAIN), 3)
    ns.Queue.GetReservedItems = nil
end

print("\na refusal at the Sell list says how")
Reset(nil)
do
    printed = {}
    ns.PostPanel = { view = "sell", IsShown = function() return true end }
    Posting:RefusesEarly(PLAIN, 1, false)
    check("the Shift-click line follows the refusal", Said(HINT), true)

    printed = {}
    ns.PostPanel.view = "buy"
    Posting:RefusesEarly(PLAIN, 1, false)
    check("not on another view", Said(HINT), false)

    printed = {}
    ns.PostPanel = { view = "sell", IsShown = function() return false end }
    Posting:RefusesEarly(PLAIN, 1, false)
    check("not with the Sell list shut", Said(HINT), false)
    ns.PostPanel = nil
end

print("\nthe listing itself")
Reset(nil)
do
    local posted = {}
    C_AuctionHouse = { PostCommodity = function(_, _, quantity, price)
        posted[#posted + 1] = { quantity = quantity, price = price }
        return true
    end }
    C_Timer = { After = function() end }
    ns.AHQueue = { NoteListing = function() end, Yield = function() end }
    ns.Auctions = { GetOwnPostedCount = function() return 0 end }
    local realCanPost = Posting.CanPost
    Posting.CanPost = function() return true end
    ns.Scanner.isAuctionHouseOpen = true

    check("a plain listing under the floor is refused", Posting:Post(PLAIN, 3, 1, false), false)
    check("nothing went up", #posted, 0)

    Posting:ListAnywayOnce(PLAIN)
    check("the Shift-click's listing goes up", Posting:Post(PLAIN, 3, 1, false), true)
    check("all three of them", posted[1] and posted[1].quantity, 3)
    check("and that ends it", Posting:PostsAnyway(PLAIN), false)

    Posting.CanPost = realCanPost
    ns.Scanner.isAuctionHouseOpen = false
    C_AuctionHouse, C_Timer, ns.AHQueue, ns.Auctions = nil, nil, nil, nil
    Posting.pending, Posting.others = nil, nil
end

BlackthornesFarmer, BlackthornesEquipment, BlackthornesPets, BlackthornesButler = nil, nil, nil, nil
sisterKeepsOn, postAnyway = nil, nil

print("")
if failures > 0 then
    print(("%d check(s) failed"):format(failures))
    error(("%d check(s) failed"):format(failures), 0)
end
print("all checks passed")
