-- Shift-click List on the Sell list, the row's side (the owner said build
-- it, 2026-11-28; the listing side is tools/test_sellnowclick.lua).
--
-- Shift held over List on a row Tradeskills holds back: the button reads
-- List Anyway, the box shows the whole stack and the tooltip says so. The
-- click asks for that one listing anyway. A plain click, List Next and a
-- Butler Says Wait row are as before.
local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.Debug, ns.Warn = function() end, function() end
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.RegisterEvent = function() return true end

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

-- A button that remembers its label, whether it shows and is enabled, and
-- runs its click.
local function Button(text, onClick)
    return Stub({
        text = text, shown = true, enabled = true, onClick = onClick,
        label = Stub(),
        SetText = function(self, value) self.text = value end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetShown = function(self, on) self.shown = on and true or false end,
        IsShown = function(self) return self.shown end,
        SetEnabledState = function(self, on) self.enabled = on and true or false end,
        Click = function(self) self.onClick() end,
    })
end

local function Shower()
    return Stub({
        shown = true,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetShown = function(self, on) self.shown = on and true or false end,
        IsShown = function(self) return self.shown end,
    })
end

CreateFrame = function() return Stub() end
C_Timer = { After = function() end, NewTicker = function() return Stub() end }

ns.Theme = {
    CreateLabel = function() return Stub({ SetText = function() end }) end,
    Unpack = function(key) return key end,
    CreateItemIcon = function() return Stub() end,
    SetItemIcon = function() end,
    TextWidth = function() return 60 end,
    Fill = function() end, Border = function() end,
}
ns.Widgets = {
    CreateButton = function(_, text, onClick) return Button(text, onClick) end,
    CreateNumberBox = function() return Shower() end,
    CreateCheckbox = function() return Stub() end,
    CreateDropdown = function() return Stub() end,
}

local names = { [10] = "Whirling Bronze Gizmo", [11] = "Bolt of Silk Cloth", [12] = "Spare Gear",
    [20] = "Ornate Spyglass", [21] = "Azure Silk Hood" }
ns.Util = {
    GetItemQualityColor = function() end,
    FormatMoney = function(c) return tostring(c) .. "c" end,
    GetItemName = function(id, fallback) return names[id] or fallback end,
}
ns.COLORS = { profit = "ff4fd18b", warn = "ffffaa00", accent = "ffffd100", loss = "ffff0000" }

local settings = {}
ns.Config = { Get = function(_, key) return settings[key] end, Set = function(_, k, v) settings[k] = v end }
ns.SisterKeeps = { CraftFirst = function() return settings.sellHoldsCraftFirst == true end }

-- Two rows feed the same recipe (the Spyglass): one makes 3, the other 2.
local crafts = {
    [10] = { recipeID = 500, name = "Ornate Spyglass", itemID = 20, crafts = 3, perItem = 12000 },
    [12] = { recipeID = 500, name = "Ornate Spyglass", itemID = 20, crafts = 2, perItem = 9000 },
    [11] = { recipeID = 501, name = "Azure Silk Hood", itemID = 21, crafts = 4, perItem = 6840 },
}
local asked, queue = {}, {}
ns.Butler = {
    CraftFor = function(_, itemID) return crafts[itemID] end,
    QueueCraft = function(_, recipeID, count)
        asked[#asked + 1] = { recipeID = recipeID, crafts = count }
        queue[recipeID] = math.max(queue[recipeID] or 0, count)
        return true
    end,
}
ns.Queue = { Find = function(_, recipeID)
    if queue[recipeID] then return 1, { recipeID = recipeID, quantity = queue[recipeID] } end
end }

local shift = false
IsShiftKeyDown = function() return shift end
local events = {}
ns.RegisterEvent = function(_, event, fn) events[event] = fn; return true end
ns.UnregisterEvent = function(_, event) events[event] = nil; return true end

local PostPanel
local realNew = ns.NewModule
ns.NewModule = function(name) local m = realNew(name); PostPanel = m; return m end
assert(loadfile(lfs_cwd .. "/UI/PostPanel.lua"))("Blackthornes_TS", ns)

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local requests = {}
ns.Posting = {
    FarUnderUsual = function() return false end,
    ClickChecksFirst = function() return false end,
    IsUnderFloor = function() return false end,
    WholeStack = function(_, itemID) return itemID == 10 and 25 or 5 end,
    Request = function(_, itemID, quantity, price, opts)
        requests[#requests + 1] = { itemID = itemID, quantity = quantity, price = price,
            anyway = type(opts) == "table" and opts.anyway == true }
    end,
}

-- A row the way the drawer makes it, with a box that keeps its number.
local function Row()
    local row = Stub({ name = Stub(), detail = Stub({ SetText = function() end, GetWidth = function() return 200 end }),
        icon = Stub(), quantity = Shower(), priceField = false })
    row.quantity.SetLimits = function(self, low, high) self.high = high end
    row.quantity.SetValue = function(self, value) self.value = value end
    row.quantity.editBox = Stub()
    local over = true
    row.post = Button("List", function() PostPanel:ListRow(row.data, IsShiftKeyDown()) end)
    row.post.IsMouseOver = function() return over end
    row.setOver = function(on) over = on end
    return row
end

local UpdateRow = PostPanel._UpdateRow
local tip = { lines = {} }
function tip:AddLine(text) self.lines[#self.lines + 1] = text end
function tip:Joined() return table.concat(self.lines, "\n") end

-- Thorium Bar: 25 in the bags, 5 kept for the queue, 20 offered.
local function Kept() return { itemID = 10, count = 20, unitPrice = 3810, postQuantity = 20, maxQuantity = 20, queueKept = true, label = "Thorium Bar" } end
local function Plain() return { itemID = 11, count = 5, unitPrice = 7100, postQuantity = 5, maxQuantity = 5, label = "Elixir" } end
local function Waiting() return { itemID = 12, count = 3, unitPrice = 500, postQuantity = 3, maxQuantity = 3, label = "Belt",
    butlerWait = { short = "Better price soon" } } end

print("\nwhat counts as held back")
check("a queue keep", PostPanel.HoldsBack(Kept()))
check("another addon's keep", PostPanel.HoldsBack({ itemID = 1, unitPrice = 1, held = "Your pet eats this" }))
check("under what it cost", PostPanel.HoldsBack({ itemID = 1, unitPrice = 1, atALoss = true }))
check("some kept back", PostPanel.HoldsBack({ itemID = 1, unitPrice = 1, kept = 2 }))
check("Keep Listed", PostPanel.HoldsBack({ itemID = 1, unitPrice = 1, listCapped = true }))
check("not a plain row", not PostPanel.HoldsBack(Plain()))
check("not Butler Says Wait", not PostPanel.HoldsBack(Waiting()))
check("not a row with no price", not PostPanel.HoldsBack({ itemID = 1, held = "x" }))

print("\nthe tooltip without Shift")
local row = Row()
row.data = Kept()
UpdateRow(row, row.data)
check("a held row says Shift-click", row.post.tooltipText:find("Shift-click to list it anyway.", 1, true) ~= nil)
check("the button reads List", row.post.text == "List")
local plainRow = Row()
plainRow.data = Plain()
UpdateRow(plainRow, plainRow.data)
check("a plain row does not", plainRow.post.tooltipText:find("Shift-click", 1, true) == nil)
check("and the hover is the usual one", PostPanel:ShiftTooltip(plainRow, tip) == false)
PostPanel:ShowShift(plainRow, false)

print("\nShift held over List")
shift = true
tip.lines = {}
check("the hover is the Shift one", PostPanel:ShiftTooltip(row, tip) == true)
check("the button reads List Anyway", row.post.text == "List Anyway")
check("the box shows the whole stack", row.quantity.value == 25 and row.quantity.high == 25)
check("the tooltip says how many", tip:Joined():find("List 25 of 25 at 3810c each.", 1, true) ~= nil)
check("and only this one", tip:Joined():find("Lists it even though Tradeskills would hold it back. Only this one.", 1, true) ~= nil)
check("Shift is watched while the mouse is there", events.MODIFIER_STATE_CHANGED ~= nil)

-- The list draws again every second with new line tables.
row.data = Kept()
UpdateRow(row, row.data)
check("a redraw keeps List Anyway", row.post.text == "List Anyway")
check("and the whole stack", row.quantity.value == 25)

row.post:Click()
local sent = requests[#requests]
check("the click lists it anyway", sent.anyway == true)
check("all 25", sent.quantity == 25)
check("at the row's price", sent.price == 3810)

print("\nShift let go")
shift = false
events.MODIFIER_STATE_CHANGED()
check("the button reads List again", row.post.text == "List")
check("the box is back to 20", row.quantity.value == 20)
row.post:Click()
sent = requests[#requests]
check("a plain click is a plain listing", sent.anyway == false and sent.quantity == 20)

print("\nthe mouse leaves")
shift = true
events.MODIFIER_STATE_CHANGED()
check("Shift again turns it on", row.post.text == "List Anyway")
row.setOver(false)
PostPanel:ShowShift(row, false)
check("leaving turns it off", row.post.text == "List" and row.quantity.value == 20)
check("and Shift is no longer watched", events.MODIFIER_STATE_CHANGED == nil)

print("\nrows Shift leaves alone")
local waitRow = Row()
waitRow.data = Waiting()
UpdateRow(waitRow, waitRow.data)
PostPanel:ShiftTooltip(waitRow, tip)
check("Butler Says Wait still reads Sell Anyway", waitRow.post.text == "Sell Anyway")
waitRow.post:Click()
sent = requests[#requests]
check("and its Shift-click is its usual Sell Anyway", sent.anyway == false and sent.quantity == 3)
PostPanel:ShowShift(waitRow, false)

plainRow.setOver(true)
PostPanel:ShiftTooltip(plainRow, tip)
check("a plain row keeps List", plainRow.post.text == "List")
plainRow.post:Click()
sent = requests[#requests]
check("its Shift-click passes the guards, at its own amount", sent.anyway == true and sent.quantity == 5)
PostPanel:ShowShift(plainRow, false)
shift = false

print("\nthe words")
for _, lang in ipairs({ "deDE", "frFR", "esES", "ruRU", "zhCN" }) do
    local text = assert(io.open(lfs_cwd .. "/Locale/" .. lang .. ".lua")):read("*a")
    for _, key in ipairs({ "Shift-click List to list it anyway.", "Shift-click to list it anyway.",
            "Lists it even though Tradeskills would hold it back. Only this one." }) do
        check(lang .. " has " .. key, text:find('L["' .. key .. '"]', 1, true) ~= nil)
    end
end
local de = assert(io.open(lfs_cwd .. "/Locale/deDE.lua")):read("*a")
check("German in du", de:find('"Umschalt-Klick auf Einstellen stellt es trotzdem ein."', 1, true) ~= nil)

print(("\n%d checks passed"):format(checks))
