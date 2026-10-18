-- Item names show in their rarity colour (the owner asked: "Item names
-- should show their rarity color always").
--
--   1. The chat line after a craft ("made 1 of [Bolt of Silk Cloth]...")
--      names the craft by the item's own link, else its name coloured, and
--      only the name is coloured: the words round it keep theirs.
--   2. A shopping list line shows the plain name in its rarity colour.
--   3. The queue footer's craft bar ("Bolt of Silk Cloth   3 more") wears the
--      rarity colour of what the craft makes, and asks the client again at
--      most once a second while it does not know it yet.
--   4. Names the client has not loaded yet are left plain, never wrongly
--      coloured.

local GLOBALS = { "C_Item", "C_TradeSkillUI", "ITEM_QUALITY_COLORS", "GetTime",
                  "UnitCastingInfo", "CreateFrame" }
local saved = {}
for _, name in ipairs(GLOBALS) do saved[name] = { value = _G[name] } end

local SILK, BOLT, RECIPE = 4306, 4305, 3839
local GREEN = { r = 0.12, g = 1, b = 0 }
ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 }, [2] = GREEN }

local known = { [SILK] = { "Silk Cloth", 1 }, [BOLT] = { "Bolt of Silk Cloth", 2 } }
local links = {}
local asked = 0
C_Item = {
    GetItemInfo = function(itemID)
        local item = known[itemID]
        if not item then return nil end
        return item[1], links[itemID], item[2]
    end,
    RequestLoadItemDataByID = function() asked = asked + 1 end,
}

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
local Util = ns.Util

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-52s %-32s %s", label, tostring(got), ok and "ok" or ("WRONG, wanted " .. tostring(want))))
end

local GREEN_CODE = "|cff1fff00"

print("")
print("the name inside a sentence")
do
    check("a known green is wrapped in its colour", Util.ColorItemName(BOLT, "Bolt of Silk Cloth"),
        GREEN_CODE .. "Bolt of Silk Cloth|r")
    check("a link keeps its own colour", Util.ColorItemName(BOLT, "|cff1eff00[Bolt]|r"), "|cff1eff00[Bolt]|r")
    check("an item not loaded yet stays plain", Util.ColorItemName(99999, "Mystery Bolt"), "Mystery Bolt")
    check("and the client is asked for it", asked > 0, true)
    check("the plain name, for a label coloured apart", Util.GetItemName(BOLT), "Bolt of Silk Cloth")
end

print("")
print("the chat line after a craft")
do
    assert(loadfile(lfs_cwd .. "/Data/Recipes.lua"))("Blackthornes_TS", ns)
    local Recipes = ns.Recipes
    local fake = setmetatable({
        Get = function(_, id) if id == RECIPE then return { name = "Bolt of Silk Cloth", outputItemID = BOLT } end end,
    }, { __index = Recipes })

    local line = string.format("made %d of %s, as materials for another craft", 1, fake:GetDisplayLink(RECIPE))
    check("no link yet: the name coloured, the words plain", line,
        "made 1 of " .. GREEN_CODE .. "Bolt of Silk Cloth|r, as materials for another craft")

    links[BOLT] = "|cff1eff00|Hitem:4305::::::::|h[Bolt of Silk Cloth]|h|r"
    check("with the item's link, the link", fake:GetDisplayLink(RECIPE), links[BOLT])
    links[BOLT] = nil
end

print("")
print("the shopping list line")
do
    -- The same steps CraftPanel.UpdateShoppingRow takes for a line still to buy.
    local label = { SetTextColor = function(self, r, g, b) self.r, self.g, self.b = r, g, b end }
    local r, g, b = Util.GetItemQualityColor(BOLT)
    label:SetTextColor(r, g, b)
    check("the bolt's line is green", label.g == 1 and label.r == GREEN.r, true)
    check("and named plainly", Util.GetItemName(BOLT), "Bolt of Silk Cloth")
end

print("")
print("the queue footer's craft bar")
do
    local now = 10
    GetTime = function() return now end
    local casting = { name = "Bolt of Silk Cloth", text = "", startMS = 9000, endMS = 13000, spellID = RECIPE }
    UnitCastingInfo = function(unit)
        if unit ~= "player" or not casting then return nil end
        return casting.name, casting.text, nil, casting.startMS, casting.endMS, true,
            nil, nil, casting.spellID
    end
    C_TradeSkillUI = { GetRemainingRecasts = function() return 3 end }

    local function Region()
        local reg = { shown = true, text = "", sets = 0 }
        function reg:SetPoint() end
        function reg:SetText(t) self.text = t end
        function reg:SetWidth() end
        function reg:SetColorTexture() end
        function reg:SetTextColor(red, green, blue) self.colour = { red, green, blue }; self.sets = self.sets + 1 end
        function reg:Show() self.shown = true end
        function reg:Hide() self.shown = false end
        function reg:IsShown() return self.shown end
        return reg
    end

    local ui = { Theme = {}, Util = Util, CastBarOnTop = { IsCrafting = function() return true end } }
    ui.NewModule = function(name) local m = {}; ui[name] = m; return m end
    ui.Recipes = { GetAny = function(_, id)
        if id == RECIPE then return { outputItemID = casting.output or BOLT } end
    end }
    ui.Theme.Unpack = function() return 0.5, 0.5, 0.5 end
    ui.Theme.CreateLabel = function() return Region() end
    ui.Theme.CreatePanel = function(p)
        local f = Region()
        f.parent = p
        function f:GetParent() return self.parent end
        function f:SetSize(w) self.w = w end
        function f:GetWidth() return self.w end
        function f:CreateTexture() return Region() end
        return f
    end
    local driver
    CreateFrame = function() return { SetScript = function(_, _, fn) driver = fn end } end
    assert(loadfile(lfs_cwd .. "/UI/CraftProgress.lua"))("Blackthornes_TS", ui)

    local parent = Region()
    function parent:IsVisible() return self.shown end
    local bar = ui.CraftProgress:Create(parent, { width = 202, height = 16, covers = Region() })
    driver()
    check("the bar names the craft", bar.label.text, "Bolt of Silk Cloth")
    check("in the green of the bolt", bar.label.colour and bar.label.colour[2] == 1
        and bar.label.colour[1] == GREEN.r, true)

    local sets = bar.label.sets
    now = now + 0.1
    driver()
    check("not coloured again on every redraw", bar.label.sets, sets)

    -- A craft whose item the client has not loaded: plain, then asked again
    -- only after a second.
    casting = { name = "Odd Bolt", text = "", startMS = 9000, endMS = 13000, spellID = RECIPE + 1 }
    ui.Recipes.GetAny = function(_, id) if id == RECIPE + 1 then return { outputItemID = 77777 } end end
    driver()
    check("an unknown item is plain text", bar.label.colour and bar.label.colour[1], 0.5)
    local before = asked
    now = now + 0.2
    driver()
    check("not asked again within the second", asked, before)
    now = now + 1.1
    driver()
    check("asked again after it", asked > before, true)
end

for _, name in ipairs(GLOBALS) do _G[name] = saved[name].value end

print("")
if failed > 0 then
    error(string.format("FAIL -- %d of %d rarity colour checks wrong", failed, passed + failed))
end
print(string.format("PASS -- item names in their rarity colour (%d checks)", passed))
