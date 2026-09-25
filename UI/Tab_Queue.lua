-- Blackthornes Tradeskills -- UI/Tab_Queue.lua
-- Queued crafts on the left, the materials they need on the right.
--
-- These are one screen rather than two tabs on purpose: "what am I making" and
-- "what am I missing" are the same question, and splitting them means bouncing
-- between tabs to answer it.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 24
local MATERIALS_WIDTH = 360

-- Right-aligned columns for the materials panel, laid out from the right edge
-- inward. The AH button occupies the rightmost slot.
local MATERIAL_COLUMNS = {
    { key = "cost", label = "COST", width = 48, offset = -34 },
    { key = "have", label = "HAVE", width = 34, offset = -86 },
    { key = "need", label = "NEED", width = 34, offset = -124 },
}

local MATERIAL_NAME_INSET = -162

local widgets = {}

--------------------------------------------------------------------------------
-- Craft rows
--------------------------------------------------------------------------------

local function CreateCraftRow(row)
    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 8, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -150, 0)

    row.profit = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.profit:SetPoint("RIGHT", -96, 0)
    row.profit:SetWidth(80)

    -- Quantity stepper
    row.minus = Widgets.CreateButton(row, "-", function()
        if not row.data then return end
        ns.Queue:SetQuantity(row.data.recipeID, row.data.quantity - 1)
    end, { width = 18, height = 16 })
    row.minus:SetPoint("RIGHT", -70, 0)

    row.count = Theme.CreateLabel(row, "small", "accent", "CENTER")
    row.count:SetPoint("RIGHT", -46, 0)
    row.count:SetWidth(22)

    row.plus = Widgets.CreateButton(row, "+", function()
        if not row.data then return end
        ns.Queue:SetQuantity(row.data.recipeID, row.data.quantity + 1)
    end, { width = 18, height = 16 })
    row.plus:SetPoint("RIGHT", -24, 0)

    row.remove = Widgets.CreateButton(row, "x", function()
        if not row.data then return end
        ns.Queue:Remove(row.data.recipeID)
    end, { width = 16, height = 16, tooltip = "Remove from queue" })
    row.remove:SetPoint("RIGHT", -4, 0)
end

local function UpdateCraftRow(row, entry)
    local recipe = ns.Recipes:GetAny(entry.recipeID)
    local analysis = ns.Profit:Analyse(entry.recipeID)

    local label = (recipe and recipe.name) or ("recipe " .. entry.recipeID)

    -- Marked so a craft the player did not add directly is explicable.
    if entry.isDependency then
        local parents = ns.Queue:GetDependencyParents(entry)

        label = ("|cff7a8089>|r %s |cff7a8089(for %s)|r"):format(
            label,
            #parents > 0 and table.concat(parents, ", ") or "another craft")
    end

    row.name:SetText(label)

    -- Colour by whether it can be made, since nothing here can start one.
    local ready, reason = ns.Crafting:GetReadiness(entry.recipeID)
    row.count:SetTextColor(Theme.Unpack(ready and "profit" or "muted"))

    -- Derived rows have no controls: their quantity comes from the parents,
    -- so anything set here would be recalculated away on the next change.
    row.minus:SetShown(not entry.isDependency)
    row.plus:SetShown(not entry.isDependency)
    row.remove:SetShown(not entry.isDependency)
    row.count:SetText(tostring(entry.quantity))

    if analysis and analysis.priceable then
        local total = analysis.profit * entry.quantity
        row.profit:SetText(Util.FormatMoney(total, { short = true }))
        row.profit:SetTextColor(Theme.ProfitColor(total))

        -- A craft queued when it was worth 4g and now worth 40s should say so,
        -- rather than silently re-pricing.
        if entry.snapshotProfit and entry.snapshotProfit > 0 then
            local drift = analysis.profit / entry.snapshotProfit
            if drift < 0.6 then
                row.name:SetTextColor(Theme.Unpack("warn"))
                return
            end
        end
        row.name:SetTextColor(Theme.Unpack("text"))
    else
        row.profit:SetText("--")
        row.profit:SetTextColor(Theme.Unpack("dim"))
        row.name:SetTextColor(Theme.Unpack("muted"))
    end
end

--------------------------------------------------------------------------------
-- Material rows
--------------------------------------------------------------------------------

local function CreateMaterialRow(row)
    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 8, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", MATERIAL_NAME_INSET, 0)

    row.cells = {}
    for _, column in ipairs(MATERIAL_COLUMNS) do
        local cell = Theme.CreateLabel(row, "small", "muted", "RIGHT")
        cell:SetPoint("RIGHT", column.offset, 0)
        cell:SetWidth(column.width)
        row.cells[column.key] = cell
    end

    row.search = Widgets.CreateButton(row, "AH", function()
        if row.data then UI:SearchAuctionHouse(row.data.itemID) end
    end, { width = 26, height = 16, tooltip = "Search the auction house for this" })
    row.search:SetPoint("RIGHT", -4, 0)
end

local function UpdateMaterialRow(row, line)
    row.name:SetText(Util.GetItemLabel(line.itemID))

    local cells = row.cells

    -- Need and have as separate columns under their own headings, rather than
    -- a combined "2/5" that has to be decoded. The raw holding is shown here,
    -- surplus and all, because the column heading now says what it means.
    cells.need:SetText(tostring(line.needed))
    cells.need:SetTextColor(Theme.Unpack("muted"))

    cells.have:SetText(tostring(line.have))

    if line.shortfall > 0 then
        cells.have:SetTextColor(Theme.Unpack("loss"))
    elseif line.needsBankTrip then
        -- Owned, but not on you. Amber rather than green: nothing to buy, but
        -- you cannot craft it until you visit the bank.
        cells.have:SetTextColor(Theme.Unpack("warn"))
    else
        cells.have:SetTextColor(Theme.Unpack("profit"))
    end

    if line.shortfall > 0 then
        cells.cost:SetText(line.estimatedCost
            and Util.FormatMoney(line.estimatedCost, { short = true }) or "?")
        cells.cost:SetTextColor(Theme.Unpack(line.fromVendor and "accent" or "muted"))

        row.name:SetTextColor(Theme.Unpack("text"))

        -- Buying a vendor reagent off the auction house is a mistake, so do
        -- not offer the search for it.
        row.search:SetShown(not line.fromVendor)
    else
        cells.cost:SetText(line.needsBankTrip and "in bank" or "")
        cells.cost:SetTextColor(Theme.Unpack("warn"))

        row.name:SetTextColor(Theme.Unpack("muted"))
        row.search:Hide()
    end
end

--- Full numbers on hover, including surplus and anything held by alts.
local function ShowMaterialTooltip(row, line)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(Util.GetItemLabel(line.itemID), 1, 1, 1)

    if line.fromVendor then
        GameTooltip:AddLine(line.vendorLimited
            and "Sold by a vendor (limited stock)" or "Sold by a vendor", 0.78, 0.64, 0.30)
    end

    GameTooltip:AddDoubleLine("Required", tostring(line.needed), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("In bags", tostring(line.inBags or 0), 0.7, 0.7, 0.7, 1, 1, 1)

    if (line.inBank or 0) > 0 then
        GameTooltip:AddDoubleLine("In bank", tostring(line.inBank),
            0.7, 0.7, 0.7, 0.91, 0.76, 0.35)
    end

    if line.needsBankTrip then
        GameTooltip:AddLine("You own enough, but some is in the bank.", 0.91, 0.76, 0.35)
    end

    if line.have > line.needed then
        GameTooltip:AddDoubleLine("Surplus", tostring(line.have - line.needed),
            0.7, 0.7, 0.7, 0.31, 0.82, 0.55)
    end

    if line.shortfall > 0 then
        GameTooltip:AddDoubleLine("Still needed", tostring(line.shortfall),
            0.7, 0.7, 0.7, 0.9, 0.38, 0.31)

        if line.unitCost then
            GameTooltip:AddDoubleLine("Cost to buy",
                Util.FormatMoney(line.estimatedCost, { noColor = true }),
                0.7, 0.7, 0.7, 1, 1, 1)
        else
            GameTooltip:AddLine("No auction data for this material", 0.9, 0.38, 0.31)
        end
    end

    -- Alt-held stock is never counted as yours automatically: it is not in
    -- reach of the craft you are about to make.
    if line.onAlts and line.onAlts > 0 then
        GameTooltip:AddDoubleLine("On other characters", tostring(line.onAlts),
            0.7, 0.7, 0.7, 0.91, 0.76, 0.35)
    end

    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

--- Warn when bank counts have not been refreshed this session.
local function UpdateBankNote()
    local note = widgets.bankNote
    if not note then return end

    -- Nothing queued means nothing to be wrong about; do not nag.
    if ns.Inventory:HasReadBankThisSession() or ns.Queue:Count() == 0 then
        note:SetText("")
        return
    end

    local age = ns.Inventory:GetBankAge()

    if age then
        note:SetText(("Bank not checked this session, so using what it held %s ago.")
            :format(Util.FormatAge(age)))
    else
        note:SetText("Bank never checked, so HAVE counts bags only.")
    end
end

--- Keep the Craft button honest about what it will do, and why it cannot.
-- @return true when the button was set to open a profession window
local function SetCraftButton(button, label)
    button.opensProfession = false

    if ns.Crafting:IsBusy() then
        button:SetText("Stop crafting")
        button:SetEnabledState(true)
        button.tooltipText = "Stop after the current craft"
        label:SetText("crafting...")
        label:SetTextColor(Theme.Unpack("profit"))
        return
    end

    if ns.Queue:Count() == 0 then
        button:SetText("Craft next")
        button:SetEnabledState(false)
        button.tooltipText = "Nothing is queued"
        label:SetText("")
        return
    end

    local ready, total = ns.Crafting:GetQueueReadiness()
    local entry = ns.Crafting:GetNextReady()

    if not entry then
        button:SetText("Craft next")
        button:SetEnabledState(false)

        -- Report the first entry's actual obstacle rather than a generic one.
        local _, reason = ns.Crafting:GetReadiness(ns.Queue:GetAll()[1].recipeID)

        button.tooltipText = reason or "Nothing here can be made yet"
        label:SetText(reason or "nothing ready")
        label:SetTextColor(Theme.Unpack("warn"))
        return
    end

    local recipe = ns.Recipes:GetAny(entry.recipeID)
    local canMake = math.min(entry.quantity, ns.Profit:GetCraftableCount(entry.recipeID))

    -- A craft only starts from its own profession window. When that is not
    -- the one open, this click opens it instead: the game lets a player's
    -- click cast the profession, which addon code alone may not do.
    local opener = ns.ProfessionOpener
    if opener and not opener:WindowShowsRecipe(entry.recipeID) then
        local profession = opener:ProfessionFor(entry.recipeID)

        if profession then
            button:SetText(("Open %s"):format(profession.name))
            button:SetEnabledState(true)
            button.tooltipText = ("Opens your %s window. Click again to craft %dx %s.")
                :format(profession.name, canMake, (recipe and recipe.name) or "item")

            label:SetText(("%d of %d ready -- click to open %s"):format(ready, total, profession.name))
            label:SetTextColor(Theme.Unpack("accent"))

            button.opensProfession = true
            opener:Arm(button, profession, entry.recipeID)
            return true
        end
    end

    button:SetText(("Craft %dx %s"):format(canMake, (recipe and recipe.name) or "item"))
    button:SetEnabledState(true)
    button.tooltipText = "One click makes every craft in this entry"

    label:SetText(("%d of %d ready"):format(ready, total))
    label:SetTextColor(Theme.Unpack("profit"))

    -- Crafting works without the window open on some clients and not others;
    -- say so rather than letting a click quietly do nothing.
    if not ns.Crafting.isTradeSkillOpen then
        label:SetText(("%d of %d ready. Open your profession"):format(ready, total))
        label:SetTextColor(Theme.Unpack("accent"))
    end
end

local function UpdateCraftStatus()
    local button, label = widgets.craftButton, widgets.craftStatus
    if not button then return end

    -- Every other state wants the click to reach the craft button itself.
    if not SetCraftButton(button, label) and ns.ProfessionOpener then
        ns.ProfessionOpener:Disarm()
    end
end

local function Refresh()
    if not widgets.craftList then return end

    local queue = ns.Queue:GetAll()

    -- Copy so sorting for display never reorders the stored queue.
    local entries = {}
    for index, entry in ipairs(queue) do
        entries[index] = entry
    end

    widgets.craftList:SetData(entries)
    widgets.materialList:SetData(ns.Queue:GetShoppingList())

    widgets.emptyLabel:SetShown(#entries == 0)

    local totals = ns.Queue:GetTotals()
    local shoppingCost, unknown = ns.Queue:GetShoppingTotal()

    UpdateCraftStatus()
    UpdateBankNote()

    if #entries == 0 then
        widgets.summaryLabel:SetText("")
        widgets.shoppingLabel:SetText("")
        return
    end

    widgets.summaryLabel:SetText(("%d craft%s  ·  materials %s  ·  profit %s%s"):format(
        totals.crafts, totals.crafts == 1 and "" or "s",
        Util.FormatMoney(totals.cost, { short = true }),
        Util.FormatMoney(totals.profit, { short = true }),
        totals.priceable and "" or "  (some unpriced)"))

    widgets.shoppingLabel:SetText(("To buy: %s%s"):format(
        Util.FormatMoney(shoppingCost, { short = true }),
        unknown > 0 and ("  (+%d unpriced)"):format(unknown) or ""))
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function Build(container)
    local heading = Theme.CreateLabel(container, "tiny", "dim")
    heading:SetPoint("TOPLEFT", 8, -10)
    heading:SetText("QUEUED CRAFTS")

    local clear = Widgets.CreateButton(container, "Clear all", function()
        ns.Queue:Clear()
    end, { width = 70, height = 18 })
    clear:SetPoint("TOPRIGHT", container, "TOPRIGHT", -MATERIALS_WIDTH - 16, -8)

    local divider = Theme.CreateDivider(container)
    divider:SetPoint("TOPLEFT", 8, -26)
    divider:SetPoint("TOPRIGHT", container, "TOPRIGHT", -MATERIALS_WIDTH - 16, -26)

    local craftList = Widgets.CreateScrollList(container, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateCraftRow,
        updateRow = UpdateCraftRow,
    })
    craftList:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    craftList:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -MATERIALS_WIDTH - 16, 62)
    widgets.craftList = craftList

    -- Crafting needs a hardware event, so this is a real click each time:
    -- one click runs one queue entry to completion.
    widgets.craftButton = Widgets.CreateButton(container, "Craft next", function()
        if ns.Crafting:IsBusy() then
            ns.Crafting:Stop()
        else
            local entry = ns.Crafting:GetNextReady()
            if widgets.craftButton.opensProfession and ns.ProfessionOpener then
                -- The secure Open button should have taken this click.
                ns.ProfessionOpener:MissedClick()
            elseif entry then
                ns.Crafting:Start(entry.recipeID, entry.quantity)
            end
        end

        Refresh()
    end, { width = 220, height = 26, primary = true })
    widgets.craftButton:SetPoint("BOTTOMLEFT", 8, 32)

    widgets.craftStatus = Theme.CreateLabel(container, "small", "accent")
    widgets.craftStatus:SetPoint("LEFT", widgets.craftButton, "RIGHT", 10, 0)
    widgets.craftStatus:SetWidth(320)


    local emptyLabel = Theme.CreateLabel(container, "small", "dim", "CENTER")
    emptyLabel:SetPoint("CENTER", craftList, "CENTER")
    emptyLabel:SetWidth(300)
    emptyLabel:SetWordWrap(true)
    emptyLabel:SetText("Nothing queued.\nRight-click a craft on the Profit tab to add one.")
    widgets.emptyLabel = emptyLabel

    local summaryLabel = Theme.CreateLabel(container, "small", "text")
    summaryLabel:SetPoint("BOTTOMLEFT", 8, 10)
    widgets.summaryLabel = summaryLabel

    -- Materials panel
    local materials = Theme.CreatePanel(container, "window")
    materials:SetPoint("TOPRIGHT", -8, -8)
    materials:SetPoint("BOTTOMRIGHT", -8, 8)
    materials:SetWidth(MATERIALS_WIDTH)

    local materialsHeading = Theme.CreateLabel(materials, "tiny", "dim")
    materialsHeading:SetPoint("TOPLEFT", 10, -10)
    materialsHeading:SetText("MATERIALS NEEDED")

    -- Column headings, so NEED and HAVE are labelled rather than inferred.
    local columnHeader = CreateFrame("Frame", nil, materials)
    columnHeader:SetPoint("TOPLEFT", 10, -28)
    columnHeader:SetPoint("TOPRIGHT", -10, -28)
    columnHeader:SetHeight(14)

    local nameHeading = Theme.CreateLabel(columnHeader, "tiny", "dim")
    nameHeading:SetPoint("LEFT", 8, 0)
    nameHeading:SetText("MATERIAL")

    for _, column in ipairs(MATERIAL_COLUMNS) do
        local heading = Theme.CreateLabel(columnHeader, "tiny", "dim", "RIGHT")
        heading:SetPoint("RIGHT", column.offset, 0)
        heading:SetWidth(column.width)
        heading:SetText(column.label)
    end

    local materialsDivider = Theme.CreateDivider(materials)
    materialsDivider:SetPoint("TOPLEFT", 10, -45)
    materialsDivider:SetPoint("TOPRIGHT", -10, -45)

    local materialList = Widgets.CreateScrollList(materials, {
        rowHeight = 20,
        createRow = CreateMaterialRow,
        updateRow = UpdateMaterialRow,
        onEnter = ShowMaterialTooltip,
        onLeave = function() GameTooltip:Hide() end,
    })
    materialList:SetPoint("TOPLEFT", materialsDivider, "BOTTOMLEFT", 0, -4)
    materialList:SetPoint("BOTTOMRIGHT", materials, "BOTTOMRIGHT", -10, 48)
    widgets.materialList = materialList

    -- Bank stock counts toward HAVE, so if the bank has not been opened this
    -- session those numbers may be understated. Say so rather than letting
    -- the player trust a stale snapshot.
    local bankNote = Theme.CreateLabel(materials, "tiny", "warn")
    bankNote:SetPoint("BOTTOMLEFT", 10, 26)
    bankNote:SetPoint("BOTTOMRIGHT", -10, 26)
    bankNote:SetWordWrap(true)
    bankNote:SetJustifyV("BOTTOM")
    widgets.bankNote = bankNote

    local shoppingLabel = Theme.CreateLabel(materials, "small", "text")
    shoppingLabel:SetPoint("BOTTOMLEFT", 10, 10)
    widgets.shoppingLabel = shoppingLabel
end

UI:RegisterTab({
    key = "queue",
    text = "Queue",
    order = 2,
    build = Build,
    refresh = Refresh,
})

function UI:OnQueueUpdated()
    -- The craft pane beside the profession window shows the same queue, and
    -- is usually the thing that just changed it.
    if ns.CraftPanel then ns.CraftPanel:RequestRefresh() end

    if self.activeTab == "queue" then
        Refresh()
    else
        -- The Gather tab is derived from the queue, so it goes stale too.
        self:RefreshActiveTab()
    end
end
