-- Blackthornes Tradeskills -- UI/CraftPanel.lua
-- The craft queue pane, docked beside Blizzard's profession window.
--
-- Queueing already worked from the Profit tab, but that means leaving the
-- window you are actually crafting in, finding the recipe again in a table of
-- several hundred, and coming back. This pane puts the same queue beside the
-- profession window instead: the recipes that window is showing, what each one
-- is worth, a number, and a button.
--
-- It is a second view of the one queue in Logic/Queue.lua, not a queue of its
-- own. Anything added here appears on the Queue tab, feeds the shopping list
-- and is crafted by the same Craft next button.
--
-- Deliberately beside Blizzard's window rather than inside ours, for the same
-- reason the sell list sits beside the auction house: the decision to make
-- something is taken while looking at the profession, and a list behind
-- another frame may as well not exist.

local _, ns = ...

local CraftPanel = ns.NewModule("CraftPanel")

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

-- Wide enough for a recipe name beside a quantity box and a button. Recipe
-- names on this client run long ("Heavy Scorpid Bracers"), so the name gets
-- its own line and the numbers sit under it.
local PANEL_WIDTH = 322
local ROW_HEIGHT = 30

local QUANTITY_WIDTH = 34
local BUTTON_WIDTH = 42

-- Right margin, button, gap, quantity box, gap before the text.
local TEXT_INSET = 8 + BUTTON_WIDTH + 6 + QUANTITY_WIDTH + 10

-- Clear of the profession window's bevelled edge without opening a gap you
-- could see the world through.
local PANEL_GAP = 6

-- Only used when Blizzard's profession window cannot be found at all.
local PANEL_FALLBACK_HEIGHT = 460

-- Short enough to still show a few rows, for a profession window smaller than
-- the pane wants to be.
local PANEL_MIN_HEIGHT = 220

-- Candidate globals for Blizzard's profession window. This client's
-- C_TradeSkillUI is the modern one, so ProfessionsFrame is expected, but the
-- name is not worth assuming -- and both frames are load-on-demand, so the
-- global can be absent on the first open of a session.
local TRADE_SKILL_FRAME_NAMES = { "ProfessionsFrame", "TradeSkillFrame" }

--------------------------------------------------------------------------------
-- Blizzard's window
--------------------------------------------------------------------------------

--- Locate Blizzard's profession window, whatever it is called on this client.
--
-- Read only, and never assigned to: taking a reference to a Blizzard frame to
-- anchor against is fine, writing one back is what taints the UI.
function CraftPanel:FindTradeSkillFrame()
    for _, name in ipairs(TRADE_SKILL_FRAME_NAMES) do
        local frame = _G[name]

        -- Guard against a global that exists but is not a frame.
        if type(frame) == "table" and frame.GetObjectType then
            local ok = pcall(frame.GetObjectType, frame)
            if ok then return frame, name end
        end
    end
end

--- As tall as the profession window it is docked to.
--
-- Returns nil while the frame has no screen coordinates yet, which is what a
-- frame that has never been laid out reports -- an attach that early has to
-- fall back rather than set a height of nil.
function CraftPanel:DesiredHeight(tradeSkillFrame)
    local top, bottom = tradeSkillFrame:GetTop(), tradeSkillFrame:GetBottom()

    if not top or not bottom then return nil end

    return math.max(top - bottom, PANEL_MIN_HEIGHT)
end

--------------------------------------------------------------------------------
-- What to show
--------------------------------------------------------------------------------

--- The recipe IDs the open profession window is showing, as a set.
--
-- Returns nil when the client will not answer, which means "no opinion" rather
-- than "nothing": the caller then falls back to every cached recipe instead of
-- showing an empty pane. GetAllRecipeIDs only answers while a profession
-- window is open, which is exactly when this pane exists.
function CraftPanel:GetOpenRecipeIDs()
    local api = _G.C_TradeSkillUI
    if not api or type(api.GetAllRecipeIDs) ~= "function" then return nil end

    local ok, ids = pcall(api.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" or #ids == 0 then return nil end

    local set = {}
    for _, recipeID in ipairs(ids) do
        set[recipeID] = true
    end

    return set
end

--- Sort comparators, kept total so two runs over the same data agree.
--
-- `pairs` hands recipes back in whatever order the table feels like, so a
-- comparator that can call two different rows equal produces a list that
-- reshuffles itself every refresh. Every tie falls through to the recipe ID.
local SORTS = {
    profit = function(a, b)
        -- Priced crafts first: an unpriced one has no position in a profit
        -- order, and burying them under a zero would be a lie about the money.
        if a.priceable ~= b.priceable then return a.priceable end

        if a.priceable and a.profit ~= b.profit then
            return a.profit > b.profit
        end

        if a.name ~= b.name then return a.name < b.name end
        return a.recipeID < b.recipeID
    end,

    name = function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.recipeID < b.recipeID
    end,
}

--- The rows to draw: one per recipe, with what it is worth and what is queued.
--
-- @param opts { search, sortBy = "profit"|"name" }
function CraftPanel:GetRows(opts)
    opts = opts or {}

    local search = (opts.search or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local open = self:GetOpenRecipeIDs()

    local rows = {}

    for recipeID, recipe in pairs(ns.Recipes:GetAll()) do
        -- Only what this profession window is showing, when it will say. The
        -- cache spans every profession the character has opened this session,
        -- and a tailoring list beside the blacksmithing window is noise.
        if not open or open[recipeID] then
            local name = recipe.name or ("recipe " .. tostring(recipeID))

            -- Plain substring, not a pattern: a recipe name with a hyphen in
            -- it would otherwise be a malformed pattern and match nothing.
            if search == "" or name:lower():find(search, 1, true) then
                local analysis = ns.Profit:Analyse(recipeID)
                local _, queued = ns.Queue:Find(recipeID, true)

                rows[#rows + 1] = {
                    recipeID = recipeID,
                    name = name,
                    outputItemID = recipe.outputItemID,
                    priceable = (analysis and analysis.priceable) == true,
                    profit = (analysis and analysis.profit) or 0,
                    reason = analysis and analysis.reason or nil,
                    craftable = ns.Profit:GetCraftableCount(recipeID) or 0,
                    queued = (queued and queued.quantity) or 0,
                }
            end
        end
    end

    table.sort(rows, SORTS[opts.sortBy] or SORTS.profit)

    return rows
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

--- How many of each recipe the Add button will queue.
--
-- Kept by recipe ID rather than on the row, because the scroll list recycles
-- its rows: scroll down and row 1 becomes a different recipe, and a number
-- left on the frame would follow the frame instead of the craft.
CraftPanel.pending = {}

--- Is the player part-way through typing a number into this box?
--
-- Guarded rather than called outright: this client has gaps in the frame API,
-- and a missing HasFocus would turn a redraw into an error.
local function BeingTyped(box)
    return box.editBox.HasFocus and box.editBox:HasFocus()
end

local function QueueFromRow(row)
    if not row.data then return end

    local quantity = math.max(1, math.floor(
        tonumber(row.quantity:GetValue()) or CraftPanel.pending[row.data.recipeID] or 1))

    ns.Queue:Add(row.data.recipeID, quantity)
end

local function CreateRow(row)
    local textWidth = PANEL_WIDTH - TEXT_INSET - 8

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("TOPLEFT", 8, -4)
    row.name:SetWidth(textWidth)

    row.detail = Theme.CreateLabel(row, "tiny", "muted")
    row.detail:SetPoint("TOPLEFT", 8, -17)
    row.detail:SetWidth(textWidth)

    row.add = Widgets.CreateButton(row, "Add", function()
        QueueFromRow(row)
    end, { width = BUTTON_WIDTH, height = 18, primary = true })
    row.add:SetPoint("RIGHT", -8, 0)

    row.quantity = Widgets.CreateNumberBox(row, {
        width = QUANTITY_WIDTH,
        height = 18,
        background = "panel",
        min = 1,
        onChange = function(value)
            if not row.data then return end
            CraftPanel.pending[row.data.recipeID] = value
        end,
    })
    row.quantity:SetPoint("RIGHT", row.add, "LEFT", -6, 0)
end

local function UpdateRow(row, line)
    row.name:SetText(line.name)

    -- Not while it is being typed into: overwriting someone mid-number is how
    -- a field ends up refusing to accept what they meant.
    if not BeingTyped(row.quantity) then
        row.quantity:SetValue(CraftPanel.pending[line.recipeID] or 1, true)
    end

    -- Rarity, the same as the Profit tab and the sell list, so the three read
    -- alike. A recipe with no sellable output has no colour to take.
    local r, g, b = Util.GetItemQualityColor(line.outputItemID)

    if r then
        row.name:SetTextColor(r, g, b)
    else
        row.name:SetTextColor(Theme.Unpack("text"))
    end

    -- What it is worth, and whether you can make one right now: the two things
    -- that decide whether this recipe is the one you want.
    local parts = {}

    if line.priceable then
        parts[#parts + 1] = ("%s each"):format(
            Util.FormatMoney(line.profit, { noColor = true, short = true }))
    else
        parts[#parts + 1] = line.reason or "no price data"
    end

    parts[#parts + 1] = line.craftable > 0
        and ("can make %d"):format(line.craftable)
        or "no materials"

    if line.queued > 0 then
        parts[#parts + 1] = ("queued %d"):format(line.queued)
    end

    row.detail:SetText(table.concat(parts, "  ·  "))

    if line.priceable and line.profit < 0 then
        row.detail:SetTextColor(Theme.Unpack("loss"))
    elseif line.queued > 0 then
        row.detail:SetTextColor(Theme.Unpack("accent"))
    else
        row.detail:SetTextColor(Theme.Unpack("muted"))
    end

    row.add.tooltipText = ("Queue %d of %s. Right-click the row to take it off the queue."):format(
        CraftPanel.pending[line.recipeID] or 1, line.name)
end

local function ShowRowTooltip(row, line)
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetText(line.name, 1, 1, 1)

    if line.priceable then
        GameTooltip:AddDoubleLine("Profit each",
            Util.FormatMoney(line.profit, { noColor = true }), 0.7, 0.7, 0.7, 1, 1, 1)
    else
        GameTooltip:AddLine(line.reason or "No price data for this yet", 0.9, 0.38, 0.31)
    end

    GameTooltip:AddDoubleLine("Materials for", tostring(line.craftable),
        0.7, 0.7, 0.7, 1, 1, 1)

    if line.queued > 0 then
        GameTooltip:AddDoubleLine("Already queued", tostring(line.queued),
            0.7, 0.7, 0.7, 0.78, 0.64, 0.30)
    end

    GameTooltip:AddLine("Left-click to queue, right-click to remove.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

--- Left-click queues, right-click takes it back off.
--
-- The Add button is the discoverable way in; this is for working down a list
-- quickly, where reaching for the same small button every time is the slow part.
local function OnRowClick(line, _, mouseButton, row)
    if mouseButton == "RightButton" then
        ns.Queue:Remove(line.recipeID)
        return
    end

    QueueFromRow(row)
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------

function CraftPanel:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesTSCraftPanel", UIParent)
    frame:SetWidth(PANEL_WIDTH)
    frame:SetFrameStrata("HIGH")

    -- Opaque, so a click on a row cannot fall through to whatever is behind
    -- the pane, and raised on click: the main window shares this strata, and
    -- without this the two would have a fixed order forever.
    frame:EnableMouse(true)
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:Hide()

    Theme.Fill(frame, "window")
    Theme.AddGameOutline(frame, { style = "dialog", color = "natural" })

    local title = Theme.CreateLabel(frame, "normal", "accent")
    title:SetPoint("TOPLEFT", 14, -14)
    title:SetText("Craft queue")

    -- Profit order is the useful default -- it answers "what should I make" --
    -- but a pane you came to in order to find one specific recipe needs the
    -- alphabet, so the order is a single click away rather than a setting.
    self.sortBy = self.sortBy or "profit"

    local sort = Widgets.CreateButton(frame, "", function()
        CraftPanel.sortBy = CraftPanel.sortBy == "profit" and "name" or "profit"
        CraftPanel:UpdateSortButton()
        CraftPanel:Refresh()
    end, { width = 66, height = 18, tooltip = "Change the order of this list" })
    sort:SetPoint("TOPRIGHT", -14, -13)
    self.sortButton = sort
    self:UpdateSortButton()

    -- Coalesced rather than refreshed per keystroke: every refresh prices
    -- every recipe the profession is showing, and typing "copper" would
    -- otherwise do that six times before the word is finished.
    local search = Widgets.CreateSearchBox(frame, "Search recipes", function()
        CraftPanel:RequestRefresh()
    end)
    -- One anchor and an explicit size. A TOPLEFT under the title plus a
    -- TOPRIGHT on the frame would set this box's top twice, from two frames
    -- that disagree about where it is, and the client resolves that by
    -- quietly dropping one of the two.
    search:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    search:SetSize(PANEL_WIDTH - 28, 22)
    self.search = search

    local divider = Theme.CreateDivider(frame)
    divider:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, 0)

    local list = Widgets.CreateScrollList(frame, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onClick = OnRowClick,
        onEnter = ShowRowTooltip,
        onLeave = function() GameTooltip:Hide() end,
    })
    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 74)
    self.list = list

    local empty = Theme.CreateLabel(frame, "small", "dim", "CENTER")
    empty:SetPoint("CENTER", list, "CENTER")
    empty:SetWidth(PANEL_WIDTH - 40)
    empty:SetWordWrap(true)
    self.empty = empty

    -- Crafting needs a hardware event, so this is a real click each time: one
    -- click runs one queue entry to completion. Same call the Queue tab makes,
    -- so working from either place behaves identically.
    local craft = Widgets.CreateButton(frame, "Craft next", function()
        if ns.Crafting:IsBusy() then
            ns.Crafting:Stop()
        else
            local entry = ns.Crafting:GetNextReady()
            if entry then
                ns.Crafting:Start(entry.recipeID, entry.quantity)
            end
        end

        CraftPanel:Refresh()
    end, { width = PANEL_WIDTH - 28, height = 24, primary = true })
    craft:SetPoint("BOTTOMLEFT", 14, 40)
    self.craftButton = craft

    local summary = Theme.CreateLabel(frame, "tiny", "muted")
    summary:SetPoint("BOTTOMLEFT", 14, 22)
    summary:SetWidth(PANEL_WIDTH - 100)
    self.summary = summary

    local openQueue = Widgets.CreateButton(frame, "Queue tab", function()
        ns.UI:Show()
        ns.UI:SelectTab("queue")
    end, { width = 64, height = 18, tooltip = "Open the full queue, with its shopping list" })
    openQueue:SetPoint("BOTTOMRIGHT", -14, 18)

    self.frame = frame
    return frame
end

function CraftPanel:UpdateSortButton()
    if not self.sortButton then return end

    self.sortButton:SetText(self.sortBy == "profit" and "Profit" or "A-Z")
    self.sortButton.tooltipText = self.sortBy == "profit"
        and "Sorted by profit. Click for alphabetical order."
        or "Sorted by name. Click to put the best-paying crafts first."
end

--- Dock to the right of the profession window, as tall as it is.
function CraftPanel:Attach()
    local frame = self:Build()
    local tradeSkillFrame, frameName = self:FindTradeSkillFrame()

    frame:ClearAllPoints()

    if tradeSkillFrame then
        -- One anchor and a measured height, rather than a point on the
        -- profession window's top and another on its bottom. Anchoring TOPLEFT
        -- and BOTTOM over-constrains the frame -- a BOTTOM point fixes the
        -- horizontal centre, which TOPLEFT has already decided -- and the
        -- client silently drops one of the two. That is how the sell list
        -- ended up docked at half the height it asked for.
        frame:SetPoint("TOPLEFT", tradeSkillFrame, "TOPRIGHT", PANEL_GAP, 0)
        frame:SetHeight(self:DesiredHeight(tradeSkillFrame) or PANEL_FALLBACK_HEIGHT)

        ns.Debug("docked craft pane to", frameName)
    else
        -- Blizzard's profession UI is load-on-demand and may not exist yet.
        -- A pane in a slightly odd place beats one that silently never appears.
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
        frame:SetHeight(PANEL_FALLBACK_HEIGHT)

        ns.Debug("no profession frame found; using fallback position")
    end

    frame:Show()
    self:Refresh()
end

--- Re-measure, for a profession window that changed size after it opened.
function CraftPanel:Reflow()
    if not self.frame or not self.frame:IsShown() then return end

    local tradeSkillFrame = self:FindTradeSkillFrame()
    if not tradeSkillFrame then return end

    local height = self:DesiredHeight(tradeSkillFrame)

    -- Only when it actually moved: setting the height relayouts the list, and
    -- this runs on every refresh.
    if height and math.abs(height - self.frame:GetHeight()) > 0.5 then
        self.frame:SetHeight(height)
    end
end

--- Keep the Craft next button honest about what it will do, and why it cannot.
function CraftPanel:UpdateCraftButton()
    local button = self.craftButton
    if not button then return end

    if ns.Crafting:IsBusy() then
        button:SetText("Stop crafting")
        button:SetEnabledState(true)
        button.tooltipText = "Stop after the current craft"
        return
    end

    if ns.Queue:Count() == 0 then
        button:SetText("Craft next")
        button:SetEnabledState(false)
        button.tooltipText = "Nothing is queued"
        return
    end

    local entry = ns.Crafting:GetNextReady()

    if not entry then
        button:SetText("Craft next")
        button:SetEnabledState(false)

        -- Report the first entry's actual obstacle rather than a generic one.
        local _, reason = ns.Crafting:GetReadiness(ns.Queue:GetAll()[1].recipeID)
        button.tooltipText = reason or "Nothing here can be made yet"
        return
    end

    local recipe = ns.Recipes:GetAny(entry.recipeID)
    local canMake = math.min(entry.quantity, ns.Profit:GetCraftableCount(entry.recipeID))

    button:SetText(("Craft %dx %s"):format(canMake, (recipe and recipe.name) or "item"))
    button:SetEnabledState(true)
    button.tooltipText = "One click runs this entry to completion"
end

function CraftPanel:Refresh()
    if not self.frame or not self.frame:IsShown() then return end

    self:Reflow()

    local rows = self:GetRows({
        search = self.search and self.search:GetText() or "",
        sortBy = self.sortBy,
    })

    self.list:SetData(rows)
    self.empty:SetShown(#rows == 0)

    if #rows == 0 then
        local searching = self.search and self.search:GetText() ~= ""

        self.empty:SetText(searching
            and "Nothing here matches that."
            or "No recipes cached for this profession yet.\n\nThey are read from the window as it opens; give it a moment.")
    end

    self:UpdateCraftButton()

    local queued = ns.Queue:Count()

    if queued == 0 then
        self.summary:SetText("Nothing queued")
        self.summary:SetTextColor(Theme.Unpack("dim"))
        return
    end

    local totals = ns.Queue:GetTotals()

    self.summary:SetText(("%d craft%s queued  ·  profit %s%s"):format(
        totals.crafts, totals.crafts == 1 and "" or "s",
        Util.FormatMoney(totals.profit, { noColor = true, short = true }),
        totals.priceable and "" or "  (some unpriced)"))
    self.summary:SetTextColor(Theme.Unpack("muted"))
end

--- Ask for a refresh soon, rather than taking one now.
--
-- A refresh analyses every recipe the profession window is showing, which is
-- several hundred on a maxed profession. The events that invalidate this pane
-- -- bags changing, a craft finishing, the recipe cache filling in -- arrive
-- in bursts, so a burst costs one pass instead of ten.
function CraftPanel:RequestRefresh()
    if not self:IsShown() or self.refreshPending then return end

    self.refreshPending = true

    C_Timer.After(0.35, function()
        CraftPanel.refreshPending = false
        CraftPanel:Refresh()
    end)
end

function CraftPanel:Hide()
    if self.frame then self.frame:Hide() end
end

function CraftPanel:IsShown()
    return self.frame ~= nil and self.frame:IsShown()
end

--- Show or hide the pane by hand.
--
-- Reports what it did rather than what it tried: on this client a command that
-- errors prints nothing at all unless scriptErrors is on, so "it isn't doing
-- anything" has to be answerable from the chat frame.
function CraftPanel:Toggle()
    if self:IsShown() then
        self:Hide()
        ns.Print("craft pane hidden. It comes back when you open a profession.")
        return
    end

    self:Attach()

    if self:IsShown() then
        local _, frameName = self:FindTradeSkillFrame()

        ns.Print(("craft pane shown%s, %d recipe(s) listed."):format(
            frameName and (", docked to " .. frameName) or " (no profession window open)",
            #self:GetRows({ sortBy = self.sortBy })))
    else
        ns.Warn("the craft pane would not show.")
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function CraftPanel:OnEnable()
    -- Blizzard's profession UI is load-on-demand, so on the first open of a
    -- session the frame may not exist yet when this event arrives. Re-anchor
    -- shortly after in case it appeared late.
    ns.RegisterEvent(self, "TRADE_SKILL_SHOW", function()
        CraftPanel:Attach()

        C_Timer.After(0.5, function()
            if ns.Crafting and ns.Crafting.isTradeSkillOpen then
                CraftPanel:Attach()
            end
        end)
    end)

    ns.RegisterEvent(self, "TRADE_SKILL_CLOSE", function()
        CraftPanel:Hide()
    end)

    ns.RegisterCommand("pane", "show or hide the craft pane", function()
        CraftPanel:Toggle()
    end)
end
