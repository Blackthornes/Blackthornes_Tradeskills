-- The Disenchanting tab's bags list, drawn without a game client.
--
-- Asked 2026-09-29: "Can we setup a way to Disenchant items in your bag
-- under the Disenchant tab?" What this pins down:
--   * the tab still opens on the auction house deals, as before;
--   * the My Bags page lists the bag rows with their own columns;
--   * the top row is picked by itself and the Disenchant button is armed on
--     it, and the next row takes over once that item has gone;
--   * the button is not armed when the item cannot be disenchanted now, and
--     says why;
--   * this session's tally shows once something has been disenchanted.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
local printed = {}
ns.Print = function(text) printed[#printed + 1] = text end
ns.Debug, ns.Warn = function() end, function() end
ns.RegisterEvent = function() return true end

--------------------------------------------------------------------------------
-- A widget layer that only remembers what was written to it
--------------------------------------------------------------------------------

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

local function Shown(fields)
    fields = fields or {}
    fields.shown = true
    fields.SetShown = function(self, value) self.shown = value and true or false end
    fields.Show = function(self) self.shown = true end
    fields.Hide = function(self) self.shown = false end
    return Stub(fields)
end

local labels = {}
local function Label()
    local label
    label = Shown({
        text = "",
        SetText = function(self, value) self.text = tostring(value) end,
        GetText = function(self) return self.text end,
        SetTextColor = function(self, a) self.color = a end,
    })
    labels[#labels + 1] = label
    return label
end

--- Some label now showing text that matches, or nil.
local function Showing(pattern)
    for _, label in ipairs(labels) do
        if label.shown and label.text:find(pattern) then return label.text end
    end
end

CreateFrame = function() return Stub() end
C_Timer = { After = function() end }
GameTooltip = Stub()

ns.Theme = {
    SetRowName = function(label, text) label:SetText(text) end,
    SetItemNameColor = function() return false end,
    CreateLabel = function() return Label() end,
    CreatePanel = function() return Stub() end,
    CreateDivider = function() return Stub() end,
    CreateHeading = function() return Shown() end,
    CreateItemIcon = function() return Shown() end,
    SetItemIcon = function() end,
    AccentStripe = function() return Stub() end,
    Unpack = function(key) return key end,
    ProfitColor = function(value) return (value or 0) >= 0 and "profit" or "loss" end,
}

local checkboxes, dropdown, buttons, pages = {}, nil, {}, nil
local salvagerSwitch

ns.Widgets = {
    CreateTabStrip = function(_, tabs, onSelect)
        local strip = Shown({ tabs = tabs, onSelect = onSelect, Select = function(self, key) self.selected = key end })
        -- The Salvager switch in the detail panel is a strip too.
        if tabs[1].key == "plain" then salvagerSwitch = strip else pages = strip end
        return strip
    end,
    CreateSearchBox = function() return Stub() end,
    CreateDropdown = function(_, options, onSelect)
        dropdown = { options = options, select = onSelect }
        return Stub()
    end,
    CreateCheckbox = function(_, text, onToggle)
        local box = Shown({ onToggle = onToggle })
        checkboxes[text] = box
        return box
    end,
    CreateButton = function(_, text, onClick)
        local button = Shown({
            onClick = onClick,
            SetEnabledState = function(self, value) self.enabled = value end,
        })
        buttons[text] = button
        return button
    end,
    ShowItemTooltip = function() return true end,
}

local lists = {}
ns.Widgets.CreateScrollList = function(_, opts)
    local list = Stub({ SetData = function(self, data) self.data = data end, opts = opts })
    lists[#lists + 1] = list
    return list
end

ns.Util = {
    FormatMoney = function(copper) return tostring(copper or 0) end,
    FormatAge = function() return "1h" end,
    FormatAgeAgo = function() return "1h ago" end,
    GetItemLabel = function(itemID) return "item" .. tostring(itemID) end,
    GetItemQualityColor = function() end,
    Round = function(v) return v end,
    ColorItemName = function(_, name) return name end,
}

ns.Prices = { Count = function() return 1 end, changes = 0,
    GetAge = function() return 60 end, IsStale = function() return false end }
ns.Config = { Get = function() return 0 end }
ns.Scanner = { isAuctionHouseOpen = false }

--------------------------------------------------------------------------------
-- The data behind the lists
--------------------------------------------------------------------------------

local auctionRows = {
    { kind = "auction", itemID = 31, name = "Listed Chest", value = 800, buy = 500, net = 760,
      gain = 260, margin = 0.52, needs = 25, canDisenchant = true,
      breakdown = { facts = {}, outcomes = {} } },
}

local bagRows
local function ResetBags()
    bagRows = {
        { kind = "bag", itemID = 21, name = "Belt", count = 2, value = 500, sells = 100,
          sellsAt = "auction", gain = 400, beatsSale = true,
          breakdown = { facts = { itemLevel = 20, qualityName = "uncommon", skill = 1 }, outcomes = {} } },
        { kind = "bag", itemID = 22, name = "Boots", count = 1, value = 300, sells = 900,
          sellsAt = "vendor", gain = -600, beatsSale = false,
          breakdown = { facts = {}, outcomes = {} } },
    }
end
ResetBags()

ns.Disenchant = {
    GetBestEnchanter = function() return 100 end,
    GetAuctionRows = function() return auctionRows, 0, 0 end,
    GetBagRows = function(_, opts)
        if not (opts and opts.beatsOnly) then return bagRows end
        local out = {}
        for _, row in ipairs(bagRows) do if row.beatsSale then out[#out + 1] = row end end
        return out
    end,
    WasRequested = function() return false end,
}

local session = { 0, 0 }
ns.DisenchantLog = { GetSession = function() return session[1], session[2] end }

-- The secure half needs a game client: this records what the tab asked of it.
local armed, disarmed = {}, 0
local carrying = { [21] = true, [22] = true }
local knows = true
ns.Disenchanter = {
    Check = function(_, itemID)
        if not knows then return { ok = false, why = "This character does not know Disenchant." } end
        if carrying[itemID] then return { ok = true, bag = 0, slot = 1 } end
        return { ok = false, why = "That item is no longer in your bags." }
    end,
    Arm = function(self, anchor, itemID) self.anchor = anchor; armed[#armed + 1] = itemID; return true end,
    Disarm = function(self) self.anchor = nil; disarmed = disarmed + 1 end,
}

local tabs = {}
ns.UI = Stub({ RegisterTab = function(_, registered) tabs[registered.key] = registered end })

assert(loadfile(lfs_cwd .. "/UI/Columns.lua"))("Blackthornes_TS", ns)

assert(loadfile(lfs_cwd .. "/UI/Tab_Disenchanting.lua"))("Blackthornes_TS", ns)

local checks = 0
local function check(label, condition)
    checks = checks + 1
    if not condition then error(("FAILED: %s"):format(label), 2) end
    print(("  ok  %s"):format(label))
end

local tab = tabs.disenchanting
tab.build(Stub())
tab.refresh()

local list = lists[#lists]
local disenchant = buttons["Disenchant"]
local search = buttons["Search the auction house"]

print("\nthe auction house view is still the first thing shown")
check("the tab opens on the auction house deals", list.data == auctionRows)
check("its tick boxes show", checkboxes["Only deals over my minimums"].shown
    and checkboxes["Only ones I can disenchant"].shown)
check("the bags tick box does not", not checkboxes["Only where disenchanting pays more"].shown)
check("no Disenchant button on an auction house item", not disenchant.shown and #armed == 0)

list.opts.onClick(auctionRows[1], 1, "LeftButton")
check("picking a deal offers the search", search.shown and not disenchant.shown)

print("\nthe bags view")
check("there is a page for it", pages ~= nil and pages.tabs[2].key == "bag"
    and pages.tabs[2].text == "My Bags")

pages.onSelect("bag")
check("it lists what is in the bags", list.data == bagRows)
check("with its own tick box", checkboxes["Only where disenchanting pays more"].shown
    and not checkboxes["Only deals over my minimums"].shown)
check("everything that can be broken is listed by default", #list.data == 2)

check("the top row is picked by itself", armed[#armed] == 21)
check("the Disenchant button shows and is ready", disenchant.shown and disenchant.enabled == true)
check("the search button steps aside", not search.shown)
check("its tooltip says what a click does", disenchant.tooltipText == "Disenchant one Belt from your bags.")

-- Row cells, right to left: DIFFERENCE, DISENCHANT, SELLS, HAVE.
local row = Stub()
list.opts.createRow(row)
list.opts.updateRow(row, bagRows[1])
check("the row shows how much more disenchanting pays", row.cells[1].text == "400"
    and row.cells[1].color == "profit")
check("its disenchant value is green", row.cells[2].text == "500" and row.cells[2].color == "profit")
check("what it sells for", row.cells[3].text == "100")
check("and how many are carried", row.cells[4].text == "2")
check("the auction columns are hidden", row.cells[5].shown == false and row.cells[6].shown == false)

list.opts.updateRow(row, bagRows[2])
check("an item that sells better shows the loss in red", row.cells[1].text == "-600"
    and row.cells[1].color == "loss")
check("and what a vendor pays when that is more", row.cells[3].text == "900")

print("\npicking and disenchanting")
list.opts.onClick(bagRows[2], 2, "LeftButton")
check("picking another row moves the button onto it", armed[#armed] == 22)

list.opts.onClick(bagRows[2], 2, "RightButton")
check("right-click in the bags does not search the auction house", #printed == 0)

-- The boots are disenchanted: they leave the bags and the list.
carrying[22] = nil
table.remove(bagRows, 2)
session = { 1, 250 }
tab.refresh()
check("the next item takes over the button", armed[#armed] == 21)
check("the count line shows this session's tally",
    Showing("1 disenchanted this session, worth 250") ~= nil)
check("and so does the detail panel", Showing("^1, worth 250$") ~= nil)

print("\nwhen it cannot be done")
knows = false
tab.refresh()
check("a character without Disenchant is not armed", disenchant.enabled == false)
check("and it says why", disenchant.tooltipText == "This character does not know Disenchant.")
check("the secure button is taken away", ns.Disenchanter.anchor == nil and disarmed > 0)
knows = true

print("\nat an Arcane Salvager")
-- The owner said build it, 2026-11-24: a switch above Breaks Into and a
-- purple line, only with Keep Salvager Results Apart ticked.
check("with the box off there is no switch", salvagerSwitch and not salvagerSwitch.shown)
check("and no Stop button", not buttons["Stop"].shown)

local salvagerUp, stopped = true, false
local Log, Dis = ns.DisenchantLog, ns.Disenchant
Log.SalvagerApart = function() return true end
Log.SalvagerUp = function() return salvagerUp, false end
Log.StopSalvager = function() stopped = true; salvagerUp = false end
Log.GetItem = function() return { casts = 40 } end
Log.GetBand = function() return { casts = 60 } end
Dis.SALVAGER_LEARN_AFTER = 5
Dis.GetOutcomes = function() return {}, { key = "2:weapon:25" } end
Dis.GetValue = function() return 300 end
Dis.MaterialName = function() return "Strange Dust" end
Dis.GetMaterialPrice = function() return 10 end
local salvaged = { outcomes = {}, facts = { casts = 2, need = 3,
    seen = { casts = 2, got = { [10940] = { times = 2, min = 1, max = 2 } } } } }
local salvagerValue
Dis.GetSalvagerValue = function() return salvagerValue, nil, salvaged end

tab.refresh()
check("ticked, the switch shows", salvagerSwitch.shown and salvagerSwitch.tabs[3].text == "Side by Side")
check("it opens on Side by Side", salvagerSwitch.selected == "side")
check("the purple line has Stop when only the cast turned it on", buttons["Stop"].shown)
check("too few: each Salvager cell says how many so far", Showing("^2 so far$") ~= nil)
check("and the note says how many more", Showing("Disenchant 3 more at a Salvager to see its chances.") ~= nil)

salvagerValue = 600   -- the Belt's plain value is 500
salvaged = { outcomes = { { itemID = 10940, chance = 1, average = 2, min = 2, max = 2 } },
    facts = { casts = 5, byItem = true } }
tab.refresh()
check("enough: the compare line", Showing("^The Salvager gives$") ~= nil and Showing("^100 more %(20%%%)$") ~= nil)
salvagerValue = 400
tab.refresh()
check("and says so when it gave less", Showing("^100 less %(20%%%)$") ~= nil)
check("with both counts in the note",
    Showing("From your own 40 plain and 5 Salvager disenchants of this item.") ~= nil)

salvagerSwitch.onSelect("salvager")
check("Salvager shows its own chances",
    Showing("Chances come from your own 5 Salvager disenchants of this item.") ~= nil)

buttons["Stop"].onClick()
check("Stop ends Salvager mode", stopped)

Log.SalvagerApart = function() return false end
tab.refresh()
check("unticked, the switch goes again", not salvagerSwitch.shown)

print("\nall done")
bagRows = {}
tab.refresh()
check("an empty bag list is not an error", list.data and #list.data == 0)
check("it cheers the finish", Showing("Done. You disenchanted 1 item this session, worth about 250") ~= nil)
check("no button without an item", not disenchant.shown)

print("\nback to the auction house")
pages.onSelect("auction")
check("the deals come back", list.data == auctionRows)
check("and the Disenchant button goes", not disenchant.shown)

print(("\n%d check(s) passed\n"):format(checks))

print("\nan auction deal on the Salvager view")
-- A player's report, 2026-11-25: after Move to Salvager the plain record
-- was empty, so the plain value fell back to the rough chances. The
-- Salvager view showed its own Disenchant value but kept the plain cut and
-- profit under it, so a deal showed a big cut and a loss.
Log.SalvagerApart = function() return true end
salvagerUp = true
salvagerValue = 1000      -- the Listed Chest's plain value is 800, net 760
salvaged = { outcomes = { { itemID = 10940, chance = 1, average = 2, min = 2, max = 2 } },
    facts = { casts = 5, byItem = true } }
ns.Config.Get = function(_, key) if key == "auctionCut" then return 0.05 end return 0 end
list.opts.onClick(auctionRows[1], 1, "LeftButton")
salvagerSwitch.onSelect("salvager")
check("the Salvager value shows", Showing("^1000$") ~= nil)
check("the cut comes off the Salvager value", Showing("^950$") ~= nil and Showing("^760$") == nil)
check("and the profit follows it", Showing("^450  %(") ~= nil and Showing("^260  %(") == nil)

ns.Config.Get = function() return 0 end
tab.refresh()
check("with no cut nothing comes off", Showing("^500  %(") ~= nil)

salvagerSwitch.onSelect("plain")
check("the plain view keeps the plain profit", Showing("^260  %(") ~= nil)
ns.Config.Get = function() return 0 end
