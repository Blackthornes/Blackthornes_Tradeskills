-- Craftsman's Writs on the Deals tab: writs by what a point of reputation
-- costs, and what a reputation goal still costs (a player's idea, 2026-10-09).
--
-- What this pins down:
--   * a writ's name finds its entry, whatever the case;
--   * a turn-in costs the writ + the item it asks for, bought or made,
--     whichever is cheaper, times how many it asks for;
--   * the reported reputation stands in until a turn-in is seen, and a
--     learned one belongs to the character that saw it;
--   * the standing is read from the game, and a goal says how many writs of
--     each level it takes, the cheapest way (one order a day) and the
--     quickest (every priced order each day);
--   * the item a writ asks for leaving the bags while the standing rises is
--     what that level of writ paid;
--   * the Deals tab's Show menu swaps in the view, and its goal menu is kept
--     in Settings.

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
                C_Timer = C_Timer, C_Reputation = C_Reputation, UnitFactionGroup = UnitFactionGroup,
                GetFactionInfoByID = GetFactionInfoByID }

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

local WISDOM, ROD, SHOT, MANA = 3383, 11128, 8069, 3827
local WISDOM_WRIT, ROD_WRIT, MANA_WRIT = 264001, 264021, 264060

local items = {
    [WISDOM_WRIT] = "Craftsman's Writ: Elixir of Wisdom",
    [MANA_WRIT] = "CRAFTSMAN'S WRIT: mana potion",
    [264100] = "Some Other Forever Item",
}

local asked = {}
C_Item = {
    GetItemInfo = function(itemID) return items[itemID] end,
    RequestLoadItemDataByID = function(itemID) asked[itemID] = true end,
}

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)

-- Copper, the cheapest listing.
local prices = {
    [WISDOM_WRIT] = 500,
    [ROD_WRIT] = 300,
    [MANA_WRIT] = 2000,
    [WISDOM] = 400,
    [ROD] = 900,
    [SHOT] = 2,
    [MANA] = 1000,
}

local config = {}
ns.Config = {
    Get = function(_, key) return config[key] end,
    Set = function(_, key, value) config[key] = value end,
    GetCharacterKey = function() return "Player-1-0001" end,
}
ns.Prices = {
    GetValue = function(_, itemID) return prices[itemID] end,
    Count = function() return 7 end,
}

-- The Golden Rod is cheaper made than bought.
local ROD_RECIPE = 14379
ns.Cost = {
    GetReagentUnitCost = function(_, itemID) return prices[itemID], "auction" end,
    FindAnyRecipeForItem = function(_, itemID) return itemID == ROD and ROD_RECIPE or nil end,
    GetMaterialValue = function(_, recipeID) return recipeID == ROD_RECIPE and 250 or nil end,
}

local bags = {}
ns.Inventory = {
    GetBagCounts = function() return bags end,
    GetBagCount = function(_, itemID) return bags[itemID] or 0 end,
}

local side, standing = "Alliance", 4500
UnitFactionGroup = function() return side end
C_Reputation = {
    GetFactionDataByID = function(id)
        if id == 2586 then return { name = "Azeroth Commerce Authority", currentStanding = standing } end
        return nil
    end,
}

ns.db = {}

assert(loadfile(lfs_cwd .. "/Data/CraftsmansWrits.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/Logic/Writs.lua"))("Blackthornes_TS", ns)

local Writs = ns.Writs

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function Row(rows, key)
    for _, row in ipairs(rows) do
        if row.key == key then return row end
    end
end

--------------------------------------------------------------------------------
print("\nthe writ list")

check("150 writs, 30 for each of five professions", #ns.CRAFTSMANS_WRITS == 150)
local seenItems, counts = {}, {}
for _, writ in ipairs(ns.CRAFTSMANS_WRITS) do
    seenItems[writ.item] = (seenItems[writ.item] or 0) + 1
    counts[writ.prof .. writ.tier] = (counts[writ.prof .. writ.tier] or 0) + 1
end
local once = true
for _, n in pairs(seenItems) do once = once and n == 1 end
check("no item is asked for by two writs", once)
check("9 Journeyman, 12 Expert and 9 Artisan in each", counts.Alchemy1 == 9 and counts.Alchemy2 == 12
    and counts.Alchemy3 == 9 and counts.Tailoring2 == 12)

--------------------------------------------------------------------------------
print("\nreading writ names")

local function Item(name)
    local writ = Writs.WritForName(name)
    return writ and writ.item
end

check("a writ's name finds it", Item("Craftsman's Writ: Elixir of Wisdom") == WISDOM)
check("whatever the case", Item("CRAFTSMAN'S WRIT: golden rod") == ROD)
check("other items are not writs", Item("Elixir of Wisdom") == nil and Item(nil) == nil
    and Item("Craftsman's Writ: Something New") == nil)

--------------------------------------------------------------------------------
print("\nwhat a point of reputation costs")

local rows = Writs:GetRows()
check("every writ is a row", #rows == #ns.CRAFTSMANS_WRITS)

local rod = Row(rows, ROD)
check("the writ is priced from the auction house by its typed item ID", rod.writID == ROD_WRIT and rod.writPrice == 300)
check("the item is made when that is cheaper", rod.how == "make" and rod.itemCost == 250 and rod.buy == 900)
check("with the reported 75 reputation", rod.rep == 75 and rod.source == "reported")
check("total is writ + item", rod.total == 550)
check("and a point is a 75th of that", math.abs(rod.perRep - 550 / 75) < 1e-9)

local shot = Row(rows, SHOT)
check("an order for 200 counts all 200", shot.count == 200 and shot.itemCost == 400)
check("a writ the game has not shown yet has no price", shot.writID == nil and shot.total == nil)

local wisdom = Row(rows, WISDOM)
check("a writ not found yet is unpriced", wisdom.writID == nil and wisdom.perRep == nil)
check("priced writs sort first", rows[1].key == ROD)

--------------------------------------------------------------------------------
print("\nfinding writs in the game")

Writs:FindWrits()
check("a writ in Forever's item IDs is found by name", ns.db.merchantsFavor.writIDs[WISDOM] == WISDOM_WRIT
    and ns.db.merchantsFavor.writIDs[MANA] == MANA_WRIT)
check("unknown item IDs are asked for", asked[264002] == true)

items[264002] = "Craftsman's Writ: Practice Lock"
Writs:OnItemInfo(264002)
check("and read when they arrive", ns.db.merchantsFavor.writIDs[6712] == 264002)

rows = Writs:GetRows()
wisdom = Row(rows, WISDOM)
check("found, it is priced", wisdom.writPrice == 500 and wisdom.total == 900)
local mana = Row(rows, MANA)
check("an Expert writ pays the reported 125", mana.rep == 125 and mana.total == 3000 and mana.perRep == 24)

--------------------------------------------------------------------------------
print("\nthe goal")

local plan = Writs:GetPlan("honored", rows)
check("the standing is read from the game", plan.standing == 4500
    and plan.faction.name == "Azeroth Commerce Authority")
check("Friendly now", Writs.StandingText(plan.standing) == "Friendly")
check("Honored is 4500 away", plan.need == 4500)
check("60 Journeyman, 36 Expert or 23 Artisan writs", plan.perTier[1].writs == 60
    and plan.perTier[2].writs == 36 and plan.perTier[3].writs == 23)
check("cheapest: the Golden Rod, one a day", plan.cheapest.row.key == ROD and plan.cheapest.writs == 60
    and plan.cheapest.days == 60 and plan.cheapest.cost == 60 * 550)

-- Three priced orders pay 75 + 75 + 125 = 275 a day: 16 full days is
-- 4400, and day 17 needs only the Golden Rod's 75 more... and then some.
check("quickest: every priced order each day", plan.quickest.days == 17
    and plan.quickest.writs == 16 * 3 + 2
    and plan.quickest.cost == 16 * (550 + 900 + 3000) + 550 + 900)

standing = 9500
plan = Writs:GetPlan("honored", rows)
check("a goal already reached needs nothing", plan.need == 0 and plan.cheapest == nil)
check("a goal key it does not know is Honored", Writs.GoalFor("nonsense").key == "honored")

side = "Horde"
plan = Writs:GetPlan("revered", rows)
check("the Horde's camp is asked for by its own ID", plan.faction.name == "Durotar Supply and Logistics"
    and plan.standing == nil and plan.need == 21000)
side = "Alliance"

--------------------------------------------------------------------------------
print("\nlearning what a turn-in pays")

standing = 4500
bags = { [ROD] = 2 }
Writs:OnEnable()
check("the bags and standing are looked at once to start", Writs.held[ROD] == 2 and Writs.standing == 4500)

-- Handing in: the item goes, the standing rises, the quest pays nothing.
clock = 200
bags = { [ROD] = 1 }
Fire("BAG_UPDATE_DELAYED")
Fire("QUEST_TURNED_IN", 94221, 0, 0)
standing = 4580
Fire("UPDATE_FACTION")
Flush()

local learned = ns.db.merchantsFavor.writRewards["Player-1-0001"]
check("the turn-in's reputation is kept for this character", learned and learned[1]
    and learned[1].rep == 80 and learned[1].turnIns == 1)

rod = Row(Writs:GetRows(), ROD)
check("Journeyman writs now say they were seen paid", rod.rep == 80 and rod.source == "learned")
mana = Row(Writs:GetRows(), MANA)
check("Expert writs are still as reported", mana.rep == 125 and mana.source == "reported")

ns.Config.GetCharacterKey = function() return "Player-1-0002" end
check("another character still sees the reported figure", Row(Writs:GetRows(), ROD).source == "reported")
ns.Config.GetCharacterKey = function() return "Player-1-0001" end

-- An item sold, with no standing coming in.
clock = 300
bags = {}
Fire("BAG_UPDATE_DELAYED")
clock = 320
Flush()
standing = 4600
Fire("UPDATE_FACTION")
Flush()
check("reputation long after an item went is not put down to it", learned[1].turnIns == 1)

-- Raising client values in an instance are no error.
local raising = C_Reputation.GetFactionDataByID
C_Reputation.GetFactionDataByID = function() error("secret") end
local ok = pcall(Fire, "UPDATE_FACTION")
check("a secret standing is ignored, not an error", ok)
C_Reputation.GetFactionDataByID = raising

--------------------------------------------------------------------------------
print("\nthe view on the Deals tab")

standing = 4500
bags = { [ROD_WRIT] = 2 }

local function Stub(fields)
    local frame = fields or {}
    frame.IsVisible = frame.IsVisible or function() return true end
    frame.SetShown = frame.SetShown or function(self, value) rawset(self, "shown", value) end
    frame.Hide = frame.Hide or function(self) rawset(self, "shown", false) end
    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

local labels = {}
local function Label()
    local label = Stub({
        text = "",
        SetText = function(self, value) self.text = tostring(value) end,
        GetText = function(self) return self.text end,
        SetTextColor = function(self, a) self.color = a end,
    })
    labels[#labels + 1] = label
    return label
end

CreateFrame = function() return Stub() end
GameTooltip = Stub({ lines = {}, AddLine = function(self, text) self.lines[#self.lines + 1] = text end })

ns.Theme = {
    SetRowName = function(label, text) label:SetText(text) end,
    CreateLabel = function() return Label() end,
    CreatePanel = function() return Stub() end,
    CreateDivider = function() return Stub() end,
    Unpack = function(key) return key end,
    ProfitColor = function(value) return (value or 0) >= 0 and "profit" or "loss" end,
    AccentStripe = function() return Stub() end,
    CreateItemIcon = function() return Stub() end,
    SetItemIcon = function() end,
    CreateHeading = function(_, text) local label = Label(); label.text = text; return label end,
    CreateBar = function() return Stub({ track = Stub() }) end,
    FitText = function(label, texts) label:SetText(texts[1]); return texts[1] end,
}

local lists, dropdowns, buttons = {}, {}, {}
local searched
ns.Widgets = {
    CreateDropdown = function(_, options, onSelect, opts)
        local dropdown = Stub({ options = options, onSelect = onSelect, opts = opts,
            SetValue = function(self, value) self.value = value end })
        dropdowns[#dropdowns + 1] = dropdown
        return dropdown
    end,
    CreateSearchBox = function(_, _, onChange) searched = onChange; return Stub() end,
    CreateCheckbox = function(_, _, onToggle, initial) return Stub({ onToggle = onToggle, initial = initial }) end,
    CreateButton = function(_, text, onClick) local button = Stub({ onClick = onClick }); buttons[text] = button; return button end,
    ShowItemTooltip = function() return true end,
    CreateScrollList = function(_, opts)
        local list = Stub({ opts = opts, SetData = function(self, data) self.data = data end })
        lists[#lists + 1] = list
        return list
    end,
}

local sent = {}
ns.Scanner = { isAuctionHouseOpen = true }
local tabs = {}
ns.UI = Stub({
    RegisterTab = function(_, tab) tabs[tab.key] = tab end,
    SearchAuctionHouse = function(_, itemID) sent[#sent + 1] = itemID; return true end,
})
ns.Disenchant = { factsVersion = 0, WasRequested = function() return false end }
ns.VendorFlips = {
    GetAuctionRows = function() return {}, 0, 0 end,
    GetResaleRows = function() return {}, 0, 0 end,
    MIN_RESALE_SCANS = 3,
}
ns.Demand = { TooltipText = function() return nil end }

assert(loadfile(lfs_cwd .. "/UI/DealsWrits.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/Tab_Deals.lua"))("Blackthornes_TS", ns)

local tab = tabs.deals
tab.build(Stub())

local show, goal = dropdowns[2], dropdowns[3]
check("the Show menu offers the writs", show.options[3].value == "writs")
check("the goal menu has four goals, Honored picked", #goal.options == 4 and goal.value == "honored"
    and goal.options[2].text == "Goal: Honored")
check("and is hidden on the flips", goal.shown == false)

show.onSelect("writs")
check("the goal menu shows with the writs", goal.shown == true)
local list = lists[#lists]
check("Craftsman's Writs builds its own list", #lists == 2 and #list.data == #ns.CRAFTSMANS_WRITS)
check("cheapest reputation first", list.data[1].key == ROD)

local function Showing(pattern)
    for _, label in ipairs(labels) do
        if label.text:find(pattern) then return label.text end
    end
end

check("the panel names the goal and the camp", Showing("^Honored with Azeroth Commerce Authority$") ~= nil)
check("and says how far it is", Showing("^Now %(Friendly%)$") ~= nil and Showing("^Still to go$") ~= nil)
check("and marks reported figures", Showing("^Expert writs %(125 each%*%)$") ~= nil
    and Showing("^Journeyman writs %(80 each%)$") ~= nil)
check("and the cheapest way", Showing("^Cheapest: 57 Golden Rod, one a day$") ~= nil)

local row = Stub()
list.opts.createRow(row)
list.opts.updateRow(row, Row(list.data, ROD))
-- Right to left: PER REP, TOTAL, ITEM, WRIT, REP.
check("PER REP shows a price", row.cells[1].text ~= "" and row.cells[1].color == "accent")
check("REP shows the learned figure", row.cells[5].text == "80" and row.cells[5].color == "text")
check("the name says how many writs are carried", row.name.text == "Golden Rod  (2)")

list.opts.updateRow(row, Row(list.data, SHOT))
check("an order for many says how many", row.name.text == "200 Crafted Solid Shot")

list.opts.onClick(Row(list.data, ROD), 1, "LeftButton")
check("the detail shows the item made", Showing("^Golden Rod %(made%)$") ~= nil)
buttons["Search item"].onClick()
check("the item button searches for the item", sent[#sent] == ROD)
list.opts.onClick(Row(list.data, ROD), 1, "RightButton")
check("right-click searches for the writ", sent[#sent] == ROD_WRIT)

list.opts.onClick(Row(list.data, SHOT), 1, "LeftButton")
printed = {}
buttons["Search writ"].onClick()
check("a writ never seen says to type its name", #printed == 1 and printed[1]:find("type its name") ~= nil)

goal.onSelect("exalted")
check("a new goal is kept in Settings", config.writGoal == "exalted")
check("and the panel follows it", Showing("^Exalted with Azeroth Commerce Authority$") ~= nil)

searched("blacksmith")
check("search finds a profession's writs", #list.data == 30)
searched("")

show.onSelect("flips")
check("back to the flips, the goal menu hides", goal.shown == false and #lists == 2)

for _, key in ipairs({ "C_Item", "GetTime", "CreateFrame", "GameTooltip", "C_Timer", "C_Reputation",
        "UnitFactionGroup", "GetFactionInfoByID" }) do
    _G[key] = saved[key]
end

print(("\n%d checks passed"):format(checks))
