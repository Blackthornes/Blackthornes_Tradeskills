-- Blackthornes Tradeskills -- UI/Tab_Sales.lua
-- What actually sold, and what came back.
--
-- Every other tab in this addon is a forecast: the Profit tab says what a craft
-- ought to earn, the Post tab says what to list it at. This one is the only
-- record of what the auction house really paid, which is the number those
-- forecasts are being judged against.
--
-- It reads Data/Mail.lua's ledger and adds nothing to it. The ledger is written
-- when the mailbox is opened, so an empty tab means "you have not been to a
-- mailbox", not "nothing sold" -- and it says so rather than showing a blank
-- list and leaving that to be worked out.
--
-- Two views, because the ledger answers two different questions. "Recent" is
-- the event list: this sold, then that expired. "By item" is the one that tells
-- you whether a craft is worth making again -- how many sold, how many came
-- back, and what the two together say about the price.
--
-- The split matters for a second reason. History from before the client was
-- last closed survives as a per-item rollup rather than as individual sales
-- (see Mail:GetRestoredRollup), so it can appear in the By item view and in the
-- totals but never in a list of events. Rather than let that read as sales
-- going missing, the Recent view says how many are being held back and where
-- to find them.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 34
local DETAIL_WIDTH = 320

local VIEWS = {
    { text = "Recent sales",   value = "sales" },
    { text = "Recent, all",    value = "all" },
    { text = "By item",        value = "item" },
    { text = "Mailbox visits", value = "visits" },
}

local state = { view = "sales", search = "", selected = nil }
local widgets = {}

--------------------------------------------------------------------------------
-- Item names
--------------------------------------------------------------------------------

-- Rows whose item the client had not sent yet when they were drawn. Item data
-- arrives on its own schedule, so the first pass over an item the client has
-- never seen gets no rarity colour back; GET_ITEM_INFO_RECEIVED redraws those
-- once it has them. Same hole, and the same fix, as UI/Tab_Profit.lua.
local awaitingItemData = false

--- What to call one ledger row's item.
--
-- An entry always has one of the two: an itemID resolved from the invoice's
-- name, or failing that the name itself. A sale of something the addon has no
-- recipe for is still a sale, so the name is shown rather than the row dropped.
local function ItemLabel(itemID, name)
    if itemID then return Util.GetItemLabel(itemID) end
    return name or "unknown item"
end

--- Colour a name by the rarity of the item, where the client knows it.
local function ApplyNameColor(label, itemID)
    local r, g, b = Util.GetItemQualityColor(itemID)

    if r then
        label:SetTextColor(r, g, b)
        return
    end

    label:SetTextColor(Theme.Unpack("text"))
    if itemID then awaitingItemData = true end
end

--- Does this row match what has been typed in the search box?
local function Matches(itemID, name, query)
    if query == "" then return true end

    local haystack = (name or ""):lower()

    -- The item is only looked up when the entry carries no name: reading
    -- every ledger entry through the client on each keystroke pulled items
    -- into its small cache and pushed bag items out.
    if itemID and (name or "") == "" then
        -- GetItemLabel hands back a link once the client has the item, and a
        -- link carries the name inside it, so searching the label works for
        -- both shapes without having to take the link apart.
        -- Only the name inside the link: its colour code and item number
        -- matched "ff" or a digit on every row.
        local label = tostring(Util.GetItemLabel(itemID))
        haystack = haystack .. " " .. (label:match("%[(.-)%]") or label):lower()
    end

    return haystack:find(query, 1, true) ~= nil
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- One row layout serves both views: a name and a figure on the top line, and a
-- line of context under it. What goes in each is all that changes, so the two
-- views cannot drift apart in how they look.
local function CreateRow(row)
    -- The item's icon beside both lines, as the bags draw it.
    row.icon = Theme.CreateItemIcon(row, 24)
    row.icon:SetPoint("LEFT", 8, 0)

    row.name = Theme.CreateLabel(row, "normal", "text")
    row.name:SetPoint("TOPLEFT", 40, -4)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -130, -4)
    row.name:SetJustifyH("LEFT")

    row.amount = Theme.CreateLabel(row, "normal", "text", "RIGHT")
    row.amount:SetPoint("TOPRIGHT", -12, -4)
    row.amount:SetWidth(115)

    row.detail = Theme.CreateLabel(row, "tiny", "muted")
    row.detail:SetPoint("TOPLEFT", 40, -19)
    row.detail:SetPoint("TOPRIGHT", row, "TOPRIGHT", -130, -19)
    row.detail:SetJustifyH("LEFT")

    row.when = Theme.CreateLabel(row, "tiny", "dim", "RIGHT")
    row.when:SetPoint("TOPRIGHT", -12, -19)
    row.when:SetWidth(115)
end

--- One event: a listing that sold, expired, or that you pulled.
local function UpdateEventRow(row, entry)
    row.name:SetText(ItemLabel(entry.itemID, entry.name))
    ApplyNameColor(row.name, entry.itemID)

    if entry.kind == "sold" then
        row.amount:SetText(Util.FormatMoney(entry.net))
        row.amount:SetTextColor(Theme.Unpack("profit"))

        local parts = {}

        -- Only ever shown when the ledger genuinely recorded one. A sale
        -- leaves no attachment behind, so the quantity is usually unknown,
        -- and printing "1" for a stack of twenty would be a number this tab
        -- states with confidence and gets wrong.
        if entry.quantity and entry.quantity > 1 then
            parts[#parts + 1] = ("%d sold"):format(entry.quantity)
        else
            parts[#parts + 1] = "sold"
        end

        if entry.cut and entry.cut > 0 then
            parts[#parts + 1] = ("cut %s"):format(
                Util.FormatMoney(entry.cut, { short = true, noColor = true }))
        end

        if entry.estimated then
            parts[#parts + 1] = "gold still held"
        end

        row.detail:SetText(table.concat(parts, "  ·  "))
        row.detail:SetTextColor(Theme.Unpack(entry.estimated and "warn" or "muted"))
    else
        -- Nothing was earned, so the column stays empty rather than saying
        -- zero: a zero here would read as a sale that paid nothing, which is
        -- exactly the bug the ledger already had once.
        row.amount:SetText("")

        local quantity = entry.quantity or 1
        row.detail:SetText(("%s%s"):format(
            quantity > 1 and ("%dx "):format(quantity) or "",
            entry.kind == "removed" and "you cancelled it" or "expired, nobody bought it"))
        row.detail:SetTextColor(Theme.Unpack(entry.kind == "removed" and "muted" or "loss"))
    end

    row.when:SetText(Util.FormatAgeAgo(entry.t and (time() - entry.t)))
    row.when:SetTextColor(Theme.Unpack("dim"))
end

--- One item, everything the ledger holds about it rolled together.
local function UpdateItemRow(row, item)
    row.name:SetText(ItemLabel(item.itemID, item.name))
    ApplyNameColor(row.name, item.itemID)

    row.amount:SetText(Util.FormatMoney(item.net, { short = true }))
    row.amount:SetTextColor(Theme.Unpack(item.net > 0 and "profit" or "muted"))

    local parts = {}

    -- Units rather than listings, because a listing is not a useful unit of
    -- anything -- except that a sale's quantity is usually unknown, so the two
    -- are the same number more often than not and saying "sold" twice would
    -- be noise.
    parts[#parts + 1] = ("%d sold"):format(item.sold)

    if item.expired > 0 then
        parts[#parts + 1] = ("%d expired"):format(item.expired)
    end

    if item.cancelled > 0 then
        parts[#parts + 1] = ("%d cancelled"):format(item.cancelled)
    end

    row.detail:SetText(table.concat(parts, "  ·  "))
    row.detail:SetTextColor(Theme.Unpack("muted"))

    if item.sellThrough then
        row.when:SetText(("%d%% sold through"):format(
            math.floor(item.sellThrough * 100 + 0.5)))
        row.when:SetTextColor(Theme.ProfitColor(item.sellThrough >= 0.5 and 1 or -1))
    else
        row.when:SetText(Util.FormatAgeAgo(item.lastAt and (time() - item.lastAt)))
        row.when:SetTextColor(Theme.Unpack("dim"))
    end
end

--- One mailbox visit: what was collected, and the best sale in it.
local function UpdateVisitRow(row, haul)
    local best = haul.best

    Theme.SetItemIcon(row.icon, best and best.itemID)

    local head = ("Collected %s"):format(Util.FormatMoney(haul.total, { short = true }))
    if haul.recordHaul then head = head .. ("  |c%sbest haul|r"):format(ns.COLORS.accent) end
    row.name:SetText(head)
    row.name:SetTextColor(Theme.Unpack("text"))

    row.amount:SetText(Util.FormatMoney(haul.total, { short = true }))
    row.amount:SetTextColor(Theme.Unpack("accent"))

    local parts = {}
    if (haul.salesCount or 0) > 0 then
        parts[#parts + 1] = ("%d sale%s"):format(haul.salesCount, haul.salesCount == 1 and "" or "s")
    end
    if best then
        parts[#parts + 1] = ("best %s %s"):format(best.name or "item",
            Util.FormatMoney(best.amount, { short = true, noColor = true }))
    end
    if (haul.itemCount or 0) > 0 then
        parts[#parts + 1] = ("%d item%s"):format(haul.itemCount, haul.itemCount == 1 and "" or "s")
    end

    local who = Util.CharacterName(haul.who)
    if who ~= "" then parts[#parts + 1] = who end

    row.detail:SetText(table.concat(parts, "  ·  "))
    row.detail:SetTextColor(Theme.Unpack("muted"))

    row.when:SetText(Util.FormatAgeAgo(haul.t and (time() - haul.t)))
    row.when:SetTextColor(Theme.Unpack("dim"))
end

local function UpdateRow(row, data)
    if data.haul then
        UpdateVisitRow(row, data)
        return
    end

    Theme.SetItemIcon(row.icon, data.itemID)
    if data.kind then
        UpdateEventRow(row, data)
    else
        UpdateItemRow(row, data)
    end
end

--------------------------------------------------------------------------------
-- Detail
--------------------------------------------------------------------------------

local LINE_COUNT = 11

local function BuildDetail(parent)
    local detail = Theme.CreatePanel(parent, "window")
    -- The gold edge every other detail pane has.
    Theme.AccentStripe(detail, 2, 0.6)
    detail:SetWidth(DETAIL_WIDTH)

    local title = Theme.CreateLabel(detail, "large", "accent")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetPoint("TOPRIGHT", -12, -12)
    detail.title = title

    local subtitle = Theme.CreateLabel(detail, "small", "muted")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -4)
    detail.subtitle = subtitle

    detail.lines = {}
    local anchor = subtitle

    for index = 1, LINE_COUNT do
        local line = CreateFrame("Frame", nil, detail)
        line:SetHeight(16)
        line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, index == 1 and -12 or 0)
        line:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -12, 0)

        line.label = Theme.CreateLabel(line, "small", "muted")
        line.label:SetPoint("LEFT", 0, 0)
        line.label:SetPoint("RIGHT", -110, 0)

        line.value = Theme.CreateLabel(line, "small", "text", "RIGHT")
        line.value:SetPoint("RIGHT", 0, 0)
        line.value:SetWidth(106)

        detail.lines[index] = line
        anchor = line
    end

    local note = Theme.CreateLabel(detail, "tiny", "dim")
    note:SetPoint("BOTTOMLEFT", 12, 14)
    note:SetPoint("BOTTOMRIGHT", -12, 14)
    note:SetWordWrap(true)
    note:SetJustifyH("LEFT")
    detail.note = note

    return detail
end

--- Fill the panel's fixed set of lines, hiding the ones this subject does not
--- need. Written as a list rather than as named fields so the two subjects --
--- one item, or everything -- can each say what is worth saying about them.
local function SetLines(detail, lines)
    for index, line in ipairs(detail.lines) do
        local content = lines[index]

        if content then
            line.label:SetText(content[1])
            line.value:SetText(content[2])
            line.value:SetTextColor(Theme.Unpack(content[3] or "text"))
            line:Show()
        else
            line:Hide()
        end
    end
end

--- What the Profit tab reckons one of these is worth, for comparison.
--
-- The whole point of keeping a ledger: the forecast said one thing and the
-- auction house paid another. Nil when the addon has no recipe for the item,
-- which is normal for anything bought rather than crafted.
local function EstimatedUnitRevenue(itemID)
    if not itemID or not ns.Recipes or not ns.Profit then return nil end

    for recipeID, recipe in pairs(ns.Recipes:GetAll()) do
        if recipe.outputItemID == itemID then
            local analysis = ns.Profit:Analyse(recipe.recipeID or recipeID)
            if analysis and analysis.priceable then return analysis.unitRevenue end
            return nil
        end
    end

    return nil
end

local function UpdateDetail(item, totals)
    local detail = widgets.detail
    local lines = {}

    local function Add(label, value, color)
        lines[#lines + 1] = { label, value, color }
    end

    if item then
        detail.title:SetText(ItemLabel(item.itemID, item.name))
        detail.subtitle:SetText(item.lastAt
            and ("last ended %s"):format(Util.FormatAgeAgo(time() - item.lastAt))
            or "nothing dated")

        Add("Sold", ("%d listing%s"):format(item.sold, item.sold == 1 and "" or "s"))

        if item.soldUnits > item.sold then
            Add("Units sold", tostring(item.soldUnits))
        end

        Add("Expired", ("%d listing%s"):format(item.expired, item.expired == 1 and "" or "s"),
            item.expired > 0 and "loss" or "muted")

        if item.cancelled > 0 then
            Add("You cancelled", ("%d listing%s"):format(
                item.cancelled, item.cancelled == 1 and "" or "s"), "muted")
        end

        if item.sellThrough then
            Add("Sell-through", ("%d%%"):format(math.floor(item.sellThrough * 100 + 0.5)),
                item.sellThrough >= 0.5 and "profit" or "loss")
        end

        if item.sold > 0 then
            Add("Taken in", Util.FormatMoney(item.net), "profit")
            Add("Average per sale", Util.FormatMoney(item.net / item.sold))

            if item.cut > 0 then
                Add("Auction cut", Util.FormatMoney(item.cut), "muted")
            end

            local estimate = EstimatedUnitRevenue(item.itemID)
            if estimate then
                Add("Profit tab says", ("%s a unit"):format(
                    Util.FormatMoney(estimate, { short = true })), "muted")
            end

            if item.estimated > 0 then
                Add("Still being paid", ("%d sale%s"):format(
                    item.estimated, item.estimated == 1 and "" or "s"), "warn")
            end
        end

        if item.restored then
            detail.note:SetText("Some of these figures are from before you last quit the game. Only sales, amounts, expiries and gold are kept when you quit, so the auction cut and cancellations here are for this session only.")
        elseif item.soldUnits == item.sold and item.sold > 0 then
            detail.note:SetText("The sale mail does not say how many were in the stack, so a stack of twenty looks the same as a single item. For now, every sale counts as one.")
        else
            detail.note:SetText("")
        end
    else
        detail.title:SetText("Everything")
        detail.subtitle:SetText(ns.Config:GetRealmKey())

        Add("Items sold", ("%d listing%s"):format(totals.sold, totals.sold == 1 and "" or "s"))
        Add("Expired", ("%d listing%s"):format(totals.expired, totals.expired == 1 and "" or "s"),
            totals.expired > 0 and "loss" or "muted")

        if totals.cancelled > 0 then
            Add("You cancelled", ("%d listing%s"):format(
                totals.cancelled, totals.cancelled == 1 and "" or "s"), "muted")
        end

        if totals.sellThrough then
            Add("Sell-through", ("%d%%"):format(math.floor(totals.sellThrough * 100 + 0.5)),
                totals.sellThrough >= 0.5 and "profit" or "loss")
        end

        if totals.sold > 0 then
            Add("Taken in", Util.FormatMoney(totals.net), "profit")
            Add("Average per sale", Util.FormatMoney(totals.net / totals.sold))

            if totals.cut > 0 then
                Add("Auction cut", Util.FormatMoney(totals.cut), "muted")
            end
        end

        Add("Different items", tostring(totals.items), "muted")

        local age = ns.Mail:GetAge()
        Add("Mailbox read", Util.FormatAgeAgo(age), "muted")

        if not ns.Mail:HasReadThisSession() then
            detail.note:SetText("Sales are only recorded when you open a mailbox. Anything that sold since you last opened one is not here yet.")
        else
            detail.note:SetText("Click an item to see how it has done. Sell-through ignores listings you cancelled, since cancelling says nothing about whether it would have sold.")
        end
    end

    SetLines(detail, lines)
end

--------------------------------------------------------------------------------
-- Gathering what to show
--------------------------------------------------------------------------------

--- Everything the ledger holds, as one set of totals.
local function Totals(items)
    local totals = {
        sold = 0, soldUnits = 0, expired = 0, cancelled = 0,
        net = 0, cut = 0, estimated = 0, items = 0, restored = false,
    }

    for _, item in ipairs(items) do
        totals.sold = totals.sold + item.sold
        totals.soldUnits = totals.soldUnits + item.soldUnits
        totals.expired = totals.expired + item.expired
        totals.cancelled = totals.cancelled + item.cancelled
        totals.net = totals.net + item.net
        totals.cut = totals.cut + item.cut
        totals.estimated = totals.estimated + item.estimated
        totals.items = totals.items + 1

        if item.restored then totals.restored = true end
    end

    local judged = totals.sold + totals.expired
    totals.sellThrough = judged > 0 and (totals.sold / judged) or nil

    return totals
end

--- How many sales are in the totals but cannot appear in the event list.
--
-- Carried-over history has no per-event detail, so the Recent view would look
-- emptier than the footer says it is. The rollup is read directly rather than
-- worked out by subtracting this session's sales from the per-item figures:
-- those figures already have this session folded into them, so the subtraction
-- lost a sale for every item that sold this session and had no history behind
-- it. The rollup is the pre-restart half on its own, which is exactly what
-- this is asking for.
local function CarriedOver()
    local rollup = ns.Mail:GetRestoredRollup()
    if not rollup then return 0 end

    local carried = 0
    for _, record in pairs(rollup) do
        carried = carried + (record.sold or 0)
    end

    -- Sales rolled into the history during this session are in the list as
    -- well, so they are not "carried over from before".
    for _, entry in ipairs(ns.Mail:GetLedger().entries) do
        if entry.kind == "sold" and ns.Mail:IsRolledUp(entry) then
            carried = carried - 1
        end
    end

    return math.max(0, carried)
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

local function Refresh()
    if not widgets.list then return end

    awaitingItemData = false

    local query = (state.search or ""):lower()
    local items = ns.Mail:GetItems()
    local totals = Totals(items)

    local data = {}

    if state.view == "visits" then
        local history = ns.MailHaul and ns.MailHaul:GetHistory() or {}

        for index = #history, 1, -1 do
            -- Flagged on a view of it, so nothing is written into saved data.
            local haul = setmetatable({ haul = true }, { __index = history[index] })

            local best = haul.best
            if query == "" or (best and Matches(best.itemID, best.name, query)) then
                data[#data + 1] = haul
            end
        end
    elseif state.view == "item" then
        for _, item in ipairs(items) do
            if Matches(item.itemID, item.name, query) then
                data[#data + 1] = item
            end
        end

        -- What came in, most first. An item that only ever came back sorts to
        -- the bottom by that measure and is still shown: a craft that never
        -- sells is exactly the thing worth seeing.
        table.sort(data, function(a, b)
            if a.net ~= b.net then return a.net > b.net end
            return (a.lastAt or 0) > (b.lastAt or 0)
        end)
    else
        local entries = ns.Mail:GetLedger().entries
        local salesOnly = state.view == "sales"

        -- Walked backwards: the ledger is appended to, so the end of it is the
        -- newest, which is the order this list wants.
        for index = #entries, 1, -1 do
            local entry = entries[index]

            if (not salesOnly or entry.kind == "sold")
                and Matches(entry.itemID, entry.name, query) then
                data[#data + 1] = entry
            end
        end
    end

    widgets.list:SetData(data)

    -- Keep the panel on whatever was selected, across a refresh and across a
    -- change of view. An item selected in the By item view still makes sense
    -- as the subject while looking at the event list.
    local selected

    if state.selected then
        for _, item in ipairs(items) do
            if item.key == state.selected then selected = item break end
        end

        if not selected then state.selected = nil end
    end

    UpdateDetail(selected, totals)

    if #data == 0 then
        widgets.emptyLabel:Show()

        if state.view ~= "visits" and totals.sold == 0 and totals.expired == 0 and totals.cancelled == 0 then
            widgets.emptyLabel:SetText(ns.Mail:HasReadThisSession()
                and "Nothing recorded yet. Sales and expiries are written down when you open the mailbox they arrive in."
                or "Nothing recorded yet. Visit a mailbox after a listing has ended and it will appear here.")
        elseif query ~= "" then
            widgets.emptyLabel:SetText(("Nothing here matches '%s'."):format(state.search))
        elseif state.view == "visits" then
            widgets.emptyLabel:SetText("No mailbox visits yet. Collect mail and each visit is kept here. Click one to see its report again.")
        else
            widgets.emptyLabel:SetText("Nothing sold yet. Switch to 'Recent, all' to see what came back.")
        end
    else
        widgets.emptyLabel:Hide()
    end

    if state.view == "visits" then
        local history = ns.MailHaul and ns.MailHaul:GetHistory() or {}
        local collected = 0
        for _, haul in ipairs(history) do collected = collected + (haul.total or 0) end
        local best = ns.MailHaul and ns.MailHaul:Records() or 0

        widgets.summary:SetText(("%d visit%s  ·  collected %s  ·  best haul %s"):format(
            #history, #history == 1 and "" or "s",
            Util.FormatMoney(collected, { short = true }),
            Util.FormatMoney(best, { short = true })))
        widgets.carried:Hide()
        return
    end

    widgets.summary:SetText(("%d sold  ·  taken in %s%s"):format(
        totals.sold,
        Util.FormatMoney(totals.net, { short = true }),
        totals.sellThrough
            and ("  ·  %d%% sell-through"):format(
                math.floor(totals.sellThrough * 100 + 0.5))
            or ""))

    -- Only in the event views, and only when there is something the list
    -- genuinely cannot show. In the By item view the carried-over figures are
    -- already on screen.
    local carried = (state.view ~= "item") and CarriedOver() or 0

    widgets.carried:SetShown(carried > 0)
    if carried > 0 then
        widgets.carried:SetText(("plus %d sale%s from before you last quit the game. See By item"):format(
            carried, carried == 1 and "" or "s"))
    end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function Build(container)
    local toolbar = CreateFrame("Frame", nil, container)
    toolbar:SetHeight(22)
    toolbar:SetPoint("TOPLEFT", 8, -10)
    toolbar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -DETAIL_WIDTH - 16, -10)

    local search = Widgets.CreateSearchBox(toolbar, "Search sales", function(text)
        state.search = text or ""
        Refresh()
    end)
    search:SetPoint("LEFT", 0, 0)
    search:SetWidth(200)
    widgets.search = search

    local view = Widgets.CreateDropdown(toolbar, VIEWS, function(value)
        state.view = value
        Refresh()
    end, { width = 130 })
    view:SetPoint("RIGHT", 0, 0)
    view:SetValue(state.view)
    widgets.view = view

    local divider = Theme.CreateDivider(container)
    divider:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    divider:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -8)

    local carried = Theme.CreateLabel(container, "tiny", "dim")
    carried:SetPoint("BOTTOMLEFT", 8, 26)
    carried:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 26)
    carried:SetJustifyH("LEFT")
    carried:Hide()
    widgets.carried = carried

    local list = Widgets.CreateScrollList(container, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onEnter = function(row, data)
            if data.haul then
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:SetText("Click to see this visit's report again", 1, 1, 1)
                GameTooltip:Show()
                return
            end
            Widgets.ShowItemOnly(row, data.itemID, data.name)
        end,
        onLeave = function() GameTooltip:Hide() end,
        -- The item the detail pane is showing is lit, as on every other tab.
        isSelected = function(data)
            if data.haul or not state.selected then return false end
            local key = data.key or data.itemID or ("?" .. tostring(data.name or "unknown"))
            return key == state.selected
        end,
        onClick = function(data)
            if data.haul then
                if ns.MailReport then ns.MailReport:Show(data, { replay = true }) end
                return
            end

            -- Both views select the same thing: an item. Clicking one sale
            -- asks about that item, not about that one listing.
            local key = data.key or data.itemID
                or ("?" .. tostring(data.name or "unknown"))

            state.selected = (state.selected == key) and nil or key
            Refresh()
        end,
    })
    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -DETAIL_WIDTH - 16, 42)
    widgets.list = list

    local emptyLabel = Theme.CreateLabel(container, "small", "dim", "CENTER")
    emptyLabel:SetPoint("CENTER", list, "CENTER")
    emptyLabel:SetWidth(340)
    emptyLabel:SetWordWrap(true)
    widgets.emptyLabel = emptyLabel

    local summary = Theme.CreateLabel(container, "small", "text")
    summary:SetPoint("BOTTOMLEFT", 8, 10)
    widgets.summary = summary

    local detail = BuildDetail(container)
    detail:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -8)
    detail:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 8)
    widgets.detail = detail

    -- An item the client has not cached yet draws with no rarity colour and a
    -- placeholder name, and stays that way until something redraws the tab.
    -- A burst of arrivals is coalesced into one pass, and nothing happens at
    -- all unless a row is actually waiting on one.
    local redrawQueued = false

    ns.RegisterEvent(UI, "GET_ITEM_INFO_RECEIVED", function()
        if redrawQueued or not awaitingItemData then return end
        if not widgets.list:IsVisible() then return end

        redrawQueued = true
        C_Timer.After(0.2, function()
            redrawQueued = false
            Refresh()
        end)
    end)
end

-- The mail report's "See all visits" button opens this view.
ns.SalesTab = {
    ShowVisits = function()
        state.view = "visits"
        if widgets.view then widgets.view:SetValue("visits") end
    end,
}

UI:RegisterTab({
    key = "sales",
    text = "Sales",
    order = 6,
    build = Build,
    refresh = Refresh,
})
