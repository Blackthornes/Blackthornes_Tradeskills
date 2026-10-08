-- The Profit tab's DISENCHANT column and Disenchant button, which took over
-- the Enchanting tab's crafts list (2026-10-07), drawn without a game client.
--
-- The widget layer is the one tools/test_rarity.lua uses: it remembers what
-- was written to each label, so a cell can be asked what it says and which
-- palette colour it was painted with.

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
        Hide = function(self) self.hidden = true end,
        Show = function(self) self.hidden = false end,
    })
end

CreateFrame = function() return Stub() end
C_Timer = { After = function() end, NewTicker = function() return Stub() end }

ns.Theme = {
    SetRowName = function(label, text) label:SetText(text) end,
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
    SetMoneyText = function(label, copper, opts) label:SetText(ns.Util.FormatMoney(copper, opts)) end,
    CreateBar = function() return Stub() end,
    CreateHeading = function() return Stub({ rule = Stub() }) end,
    StyleHeading = function(label) label.rule = Stub(); return label end,
}

local checkboxes = {}
local lastDropdown, lastOptions

ns.Widgets = {
    CreateSearchBox = function() return Stub() end,
    CreateDropdown = function(_, options, onSelect)
        lastDropdown = onSelect
        lastOptions = options
        return Stub()
    end,
    CreateCheckbox = function(_, text) local box = Stub({ shown = true, SetShown = function(self, v) self.shown = v end }); checkboxes[text] = box; return box end,
    ShowItemTooltip = function() return true end,
    CreateNumberBox = function() return Stub({ editBox = Stub() }) end,
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
    FormatAgeAgo = function() return "1h ago" end,
    Round = function(v) return v end,
    HasFunction = function() return false end,
}

ns.Profit = { GetRanked = function() return {} end, Analyse = function() return nil end }
ns.Recipes = { Count = function() return 1 end, GetAll = function() return {} end }
ns.Prices = { Count = function() return 1 end }
ns.Auctions = { SetLimit = function() end }
ns.Config = { Get = function() return 0 end }


local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

--------------------------------------------------------------------------------
-- What the Profit tab took over from the Enchanting tab (2026-10-07)
--------------------------------------------------------------------------------

ns.Disenchant = {}
ns.Queue = { Add = function() end }

-- The Disenchant button's secure half, which needs a game client: this only
-- records what the tab asked of it.
local armed = {}
local carrying = { [11] = true, [21] = true }
ns.Disenchanter = {
    FindSlot = function(_, itemID) if carrying[itemID] then return 0, 1 end end,
    Check = function(_, itemID)
        if carrying[itemID] then return { ok = true, bag = 0, slot = 1 } end
        return { ok = false, why = "That item is no longer in your bags." }
    end,
    Arm = function(_, anchor, itemID) armed[#armed + 1] = itemID; return true end,
    Disarm = function() end,
}

local lists = {}
ns.Widgets.CreateScrollList = function(_, opts)
    local list = Stub({ SetData = function(self, data) self.data = data end })
    list.opts = opts
    lists[#lists + 1] = list
    return list
end

-- Buttons remember their words and whether they show.
local buttons = {}
ns.Widgets.CreateButton = function(_, text)
    local button = Stub({ text = text, shown = true,
        SetShown = function(self, value) self.shown = value and true or false end,
        Hide = function(self) self.shown = false end,
        Show = function(self) self.shown = true end })
    buttons[#buttons + 1] = button
    return button
end

local function Button(text)
    for index = #buttons, 1, -1 do
        if buttons[index].text == text then return buttons[index] end
    end
end

local tabs = {}
ns.UI = Stub({ RegisterTab = function(_, registered) tabs[registered.key] = registered end })

--------------------------------------------------------------------------------
-- The Profit tab's column
--------------------------------------------------------------------------------

local analyses = {
    { recipeID = 1, name = "Chest", outputItemID = 11, priceable = true, totalCost = 100,
      revenue = 700, unitRevenue = 700, profit = 565, margin = 0.8, disenchantable = true,
      disenchantValue = 800, disenchantBeatsSale = true, craftableNow = 1 },
    { recipeID = 3, name = "Potion", outputItemID = 13, priceable = true, totalCost = 100,
      revenue = 700, unitRevenue = 700, profit = 565, margin = 0.8, craftableNow = 1 },
}
local showing = analyses

ns.Profit.GetRanked = function() return showing end

assert(loadfile(lfs_cwd .. "/UI/Tab_Profit.lua"))("Blackthornes_TS", ns)

ns.Profit.MaxCrafts = function() return 1 end
ns.Profit.Analyse = function(_, recipeID)
    for _, analysis in ipairs(analyses) do
        if analysis.recipeID == recipeID then return analysis end
    end
end

tabs.profit.build(Stub())
tabs.profit.refresh()

local disenchantButton = Button("Disenchant")
check("the Profit tab's pane has a Disenchant button", disenchantButton ~= nil)
check("hidden until a craft is picked", disenchantButton.shown == false)

local picker = lists[#lists]
picker.opts.onClick(analyses[1], 1, "LeftButton")
check("a craft you carry that can be disenchanted shows it", disenchantButton.shown == true)
check("and sets it on that item", armed[#armed] == 11)

local before = #armed
picker.opts.onClick(analyses[2], 2, "LeftButton")
check("a craft that cannot be disenchanted hides it", disenchantButton.shown == false and #armed == before)

carrying[11] = nil
picker.opts.onClick(analyses[1], 1, "LeftButton")
check("so does one you do not carry", disenchantButton.shown == false and #armed == before)
carrying[11] = true

local profitList = lists[#lists]
local profitRow = Stub()
profitList.opts.createRow(profitRow)

profitList.opts.updateRow(profitRow, analyses[1])
check("the Profit tab shows the disenchant value", profitRow.cells.disenchant.text == "800")
check("green when disenchanting beats selling", profitRow.cells.disenchant.color[1] == "profit")

profitList.opts.updateRow(profitRow, analyses[2])
check("and nothing for a craft that cannot be disenchanted", profitRow.cells.disenchant.text == "")

-- Ezmode (Discord, 2026-10-08): AGE said "DE" and "vendor" on these rows.
profitList.opts.updateRow(profitRow, { recipeID = 4, name = "Cuffs", outputItemID = 14,
    priceable = true, totalCost = 90, revenue = 323, unitRevenue = 323, profit = 217,
    margin = 0.67, via = "disenchant", priceBasis = "disenchant", age = 3600, craftableNow = 0 })
check("a disenchant row's AGE is its material's price age", profitRow.cells.age.text == "1h")

profitList.opts.updateRow(profitRow, { recipeID = 5, name = "Oil", outputItemID = 15,
    priceable = true, totalCost = 399, revenue = 500, unitRevenue = 500, profit = 101,
    margin = 0.2, via = "vendor", priceBasis = "vendor", age = 3600, craftableNow = 3 })
check("a vendor row's AGE is a dash, not the word vendor", profitRow.cells.age.text == "--")

check("the column shows while something can be disenchanted",
    profitRow.cells.disenchant.hidden == false)

-- With nothing disenchantable in the list, the column steps aside.
showing = { analyses[2] }
tabs.profit.refresh()
profitList.opts.updateRow(profitRow, analyses[2])
check("an alchemist's list carries no DISENCHANT column", profitRow.cells.disenchant.hidden == true)

print(("\n%d check(s) passed\n"):format(checks))
