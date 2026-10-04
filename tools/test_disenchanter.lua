-- The Enchanting tab's Disenchant button, as far as it can be seen without a
-- game client (2026-09-27: "we also need ... disenchanting items in
-- inventory").
--
-- The cast itself needs the game. What this pins down is everything around
-- it: when the button is offered at all, that it is aimed at the right bag
-- slot, that it is never a macro that could equip the item, and that a slot
-- which no longer holds the item casts nothing.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end

local saved = {
    CreateFrame = CreateFrame, C_Container = C_Container, InCombatLockdown = InCombatLockdown,
    IsPlayerSpell = IsPlayerSpell, UIParent = UIParent, GetTime = GetTime,
}

-- Frames remember their attributes and scripts; anything else is a no-op.
local function Frame()
    local frame = { attributes = {}, scripts = {}, shown = false }
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    function frame:GetAttribute(key) return self.attributes[key] end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:HookScript(name, fn) self.scripts[name] = fn end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return true end
    function frame:GetLeft() return 10 end
    function frame:GetBottom() return 10 end
    function frame:GetWidth() return 100 end
    function frame:GetHeight() return 24 end
    function frame:GetEffectiveScale() return 1 end
    function frame:GetFrameStrata() return "HIGH" end
    function frame:GetFrameLevel() return 4 end
    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

CreateFrame = function() return Frame() end
UIParent = Frame()
GetTime = function() return 1 end

-- Bag 0 slot 3 holds the chest.
local bag0 = { [3] = 1001 }
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
    GetContainerItemID = function(bag, slot) return bag == 0 and bag0[slot] or nil end,
}

local combat, known = false, true
InCombatLockdown = function() return combat end
IsPlayerSpell = function() return known end

ns.Util = {
    HasFunction = function(path)
        local value = _G
        for part in path:gmatch("[^.]+") do
            value = type(value) == "table" and value[part] or nil
        end
        return type(value) == "function"
    end,
    GetItemLabel = function(itemID) return "item" .. itemID end,
}
ns.Inventory = { GetCarriedBags = function() return { 0, 1, 2, 3, 4 } end }
ns.Disenchant = { IsDisenchantable = function(_, itemID) return itemID == 1001 end }
ns.Theme = {
    Fill = function() return Frame() end, Border = function() end,
    CreateLabel = function() return Frame() end, Unpack = function() return 1, 1, 1 end,
}

assert(loadfile(lfs_cwd .. "/UI/Disenchanter.lua"))("Blackthornes_TS", ns)

local Disenchanter = ns.Disenchanter

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\nwhen the button is offered")

local result = Disenchanter:Check(1001)
check("an item in the bags can be disenchanted", result.ok and result.bag == 0 and result.slot == 3)
check("nothing picked says so", Disenchanter:Check(nil).ok == false)
check("an item that cannot be disenchanted says so", Disenchanter:Check(2002).ok == false)

known = false
check("a character without Disenchant is told", Disenchanter:Check(1001).why
    == "This character does not know Disenchant.")
known = true

combat = true
check("not during combat", Disenchanter:Check(1001).why == "Not during combat.")
combat = false

bag0[3] = nil
check("an item no longer carried says so", Disenchanter:Check(1001).why
    == "That item is no longer in your bags.")
bag0[3] = 1001

print("\nthe secure button")

local tabButton = Frame()
check("it arms", Disenchanter:Arm(tabButton, 1001, 0, 3) == true)

local overlay = Disenchanter.overlay
check("as a spell, never a macro that could equip the item",
    overlay:GetAttribute("type") == "spell" and overlay:GetAttribute("macrotext") == nil)
check("the spell is Disenchant", overlay:GetAttribute("spell") == 13262)
check("aimed at the item's bag and slot",
    overlay:GetAttribute("target-bag") == 0 and overlay:GetAttribute("target-slot") == 3)
check("and it shows over the tab's button", overlay:IsShown())

-- The item moved to another slot after the button was set.
bag0[3], bag0[7] = nil, 1001
overlay.scripts.PreClick(overlay, "LeftButton", false)
check("a moved item is followed to its new slot", overlay:GetAttribute("target-slot") == 7
    and overlay:GetAttribute("type") == "spell")

-- And gone altogether.
bag0[7] = nil
overlay.scripts.PreClick(overlay, "LeftButton", false)
check("an item that has left the bags casts nothing", overlay:GetAttribute("type") == nil)
check("and says why", printed[#printed]:find("no longer in your bags") ~= nil)

Disenchanter:Disarm()
check("disarmed, it hides", not overlay:IsShown())
check("and aims at nothing", overlay:GetAttribute("target-slot") == nil)

CreateFrame, C_Container, InCombatLockdown = saved.CreateFrame, saved.C_Container, saved.InCombatLockdown
IsPlayerSpell, UIParent, GetTime = saved.IsPlayerSpell, saved.UIParent, saved.GetTime

print(("\n%d check(s) passed\n"):format(checks))
