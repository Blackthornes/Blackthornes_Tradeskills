-- Blackthornes Tradeskills -- UI/Tab_Today.lua
-- The Today tab (the owner said build it, 2026-11-26, from a mockup): four
-- cards along the top (Gold Today, Up For Sale, Sold Today, Prices Read),
-- then Do Next, a dark glass list of what is worth doing right now, each
-- line with one gold button. Logic/Today.lua finds the lines; this draws
-- them.
--
-- Smooth: the lines are found when the tab shows and when a fact the
-- window already hears about changes (sales, bags, auctions, scans). Rows
-- whose line did not change keep what they drew. Nothing runs on a timer;
-- the Profit ranking runs a few recipes a frame and draws once when done.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })
local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local CARD_HEIGHT, CARD_GAP = 52, 8
local ROW_HEIGHT = 40
local ICON_SIZE = 26
local PAD = 10

local widgets = {}
local shownKeys      -- the lines' keys as last drawn, joined

local function Money(copper, signed)
    if type(copper) ~= "number" then return "" end
    if signed and ns.CraftProfit and ns.CraftProfit.SignedMoney then
        return ns.CraftProfit.SignedMoney(copper)
    end
    return Util.FormatMoney(copper)
end

--------------------------------------------------------------------------------
-- Cards
--------------------------------------------------------------------------------

local CARD_LABELS = { L["Gold Today:"], L["Up For Sale:"], L["Sold Today:"], L["Prices Read:"] }

local function BuildCards(container)
    local cards = CreateFrame("Frame", nil, container)
    cards:SetPoint("TOPLEFT", PAD, -PAD)
    cards:SetPoint("TOPRIGHT", -PAD, -PAD)
    cards:SetHeight(CARD_HEIGHT)
    cards.items = {}
    for index, text in ipairs(CARD_LABELS) do
        local card = Theme.CreatePanel(cards, "glassAlt")
        card:SetHeight(CARD_HEIGHT)
        Theme.AccentStripe(card, 3)
        card.label = Theme.CreateLabel(card, "tiny", "accent")
        card.label:SetPoint("TOPLEFT", 12, -8)
        card.label:SetPoint("RIGHT", card, "RIGHT", -6, 0)
        card.label:SetText(text)
        card.value = Theme.CreateLabel(card, "large", "text")
        card.value:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -6)
        card.value:SetPoint("RIGHT", card, "RIGHT", -6, 0)
        cards.items[index] = card
    end
    local function Place()
        local width = cards:GetWidth() or 0
        if width <= 0 then return end
        local each = (width - 3 * CARD_GAP) / 4
        for index, card in ipairs(cards.items) do
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", cards, "TOPLEFT", (index - 1) * (each + CARD_GAP), 0)
            card:SetWidth(each)
        end
    end
    cards:SetScript("OnSizeChanged", Place)
    Place()
    widgets.cards = cards
    return cards
end

local function PaintCards()
    local items = widgets.cards and widgets.cards.items
    if not items then return end
    local cards = ns.Today:Cards()

    items[1].value:SetText(cards.goldToday and Money(cards.goldToday, true) or Util.FormatMoney(nil))

    if cards.upCount then
        local text = tostring(cards.upCount)
        if cards.upCount > 0 then
            text = text .. "  |c" .. ns.COLORS.muted .. L.Format("worth %s", Util.FormatMoney(cards.upWorth)) .. "|r"
        end
        items[2].value:SetText(text)
    else
        items[2].value:SetText(Util.FormatMoney(nil))
    end

    items[3].value:SetText(tostring(cards.soldToday or 0))

    local at = cards.pricesAt
    items[4].value:SetText(at and Util.FormatAgeAgo(time() - at) or L["never"])
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

local function ButtonWidth(lines)
    local width = 90
    for _, line in ipairs(lines) do
        local ok, w = pcall(Theme.MeasureText, "small", line.button or "")
        if ok and type(w) == "number" then width = math.max(width, math.ceil(w) + 24) end
    end
    return width
end

local function CreateRow(row)
    row.iconFrame = Theme.CreatePanel(row, "well", "border")
    row.iconFrame:SetSize(ICON_SIZE + 4, ICON_SIZE + 4)
    row.iconFrame:SetPoint("LEFT", 8, 0)
    row.icon = Theme.CreateItemIcon(row.iconFrame, ICON_SIZE)
    row.icon:SetPoint("CENTER")

    row.button = Widgets.CreateButton(row, "", function(self)
        local line = self:GetParent().data
        if line and ns.Today:Run(line) then UI:RefreshActiveTab() end
    end, { primary = true, height = 24 })
    row.button:SetPoint("RIGHT", -8, 0)

    row.amount = Theme.CreateLabel(row, "normal", "text", "RIGHT")
    row.amount:SetPoint("RIGHT", row.button, "LEFT", -10, 0)

    row.detail = Theme.CreateLabel(row, "small", "muted", "RIGHT")
    row.detail:SetPoint("RIGHT", row.amount, "LEFT", -10, 0)
    row.detail:SetWidth(150)
    row.detail:SetWordWrap(true)

    row.text = Theme.CreateLabel(row, "normal", "text")
    row.text:SetPoint("LEFT", row.iconFrame, "RIGHT", 10, 0)
    row.text:SetPoint("RIGHT", row.detail, "LEFT", -10, 0)
    row.text:SetWordWrap(true)
end

local function UpdateRow(row, line)
    -- A line that did not change keeps what it drew.
    if row.drawnKey == line.key and row.drawnWidth == widgets.buttonWidth then return end
    row.drawnKey, row.drawnWidth = line.key, widgets.buttonWidth

    Theme.SetItemIcon(row.icon, line.itemID, line.link)
    row.text:SetText(line.text or "")

    local amount = ""
    if line.money then
        amount = Money(line.money, line.signed)
        if line.moneyFormat then amount = line.moneyFormat:format(amount) end
    end
    row.amount:SetText(amount)

    row.detail:SetText(line.detail or "")
    row.detail:SetShown(line.detail ~= nil)

    row.button:SetText(line.button or "")
    row.button:SetWidth(widgets.buttonWidth or 90)
end

local function ShowTip(row, line)
    if not (GameTooltip and line and line.itemID) then return end
    Widgets.ShowItemTooltip(row, "ANCHOR_RIGHT", line.itemID, nil, line.link)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Draw
--------------------------------------------------------------------------------

local Refresh

local function Draw(lines)
    local keys = {}
    for index, line in ipairs(lines) do keys[index] = line.key end
    local joined = table.concat(keys, ";")
    local empty = #lines == 0
    widgets.list:SetShown(not empty)
    widgets.heading:SetShown(not empty)
    widgets.note:SetShown(not empty)
    widgets.empty:SetShown(empty)
    if joined == shownKeys then return end
    shownKeys = joined
    local width = ButtonWidth(lines)
    if width ~= widgets.buttonWidth then widgets.buttonWidth = width end
    widgets.list:SetData(lines)
end

local function OnReady()
    if widgets.container and widgets.container:IsVisible() then Refresh() end
end

function Refresh()
    if not widgets.container then return end
    PaintCards()
    Draw(ns.Today:Lines(OnReady))
end

local function Build(container)
    widgets.container = container
    local cards = BuildCards(container)

    local heading = Theme.CreateHeading(container, L["Do Next"], "small")
    heading:SetPoint("TOPLEFT", cards, "BOTTOMLEFT", 2, -14)
    widgets.heading = heading

    local note = Theme.CreateLabel(container, "small", "muted")
    note:SetPoint("BOTTOMLEFT", PAD, PAD)
    note:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    note:SetWordWrap(true)
    note:SetText(L["Each line goes away once it is done. Lines you never want can be turned off in Settings."])
    widgets.note = note

    local list = Widgets.CreateScrollList(container, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onEnter = ShowTip,
        onLeave = function() if GameTooltip then GameTooltip:Hide() end end,
    })
    list:SetPoint("TOPLEFT", cards, "BOTTOMLEFT", 0, -36)
    list:SetPoint("RIGHT", container, "RIGHT", -PAD, 0)
    list:SetPoint("BOTTOM", note, "TOP", 0, 8)
    widgets.list = list

    -- Nothing left to do: one quiet panel under the cards.
    local empty = Theme.CreatePanel(container, "glassAlt", "border")
    empty:SetPoint("TOPLEFT", cards, "BOTTOMLEFT", 0, -12)
    empty:SetPoint("RIGHT", container, "RIGHT", -PAD, 0)
    empty:SetHeight(96)
    empty.title = Theme.CreateLabel(empty, "large", "accentHi", "CENTER")
    empty.title:SetPoint("TOP", 0, -28)
    empty.title:SetText(L["You are all caught up."])
    empty.sub = Theme.CreateLabel(empty, "normal", "dim", "CENTER")
    empty.sub:SetPoint("TOP", empty.title, "BOTTOM", 0, -6)
    empty.sub:SetText(L["New things to do show up here as they come."])
    empty:Hide()
    widgets.empty = empty
end

local function OnShow()
    -- A fresh look each time the tab is picked.
    shownKeys = nil
end

UI:RegisterTab({
    key = "today",
    text = L["Today"],
    order = 0,
    build = Build,
    refresh = function() Refresh() end,
    onShow = OnShow,
})

-- For the tests.
UI._TodayWidgets = widgets
