-- Blackthornes Tradeskills -- UI/SalesBought.lua
-- The Sales tab's Bought view: every auction house buy for the period
-- picked, from Logic/BuyLog.lua (a player asked, the owner said build it
-- from a mockup, 2026-11-14).
--
-- Three numbers over a full-width list (Spent, Items Bought, Most Bought),
-- then one row a buy: ITEM, BOUGHT, PAID EACH, TOTAL, CHARACTER, WHEN, all
-- sortable, newest first. The period chips are the tab's own; this file
-- adds the Character: menu after them and the search box on the right.
-- Nothing here writes to the save.

local _, ns = ...
local L = ns.L

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local SalesBought = ns.NewModule("SalesBought")

local ROW_HEIGHT = 30
local TILE_HEIGHT, TILE_GAP = 46, 8
local GAP = 8
local DAY = 86400

--- Right to left, as the row cells are laid out.
SalesBought.COLUMNS = {
    { key = "when",  label = L["WHEN"],      width = 64 },
    { key = "who",   label = L["CHARACTER"], width = 130 },
    { key = "total", label = L["TOTAL"],     width = 84, money = true },
    { key = "each",  label = L["PAID EACH"], width = 84, money = true },
    { key = "n",     label = L["BOUGHT"],    width = 56 },
}

local state = { who = "all", search = "", rows = {}, shown = {} }
SalesBought.state = state

local w = {}
local awaitingItemData = false

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

--- "1h ago", "yesterday", "2d ago".
function SalesBought.WhenText(at, now)
    now = now or time()
    local age = math.max(0, now - (at or now))
    if age >= DAY and age < 2 * DAY then return L["yesterday"] end
    return Util.FormatAgeAgo(age)
end

--- The character's whole name, or a dash for buys from before the log.
function SalesBought.WhoText(who)
    if type(who) ~= "string" or who == "" then return "-" end
    local name = Util.CharacterName(who)
    if name == "" then return "-" end
    return name
end

local function EachOf(row)
    if not row.n or row.n <= 0 then return 0 end
    return math.floor(row.paid / row.n + 0.5)
end

local function Money(copper)
    return Util.FormatMoney(copper or 0, { short = true })
end

--- The item's plain name: the row colours it by quality itself.
local function NameOf(id)
    local label = Util.Uncolored(Util.GetItemLabel(id) or tostring(id))
    if type(label) ~= "string" then return tostring(id) end
    return label:match("%[(.-)%]") or label
end
SalesBought.NameOf = NameOf

local function ColorName(label, id)
    local r, g, b = Util.GetItemQualityColor(id)
    if r then
        label:SetTextColor(r, g, b)
    else
        label:SetTextColor(Theme.Unpack("text"))
        awaitingItemData = true
    end
end

--- Does a buy match what has been typed? By name or item ID.
function SalesBought.Matches(row, query)
    if not query or query == "" then return true end
    if tostring(row.id) == query then return true end
    return NameOf(row.id):lower():find(query, 1, true) ~= nil
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function PlaceCells(cells, right)
    local x = right or -12
    for _, column in ipairs(SalesBought.COLUMNS) do
        local cell = cells[column.key]
        cell:ClearAllPoints()
        cell:SetPoint("RIGHT", cell:GetParent(), "RIGHT", x, 0)
        cell:SetWidth(column.width)
        x = x - column.width - GAP
    end
    return x
end

local function CreateRow(row)
    row.icon = Theme.CreateItemIcon(row, 24)
    row.icon:SetPoint("LEFT", 8, 0)

    row.cells = {}
    for _, column in ipairs(SalesBought.COLUMNS) do
        local color = (column.key == "n" and "accent") or (column.key == "when" and "dim") or "text"
        local cell = Theme.CreateLabel(row, "small", color, "RIGHT")
        cell:SetWordWrap(true)
        row.cells[column.key] = cell
    end
    local left = PlaceCells(row.cells)

    row.name = Theme.CreateLabel(row, "normal", "text")
    row.name:SetPoint("LEFT", 40, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", left, 0)
    row.name:SetJustifyH("LEFT")
end

local function UpdateRow(row, data)
    Theme.SetItemIcon(row.icon, data.id)
    if Theme.SetRowName then
        Theme.SetRowName(row.name, NameOf(data.id), "normal")
    else
        row.name:SetText(NameOf(data.id))
    end
    ColorName(row.name, data.id)

    row.cells.n:SetText(Util.Comma and Util.Comma(data.n) or tostring(data.n))
    row.cells.each:SetText(Money(EachOf(data)))
    row.cells.total:SetText(Money(data.paid))
    row.cells.who:SetText(SalesBought.WhoText(data.who))
    row.cells.when:SetText(SalesBought.WhenText(data.at))
end

local function ShowTip(row, data)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local r, g, b = Util.GetItemQualityColor(data.id)
    GameTooltip:SetText(NameOf(data.id), r or 1, g or 1, b or 1)

    local dr, dg, db = Theme.Unpack("dim")
    local tr, tg, tb = Theme.Unpack("text")
    local who = SalesBought.WhoText(data.who)
    local bought = who ~= "-" and L.Format("%d by %s", data.n, who) or tostring(data.n)
    GameTooltip:AddDoubleLine(L["Bought:"], bought, dr, dg, db, tr, tg, tb)

    local totals = ns.BuyLog.ItemTotals(state.rows, data.id)
    GameTooltip:AddDoubleLine(L["Average Paid:"], L.Format("%s each", Money(math.floor(totals.each + 0.5))),
        dr, dg, db, tr, tg, tb)
    GameTooltip:AddDoubleLine(L["All Buys:"], L.Format("%d in %d buys", totals.n, totals.buys),
        dr, dg, db, tr, tg, tb)
    GameTooltip:AddLine(L["Click to search for it at the auction house."], dr, dg, db, true)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

--- Lay the view out. `toolbar` is the tab's bar, `period` its time chips.
function SalesBought:Build(container, toolbar, period, onChange)
    self.onChange = onChange

    local characterLabel = Theme.CreateLabel(toolbar, "small", "muted")
    characterLabel:SetText(L["Character:"])
    w.characterLabel = characterLabel

    local character = Widgets.CreateDropdown(toolbar, {}, function(value)
        state.who = value or "all"
        if self.onChange then self.onChange() end
    end, { width = 140 })
    character:SetPoint("LEFT", characterLabel, "RIGHT", 6, 0)
    w.character = character
    self:PlaceCharacter(period)

    local search = Widgets.CreateSearchBox(toolbar, L["Search buys"], function(text)
        state.search = (text or ""):lower()
        if self.onChange then self.onChange() end
    end)
    search:SetPoint("RIGHT", 0, 0)
    search:SetWidth(Widgets.SEARCH_WIDTH)
    w.search = search

    local panel = CreateFrame("Frame", nil, container)
    panel:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    panel:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 42)
    w.panel = panel

    local divider = Theme.CreateDivider(panel)
    divider:SetPoint("TOPLEFT", 0, 0)
    divider:SetPoint("TOPRIGHT", 0, 0)

    local tiles = CreateFrame("Frame", nil, panel)
    tiles:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -6)
    tiles:SetPoint("TOPRIGHT", divider, "BOTTOMRIGHT", 0, -6)
    tiles:SetHeight(TILE_HEIGHT)
    tiles.items = {}
    for index = 1, 3 do
        local tile = Theme.CreatePanel(tiles, "glassAlt")
        tile:SetHeight(TILE_HEIGHT)
        Theme.AccentStripe(tile, 3)
        tile.label = Theme.CreateLabel(tile, "tiny", "dim")
        tile.label:SetPoint("TOPLEFT", 10, -5)
        tile.label:SetPoint("RIGHT", tile, "RIGHT", -6, 0)
        tile.value = Theme.CreateLabel(tile, "large", "accent")
        tile.value:SetPoint("TOPLEFT", tile.label, "BOTTOMLEFT", 0, -2)
        tile.value:SetPoint("RIGHT", tile, "RIGHT", -6, 0)
        tile.value:SetWordWrap(false)
        tile.sub = Theme.CreateLabel(tile, "tiny", "dim")
        tile.sub:SetPoint("TOPLEFT", tile.value, "BOTTOMLEFT", 0, -1)
        tile.sub:SetPoint("RIGHT", tile, "RIGHT", -6, 0)
        tile.sub:SetWordWrap(false)
        tiles.items[index] = tile
    end
    tiles.items[1].label:SetText(L["Spent:"])
    tiles.items[2].label:SetText(L["Items Bought:"])
    tiles.items[3].label:SetText(L["Most Bought:"])
    local function PlaceTiles()
        local width = tiles:GetWidth() or 0
        if width <= 0 then return end
        local each = (width - 2 * TILE_GAP) / 3
        for index, tile in ipairs(tiles.items) do
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", tiles, "TOPLEFT", (index - 1) * (each + TILE_GAP), 0)
            tile:SetWidth(each)
        end
    end
    tiles:SetScript("OnSizeChanged", PlaceTiles)
    PlaceTiles()
    w.tiles = tiles

    if Widgets.FitColumns then Widgets.FitColumns(self.COLUMNS) end
    local headings = CreateFrame("Frame", nil, panel)
    headings:SetHeight(14)
    headings:SetPoint("TOPLEFT", tiles, "BOTTOMLEFT", 0, -6)
    headings:SetPoint("TOPRIGHT", tiles, "BOTTOMRIGHT", 0, -6)
    local itemHeading = Theme.CreateLabel(headings, "tiny", "dim")
    itemHeading:SetPoint("LEFT", 40, 0)
    itemHeading:SetText(L["ITEM"])
    headings.cells = {}
    for _, column in ipairs(self.COLUMNS) do
        local cell = Theme.CreateLabel(headings, "tiny", "dim", "RIGHT")
        cell:SetText(column.label)
        headings.cells[column.key] = cell
    end
    PlaceCells(headings.cells)
    w.headings = headings

    local labels = { name = itemHeading }
    for key, cell in pairs(headings.cells) do labels[key] = cell end
    w.sorter = Widgets.SortableHeadings and Widgets.SortableHeadings(labels, {
        name = function(row) return NameOf(row.id) end,
        n = function(row) return row.n or 0 end,
        each = function(row) return EachOf(row) end,
        total = function(row) return row.paid or 0 end,
        who = function(row) return SalesBought.WhoText(row.who) end,
        when = function(row) return row.at or 0 end,
    }, function() self:Draw() end)
    if w.sorter then
        w.sorter:SetText({ "name", "who" })
        w.sorter.key = "when"
        w.sorter.ascending = false
        w.sorter:Sync()
    end

    local list = Widgets.CreateScrollList(panel, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onEnter = ShowTip,
        onLeave = function() GameTooltip:Hide() end,
        onScrollbarShown = function(shown)
            headings:SetPoint("TOPRIGHT", tiles, "BOTTOMRIGHT", shown and -10 or 0, -6)
        end,
        onClick = function(data)
            if ns.UI and ns.UI.SearchAuctionHouse then ns.UI:SearchAuctionHouse(data.id, data.n) end
        end,
    })
    list:SetPoint("TOPLEFT", headings, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    w.list = list


    local queued = false
    ns.RegisterEvent(ns.UI, "GET_ITEM_INFO_RECEIVED", function()
        if queued or not awaitingItemData or not panel:IsVisible() then return end
        queued = true
        C_Timer.After(0.2, function()
            queued = false
            self:Draw()
        end)
    end)

    self:Show(false)
end

--- The Character: menu sits right after the period chips, or after the
--- picked days when dates are being picked.
function SalesBought:PlaceCharacter(after)
    if not w.characterLabel or not after then return end
    w.characterLabel:ClearAllPoints()
    w.characterLabel:SetPoint("LEFT", after, "RIGHT", 12, 0)
end

function SalesBought:Show(shown)
    if not w.panel then return end
    w.panel:SetShown(shown)
    w.search:SetShown(shown)
    w.character:SetShown(shown)
    w.characterLabel:SetShown(shown)
end

local function UpdateCharacterMenu()
    local options = { { text = L["All Characters"], value = "all" } }
    local found = state.who == "all"
    local keys = ns.BuyLog:Characters()
    local named = {}
    for _, key in ipairs(keys) do
        local name = SalesBought.WhoText(key)
        if name ~= "-" then named[#named + 1] = { text = name, value = key } end
    end
    table.sort(named, function(a, b) return a.text < b.text end)
    local widest = Theme.MeasureText and Theme.MeasureText("small", options[1].text) or 0
    for _, option in ipairs(named) do
        options[#options + 1] = option
        if option.value == state.who then found = true end
        widest = math.max(widest, Theme.MeasureText and Theme.MeasureText("small", option.text) or 0)
    end
    if not found then state.who = "all" end
    w.character:SetWidth(math.max(140, widest + 30))
    w.character:SetOptions(options)
    w.character:SetValue(state.who)
end

--- Read the log for `from` to `to` and draw. Returns how many buys show.
function SalesBought:Refresh(from, to)
    if not w.panel then return 0 end
    UpdateCharacterMenu()
    state.rows = ns.BuyLog:Rows(from, to, state.who)
    return self:Draw()
end

function SalesBought:Draw()
    if not w.panel then return 0 end
    awaitingItemData = false

    local shown = {}
    for _, row in ipairs(state.rows) do
        if SalesBought.Matches(row, state.search) then shown[#shown + 1] = row end
    end
    state.shown = shown

    local totals = ns.BuyLog.Totals(shown)
    local tiles = w.tiles.items
    tiles[1].value:SetText(Money(totals.spent))
    tiles[1].sub:SetText(L["on the auction house"])
    tiles[2].value:SetText(Util.Comma and Util.Comma(totals.items) or tostring(totals.items))
    tiles[2].sub:SetText(L.Format("in %d buys", totals.buys))
    if totals.top then
        tiles[3].value:SetText(NameOf(totals.top))
        ColorName(tiles[3].value, totals.top)
        tiles[3].sub:SetText(L.Format("%d bought", totals.topCount))
    else
        tiles[3].value:SetText("-")
        tiles[3].value:SetTextColor(Theme.Unpack("accent"))
        tiles[3].sub:SetText("")
    end

    local data = w.sorter and w.sorter:Sort(shown) or shown
    w.list:SetData(data)
    return #shown
end
