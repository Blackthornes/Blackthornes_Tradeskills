local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

-- The Snipe view inside the auction house drawer. Logic/Snipe.lua does the
-- work; this file shows the settings strip, the finds and the Start button.
local SnipeView = ns.NewModule("SnipeView")
local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local ROW_HEIGHT = 36
local ICON_SIZE = 24
local STRIP_HEIGHT = 84
local HEAD_HEIGHT = 18
local COLUMNS_HEIGHT = 16
-- Average, Price and Under Average sit in cells laid out from the right, so
-- their headings line up over them and never overlap.
local CELL_WIDTH = 68
local CELL_GAP = 4
local RIGHT_PAD = 8
local SORT_ARROW = [[Interface\AddOns\]] .. (ns.ADDON_NAME or "Blackthornes_TS") .. [[\Media\Frame\SortArrow]]

-- Right edge of cell n (1 = Under Average, 2 = Price, 3 = Average).
local function CellRight(n)
    return -(RIGHT_PAD + (n - 1) * (CELL_WIDTH + CELL_GAP))
end
local NAME_RIGHT = CellRight(3) - CELL_WIDTH - 6

SnipeView.sortKey = "deal"
SnipeView.sortDown = true

local function Config(key, default)
    local value = ns.Config and ns.Config:Get(key)
    if value == nil then return default end
    return value
end

local function Money(copper)
    return Util.FormatMoney(copper or 0, { noColor = true, short = true })
end

local function Colored(copper)
    return Util.FormatMoney(copper or 0, { short = true })
end

local function Snipe() return ns.Snipe end

local function ItemName(itemID)
    local label = Util.GetItemLabel and Util.GetItemLabel(itemID)
    return label or L["that item"]
end

function SnipeView:Changed()
    self.key = nil
    if ns.PostPanel and ns.PostPanel.Refresh then ns.PostPanel:Refresh() end
end

--------------------------------------------------------------------------------
-- Finds, sorted for showing only
--------------------------------------------------------------------------------

local function DealOf(find)
    -- A vendor find is ranked by its profit, the others by how far under.
    if find.kind == "vendor" then return Snipe().Profit(find) end
    return Snipe().Deal(find.price, find.worth) or 0
end

local function Vendoring()
    return Snipe():Watch() == "vendor"
end

function SnipeView:SortedFinds()
    local rows = {}
    for _, find in ipairs(Snipe():Finds() or {}) do rows[#rows + 1] = find end
    local key, down = self.sortKey, self.sortDown
    table.sort(rows, function(a, b)
        local x, y
        if key == "price" then x, y = a.price or 0, b.price or 0
        elseif key == "average" then x, y = a.worth or 0, b.worth or 0
        elseif key == "name" then x, y = ItemName(a.itemID), ItemName(b.itemID)
        else x, y = DealOf(a), DealOf(b) end
        if x == y then return (a.itemID or 0) < (b.itemID or 0) end
        if down then return x > y end
        return x < y
    end)
    return rows
end

function SnipeView:SortBy(key)
    if self.sortKey == key then
        self.sortDown = not self.sortDown
    else
        self.sortKey, self.sortDown = key, (key ~= "name")
    end
    self:Changed()
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function CreateRow(row)
    row.icon = Theme.CreateItemIcon(row, ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", row, "LEFT", 8 + ICON_SIZE + 8, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", NAME_RIGHT, 0)
    row.name:SetWordWrap(true)
    row.edge = Theme.AccentStripe(row, 3)
    row.edge:Hide()
    local function Cell(n, size)
        local cell = Theme.CreateLabel(row, size or "small", "text", "RIGHT")
        cell:SetPoint("RIGHT", row, "RIGHT", CellRight(n), 0)
        cell:SetWidth(CELL_WIDTH)
        cell:SetWordWrap(false)
        return cell
    end
    row.badge = Cell(1, "tiny")
    row.price = Cell(2)
    row.average = Cell(3)
    row.qty = Theme.CreateLabel(row, "tiny", "muted", "RIGHT")
    row.qty:SetPoint("TOPRIGHT", row.price, "BOTTOMRIGHT", 0, -1)
end

local function IsPending(find)
    local pending = Snipe().pending
    return pending and pending.find == find
end

local function UpdateRow(row, find)
    if not find then return end
    -- Price and deal first, so a find always shows what it costs even when
    -- its name is still loading.
    row.price:SetText(Colored(find.price))
    row.average:SetText(Colored(find.worth))
    local qty = find.qty or 1
    row.qty:SetText(qty > 1 and ("x" .. qty) or "")

    local pending = Snipe().pending
    local busy = IsPending(find)
    row.price:SetShown(not busy)
    row.average:SetShown(not busy)
    row.qty:SetShown(not busy)
    row.badge:ClearAllPoints()
    row.badge:SetPoint("RIGHT", row, "RIGHT", CellRight(1), 0)
    row.badge:SetWidth(busy and (CELL_WIDTH * 3 + CELL_GAP * 2) or CELL_WIDTH)
    if busy then
        if Snipe().armed == pending then
            row.badge:SetText(L["Click Again"])
        elseif pending.phase == "quoted" then
            row.badge:SetText(L.Format("Pay %s", Money(pending.total)))
        else
            row.badge:SetText(L["Asking..."])
        end
        row.badge:SetTextColor(Theme.Unpack("accent"))
        row.edge:Show()
    else
        if find.kind == "vendor" then
            row.badge:SetText(Money(Snipe().Profit(find)))
        else
            row.badge:SetText(L.Format("%d%% under", DealOf(find)))
        end
        row.badge:SetTextColor(Theme.Unpack("profit"))
        row.edge:Hide()
    end

    Theme.SetItemIcon(row.icon, find.itemID)
    local label = ItemName(find.itemID)
    if Theme.SetRowName then Theme.SetRowName(row.name, label) else row.name:SetText(label) end
    local r, g, b
    if Util.GetItemQualityColor then r, g, b = Util.GetItemQualityColor(find.itemID) end
    if not (r and g and b) then r, g, b = Theme.Unpack("text") end
    row.name:SetTextColor(r, g, b)
end

local function ShowTooltip(row, find)
    if find and Widgets.ShowItemTooltip then
        Widgets.ShowItemTooltip(row, "ANCHOR_LEFT", find.itemID)
        if find.kind == "vendor" then
            GameTooltip:AddLine(L.Format("%1$s each, a vendor pays %2$s", Colored(find.price), Colored(find.worth)), 1, 1, 1, true)
            GameTooltip:Show()
        end
    end
end

local function ClickRow(find, _, mouseButton)
    if mouseButton == "RightButton" then return end
    local snipe = Snipe()
    if not (snipe:IsRunning() and find) then return end
    local pending = snipe.pending
    if pending then
        if pending.find == find and pending.phase == "quoted" then snipe:Pay() end
    else
        snipe:Buy(find)
    end
end

--------------------------------------------------------------------------------
-- Settings strip
--------------------------------------------------------------------------------

local function Lock(money, locked)
    for _, box in ipairs(money.boxes or {}) do
        if box.editBox then
            box.editBox:EnableMouse(not locked)
            if locked then box.editBox:ClearFocus() end
        end
        box:SetAlpha(locked and 0.5 or 1)
    end
end

function SnipeView:BuildStrip(body, topAnchor)
    local head = CreateFrame("Button", nil, body)
    head:SetHeight(HEAD_HEIGHT)
    head:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -4)
    head:SetPoint("TOPRIGHT", topAnchor, "BOTTOMRIGHT", 0, -4)
    head.text = Theme.CreateLabel(head, "tiny", "accent")
    head.text:SetPoint("LEFT", head, "LEFT", 8, 0)
    head:SetScript("OnClick", function()
        ns.Config:Set("snipeStripOpen", not self:StripOpen())
        self:Place()
        self:Changed()
    end)
    self.head = head

    local strip = CreateFrame("Frame", nil, body)
    strip:SetHeight(STRIP_HEIGHT)
    strip:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, 0)
    self.strip = strip

    local function Row(y, text)
        local label = Theme.CreateLabel(strip, "small", "text")
        label:SetPoint("TOPLEFT", strip, "TOPLEFT", 8, y)
        label:SetText(text)
        return label
    end

    -- Spending Cap
    local capLabel = Row(-4, L["Spending Cap:"])
    local money = ns.PriceEditor.MoneyBoxes(strip, function(copper)
        ns.Config:Set("snipeCap", math.max(0, copper or 0))
        self:Changed()
    end)
    money:SetPoint("LEFT", capLabel, "RIGHT", 10, 0)
    money:Set(Snipe():Cap())
    self.cap = money

    -- Snipe Below
    local belowLabel = Row(-30, L["Snipe Below:"])
    local pct = Widgets.CreateNumberBox(strip, {
        width = 40, height = 20, min = 10, max = 95,
        onChange = function(value)
            if type(value) == "number" then
                ns.Config:Set("snipePct", math.max(10, math.min(95, math.floor(value))))
                self:Changed()
            end
        end,
    })
    pct:SetPoint("LEFT", belowLabel, "RIGHT", 10, 0)
    pct:SetValue(Snipe():Percent(), true)
    self.pct = pct
    local sign = Theme.CreateLabel(strip, "small", "muted")
    sign:SetPoint("LEFT", pct, "RIGHT", 4, 0)
    sign:SetText(L["% of worth"])

    -- Watch
    local watchLabel = Row(-56, L["Watch:"])
    local options = {
        { value = "priced", text = L["Priced Items"] },
        { value = "disenchant", text = L["To Disenchant"] },
        { value = "vendor", text = L["Below Vendor"] },
    }
    local watch = Widgets.CreateDropdown(strip, options, function(value)
        ns.Config:Set("snipeWatch", value)
        if Snipe().BuildPool and not Snipe():IsRunning() then Snipe().pool = nil end
        self:Changed()
    end, { width = 140 })
    watch:SetPoint("LEFT", watchLabel, "RIGHT", 10, 0)
    watch:SetValue(Snipe():Watch())
    self.watch = watch

    local sound = Widgets.CreateCheckbox(strip, L["Snipe Sound"], function(on)
        ns.Config:Set("snipeSound", on and true or false)
    end, Config("snipeSound", true) ~= false)
    sound:SetPoint("LEFT", watch, "RIGHT", 16, 0)
    self.sound = sound

    -- Column heads
    local cols = CreateFrame("Frame", nil, body)
    cols:SetHeight(COLUMNS_HEIGHT)
    self.cols = cols
    -- The list sits 14 in from the right for its scroll bar; the heads match.
    local function Head(key, text, cell)
        local button = CreateFrame("Button", nil, cols)
        button:SetHeight(COLUMNS_HEIGHT)
        local justify = cell and "RIGHT" or "LEFT"
        local label = Theme.CreateLabel(button, "tiny", "muted", justify)
        label:SetAllPoints(button)
        label:SetWordWrap(false)
        local arrow = button:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture(SORT_ARROW)
        arrow:SetSize(8, 8)
        arrow:SetVertexColor(Theme.Unpack("accent"))
        arrow:Hide()
        button.label, button.arrow, button.key, button.text, button.cell = label, arrow, key, text, cell
        if cell then
            button:SetWidth(CELL_WIDTH)
            button:SetPoint("RIGHT", cols, "RIGHT", CellRight(cell) - 14, 0)
        else
            button:SetPoint("LEFT", cols, "LEFT", 8 + ICON_SIZE + 8, 0)
            button:SetPoint("RIGHT", cols, "RIGHT", NAME_RIGHT - 14, 0)
        end
        button:SetScript("OnClick", function() self:SortBy(key) end)
        return button
    end
    self.heads = {
        Head("name", L["Item"]),
        Head("average", L["Average"], 3),
        Head("price", L["Price"], 2),
        Head("deal", L["Under Average"], 1),
    }
end

function SnipeView:StripOpen()
    return Config("snipeStripOpen", true) ~= false
end

function SnipeView:Place()
    if not self.head then return end
    local open = self:StripOpen()
    self.strip:SetShown(open and self.shown)
    local anchor = open and self.strip or self.head
    self.cols:ClearAllPoints()
    self.cols:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    self.cols:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    if self.list then
        self.list:ClearAllPoints()
        self.list:SetPoint("TOPLEFT", self.cols, "BOTTOMLEFT", 0, -2)
        self.list:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -14, self.bottom or 49)
    end
end

--------------------------------------------------------------------------------
-- Built inside the drawer
--------------------------------------------------------------------------------

function SnipeView:Build(body, frame, topAnchor, opts)
    if self.list then return end
    opts = opts or {}
    self.frame, self.bottom = frame, opts.bottom

    self:BuildStrip(body, topAnchor)

    local list = Widgets.CreateScrollList(body, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onClick = ClickRow,
        onEnter = ShowTooltip,
        onLeave = function() GameTooltip:Hide() end,
    })
    self.list = list

    local pad = opts.edge or 11
    local footMiddle = pad + (opts.footHeight or 34) / 2

    local width = 110
    if Theme.MeasureText then
        for _, word in ipairs({ L["Start Sniping"], L["Stop"] }) do
            local ok, measured = pcall(Theme.MeasureText, "small", word)
            if ok and type(measured) == "number" then width = math.max(width, measured + 20) end
        end
    end
    local go = Widgets.CreateButton(body, L["Start Sniping"], function() SnipeView:Toggle() end,
        { width = width, height = 22, primary = true })
    go:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -(pad + 6), footMiddle)
    self.go = go

    local note = Theme.CreateLabel(body, "tiny", "muted")
    note:SetPoint("LEFT", frame, "BOTTOMLEFT", pad + 8, footMiddle)
    note:SetPoint("RIGHT", go, "LEFT", -8, 0)
    note:SetWordWrap(true)
    self.note = note

    local empty = Theme.CreateLabel(body, "small", "dim", "CENTER")
    empty:SetPoint("CENTER", list, "CENTER")
    empty:SetWidth(300)
    empty:SetWordWrap(true)
    self.empty = empty

    self.parts = { list = list, go = go, note = note, head = self.head, cols = self.cols }
    self:Place()
    self:SetShown(false)
end

function SnipeView:Toggle()
    local snipe = Snipe()
    if not snipe then return end
    if snipe:IsRunning() then snipe:Stop() else snipe:Start() end
    self:Changed()
end

function SnipeView:SetShown(on)
    self.shown = on and true or false
    for _, part in pairs(self.parts or {}) do part:SetShown(self.shown) end
    if self.empty and not self.shown then self.empty:Hide() end
    if self.strip then self.strip:SetShown(self.shown and self:StripOpen()) end
    if self.shown then self.key = nil end
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

function SnipeView:Refresh(force)
    if not (self.list and self.shown) then return end
    local snipe = Snipe()
    local running = snipe:IsRunning()
    local pending = snipe.pending
    local key = table.concat({
        tostring(snipe.version), tostring(running), tostring(snipe:Spent()), tostring(snipe:Cap()),
        tostring(self.sortKey), tostring(self.sortDown), tostring(self:StripOpen()), snipe:Watch(),
        pending and (pending.phase .. tostring(pending.total)) or "-", tostring(snipe.armed ~= nil),
    }, "|")
    if not force and key == self.key then return end
    self.key = key

    self.head.text:SetText((self:StripOpen() and "- " or "+ ") .. L["SNIPE SETTINGS"])
    for _, head in ipairs(self.heads) do
        local active = head.key == self.sortKey
        local text = head.text
        -- Below Vendor: the worth is what a vendor pays, the deal its profit.
        if Vendoring() then
            if head.key == "average" then text = L["Vendor"]
            elseif head.key == "deal" then text = L["Profit"] end
        end
        head.label:SetText(text)
        head.label:SetTextColor(Theme.Unpack(active and "accent" or "muted"))
        head.arrow:SetShown(active)
        if active then
            -- The house arrow points down for biggest first, flipped otherwise.
            if self.sortDown then head.arrow:SetTexCoord(0, 0.5625, 0, 1)
            else head.arrow:SetTexCoord(0, 0.5625, 1, 0) end
            head.arrow:ClearAllPoints()
            local width = Theme.TextWidth and Theme.TextWidth(head.label) or 0
            if type(width) ~= "number" then width = 0 end
            if head.cell then
                head.arrow:SetPoint("RIGHT", head.label, "RIGHT", -math.ceil(width) - 2, 0)
            else
                head.arrow:SetPoint("LEFT", head.label, "LEFT", math.ceil(width) + 2, 0)
            end
        end
    end
    Lock(self.cap, running)
    -- Snipe Below has no say in Below Vendor, so it greys out there.
    local fixed = running or Vendoring()
    self.pct.editBox:EnableMouse(not fixed)
    if fixed then self.pct.editBox:ClearFocus() end
    self.pct:SetAlpha(fixed and 0.5 or 1)

    local rows = self:SortedFinds()
    self.list:SetData(rows)
    if #rows == 0 then
        self.empty:SetText(running and L["Looking for deals..."]
            or L["Nothing to snipe yet. Scan the auction house first."])
        self.empty:Show()
    else
        self.empty:Hide()
    end

    self.note:SetText(self:Summary())
    self.go:SetText(running and L["Stop"] or L["Start Sniping"])
    self.go:SetEnabledState(true)
end

function SnipeView:Summary()
    local snipe = Snipe()
    if not snipe then return "" end
    if snipe:Cap() <= 0 and not snipe:IsRunning() then return L["Set a Spending Cap first."] end
    return L.Format("Spent: %1$s of %2$s", Money(snipe:Spent()), Money(snipe:Cap()))
end

-- The drawer's one-line summary and title.
function SnipeView:SummaryLine()
    local snipe = Snipe()
    if not snipe then return "" end
    local count = #(snipe:Finds() or {})
    return L.Format("%d finds", count)
end

function SnipeView:Title()
    return L["Snipe"]
end
