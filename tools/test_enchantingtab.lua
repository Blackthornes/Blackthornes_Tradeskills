-- The Enchanting tab and the Profit tab's DISENCHANT column, drawn without a
-- game client.
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

local checkboxes = {}
local lastDropdown

ns.Widgets = {
    CreateSearchBox = function() return Stub() end,
    CreateDropdown = function(_, _, onSelect) lastDropdown = onSelect; return Stub() end,
    CreateCheckbox = function(_, text) local box = Stub({ shown = true, SetShown = function(self, v) self.shown = v end }); checkboxes[text] = box; return box end,
    ShowItemTooltip = function() return true end,
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
-- The Enchanting tab
--------------------------------------------------------------------------------

local craftRows = {
    { kind = "craft", recipeID = 1, itemID = 11, name = "Chest", value = 800, sells = 700,
      sellsAt = "auction", cost = 100, gain = 700, beatsSale = true, craftableNow = 2,
      breakdown = { facts = { itemLevel = 22, qualityName = "uncommon", skill = 25 },
                    outcomes = { { itemID = 10940, name = "Strange Dust", chance = 0.75,
                                   min = 4, max = 6, price = 100 } } } },
    { kind = "craft", recipeID = 2, itemID = 12, name = "Sword", value = 1400, sells = 5000,
      sellsAt = "auction", cost = 100, gain = 1300, beatsSale = false, craftableNow = 0,
      breakdown = { facts = {}, outcomes = {} } },
}

ns.Disenchant = {
    GetCraftRows = function() return craftRows end,
    GetBagRows = function()
        return { { kind = "bag", itemID = 21, name = "Belt", count = 1, value = 500, sells = 100,
                   sellsAt = "auction", gain = 400, beatsSale = true,
                   breakdown = { facts = { itemLevel = 20, qualityName = "uncommon", skill = 1 }, outcomes = {} } } }
    end,
    GetMaterialRows = function()
        return { { kind = "material", itemID = 10940, name = "Strange Dust", price = 100, have = 7, age = 60 } }
    end,
}
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

local tabs = {}
ns.UI = Stub({ RegisterTab = function(_, registered) tabs[registered.key] = registered end })

assert(loadfile(lfs_cwd .. "/UI/Tab_Enchanting.lua"))("Blackthornes_TS", ns)

local enchanting = tabs.enchanting
check("the tab registers as Enchanting", enchanting and enchanting.text == "Enchanting")

enchanting.build(Stub())
enchanting.refresh()

local list = lists[#lists]
check("the craft view lists the crafts", list.data == craftRows)

local row = Stub()
list.opts.createRow(row)
list.opts.updateRow(row, craftRows[1])

-- Columns run right to left: PROFIT, DISENCHANT, SELLS, COST, MAKE.
check("the craft's name is shown", row.name.text == "Chest")
check("its disenchant value is shown", row.cells[2].text == "800")
check("and green, because it beats selling", row.cells[2].color[1] == "profit")
check("the sale price sits beside it", row.cells[3].text == "700")
check("profit over materials is shown", row.cells[1].text == "700")

list.opts.updateRow(row, craftRows[2])
check("a craft that sells for more is not green", row.cells[2].color[1] ~= "profit")
check("and shows it cannot be made now", row.cells[5].text == "0" and row.cells[5].color[1] == "loss")

-- Picking a row fills the detail panel without an error.
list.opts.onClick(craftRows[1], 1, "LeftButton")
check("picking a row fills the detail panel", true)
check("a craft you carry gets the Disenchant button", armed[#armed] == 11)

local before = #armed
list.opts.onClick(craftRows[2], 2, "LeftButton")
check("a craft you do not carry does not", #armed == before)

-- The bags list picks its top row by itself, ready to disenchant.
local viewPicker = lastDropdown
before = #armed
viewPicker("bag")
check("the bags list arms Disenchant on its top row unasked", armed[#armed] == 21 and #armed > before)

carrying[21] = nil
before = #armed
enchanting.refresh()
check("an item that has left the bags is not armed", #armed == before)
viewPicker("craft")

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

tabs.profit.build(Stub())
tabs.profit.refresh()

local profitList = lists[#lists]
local profitRow = Stub()
profitList.opts.createRow(profitRow)

profitList.opts.updateRow(profitRow, analyses[1])
check("the Profit tab shows the disenchant value", profitRow.cells.disenchant.text == "800")
check("green when disenchanting beats selling", profitRow.cells.disenchant.color[1] == "profit")

profitList.opts.updateRow(profitRow, analyses[2])
check("and nothing for a craft that cannot be disenchanted", profitRow.cells.disenchant.text == "")

check("the column shows while something can be disenchanted",
    profitRow.cells.disenchant.hidden == false)

-- With nothing disenchantable in the list, the column steps aside.
showing = { analyses[2] }
tabs.profit.refresh()
profitList.opts.updateRow(profitRow, analyses[2])
check("an alchemist's list carries no DISENCHANT column", profitRow.cells.disenchant.hidden == true)

print(("\n%d check(s) passed\n"):format(checks))
