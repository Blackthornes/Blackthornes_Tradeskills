-- The green arrow on enchants that are better for you, outside WoW.
--
-- Blackthornes Equipment says which enchant beats what is on the gear the
-- character wears (its Enchants:ForRecipe). What must hold:
--   1. Upgrades:EnchantFor asks it once per recipe, in a pcall, and keeps
--      the answer until Forget; a raising or missing Equipment is nil.
--   2. EnchantText says "For you: Chest +3%", or "Chest +3%" short.
--   3. With the upgrade arrows setting off, nothing is asked.
--   4. Theme.SetSpellIcon shows the spell's icon, with the arrow only when
--      asked, and hides the icon when the client has none.

local GLOBALS = { "CreateFrame", "UIParent", "C_Texture", "C_Timer", "C_Spell",
  "GetSpellTexture", "BlackthornesEquipment" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end
C_Timer = nil
GetSpellTexture = nil

local function Region(parent)
    local region = { shown = true, parent = parent }
    region.Show = function(self) self.shown = true end
    region.Hide = function(self) self.shown = false end
    region.SetShown = function(self, on) self.shown = on and true or false end
    region.IsShown = function(self) return self.shown end
    region.SetSize = function(self, w, h) self.width, self.height = w, h end
    region.SetTexture = function(self, path) self.texture = path end
    region.SetAtlas = function(self, name) self.atlas = name end
    region.GetParent = function(self) return self.parent end
    region.CreateTexture = function(self) return Region(self) end
    return setmetatable(region, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return function() end end
    end })
end

CreateFrame = function() return Region() end
UIParent = Region()
C_Texture = { GetAtlasInfo = function(name) return name == "bags-greenarrow" and {} or nil end }
C_Spell = { GetSpellTexture = function(id) return id == 7857 and 135913 or nil end }

local settings = {}
local ns = {}
ns.Config = { Get = function(_, key) return settings[key] end }
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.RegisterEvent = function() end
ns.UI = { RefreshActiveTab = function() end }

assert(loadfile(lfs_cwd .. "/Logic/Upgrades.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/Theme.lua"))("Blackthornes_TS", ns)
local Upgrades, Theme = ns.Upgrades, ns.Theme

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

print("\nasking Equipment")
local asked = 0
BlackthornesEquipment = {
    Enchants = {
        ForRecipe = function(_, recipeID)
            asked = asked + 1
            if recipeID == 7857 then return { slot = "Chest", slotID = 5, gain = 3, best = true } end
            if recipeID == 7858 then return { slot = "Back", slotID = 15 } end
            if recipeID == 666 then error("boom") end
            return nil
        end,
    },
}

local chest = Upgrades:EnchantFor(7857)
check("the slot and gain", chest and chest.slot == "Chest" and chest.gain == 3 and chest.best == true)
check("asked once", asked == 1)
check("for you text", Upgrades:EnchantText(7857) == "For you: Chest +3%")
check("short text", Upgrades:EnchantText(7857, true) == "Chest +3%")
check("no gain says the slot", Upgrades:EnchantText(7858) == "For you: Back")
check("better for nothing worn is nil", Upgrades:EnchantFor(1) == nil and Upgrades:EnchantText(1) == nil)
asked = 0
Upgrades:EnchantFor(1)
check("a nil answer is kept too", asked == 0)
check("a raising Equipment is nil", Upgrades:EnchantFor(666) == nil)

Upgrades:Forget()
asked = 0
Upgrades:EnchantFor(7857)
check("Forget asks again", asked == 1)

settings.showUpgradeArrows = false
Upgrades:Forget()
asked = 0
check("arrows off, nothing", Upgrades:EnchantFor(7857) == nil and asked == 0)
settings.showUpgradeArrows = nil

BlackthornesEquipment = { Compare = {} }
Upgrades:Forget()
check("an older Equipment says nothing", Upgrades:EnchantFor(7857) == nil)

print("\nthe spell's icon")
local parent = Region()
local icon = Theme.CreateItemIcon(parent, 16)
local made = {}
parent.CreateTexture = function(self)
    local texture = Region(self)
    made[#made + 1] = texture
    return texture
end
local function ArrowShown()
    for _, texture in ipairs(made) do
        if texture.atlas == "bags-greenarrow" then return texture.shown end
    end
    return false
end

Theme.SetSpellIcon(icon, 7857, false)
check("the icon shows", icon:IsShown() and icon.texture == 135913)
check("no arrow when not better", ArrowShown() == false)
Theme.SetSpellIcon(icon, 7857, true)
check("the arrow when better", ArrowShown() == true)
Theme.SetSpellIcon(icon, 1, true)
check("no icon from the client hides it", not icon:IsShown())
check("and its arrow", ArrowShown() == false)
Theme.SetItemIcon(icon, nil)
check("an item icon after clears it", not icon:IsShown())

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print(("\n%d check(s) passed\n"):format(checks))
