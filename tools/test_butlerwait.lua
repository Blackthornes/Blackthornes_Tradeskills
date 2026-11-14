-- Butler's Wait for a Better Price on the auction house drawer (2026-11-14).
--
--   * a bag copy Butler says waits carries butlerWait (short, reason, prices);
--   * it stays on the drawer, but List Next and the summary pass it over;
--   * Sell Anyway tells Butler, and the row lists again;
--   * Show Waiting unticked takes waiting rows off the drawer;
--   * Sell All Waiting tells Butler about every waiting row;
--   * no Butler, or a Butler that raises, changes nothing.
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
        if k == "postAnyway" then return postAnywayOn end
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
local failures = 0

local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(("  %-52s %-30s %s"):format(label, tostring(got), ok and "ok" or
        ("FAILED, expected " .. tostring(expected))))
end

local WAITS, LOSS, PLAIN = 2589, 7955, 2770

local function LineFor(lines, itemID)
    for _, line in ipairs(lines) do
        if line.itemID == itemID then return line end
    end
end

local soldAnyway
local function Butler()
    soldAnyway = {}
    BlackthornesButler = {
        Verdicts = {
            Waiting = function(_, id, bag, slot)
                if soldAnyway[id] or bag == nil or slot == nil then return nil end
                if id == WAITS then
                    return { short = "Usually 10s, now 6s", reason = "Usually 10s, now 6s",
                        now = 600, usual = 1000 }
                end
                if id == LOSS then
                    return { short = "Costs more to make", reason = "Costs more to make", cost = 2000 }
                end
            end,
            SellAnyway = function(_, id) soldAnyway[id] = true end,
        },
    }
end

local function Reset()
    Posting.chosenQuantity = {}
    ns.SisterKeeps:Forget()
    sisterKeepsOn = true
    commodities = { [WAITS] = true, [LOSS] = true, [PLAIN] = true }
    reserved, recipes, bindTypes = {}, {}, {}
    prices = { [WAITS] = { market = 1000 }, [LOSS] = { market = 1000 }, [PLAIN] = { market = 1000 } }
    bags = { [0] = {
        { itemID = WAITS, stackCount = 5 },
        { itemID = LOSS, stackCount = 2 },
        { itemID = PLAIN, stackCount = 7 },
    } }
    Butler()
end

print("\nButler says wait")
Reset()
do
    local lines = Posting:GetPostable({ includeAll = true, showHeld = true })
    local w = LineFor(lines, WAITS)
    check("a waiting item stays on the drawer", w ~= nil, true)
    check("and carries Butler's short why", w and w.butlerWait and w.butlerWait.short, "Usually 10s, now 6s")
    check("with today's price", w and w.butlerWait and w.butlerWait.now, 600)
    check("and the usual one", w and w.butlerWait and w.butlerWait.usual, 1000)
    check("a loss carries what it costs", LineFor(lines, LOSS).butlerWait.cost, 2000)
    check("a plain item does not wait", LineFor(lines, PLAIN).butlerWait, nil)
    check("it is not held", w and w.held, nil)
    check("List Next passes waiting rows over", Posting:GetNextPostable(nil, lines).itemID, PLAIN)
    check("the summary counts only what lists", (Posting:GetSummary(nil, lines)), 1)
end

print("\nSell Anyway")
Reset()
do
    check("Butler hears Sell Anyway", ns.SisterKeeps:SellAnyway(WAITS), true)
    ns.SisterKeeps:Forget()
    ns.Inventory.changes = (ns.Inventory.changes or 0) + 1
    local lines = Posting:GetPostable({ includeAll = true, showHeld = true })
    check("the row no longer waits", LineFor(lines, WAITS).butlerWait, nil)
    check("the loss still waits", LineFor(lines, LOSS).butlerWait ~= nil, true)
    check("and lists again", (Posting:GetSummary(nil, lines)), 2)
end

print("\nThe scroll wheel and List Next ask Butler again")
Reset()
do
    -- The list was drawn before Butler said wait (or a free row shares its
    -- item with a waiting copy): the line carries no butlerWait, but the
    -- copy a listing would draw from does.
    BlackthornesButler = nil
    ns.SisterKeeps:Forget()
    ns.Inventory.changes = (ns.Inventory.changes or 0) + 1
    local lines = Posting:GetPostable({ includeAll = true, showHeld = true })
    check("drawn without Butler, nothing waits", LineFor(lines, WAITS).butlerWait, nil)
    Butler()
    ns.SisterKeeps:Forget()
    check("Butler waits on the copy listing would use", Posting:ButlerWaitsNow(WAITS), true)
    check("a plain item does not", Posting:ButlerWaitsNow(PLAIN), false)
    check("List Next still passes the waiting rows", Posting:GetNextPostable(nil, lines).itemID, PLAIN)
    check("and with fast listing", Posting:GetNextPostable({ skipSettling = true }, lines).itemID, PLAIN)
    bags[0][3] = nil
    check("nothing else left, nothing lists", Posting:GetNextPostable(nil, lines), nil)
    postAnywayOn = true
    check("Bypass Disallowed Postings still lists it", Posting:GetNextPostable(nil, lines).itemID, WAITS)
    postAnywayOn = nil
    check("after Sell Anyway it lists", (function()
        ns.SisterKeeps:SellAnyway(WAITS); ns.SisterKeeps:Forget()
        local line = Posting:GetNextPostable(nil, lines)
        return line and line.itemID
    end)(), WAITS)
end

print("\nNo Butler, or one that raises")
Reset()
BlackthornesButler = nil
ns.SisterKeeps:Forget()
ns.Inventory.changes = (ns.Inventory.changes or 0) + 1
do
    local lines = Posting:GetPostable({ includeAll = true, showHeld = true })
    check("nothing waits without Butler", LineFor(lines, WAITS).butlerWait, nil)
    check("Sell Anyway says no", ns.SisterKeeps:SellAnyway(WAITS), false)
end
Reset()
BlackthornesButler.Verdicts.Waiting = function() error("boom") end
BlackthornesButler.Verdicts.SellAnyway = function() error("boom") end
ns.SisterKeeps:Forget()
ns.Inventory.changes = (ns.Inventory.changes or 0) + 1
do
    local lines = Posting:GetPostable({ includeAll = true, showHeld = true })
    check("a Butler that raises makes nothing wait", LineFor(lines, WAITS).butlerWait, nil)
    check("and Sell Anyway says no", ns.SisterKeeps:SellAnyway(WAITS), false)
end

BlackthornesButler = nil
sisterKeepsOn = nil

print("")
if failures > 0 then
    print(("%d check(s) failed"):format(failures))
    error(("%d check(s) failed"):format(failures), 0)
end
print("all checks passed")
