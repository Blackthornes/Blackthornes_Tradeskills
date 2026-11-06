-- The Enchant strip under the game's recipe pane (Trent, 2026-11-06: the
-- floating window opened behind the queued crafts and was hard to move, and
-- he wanted it to feel part of the Enchanting window). It sits at the bottom
-- of the recipe pane, lifted clear of the game's Create buttons.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Theme, ns.Widgets = {}, {}
ns.COLORS = { loss = "ffe5604f", profit = "ff4fd18b" }
ns.Util = { FormatMoney = function(c) return c .. "c" end }
assert(loadfile(lfs_cwd .. "/UI/EnchantWindow.lua"))("Blackthornes_TS", ns)
local UI = ns.EnchantWindowUI

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local function F(shown, fields)
    local f = fields or {}
    f.IsVisible = function() return shown end
    return f
end

print("\nwhat it anchors to")
local form = F(true)
_G.ProfessionsFrame = F(true, { CraftingPage = F(true, { SchematicForm = form }) })
local a = UI.FindAnchor()
check("the recipe pane first", a and a.frame == form and a.name:find("SchematicForm", 1, true) ~= nil)
check("with the game's window to match", a.game == _G.ProfessionsFrame)
_G.ProfessionsFrame.CraftingPage.SchematicForm = F(false)
a = UI.FindAnchor()
check("the crafting page when the pane hides", a and a.name == "ProfessionsFrame.CraftingPage")
_G.ProfessionsFrame = nil
local detail = F(true)
_G.TradeSkillFrame, _G.TradeSkillDetailScrollFrame = F(true), detail
a = UI.FindAnchor()
check("the older detail pane on older clients", a and a.frame == detail)
_G.TradeSkillFrame, _G.TradeSkillDetailScrollFrame = nil, nil
check("nothing with no window open", UI.FindAnchor() == nil)

print("\nclear of the Create buttons")
check("no lift with no buttons", UI.Lift(100, {}) == 0)
check("lifted over a button at the pane's foot", UI.Lift(100, { { top = 126, bottom = 104 } }) == 26 + UI.GAP)
check("the tallest button wins", UI.Lift(100, { { top = 120, bottom = 104 }, { top = 130, bottom = 106 } }) == 30 + UI.GAP)
check("a button under the pane doesn't lift it", UI.Lift(100, { { top = 98, bottom = 76 } }) == 0)
check("a button high up doesn't lift it", UI.Lift(100, { { top = 400, bottom = 380 } }) == 0)

print("\nwhen it shows")
local up = { on = true, open = true, enchanting = true, combat = false, enchant = {} }
check("an enchant with everything right", UI.ShouldShow(up) == true)
local function without(key, value)
    local s = {}
    for k, v in pairs(up) do s[k] = v end
    s[key] = value
    return UI.ShouldShow(s)
end
check("not with the setting off", without("on", false) == false)
check("not with no window open", without("open", nil) == false)
check("not outside Enchanting", without("enchanting", false) == false)
check("not in a fight", without("combat", true) == false)
check("not for a recipe that isn't an enchant", without("enchant", nil) == false)

print("\nthe materials line")
local line = UI.InfoLine({ { itemID = 1, have = 3, need = 2, short = 0 }, { itemID = 2, have = 0, need = 1, short = 1 } },
    250, function(id) return id == 1 and "Strange Dust" or "Lesser Magic Essence" end)
check("names each material", line:find("Strange Dust", 1, true) and line:find("Lesser Magic Essence", 1, true))
check("green when you have enough", line:find("|cff4fd18b3/2|r", 1, true) ~= nil)
check("red when you're short", line:find("|cffe5604f0/1|r", 1, true) ~= nil)
check("ends with the cost", line:sub(-4) == "250c")
check("no cost when it's free", not UI.InfoLine({}, 0):find("c", 1, true))

print("\nthe probe says where it sits")
_G.ProfessionsFrame = F(true, { CraftingPage = F(true, { SchematicForm = F(true) }) })
local lines = UI:ProbeLines()
local function find(label)
    for _, l in ipairs(lines) do if l[1] == label then return l[2] end end
end
check("names the frame it anchored to", (find("enchant strip") or ""):find("SchematicForm", 1, true) ~= nil)
check("says how far it lifted", find("enchant strip lift") ~= nil)
check("says what it follows", (find("enchant strip pick") or ""):find("hook", 1, true) ~= nil)
_G.ProfessionsFrame = nil

print(("\n%d check(s) passed\n"):format(checks))
