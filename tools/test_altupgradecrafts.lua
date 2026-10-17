-- Crafted gear that's an upgrade for another of your characters
-- (Logic/Upgrades.lua, AltFor and AltText, 2026-10-16).
--
-- Blackthornes Equipment's Butler:Advise gives `alt` when gear is no
-- upgrade here but is for another character. What must hold:
--   1. The line names the whole name, with the gain or the level it waits on.
--   2. No Equipment, no alt, a name Tradeskills does not know, or an
--      Equipment that raises: no line, nothing raises.
--   3. Answers are kept until Forget, and the setting turns it off.
--   4. Off until Show Equipment Upgrades is ticked (the owner, 2026-10-17),
--      and the box saves one value for every tab.

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.RegisterEvent = function() return true end
ns.COLORS = { profit = "ff4fd17a" }
local arrowsOn = true
local saved = {}
ns.Config = {
    Get = function(_, key)
        if key == "showUpgradeArrows" then return arrowsOn end
        return saved[key]
    end,
    Set = function(_, key, value) saved[key] = value end,
}
ns.Recipes = { GetCharacterName = function(_, key)
    if key == "Player-1-ALT" then return "Ana Stormwood" end
    return key
end }

assert(loadfile(lfs_cwd .. "/Logic/Upgrades.lua"))("Blackthornes_TS", ns)
local Upgrades = ns.Upgrades

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("  FAIL  %-52s got %s, wanted %s", label, tostring(got), tostring(want)))
    else
        print(string.format("  ok    %-52s %s", label, tostring(got)))
    end
end

local CHEST, BOOTS, RING, MINE, STRANGER = 101, 102, 103, 104, 105
local asked = 0
local savedEquipment = BlackthornesEquipment

print("\nwith Equipment")
BlackthornesEquipment = { Butler = { Advise = function(_, id)
    asked = asked + 1
    if id == CHEST then return { alt = { key = "Player-1-ALT", gain = 10.6 } } end
    if id == BOOTS then return { alt = { key = "Player-1-ALT", gain = 4, level = 32 } } end
    if id == RING then return { alt = { key = "Player-1-ALT" } } end
    if id == MINE then return { upgrade = "now", gain = 8 } end
    if id == STRANGER then return { alt = { key = "Player-9-NOBODY", gain = 5 } } end
end } }

check("off by default", Upgrades:AltText(CHEST), nil)
check("asks Equipment nothing while off", asked, 0)
check("not shown by default", Upgrades:ShowsAlts(), false)
Upgrades:SetShowsAlts(true)
check("ticked: saved", saved.showAltUpgrades, true)

check("with the gain", Upgrades:AltText(CHEST), "Upgrade for Ana Stormwood, +11%")
check("waiting on their level", Upgrades:AltText(BOOTS), "Upgrade for Ana Stormwood at level 32")
check("an empty slot, no gain", Upgrades:AltText(RING), "Upgrade for Ana Stormwood")
check("an upgrade here is no alt line", Upgrades:AltText(MINE), nil)
check("a character we can't name: none", Upgrades:AltText(STRANGER), nil)
check("on a row, after the name in green", Upgrades:WithAltText("Silk Vest", CHEST),
    "Silk Vest  |cff4fd17aUpgrade for Ana Stormwood, +11%|r")
check("a row with none stays as it is", Upgrades:WithAltText("Silk Vest", MINE), "Silk Vest")

local before = asked
Upgrades:AltText(CHEST)
check("kept: Equipment asked once", asked, before)
Upgrades:Forget()
Upgrades:AltText(CHEST)
check("asked again after Forget", asked, before + 1)

arrowsOn = false
Upgrades:Forget()
check("off with the upgrade setting", Upgrades:AltText(CHEST), nil)
arrowsOn = true

Upgrades:SetShowsAlts(false)
check("unticked: saved", saved.showAltUpgrades, false)
check("unticked: no line", Upgrades:AltText(CHEST), nil)
Upgrades:SetShowsAlts(true)

print("\nwithout Equipment, or one that raises")
Upgrades:Forget()
BlackthornesEquipment = nil
check("no Equipment", Upgrades:AltText(CHEST), nil)
Upgrades:Forget()
BlackthornesEquipment = { Butler = { Advise = function() error("boom") end } }
check("a raise costs the line, not an error", Upgrades:AltText(CHEST), nil)

BlackthornesEquipment = savedEquipment
Upgrades:Forget()

if failures > 0 then error(("%d check(s) failed"):format(failures), 0) end
print("all checks passed")
