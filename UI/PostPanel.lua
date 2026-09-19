-- Blackthornes Tradeskills -- UI/PostPanel.lua
-- The sell list, docked beside Blizzard's auction house.
--
-- Post All can work through a whole bag, so what it is about to sell needs to
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

local PANEL_WIDTH = 300
local ROW_HEIGHT = 30

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function CreateRow(row)
    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("TOPLEFT", 8, -4)
    row.name:SetWidth(PANEL_WIDTH - 90)

    row.detail = Theme.CreateLabel(row, "tiny", "muted")
    row.detail:SetPoint("TOPLEFT", 8, -17)
    row.detail:SetWidth(PANEL_WIDTH - 90)

    row.post = Widgets.CreateButton(row, "List", function()
        if not row.data then return end

        ns.Posting:Request(row.data.itemID, row.data.postQuantity, row.data.unitPrice)
    end, { width = 46, height = 18, primary = true })
    row.post:SetPoint("RIGHT", -8, 0)
end

--- Why a line is a loss, in words the player can act on.
local function LossText(line)
    if line.lossReason == "vendor" then
        return "Below what a vendor would pay for it."
    end
    return "Below what the materials cost."
end

local function UpdateRow(row, line)
    row.name:SetText(line.label)

    -- Quantity and unit price on one line: together they are the decision,
    -- and a commodity posting 63 at once is worth noticing before clicking.
    row.detail:SetText(("%d @ %s  =  %s"):format(
        line.postQuantity,
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
        or ("List %d at %s each."):format(
            line.postQuantity,
            Util.FormatMoney(line.unitPrice or 0, { noColor = true }))
end

local function ShowRowTooltip(row, line)
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetText(line.label, 1, 1, 1)

    GameTooltip:AddDoubleLine("In bags", tostring(line.count), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("Listing", tostring(line.postQuantity), 0.7, 0.7, 0.7, 1, 1, 1)

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

--- Dock to the right of the auction house, matching its height.
function PostPanel:Attach()
    local frame = self:Build()
    local auctionFrame = ns.UI:FindAuctionFrame()

    frame:ClearAllPoints()

    if auctionFrame then
        frame:SetPoint("TOPLEFT", auctionFrame, "TOPRIGHT", 6, 0)
        frame:SetPoint("BOTTOM", auctionFrame, "BOTTOM", 0, 0)
    else
        -- The auction house window is load-on-demand and may not exist yet.
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -120)
        frame:SetHeight(420)
    end

    frame:Show()
    self:Refresh()
end

function PostPanel:Refresh()
    if not self.frame or not self.frame:IsShown() then return end

    local lines = ns.Posting:GetPostable({ includeAll = true })

    self.list:SetData(lines)
    self.empty:SetShown(#lines == 0)

    if #lines == 0 then
        self.empty:SetText(
            "Nothing in your bags with a known price.\n\nScan the auction house so I know what things sell for.")
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

function PostPanel:Hide()
    if self.frame then self.frame:Hide() end
end

function PostPanel:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end
