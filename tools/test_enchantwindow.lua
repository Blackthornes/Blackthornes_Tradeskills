-- The Enchant window's logic (Trent said build it, 2026-11-05), as far as it
-- can be seen without a game client: off by default, what blocks the
-- Enchant button and why, the three ways a click casts and the order they
-- are tried in, the Put It On macro, reading what is on an item now, and
-- the one-time What's New card.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.Debug, ns.Warn = function() end, function() end, function() end
ns.db = { settings = {} }
ns.Config = {
    Get = function(_, key) return ns.db.settings[key] end,
    Set = function(_, key, value) ns.db.settings[key] = value end,
}

ns.Util = {}
function ns.Util.ResolvePath(path)
    local current = _G
    for segment in path:gmatch("[^%.]+") do
        if type(current) ~= "table" then return nil, false end
        local value = current[segment]
        if value == nil then return nil, false end
        current = value
    end
    return current, true
end
function ns.Util.HasFunction(path)
    local value, found = ns.Util.ResolvePath(path)
    return found and type(value) == "function"
end
ns.Util.GetItemLabel = function(itemID) return ({ [10] = "Soul Dust", [11] = "Lesser Magic Essence" })[itemID] end

local bags = { [10] = 1, [11] = 2 }
ns.Inventory = { GetBagCount = function(_, itemID) return bags[itemID] or 0 end }
ns.Cost = { GetReagentCost = function(_, itemID, need) return need * 100 end }

local saved = {
    InCombatLockdown = InCombatLockdown, C_TradeSkillUI = C_TradeSkillUI, ItemLocation = ItemLocation,
    SpellIsTargeting = SpellIsTargeting, GetInventoryItemLink = GetInventoryItemLink, GetTime = GetTime,
    C_Container = C_Container, C_TooltipInfo = C_TooltipInfo, C_Timer = C_Timer,
}

local combat, targeting = false, false
InCombatLockdown = function() return combat end
SpellIsTargeting = function() return targeting end
GetTime = function() return 1 end
C_Timer = nil

local calls = {}
local oneWorks = true
C_TradeSkillUI = {
    CraftEnchant = function(recipeID, count, _, location)
        calls[#calls + 1] = { "CraftEnchant", recipeID, location }
        if not oneWorks then error("no") end
    end,
    CraftRecipe = function(recipeID, count)
        calls[#calls + 1] = { "CraftRecipe", recipeID }
    end,
}
ItemLocation = {
    CreateFromEquipmentSlot = function(_, slot) return { slot = slot } end,
    CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end,
}
local worn = { [9] = "|cffffffff|Hitem:2000:0:0|h[Bracers]|h|r" }
GetInventoryItemLink = function(_, slot) return worn[slot] end
C_Container = { GetContainerItemLink = function(bag, slot)
    if bag == 0 and slot == 4 then return "|cff1eff00|Hitem:3000:41:0|h[Cloak]|h|r" end
end }
C_TooltipInfo = { GetBagItem = function()
    return { lines = { { leftText = "Cloak" }, { leftText = "Enchanted: Minor Health" } } }
end }

assert(loadfile(lfs_cwd .. "/Logic/EnchantWindow.lua"))("Blackthornes_TS", ns)
local EW = ns.EnchantWindow

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\nthe setting")
check("off until ticked", EW:IsOn() == false)
EW:SetOn(true)
check("ticked, it is on", EW:IsOn() == true and ns.db.settings.enchantWindow == true)
EW:SetOn(false)

print("\nmaterials and the button")
local enchant = { recipeID = 7418, materials = { { itemID = 10, need = 2 }, { itemID = 11, need = 1 } } }
local bracers = { worn = true, slot = 9, link = worn[9] }
local rows, ready, short, cost = EW:MaterialState(enchant)
check("one material short", ready == 0 and short and short.itemID == 10 and short.short == 1)
check("both rows listed with what you have", #rows == 2 and rows[1].have == 1 and rows[2].have == 2)
check("the cost adds up", cost == 300)
check("short says what is missing", EW:Blocked(enchant, bracers) == "You need 1 more Soul Dust.")
check("no item says to pick one", EW:Blocked(enchant, nil) == "Pick an item first.")
bags[10] = 4
check("with enough, nothing blocks it", EW:Blocked(enchant, bracers) == nil)
combat = true
check("never in a fight", EW:Blocked(enchant, bracers) == "Wait until the fight ends.")
local result, why = EW:Cast(enchant, bracers)
check("and a click in a fight casts nothing", result == nil and why and #calls == 0)
combat = false

print("\nthe ways a click casts")
check("one click first when the client has CraftEnchant", EW:Way() == "one")
result = EW:Cast(enchant, bracers)
check("it casts on the worn bracers", result == "cast" and calls[1][1] == "CraftEnchant"
    and calls[1][2] == 7418 and calls[1][3].slot == 9)
oneWorks = false
calls = {}
result = EW:Cast(enchant, bracers)
check("a refused one click falls back to Put It On", result == "target"
    and calls[#calls][1] == "CraftRecipe")
check("and is remembered for the probe", ns.db.settings.enchantWindowSeen.one == "failed")
check("the next click goes straight to the second way", EW:Way() == "two")
ns.db.settings.enchantWindowWay = "glow"
check("the way can be set by hand for testing", EW:Way() == "glow")
ns.db.settings.enchantWindowWay = nil

print("\nPut It On")
check("only while the spell waits", EW:PutOnTarget() == nil)
targeting = true
check("then it names the item", EW:PutOnTarget() == bracers)
worn[9] = nil
check("an item that left its slot gets nothing", EW:PutOnTarget() == nil)
worn[9] = bracers.link
check("a worn item is used by slot", EW.PutOnMacro(bracers) == "/use 9")
check("a bag item by bag and slot", EW.PutOnMacro({ bag = 0, slot = 4 }) == "/use 0 4")
targeting = false

print("\nwhat is on it now")
local cloak = { bag = 0, slot = 4, link = "|cff1eff00|Hitem:3000:41:0|h[Cloak]|h|r" }
check("the enchant ID from the link", EW.EnchantID(cloak.link) == 41 and EW.EnchantID(bracers.link) == 0)
check("nothing on it reads as nothing", EW:CurrentEnchant(bracers) == nil)
check("the tooltip names what is on it", EW:CurrentEnchant(cloak) == "Minor Health")

print("\nthe item to start on")
local items = { { worn = true, slot = 9, gain = 1 }, { bag = 0, slot = 4, gain = 3 } }
check("the biggest gain first", EW.StartItem(items) == items[2])
check("the one picked before when it still fits", EW.StartItem(items, "w9") == items[1])
check("nothing when nothing gains", EW.StartItem({ { worn = true, slot = 9 } }) == nil)

print("\nthe What's New card")
local tip
for _, t in ipairs(ns.WHATS_NEW_TIPS or {}) do if t.key == "enchantWindow" then tip = t end end
check("there is one", tip ~= nil and type(tip.paragraphs) == "table")
check("due while the window is off", tip.due() == true)
tip.run()
check("its button turns it on", EW:IsOn() == true and tip.due() == false)

InCombatLockdown, C_TradeSkillUI, ItemLocation = saved.InCombatLockdown, saved.C_TradeSkillUI, saved.ItemLocation
SpellIsTargeting, GetInventoryItemLink, GetTime = saved.SpellIsTargeting, saved.GetInventoryItemLink, saved.GetTime
C_Container, C_TooltipInfo, C_Timer = saved.C_Container, saved.C_TooltipInfo, saved.C_Timer

print(("\n%d check(s) passed\n"):format(checks))
