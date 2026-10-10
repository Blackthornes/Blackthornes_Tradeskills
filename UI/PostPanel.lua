-- Blackthornes Tradeskills -- UI/PostPanel.lua
-- The sell list, docked beside Blizzard's auction house.
--
-- Listing can work through a whole bag, so what is about to be sold needs to
-- be visible before the first click rather than discovered one confirmation
-- dialog at a time. This is that list: everything postable, its price, and a
-- button per row for selling just the one.
--
-- Deliberately beside the auction house rather than inside our own window:
-- the decision to sell is made while looking at the auction house, and a list
-- behind another frame may as well not exist.

local _, ns = ...

local PostPanel = ns.NewModule("PostPanel")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

-- Wider than it needs to be for the text alone: the amount to list sits beside
-- the button, and squeezing it in would have cost the item names their width.
local PANEL_WIDTH = 348
local ROW_HEIGHT = 30

local BUTTON_WIDTH = 46
local QUANTITY_WIDTH = 42

-- The red x that ignores an item, at the row's right end past List. A
-- symbol rather than the word: "Ignore" would have cost the item names their
-- room. Beside the amount box it read as "x 8", so it sits apart from it.
local IGNORE_WIDTH = 20

-- Right margin, ignore, gap, button, gap, quantity box, gap before the text.
local TEXT_INSET = 6 + IGNORE_WIDTH + 6 + BUTTON_WIDTH + 6 + QUANTITY_WIDTH + 10

-- Clear of the auction window's bevelled edge without opening a gap you could
-- see the world through.
local PANEL_GAP = 6

-- Only used when Blizzard's auction window cannot be found at all.
local PANEL_FALLBACK_HEIGHT = 420

-- Short enough to still show a few rows. Below this the panel stops giving
-- way to the main window: at that point there is no arrangement that fits,
-- and a panel squeezed to nothing is worse than one that overlaps.
local PANEL_MIN_HEIGHT = 200

-- Remembers whether the panel is folded down to its title (UI/Collapse.lua).
local COLLAPSE_KEY = "postPanelCollapsed"

-- The Sell and Buy switch under the title. Buy is the craft queue's shopping
-- list, the one beside the profession window (2026-10-01: "could we
-- have a shopping list also appear on the actual AH UI somewhere that's not
-- in the way?"). Sharing this panel puts it at the auction house without
-- taking any more of the screen.
local SWITCH_HEIGHT = 28
local SHOPPING_ROW_HEIGHT = 28

-- The shopping list walks the queue, the bags and every character's saved
-- counts, too much for the one-second ticker; at most this often instead.
local SHOPPING_REFRESH_SECONDS = 2

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- Declared early because typing in a row's quantity box redraws that one row.
-- Rebuilding the list instead would scroll it back to the top, and losing your
-- place every time you change a number is worse than the problem being solved.
local UpdateRow

--- Is the player part-way through typing a number into this box?
--
-- Guarded rather than called outright: this client has gaps in the frame API,
-- and a missing HasFocus would turn a redraw into an error.
local function BeingTyped(box)
    return box.editBox.HasFocus and box.editBox:HasFocus()
end

--- Is a LIST box anywhere in this list being typed into?
--
-- The list is redrawn every second at the auction house, sorted by value,
-- and rows are reused. Redrawn mid-number, the box being typed in could end
-- up on a different item, and the number went to that one when it was
-- entered. So the redraw waits until the typing is done.
local function TypingInList(list)
    for _, row in ipairs((list and list.rows) or {}) do
        if row.quantity and row:IsShown() and BeingTyped(row.quantity) then
            return true
        end
    end
    return false
end

--- Enter whatever is half-typed in a LIST box of this list, as Enter would.
--
-- Clicking a button does not take the keyboard from a box, so a number typed
-- and not yet entered was still waiting when List was clicked: the old
-- amount was listed, often the whole stack, with the new one on screen.
local function CommitTyping(list)
    for _, row in ipairs((list and list.rows) or {}) do
        if row.quantity and BeingTyped(row.quantity) then
            row.quantity.editBox:ClearFocus()
        end
    end
end

local function CreateRow(row)
    -- The item's icon at the start of the name line, as the bags draw it.
    row.icon = Theme.CreateItemIcon(row, 13)
    row.icon:SetPoint("TOPLEFT", 8, -3)

    -- Right edges tied to the row, which is narrower than the panel (the
    -- list is inset, and narrower again with the scrollbar). Widths taken
    -- from the panel ran the text under the quantity box and List button.
    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("TOPLEFT", 25, -4)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -TEXT_INSET, -4)

    row.detail = Theme.CreateLabel(row, "tiny", "muted")
    row.detail:SetPoint("TOPLEFT", 8, -17)
    row.detail:SetPoint("TOPRIGHT", row, "TOPRIGHT", -TEXT_INSET, -17)

    -- The price line is a field: click it to set your own price each, or a
    -- total (UI/PriceEditor.lua, asked 2026-10-08 to sell a bad buy under
    -- market). Drawn as a box with a gold edge that lights under the mouse,
    -- so it reads as something to click rather than plain text.
    local field = CreateFrame("Button", nil, row)
    field:SetPoint("TOPLEFT", row.detail, "TOPLEFT", -4, 2)
    field:SetHeight(14)
    field:SetWidth(60)
    Theme.Fill(field, "panel", 0.6)
    Theme.Border(field, "metal", 0.45)
    if Theme.Halo then Theme.Halo(field, 4, 0) end
    -- The text stays on top of the box.
    row.detail:SetParent(field)
    row.detail:SetDrawLayer("OVERLAY")
    field:SetScript("OnEnter", function(self)
        Theme.SetBorderColor(self, "accentHi")
        if rawget(self, "haloTextures") then Theme.SetHalo(self, 0.25) end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Set your own price", 1, 1, 1)
        GameTooltip:AddLine("Click to change the price each, or type a total and have it split over the stack. Handy for selling under market value.", 0.9, 0.9, 0.9, true)
        if row.data and row.data.priceBasis == "chosen" and row.data.suggestedPrice then
            GameTooltip:AddDoubleLine("Suggested",
                Util.FormatMoney(row.data.suggestedPrice, { noColor = true }), 0.7, 0.7, 0.7, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    field:SetScript("OnLeave", function(self)
        Theme.SetBorderColor(self, "metal", 0.45)
        if rawget(self, "haloTextures") then Theme.SetHalo(self, 0) end
        GameTooltip:Hide()
    end)
    field:SetScript("OnClick", function()
        CommitTyping(PostPanel.list)
        if row.data and ns.PriceEditor then ns.PriceEditor:Open(row.data, PostPanel.frame) end
    end)
    row.priceField = field

    row.post = Widgets.CreateButton(row, "List", function()
        CommitTyping(PostPanel.list)
        if not row.data then return end

        ns.Posting:Request(row.data.itemID, row.data.postQuantity, row.data.unitPrice)
    end, { width = BUTTON_WIDTH, height = 18, primary = true })
    row.post:SetPoint("RIGHT", -(6 + IGNORE_WIDTH + 6), 0)

    -- How many to list, beside the button that lists them. Empty-handed this
    -- panel posted whole stacks with no way to say otherwise.
    row.quantity = Widgets.CreateNumberBox(row, {
        width = QUANTITY_WIDTH,
        height = 18,
        background = "panel",
        min = 1,
        onChange = function(value)
            if not row.data then return end

            ns.Posting:ApplyQuantity(row.data, value)
            UpdateRow(row, row.data)
        end,
    })
    row.quantity:SetPoint("RIGHT", row.post, "LEFT", -6, 0)

    -- Takes the item off this list for good, on every character
    -- (2026-10-04). Settings lists what is ignored, with a Restore button for
    -- each, so a misclick is never for good.
    row.ignore = Widgets.CreateButton(row, "x", function()
        if not row.data then return end
        CommitTyping(PostPanel.list)

        -- By item, so every copy goes: a "Lead Band of the Wolf" ignores
        -- all Lead Bands, and Settings names it by the plain item name.
        local line = row.data
        ns.Posting:SetIgnored(line.itemID, true)
        ns.Print(("ignored %s: it no longer shows on Ready to sell. Restore it under Ignored items in Settings.")
            :format(line.label or "that item"))
    end, { width = IGNORE_WIDTH, height = 18, danger = true,
           tooltip = "Ignore this item: it stops showing on Ready to sell. Settings lists ignored items, each with a Restore button." })
    row.ignore:SetPoint("RIGHT", -6, 0)
end

--- What one of this item is worth disenchanted, for an enchanter.
--
-- Only for a character that knows Disenchant (or a client that will not
-- say), since to anyone else it is not a choice they have.
-- @return value, beatsSale  -- nil when it does not apply
local function DisenchantFor(line)
    if not ns.Disenchant or not ns.Disenchanter then return nil end
    if ns.Disenchanter:Knows() == false then return nil end

    local value = ns.Disenchant:GetValue(line.itemID)
    if not value then return nil end

    return value, line.unitPrice ~= nil and value > line.unitPrice
end

PostPanel._DisenchantFor = DisenchantFor
PostPanel._TypingInList = TypingInList

--- Whether a row's detail line runs past the room it has. False when it
--- cannot be measured, so nothing is shortened on a guess.
local function DetailTooWide(row)
    local label = row.detail
    -- Theme.TextWidth, because a label's own GetStringWidth can stop at the
    -- label's width, and then nothing is ever too wide.
    local width = Theme.TextWidth(label)
    if not width then return false end

    local room = label:GetWidth()
    if type(room) ~= "number" or room <= 0 then
        -- Not laid out yet: the room its anchors will give it.
        local rowWidth = row:GetWidth()
        room = type(rowWidth) == "number" and (rowWidth - 8 - TEXT_INSET) or nil
    end

    return room ~= nil and room > 0 and width > room
end

PostPanel._DetailTooWide = DetailTooWide

--- Why a line is a loss, in words the player can act on.
local function LossText(line)
    if line.lossReason == "vendor" then
        return "Below what a vendor would pay for it."
    end
    if line.lossReason == "crafted" then
        return "Below what you paid to make it, after the auction house's cut."
    end
    return "Below what the materials cost."
end

function UpdateRow(row, line)
    row.name:SetText(line.label)
    Theme.SetItemIcon(row.icon, line.itemID)

    local maxQuantity = line.maxQuantity or line.count or 1

    -- Not while it is being typed into: overwriting someone mid-number is how
    -- a field ends up refusing to accept what they meant.
    -- A reused row now showing another item drops the half-typed number,
    -- though: it was for the item that scrolled away, and pressing Enter
    -- would have set that many of this one. The Queue tab does the same.
    local typing = BeingTyped(row.quantity)
    if not typing or row.boundItemID ~= line.itemID then
        row.quantity:SetLimits(1, math.max(1, maxQuantity))
        row.quantity:SetValue(line.postQuantity or maxQuantity, true)
        if typing then row.quantity.editBox:ClearFocus() end
    end
    row.boundItemID = line.itemID

    -- Quantity and unit price on one line: together they are the decision,
    -- and a commodity posting 63 at once is worth noticing before clicking.
    -- Listing part of a stack says so, since "7 @ 6c" out of 20 in the bag
    -- reads the same as all of them otherwise.
    local each = ("%d%s @ %s"):format(
        line.postQuantity,
        line.postQuantity < maxQuantity and (" of " .. maxQuantity) or "",
        Util.FormatMoney(line.unitPrice, { noColor = true, short = true }))
    local total = "  =  " .. Util.FormatMoney(line.postTotal or 0, { noColor = true, short = true })

    -- Beside the price, so selling and disenchanting read against each
    -- other: green when disenchanting one is worth more than listing it.
    local disenchant, beats = DisenchantFor(line)
    local de = ""
    if disenchant then
        de = "   DE " .. Util.FormatMoney(disenchant, { noColor = true, short = true })
        if beats then de = ("|c%s%s|r"):format(ns.COLORS.profit, de) end
    end

    -- Measured, and shortened rather than cut off: with gold-sized prices
    -- the end of the line ran under the LIST box. The total goes first when
    -- disenchanting wins (that green is the point), the disenchant value
    -- first otherwise; the tooltip has both.
    row.detail:SetText(each .. total .. de)

    if DetailTooWide(row) then
        row.detail:SetText(beats and (each .. de) or (each .. total))
        if DetailTooWide(row) then row.detail:SetText(each) end
    end

    -- The field round the price line, as wide as its words.
    if row.priceField then
        local width = Theme.TextWidth(row.detail)
        local room = row.detail:GetWidth()
        if type(room) == "number" and room > 0 and width and width > room then width = room end
        row.priceField:SetWidth(math.max(40, (width or 60) + 8))
    end

    if line.atALoss then
        row.name:SetTextColor(Theme.Unpack("loss"))
        row.detail:SetTextColor(Theme.Unpack("loss"))
    else
        -- Rarity, the same as the Profit tab, so the two read alike.
        local r, g, b = Util.GetItemQualityColor(line.itemID)

        if r then
            row.name:SetTextColor(r, g, b)
        else
            row.name:SetTextColor(Theme.Unpack("text"))
        end

        -- A price of your own (the price editor) in gold, as the Prices
        -- tab draws "my price".
        row.detail:SetTextColor(Theme.Unpack(line.priceBasis == "chosen" and "accent" or "muted"))
    end

    row.post:SetEnabledState(line.unitPrice ~= nil)

    row.post.tooltipText = line.atALoss
        and LossText(line)
        or ("List %d of %d at %s each."):format(
            line.postQuantity, maxQuantity,
            Util.FormatMoney(line.unitPrice or 0, { noColor = true }))
end

--- The crafted cost lines (Logic/CraftedCost.lua) on the row's tooltip.
local function AddCraftedLines(line)
    if not ns.CraftedCost then return end
    for _, entry in ipairs(ns.CraftedCost:Lines(line.itemID, line.unitPrice)) do
        local r, g, b = 1, 1, 1
        if entry.color then r, g, b = Theme.Unpack(entry.color) end
        GameTooltip:AddDoubleLine(entry[1], entry[2], 0.7, 0.7, 0.7, r, g, b)
    end
end

local function ShowRowTooltip(row, line)
    ns.Widgets.ShowItemTooltip(row, "ANCHOR_LEFT", line.itemID, line.label)
    GameTooltip:AddLine(" ")

    GameTooltip:AddDoubleLine("In bags", tostring(line.count), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("Listing", ("%d of %d"):format(
        line.postQuantity, line.maxQuantity or line.count), 0.7, 0.7, 0.7, 1, 1, 1)

    if line.unitCost then
        GameTooltip:AddDoubleLine("Cost each",
            Util.FormatMoney(line.unitCost, { noColor = true }), 0.7, 0.7, 0.7, 1, 1, 1)
    end

    -- What it cost when it was made, what it last went up at, and what this
    -- listing makes over that cost (2026-10-05).
    AddCraftedLines(line)

    if line.vendorPrice then
        GameTooltip:AddDoubleLine("Vendor pays",
            Util.FormatMoney(line.vendorPrice, { noColor = true }), 0.7, 0.7, 0.7, 1, 1, 1)
    end

    local disenchant, beats = DisenchantFor(line)
    if disenchant then
        GameTooltip:AddDoubleLine("Disenchant value",
            Util.FormatMoney(disenchant, { noColor = true }), 0.7, 0.7, 0.7, 1, 1, 1)
        if beats then
            GameTooltip:AddLine(("Disenchanting it is worth %s more than listing it."):format(
                Util.FormatMoney(disenchant - line.unitPrice, { noColor = true })), 0.35, 0.85, 0.45, true)
        end
    end

    GameTooltip:AddLine(line.isCommodity
        and "Commodity: sells from every bag at once"
        or "Item auction: one stack at a time", 0.5, 0.5, 0.5)

    if line.priceBasis == "chosen" then
        GameTooltip:AddDoubleLine("Your price",
            Util.FormatMoney(line.unitPrice, { noColor = true }), 0.7, 0.7, 0.7, 0.78, 0.64, 0.30)
        if line.suggestedPrice then
            GameTooltip:AddDoubleLine("Suggested",
                Util.FormatMoney(line.suggestedPrice, { noColor = true }), 0.7, 0.7, 0.7, 1, 1, 1)
        end
    end

    GameTooltip:AddLine("Type in the box to list fewer than that.", 0.5, 0.5, 0.5)
    GameTooltip:AddLine("Click the price to set your own.", 0.5, 0.5, 0.5)

    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

function PostPanel:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesTSPostPanel", UIParent)
    frame:SetWidth(PANEL_WIDTH)
    frame:SetFrameStrata("HIGH")

    -- Opaque, so a click on a row cannot fall through to the auction window
    -- underneath, and raised on click: this panel shares its strata with the
    -- main window, and without this the two have a fixed order forever. That
    -- order put the sell list across the main window's tab row.
    frame:EnableMouse(true)
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:Hide()

    Theme.Fill(frame, "window")
    -- The house frame (UI/Titanforged.lua): the gold rim and corner gems.
    if ns.Titanforged then
        ns.Titanforged:Dress(frame)
    else
        Theme.AddGameOutline(frame, { style = "dialog", color = "natural" })
    end
    -- The house glow round its edge, flaring as it opens.
    Theme.Halo(frame, 8, 0.08)

    local header, title = ns.Collapse.CreateHeader(frame, "Ready to sell")
    self.title = title

    -- What everything listed here would fetch, in gold on the header, so it
    -- is still there to see with the panel folded away.
    local worth = Theme.CreateLabel(header, "small", "accent", "RIGHT")
    worth:SetPoint("RIGHT", header, "RIGHT", -10, 0)
    self.worth = worth

    -- Everything under the title, so the collapse button can fold it away in
    -- one go and leave the title strip showing.
    local body = CreateFrame("Frame", nil, frame)
    body:SetAllPoints(frame)
    self.body = body

    ns.Collapse.Attach(frame, {
        key = COLLAPSE_KEY,
        header = header,
        title = title,
        body = body,
        onToggle = function()
            PostPanel:ApplyHeight()
            PostPanel:Refresh()
        end,
    })

    local half = math.floor((PANEL_WIDTH - 28) / 2)
    local switch = Widgets.CreateTabStrip(body, {
        { key = "sell", text = "Sell", width = half },
        { key = "buy", text = "Buy", width = half },
    }, function(key)
        PostPanel:SetView(key)
    end)
    switch:SetPoint("TOPLEFT", 14, ns.Collapse.CONTENT_TOP)
    switch:Select(self.view)
    self.switch = switch

    local summary = Theme.CreateLabel(body, "tiny", "muted")
    summary:SetPoint("TOPLEFT", switch, "BOTTOMLEFT", 0, -6)
    summary:SetWidth(PANEL_WIDTH - 28)
    self.summary = summary

    local divider = Theme.CreateDivider(body)
    divider:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -6)
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, 0)

    local list = Widgets.CreateScrollList(body, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onEnter = ShowRowTooltip,
        onLeave = function() GameTooltip:Hide() end,
    })
    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    self.list = list

    local shopping = Widgets.CreateScrollList(body, {
        rowHeight = SHOPPING_ROW_HEIGHT,
        createRow = PostPanel.CreateShoppingRow,
        updateRow = PostPanel.UpdateShoppingRow,
        onEnter = PostPanel.ShowShoppingTooltip,
        onLeave = function() GameTooltip:Hide() end,
        onClick = function(line)
            if PostPanel:CanSearch(line) then ns.UI:SearchAuctionHouse(line.itemID, line.shortfall) end
        end,
    })
    shopping:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    shopping:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    shopping:Hide()
    self.shoppingList = shopping

    local empty = Theme.CreateLabel(body, "small", "dim", "CENTER")
    empty:SetPoint("CENTER", list, "CENTER")
    empty:SetWidth(PANEL_WIDTH - 40)
    empty:SetWordWrap(true)
    self.empty = empty

    self.frame = frame
    return frame
end

--- How tall the panel can be without running into the main window.
--
-- The auction window's own height, normally. But the auction window, this
-- panel and the main window together are wider than the screen on a lot of
-- setups, so when the main window is parked under this panel the two collide.
-- The panel is the one that gives way: it loses a row or two off the bottom,
-- where the main window would lose its title bar and tab row.
--
-- Returns nil while the frames have no screen coordinates yet, which is what
-- a frame that has never been laid out reports.
--
-- @param left  where the panel's left edge is, when it is not right beside the
--   auction window (it moves over for the character window)
function PostPanel:DesiredHeight(auctionFrame, left)
    local top, bottom, right =
        auctionFrame:GetTop(), auctionFrame:GetBottom(), auctionFrame:GetRight()

    if not top or not bottom or not right then return nil end

    left = left or right + PANEL_GAP

    local window = ns.UI and ns.UI.window

    if window and window:IsShown() then
        local windowTop, windowLeft, windowRight =
            window:GetTop(), window:GetLeft(), window:GetRight()

        -- Read in the window's own units, which a player-sized window does
        -- not share with this panel (/bts size): put into the panel's.
        local scale = type(window.GetScale) == "function" and window:GetScale()
        if type(scale) == "number" and scale > 0 and scale ~= 1
            and windowTop and windowLeft and windowRight then
            windowTop, windowLeft, windowRight =
                windowTop * scale, windowLeft * scale, windowRight * scale
        end

        -- Only when the two really do share screen space. The main window is
        -- movable, so most of the time it is somewhere else entirely.
        if windowTop and windowLeft and windowRight then
            if windowRight > left and windowLeft < left + PANEL_WIDTH
                and windowTop > bottom then
                bottom = windowTop + PANEL_GAP
            end
        end
    end

    return math.max(top - bottom, PANEL_MIN_HEIGHT)
end

--------------------------------------------------------------------------------
-- Making room for the character window
--------------------------------------------------------------------------------

-- With the auction house open, the game puts the character window (and any
-- other window that opens beside it) in the slot to the auction window's
-- right. That is exactly where this panel docks, and the panel sits in a
-- higher strata, so it covered the paper doll completely. Now it moves over
-- to the right of whatever window has opened there, and steps aside if the
-- screen has no room for both.

-- Windows worth checking even if the game's panel slots cannot be read.
local SIDE_FRAME_NAMES = { "CharacterFrame" }

--- A frame edge in the panel's own coordinates (UIParent's), or nil.
--
-- Blizzard shrinks some windows to fit the screen, and an edge read off a
-- scaled frame is in that frame's units, not ours.
local function Edge(frame, method)
    local ok, value = pcall(frame[method], frame)
    if not ok or type(value) ~= "number" then return nil end

    local parent = _G.UIParent
    if frame == parent or type(frame.GetEffectiveScale) ~= "function"
        or type(parent) ~= "table" or type(parent.GetEffectiveScale) ~= "function" then
        return value
    end

    local okFrame, frameScale = pcall(frame.GetEffectiveScale, frame)
    local okParent, parentScale = pcall(parent.GetEffectiveScale, parent)

    if okFrame and okParent and type(frameScale) == "number"
        and type(parentScale) == "number" and parentScale > 0 then
        value = value * frameScale / parentScale
    end

    return value
end

--- How far a window's own buttons stick out past its right edge, in the
-- panel's coordinates.
--
-- A player's screenshot, 2026-10-04: with a custom interface, the Professions
-- window carries a column of buttons hanging off its right side, and the
-- list docked to the window's edge sat on top of them. The craft queue pane
-- already measures the same thing beside the profession window
-- (CraftPanel:RightOverhang), so the same measure is used here.
local function Overhang(frame)
    local panel = ns.CraftPanel
    if type(panel) ~= "table" or type(panel.RightOverhang) ~= "function" then return 0 end

    local ok, overhang = pcall(panel.RightOverhang, panel, frame)
    if not ok or type(overhang) ~= "number" or overhang <= 0 then return 0 end

    -- Measured in the window's own units, which a scaled window does not
    -- share with the panel.
    local parent = _G.UIParent
    if type(frame.GetEffectiveScale) == "function" and type(parent) == "table"
        and type(parent.GetEffectiveScale) == "function" then
        local okFrame, frameScale = pcall(frame.GetEffectiveScale, frame)
        local okParent, parentScale = pcall(parent.GetEffectiveScale, parent)
        if okFrame and okParent and type(frameScale) == "number"
            and type(parentScale) == "number" and parentScale > 0 then
            overhang = overhang * frameScale / parentScale
        end
    end

    return overhang
end

local function IsShownFrame(frame)
    if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then return false end

    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

--- The game window open beside the auction house, if one is in the way.
--
-- Anything in the game's right-hand panel slot counts, not just the character
-- window: the spellbook and the rest land in the same place.
function PostPanel:SideFrame(auctionFrame)
    local candidates = {}

    if type(_G.GetUIPanel) == "function" then
        local ok, frame = pcall(_G.GetUIPanel, "right")
        if ok and frame then candidates[#candidates + 1] = frame end
    end

    for _, name in ipairs(SIDE_FRAME_NAMES) do
        candidates[#candidates + 1] = _G[name]
    end

    local ahRight, ahTop, ahBottom =
        Edge(auctionFrame, "GetRight"), Edge(auctionFrame, "GetTop"), Edge(auctionFrame, "GetBottom")
    if not (ahRight and ahTop and ahBottom) then return nil end

    -- Where the panel would sit, docked beside the auction window.
    local dockLeft, dockRight = ahRight + PANEL_GAP, ahRight + PANEL_GAP + PANEL_WIDTH

    for _, frame in ipairs(candidates) do
        if frame ~= auctionFrame and frame ~= self.frame and IsShownFrame(frame) then
            local left, right = Edge(frame, "GetLeft"), Edge(frame, "GetRight")
            local top, bottom = Edge(frame, "GetTop"), Edge(frame, "GetBottom")

            -- Only a window actually in the panel's spot. One the player has
            -- dragged somewhere else is left to itself.
            if left and right and top and bottom
                and left < dockRight and right > dockLeft
                and bottom < ahTop and top > ahBottom then
                return self:PastOwnPanes(frame, right + Overhang(frame), ahTop, ahBottom)
            end
        end
    end
end

-- Panes of this addon that dock to the right of a game window: the craft
-- queue beside the profession window, and its queued crafts beside that.
local function OwnPanes()
    local panel = ns.CraftPanel
    if type(panel) ~= "table" then return {} end
    return { panel.frame, panel.queuedFrame }
end

--- Past the craft queue panes, when they are docked beside the window found.
--
-- With the auction house and a profession both open, the profession window
-- takes the slot beside the auction window and the craft queue panes dock to
-- its right, which is where this panel went next. A screenshot,
-- 2026-10-01: Ready to sell drawn over the queued crafts and shopping list.
-- @return the frame to dock to, its right edge
function PostPanel:PastOwnPanes(frame, right, ahTop, ahBottom)
    local moved = true
    while moved do
        moved = false
        for _, pane in ipairs(OwnPanes()) do
            if pane ~= frame and IsShownFrame(pane) then
                local left, paneRight = Edge(pane, "GetLeft"), Edge(pane, "GetRight")
                local top, bottom = Edge(pane, "GetTop"), Edge(pane, "GetBottom")

                -- Anywhere in the panel's spot past the edge so far. The
                -- craft pane sits clear of the profession tabs, which stick
                -- out past that window's edge, so it is not right beside it.
                if left and paneRight and top and bottom
                    and left < right + PANEL_GAP + PANEL_WIDTH and paneRight > right
                    and bottom < ahTop and top > ahBottom then
                    frame, right, moved = pane, paneRight, true
                end
            end
        end
    end
    return frame, right
end

--- Where the panel should be right now.
--
-- @return the frame to dock to, the panel's left edge (nil for "beside the
--   auction window"), and false when there is no room for it at all
function PostPanel:Placement(auctionFrame)
    local side, sideRight = self:SideFrame(auctionFrame)
    if not side then return auctionFrame, nil, true end

    local left = sideRight + PANEL_GAP
    local screenRight = _G.UIParent and Edge(_G.UIParent, "GetRight")
    local fits = not screenRight or left + PANEL_WIDTH <= screenRight

    return side, left, fits
end

--- Put the panel where Placement says, showing or hiding it to match.
--
-- Cheap enough for the one-second auction house ticker, which is what brings
-- the panel back after the character window closes if no event does.
function PostPanel:Redock()
    local frame = self.frame
    if not (frame and self.attached) then return end

    local auctionFrame = ns.UI:FindAuctionFrame()
    if not auctionFrame then return end

    local host, left, fits = self:Placement(auctionFrame)

    if not fits then
        -- No room beside the character window. Out of the way until it
        -- closes: the paper doll is what the player just asked to see.
        self.dockedTo = nil
        if frame:IsShown() then frame:Hide() end
        return
    end

    self.dockedLeft = left

    -- Past the window's edge by the gap, and by whatever of its own sticks
    -- out there (Overhang).
    local offset = PANEL_GAP
    local hostRight = left and Edge(host, "GetRight")
    if hostRight then offset = math.max(PANEL_GAP, left - hostRight) end

    if self.dockedTo ~= host or math.abs((self.dockedOffset or PANEL_GAP) - offset) > 0.5 then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", host, "TOPRIGHT", offset, 0)
        self.dockedTo, self.dockedOffset = host, offset

        -- Beside a different window, the main window may be in the way now,
        -- or no longer.
        self:ApplyHeight(true)
    end

    if not frame:IsShown() then
        frame:Show()
        self:ApplyHeight(true)
        self:Refresh()
        -- Fades in where it docked; it never rises, since it sits beside
        -- another window.
        if ns.Motion then ns.Motion:Open(frame, 0) end
    end
end

--- Redock as soon as the game has placed a window, rather than on the next
-- tick of the ticker. Hooked once; hooksecurefunc and HookScript leave the
-- game's own code untouched.
function PostPanel:WatchSideFrames()
    if self.watching then return end
    self.watching = true

    local function Soon()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() PostPanel:Redock() end)
        end
    end

    if type(_G.hooksecurefunc) == "function" then
        for _, name in ipairs({ "ShowUIPanel", "HideUIPanel" }) do
            if type(_G[name]) == "function" then pcall(_G.hooksecurefunc, name, Soon) end
        end
    end

    for _, name in ipairs(SIDE_FRAME_NAMES) do
        local frame = _G[name]
        if type(frame) == "table" and type(frame.HookScript) == "function" then
            pcall(frame.HookScript, frame, "OnShow", Soon)
            pcall(frame.HookScript, frame, "OnHide", Soon)
        end
    end
end

--- Dock to the right of the auction house, as tall as there is room for.
function PostPanel:Attach()
    local frame = self:Build()
    local auctionFrame = ns.UI:FindAuctionFrame()

    frame:ClearAllPoints()
    self.dockedTo, self.dockedLeft = nil, nil

    if auctionFrame then
        -- One anchor and a measured height, rather than a point on the auction
        -- window's top and another on its bottom. Two points would keep the
        -- height in step on their own, but they would also pin the bottom to
        -- the auction window, and the bottom is exactly what has to move out
        -- of the main window's way.
        --
        -- (The pair to avoid is TOPLEFT with BOTTOM, which is what this used to
        -- be: a BOTTOM point fixes the horizontal centre too, which TOPLEFT has
        -- already decided, so the client drops one of the two and the panel
        -- keeps whatever height it had. That is how it ended up half as tall as
        -- the window it was docked to.)
        frame:SetPoint("TOPLEFT", auctionFrame, "TOPRIGHT", PANEL_GAP, 0)
        self.dockedTo, self.dockedOffset = auctionFrame, PANEL_GAP
    else
        -- The auction house window is load-on-demand and may not exist yet.
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -120)
    end

    self.attached = true
    self:WatchSideFrames()

    self:ApplyHeight(true)

    local opening = not frame:IsShown()
    frame:Show()
    self:Redock()
    self:Refresh()

    if opening and ns.Motion then ns.Motion:Open(frame, 0) end
end

--- The height to be right now: the title strip when collapsed, otherwise as
-- tall as there is room for.
--
-- @param fallback  use the fallback height when nothing can be measured,
--   rather than leaving the height alone
-- @return nil when there is nothing to go on
function PostPanel:TargetHeight(fallback)
    local auctionFrame = ns.UI:FindAuctionFrame()
    local full = auctionFrame and self:DesiredHeight(auctionFrame, self.dockedLeft)

    if not full and fallback then full = PANEL_FALLBACK_HEIGHT end
    if not full then return nil end

    return ns.Collapse.Height(COLLAPSE_KEY, full)
end

function PostPanel:IsCollapsed()
    return ns.Collapse.IsCollapsed(COLLAPSE_KEY)
end

--- Set the height outright, after attaching or folding.
function PostPanel:ApplyHeight(fallback)
    if not self.frame then return end

    local height = self:TargetHeight(fallback ~= false)
    if height then self.frame:SetHeight(height) end
end

--- Re-measure after the main window is opened, closed or dragged.
function PostPanel:Reflow()
    if not self.frame or not self.frame:IsShown() then return end

    local height = self:TargetHeight(false)

    -- Only when it actually moved. This runs on the auction house ticker, and
    -- setting the height every second would relayout the list for nothing.
    if height and math.abs(height - self.frame:GetHeight()) > 0.5 then
        self.frame:SetHeight(height)
    end
end

--------------------------------------------------------------------------------
-- Buy: the craft queue's shopping list
--------------------------------------------------------------------------------

PostPanel.view = "sell"

--- Switch between the sell list and the shopping list.
function PostPanel:SetView(view)
    self.view = view == "buy" and "buy" or "sell"
    if self.switch then self.switch:Select(self.view) end
    self.shoppingAt = nil
    self:Refresh()
end

--- A row worth searching the auction house for: still short, and not a
--- vendor material, which is a mistake to buy there.
function PostPanel:CanSearch(line)
    return type(line) == "table" and (line.shortfall or 0) > 0 and not line.fromVendor
end

-- Clicking the row searched already, but nothing said so. Asked for: "a button
-- would be clearer to a new user". The same size as the sell list's List.
local SEARCH_WIDTH = BUTTON_WIDTH

--- The craft pane's shopping row, with a Search button at its right end and
--- the counts moved over to make room for it.
function PostPanel.CreateShoppingRow(row)
    ns.CraftPanel.CreateShoppingRow(row)

    row.search = Widgets.CreateButton(row, "Search", function()
        if PostPanel:CanSearch(row.data) then
            ns.UI:SearchAuctionHouse(row.data.itemID, row.data.shortfall)
        end
    end, { width = SEARCH_WIDTH, height = 18, primary = true, tooltip = "Search the auction house for this. Pick it in the results and the quantity is filled in with how many you still need." })
    row.search:SetPoint("RIGHT", row, "RIGHT", -8, 0)

    local inset = -(8 + SEARCH_WIDTH + 6)
    row.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", inset, -4)
    row.tag:SetPoint("TOPRIGHT", row, "TOPRIGHT", inset, -15)
end

function PostPanel.UpdateShoppingRow(row, line)
    ns.CraftPanel.UpdateShoppingRow(row, line)
    row.search:SetShown(PostPanel:CanSearch(line))
end

--- The Queue tab's tooltip, and what a click does.
function PostPanel.ShowShoppingTooltip(row, line)
    if ns.UI and ns.UI.ShowMaterialTooltip then ns.UI.ShowMaterialTooltip(row, line) end
    if PostPanel:CanSearch(line) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to search the auction house", 0.78, 0.64, 0.30)
        GameTooltip:Show()
    end
end

--- The shopping list, at most once every couple of seconds.
function PostPanel:ShoppingLines()
    local now = GetTime()
    if not self.shoppingLines or not self.shoppingAt
        or now - self.shoppingAt >= SHOPPING_REFRESH_SECONDS then
        self.shoppingLines = ns.Queue:GetShoppingList()
        self.shoppingAt = now
    end
    return self.shoppingLines
end

--- What the Buy view's summary line says.
-- @return text, and how many lines are still short
function PostPanel:ShoppingSummary(lines)
    local short = 0
    for _, line in ipairs(lines) do
        if (line.shortfall or 0) > 0 then short = short + 1 end
    end

    if short == 0 then
        return "You have everything the queue needs.", 0
    end

    -- From the lines in hand. Asked for on its own, the total built the whole
    -- list again on every one-second tick, which the cache above is there
    -- to stop.
    local cost = ns.Queue:GetShoppingTotal(lines)
    return ("%d material%s to buy, about %s"):format(
        short, short == 1 and "" or "s",
        Util.FormatMoney(cost or 0, { short = true })), short
end

function PostPanel:RefreshShopping()
    self.list:Hide()
    self.shoppingList:Show()

    local lines = self:ShoppingLines()
    local text, short = self:ShoppingSummary(lines)

    self.title:SetText(self:IsCollapsed() and short > 0
        and ("Shopping list (%d)"):format(short) or "Shopping list")

    self.shoppingList:SetData(lines)
    self.empty:SetShown(#lines == 0)

    if #lines == 0 then
        self.empty:SetText(ns.Queue:Count() == 0
            and "Nothing queued.\n\nQueue crafts and the materials they need show up here."
            or "You already have everything the queue needs.")
        self.summary:SetText("")
        return
    end

    self.summary:SetText(text)
end

--- Back in place, and laid out against the main window, without rebuilding
--- the list: what the one-second ticker does when nothing on it changed.
function PostPanel:Place()
    self:Redock()
    if self.frame and self.frame:IsShown() then self:Reflow() end
end

function PostPanel:Refresh()
    -- Before the shown check: this is how a panel that stepped aside for the
    -- character window comes back.
    self:Redock()

    if not self.frame or not self.frame:IsShown() then return end

    -- Cheap, and it catches the main window being dragged, which has no event.
    self:Reflow()

    if self.view == "buy" then
        self.worth:SetText("")
        self:RefreshShopping()
        return
    end

    self.shoppingList:Hide()
    self.list:Show()

    if TypingInList(self.list) then return end

    local lines = ns.Posting:GetPostable({ includeAll = true })

    -- Folded away, the title is all there is to read, so it carries the count.
    if self:IsCollapsed() then
        self.title:SetText(#lines > 0
            and ("Ready to sell (%d)"):format(#lines)
            or "Ready to sell")
    else
        self.title:SetText("Ready to sell")
    end

    self.list:SetData(lines)
    self.empty:SetShown(#lines == 0)

    if #lines == 0 then
        self.empty:SetText(
            "Nothing in your bags with a known price.\n\nScan the auction house to find out what things sell for.")
        self.summary:SetText("")
        self.worth:SetText("")
        return
    end

    local total, losses = 0, 0
    for _, line in ipairs(lines) do
        total = total + (line.postTotal or 0)
        if line.atALoss then losses = losses + 1 end
    end

    self.worth:SetText(Util.FormatMoney(total, { noColor = true, short = true }))

    self.summary:SetText(("%d item%s, about |c%s%s|r%s"):format(
        #lines, #lines == 1 and "" or "s",
        ns.COLORS.accent,
        Util.FormatMoney(total, { noColor = true, short = true }),
        losses > 0 and (("  ·  |c%s%d at a loss|r"):format(ns.COLORS.loss, losses)) or ""))
end

--- Put the current wait on every visible List button.
--
-- The bar's Post Crafted is not the only way to list something, and a row
-- button that did nothing for three seconds looked exactly as broken there as
-- it did on the bar. Every row shows the same number because the wait is the
-- auction house's, not the row's.
--
-- Labels only: called four times a second, so it must not rebuild the list or
-- touch anything that walks the bags.
function PostPanel:UpdateWaitLabels(seconds, reason)
    if not self.list or not self.list.rows then return end
    if not self.frame or not self.frame:IsShown() then return end

    local Apply = ns.UI and ns.UI.ApplyWaitLabel
    if not Apply then return end

    for i = 1, #self.list.rows do
        local row = self.list.rows[i]

        -- A row with no price is disabled on its own account, and leaving it
        -- alone keeps that reason visible rather than replacing it with a
        -- countdown it is not really serving.
        if row and row.data and row.post and not row.post.disabled then
            -- Another copy of the item being confirmed does not wait for it.
            local pending = ns.Posting and ns.Posting.pending
            if pending and pending.itemID == row.data.itemID then
                Apply(row.post, "List", ns.Posting:SecondsUntilPostable(row.data.itemID))
            else
                Apply(row.post, "List", seconds, reason)
            end
        end
    end
end

function PostPanel:Hide()
    -- The auction house closed: nothing should bring the panel back now.
    self.attached = false
    self.dockedTo, self.dockedLeft = nil, nil

    if self.frame then self.frame:Hide() end

    -- A price being set for a listing goes with it: nothing can be listed
    -- away from the auction house.
    if ns.PriceEditor and ns.PriceEditor.IsShown and ns.PriceEditor:IsShown() then ns.PriceEditor:Hide() end
end

function PostPanel:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end
