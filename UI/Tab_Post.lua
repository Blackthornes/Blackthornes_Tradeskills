-- Blackthornes Tradeskills -- UI/Tab_Post.lua
-- What to sell, and what to charge.
--
-- One click per listing, because Blizzard requires a hardware event to post.
-- The price is on the row before you press it, and anything that would sell
-- below its material cost is marked red and refused unless allowed.
--
-- The list is everything in your bags, not only what your recipes make. It
-- began as crafted output alone, on the reasoning that offering to sell
-- arbitrary bag contents invites mistakes -- but the mistake it invites is
-- one click on one row, and the thing it was costing was every drop, every
-- gathered stack and everything bought to resell. The crafted-only view is
-- still there, one tick box away, and the bar's Post Crafted button never
-- changed.
--
-- The price is also shown split into Blizzard's gold/silver/copper boxes, so
-- listing by hand stays easy when the auction house is refusing addon
-- listings -- which it has done for stretches on this beta.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 26

-- Right to left. Money and the price boxes sit to the right, so their
-- digits line up; HAVE is centred under its heading. `width` is the least
-- each gets: Widgets.FitColumns widens it to fit the heading and an amount.
local COLUMNS = {
    { key = "action",  label = "",        width = 56 },
    { key = "qty",     label = "LIST",    width = 44 },
    { key = "total",   label = "TOTAL",   width = 78, money = true },
    { key = "deposit", label = "DEPOSIT", width = 62, money = true },
    { key = "copper",  label = "C",       width = 34 },
    { key = "silver",  label = "S",       width = 34 },
    { key = "gold",    label = "G",       width = 40 },
    { key = "cost",    label = "COST",    width = 66, money = true },
    { key = "count",   label = "HAVE",    width = 42, justify = "CENTER" },
}

local widgets = {}

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- Declared early because typing in a row's quantity box redraws that one row.
-- Rebuilding the whole list instead would scroll it back to the top, which
-- loses your place every time you change a number.
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
    -- The item's icon beside its name, as the bags draw it.
    row.icon = Theme.CreateItemIcon(row, 16)
    row.icon:SetPoint("LEFT", 10, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 30, 0)

    row.cells = {}

    local offset = -8
    local reserved = 18

    for _, column in ipairs(COLUMNS) do
        if column.key == "qty" then
            row.quantity = Widgets.CreateNumberBox(row, {
                width = column.width,
                height = 18,
                background = "panel",
                min = 1,
                onChange = function(value)
                    if not row.data then return end

                    ns.Posting:ApplyQuantity(row.data, value)
                    UpdateRow(row, row.data)
                end,
            })
            row.quantity:SetPoint("RIGHT", offset, 0)
        elseif column.key ~= "action" then
            local cell = Theme.CreateLabel(row, "small", "muted", column.justify or "RIGHT")
            cell:SetPoint("RIGHT", offset, 0)
            cell:SetWidth(column.width)
            row.cells[column.key] = cell
        end

        offset = offset - column.width - 6
        reserved = reserved + column.width + 6
    end

    row.name:SetPoint("RIGHT", row, "RIGHT", -reserved, 0)

    row.post = Widgets.CreateButton(row, "List", function()
        CommitTyping(widgets.list)
        local line = row.data
        if not line then return end

        -- A row nothing has ever priced goes and finds a price instead of
        -- sitting there refusing. The whole bag is on show, so most of these
        -- are simply things the scan has never had a reason to look at.
        if not line.unitPrice then
            ns.Posting:CheckPrice(line.itemID, function(itemID, price, status)
                -- "recent" while that same search is still out means a
                -- second click before the answer: it will redraw the row
                -- itself, and saying nobody sells one would be a guess.
                local pending = ns.Scanner.pendingItem
                local stillAsking = status == "recent" and pending and pending.itemID == itemID

                if not price and not stillAsking then
                    ns.Print(("%s: %s"):format(Util.GetItemLabel(itemID),
                        -- "recent": searched moments ago, and that search
                        -- found nobody selling it.
                        (status == "empty" or status == "recent")
                            and "nobody is selling one right now, so there is no price to go on."
                            or "the auction house did not answer. Try again in a moment."))
                end

                UI:RefreshActiveTab()
            end)
            return
        end

        -- Left clickable even when it cannot list, so the click produces an
        -- explanation rather than nothing at all.
        local allowed, reason = ns.Posting:CanPost(line.itemID)
        if not allowed then
            ns.Print(reason or "cannot post right now")
            return
        end

        ns.Posting:Request(line.itemID, line.postQuantity, line.unitPrice)
        UI:RefreshActiveTab()
    end, { width = 50, height = 18, primary = true })
    row.post:SetPoint("RIGHT", -8, 0)
end

function UpdateRow(row, line)
    Theme.SetRowName(row.name, line.label)
    Theme.SetItemIcon(row.icon, line.itemID, line.link)

    local cells = row.cells

    -- Not while it is being typed into: overwriting someone mid-number is how
    -- a field ends up refusing to accept what they meant.
    -- A reused row now showing another item drops the half-typed number,
    -- though: it was for the item that scrolled away, and pressing Enter
    -- would have set that many of this one. The Queue tab does the same.
    local typing = BeingTyped(row.quantity)
    if not typing or row.boundItemID ~= line.itemID then
        row.quantity:SetLimits(1, math.max(1, line.maxQuantity or line.count or 1))
        row.quantity:SetValue(line.postQuantity or line.count or 1, true)
        if typing then row.quantity.editBox:ClearFocus() end
    end
    row.boundItemID = line.itemID

    cells.count:SetText(tostring(line.count))
    cells.count:SetTextColor(Theme.Unpack("text"))

    -- Money cells are measured: "12g 34s 56c" was wider than COST and
    -- DEPOSIT, and ended in "...". It now drops to "12g 35s" instead.
    if line.unitCost then
        Theme.SetMoneyText(cells.cost, line.unitCost, { short = true })
    else
        cells.cost:SetText("?")
    end

    if line.unitPrice then
        -- Split into the three boxes Blizzard's Sell tab asks for, so the price
        -- can be read straight across rather than converted in your head.
        local gold, silver, copper = Util.SplitMoney(line.unitPrice)

        local priceColour = line.atALoss and "loss" or "accent"

        cells.gold:SetText(tostring(gold))
        cells.silver:SetText(tostring(silver))
        cells.copper:SetText(tostring(copper))

        for _, key in ipairs({ "gold", "silver", "copper" }) do
            cells[key]:SetTextColor(Theme.Unpack(priceColour))
        end

        -- What this listing comes to at the LIST amount, the same figure the
        -- tooltip gives, not the whole stack's.
        Theme.SetMoneyText(cells.total, line.postTotal or line.total, { short = true })
        cells.total:SetTextColor(Theme.Unpack(line.atALoss and "loss" or "profit"))
    else
        for _, key in ipairs({ "gold", "silver", "copper" }) do
            cells[key]:SetText("-")
            cells[key]:SetTextColor(Theme.Unpack("dim"))
        end

        cells.total:SetText("no price")
        cells.total:SetTextColor(Theme.Unpack("dim"))
    end

    if line.deposit then
        Theme.SetMoneyText(cells.deposit, line.deposit, { short = true })
    else
        cells.deposit:SetText("--")
    end

    -- The bag holds all sorts now, so a row is worth recognising at a glance.
    -- Rarity is how the game itself says what a thing is.
    local red, green, blue = Util.GetItemQualityColor(line.itemID)

    if red and line.unitPrice then
        row.name:SetTextColor(red, green, blue)
    else
        row.name:SetTextColor(Theme.Unpack(line.unitPrice and "text" or "muted"))
    end

    -- The G/S/C columns stay either way: when the auction house refuses a
    -- listing, typing it into Blizzard's Sell tab is the fallback.
    local allowed, reason = ns.Posting:CanPost(line.itemID)

    if line.unitPrice then
        row.post:SetText("List")
        row.post:SetEnabledState(true)

        if not allowed then
            row.post.tooltipText = reason
        elseif line.atALoss then
            row.post.tooltipText = (line.lossReason == "vendor"
                and "This would sell for less than a vendor pays, so it will not be listed. Sell it to a vendor instead."
                or line.lossReason == "crafted"
                and "After the auction house's cut, this brings in less than you paid to make it. Blocked while 'Never below what I paid' is on in Settings."
                or "This would sell below its material cost. Blocked unless you allow it in Settings.")
        else
            row.post.tooltipText = ("List %d of %d at %s each"):format(
                line.postQuantity, line.maxQuantity or line.count,
                Util.FormatMoney(line.unitPrice, { noColor = true }))
        end
    else
        -- Nothing has ever priced this. The button becomes the way to fix
        -- that, because a disabled control and a missing one look identical
        -- on a client that prints no error.
        local canPrice, priceReason = ns.Posting:CanPrice()

        row.post:SetText("Price")
        row.post:SetEnabledState(canPrice)

        row.post.tooltipText = canPrice
            and "No scan has priced this yet.\nSearch the auction house for it now."
            or (priceReason or "open the auction house to check a price")
    end
end

local function ShowRowTooltip(row, line)
    ns.Widgets.ShowItemTooltip(row, "ANCHOR_RIGHT", line.itemID, line.label, line.link)
    GameTooltip:AddLine(" ")

    GameTooltip:AddDoubleLine("In bags", tostring(line.count), 0.7, 0.7, 0.7, 1, 1, 1)

    GameTooltip:AddDoubleLine("Listing", ("%d of %d"):format(
        line.postQuantity, line.maxQuantity or line.count), 0.7, 0.7, 0.7, 1, 1, 1)

    if line.unitPrice and line.postTotal then
        GameTooltip:AddDoubleLine("That comes to",
            Util.FormatMoney(line.postTotal, { noColor = true }),
            0.7, 0.7, 0.7, 1, 1, 1)
    end

    if line.unitPrice then
        GameTooltip:AddDoubleLine("List each at",
            Util.FormatMoney(line.unitPrice, { noColor = true }),
            0.7, 0.7, 0.7, 0.78, 0.64, 0.30)

        local why = "Nothing listed to undercut, so using market value"

        if line.priceBasis == "undercut" then
            why = "Undercutting the cheapest listing that is not yours"
        elseif line.priceBasis == "derived" then
            -- Neither of these two is a market observation at all.
            why = "No scan has priced this, so it is estimated from what its materials are worth"
        elseif line.priceBasis == "uncontested" then
            why = "Nobody else is listing one, so it is priced at your materials plus the markup"
        elseif line.priceBasis == "mine" then
            why = "Your own price, set on the Prices tab"
        elseif line.priceBasis == "floor" then
            why = "Raised to the least you set on the Prices tab"
        elseif line.priceBasis == "chosen" then
            why = "Your price for now, set on Ready to sell"
        elseif line.priceBasis == "match" then
            -- Worth spelling out, because "match" looks like the addon has
            -- stopped undercutting when in fact no smaller step exists.
            why = "Matching the cheapest listing, since an undercut here costs a whole silver"
        end

        GameTooltip:AddLine(why, 0.5, 0.5, 0.5)
    end

    if not line.unitPrice then
        GameTooltip:AddLine("No scan has priced this one yet.", 0.9, 0.7, 0.3)
        GameTooltip:AddLine("Press Price to search the auction house for it.",
            0.5, 0.5, 0.5)
    end

    if line.unitCost then
        GameTooltip:AddDoubleLine("Materials cost, each",
            Util.FormatMoney(line.unitCost, { noColor = true }), 0.7, 0.7, 0.7, 1, 1, 1)
    end

    -- What it cost when it was made, what it last went up at, and what this
    -- listing makes over that cost (2026-10-05).
    if ns.CraftedCost then
        for _, entry in ipairs(ns.CraftedCost:Lines(line.itemID, line.unitPrice)) do
            local r, g, b = 1, 1, 1
            if entry.color then r, g, b = Theme.Unpack(entry.color) end
            GameTooltip:AddDoubleLine(entry[1], entry[2], 0.7, 0.7, 0.7, r, g, b)
        end
    end

    if line.vendorPrice then
        GameTooltip:AddDoubleLine("Vendor pays, each",
            Util.FormatMoney(line.vendorPrice, { noColor = true }), 0.7, 0.7, 0.7, 1, 1, 1)
    end

    if line.atALoss then
        GameTooltip:AddLine(line.lossReason == "vendor"
            and "Would sell for less than a vendor pays"
            or line.lossReason == "crafted"
            and "Would bring in less than you paid to make it"
            or "Would sell below material cost", 0.9, 0.38, 0.31)
    end

    if not line.isCrafted then
        GameTooltip:AddLine("Not something your recipes make, just something in your bags.",
            0.5, 0.5, 0.5)
    end

    -- Commodities sell from across the bags at once, and so do copies of an
    -- item that does not stack (one auction each); other gear goes up one at
    -- a time.
    local together = line.isCommodity
        and ("Commodity: all %d can go up together"):format(line.count)
        or ((line.maxQuantity or 1) > 1
            and ("All %d go up in one click, one auction each"):format(line.maxQuantity)
            or "Item auction: one listing at a time")
    GameTooltip:AddLine(together, 0.5, 0.5, 0.5)

    GameTooltip:AddLine("Type into the LIST box to sell fewer than that.", 0.5, 0.5, 0.5)
    GameTooltip:AddLine("Right-click to search the auction house for it.", 0.5, 0.5, 0.5)

    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

--- Is the tab showing the whole bag, or only what the recipes make?
local function ShowingEverything()
    return ns.Config:Get("postShowAllItems") ~= false
end

--- The rows to draw: what is postable, narrowed by whatever was typed.
--
-- The filter is on the label, which is an item link when the client has the
-- item cached -- the name sits inside it, so a plain substring match finds it
-- either way.
local function VisibleLines()
    local showAll = ShowingEverything()

    local lines = ns.Posting:GetPostable(showAll
        and { includeAll = true, includeUnpriced = true }
        or nil)

    local needle = widgets.search and widgets.search:GetText() or ""
    if needle == "" then return lines, #lines end

    needle = needle:lower()

    local kept = {}
    for _, line in ipairs(lines) do
        -- The name only: the label is an item link, and its colour code and
        -- item number matched "ff" or "20" on nearly every row.
        local label = line.label or ""
        local name = label:match("%[(.-)%]") or label
        if name:lower():find(needle, 1, true) then
            kept[#kept + 1] = line
        end
    end

    return kept, #lines
end

local function Refresh()
    if not widgets.list then return end
    if TypingInList(widgets.list) then return end

    local showAll = ShowingEverything()

    if widgets.showAll then widgets.showAll:SetChecked(showAll) end

    local lines, found = VisibleLines()
    -- A clicked heading's order over the list's own.
    if widgets.sorter then lines = widgets.sorter:Sort(lines) end
    widgets.list:SetData(lines)

    -- Ticking the box or typing in the search makes this a different list,
    -- not the same one a second later, so it starts at the top. Everything
    -- else keeps the reader where they were: the tab rebuilds itself once a
    -- second at the auction house, and a list that jumps cannot be read.
    local view = ("%s|%s"):format(tostring(showAll),
        widgets.search and widgets.search:GetText() or "")

    if view ~= widgets.view then
        widgets.view = view
        if widgets.list.ScrollToTop then widgets.list:ScrollToTop() end
    end

    widgets.emptyLabel:SetShown(#lines == 0)
    if #lines == 0 then
        -- Three different nothings, and telling them apart is the difference
        -- between a tab that looks broken and one that has answered.
        if found > 0 then
            widgets.emptyLabel:SetText(
                "Nothing in your bags matches that.\nClear the search box to see the rest.")
        elseif showAll then
            widgets.emptyLabel:SetText(
                "Nothing in your bags can go on the auction house.\nSoulbound items and reagents your queue needs are left out.")
        else
            widgets.emptyLabel:SetText(
                "Nothing in your bags that one of your recipes makes.\nTick 'Everything in my bags' to sell the rest of it.")
        end
    end

    local total, losses, unpriced = 0, 0, 0
    for _, line in ipairs(lines) do
        -- What the LIST column will put up, as each row's TOTAL shows.
        total = total + (line.postTotal or line.total or 0)
        if line.atALoss then losses = losses + 1 end
        if not line.unitPrice then unpriced = unpriced + 1 end
    end

    widgets.summary:SetText(("%d stack%s worth about %s%s"):format(
        #lines, #lines == 1 and "" or "s", Util.FormatMoney(total, { short = true }),
        unpriced > 0 and ("  ·  %d with no price yet"):format(unpriced) or ""))

    widgets.warning:SetText(losses > 0
        and ("%d item%s would sell at a loss"):format(
            losses, losses == 1 and "" or "s")
        or "")

    local allowed, reason = ns.Posting:CanPost()
    widgets.statusLabel:SetText(allowed and "" or (reason or ""))

    widgets.duration:SetValue(ns.Config:Get("postDuration") or 2)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function Build(container)
    -- Before any row or heading is laid out: they read these widths.
    if Widgets.FitColumns then Widgets.FitColumns(COLUMNS) end

    local toolbar = CreateFrame("Frame", nil, container)
    toolbar:SetPoint("TOPLEFT", 8, -8)
    toolbar:SetPoint("TOPRIGHT", -8, -8)
    toolbar:SetHeight(24)

    local durationLabel = Theme.CreateLabel(toolbar, "small", "muted")
    durationLabel:SetPoint("LEFT", 2, 0)
    durationLabel:SetText("Duration")

    widgets.duration = Widgets.CreateDropdown(toolbar, ns.Posting.DURATIONS, function(value)
        ns.Config:Set("postDuration", value)
        Refresh()
    end, { width = 110 })
    widgets.duration:SetPoint("LEFT", durationLabel, "RIGHT", 8, 0)

    local durationHint = Theme.CreateLabel(toolbar, "tiny", "dim")
    durationHint:SetPoint("LEFT", widgets.duration, "RIGHT", 8, 0)
    durationHint:SetText("how long listings stay up")

    widgets.statusLabel = Theme.CreateLabel(toolbar, "small", "warn", "RIGHT")
    widgets.statusLabel:SetPoint("RIGHT", 0, 0)
    widgets.statusLabel:SetWidth(340)

    -- What the list covers, and a way to find one thing in a full bag.
    local filterBar = CreateFrame("Frame", nil, container)
    filterBar:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -6)
    filterBar:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -6)
    filterBar:SetHeight(22)

    widgets.showAll = Widgets.CreateCheckbox(filterBar, "Everything in my bags",
        function(checked)
            ns.Config:Set("postShowAllItems", checked)
            Refresh()
        end, ns.Config:Get("postShowAllItems") ~= false)
    widgets.showAll:SetPoint("LEFT", 2, 0)

    local showAllHint = Theme.CreateLabel(filterBar, "tiny", "dim")
    showAllHint:SetPoint("LEFT", widgets.showAll, "RIGHT", 8, 0)
    showAllHint:SetText("untick to show only things you craft")

    widgets.search = Widgets.CreateSearchBox(filterBar, "Find an item", function()
        Refresh()
    end)
    widgets.search:SetPoint("RIGHT", 0, 0)
    widgets.search:SetWidth(200)

    -- Stated once, plainly, rather than discovered by clicking a dead button.
    local note = Theme.CreateLabel(container, "small", "warn")
    note:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 2, -6)
    note:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", 0, -6)
    note:SetWordWrap(true)
    note:SetText("Set LIST to sell part of a stack. Or type the G / S / C price into Blizzard's own Sell tab.")

    -- Column headings
    local headings = CreateFrame("Frame", nil, container)
    headings:SetPoint("TOPLEFT", note, "BOTTOMLEFT", -2, -8)
    headings:SetPoint("TOPRIGHT", note, "BOTTOMRIGHT", 0, -8)
    headings:SetHeight(16)

    local nameHeading = Theme.CreateLabel(headings, "tiny", "muted")
    nameHeading:SetPoint("LEFT", 30, 0)
    nameHeading:SetText("ITEM")

    local sortLabels = { name = nameHeading }
    local offset = -8
    for _, column in ipairs(COLUMNS) do
        local heading = Theme.CreateLabel(headings, "tiny", "muted", column.justify or "RIGHT")
        heading:SetPoint("RIGHT", offset, 0)
        heading:SetWidth(column.width)
        heading:SetText(column.label)
        sortLabels[column.key] = heading

        offset = offset - column.width - 6
    end

    -- Click a heading to sort by it. G, S and C are all the price.
    local function Price(line) return line.unitPrice end
    widgets.sorter = Widgets.SortableHeadings and Widgets.SortableHeadings(sortLabels, {
        name = function(line)
            local label = line.label or ""
            return label:match("%[(.-)%]") or label
        end,
        qty = function(line) return line.postQuantity end,
        total = function(line) return line.postTotal end,
        deposit = function(line) return line.deposit end,
        gold = Price, silver = Price, copper = Price,
        cost = function(line) return line.unitCost end,
        count = function(line) return line.count end,
    }, function() Refresh() end)
    if widgets.sorter then widgets.sorter:SetText({ "name" }) end

    local divider = Theme.CreateDivider(container, "borderLit")
    divider:SetPoint("TOPLEFT", headings, "BOTTOMLEFT", 0, -2)
    divider:SetPoint("TOPRIGHT", headings, "BOTTOMRIGHT", 0, -2)

    local list = Widgets.CreateScrollList(container, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onEnter = ShowRowTooltip,
        onLeave = function() GameTooltip:Hide() end,
        -- Right-click: every listing of the item on the auction house, all
        -- its suffixes included (kronosbest's request, 2026-10-02).
        onClick = function(line, _, mouseButton)
            if mouseButton == "RightButton" then UI:SearchAuctionHouse(line.itemID) end
        end,
        -- The headings move in with the rows when the scrollbar takes its room.
        onScrollbarShown = function(shown)
            headings:SetPoint("TOPRIGHT", note, "BOTTOMRIGHT", shown and -10 or 0, -8)
        end,
    })
    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 54)
    widgets.list = list

    local emptyLabel = Theme.CreateLabel(container, "small", "dim", "CENTER")
    emptyLabel:SetPoint("CENTER", list, "CENTER")
    emptyLabel:SetWidth(380)
    emptyLabel:SetWordWrap(true)
    widgets.emptyLabel = emptyLabel

    local footerDivider = Theme.CreateDivider(container)
    footerDivider:SetPoint("BOTTOMLEFT", 8, 46)
    footerDivider:SetPoint("BOTTOMRIGHT", -8, 46)

    widgets.summary = Theme.CreateLabel(container, "small", "text")
    widgets.summary:SetPoint("BOTTOMLEFT", 10, 28)

    widgets.warning = Theme.CreateLabel(container, "tiny", "loss")
    widgets.warning:SetPoint("BOTTOMLEFT", 10, 12)
end

UI:RegisterTab({
    key = "post",
    text = "Post",
    order = 4,
    build = Build,
    refresh = Refresh,
})
