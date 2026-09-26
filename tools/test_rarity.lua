-- What a row in the Profit list says about an item, without a game client.
--
-- The list used to grey a craft's name out when the materials were not in the
-- bags. That read as "this item is junk" rather than "you are short of
-- silk", and it cost the one thing the name was carrying: rarity, which is
-- how a player decides whether a craft is worth making at all.
--
-- So the name is always the item's quality colour now, and "can I make it"
-- moved to its own MAKE column. This checks both, including the two cases
-- that used to be indistinguishable: an item you cannot make, and one the
-- client has not sent us yet.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.Print, ns.Debug, ns.Warn = function() end, function() end, function() end

local registeredEvents = {}
ns.RegisterEvent = function(_, event, fn)
    registeredEvents[event] = fn
    return true
end

--------------------------------------------------------------------------------
-- A widget layer that only remembers what was written to it
--------------------------------------------------------------------------------

-- Any method this test does not care about answers as a no-op, so the tab can
-- build its toolbar, headings and detail panel undisturbed.
local function Stub(fields)
    local frame = fields or {}

    frame.GetParent = frame.GetParent or function() return Stub() end
    frame.IsVisible = frame.IsVisible or function() return true end

    return setmetatable(frame, { __index = function(self, key)
        local noop = function() end
        rawset(self, key, noop)
        return noop
    end })
end

local function Label()
    return Stub({
        text = "",
        color = nil,
        SetText = function(self, value) self.text = tostring(value) end,
        SetTextColor = function(self, a, b, c) self.color = { a, b, c } end,
    })
end

CreateFrame = function() return Stub() end
C_Timer = { After = function() end, NewTicker = function() return Stub() end }

ns.Theme = {
    FONT = "font",
    sizes = { tiny = 10, small = 11, normal = 12, large = 14, title = 16 },
    CreateLabel = function() return Label() end,
    CreatePanel = function() return Stub() end,
    CreateDivider = function() return Stub() end,

    -- Palette entries come back as their own name, so an assertion can say
    -- which one a cell was painted with.
    Unpack = function(key) return key end,
    ProfitColor = function(value) return (value or 0) >= 0 and "profit" or "loss" end,

    -- The skill-up star. It remembers the tier it was last set to, so a row
    -- can be asked whether it is wearing one -- false rather than nil, because
    -- the stub answers a missing field with a no-op function.
    CreateMark = function() return Stub({ tier = false }) end,
    SetMark = function(mark, tier) mark.tier = tier or false end,

    -- The house trim: drawn, never asserted on.
    AccentStripe = function() return Stub() end,
    CreateItemIcon = function() return Stub() end,
    SetItemIcon = function() end,
    CreateBar = function() return Stub() end,
    CreateHeading = function() return Stub({ rule = Stub() }) end,
    StyleHeading = function(label) label.rule = Stub(); return label end,
}

ns.Widgets = {
    CreateSearchBox = function() return Stub() end,
    CreateDropdown = function() return Stub() end,
    CreateCheckbox = function() return Stub() end,
    CreateNumberBox = function() return Stub() end,
    CreateButton = function() return Stub() end,
}

--------------------------------------------------------------------------------
-- What the client knows about each item
--------------------------------------------------------------------------------

local GREEN = { 0.12, 1.00, 0.00 }
local BLUE  = { 0.00, 0.44, 0.87 }

local quality = {}

ns.Util = {
    -- Nil for an item the client has not sent yet, which is the case the
    -- redraw exists for.
    GetItemQualityColor = function(itemID)
        local color = quality[itemID]
        if not color then return end
        return color[1], color[2], color[3]
    end,

    FormatMoney = function(copper) return tostring(copper or 0) end,
    FormatAge = function() return "1h" end,
    GetItemLabel = function(itemID) return "item" .. tostring(itemID) end,
    HasFunction = function() return false end,
}

ns.Profit = { GetRanked = function() return {} end, Analyse = function() return nil end }
ns.Recipes = { Count = function() return 1 end, GetAll = function() return {} end }
ns.Prices = { Count = function() return 1 end }
ns.Auctions = { SetLimit = function() end }
ns.Config = { Get = function() return 0 end }

--------------------------------------------------------------------------------
-- Load the tab and take hold of its row callbacks
--------------------------------------------------------------------------------

local createRow, updateRow

ns.Widgets.CreateScrollList = function(_, opts)
    createRow, updateRow = opts.createRow, opts.updateRow
    return Stub({ SetData = function() end })
end

local tab
ns.UI = Stub({
    RegisterTab = function(_, registered) tab = registered end,
})

do
    local chunk = assert(loadfile(lfs_cwd .. "/UI/Tab_Profit.lua"))
    chunk("Blackthornes_TS", ns)
end

assert(tab, "Tab_Profit did not register a tab")
tab.build(Stub())
assert(updateRow, "Tab_Profit did not hand over its row callbacks")

local function Row()
    local row = Stub()
    createRow(row)
    return row
end

--------------------------------------------------------------------------------

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-56s %-10s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function checkColor(label, got, want)
    got = got or {}
    check(label, table.concat({ tostring(got[1]), tostring(got[2]), tostring(got[3]) }, ","),
        table.concat({ tostring(want[1]), tostring(want[2]), tostring(want[3]) }, ","))
end

print("")
print("Profit list, a craft you can make")

quality[2589] = GREEN

local row = Row()
updateRow(row, {
    recipeID = 1, name = "Bolt of Linen Cloth", outputItemID = 2589,
    priceable = true, craftableNow = 4, stock = 0,
    totalCost = 100, revenue = 300, profit = 200, margin = 0.66, age = 60,
})

checkColor("the name carries the item's quality colour", row.name.color, GREEN)
check("MAKE says how many the materials cover", row.cells.make.text, "4")
check("and is not calling for attention", row.cells.make.color[1], "text")

print("")
print("Profit list, a craft you are short of materials for")

quality[6889] = BLUE

row = Row()
updateRow(row, {
    recipeID = 2, name = "Gyrochronatom", outputItemID = 6889,
    priceable = true, craftableNow = 0, stock = 0,
    totalCost = 100, revenue = 300, profit = 200, margin = 0.66, age = 60,
})

checkColor("rarity still shows: this is the point of the change", row.name.color, BLUE)
check("MAKE reads zero", row.cells.make.text, "0")
check("in the colour that says something is missing", row.cells.make.color[1], "loss")

print("")
print("Profit list, a craft with no price data")

row = Row()
updateRow(row, {
    recipeID = 3, name = "Heavy Linen Bandage", outputItemID = 2589,
    priceable = false, reason = "output has no price data", craftableNow = 2,
})

checkColor("rarity shows on an unpriceable craft too", row.name.color, GREEN)
check("MAKE is filled before the early exit", row.cells.make.text, "2")
check("and the missing price is still reported", row.cells.profit.text, "no sales")

print("")
print("Profit list, an item the client has not sent yet")

row = Row()
updateRow(row, {
    recipeID = 4, name = "Copper Rod", outputItemID = 6217,
    priceable = true, craftableNow = 1, stock = 0,
    totalCost = 10, revenue = 20, profit = 10, margin = 0.5, age = 60,
})

check("falls back to plain text rather than an invented colour",
    row.name.color[1], "text")
check("and the tab listens for the item arriving",
    registeredEvents["GET_ITEM_INFO_RECEIVED"] ~= nil, true)

quality[6217] = BLUE
updateRow(row, {
    recipeID = 4, name = "Copper Rod", outputItemID = 6217,
    priceable = true, craftableNow = 1, stock = 0,
    totalCost = 10, revenue = 20, profit = 10, margin = 0.5, age = 60,
})

checkColor("so the redraw picks up the colour", row.name.color, BLUE)

print("")
print("Profit list, the skill-up star")

row = Row()
updateRow(row, {
    recipeID = 5, name = "Rough Grinding Stone", outputItemID = 2589,
    priceable = true, craftableNow = 3, stock = 0,
    totalCost = 100, revenue = 400, profit = 300, margin = 0.75, age = 60,
    skillUp = { tier = "optimal" }, recommended = true,
})

check("a craft that skills you up and pays wears one", row.mark.tier, "optimal")
check("and the name still carries its rarity", row.name.color[1], GREEN[1])

-- The same recipe, still orange, but no longer worth the materials. The star
-- follows the recommendation, never the difficulty on its own.
updateRow(row, {
    recipeID = 5, name = "Rough Grinding Stone", outputItemID = 2589,
    priceable = true, craftableNow = 3, stock = 0,
    totalCost = 400, revenue = 100, profit = -300, margin = -3, age = 60,
    skillUp = { tier = "optimal" }, recommended = false,
})

check("a skill up that loses gold does not", row.mark.tier, false)

-- Rows are recycled, so a marked row reused for an ordinary craft has to lose
-- the star rather than carry it to the next recipe down the list.
updateRow(row, {
    recipeID = 6, name = "Linen Bandage", outputItemID = 2589,
    priceable = false, reason = "output has no price data", craftableNow = 1,
})

check("and a recycled row does not keep one", row.mark.tier, false)

print("")
print(string.format("  %d passed, %d failed", passed, failed))
print("")

if failed > 0 then error("test_rarity.lua: " .. failed .. " failure(s)", 0) end
