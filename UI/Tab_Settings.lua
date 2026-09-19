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

local LABEL_WIDTH = 200
local CONTROL_X = 212

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

    local label = Theme.CreateLabel(row, "small", "text")
    label:SetPoint("TOPLEFT", 0, -4)
    label:SetWidth(LABEL_WIDTH)
    label:SetText(labelText)

    if description then
        local hint = Theme.CreateLabel(row, "tiny", "dim")
        hint:SetPoint("TOPLEFT", 0, -24)
        hint:SetWidth(COLUMN_WIDTH)
        hint:SetText(description)
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
        "Your posting price is the cheapest rival listing minus this.")

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
        "Percentage taken from each sale, deducted from revenue.")

    widgets.cut = Widgets.CreateNumberBox(cutRow, {
        width = 70, min = 0, max = 100, decimals = 1,
        onChange = function(value)
            Config:Set("auctionCut", value / 100)
            UI:RefreshActiveTab()
        end,
    })
    widgets.cut:SetPoint("TOPLEFT", CONTROL_X, 0)
    AddUnit(cutRow, widgets.cut, "%")

    local ownedRow = CreateRow(container, cutRow, "Materials you already own",
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
        "Also queue reagents that are cheaper to craft than to buy.")

    widgets.subCrafts = Widgets.CreateCheckbox(subCraftRow, "Queue them", function(checked)
        Config:Set("autoQueueSubCrafts", checked)
    end, true)
    widgets.subCrafts:SetPoint("TOPLEFT", CONTROL_X, -2)

    local lossRow = CreateRow(container, subCraftRow, "Recommend selling at a loss",
        "Off: the Post tab still lists them, marked red, but does not recommend them.")

    widgets.allowLoss = Widgets.CreateCheckbox(lossRow, "Recommend anyway", function(checked)
        Config:Set("allowPostingAtALoss", checked)
        UI:RefreshActiveTab()
    end, false)
    widgets.allowLoss:SetPoint("TOPLEFT", CONTROL_X, -2)

    local confirmRow = CreateRow(container, lossRow, "Confirm before each listing",
        "Off: clicking List or Post All lists immediately, with no prompt.")

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

    local filters = CreateSection(container, "FILTERS", { anchor = verifyRow })

    local profitRow = CreateRow(container, filters, "Minimum profit",
        "Crafts below this are hidden from the Profit tab.")

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

    widgets.dataSummary = Theme.CreateLabel(container, "small", "text")
    widgets.dataSummary:SetPoint("TOPLEFT", data, "BOTTOMLEFT", 0, -6)
    widgets.dataSummary:SetWidth(COLUMN_WIDTH)

    widgets.recipeSummary = Theme.CreateLabel(container, "small", "text")
    widgets.recipeSummary:SetPoint("TOPLEFT", widgets.dataSummary, "BOTTOMLEFT", 0, -4)
    widgets.recipeSummary:SetWidth(COLUMN_WIDTH)

    widgets.bankSummary = Theme.CreateLabel(container, "tiny", "dim")
    widgets.bankSummary:SetPoint("TOPLEFT", widgets.recipeSummary, "BOTTOMLEFT", 0, -6)
    widgets.bankSummary:SetWidth(COLUMN_WIDTH)

    widgets.auctionSummary = Theme.CreateLabel(container, "tiny", "dim")
    widgets.auctionSummary:SetPoint("TOPLEFT", widgets.bankSummary, "BOTTOMLEFT", 0, -4)
    widgets.auctionSummary:SetWidth(COLUMN_WIDTH)

    widgets.loadWarning = Theme.CreateLabel(container, "tiny", "warn")
    widgets.loadWarning:SetPoint("TOPLEFT", widgets.auctionSummary, "BOTTOMLEFT", 0, -6)
    widgets.loadWarning:SetWidth(COLUMN_WIDTH)
    widgets.loadWarning:SetWordWrap(true)

    local pruneButton = Widgets.CreateButton(container, "Prune old prices", function()
        local removed = ns.Prices:Prune()
        ns.Print(("removed %d stale price record(s)"):format(removed))
        UI:RefreshActiveTab()
    end, { width = 140, height = 22, tooltip = "Drop items not seen on the auction house for 21 days" })
    pruneButton:SetPoint("TOPLEFT", widgets.loadWarning, "BOTTOMLEFT", 0, -18)

    -- Destructive, so it arms first rather than wiping a long price history on
    -- a misclick.
    widgets.clearButton = Widgets.CreateButton(container, "Clear price data", function()
        local button = widgets.clearButton

        if button.armed then
            ns.db.prices[ns.Config:GetRealmKey()] = {}
            ns.db.lastFullScan = nil

            button.armed = false
            button:SetText("Clear price data")

            ns.Print("price data cleared for this realm")
            UI:RefreshActiveTab()
            UI:UpdateHeader()
            return
        end

        button.armed = true
        button:SetText("Really clear?")

        C_Timer.After(4, function()
            if button.armed then
                button.armed = false
                button:SetText("Clear price data")
            end
        end)
    end, { width = 140, height = 22, tooltip = "Delete every stored price for this realm" })
    widgets.clearButton:SetPoint("LEFT", pruneButton, "RIGHT", 8, 0)

    local exportButton = Widgets.CreateButton(container, "Export queue", function()
        UI:ShowTransferDialog("export")
    end, { width = 140, height = 22,
           tooltip = "Copy your queue, settings and posted limits to a code" })
    exportButton:SetPoint("TOPLEFT", pruneButton, "BOTTOMLEFT", 0, -8)

    local importButton = Widgets.CreateButton(container, "Import", function()
        UI:ShowTransferDialog("import")
    end, { width = 140, height = 22,
           tooltip = "Restore from a code" })
    importButton:SetPoint("LEFT", exportButton, "RIGHT", 8, 0)

    local advanced = CreateSection(container, "ADVANCED", { anchor = exportButton })

    local budgetRow = CreateRow(container, advanced, "Scan speed",
        "Milliseconds per frame spent reading auction data.")

    widgets.budget = Widgets.CreateNumberBox(budgetRow, {
        width = 60, min = 2, max = 16,
        onChange = function(value) Config:Set("scanBudgetMs", value) end,
    })
    widgets.budget:SetPoint("TOPLEFT", CONTROL_X, 0)
    AddUnit(budgetRow, widgets.budget, "ms")

    local autoScanRow = CreateRow(container, budgetRow, "Scan automatically",
        "Rescans when the auction house opens and prices are missing or stale.")

    widgets.autoScan = Widgets.CreateCheckbox(autoScanRow, "Enabled", function(checked)
        Config:Set("autoScan", checked)
    end, true)
    widgets.autoScan:SetPoint("TOPLEFT", CONTROL_X, -2)

    local debugRow = CreateRow(container, autoScanRow, "Debug output",
        "Extra detail in the chat frame, for diagnosing problems.")

    widgets.debug = Widgets.CreateCheckbox(debugRow, "Enabled", function(checked)
        ns.db.global.debug = checked
    end, false)
    widgets.debug:SetPoint("TOPLEFT", CONTROL_X, -2)

    local resetButton = Widgets.CreateButton(container, "Reset to defaults", function()
        for key, value in pairs(ns.Config.DEFAULTS.settings) do
            ns.db.settings[key] = value
        end

        ns.Print("settings reset to defaults")
        UI:RefreshActiveTab()
    end, { width = 140, height = 22 })
    resetButton:SetPoint("BOTTOMLEFT", COLUMN_TWO_X, 12)
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

local function Refresh()
    if not widgets.undercut then return end

    local Config = ns.Config

    -- silent = true: writing a stored value back into its own box must not fire
    -- the change handler and write it straight back to the database.
    widgets.undercut:SetValue(Config:Get("undercutCopper") or 1, true)
    widgets.cut:SetValue((Config:Get("auctionCut") or 0.05) * 100, true)
    widgets.minProfit:SetValue((Config:Get("minProfit") or 0) / 100, true)
    widgets.minMargin:SetValue(Config:Get("minMarginPercent") or 0, true)
    widgets.budget:SetValue(Config:Get("scanBudgetMs") or 8, true)

    widgets.minProfitPreview:SetText(
        Util.FormatMoney(Config:Get("minProfit") or 0, { short = true }))

    widgets.maxPosted:SetValue(Config:Get("maxPostedPerItem") or 0, true)

    local overrides = 0
    for _ in pairs(ns.db.postLimits or {}) do overrides = overrides + 1 end
    widgets.maxPostedHint:SetText(overrides > 0
        and ("%d item override%s"):format(overrides, overrides == 1 and "" or "s")
        or "")

    widgets.hideMaxed:SetChecked(Config:Get("hideAtPostLimit") ~= false)
    widgets.allowLoss:SetChecked(Config:Get("allowPostingAtALoss") == true)
    widgets.confirmPost:SetChecked(Config:Get("confirmBeforePosting") ~= false)
    widgets.verifyPrice:SetChecked(Config:Get("verifyPriceBeforePosting") ~= false)
    widgets.subCrafts:SetChecked(Config:Get("autoQueueSubCrafts") ~= false)
    widgets.valueOwned:SetChecked(Config:Get("valueOwnedMaterials") ~= false)
    widgets.debug:SetChecked(ns.db.global.debug == true)
    widgets.autoScan:SetChecked(Config:Get("autoScan") ~= false)
    widgets.stale:SetValue(Config:Get("staleAfterSeconds") or (48 * 3600), true)

    local lastScan = ns.db.lastFullScan

    widgets.dataSummary:SetText(("%s items priced on %s"):format(
        Util.Comma(ns.Prices:Count()), Config:GetRealmKey()))

    widgets.recipeSummary:SetText(("%s recipes cached  ·  last scan %s"):format(
        Util.Comma(ns.Recipes:Count()),
        lastScan and (Util.FormatAge(time() - lastScan) .. " ago") or "never"))

    -- The beta can start a session with nothing. Say so where the data
    -- counts are shown, rather than leaving it looking like the addon
    -- forgot everything on its own.
    local diagnostics = ns.Config:GetLoadDiagnostics()
    if diagnostics.restoredFromCVars then
        widgets.loadWarning:SetText(
            "This client did not return saved data at login, so it was recovered from CVars instead. A known WoW: Forever beta issue.")
    elseif diagnostics.globalType ~= "table" and not diagnostics.restored then
        widgets.loadWarning:SetText(
            "This client did not return saved data at login, so everything was rebuilt this session. A known WoW: Forever beta issue.")
    else
        widgets.loadWarning:SetText("")
    end

    local auctionAge = ns.Auctions:GetAge()
    widgets.auctionSummary:SetText(auctionAge
        and ("Your auctions last read " .. Util.FormatAge(auctionAge) .. " ago.")
        or "Your auctions have never been read. Open the auction house once.")

    local bankAge = ns.Inventory:GetBankAge()
    widgets.bankSummary:SetText(bankAge
        and ("Bank contents last read " .. Util.FormatAge(bankAge) .. " ago.")
        or "Bank never read. Visit a bank so material counts include it.")

    -- Last: the warnings above wrap to different heights depending on what
    -- they say, so the page's total height is only known once they are set.
    FitScroll()
end

UI:RegisterTab({
    key = "settings",
    text = "Settings",
    order = 7,
    build = Build,
    refresh = Refresh,
    onShow = Refresh,
})
