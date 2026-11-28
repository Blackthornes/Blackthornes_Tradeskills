-- Tooltips and Sales names for random suffix items (a player's report,
-- 2026-11-23): hovering "Captain's Breastplate of Magic" on the drawer's
-- Sell list, a listing on Auctions, or a suffix row on the Prices tab showed
-- the plain "Captain's Breastplate" card. Sales named "Royal Cape of the
-- Sorcerer" as plain "Royal Cape", on its rows and its hover.
--
-- What must hold:
--   1. The item card shows the copy's own link when there is one, and else
--      takes the full name the row knows as its title.
--   2. The Sell list and Auctions hand the card the copy's link.
--   3. A suffix row on the Prices tab shows that suffix; the item's own row
--      stays plain.
--   4. Sales names each suffix as the mail did, on its own row in By item,
--      and picking one lights its own sales.

local GLOBALS = { "CreateFrame", "UIParent", "GameTooltip", "GameTooltipTextLeft1", "C_Timer",
    "GetTime", "time", "C_Item", "GetItemInfo", "GetLocale" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local passed, failed = 0, 0
local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-58s %s", label, ok and "ok" or
        ("WRONG: got " .. tostring(got) .. ", wanted " .. tostring(want))))
end

local function Frame()
    local f = { text = "", scripts = {} }
    f.SetText = function(self, t) self.text = t end
    f.GetText = function(self) return self.text end
    f.SetScript = function(self, name, fn) self.scripts[name] = fn end
    f.GetScript = function(self, name) return self.scripts[name] end
    f.CreateTexture = function() return Frame() end
    f.CreateFontString = function() return Frame() end
    return setmetatable(f, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
end

GetTime = function() return 1000 end
time = function() return 100000 end
GetLocale = function() return "enUS" end
C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }
CreateFrame = function() return Frame() end
UIParent = Frame()

local CAPTAIN, CAPE = 7486, 9945
local BASE = { [CAPTAIN] = "Captain's Breastplate", [CAPE] = "Royal Cape" }
local MAGIC_BONUS, MAGIC_KEY = 12801, 14330
local function NameOf(item)
    if type(item) == "number" then return BASE[item] end
    local named = type(item) == "string" and item:match("%[(.-)%]")
    if named then return named end
    local id = type(item) == "string" and tonumber(item:match("item:(%d+)"))
    if not id then return nil end
    if item:find(":1:" .. MAGIC_BONUS, 1, true) then return BASE[id] .. " of Magic" end
    return BASE[id]
end
C_Item = {
    GetItemInfo = function(item)
        local name = NameOf(item)
        if not name then return nil end
        local id = type(item) == "number" and item or tonumber(item:match("item:(%d+)"))
        return name, ("|cff1eff00|Hitem:%d::::::::::::|h[%s]|h|r"):format(id, BASE[id]), 2
    end,
    GetItemQualityByID = function() return 2 end,
}
GetItemInfo = C_Item.GetItemInfo

-- The game's tooltip: a link draws that copy, an ID draws the plain item.
local title = Frame()
GameTooltipTextLeft1 = title
GameTooltip = Frame()
GameTooltip.lines = 0
GameTooltip.SetOwner = function(self) self.lines = 0; title.text = "" end
GameTooltip.SetHyperlink = function(self, link) title.text = NameOf(link); self.lines = 3 end
GameTooltip.SetItemByID = function(self, id) title.text = BASE[id]; self.lines = 3 end
GameTooltip.SetText = function(self, t) title.text = t; self.lines = 1 end
GameTooltip.NumLines = function(self) return self.lines end

local function NewNs()
    local ns = {}
    ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
    ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
    ns.RegisterCommand, ns.RegisterEvent = noop, function() return true end
    ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = noop, noop, noop, noop
    return ns
end

local MAGIC_LINK = ("|cff1eff00|Hitem:%d::::::::18:1484::1:1:%d:::::|h[Captain's Breastplate of Magic]|h|r")
    :format(CAPTAIN, MAGIC_BONUS)

--------------------------------------------------------------------------------
print("")
print("1. the item card")

do
    local ns = NewNs()
    ns.Theme = setmetatable({ sizes = { small = 10, normal = 12, tiny = 9 }, FONT = "font",
        Unpack = function() return 1, 1, 1, 1 end, TextWidth = function() return 40 end },
        { __index = function() return function() return Frame() end end })
    assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
    assert(loadfile(lfs_cwd .. "/UI/Widgets.lua"))("Blackthornes_TS", ns)
    local Widgets = ns.Widgets
    local owner = Frame()

    Widgets.ShowItemTooltip(owner, "ANCHOR_LEFT", CAPTAIN, nil, MAGIC_LINK)
    check("a link draws that copy", title.text, "Captain's Breastplate of Magic")

    Widgets.ShowItemTooltip(owner, "ANCHOR_LEFT", CAPTAIN, "Captain's Breastplate of Magic")
    check("no link: the row's full name is the title", title.text, "Captain's Breastplate of Magic")

    Widgets.ShowItemTooltip(owner, "ANCHOR_LEFT", CAPTAIN, MAGIC_LINK)
    check("a full name given as a link reads the same", title.text, "Captain's Breastplate of Magic")

    Widgets.ShowItemTooltip(owner, "ANCHOR_LEFT", CAPTAIN, "Captain's Breastplate")
    check("the plain name stays plain", title.text, "Captain's Breastplate")

    Widgets.ShowItemTooltip(owner, "ANCHOR_LEFT", CAPTAIN, "Captain's Breastplates")
    check("a name that only starts the same is not taken", title.text, "Captain's Breastplate")

    Widgets.ShowItemTooltip(owner, "ANCHOR_LEFT", CAPTAIN, "Captain's Breastplate (2)")
    check("a count after the name is not a suffix", title.text, "Captain's Breastplate")

    Widgets.ShowItemTooltip(owner, "ANCHOR_LEFT", CAPTAIN, "craft")
    check("a label that is no name is not taken", title.text, "Captain's Breastplate")
end

--------------------------------------------------------------------------------
print("")
print("2. the Sell list and Auctions")

local handed
local function Recorder()
    return { ShowItemTooltip = function(_, _, itemID, fallback, link)
        handed = { itemID = itemID, fallback = fallback, link = link }
        return true
    end, CreateButton = function() return Frame() end }
end

do
    local ns = NewNs()
    ns.Theme = setmetatable({ sizes = { tiny = 10, small = 11, normal = 12 },
        Unpack = function() return 1, 1, 1 end, MeasureText = function(_, t) return #t * 6 end },
        { __index = function() return function() return Frame() end end })
    ns.Widgets = Recorder()
    ns.Util = { FormatMoney = function(c) return tostring(c) end }
    ns.Config = { Get = noop, Set = noop }
    ns.Collapse = { IsCollapsed = function() return false end }
    assert(loadfile(lfs_cwd .. "/UI/PostPanel.lua"))("Blackthornes_TS", ns)

    handed = nil
    -- Only the card matters here; the lines after it need more of the drawer.
    pcall(ns.PostPanel._ShowRowTooltip, Frame(), { itemID = CAPTAIN, link = MAGIC_LINK, label = MAGIC_LINK,
        unitPrice = 20987, postQuantity = 1 })
    check("Sell hands the card the copy's link", handed and handed.link, MAGIC_LINK)
end

-- After 1.43.0 (the same player, 2026-11-24): the drawer's card still read
-- "Captain's Breastplate". Drawn from a link, the game puts the plain name on
-- top and draws the card again from that link a moment later, so a name put
-- on top by hand does not stay. The bag copy itself names its suffix, so the
-- card comes from the bag slot while that slot still holds the item.
do
    local ns = NewNs()
    ns.Theme = setmetatable({ sizes = { tiny = 10, small = 11, normal = 12 },
        Unpack = function() return 1, 1, 1 end, MeasureText = function(_, t) return #t * 6 end },
        { __index = function() return function() return Frame() end end })
    ns.Util = { FormatMoney = function(c) return tostring(c) end }
    ns.Config = { Get = noop, Set = noop }
    ns.Collapse = { IsCollapsed = function() return false end }
    assert(loadfile(lfs_cwd .. "/UI/Widgets.lua"))("Blackthornes_TS", ns)
    ns.Widgets.CreateButton = function() return Frame() end
    assert(loadfile(lfs_cwd .. "/UI/PostPanel.lua"))("Blackthornes_TS", ns)

    -- Forever: a link draws the plain name; the bag slot draws the copy.
    local bagItems = { ["0:3"] = { itemID = CAPTAIN, name = "Captain's Breastplate of Magic" } }
    local source
    local savedHyper, savedContainer = GameTooltip.SetHyperlink, _G.C_Container
    GameTooltip.SetHyperlink = function(self, link)
        source = { kind = "link", id = tonumber(link:match("item:(%d+)")) }
        title.text = BASE[source.id]; self.lines = 3
    end
    GameTooltip.SetBagItem = function(self, bag, slot)
        local held = bagItems[bag .. ":" .. slot]
        if not held then return end
        source = { kind = "bag", held = held }
        title.text = held.name; self.lines = 3
    end
    -- The game drawing the card again from where it came from.
    local function Redraw()
        if not source then return end
        title.text = source.kind == "bag" and source.held.name or BASE[source.id]
    end
    _G.C_Container = { GetContainerItemInfo = function(bag, slot)
        local held = bagItems[bag .. ":" .. slot]
        return held and { itemID = held.itemID } or nil
    end }

    local line = { itemID = CAPTAIN, link = MAGIC_LINK, label = MAGIC_LINK, bag = 0, slot = 3,
        unitPrice = 20987, postQuantity = 1 }
    source = nil
    pcall(ns.PostPanel._ShowRowTooltip, Frame(), line)
    Redraw()
    check("the drawer's card names the suffix, and keeps it", title.text, "Captain's Breastplate of Magic")

    -- The copy moved: the slot holds something else now, so the link is used.
    bagItems["0:3"] = { itemID = 2589, name = "Linen Cloth" }
    source = nil
    pcall(ns.PostPanel._ShowRowTooltip, Frame(), line)
    check("a slot holding another item is not shown", source and source.kind, "link")
    check("the full name still goes on top", title.text, "Captain's Breastplate of Magic")

    GameTooltip.SetHyperlink, GameTooltip.SetBagItem, _G.C_Container = savedHyper, nil, savedContainer
end

do
    local ns = NewNs()
    ns.Theme = setmetatable({}, { __index = function() return function() return Frame() end end })
    ns.Widgets = Recorder()
    ns.Util = { FormatMoney = function(c) return tostring(c) end }
    assert(loadfile(lfs_cwd .. "/UI/AuctionsView.lua"))("Blackthornes_TS", ns)

    handed = nil
    pcall(ns.AuctionsView.ShowTooltip, Frame(), { itemID = CAPTAIN, link = MAGIC_LINK, unit = 20987, quantity = 1 })
    check("Auctions hands the card the copy's link", handed and handed.link, MAGIC_LINK)
end

--------------------------------------------------------------------------------
print("")
print("3. the Prices tab")

do
    local ns = NewNs()
    ns.Config = { Get = noop, GetPriceTable = function() return {} end, GetRealmKey = function() return "R" end }
    ns.db = { suffixWords = { bonuses = { [MAGIC_BONUS] = MAGIC_KEY }, tails = {} } }
    assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
    assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))("Blackthornes_TS", ns)
    local link = ns.Prices.SuffixLink and ns.Prices.SuffixLink(CAPTAIN, MAGIC_KEY)
    check("a suffix with a known bonus has a link", link and NameOf(link), "Captain's Breastplate of Magic")
    check("one without has none", ns.Prices.SuffixLink and ns.Prices.SuffixLink(CAPTAIN, 14999), nil)
    local opened = link and C_Item.GetItemInfo(link)
    check("and the link names the suffix", opened, "Captain's Breastplate of Magic")

    local prices = ns.Prices
    local ui = NewNs()
    ui.Theme = setmetatable({}, { __index = function() return function() return Frame() end end })
    ui.Util = { HasFunction = function() return false end }
    ui.UI = { RegisterTab = noop }
    ui.Prices = { SuffixLink = prices.SuffixLink, GetTable = function() return {} end }
    ui.Mail = { GetLedger = function() return { entries = {} } end }
    ui.db = { characters = {} }
    local listOpts
    ui.Widgets = setmetatable({
        ShowItemTooltip = Recorder().ShowItemTooltip,
        CreateScrollList = function(_, opts) listOpts = opts; return Frame() end,
    }, { __index = function() return function() return Frame() end end })
    assert(loadfile(lfs_cwd .. "/UI/Columns.lua"))("Blackthornes_TS", ui)
    assert(loadfile(lfs_cwd .. "/UI/Tab_Prices.lua"))("Blackthornes_TS", ui)
    local hover = ui.UI._PricesRowTooltip
    check("the tab has a row hover", type(hover), "function")
    if hover then
        handed = nil
        hover(Frame(), { kid = true, itemID = CAPTAIN, suffix = MAGIC_KEY,
            fullName = "Captain's Breastplate of Magic", name = " of Magic" })
        check("a suffix row hands that suffix's link", handed and handed.link and NameOf(handed.link),
            "Captain's Breastplate of Magic")
        check("and its full name", handed and handed.fallback, "Captain's Breastplate of Magic")
        handed = nil
        hover(Frame(), { kid = true, itemID = CAPTAIN, suffix = 14999, fullName = "Captain's Breastplate of Power" })
        check("no bonus known: the full name still goes", handed and handed.fallback,
            "Captain's Breastplate of Power")
        handed = nil
        hover(Frame(), { itemID = CAPTAIN, label = "Captain's Breastplate", suffixCount = 32 })
        check("the item's own row stays plain", handed and handed.link, nil)
    end
end

--------------------------------------------------------------------------------
print("")
print("4. Sales")

do
    local ns = NewNs()
    ns.Config = {
        GetRealmKey = function() return "Realm-Alliance" end,
        GetCharacterKey = function() return "Player-1" end,
        Get = noop,
    }
    ns.Recipes = { GetAccountWide = function() return {} end, GetAll = function() return {} end,
        GetCharacterRecord = noop }
    local detailTitle
    ns.Theme = setmetatable({
        Unpack = function() return 1, 1, 1, 1 end,
        CreateLabel = function(_, size)
            local label = Frame()
            if size == "large" then detailTitle = label end
            return label
        end,
    }, { __index = function() return function() return Frame() end end })
    ns.db = { mailLedger = { ["Realm-Alliance"] = { seen = {}, entries = {
        { t = 90000, kind = "sold", who = "Player-1", name = "Royal Cape of the Sorcerer", itemID = CAPE, net = 9000 },
        { t = 91000, kind = "sold", who = "Player-1", name = "Royal Cape of the Owl", itemID = CAPE, net = 7000 },
        { t = 92000, kind = "expired", who = "Player-1", name = "Royal Cape of the Sorcerer", itemID = CAPE },
        { t = 93000, kind = "sold", who = "Player-1", name = "Royal Cape", itemID = CAPE, net = 5000 },
    } } } }
    assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
    assert(loadfile(lfs_cwd .. "/Data/Mail.lua"))("Blackthornes_TS", ns)

    local listOpts, listData
    local rows = {}
    ns.Widgets = {
        CreateSearchBox = function() return Frame() end,
        CreateDropdown = function() return Frame() end,
        CreateTabStrip = function() local strip = Frame() strip.Select = noop return strip end,
        CreateButton = function() return Frame() end,
        ShowItemOnly = function(_, itemID, name) handed = { itemID = itemID, fallback = name } end,
        CreateScrollList = function(_, opts)
            listOpts = opts
            local list = Frame()
            list.SetData = function(_, data) listData = data end
            return list
        end,
    }
    local tab
    ns.UI = { RegisterTab = function(_, def) tab = def end }
    ns.MailHaul = { GetHistory = function() return {} end, Records = function() return 0 end }
    ns.GoldChart = { CreateChart = function() return Frame() end, CreateLegend = function() return Frame() end }
    assert(loadfile(lfs_cwd .. "/UI/Tab_Sales.lua"))("Blackthornes_TS", ns)
    tab.build(Frame())
    tab.refresh()

    local items = ns.Mail:GetItems()
    local byName = {}
    for _, item in ipairs(items) do byName[item.name] = item end
    check("By item: each suffix has its own row", #items, 3)
    check("the Sorcerer row counts its own sale", byName["Royal Cape of the Sorcerer"]
        and byName["Royal Cape of the Sorcerer"].sold, 1)
    check("and its own expiry", byName["Royal Cape of the Sorcerer"]
        and byName["Royal Cape of the Sorcerer"].expired, 1)
    check("the plain cape keeps its own", byName["Royal Cape"] and byName["Royal Cape"].sold, 1)

    local sorcererSale
    for _, data in ipairs(listData) do
        if data.kind == "sold" and data.name == "Royal Cape of the Sorcerer" then sorcererSale = data end
    end
    local row = Frame()
    listOpts.createRow(row)
    if row and sorcererSale then
        listOpts.updateRow(row, sorcererSale)
        local shown = ns.Util.StripColors and ns.Util.StripColors(row.name:GetText()) or row.name:GetText()
        check("the sale's row names the suffix", shown and shown:match("%[?(Royal Cape[^%]|]*)"),
            "Royal Cape of the Sorcerer")
    else
        check("a sale's row could be drawn", row ~= nil and sorcererSale ~= nil, true)
    end

    listOpts.onClick(sorcererSale)
    check("picking the sale shows its suffix in the pane", detailTitle and
        (detailTitle:GetText() or ""):find("Royal Cape of the Sorcerer", 1, true) ~= nil, true)
    listOpts.onClick(sorcererSale)
    listOpts.onClick(byName["Royal Cape of the Sorcerer"])
    check("picked from By item, its own sale is lit", listOpts.isSelected(sorcererSale), true)
end

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "suffix tooltip checks failed")
