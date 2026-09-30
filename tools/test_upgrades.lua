-- Logic/Upgrades.lua and the arrow UI/Theme.lua draws on item icons, outside
-- WoW.
--
-- Blackthornes Equipment decides what is an upgrade; Tradeskills only draws
-- its answer. What must hold:
--   1. Without Equipment (or an Equipment too old to answer) no icon gets an
--      arrow and nothing raises.
--   2. With Equipment, gear it calls an upgrade gets the arrow and nothing
--      else does; an Equipment that raises costs the arrow, not an error.
--   3. The arrow follows its icon: hidden with it, gone when the row shows
--      another item, off when the setting is off.
--   4. Answers are remembered until something that changes them happens.

local ns = {}

-- Tests share one Lua state, so the globals replaced here are put back.
local saved = { CreateFrame = CreateFrame, UIParent = UIParent, C_Texture = C_Texture,
    C_Timer = C_Timer }
C_Timer = nil

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
    region.CreateTexture = function(self)
        local texture = Region(self)
        return texture
    end

    return setmetatable(region, { __index = function() return function() end end })
end

CreateFrame = function() return Region() end
UIParent = Region()
C_Texture = { GetAtlasInfo = function(name) return name == "bags-greenarrow" and {} or nil end }

local settings = {}
ns.Config = { Get = function(_, key) return settings[key] end }
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.RegisterEvent = function(owner, event, fn)
    ns.events = ns.events or {}
    ns.events[event] = function(...) return fn(owner, event, ...) end
end

local redraws = 0
ns.UI = { RefreshActiveTab = function() redraws = redraws + 1 end }

local function Load(path)
    local chunk = assert(loadfile(lfs_cwd .. path))
    chunk("Blackthornes_TS", ns)
end

Load("/Logic/Upgrades.lua")
Load("/UI/Theme.lua")

local Upgrades, Theme = ns.Upgrades, ns.Theme
Upgrades:OnEnable()

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local parent = Region()
local icon = Theme.CreateItemIcon(parent, 16)

-- Theme's arrow is the only texture the parent makes after the icon, so
-- find it by the atlas it was given.
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

print("")
print("without Equipment")

BlackthornesEquipment = nil
check("nothing is an upgrade", Upgrades:IsUpgrade(100), false)
Theme.SetItemIcon(icon, 100)
check("the icon shows", icon.shown, true)
check("with no arrow", ArrowShown(), false)
check("and no arrow was even made", #made, 0)

BlackthornesEquipment = { Compare = {} }
check("an Equipment with no IsUpgrade is ignored", Upgrades:IsUpgrade(100), false)

print("")
print("with Equipment")

local asked = {}
local upgrades = { [100] = true }
BlackthornesEquipment = {
    Compare = {
        IsUpgrade = function(_, itemID)
            asked[#asked + 1] = itemID
            return upgrades[itemID] == true
        end,
    },
}
Upgrades:Forget()

Theme.SetItemIcon(icon, 100)
check("an upgrade gets the arrow", ArrowShown(), true)
check("asked by item ID", asked[1], 100)

Theme.SetItemIcon(icon, 200)
check("the row showing something else loses it", ArrowShown(), false)

Theme.SetItemIcon(icon, 100)
icon:Hide()
check("hiding the icon hides the arrow", ArrowShown(), false)
icon:SetShown(true)
check("showing it again brings it back", ArrowShown(), true)

Theme.SetItemIcon(icon, nil)
check("no item: icon hidden", icon.shown, false)
check("and the arrow with it", ArrowShown(), false)

print("")
print("remembered answers")

asked = {}
Upgrades:IsUpgrade(100)
Upgrades:IsUpgrade(100)
check("asked once for two draws", #asked, 0)

upgrades[100] = false
ns.events.PLAYER_EQUIPMENT_CHANGED()
check("new gear on: asked again", Upgrades:IsUpgrade(100), false)
check("and the open tab redrawn", redraws, 1)

upgrades[300] = true
Upgrades:IsUpgrade(300)
ns.events.GET_ITEM_INFO_RECEIVED(300)
asked = {}
Upgrades:IsUpgrade(300)
check("an item's details arriving: asked again", asked[1], 300)

print("")
print("the setting and a broken Equipment")

settings.showUpgradeArrows = false
Upgrades:Forget()
Theme.SetItemIcon(icon, 300)
check("off: no arrow", ArrowShown(), false)
settings.showUpgradeArrows = nil

BlackthornesEquipment.Compare.IsUpgrade = function() error("secret value") end
Upgrades:Forget()
local ok = pcall(Theme.SetItemIcon, icon, 300)
check("an Equipment that raises does not break the icon", ok, true)
check("and draws no arrow", ArrowShown(), false)
check("the icon still shows", icon.shown, true)

BlackthornesEquipment = nil
for name, value in pairs(saved) do _G[name] = value end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "upgrade arrow checks failed")
