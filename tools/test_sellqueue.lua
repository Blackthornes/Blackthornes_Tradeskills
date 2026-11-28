-- Queue From Sell List on the Sell tab at the auction house.
--
-- The owner said build it (2026-11-23, from a mockup): a row Craft First
-- keeps back gets a gold Queue button, and Queue All shows by List Next
-- while some row can be queued. Counts come from Butler:CraftFor, the queue
-- is asked through Butler:QueueCraft, and a recipe two rows share is asked
-- once, for the most either makes. Off unless ticked; greyed while Craft
-- First is off.

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

local function Lines()
    return {
        { itemID = 10, count = 6, unitPrice = 4215, craftHeld = true, held = "Worth more as Ornate Spyglass: 1g 20s each" },
        { itemID = 11, count = 8, unitPrice = 3000, craftHeld = true, held = "Worth more as Azure Silk Hood: 68s 40c each" },
        { itemID = 12, count = 4, unitPrice = 1000, craftHeld = true, held = "Worth more as Ornate Spyglass" },
        { itemID = 30, count = 20, unitPrice = 980 },
        { itemID = 31, count = 12, unitPrice = 500, held = "Your pet eats this" },
    }
end

print("\noff unless ticked")
check("unticked, nothing can be queued", #PostPanel:QueueableRows(Lines()) == 0)
settings.sellQueueFromList = true
check("ticked without Craft First, still nothing", #PostPanel:QueueableRows(Lines()) == 0)
settings.sellHoldsCraftFirst = true
check("with both ticked, the three Craft First rows can be queued", #PostPanel:QueueableRows(Lines()) == 3)
check("a plain row has no craft to queue", PostPanel:CraftToQueue(Lines()[4]) == nil)
check("another addon's keep has no craft to queue", PostPanel:CraftToQueue(Lines()[5]) == nil)

print("\nQueue All by List Next")
PostPanel.view = "sell"
PostPanel.listAll = Button("List Next")
PostPanel.footNote = Stub()
PostPanel.queueAll = Button("Queue All (0)", function() PostPanel:QueueAll() end)
PostPanel.queueAll.shown = false
local refreshed = 0
local realRefresh = PostPanel.Refresh
PostPanel.Refresh = function(self)
    refreshed = refreshed + 1
    self:UpdateQueueAll(self.shownLines)
end
PostPanel.shownLines = Lines()
PostPanel:UpdateQueueAll(PostPanel.shownLines)
check("it shows while rows can be queued", PostPanel.queueAll.shown)
check("and counts them", PostPanel.queueAll.text == "Queue All (3)")

PostPanel.queueAll:Click()
check("a recipe two rows share is asked once", #asked == 2)
local spyglass, hood
for _, ask in ipairs(asked) do
    if ask.recipeID == 500 then spyglass = ask.crafts elseif ask.recipeID == 501 then hood = ask.crafts end
end
check("for the most either makes", spyglass == 3)
check("the other recipe for its own count", hood == 4)
check("chat says how many rows went in", printed[#printed] == "Added 3 crafts to your queue.")
check("the drawer is drawn again", refreshed >= 1)
check("then Queue All hides, nothing is left to queue", PostPanel.queueAll.shown == false)

print("\none row's Queue button")
queue, asked, printed = {}, {}, {}
local row = Stub({ name = Stub(), detail = Stub({ SetText = function() end, GetWidth = function() return 200 end }),
    icon = Stub(), quantity = Shower(), post = Button("List"), priceField = false })
row.quantity.SetLimits = function() end
row.quantity.SetValue = function() end
row.quantity.editBox = Stub()
row.queue = Button("Queue", function() PostPanel:QueueRow(row.data) end)
row.queue.shown = false

-- UpdateRow is the drawer's own row painter; reach it through the list's
-- row update the way the drawer does.
local UpdateRow = PostPanel._UpdateRow
check("the row painter is reachable", type(UpdateRow) == "function")
ns.Posting = { FarUnderUsual = function() return false end, ClickChecksFirst = function() return false end }

local line = Lines()[1]
line.postQuantity, line.maxQuantity = 6, 6
row.data = line
UpdateRow(row, line)
check("a Craft First row shows Queue", row.queue.shown and row.queue.text == "Queue")
check("in the amount box's place", row.quantity.shown == false)
check("the button can be clicked", row.queue.enabled)
row.queue:Click()
check("it asks for what the bags make", #asked == 1 and asked[1].recipeID == 500 and asked[1].crafts == 3)
check("chat names the craft", printed[#printed] == "Added 3 Ornate Spyglass to your queue.")
UpdateRow(row, line)
check("then it says Queued", row.queue.text:find("Queued", 1, true) ~= nil)
check("and takes no more clicks", row.queue.enabled == false)
row.queue:Click()
check("a second click asks nothing more", #asked == 1)

local plain = Lines()[4]
plain.postQuantity, plain.maxQuantity = 20, 20
UpdateRow(row, plain)
check("a reused row with a plain item hides Queue", row.queue.shown == false)
check("and brings the amount box back", row.quantity.shown == true)

settings.sellQueueFromList = false
UpdateRow(row, line)
check("unticked, the Craft First row has no Queue", row.queue.shown == false)
settings.sellQueueFromList = true

print("\nthe Queue button's hover")
local tip = { lines = {} }
function tip:SetText(text) self.lines[#self.lines + 1] = text end
function tip:AddLine(text) self.lines[#self.lines + 1] = text end
function tip:AddDoubleLine(a, b) self.lines[#self.lines + 1] = a .. " " .. b end
local hoodLine = Lines()[2]
hoodLine.postQuantity, hoodLine.maxQuantity = 8, 8
UpdateRow(row, hoodLine)
check("the hover draws", PostPanel.QueueTooltip(row.queue, tip) == true)
check("what it queues", tip.lines[1] == "Queues 4 Azure Silk Hood.")
check("what it uses", tip.lines[2] == "Uses the 8 Bolt of Silk Cloth in your bags.")
check("what each is worth crafted", tip.lines[3] == "Each one sells for: 6840c")
check("what one sells for as it is", tip.lines[4] == "A Bolt of Silk Cloth sells for: 3000c")
check("and where the rest goes", tip.lines[5] == "Anything else it needs goes on your shopping list.")

print("\na queue that says no")
queue, asked, printed = {}, {}, {}
ns.Butler.QueueCraft = function() return false, "the queue would not take it" end
PostPanel:QueueRow(Lines()[1])
check("chat says why", printed[#printed] == "the queue would not take it")
ns.Butler.QueueCraft = function() error("boom") end
check("a queue that raises changes nothing", PostPanel:QueueRow(Lines()[1]) == false)
PostPanel.Refresh = realRefresh

print("\nsaved setting and Settings row")
local config = assert(io.open(lfs_cwd .. "/Core/Config.lua")):read("*a")
check("the setting is off to start", config:find("sellQueueFromList = false", 1, true) ~= nil)
local page = assert(io.open(lfs_cwd .. "/UI/Tab_Settings.lua")):read("*a")
local craftAt = page:find('L["Craft First:"]', 1, true)
local queueAt = page:find('L["Queue From Sell List:"]', 1, true)
check("the row sits right under Craft First", craftAt and queueAt and queueAt > craftAt)
check("it greys while Craft First is off", page:find("GreyQueueFromSell(widgets, checked)", 1, true) ~= nil)

print(("\n%d check(s) passed\n"):format(checks))
