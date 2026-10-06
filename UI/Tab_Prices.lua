-- Blackthornes Tradeskills -- UI/Tab_Prices.lua
-- The price database, browsable.
--
-- The Profit tab tells you what to make; this tells you why it thinks so. Every
-- number the profit engine uses is visible here, including the ones that
-- undermine it: how thin the market is, how old the reading is, and how few
-- scans it rests on.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 22
local DETAIL_WIDTH = 300

local COLUMNS = {
    { key = "age",       label = "AGE",    width = 44 },
    { key = "liquidity", label = "MOVES",  width = 52 },
    { key = "quantity",  label = "LISTED", width = 52 },
    { key = "min",       label = "CHEAPEST", width = 80 },
    { key = "market",    label = "MARKET", width = 80 },
}

local state = {
    search = "",
    reagentsOnly = false,
    favouritesOnly = false,
    mineOnly = false,
    sortBy = "market",
    selected = nil,
}

local widgets = {}

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

--- Item IDs used as reagents by any cached recipe.
local function GetReagentSet()
    local reagents = {}

    for _, recipe in pairs(ns.Recipes:GetAll()) do
        for _, reagent in ipairs(recipe.reagents or {}) do
            reagents[reagent.itemID] = true
        end

        if recipe.outputItemID then
            reagents[recipe.outputItemID] = true
        end
    end

    return reagents
end

--- An item's plain name without fetching it: the saved facts first, then
--- the client only for an item it already holds. The whole price table is
--- thousands of items, and reading each through the client on every redraw
--- pushed bag items out of its small cache (Ready to sell then flickers).
local function PlainName(itemID)
    local name = ns.Disenchant and ns.Disenchant.KnownName and ns.Disenchant:KnownName(itemID)
    if name then return name end

    if Util.HasFunction("C_Item.IsItemDataCachedByID") then
        local ok, cached = pcall(C_Item.IsItemDataCachedByID, itemID)
        if not ok or cached ~= true then return nil end
    else
        return nil
    end

    local ok, itemName = pcall(C_Item.GetItemInfo, itemID)
    return ok and itemName or nil
end

--- Names the addon saved itself, for items the game has not loaded: the
--- sales history's item names and what your recipes make. Read from saved
--- data only, so a search never asks the game to load anything.
local function StoredNames()
    local names = {}

    if ns.Mail and ns.Mail.GetLedger then
        local ok, ledger = pcall(ns.Mail.GetLedger, ns.Mail)
        for _, entry in ipairs(ok and type(ledger) == "table" and ledger.entries or {}) do
            if entry.itemID and type(entry.name) == "string" then names[entry.itemID] = entry.name end
        end
    end

    for _, record in pairs(ns.db and ns.db.characters or {}) do
        for _, recipe in pairs(type(record) == "table" and record.recipes or {}) do
            local itemID = type(recipe) == "table" and recipe.outputItemID
            if itemID and not names[itemID] and type(recipe.name) == "string" then
                names[itemID] = recipe.name
            end
        end
    end

    -- A starred item keeps the name it had when it was starred.
    for itemID, name in pairs(ns.Prices.GetFavourites and ns.Prices:GetFavourites() or {}) do
        if not names[itemID] and type(name) == "string" then names[itemID] = name end
    end

    -- And an item given its own price, the name it had then.
    for itemID, entry in pairs(ns.Prices.GetAllMine and ns.Prices:GetAllMine() or {}) do
        if not names[itemID] and type(entry) == "table" and type(entry.name) == "string" then
            names[itemID] = entry.name
        end
    end

    return names
end

local function IsFavourite(itemID)
    return ns.Prices.IsFavourite ~= nil and ns.Prices:IsFavourite(itemID)
end

--- The price the player set on an item, and its kind, or nil.
local function Mine(itemID)
    if not ns.Prices.GetMine then return nil end
    return ns.Prices:GetMine(itemID)
end

local function BuildList()
    local rows = {}
    local reagents = state.reagentsOnly and GetReagentSet() or nil
    local favourites = ns.Prices.GetFavourites and ns.Prices:GetFavourites() or {}

    -- Names are only needed to search or sort by; the label itself is read
    -- for the rows on screen, in UpdateRow.
    local wantNames = state.search ~= "" or state.sortBy == "name"
        or (widgets.sorter ~= nil and widgets.sorter.key == "name")
    local stored = wantNames and StoredNames() or {}

    local prices = ns.Prices:GetTable()

    local function Add(itemID, record)
        if reagents and not reagents[itemID] then return end
        if state.favouritesOnly and favourites[itemID] == nil then return end
        if state.mineOnly and not Mine(itemID) then return end

        rows[#rows + 1] = {
            itemID = itemID,
            record = record,
            market = record.market or 0,
            min = record.min or 0,
            quantity = record.quantity or 0,
            age = ns.Prices:GetAge(itemID) or math.huge,
            liquidity = ns.Prices:GetLiquidity(itemID),
            name = wantNames and (PlainName(itemID) or stored[itemID]
                or ("~item %d"):format(itemID)) or "",
        }
    end

    for itemID, record in pairs(prices) do
        Add(itemID, record)
    end

    -- A starred item with no price yet (never scanned, or pruned for age)
    -- still shows, with dashes, so it never quietly drops off the list.
    local added = {}
    for itemID in pairs(favourites) do
        if type(itemID) == "number" and not prices[itemID] then
            Add(itemID, {})
            added[itemID] = true
        end
    end

    -- So does an item given its own price.
    for itemID in pairs(ns.Prices.GetAllMine and ns.Prices:GetAllMine() or {}) do
        if type(itemID) == "number" and not prices[itemID] and not added[itemID] and Mine(itemID) then
            Add(itemID, {})
        end
    end

    if state.search ~= "" then
        local needle = state.search:lower()
        local filtered = {}

        for _, row in ipairs(rows) do
            if row.name:lower():find(needle, 1, true) then
                filtered[#filtered + 1] = row
            end
        end
        rows = filtered
    end

    local sortBy = state.sortBy

    table.sort(rows, function(a, b)
        -- Age sorts ascending: freshest first is the useful direction.
        if sortBy == "age" then
            -- One scan prices many items at once; ties go by item so those
            -- rows do not swap places on every redraw.
            if a.age ~= b.age then return a.age < b.age end
            return a.itemID < b.itemID
        end

        if sortBy == "name" then
            if a.name ~= b.name then return a.name < b.name end
            return a.itemID < b.itemID
        end

        local left = a[sortBy] or 0
        local right = b[sortBy] or 0

        if left == right then return a.itemID < b.itemID end
        return left > right
    end)

    -- A clicked heading's order over the menu's.
    if widgets.sorter then rows = widgets.sorter:Sort(rows) end

    return rows
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local Refresh
local BuildMyPrice

--- The favourite star: a gold star when the item is starred, a grey one when
--- not, lit under the mouse with a tooltip saying what a click does, so it
--- reads as a button rather than decoration. `getItemID` names the item the
--- star belongs to when it is clicked.
local function CreateStar(parent, size, getItemID)
    local star = CreateFrame("Button", nil, parent)
    star:SetSize(size + 4, size + 4)

    local file = (Theme.MEDIA or "") .. "SkillUpStar"

    -- A soft gold light behind the star, under the mouse and when starred.
    local glow = star:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("CENTER")
    glow:SetSize(size + 10, size + 10)
    glow:SetTexture(file)
    pcall(glow.SetBlendMode, glow, "ADD")
    glow:SetAlpha(0)
    star.glow = glow

    local art = star:CreateTexture(nil, "ARTWORK")
    art:SetPoint("CENTER")
    art:SetSize(size, size)
    art:SetTexture(file)
    star.art = art

    local function Paint(hovered)
        local on = star.itemID ~= nil and IsFavourite(star.itemID)
        star.on = on
        pcall(art.SetDesaturated, art, not on)
        if on then
            art:SetVertexColor(1, 1, 1)
            art:SetAlpha(1)
        else
            -- Grey but plain to see, brighter under the mouse.
            art:SetVertexColor(0.85, 0.85, 0.85)
            art:SetAlpha(hovered and 0.95 or 0.5)
        end
        glow:SetAlpha(hovered and 0.55 or on and 0.2 or 0)
    end
    star.Paint = Paint

    function star:SetItem(itemID)
        self.itemID = itemID
        Paint(self.IsMouseOver ~= nil and self:IsMouseOver() == true)
    end

    local function ShowTip()
        GameTooltip:SetOwner(star, "ANCHOR_TOP")
        GameTooltip:SetText(star.on and "Remove from favourites" or "Add to favourites", 1, 1, 1, 1, true)
        GameTooltip:AddLine("Tick Favourites only to see just your starred items.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end

    star:SetScript("OnClick", function(self)
        local itemID = getItemID and getItemID() or self.itemID
        if not itemID then return end

        local on = not IsFavourite(itemID)
        local name = PlainName(itemID)
        ns.Prices:SetFavourite(itemID, on, name)

        -- Starred by hand, the star pops: a little past full size, then settles.
        if on and ns.Motion and ns.Motion.Run then
            ns.Motion:Run(art, "pop", 0.25, function(p)
                local grown = math.max(1, size * p)
                art:SetSize(grown, grown)
            end, { ease = ns.Motion.EaseOutBack })
        end

        if Refresh then Refresh() end
        Paint(true)
        ShowTip()
    end)

    star:SetScript("OnEnter", function()
        Paint(true)
        ShowTip()
    end)
    star:SetScript("OnLeave", function()
        Paint(false)
        GameTooltip:Hide()
    end)

    Paint(false)
    return star
end

local function CreateRow(row)
    -- The favourite star at the row's left end, before the icon.
    row.star = CreateStar(row, 14, function() return row.data and row.data.itemID end)
    row.star:SetPoint("LEFT", 4, 0)

    -- The item's icon beside its name, as the bags draw it.
    row.icon = Theme.CreateItemIcon(row, 16)
    row.icon:SetPoint("LEFT", 26, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 46, 0)

    row.cells = {}

    local offset = -8
    local reserved = 16

    for _, column in ipairs(COLUMNS) do
        local cell = Theme.CreateLabel(row, "small", "muted", "RIGHT")
        cell:SetPoint("RIGHT", offset, 0)
        cell:SetWidth(column.width)

        row.cells[column.key] = cell

        offset = offset - column.width - 6
        reserved = reserved + column.width + 6
    end

    row.name:SetPoint("RIGHT", row, "RIGHT", -reserved, 0)
end

local function UpdateRow(row, entry)
    entry.label = Util.GetItemLabel(entry.itemID)
    -- An item with its own price says so, in gold, beside its name.
    if Mine(entry.itemID) then
        row.name:SetText(("%s  |c%smy price|r"):format(entry.label, ns.COLORS.warn))
    else
        row.name:SetText(entry.label)
    end
    Theme.SetItemIcon(row.icon, entry.itemID)
    row.star:SetItem(entry.itemID)

    local stale = ns.Prices:IsStale(entry.itemID)
    row.name:SetTextColor(Theme.Unpack(stale and "muted" or "text"))

    local cells = row.cells

    -- Measured into the cell: "12g 34s 56c" is wider than it, and was cut
    -- off. It drops to the two largest coins, then one, rounded.
    Theme.SetMoneyText(cells.market, entry.record.market, { short = true })
    cells.market:SetTextColor(Theme.Unpack("text"))

    local listedMin = entry.record.min ~= nil
    if listedMin then
        Theme.SetMoneyText(cells.min, entry.record.min, { short = true })
    else
        cells.min:SetText("none")
    end
    cells.min:SetTextColor(Theme.Unpack(listedMin and "text" or "dim"))

    -- Sold out reads as sold out, apart from a thin shelf at a glance.
    local listed = (entry.quantity or 0) > 0
    cells.quantity:SetText(listed and Util.Comma(entry.quantity) or "none")
    cells.quantity:SetTextColor(Theme.Unpack(listed and "muted" or "dim"))

    if entry.liquidity then
        cells.liquidity:SetText(("%d%%"):format(math.floor(entry.liquidity * 100)))
        cells.liquidity:SetTextColor(Theme.Unpack(entry.liquidity > 0.15 and "profit" or "muted"))
    else
        -- One scan cannot show movement; say so rather than implying zero sales.
        cells.liquidity:SetText("--")
        cells.liquidity:SetTextColor(Theme.Unpack("dim"))
    end

    -- "now" rather than "just now", which is wider than the column.
    local age = Util.FormatAge(entry.record.seen and (time() - entry.record.seen))
    cells.age:SetText(age == "just now" and "now" or age)
    cells.age:SetTextColor(Theme.Unpack(stale and "warn" or "dim"))
end

--------------------------------------------------------------------------------
-- Detail panel
--------------------------------------------------------------------------------

-- My price (Ponyboy, 2026-10-06): the player's own price for the item, in
-- gold, silver and copper boxes, and whether it is used instead of the
-- auction price or only as the least it can be. Saved as it is typed;
-- a price of nothing clears it, and so does Clear.

local MY_MODES = {
    { text = "Use this price", value = "use" },
    { text = "Never below", value = "floor" },
}

local MY_STATUS = {
    use = "Used instead of the AH price",
    floor = "AH price, but never below",
}

local function MyPriceTyped(my)
    local gold = my.gold:GetValue() or 0
    local silver = my.silver:GetValue() or 0
    local copper = my.copper:GetValue() or 0
    return gold * 10000 + silver * 100 + copper
end

local function SaveMyPrice()
    -- The item the boxes were filled for: a box left mid-edit by a click on
    -- another row saves to the item it was typed for.
    local my = widgets.detail and widgets.detail.myPrice
    local itemID = my and my.itemID
    if not itemID then return end

    ns.Prices:SetMine(itemID, MyPriceTyped(my), my.mode:GetValue() or "use", PlainName(itemID))
    if Refresh then Refresh() end
end

BuildMyPrice = function(detail, anchor)
    local my = {}
    detail.myPrice = my

    local heading = Theme.CreateLabel(detail, "tiny", "dim")
    heading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
    heading:SetText("MY PRICE")
    Theme.StyleHeading(heading, detail)
    my.heading = heading

    local parts = {}
    local last
    local function Coin(key, width, max, suffix)
        local box = Widgets.CreateNumberBox(detail, {
            width = width, min = 0, max = max,
            onChange = function() SaveMyPrice() end,
        })
        if last then
            box:SetPoint("LEFT", last, "RIGHT", 4, 0)
        else
            box:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -6)
        end

        local mark = Theme.CreateLabel(detail, "small", "text")
        mark:SetPoint("LEFT", box, "RIGHT", 2, 0)
        mark:SetText(suffix)

        my[key] = box
        parts[#parts + 1] = box
        parts[#parts + 1] = mark
        last = mark
    end

    Coin("gold", 44, 214748, "|cffffd700g|r")
    Coin("silver", 28, 99, "|cffc7c7cfs|r")
    Coin("copper", 28, 99, "|cffeda55fc|r")

    my.mode = Widgets.CreateDropdown(detail, MY_MODES, function() SaveMyPrice() end, { width = 118 })
    my.mode:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, 0)
    my.mode:SetPoint("TOP", my.gold, "TOP", 0, 0)
    my.mode:SetValue("use")
    parts[#parts + 1] = my.mode

    my.clear = Widgets.CreateButton(detail, "Clear", function()
        if not my.itemID then return end
        ns.Prices:SetMine(my.itemID, nil)
        if Refresh then Refresh() end
    end, { width = 64, height = 22, tooltip = "Take your price off and go back to the AH price" })
    my.clear:SetPoint("TOPRIGHT", my.mode, "BOTTOMRIGHT", 0, -6)
    parts[#parts + 1] = my.clear

    -- Beside Clear, as wide as the pane leaves it.
    local status = Theme.CreateLabel(detail, "small", "muted")
    status:SetPoint("TOPLEFT", my.gold, "BOTTOMLEFT", 0, -11)
    status:SetWidth(DETAIL_WIDTH - 24 - 64 - 8)
    status:SetWordWrap(false)
    my.status = status
    parts[#parts + 1] = status

    -- Tooltips on the boxes, so what they are for is never a guess.
    for _, box in ipairs({ my.gold, my.silver, my.copper }) do
        box.editBox:SetScript("OnEnter", function(self)
            Theme.SetBorderColor(box, "borderLit")
            GameTooltip:SetOwner(box, "ANCHOR_TOP")
            GameTooltip:SetText("My price", 1, 1, 1)
            GameTooltip:AddLine("Your own price for this item. Pick whether it is used instead of the AH price, or only as the least it can be.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        box.editBox:SetScript("OnLeave", function()
            Theme.SetBorderColor(box, "border")
            GameTooltip:Hide()
        end)
    end

    function my:SetShown(shown)
        heading:SetShown(shown)
        for _, part in ipairs(parts) do part:SetShown(shown) end
    end

    local function Focused(box)
        local edit = box.editBox
        return type(edit.HasFocus) == "function" and edit:HasFocus() == true
    end

    function my:Show(itemID)
        -- Another item: a box still being typed in saves first, to its own.
        if self.itemID ~= itemID then
            for _, box in ipairs({ self.gold, self.silver, self.copper }) do
                if Focused(box) then box.editBox:ClearFocus() end
            end
        end
        self.itemID = itemID

        -- A redraw while typing (the auction house redraws often) leaves
        -- the box being typed in alone.
        local price, mode = Mine(itemID)
        local gold, silver, copper = Util.SplitMoney(price or 0)
        if not Focused(self.gold) then self.gold:SetValue(gold, true) end
        if not Focused(self.silver) then self.silver:SetValue(silver, true) end
        if not Focused(self.copper) then self.copper:SetValue(copper, true) end
        self.mode:SetValue(mode or self.mode:GetValue() or "use")
        self.clear:SetEnabledState(price ~= nil)

        if price then
            status:SetText(MY_STATUS[mode])
            status:SetTextColor(Theme.Unpack("warn"))
        else
            status:SetText("Not set, the AH price is used")
            status:SetTextColor(Theme.Unpack("dim"))
        end
    end
end

local function BuildDetail(parent)
    local detail = Theme.CreatePanel(parent, "window")
    detail:SetWidth(DETAIL_WIDTH)

    Theme.AccentStripe(detail, 2, 0.6)

    -- The item's icon beside its name, as on the other detail panes.
    local icon = Theme.CreateItemIcon(detail, 30)
    icon:SetPoint("TOPLEFT", 12, -12)
    detail.icon = icon

    -- The same star as the rows', at the pane's top right.
    detail.star = CreateStar(detail, 18, function() return state.selected and state.selected.itemID end)
    detail.star:SetPoint("TOPRIGHT", -8, -10)

    local title = Theme.CreateLabel(detail, "large", "accent")
    title:SetPoint("TOPLEFT", 50, -12)
    title:SetPoint("TOPRIGHT", -36, -12)
    title:SetWordWrap(true)
    detail.title = title

    -- Rows start under the icon or the title, whichever is lower, back at
    -- the pane's left edge.
    local titleBlock = CreateFrame("Frame", nil, detail)
    titleBlock:SetPoint("TOPLEFT", 12, -12)
    titleBlock:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    titleBlock:SetHeight(30)
    detail.titleBlock = titleBlock

    local rowsAnchor = titleBlock

    detail.values = {}

    local function AddRow(key, labelText)
        local label = Theme.CreateLabel(detail, "small", "muted")
        label:SetPoint("TOPLEFT", rowsAnchor, "BOTTOMLEFT", 0, -8)

        local value = Theme.CreateLabel(detail, "small", "text", "RIGHT")
        value:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, 0)
        value:SetPoint("TOP", label, "TOP", 0, 0)

        label:SetText(labelText)

        detail.values[key] = value
        detail.labels = detail.labels or {}
        detail.labels[key] = label
        rowsAnchor = label
        return value
    end

    AddRow("market", "Market value")
    AddRow("min", "Cheapest listing")
    AddRow("rival", "Cheapest rival")
    AddRow("own", "Your listing")
    AddRow("quantity", "Listed quantity")
    AddRow("scans", "Times scanned")
    AddRow("confidence", "Confidence")
    AddRow("liquidity", "Stock movement")

    BuildMyPrice(detail, rowsAnchor)

    -- The price graph: the cheapest price hour by hour, 24 hours or 7 days,
    -- and when in the day it is cheapest and dearest. It runs down to the
    -- buttons, so it gets whatever room the rows above leave.
    if ns.PriceGraph then
        local graph = ns.PriceGraph.Create(detail, { heading = "PRICE HISTORY" })
        graph:SetPoint("TOPLEFT", detail.myPrice.status, "BOTTOMLEFT", 0, -12)
        graph:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -12, 14 + 24 + 8)
        detail.graph = graph
    end

    -- Actions
    detail.deepScan = Widgets.CreateButton(detail, "Deep scan", function()
        if not state.selected then return end

        local itemID = state.selected.itemID
        ns.Print(("scanning %s..."):format(Util.GetItemLabel(itemID)))

        ns.Scanner:ScanItem(itemID, function()
            UI:RefreshActiveTab()
        end)
    end, { width = 110, height = 24, primary = true,
           tooltip = "Read every listing of this item from the auction house" })
    detail.deepScan:SetPoint("BOTTOMLEFT", 12, 14)

    detail.searchAH = Widgets.CreateButton(detail, "Search AH", function()
        if not state.selected then return end
        UI:SearchAuctionHouse(state.selected.itemID)
    end, { width = 110, height = 24, tooltip = "Search the auction house for this item" })
    detail.searchAH:SetPoint("LEFT", detail.deepScan, "RIGHT", 8, 0)

    local empty = Theme.CreateLabel(detail, "small", "dim", "CENTER")
    empty:SetPoint("CENTER")
    empty:SetWidth(240)
    empty:SetWordWrap(true)
    empty:SetText("Select an item to see its price history")
    detail.empty = empty

    return detail
end

local function UpdateDetail(entry)
    local detail = widgets.detail
    local shown = entry ~= nil

    detail.empty:SetShown(not shown)
    detail.title:SetShown(shown)
    detail.icon:SetShown(shown)
    local graph = rawget(detail, "graph")
    if type(graph) == "table" then graph:SetShown(shown) end
    detail.deepScan:SetShown(shown)
    detail.searchAH:SetShown(shown)
    detail.star:SetShown(shown)

    for _, value in pairs(detail.values) do
        value:SetShown(shown)
    end

    -- The labels go with their values: left up with nothing selected, they
    -- stood around the "Select an item" line saying nothing.
    for _, label in pairs(detail.labels or {}) do
        label:SetShown(shown)
    end
    detail.myPrice:SetShown(shown)

    if not shown then
        return
    end

    local record = ns.Prices:Get(entry.itemID) or entry.record

    detail.title:SetText(Util.GetItemLabel(entry.itemID))
    Theme.SetItemIcon(detail.icon, entry.itemID)
    detail.star:SetItem(entry.itemID)
    detail.myPrice:Show(entry.itemID)

    -- A name that wraps to two lines pushes the rows down with it.
    local titleHeight = detail.title.GetStringHeight and detail.title:GetStringHeight() or 0
    detail.titleBlock:SetHeight(math.max(30, tonumber(titleHeight) or 0))

    detail.values.market:SetText(Util.FormatMoney(record.market))
    -- Worded like the Cheapest rival line when there is nothing listed.
    if record.min then
        detail.values.min:SetText(Util.FormatMoney(record.min))
        detail.values.min:SetTextColor(Theme.Unpack("text"))
    else
        detail.values.min:SetText("none listed")
        detail.values.min:SetTextColor(Theme.Unpack("dim"))
    end

    if record.rivalMin then
        detail.values.rival:SetText(Util.FormatMoney(record.rivalMin))
        detail.values.rival:SetTextColor(Theme.Unpack("text"))
    else
        detail.values.rival:SetText("none listed")
        detail.values.rival:SetTextColor(Theme.Unpack("dim"))
    end

    if record.ownMin then
        detail.values.own:SetText(Util.FormatMoney(record.ownMin))
        detail.values.own:SetTextColor(Theme.Unpack(
            ns.Prices:HoldsLowest(entry.itemID) and "profit" or "loss"))
    else
        detail.values.own:SetText("none")
        detail.values.own:SetTextColor(Theme.Unpack("dim"))
    end

    detail.values.quantity:SetText(Util.Comma(record.quantity or 0))
    detail.values.scans:SetText(tostring(record.scans or 0))

    local confidence, reason = ns.Prices:GetConfidence(entry.itemID)
    -- No reason means nothing is holding the number down, so nothing is named.
    detail.values.confidence:SetText(("%d%%%s"):format(math.floor(confidence * 100),
        reason and ("  (" .. reason .. ")") or ""))
    detail.values.confidence:SetTextColor(Theme.Unpack(confidence > 0.6 and "profit" or "warn"))

    local liquidity = ns.Prices:GetLiquidity(entry.itemID)
    if liquidity then
        detail.values.liquidity:SetText(("%d%% per scan"):format(math.floor(liquidity * 100)))
        detail.values.liquidity:SetTextColor(Theme.Unpack("text"))
    else
        detail.values.liquidity:SetText("not enough scans")
        detail.values.liquidity:SetTextColor(Theme.Unpack("dim"))
    end

    detail.deepScan:SetEnabledState(ns.Scanner.isAuctionHouseOpen)
    detail.deepScan.tooltipText = ns.Scanner.isAuctionHouseOpen
        and "Read every listing of this item from the auction house"
        or "The auction house must be open"

    if type(graph) == "table" then graph:SetItem(entry.itemID) end
end

--- The list a search would show, for the tests.
function UI._PricesList(search, favouritesOnly, mineOnly)
    state.search = search or ""
    state.favouritesOnly = favouritesOnly and true or false
    state.mineOnly = mineOnly and true or false
    return BuildList()
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

function Refresh()
    if not widgets.list then return end

    local data = BuildList()
    widgets.list:SetData(data)

    widgets.emptyLabel:SetShown(#data == 0)
    local starred = ns.Prices.GetFavourites and Util.Count(ns.Prices:GetFavourites()) or 0

    if #data == 0 then
        if state.favouritesOnly and starred == 0 then
            widgets.emptyLabel:SetText("No favourites yet. Click the star beside an item to keep it here.")
        elseif state.mineOnly and not next(ns.Prices.GetAllMine and ns.Prices:GetAllMine() or {}) then
            widgets.emptyLabel:SetText("No prices of your own yet. Pick an item and type one under My price.")
        else
            widgets.emptyLabel:SetText(ns.Prices:Count() == 0
                and "No auction data yet. Open the auction house and press Scan."
                or "Nothing matches these filters.")
        end
    end

    widgets.countLabel:SetText(("%s item%s priced%s"):format(
        Util.Comma(#data), #data == 1 and "" or "s",
        starred > 0 and (", %d starred"):format(starred) or ""))

    UpdateDetail(state.selected)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function Build(container)
    local toolbar = CreateFrame("Frame", nil, container)
    toolbar:SetPoint("TOPLEFT", 8, -8)
    toolbar:SetPoint("TOPRIGHT", -8, -8)
    toolbar:SetHeight(24)

    -- A new search, filter or sort is a different list, so it starts at the
    -- top. The list keeps its place on the redraws that bag and auction
    -- events cause, which left a new search showing its results part way
    -- down, with the best of them above the view.
    local function ShowFromTop()
        Refresh()
        if widgets.list then widgets.list:ScrollToTop() end
    end

    local search = Widgets.CreateSearchBox(toolbar, "Search items", function(text)
        state.search = text or ""
        ShowFromTop()
    end)
    search:SetPoint("LEFT", 0, 0)
    search:SetWidth(Widgets.SEARCH_WIDTH)

    local reagentsOnly = Widgets.CreateCheckbox(toolbar, "Only what I craft with", function(checked)
        state.reagentsOnly = checked
        ShowFromTop()
    end, false)
    reagentsOnly:SetPoint("LEFT", search, "RIGHT", 12, 0)

    -- Only the starred items (Voldar, 2026-10-06). Remembered, so the tab
    -- opens on the watch list for whoever keeps one.
    state.favouritesOnly = ns.Config:Get("pricesFavouritesOnly") == true
    local favouritesOnly = Widgets.CreateCheckbox(toolbar, "Favourites only", function(checked)
        state.favouritesOnly = checked
        ns.Config:Set("pricesFavouritesOnly", checked)
        ShowFromTop()
    end, state.favouritesOnly)
    favouritesOnly:SetPoint("LEFT", reagentsOnly, "RIGHT", 12, 0)

    -- Only the items given their own price (Ponyboy, 2026-10-06).
    local mineOnly = Widgets.CreateCheckbox(toolbar, "My prices only", function(checked)
        state.mineOnly = checked
        ShowFromTop()
    end, false)
    mineOnly:SetPoint("LEFT", favouritesOnly, "RIGHT", 12, 0)

    -- No sort menu: the headings sort (Ezmode, 2026-10-06). The list opens
    -- by market value.

    -- Column headings
    local headings = CreateFrame("Frame", nil, container)
    headings:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -DETAIL_WIDTH - 8, -8)
    headings:SetHeight(16)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "muted")
    nameHeading:SetPoint("LEFT", 46, 0)
    nameHeading:SetText("ITEM")

    local sortLabels = { name = nameHeading }
    local offset = -8
    for _, column in ipairs(COLUMNS) do
        local heading = Theme.CreateLabel(headings, "tiny", "muted", "RIGHT")
        heading:SetPoint("RIGHT", offset, 0)
        heading:SetWidth(column.width)
        heading:SetText(column.label)
        sortLabels[column.key] = heading
        offset = offset - column.width - 6
    end

    -- Click a heading to sort by it. Unknown ages sort as unknown, not as
    -- the oldest.
    local function Field(key) return function(row) return row[key] end end
    widgets.sorter = Widgets.SortableHeadings and Widgets.SortableHeadings(sortLabels, {
        name = Field("name"), market = Field("market"), min = Field("min"),
        quantity = Field("quantity"), liquidity = Field("liquidity"),
        age = function(row) return row.age ~= math.huge and row.age or nil end,
    }, function() ShowFromTop() end)
    if widgets.sorter then widgets.sorter:SetText({ "name" }) end

    local divider = Theme.CreateDivider(container, "borderLit")
    divider:SetPoint("TOPLEFT", headings, "BOTTOMLEFT", 0, -2)
    divider:SetPoint("TOPRIGHT", headings, "BOTTOMRIGHT", 0, -2)

    local list = Widgets.CreateScrollList(container, {
        -- The headings move in with the rows when the scrollbar takes its room.
        onScrollbarShown = function(shown)
            headings:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", -DETAIL_WIDTH - 8 - (shown and 10 or 0), -8)
        end,
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onEnter = function(row, entry) Widgets.ShowItemOnly(row, entry.itemID, entry.label) end,
        onLeave = function() GameTooltip:Hide() end,
        -- The row the detail pane is showing stays lit.
        isSelected = function(entry)
            return state.selected ~= nil and entry.itemID == state.selected.itemID
        end,

        onClick = function(entry)
            state.selected = entry
            UpdateDetail(entry)
        end,
    })
    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 24)
    widgets.list = list

    local emptyLabel = Theme.CreateLabel(container, "small", "dim", "CENTER")
    emptyLabel:SetPoint("CENTER", list, "CENTER")
    emptyLabel:SetWidth(320)
    emptyLabel:SetWordWrap(true)
    widgets.emptyLabel = emptyLabel

    local countLabel = Theme.CreateLabel(container, "tiny", "dim")
    countLabel:SetPoint("BOTTOMLEFT", 8, 8)
    widgets.countLabel = countLabel

    local detail = BuildDetail(container)
    detail:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -40)
    detail:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 8)
    widgets.detail = detail

    UpdateDetail(nil)
end

UI:RegisterTab({
    key = "prices",
    text = "Prices",
    order = 5,
    build = Build,
    refresh = Refresh,
})
