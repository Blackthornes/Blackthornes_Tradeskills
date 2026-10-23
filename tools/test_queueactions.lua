-- Queue row actions, marks, Disenchant next and Sell marked, outside WoW
-- (a player's request, 2026-10-07).
--
-- What must hold:
--   1. A row starts on whichever way pays most (the Profit tab's Best), a
--      click steps through what is open to the item, and a right-click goes
--      back to the best. Disenchant is offered only for an item that can be
--      disenchanted by one of your characters.
--   2. Only what the queue makes on DE or Vendor is marked, and a mark never
--      grows past what is carried: an item that leaves the bags takes its
--      mark with it, and a copy picked up later is not marked.
--   3. Nothing blue or better is offered, nor a locked slot, nor a stack
--      bigger than what the queue made of that item.
--   4. Sell marked sells through "/use bag slot", never the template's
--      "item" type (which equips gear), only with the vendor open, and no
--      more than 12 a visit.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
local events = {}
ns.RegisterEvent = function(_, event, fn) events[event] = fn end
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end

local saved = {
    CreateFrame = CreateFrame, C_Container = C_Container, C_Item = C_Item,
    InCombatLockdown = InCombatLockdown, UIParent = UIParent, GetTime = GetTime,
    C_Timer = C_Timer, MerchantFrame = MerchantFrame, GameTooltip = GameTooltip,
    GetMoney = GetMoney,
}

local function Frame()
    local frame = { attributes = {}, scripts = {}, shown = false }
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    function frame:GetAttribute(key) return self.attributes[key] end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:SetText(text) self.text = text end
    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

CreateFrame = function() return Frame() end
UIParent = Frame()
GameTooltip = Frame()
MerchantFrame = Frame()
MerchantFrame:Show()
GetTime = function() return 100 end
C_Timer = { After = function(_, fn) fn() end }

-- Bags: bag 0. Each slot { id, count, locked }.
local bags = {}
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
    GetContainerItemID = function(bag, slot)
        local item = bag == 0 and bags[slot]
        return item and item.id or nil
    end,
    GetContainerItemInfo = function(bag, slot)
        local item = bag == 0 and bags[slot]
        if not item then return nil end
        return { itemID = item.id, stackCount = item.count or 1, isLocked = item.locked == true,
            quality = item.quality }
    end,
}

-- 2001 bracers (green), 2002 cloak (blue), 2003 potion (white, stacks).
local qualities = { [2001] = 2, [2002] = 3, [2003] = 1 }
C_Item = { GetItemQualityByID = function(itemID) return qualities[itemID] end }

local combat = false
InCombatLockdown = function() return combat end

local function Held(itemID)
    local total = 0
    for _, item in pairs(bags) do
        if item.id == itemID then total = total + (item.count or 1) end
    end
    return total
end

ns.Util = {
    HasFunction = function(path)
        local value = _G
        for part in path:gmatch("[^.]+") do
            value = type(value) == "table" and value[part] or nil
        end
        return type(value) == "function"
    end,
    GetItemLabel = function(itemID) return "[item" .. itemID .. "]" end,
    Uncolored = function(text) return text end,
    GetVendorSellPrice = function() return 10 end,
    FormatMoney = function(value) return tostring(value) end,
}
ns.Inventory = {
    GetCarriedBags = function() return { 0 } end,
    GetBagCount = function(_, itemID) return Held(itemID) end,
}
ns.Config = {
    GetCharacterKey = function() return "Ana-Realm" end,
    Get = function(_, key) return ns.settings[key] end,
}
ns.settings = {}
ns.db = {}

-- Recipes 1 (bracers), 2 (cloak), 3 (potion), 4 (an enchant).
local recipes = {
    [1] = { outputItemID = 2001 }, [2] = { outputItemID = 2002 },
    [3] = { outputItemID = 2003 }, [4] = {},
}
ns.Recipes = { GetAny = function(_, recipeID) return recipes[recipeID] end }

local analyses = {}
ns.Profit = { Analyse = function(_, recipeID) return analyses[recipeID] end }
ns.Disenchant = { IsDisenchantable = function(_, itemID) return itemID == 2001 or itemID == 2002 end }

local notified = 0
ns.Queue = { Notify = function() notified = notified + 1 end }

local marksChanged = 0
ns.UI = { OnQueueMarksChanged = function() marksChanged = marksChanged + 1 end }

ns.Theme = {
    Fill = function() return Frame() end, Border = function() end,
    CreateLabel = function() return Frame() end, Unpack = function() return 1, 1, 1 end,
    TextWidth = function() return 100 end, SetBorderColor = function() end,
}
ns.Vendor = { isMerchantOpen = true }

assert(loadfile(lfs_cwd .. "/Logic/QueueActions.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/SellMarked.lua"))("Blackthornes_TS", ns)
local QA, SellMarked = ns.QueueActions, ns.SellMarked
QA:OnEnable()
SellMarked:OnEnable()

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\nthe row's action")

analyses[1] = { via = "disenchant", ways = {
    auction = { profit = 50 }, vendor = { profit = 5 }, disenchant = { profit = 80, canDisenchant = true } } }
local bracers = { recipeID = 1, quantity = 3 }

local action, chosen, choices = QA:Get(bracers)
check("starts on whichever pays most", action == "disenchant" and chosen == false)
check("offers all three for a disenchantable item a vendor buys", #choices == 3)

check("a click steps to the next way", QA:Cycle(bracers) == "vendor" and bracers.action == "vendor")
check("and round to the first", QA:Cycle(bracers) == "auction")
QA:Set(bracers, nil)
check("a right-click goes back to the best", QA:Get(bracers) == "disenchant" and bracers.action == nil)

analyses[1].ways.disenchant.canDisenchant = false
analyses[1].via = "auction"
local _, _, noDE = QA:Get(bracers)
check("no disenchant when none of your characters can", #noDE == 2 and noDE[2] == "vendor")
analyses[1].ways.disenchant.canDisenchant = true
analyses[1].via = "disenchant"

bracers.action = "disenchant"
analyses[1].ways.disenchant.canDisenchant = false
check("a picked way that is no longer open falls back", QA:Get(bracers) ~= "disenchant")
analyses[1].ways.disenchant.canDisenchant = true

check("a sub-craft gets no action", QA:Get({ recipeID = 1, quantity = 1, isDependency = true }) == nil)
check("an enchant gets no action", QA:Get({ recipeID = 4, quantity = 1 }) == nil)

print("\nmarks")

bags[1] = { id = 2001 }
bags[2] = { id = 2001 }
QA:NoteMade(bracers, 2001, 2)
local marks = ns.db.queueMarks["Ana-Realm"]
check("made items are marked with the row's action", marks[2001].action == "disenchant" and marks[2001].count == 2)

analyses[3] = { via = "auction", ways = { auction = { profit = 9 }, vendor = { profit = 1 } } }
QA:NoteMade({ recipeID = 3, quantity = 5 }, 2003, 5)
check("an auction house craft is not marked", marks[2003] == nil)

-- At the first login the bags have not been reported yet and read as
-- empty; settling then dropped every mark. A reload settles as before.
do
    local before = {}
    for id, mark in pairs(marks) do before[id] = mark.count end
    local carried = bags
    bags = {}
    events.PLAYER_ENTERING_WORLD(nil, "PLAYER_ENTERING_WORLD", true, false)
    check("the first login's empty bags take no mark", marks[2001] ~= nil and marks[2001].count == before[2001])
    bags = carried
    events.PLAYER_ENTERING_WORLD(nil, "PLAYER_ENTERING_WORLD", false, true)
    check("a reload settles against the bags", marks[2001].count == 2)
end

-- A looted bracer joins the two crafted ones: still only two marked.
bags[3] = { id = 2001 }
QA:Settle()
check("a mark never grows with the bags", marks[2001].count == 2)

bags[1] = nil
QA:Settle()
check("an item leaving the bags takes its mark", marks[2001].count == 2)
bags[2] = nil
QA:Settle()
check("down to what is carried", marks[2001].count == 1)
bags[3] = nil
QA:Settle()
check("and gone when none are left", marks[2001] == nil)

print("\nwhat the buttons may touch")

bags[1] = { id = 2001 }
bags[2] = { id = 2001, locked = true }
bags[3] = { id = 2001 }
QA:NoteMade(bracers, 2001, 2)

local itemID, bag, slot, total = QA:Next("disenchant")
check("the next disenchant is the first slot", itemID == 2001 and bag == 0 and slot == 1 and total == 2)

local slots = QA:Slots("disenchant")
check("a locked slot is skipped, and no more than are marked",
    #slots == 2 and slots[1].slot == 1 and slots[2].slot == 3)

bags[4] = { id = 2002 }
analyses[2] = { via = "disenchant", ways = { disenchant = { profit = 90, canDisenchant = true } } }
QA:NoteMade({ recipeID = 2, quantity = 1 }, 2002, 1)
local list = QA:List("disenchant")
check("a blue item is never offered", #list == 1 and list[1].itemID == 2001)

qualities[2001] = nil
check("nor one whose quality the client has not said", QA:Next("disenchant") == nil)
qualities[2001] = 2

-- A stack of 20 potions, 3 of them made on Vendor.
analyses[3].via = "vendor"
bags[5] = { id = 2003, count = 20 }
QA:NoteMade({ recipeID = 3, quantity = 3 }, 2003, 3)
check("a stack bigger than what the queue made is left alone", QA:Next("vendor") == nil)
bags[5] = { id = 2003, count = 3 }
check("a stack of what it made is offered", (QA:Next("vendor")) == 2003)

QA:NoteDisenchantClick(2001)
events.UNIT_SPELLCAST_SUCCEEDED(QA, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 13262)
check("a finished Disenchant next cast uses one mark", marks[2001].count == 1)
events.UNIT_SPELLCAST_SUCCEEDED(QA, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 13262)
check("and only the one it was clicked for", marks[2001].count == 1)

print("\nSell marked")

events.MERCHANT_SHOW(SellMarked, "MERCHANT_SHOW")
local button = SellMarked.button
check("shows at a vendor with something marked", button ~= nil and button:IsShown())

button.scripts.PreClick(button)
check("sells through /use on the bag slot, never the item type that equips gear",
    button:GetAttribute("type") == "macro" and button:GetAttribute("macrotext") == "/use 0 5")
button.scripts.PostClick(button)
check("nothing is left aimed after the click", button:GetAttribute("type") == nil
    and button:GetAttribute("macrotext") == nil)
check("the sale uses the mark", marks[2003] == nil and SellMarked.soldThisVisit == 1)

QA:NoteMade({ recipeID = 3, quantity = 3 }, 2003, 3)
ns.Vendor.isMerchantOpen = false
button.scripts.PreClick(button)
check("with the vendor gone, the click does nothing", button:GetAttribute("type") == nil)
ns.Vendor.isMerchantOpen = true

SellMarked.soldThisVisit = 12
button.scripts.PreClick(button)
check("no more than 12 a visit, so buyback can undo every sale", button:GetAttribute("type") == nil)
events.MERCHANT_SHOW(SellMarked, "MERCHANT_SHOW")
check("a new visit starts again", SellMarked.soldThisVisit == 0)

-- No Test button (the owner, 2026-10-23): untested, the click's own sale
-- is followed by one from addon code, which says whether one click may
-- sell them all.
do
    for slot = 1, 16 do if bags[slot] and bags[slot].id == 2003 then bags[slot] = nil end end
    bags[7] = { id = 2003, count = 1 }
    bags[8] = { id = 2003, count = 1 }
    for id in pairs(marks) do marks[id] = nil end
    QA:NoteMade({ recipeID = 3, quantity = 2 }, 2003, 2)
    local money = 0
    GetMoney = function() return money end
    C_Container.UseContainerItem = function(_, slot) bags[slot] = nil; money = money + 10 end
    ns.db.sellTest = nil
    button.scripts.PreClick(button)
    local aimed = button:GetAttribute("macrotext")
    -- The game locks the slot the click sold from.
    local clicked = tonumber(aimed and aimed:match("(%d+)$") or "")
    if clicked and bags[clicked] then bags[clicked].locked = true end
    button.scripts.PostClick(button)
    check("untested, the next stack is sold from addon code to check",
        clicked ~= nil and bags[clicked] ~= nil and bags[clicked == 7 and 8 or 7] == nil)
    check("and what it found is kept", ns.db.sellTest and ns.db.sellTest.result == "works"
        and ns.db.sellTest.quiet == true)
    check("so one click sells them all now", SellMarked:CanSellAll())
    C_Container.UseContainerItem = nil
end

ns.settings.sellMarkedButton = false
SellMarked:Update()
check("Settings can hide it", not button:IsShown())
ns.settings.sellMarkedButton = nil

events.MERCHANT_CLOSED(SellMarked, "MERCHANT_CLOSED")
check("closing the vendor hides it", not button:IsShown())

print(("\n%d passed, 0 failed"):format(checks))

for key, value in pairs(saved) do _G[key] = value end
