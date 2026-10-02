-- Blackthornes Tradeskills -- UI/Tab_Settings.lua
-- The knobs that change which crafts come out on top.
--
-- Each one shows what it actually does rather than just its name: several of
-- these silently reshuffle the whole profit table, and a setting you cannot
-- reason about is worse than no setting.
--
-- Layout rule: a row is [label ......... control] on one line, with its
-- description on its own line underneath spanning the full column. Descriptions
-- are kept short enough to fit that single line, so row heights stay fixed and
-- nothing can overlap the control beside it.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local COLUMN_WIDTH = 400
local COLUMN_ONE_X = 16
local COLUMN_TWO_X = 452

-- Wide enough for the longest label ("Recommend selling at a loss"), with the
-- widest control ("Charge market price") still inside the column.
local LABEL_WIDTH = 228
local CONTROL_X = 240

local ROW_GAP = -8
local SECTION_GAP = -22

local widgets = {}

--------------------------------------------------------------------------------
-- Layout helpers
--------------------------------------------------------------------------------

--- Section heading with a rule underneath. Returns a frame to anchor rows to.
local function CreateSection(parent, text, opts)
    opts = opts or {}

    local section = CreateFrame("Frame", nil, parent)
    section:SetSize(COLUMN_WIDTH, 20)

    if opts.anchor then
        section:SetPoint("TOPLEFT", opts.anchor, "BOTTOMLEFT", 0, SECTION_GAP)
    else
        section:SetPoint("TOPLEFT", opts.x or COLUMN_ONE_X, opts.y or -16)
    end

    local heading = Theme.CreateLabel(section, "tiny", "accent")
    heading:SetPoint("TOPLEFT", 0, 0)
    heading:SetText(text)

    local divider = Theme.CreateDivider(section)
    divider:SetPoint("TOPLEFT", 0, -14)
    divider:SetWidth(COLUMN_WIDTH)

    return section
end

--- One setting: label and control on a line, description beneath it.
-- Returns the row frame; anchor the control at CONTROL_X inside it.
local function CreateRow(parent, anchor, labelText, description)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, ROW_GAP)
    row:SetSize(COLUMN_WIDTH, description and 40 or 24)

    -- Wrapped rather than cut off should a label still outgrow its room at
    -- the player's font; the description then starts under its last line.
    local label = Theme.CreateLabel(row, "small", "text")
    label:SetPoint("TOPLEFT", 0, -4)
    label:SetWidth(LABEL_WIDTH)
    label:SetWordWrap(true)
    label:SetText(labelText)

    local top = 24
    local labelHeight = label.GetStringHeight and label:GetStringHeight() or 0
    if type(labelHeight) == "number" and labelHeight > 16 then
        top = math.ceil(4 + labelHeight + 6)
        row:SetHeight(math.max(row:GetHeight() or 0, top))
    end

    if description then
        -- "muted" rather than "dim": the small print says what each setting
        -- does, and "dim" was hard to read on the panel.
        local hint = Theme.CreateLabel(row, "tiny", "muted")
        hint:SetPoint("TOPLEFT", 0, -top)
        hint:SetWidth(COLUMN_WIDTH)
        -- Wrapped, with the row grown to fit: on one line the longer ones
        -- (Undercut by, Minimum profit) were cut off halfway with "...".
        hint:SetWordWrap(true)
        hint:SetText(description)

        local height = hint.GetStringHeight and hint:GetStringHeight() or 0
        if type(height) == "number" and height > 0 then
            row:SetHeight(math.max(40, top + math.ceil(height) + 2))
        end
    end

    return row
end

--- Small unit label sitting to the right of a control.
local function AddUnit(row, control, text)
    local unit = Theme.CreateLabel(row, "small", "muted")
    unit:SetPoint("LEFT", control, "RIGHT", 6, 0)
    unit:SetText(text)
    return unit
end

--- Widen a button to its label when the label, measured at the player's
--- font, needs more room than the button was given: "Remove old prices"
--- and "Reset to defaults" ended in "..." on 140-pixel buttons.
local function FitButton(button)
    local width = Theme.TextWidth(button.label)
    local have = button:GetWidth()
    if width and type(have) == "number" and width + 16 > have then
        button:SetWidth(math.ceil(width) + 16)
    end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function Build(outer)
    local Config = ns.Config

    -- This page is taller than the window at most resolutions, so everything
    -- is built into a scrolling child rather than straight onto the tab.
    -- Nothing below changes: the controls anchor to `container` either way.
    local scroll = Widgets.CreateScrollFrame(outer, { step = 40 })
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -14, 0)
    widgets.scroll = scroll

    local container = scroll.content

    ----------------------------------------------------------------------------
    -- Column one: pricing and filters
    ----------------------------------------------------------------------------

    local pricing = CreateSection(container, "PRICING", { x = COLUMN_ONE_X, y = -16 })

    local undercutRow = CreateRow(container, pricing, "Undercut by",
        "Your posting price is the cheapest rival listing minus this. " ..
        "Stackable goods only: gear and bags can only be priced in whole " ..
        "silver, so those match the cheapest rival unless dropping a full " ..
        "silver still leaves the minimum profit below.")

    widgets.undercut = Widgets.CreateNumberBox(undercutRow, {
        width = 70, min = 0, max = 1000000,
        onChange = function(value)
            Config:Set("undercutCopper", value)
            UI:RefreshActiveTab()
        end,
    })
    widgets.undercut:SetPoint("TOPLEFT", CONTROL_X, 0)
    AddUnit(undercutRow, widgets.undercut, "copper")

    local cutRow = CreateRow(container, undercutRow, "Auction house cut",
        "The share of each sale the auction house keeps.")

    widgets.cut = Widgets.CreateNumberBox(cutRow, {
        width = 70, min = 0, max = 100, decimals = 1,
        onChange = function(value)
            Config:Set("auctionCut", value / 100)
            UI:RefreshActiveTab()
        end,
    })
    widgets.cut:SetPoint("TOPLEFT", CONTROL_X, 0)
    AddUnit(cutRow, widgets.cut, "%")

    local unscannedRow = CreateRow(container, cutRow, "Markup with no competition",
        "When nobody else is listing one (never scanned, or every listing is " ..
        "yours), the price is your material cost plus this, never below market " ..
        "value. It is shown as an estimate and never saved as a real price.")

    widgets.unscannedMarkup = Widgets.CreateNumberBox(unscannedRow, {
        width = 70, min = 0, max = 1000,
        onChange = function(value)
            Config:Set("unscannedMarkupPercent", value)
            UI:RefreshActiveTab()
        end,
    })
    widgets.unscannedMarkup:SetPoint("TOPLEFT", CONTROL_X, 0)
    AddUnit(unscannedRow, widgets.unscannedMarkup, "% markup")

    local unscannedOnRow = CreateRow(container, unscannedRow, "Use that markup",
        "Off: crafts with no scanned price have no price at all, and your own listings hold at market value.")

    widgets.priceUnscanned = Widgets.CreateCheckbox(unscannedOnRow, "Enabled", function(checked)
        Config:Set("priceUnscannedCrafts", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.priceUnscanned:SetPoint("TOPLEFT", CONTROL_X, -2)

    local ownedRow = CreateRow(container, unscannedOnRow, "Materials you already own",
        "On: they still cost market price. Off: they count as free.")

    widgets.valueOwned = Widgets.CreateCheckbox(ownedRow, "Charge market price", function(checked)
        Config:Set("valueOwnedMaterials", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.valueOwned:SetPoint("TOPLEFT", CONTROL_X, -2)

    local postedRow = CreateRow(container, ownedRow, "Keep in stock per item",
        "Counts listings, bags and bank together. 0 = no limit. Equipped gear is not counted.")

    widgets.maxPosted = Widgets.CreateNumberBox(postedRow, {
        width = 70, min = 0, max = 999,
        onChange = function(value)
            Config:Set("maxPostedPerItem", value)
            UI:RefreshActiveTab()
        end,
    })
    widgets.maxPosted:SetPoint("TOPLEFT", CONTROL_X, 0)

    widgets.maxPostedHint = Theme.CreateLabel(postedRow, "small", "muted")
    widgets.maxPostedHint:SetPoint("LEFT", widgets.maxPosted, "RIGHT", 6, 0)
    widgets.maxPostedHint:SetWidth(120)

    local hideMaxedRow = CreateRow(container, postedRow, "Hide maxed crafts",
        "Off: they still appear, marked as at their limit.")

    widgets.hideMaxed = Widgets.CreateCheckbox(hideMaxedRow, "Hide them", function(checked)
        Config:Set("hideAtPostLimit", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.hideMaxed:SetPoint("TOPLEFT", CONTROL_X, -2)

    local subCraftRow = CreateRow(container, hideMaxedRow, "Queue sub-crafts",
        "Also queue materials that are cheaper to make than to buy.")

    widgets.subCrafts = Widgets.CreateCheckbox(subCraftRow, "Queue them", function(checked)
        Config:Set("autoQueueSubCrafts", checked)

        -- Sub-crafts are only worked out when the queue changes, so unticking
        -- this left them queued (and ticking it queued none) until then.
        ns.Queue:RebuildDependencies()
        ns.Queue:Notify()
    end, true)
    widgets.subCrafts:SetPoint("TOPLEFT", CONTROL_X, -2)

    local altCraftRow = CreateRow(container, subCraftRow, "Suggest other characters",
        "Point out materials one of your other characters can make for less than buying them.")

    widgets.altCrafts = Widgets.CreateCheckbox(altCraftRow, "Suggest swapping", function(checked)
        Config:Set("suggestOtherCharacters", checked)
        UI:RefreshActiveTab()
    end, true)
    widgets.altCrafts:SetPoint("TOPLEFT", CONTROL_X, -2)

    local lossRow = CreateRow(container, altCraftRow, "Recommend selling at a loss",
        "Off: the Post tab shows them in red but will not list them.")

    widgets.allowLoss = Widgets.CreateCheckbox(lossRow, "Recommend anyway", function(checked)
        Config:Set("allowPostingAtALoss", checked)
        UI:RefreshActiveTab()
    end, false)
    widgets.allowLoss:SetPoint("TOPLEFT", CONTROL_X, -2)

    local confirmRow = CreateRow(container, lossRow, "Confirm before each listing",
        "Off: clicking List or Post Crafted lists immediately, with no prompt.")

    widgets.confirmPost = Widgets.CreateCheckbox(confirmRow, "Ask first", function(checked)
        Config:Set("confirmBeforePosting", checked)
    end, true)
    widgets.confirmPost:SetPoint("TOPLEFT", CONTROL_X, -2)

    local verifyRow = CreateRow(container, confirmRow, "Check price before listing",
        "Searches the auction house for that one item first, so you undercut the price as it is now.")

    widgets.verifyPrice = Widgets.CreateCheckbox(verifyRow, "Check first", function(checked)
        Config:Set("verifyPriceBeforePosting", checked)
    end, true)
    widgets.verifyPrice:SetPoint("TOPLEFT", CONTROL_X, -2)

    local saleAlarmRow = CreateRow(container, verifyRow, "Sound when an auction sells",
        "Plays an alarm as soon as one of your auctions sells, wherever you are.")

    widgets.saleAlarm = Widgets.CreateCheckbox(saleAlarmRow, "Enabled", function(checked)
        Config:Set("saleAlarm", checked)
    end, true)
    widgets.saleAlarm:SetPoint("TOPLEFT", CONTROL_X, -2)

    local saleAlarmTest = Widgets.CreateButton(saleAlarmRow, "Test", function()
        if ns.SaleAlarm then ns.SaleAlarm:Play() end
    end, { width = 60, height = 20, tooltip = "Play the sale alarm now" })
    saleAlarmTest:SetPoint("TOPLEFT", CONTROL_X + 100, -2)

    local mailReportRow = CreateRow(container, saleAlarmRow, "Report after collecting mail",
        "Counts up what you collected at the mailbox and shows it when you walk away, with your best sale.")

    widgets.mailReport = Widgets.CreateCheckbox(mailReportRow, "Enabled", function(checked)
        Config:Set("mailReport", checked)
    end, true)
    widgets.mailReport:SetPoint("TOPLEFT", CONTROL_X, -2)

    local mailReportTest = Widgets.CreateButton(mailReportRow, "Preview", function()
        if ns.MailReport and ns.MailHaul then ns.MailReport:Show(ns.MailHaul:Sample()) end
    end, { width = 70, height = 20, tooltip = "Show a sample report" })
    mailReportTest:SetPoint("TOPLEFT", CONTROL_X + 100, -2)

    local scanSoundsRow = CreateRow(container, mailReportRow, "Sound when a scan finishes",
        "Plays a chime when an auction house scan finishes, and another when it finds disenchant or vendor deals.")

    widgets.scanSounds = Widgets.CreateCheckbox(scanSoundsRow, "Enabled", function(checked)
        Config:Set("scanSounds", checked)
    end, true)
    widgets.scanSounds:SetPoint("TOPLEFT", CONTROL_X, -2)

    local filters = CreateSection(container, "FILTERS", { anchor = scanSoundsRow })

    local profitRow = CreateRow(container, filters, "Minimum profit",
        "Crafts that make less than this are hidden from the Profit tab. " ..
        "For gear and bags, which are priced in whole silver, it also " ..
        "decides whether to undercut by a silver or just match the cheapest rival.")

    widgets.minProfit = Widgets.CreateNumberBox(profitRow, {
        width = 70, min = 0, max = 1000000,
        onChange = function(value)
            -- Entered in silver: copper is unusable at realistic values.
            Config:Set("minProfit", value * 100)
            widgets.minProfitPreview:SetText(Util.FormatMoney(value * 100, { short = true }))
            UI:RefreshActiveTab()
        end,
    })
    widgets.minProfit:SetPoint("TOPLEFT", CONTROL_X, 0)

    widgets.minProfitPreview = Theme.CreateLabel(profitRow, "small", "muted")
    widgets.minProfitPreview:SetPoint("LEFT", widgets.minProfit, "RIGHT", 6, 0)
    widgets.minProfitPreview:SetWidth(100)

    local marginRow = CreateRow(container, profitRow, "Minimum margin",
        "Profit as a share of the sale price.")

    widgets.minMargin = Widgets.CreateNumberBox(marginRow, {
        width = 70, min = 0, max = 100,
        onChange = function(value)
            Config:Set("minMarginPercent", value)
            UI:RefreshActiveTab()
        end,
    })
    widgets.minMargin:SetPoint("TOPLEFT", CONTROL_X, 0)
    AddUnit(marginRow, widgets.minMargin, "%")

    local staleRow = CreateRow(container, marginRow, "Prices go stale after",
        "Older prices are greyed out, but still used.")

    widgets.stale = Widgets.CreateDropdown(staleRow, {
        { text = "12 hours", value = 12 * 3600 },
        { text = "24 hours", value = 24 * 3600 },
        { text = "2 days", value = 48 * 3600 },
        { text = "7 days", value = 7 * 24 * 3600 },
    }, function(value)
        Config:Set("staleAfterSeconds", value)
        UI:RefreshActiveTab()
    end, { width = 110 })
    widgets.stale:SetPoint("TOPLEFT", CONTROL_X, 0)

    ----------------------------------------------------------------------------
    -- Column two: data and advanced
    ----------------------------------------------------------------------------

    local data = CreateSection(container, "DATA", { x = COLUMN_TWO_X, y = -16 })

    -- All four wrap: "last scan 3h ago (stopped at the page limit)" and the
    -- bank and auction warnings are longer than the column, and were cut
    -- off. Refresh measures the page after setting them.
    widgets.dataSummary = Theme.CreateLabel(container, "small", "text")
    widgets.dataSummary:SetPoint("TOPLEFT", data, "BOTTOMLEFT", 0, -6)
    widgets.dataSummary:SetWidth(COLUMN_WIDTH)
    widgets.dataSummary:SetWordWrap(true)

    widgets.recipeSummary = Theme.CreateLabel(container, "small", "text")
    widgets.recipeSummary:SetPoint("TOPLEFT", widgets.dataSummary, "BOTTOMLEFT", 0, -4)
    widgets.recipeSummary:SetWidth(COLUMN_WIDTH)
    widgets.recipeSummary:SetWordWrap(true)

    widgets.bankSummary = Theme.CreateLabel(container, "tiny", "dim")
    widgets.bankSummary:SetPoint("TOPLEFT", widgets.recipeSummary, "BOTTOMLEFT", 0, -6)
    widgets.bankSummary:SetWidth(COLUMN_WIDTH)
    widgets.bankSummary:SetWordWrap(true)

    widgets.auctionSummary = Theme.CreateLabel(container, "tiny", "dim")
    widgets.auctionSummary:SetPoint("TOPLEFT", widgets.bankSummary, "BOTTOMLEFT", 0, -4)
    widgets.auctionSummary:SetWidth(COLUMN_WIDTH)
    widgets.auctionSummary:SetWordWrap(true)

    widgets.loadWarning = Theme.CreateLabel(container, "tiny", "warn")
    widgets.loadWarning:SetPoint("TOPLEFT", widgets.auctionSummary, "BOTTOMLEFT", 0, -6)
    widgets.loadWarning:SetWidth(COLUMN_WIDTH)
    widgets.loadWarning:SetWordWrap(true)

    local pruneButton = Widgets.CreateButton(container, "Remove old prices", function()
        local removed = ns.Prices:Prune()
        ns.Print(("removed %d old price(s)"):format(removed))
        UI:RefreshActiveTab()
    end, { width = 150, height = 22, tooltip = "Drop items not seen on the auction house for 21 days" })
    pruneButton:SetPoint("TOPLEFT", widgets.loadWarning, "BOTTOMLEFT", 0, -18)
    FitButton(pruneButton)

    -- Destructive, so it arms first rather than wiping a long price history on
    -- a misclick.
    widgets.clearButton = Widgets.CreateButton(container, "Clear price data", function()
        local button = widgets.clearButton

        if button.armed then
            -- This realm only: the other realms keep their prices, so they
            -- keep their scan times and sizes too.
            local realmKey = ns.Config:GetRealmKey()
            ns.db.prices[realmKey] = {}
            ns.db.lastFullScan = nil
            -- The page-limit stamp too: a big auction house only ever has
            -- that one, and left behind it went on saying "scanned 3h ago"
            -- over no prices at all.
            for _, field in ipairs({ "lastFullScanByRealm", "lastCappedScanByRealm",
                                     "sweepSeenByRealm", "sweepRefusedByRealm" }) do
                if ns.db[field] then ns.db[field][realmKey] = nil end
            end

            button.armed = false
            button:SetText("Clear price data")
            button:SetConfirming(false)

            ns.Print("price data cleared for this realm")
            UI:RefreshActiveTab()
            UI:UpdateHeader()
            return
        end

        button.armed = true
        button:SetText("Really clear?")
        -- Red while armed, like the craft pane's Clear queue.
        button:SetConfirming(true)

        C_Timer.After(4, function()
            if button.armed then
                button.armed = false
                button:SetText("Clear price data")
                button:SetConfirming(false)
            end
        end)
    end, { width = 150, height = 22, tooltip = "Delete every stored price for this realm" })
    widgets.clearButton:SetPoint("LEFT", pruneButton, "RIGHT", 8, 0)
    FitButton(widgets.clearButton)

    local exportButton = Widgets.CreateButton(container, "Export queue", function()
        UI:ShowTransferDialog("export")
    end, { width = 150, height = 22,
           tooltip = "Copy your queue, settings and stock limits to a code" })
    exportButton:SetPoint("TOPLEFT", pruneButton, "BOTTOMLEFT", 0, -8)
    FitButton(exportButton)

    local importButton = Widgets.CreateButton(container, "Import", function()
        UI:ShowTransferDialog("import")
    end, { width = 150, height = 22,
           tooltip = "Restore from a code" })
    importButton:SetPoint("LEFT", exportButton, "RIGHT", 8, 0)

    local advanced = CreateSection(container, "ADVANCED", { anchor = exportButton })

    local budgetRow = CreateRow(container, advanced, "Scan speed",
        "How long each screen refresh spends reading auction data. Higher scans faster but can make the game stutter.")

    widgets.budget = Widgets.CreateNumberBox(budgetRow, {
        width = 60, min = 2, max = 16,
        onChange = function(value) Config:Set("scanBudgetMs", value) end,
    })
    widgets.budget:SetPoint("TOPLEFT", CONTROL_X, 0)
    AddUnit(budgetRow, widgets.budget, "ms")

    local autoScanRow = CreateRow(container, budgetRow, "Scan automatically",
        "Scans again when the auction house opens and prices are missing or out of date.")

    widgets.autoScan = Widgets.CreateCheckbox(autoScanRow, "Enabled", function(checked)
        Config:Set("autoScan", checked)
    end, true)
    widgets.autoScan:SetPoint("TOPLEFT", CONTROL_X, -2)

    local learnRow = CreateRow(container, autoScanRow, "Learn from searches",
        "Also takes prices from searches you run in the auction house yourself.")

    widgets.learnFromSearches = Widgets.CreateCheckbox(learnRow, "Enabled", function(checked)
        Config:Set("learnFromSearches", checked)
    end, true)
    widgets.learnFromSearches:SetPoint("TOPLEFT", CONTROL_X, -2)

    local professionValueRow = CreateRow(container, learnRow, "Value in profession window",
        "Shows what one of each recipe sells for beside its name in Blizzard's own window.")

    widgets.professionValue = Widgets.CreateCheckbox(professionValueRow, "Enabled", function(checked)
        Config:Set("showValueInProfessionWindow", checked)
        if ns.RecipeValue then ns.RecipeValue:Refresh() end
    end, true)
    widgets.professionValue:SetPoint("TOPLEFT", CONTROL_X, -2)

    local tooltipValueRow = CreateRow(container, professionValueRow, "Value on item tooltips",
        "Adds what an item sells for to its tooltip, wherever the game shows one.")

    widgets.tooltipValue = Widgets.CreateCheckbox(tooltipValueRow, "Enabled", function(checked)
        Config:Set("showValueOnItemTooltips", checked)
    end, true)
    widgets.tooltipValue:SetPoint("TOPLEFT", CONTROL_X, -2)

    local upgradeRow = CreateRow(container, tooltipValueRow, "Upgrade arrows on gear",
        "A green arrow on the icon of gear that is an upgrade for you. Needs Blackthornes Equipment.")

    widgets.upgradeArrows = Widgets.CreateCheckbox(upgradeRow, "Enabled", function(checked)
        Config:Set("showUpgradeArrows", checked)
        if ns.Upgrades then ns.Upgrades:Forget() end
        UI:RefreshActiveTab()
    end, true)
    widgets.upgradeArrows:SetPoint("TOPLEFT", CONTROL_X, -2)

    local effectsRow = CreateRow(container, upgradeRow, "Window effects",
        "Full: windows fade up and glow as they open, and buttons ease into their colours. Subtle: shorter, and nothing rises. Off: no movement at all.")

    widgets.effects = Widgets.CreateDropdown(effectsRow, {
        { text = "Full", value = "full" },
        { text = "Subtle", value = "subtle" },
        { text = "Off", value = "off" },
    }, function(value)
        Config:Set("windowEffects", value)
        -- Anything moving now lands at once rather than finishing slowly.
        if value == "off" and ns.Motion then ns.Motion:FinishAll() end
    end, { width = 110 })
    widgets.effects:SetPoint("TOPLEFT", CONTROL_X, 0)

    local debugRow = CreateRow(container, effectsRow, "Debug output",
        "Extra messages in chat, to help track down problems.")

    widgets.debug = Widgets.CreateCheckbox(debugRow, "Enabled", function(checked)
        ns.db.global.debug = checked
    end, false)
    widgets.debug:SetPoint("TOPLEFT", CONTROL_X, -2)

    -- Every setting at once, so it arms first like Clear price data.
    local resetButton
    resetButton = Widgets.CreateButton(container, "Reset to defaults", function()
        if not resetButton.armed then
            resetButton.armed = true
            resetButton:SetText("Really reset?")
            resetButton:SetConfirming(true)

            C_Timer.After(4, function()
                if resetButton.armed then
                    resetButton.armed = false
                    resetButton:SetText("Reset to defaults")
                    resetButton:SetConfirming(false)
                end
            end)
            return
        end

        resetButton.armed = false
        resetButton:SetText("Reset to defaults")
        resetButton:SetConfirming(false)

        -- Through Config:Set, as every other setting change is, so a session
        -- keeping its settings in the backup store saves these too.
        for key, value in pairs(ns.Config.DEFAULTS.settings) do
            ns.Config:Set(key, value)
        end

        -- What each control does on a change, done for the reset too. Only
        -- the values moved before: queued sub-crafts stayed as they were,
        -- the profession window kept its old values, and a folded side
        -- panel grew to full height with nothing in it.
        ns.Queue:RebuildDependencies()
        ns.Queue:Notify()
        if ns.RecipeValue then ns.RecipeValue:Refresh() end
        for _, panel in ipairs({ ns.PostPanel, ns.CraftPanel }) do
            if panel and panel.frame then
                ns.Collapse.Apply(panel.frame)
                panel:ApplyHeight()
                panel:Refresh()
            end
        end

        ns.Print("settings reset to defaults")
        UI:RefreshActiveTab()
    end, { width = 150, height = 22, tooltip = "Put every setting back to how it started. Asks you to click again first." })
    -- Under the last setting rather than pinned to the page's bottom edge:
    -- measured from there, the page grew 4 pixels taller every time it was
    -- drawn, and left more empty space to scroll into each time.
    resetButton:SetPoint("TOPLEFT", debugRow, "BOTTOMLEFT", 0, -18)
    FitButton(resetButton)
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

--- Size the scrolling area to the content, once it has real coordinates.
--
-- On the first build the frames have not been laid out yet, so GetTop() is
-- nil and there is nothing to measure. Retrying on the next frame costs one
-- timer and avoids a page that cannot scroll until you click away and back.
local function FitScroll()
    if not widgets.scroll then return end

    if not widgets.scroll:FitContent() then
        C_Timer.After(0, function()
            if widgets.scroll then widgets.scroll:FitContent() end
        end)
    end
end

--- Write a stored value back into its box, unless the player is typing in
--- it. Bag, mail and auction events redraw this page every few seconds at
--- the auction house, and each redraw put the stored number back over the
--- one being typed, so Enter then saved the old number (or a mix of both).
local function Put(box, value)
    local editBox = box.editBox
    if editBox and editBox.HasFocus and editBox:HasFocus() then return end
    box:SetValue(value, true)
end

local function Refresh()
    if not widgets.undercut then return end

    local Config = ns.Config

    -- silent = true (inside Put): writing a stored value back into its own
    -- box must not fire the change handler and write it straight back to
    -- the database.
    Put(widgets.undercut, Config:Get("undercutCopper") or 1)
    Put(widgets.cut, (Config:Get("auctionCut") or 0.05) * 100)
    Put(widgets.minProfit, (Config:Get("minProfit") or 0) / 100)
    Put(widgets.minMargin, Config:Get("minMarginPercent") or 0)
    Put(widgets.budget, Config:Get("scanBudgetMs") or 8)

    local markup = Config:Get("unscannedMarkupPercent")
    Put(widgets.unscannedMarkup, type(markup) == "number" and markup or 50)
    widgets.priceUnscanned:SetChecked(Config:Get("priceUnscannedCrafts") ~= false)

    widgets.minProfitPreview:SetText(
        Util.FormatMoney(Config:Get("minProfit") or 0, { short = true }))

    Put(widgets.maxPosted, Config:Get("maxPostedPerItem") or 0)

    local overrides = 0
    for _ in pairs(ns.db.postLimits or {}) do overrides = overrides + 1 end
    widgets.maxPostedHint:SetText(overrides > 0
        -- Short enough for the 120 pixels beside the box; the longer wording
        -- was cut off with "...".
        and ("%d set per item"):format(overrides)
        or "")

    widgets.hideMaxed:SetChecked(Config:Get("hideAtPostLimit") ~= false)
    widgets.allowLoss:SetChecked(Config:Get("allowPostingAtALoss") == true)
    widgets.confirmPost:SetChecked(Config:Get("confirmBeforePosting") ~= false)
    widgets.verifyPrice:SetChecked(Config:Get("verifyPriceBeforePosting") ~= false)
    widgets.subCrafts:SetChecked(Config:Get("autoQueueSubCrafts") ~= false)
    widgets.altCrafts:SetChecked(Config:Get("suggestOtherCharacters") ~= false)
    widgets.valueOwned:SetChecked(Config:Get("valueOwnedMaterials") ~= false)
    widgets.debug:SetChecked(ns.db.global.debug == true)
    widgets.autoScan:SetChecked(Config:Get("autoScan") ~= false)
    widgets.learnFromSearches:SetChecked(Config:Get("learnFromSearches") ~= false)
    widgets.professionValue:SetChecked(Config:Get("showValueInProfessionWindow") ~= false)
    widgets.tooltipValue:SetChecked(Config:Get("showValueOnItemTooltips") ~= false)
    widgets.upgradeArrows:SetChecked(Config:Get("showUpgradeArrows") ~= false)
    widgets.effects:SetValue(ns.Motion and ns.Motion.Level() or "full")
    widgets.saleAlarm:SetChecked(Config:Get("saleAlarm") ~= false)
    widgets.mailReport:SetChecked(Config:Get("mailReport") ~= false)
    widgets.scanSounds:SetChecked(Config:Get("scanSounds") ~= false)
    widgets.stale:SetValue(Config:Get("staleAfterSeconds") or (48 * 3600), true)

    local lastScan, capped = ns.Prices:GetLastScan()

    widgets.dataSummary:SetText(("%s items priced on %s"):format(
        Util.Comma(ns.Prices:Count()), Config:GetRealmKey()))

    widgets.recipeSummary:SetText(("%s recipes saved  ·  last scan %s"):format(
        Util.Comma(ns.Recipes:Count()),
        lastScan and (Util.FormatAgeAgo(time() - lastScan)
            .. (capped and " (stopped at the page limit)" or "")) or "never"))

    -- The beta can start a session with nothing. Say so where the data
    -- counts are shown, rather than leaving it looking like the addon
    -- forgot everything on its own.
    local diagnostics = ns.Config:GetLoadDiagnostics()
    widgets.loadWarning:SetTextColor(Theme.Unpack("warn"))
    if ns.Config:IsFirstRun() then
        widgets.loadWarning:SetTextColor(Theme.Unpack("text"))
        widgets.loadWarning:SetText(
            "Welcome! This is the first time the addon has run here, so there is no saved data yet.")
    elseif diagnostics.restoredFromCVars then
        widgets.loadWarning:SetText(
            "The game did not load your saved data at login, so it was recovered from the backup in CVars.")
    elseif diagnostics.globalType ~= "table" and not diagnostics.restored then
        widgets.loadWarning:SetText(
            "The game did not load your saved data at login, so this session started fresh.")
    else
        widgets.loadWarning:SetText("")
    end

    local auctionAge = ns.Auctions:GetAge()
    widgets.auctionSummary:SetText(auctionAge
        and ("Your auctions last read " .. Util.FormatAgeAgo(auctionAge) .. ".")
        or "Your auctions have never been read. Open the auction house once.")

    local bankAge = ns.Inventory:GetBankAge()
    widgets.bankSummary:SetText(bankAge
        and ("Bank contents last read " .. Util.FormatAgeAgo(bankAge) .. ".")
        or "Bank never read. Visit a bank so material counts include it.")

    -- Last: the warnings above wrap to different heights depending on what
    -- they say, so the page's total height is only known once they are set.
    FitScroll()
end

UI:RegisterTab({
    key = "settings",
    text = "Settings",
    order = 8,
    build = Build,
    refresh = Refresh,
    onShow = Refresh,
})
