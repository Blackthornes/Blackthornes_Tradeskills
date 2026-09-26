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

-- Right margin, button, gap, quantity box, gap before the text.
local TEXT_INSET = 8 + BUTTON_WIDTH + 6 + QUANTITY_WIDTH + 10

-- Clear of the auction window's bevelled edge without opening a gap you could
-- see the world through.
local PANEL_GAP = 6

-- Only used when Blizzard's auction window cannot be found at all.
local PANEL_FALLBACK_HEIGHT = 420

-- Short enough to still show a few rows. Below this the panel stops giving
-- way to the main window: at that point there is no arrangement that fits,
-- and a panel squeezed to nothing is worse than one that overlaps.
local PANEL_MIN_HEIGHT = 200

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
local function CreateRow(row)
    local textWidth = PANEL_WIDTH - TEXT_INSET - 8

    -- The item's icon at the start of the name line, as the bags draw it.
    row.icon = Theme.CreateItemIcon(row, 13)
    row.icon:SetPoint("TOPLEFT", 8, -3)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("TOPLEFT", 25, -4)
    row.name:SetWidth(textWidth - 17)

    row.detail = Theme.CreateLabel(row, "tiny", "muted")
    row.detail:SetPoint("TOPLEFT", 8, -17)
    row.detail:SetWidth(textWidth)

    row.post = Widgets.CreateButton(row, "List", function()
        if not row.data then return end

        ns.Posting:Request(row.data.itemID, row.data.postQuantity, row.data.unitPrice)
    end, { width = BUTTON_WIDTH, height = 18, primary = true })
    row.post:SetPoint("RIGHT", -8, 0)

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
end

--- Why a line is a loss, in words the player can act on.
local function LossText(line)
    if line.lossReason == "vendor" then
        return "Below what a vendor would pay for it."
    end
    return "Below what the materials cost."
end

function UpdateRow(row, line)
    row.name:SetText(line.label)
    Theme.SetItemIcon(row.icon, line.itemID)

    local maxQuantity = line.maxQuantity or line.count or 1

    -- Not while it is being typed into: overwriting someone mid-number is how
    -- a field ends up refusing to accept what they meant.
    if not BeingTyped(row.quantity) then
        row.quantity:SetLimits(1, math.max(1, maxQuantity))
        row.quantity:SetValue(line.postQuantity or maxQuantity, true)
    end

    -- Quantity and unit price on one line: together they are the decision,
    -- and a commodity posting 63 at once is worth noticing before clicking.
    -- Listing part of a stack says so, since "7 @ 6c" out of 20 in the bag
    -- reads the same as all of them otherwise.
    row.detail:SetText(("%d%s @ %s  =  %s"):format(
        line.postQuantity,
        line.postQuantity < maxQuantity and (" of " .. maxQuantity) or "",
        Util.FormatMoney(line.unitPrice, { noColor = true, short = true }),
        Util.FormatMoney(line.postTotal or 0, { noColor = true, short = true })))

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

        row.detail:SetTextColor(Theme.Unpack("muted"))
    end

    row.post:SetEnabledState(line.unitPrice ~= nil)

    row.post.tooltipText = line.atALoss
        and LossText(line)
        or ("List %d of %d at %s each."):format(
            line.postQuantity, maxQuantity,
            Util.FormatMoney(line.unitPrice or 0, { noColor = true }))
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

    if line.vendorPrice then
        GameTooltip:AddDoubleLine("Vendor pays",
            Util.FormatMoney(line.vendorPrice, { noColor = true }), 0.7, 0.7, 0.7, 1, 1, 1)
    end

    GameTooltip:AddLine(line.isCommodity
        and "Commodity: sells from every bag at once"
        or "Item auction: one stack at a time", 0.5, 0.5, 0.5)

    GameTooltip:AddLine("Type in the box to list fewer than that.", 0.5, 0.5, 0.5)

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
    Theme.AddGameOutline(frame, { style = "dialog", color = "natural" })

    local title = Theme.CreateLabel(frame, "normal", "accent")
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetText("Ready to sell")

    local summary = Theme.CreateLabel(frame, "tiny", "muted")
    summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    summary:SetWidth(PANEL_WIDTH - 28)
    self.summary = summary

    local divider = Theme.CreateDivider(frame)
    divider:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -6)
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, 0)

    local list = Widgets.CreateScrollList(frame, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onEnter = ShowRowTooltip,
        onLeave = function() GameTooltip:Hide() end,
    })
    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    self.list = list

    local empty = Theme.CreateLabel(frame, "small", "dim", "CENTER")
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
function PostPanel:DesiredHeight(auctionFrame)
    local top, bottom, right =
        auctionFrame:GetTop(), auctionFrame:GetBottom(), auctionFrame:GetRight()

    if not top or not bottom or not right then return nil end

    local window = ns.UI and ns.UI.window

    if window and window:IsShown() then
        local windowTop, windowLeft, windowRight =
            window:GetTop(), window:GetLeft(), window:GetRight()

        -- Only when the two really do share screen space. The main window is
        -- movable, so most of the time it is somewhere else entirely.
        if windowTop and windowLeft and windowRight then
            local left = right + PANEL_GAP

            if windowRight > left and windowLeft < left + PANEL_WIDTH
                and windowTop > bottom then
                bottom = windowTop + PANEL_GAP
            end
        end
    end

    return math.max(top - bottom, PANEL_MIN_HEIGHT)
end

--- Dock to the right of the auction house, as tall as there is room for.
function PostPanel:Attach()
    local frame = self:Build()
    local auctionFrame = ns.UI:FindAuctionFrame()

    frame:ClearAllPoints()

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
        frame:SetHeight(self:DesiredHeight(auctionFrame) or PANEL_FALLBACK_HEIGHT)
    else
        -- The auction house window is load-on-demand and may not exist yet.
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -120)
        frame:SetHeight(PANEL_FALLBACK_HEIGHT)
    end

    frame:Show()
    self:Refresh()
end

--- Re-measure after the main window is opened, closed or dragged.
function PostPanel:Reflow()
    if not self.frame or not self.frame:IsShown() then return end

    local auctionFrame = ns.UI:FindAuctionFrame()
    if not auctionFrame then return end

    local height = self:DesiredHeight(auctionFrame)

    -- Only when it actually moved. This runs on the auction house ticker, and
    -- setting the height every second would relayout the list for nothing.
    if height and math.abs(height - self.frame:GetHeight()) > 0.5 then
        self.frame:SetHeight(height)
    end
end

function PostPanel:Refresh()
    if not self.frame or not self.frame:IsShown() then return end

    -- Cheap, and it catches the main window being dragged, which has no event.
    self:Reflow()

    local lines = ns.Posting:GetPostable({ includeAll = true })

    self.list:SetData(lines)
    self.empty:SetShown(#lines == 0)

    if #lines == 0 then
        self.empty:SetText(
            "Nothing in your bags with a known price.\n\nScan the auction house to find out what things sell for.")
        self.summary:SetText("")
        return
    end

    local total, losses = 0, 0
    for _, line in ipairs(lines) do
        total = total + (line.postTotal or 0)
        if line.atALoss then losses = losses + 1 end
    end

    self.summary:SetText(("%d item%s, about %s%s"):format(
        #lines, #lines == 1 and "" or "s",
        Util.FormatMoney(total, { noColor = true, short = true }),
        losses > 0 and (("  ·  %d at a loss"):format(losses)) or ""))
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
            Apply(row.post, "List", seconds, reason)
        end
    end
end

function PostPanel:Hide()
    if self.frame then self.frame:Hide() end
end

function PostPanel:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end
