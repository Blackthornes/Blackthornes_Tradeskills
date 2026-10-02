-- The upgrade arrow for random-suffix gear, outside WoW.
--
-- "of the Monkey" and "of the Eagle" share one item ID, so asked by ID every
-- suffix got the plain item's answer. What must hold:
--   1. With a bag link, Equipment is asked about that link, and each copy's
--      answer is kept under its own item string.
--   2. Without a link, it is asked by item ID, as before.
--   3. A link the client will not let addons read falls back to the item ID
--      and raises nothing.
--   4. Theme.SetItemIcon passes the link through, so the arrow follows it.

local GLOBALS = { "CreateFrame", "UIParent", "C_Texture", "C_Timer", "BlackthornesEquipment" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end
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
    region.CreateTexture = function(self) return Region(self) end

    return setmetatable(region, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return function() end end
    end })
end

CreateFrame = function() return Region() end
UIParent = Region()
C_Texture = { GetAtlasInfo = function(name) return name == "bags-greenarrow" and {} or nil end }

local ns = {}
ns.Config = { Get = function() return nil end }
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

local MONKEY = "|cff1eff00|Hitem:15210::::::-12:1:60|h[Raider Shortsword of the Monkey]|h|r"
local EAGLE = "|cff1eff00|Hitem:15210::::::-19:1:60|h[Raider Shortsword of the Eagle]|h|r"
-- The same copy, written by another window with another colour code.
local MONKEY_AGAIN = "|cffffffff|Hitem:15210::::::-12:1:60|h[Raider Shortsword of the Monkey]|h|r"
local SECRET = "|cff1eff00|Hitem:15210::::::-5:1:60|h[secret]|h|r"

-- Equipment calls only the Monkey suffix an upgrade.
local asked = {}
BlackthornesEquipment = {
    Compare = {
        IsUpgrade = function(_, item)
            asked[#asked + 1] = item
            return type(item) == "string" and item:find("item:15210::::::%-12:") ~= nil
        end,
    },
}

print("\nasking by link")

check("by item ID it is the plain item's answer", Upgrades:IsUpgrade(15210) == false
    and asked[1] == 15210)
check("with the Monkey's link, Equipment is asked about that copy", Upgrades:IsUpgrade(15210, MONKEY) == true
    and asked[2] == MONKEY)
check("the Eagle gets its own answer", Upgrades:IsUpgrade(15210, EAGLE) == false and asked[3] == EAGLE)

asked = {}
check("each answer is kept under its item string", Upgrades:IsUpgrade(15210, MONKEY_AGAIN) == true
    and Upgrades:IsUpgrade(15210, EAGLE) == false and #asked == 0)
check("the ID's own answer is kept apart from them", Upgrades:IsUpgrade(15210) == false and #asked == 0)

Upgrades:Forget()
Upgrades:IsUpgrade(15210, MONKEY)
check("forgetting asks again", #asked == 1)

print("\na link the client will not let addons read")

-- Matching it raises, the way a secret value does in an instance.
local realMatch = string.match
string.match = function(text, ...)
    if text == SECRET then error("secret value") end
    return realMatch(text, ...)
end
asked = {}
local ok, answer = pcall(Upgrades.IsUpgrade, Upgrades, 15210, SECRET)
string.match = realMatch

check("raises nothing", ok)
check("and falls back to the item ID", answer == false and asked[1] == 15210)

print("\nthe arrow on an icon")

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

Theme.SetItemIcon(icon, 15210)
check("by item ID: no arrow", ArrowShown() == false)
Theme.SetItemIcon(icon, 15210, MONKEY)
check("with the Monkey's link: the arrow", ArrowShown() == true)
Theme.SetItemIcon(icon, 15210, EAGLE)
check("with the Eagle's: none", ArrowShown() == false)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print(("\n%d check(s) passed\n"):format(checks))
