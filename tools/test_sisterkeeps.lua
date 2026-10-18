-- Logic/SisterKeeps.lua and the Sell list (2026-10-16).
--
-- What the other Blackthornes addons want kept never goes up through List
-- all or Post Crafted:
--   * a Farmer goal holds back up to its target, the rest still sells;
--   * an upgrade (for you or an alt), pet food, Butler's lists, a set
--     piece, a quest item and a clam worth more opened are held whole;
--   * a held row still shows on the drawer (showHeld), with why, and
--     nothing that picks what to list ever takes it;
--   * a sister that raises, or no sisters at all, changes nothing;
--   * unticked, nothing is held.
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
        return nil
    end,
    GetPriceTable = function() return {} end,
}

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

local function Reset()
    Posting.chosenQuantity = {}
    ns.SisterKeeps:Forget()
    sisterKeepsOn = true
    altUpgradesOn = true
    commodities = { [GOAL] = true, [FOOD] = true, [KEEP] = true, [QUEST] = true, [CLAM] = true, [PLAIN] = true }
    reserved, recipes, bindTypes = {}, {}, {}
    prices = {}
    for _, id in ipairs({ GOAL, UPGRADE, ALTGEAR, FOOD, KEEP, SET, QUEST, CLAM, PLAIN }) do
        prices[id] = { market = 1000 }
    end
    bags = { [0] = {
        { itemID = GOAL, stackCount = 20 },
        { itemID = UPGRADE, stackCount = 1 },
        { itemID = ALTGEAR, stackCount = 1 },
        { itemID = FOOD, stackCount = 10 },
        { itemID = KEEP, stackCount = 5 },
        { itemID = SET, stackCount = 1 },
        { itemID = QUEST, stackCount = 4 },
        { itemID = CLAM, stackCount = 3 },
        { itemID = PLAIN, stackCount = 7 },
    } }
    Sisters()
end

print("\nList all with every sister loaded")
Reset()
do
    local lines = Posting:GetPostable({ includeAll = true })
    check("the goal's target is held, the rest sells", LineFor(lines, GOAL) and LineFor(lines, GOAL).count, 8)
    check("and says why", LineFor(lines, GOAL).keptWhy, "For your goal")
    check("an upgrade for you is left out", LineFor(lines, UPGRADE), nil)
    check("an alt's upgrade is left out", LineFor(lines, ALTGEAR), nil)
    check("pet food is left out", LineFor(lines, FOOD), nil)
    check("Always keep is left out", LineFor(lines, KEEP), nil)
    check("a set piece is left out", LineFor(lines, SET), nil)
    check("a quest item is left out", LineFor(lines, QUEST), nil)
    check("a clam worth more opened is left out", LineFor(lines, CLAM), nil)
    check("everything else sells", LineFor(lines, PLAIN) and LineFor(lines, PLAIN).count, 7)

    local nextLine = Posting:GetNextPostable(nil, lines)
    check("List all's next is the goal's spare", nextLine and nextLine.itemID, GOAL)
    check("and counts two", (Posting:GetSummary(nil, lines)), 2)
end

print("\nan alt's upgrade sells unless Keep Upgrades for Alts is ticked")
Reset()
altUpgradesOn = nil
do
    local lines = Posting:GetPostable({ includeAll = true, showHeld = true })
    check("an alt's upgrade is on the list", LineFor(lines, ALTGEAR) ~= nil, true)
    check("and not held", LineFor(lines, ALTGEAR).held, nil)
    check("your own upgrade is still held", LineFor(lines, UPGRADE).held, "An upgrade for you, +6%")
end
check("the setting is off unless ticked", ns.SisterKeeps:HoldsAltUpgrades(), false)

print("\nthe drawer shows held rows, dimmed, with why")
Reset()
do
    local lines = Posting:GetPostable({ includeAll = true, showHeld = true })
    check("the upgrade shows", LineFor(lines, UPGRADE) and LineFor(lines, UPGRADE).held, "An upgrade for you, +6%")
    check("the alt's, by full name", LineFor(lines, ALTGEAR).held, "An upgrade for Ana Stormwood, +9%")
    check("pet food", LineFor(lines, FOOD).held, "Your pet eats this")
    check("Always keep", LineFor(lines, KEEP).held, "On your Always keep list")
    check("the set", LineFor(lines, SET).held, "In your Tank equipment set")
    check("the quest", LineFor(lines, QUEST).held, "Spider's Silk needs 4 more")
    check("the clam", LineFor(lines, CLAM).held ~= nil and LineFor(lines, CLAM).held:find("Worth more opened", 1, true) ~= nil, true)
    check("a held row keeps its whole count", LineFor(lines, FOOD).count, 10)
    check("only two can be listed", (Posting:GetSummary(nil, lines)), 2)
    local picked = {}
    for _ = 1, 3 do
        local line = Posting:GetNextPostable(nil, lines)
        if line then picked[line.itemID] = true end
    end
    check("nothing held is ever next", picked[UPGRADE] or picked[FOOD] or picked[CLAM] or false, false)
end

print("\nfive copies of an upgrade: one is held, four sell")
Reset()
for _ = 1, 4 do table.insert(bags[0], { itemID = UPGRADE, stackCount = 1 }) end
do
    local lines = Posting:GetPostable({ includeAll = true, showHeld = true })
    local line = LineFor(lines, UPGRADE)
    check("four are on the list", line and line.count, 4)
    check("one is held for you", line and line.kept, 1)
    check("and says why", line and line.keptWhy, "An upgrade for you, +6%")
end

print("\na clam worth less opened sells")
Reset()
prices[CLAM] = { market = 9000 }
check("listed", LineFor(Posting:GetPostable({ includeAll = true }), CLAM) ~= nil, true)

print("\nunticked, only what Butler keeps is held")
Reset()
sisterKeepsOn = false
do
    local lines = Posting:GetPostable({ includeAll = true })
    check("the upgrade sells", LineFor(lines, UPGRADE) ~= nil, true)
    check("the whole goal stack sells", LineFor(lines, GOAL).count, 20)
end

print("\nwhat Butler keeps is held, ticked or not")
for _, on in ipairs({ true, false }) do
    Reset()
    sisterKeepsOn = on
    local AMMO, BACK, HERE = 3030, 2592, 2318
    commodities[AMMO], commodities[BACK], commodities[HERE] = true, true, true
    prices[AMMO], prices[BACK], prices[HERE] = { market = 1000 }, { market = 1000 }, { market = 1000 }
    table.insert(bags[0], { itemID = AMMO, stackCount = 200 })
    table.insert(bags[0], { itemID = BACK, stackCount = 6 })
    table.insert(bags[0], { itemID = HERE, stackCount = 20 })
    BlackthornesButler.Ammo = { Keeps = function(_, id) if id == AMMO then return "Ammo for your bow" end end }
    BlackthornesButler.Learning = { Get = function(_, id) if id == BACK then return "keep" end end }
    BlackthornesButler.KeepHere = {
        Count = function(_, id) if id == HERE then return 15 end end,
        IsAll = function(count) return count >= 9999 end,
    }
    local label = on and " (ticked)" or " (unticked)"
    local lines = Posting:GetPostable({ includeAll = true, showHeld = true })
    check("a hunter's own ammo is held" .. label, LineFor(lines, AMMO) and LineFor(lines, AMMO).held, "Ammo for your bow")
    check("bought back is held" .. label, LineFor(lines, BACK) and LineFor(lines, BACK).held,
        "You bought this back, so Butler keeps it")
    check("Always keep is held" .. label, LineFor(lines, KEEP) and LineFor(lines, KEEP).held, "On your Always keep list")
    check("keep here holds its number" .. label, LineFor(lines, HERE) and LineFor(lines, HERE).count, 5)
    check("and says why" .. label, LineFor(lines, HERE) and LineFor(lines, HERE).keptWhy, "Keeping 15 on this character")
    check("pet food only when ticked" .. label, LineFor(lines, FOOD).held ~= nil, on)
    local nextLine = Posting:GetNextPostable(nil, lines)
    check("List all never picks Butler's ammo" .. label, nextLine and nextLine.itemID ~= AMMO, true)
end

print("\nAlways mail to the character playing sells here")
for _, on in ipairs({ true, false }) do
    Reset()
    sisterKeepsOn = on
    commodities[MAILHERE], commodities[MAILAWAY] = true, true
    prices[MAILHERE], prices[MAILAWAY] = { market = 1000 }, { market = 1000 }
    table.insert(bags[0], { itemID = MAILHERE, stackCount = 8 })
    table.insert(bags[0], { itemID = MAILAWAY, stackCount = 8 })
    local label = on and " (ticked)" or " (unticked)"
    local lines = Posting:GetPostable({ includeAll = true, showHeld = true })
    check("mailed to you, it sells" .. label, LineFor(lines, MAILHERE) and LineFor(lines, MAILHERE).held, nil)
    check("the whole stack" .. label, LineFor(lines, MAILHERE) and LineFor(lines, MAILHERE).count, 8)
    check("mailed to another, it's held" .. label, LineFor(lines, MAILAWAY) and LineFor(lines, MAILAWAY).held,
        "On your Always mail list")
end
Reset()
BlackthornesButler.Verdicts.IsMe = nil
commodities[MAILHERE], prices[MAILHERE] = true, { market = 1000 }
table.insert(bags[0], { itemID = MAILHERE, stackCount = 8 })
check("an older Butler that can't say still holds it",
    LineFor(Posting:GetPostable({ includeAll = true, showHeld = true }), MAILHERE).held, "On your Always mail list")

print("\nno sisters, or sisters that raise")
Reset()
BlackthornesFarmer, BlackthornesEquipment, BlackthornesPets, BlackthornesButler = nil, nil, nil, nil
check("without sisters all nine sell", #Posting:GetPostable({ includeAll = true }), 9)
Reset()
local function Boom() error("boom") end
BlackthornesFarmer = { Butler = { Advise = Boom }, Value = { Contents = Boom } }
BlackthornesEquipment = { Butler = { Advise = Boom } }
BlackthornesPets = { Butler = { Advise = Boom } }
BlackthornesButler = { Verdicts = { Choice = Boom, InSet = Boom }, Quests = { Reason = Boom } }
check("sisters that raise change nothing", #Posting:GetPostable({ includeAll = true }), 9)

print("\nanswers are kept until the bags change")
Reset()
local asked = 0
BlackthornesPets.Butler.Advise = function(_, id) asked = asked + 1; if id == FOOD then return { eats = true } end end
ns.Inventory.changes = 1
Posting:GetPostable({ includeAll = true })
local first = asked
Posting:GetPostable({ includeAll = true })
check("a second build asks nothing again", asked, first)
ns.Inventory.changes = 2
Posting:GetPostable({ includeAll = true })
check("a bag change asks again", asked > first, true)

BlackthornesFarmer, BlackthornesEquipment, BlackthornesPets, BlackthornesButler = nil, nil, nil, nil
sisterKeepsOn = nil

print("")
if failures > 0 then
    print(("%d check(s) failed"):format(failures))
    error(("%d check(s) failed"):format(failures), 0)
end
print("all checks passed")
