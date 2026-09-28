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
-- its own line and the numbers sit under it. The - and + buttons and the
-- quantity box between them sit on the name's line, so the line under it can run the full width of the
-- row: at 322 wide with the buttons beside it, that line was cut off on
-- almost every recipe.
local PANEL_WIDTH = 350
local ROW_HEIGHT = 30

local QUANTITY_WIDTH = 34

-- The - and + buttons either side of the quantity box, and the gap between
-- each button and the box.
local STEP_WIDTH = 18
local STEP_GAP = 3

-- Both step buttons and their gaps: everything beside the box.
local BUTTON_WIDTH = STEP_WIDTH * 2 + STEP_GAP * 2

-- The Craft button left of the -, shown only on rows with something queued.
local CRAFT_WIDTH = 36
local CRAFT_GAP = 5
local CRAFT_INSET = CRAFT_WIDTH + CRAFT_GAP

-- Right margin, the buttons and box, gap before the text.
local TEXT_INSET = 8 + BUTTON_WIDTH + QUANTITY_WIDTH + 14

-- Clear of the profession window's bevelled edge without opening a gap you
-- could see the world through.
local PANEL_GAP = 6

-- The two buttons at the bottom right, and how long Clear queue waits for its
-- second click.
local QUEUE_TAB_WIDTH = 64
local CLEAR_WIDTH = 84
local CLEAR_CONFIRM_SECONDS = 4

-- Only used when Blizzard's profession window cannot be found at all.
local PANEL_FALLBACK_HEIGHT = 460

-- Short enough to still show a few rows, for a profession window smaller than
-- the pane wants to be.
local PANEL_MIN_HEIGHT = 220

-- Remembers whether the pane is folded down to its title (UI/Collapse.lua).
local COLLAPSE_KEY = "craftPaneCollapsed"

-- Candidate globals for Blizzard's profession window. This client's
-- C_TradeSkillUI is the modern one, so ProfessionsFrame is expected, but the
-- name is not worth assuming -- and both frames are load-on-demand, so the
-- global can be absent on the first open of a session.
local TRADE_SKILL_FRAME_NAMES = { "ProfessionsFrame", "TradeSkillFrame" }

-- Exposed so a test can hold the row geometry to its own promise: the text
-- must stop clear of every control standing to its right.
CraftPanel.TEXT_INSET = TEXT_INSET
CraftPanel.QUANTITY_WIDTH = QUANTITY_WIDTH
CraftPanel.BUTTON_WIDTH = BUTTON_WIDTH
CraftPanel.CRAFT_INSET = CRAFT_INSET
CraftPanel.PANEL_GAP = PANEL_GAP

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

--- How far past its own right edge a frame's visible children reach.
--
-- Blizzard hangs the profession tabs off the right-hand side of the profession
-- window, as child frames anchored outside their parent's rectangle. GetRight()
-- reports the window, not the tabs, so docking at TOPRIGHT + a small gap parks
-- this pane straight on top of them -- which is what it did.
--
-- Measured rather than guessed at with a bigger fixed gap: the tabs are only
-- there for a character with more than one profession, and a constant wide
-- enough to clear them would strand the pane in open space for everyone else.
--
-- Only visible children count, and the result is capped: one stray child
-- anchored far away should not push the pane off the side of the screen.
local MAX_OVERHANG = 120

function CraftPanel:RightOverhang(tradeSkillFrame)
    local right = tradeSkillFrame:GetRight()
    if not right then return 0 end

    -- Guarded: GetChildren is not worth assuming on a client with API gaps,
    -- and a pane that fails to dock is worse than one docked a little close.
    local ok, children = pcall(function()
        return { tradeSkillFrame:GetChildren() }
    end)

    if not ok or type(children) ~= "table" then return 0 end

    local overhang = 0

    for _, child in ipairs(children) do
        if type(child) == "table" and child.GetRight and child.IsShown then
            local shownOk, shown = pcall(child.IsShown, child)
            local rightOk, childRight = pcall(child.GetRight, child)

            if shownOk and shown and rightOk and childRight then
                overhang = math.max(overhang, childRight - right)
            end
        end
    end

    return math.min(math.max(overhang, 0), MAX_OVERHANG)
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

        -- Ranked, not raw. See RankOf below: a craft you already have nine of
        -- listed is worth less right now than the number in the row says.
        if a.priceable and a.rank ~= b.rank then
            return a.rank > b.rank
        end

        if a.name ~= b.name then return a.name < b.name end
        return a.recipeID < b.recipeID
    end,

    name = function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.recipeID < b.recipeID
    end,

    -- The Level Up tab's order, so the two agree: orange, yellow, green,
    -- then cheapest materials first. Its comparator reads `tier` and `cost`.
    levelup = function(a, b)
        local compare = ns.LevelUp and ns.LevelUp.Compare
        if compare then
            return compare(
                { tier = a.skillUpTier, cost = a.materialCost, name = a.name, recipeID = a.recipeID },
                { tier = b.skillUpTier, cost = b.materialCost, name = b.name, recipeID = b.recipeID })
        end

        if a.name ~= b.name then return a.name < b.name end
        return a.recipeID < b.recipeID
    end,
}

-- What the sort button steps through, and what it says for each.
local SORT_ORDER = { "profit", "levelup", "name" }
local SORT_LABEL = { profit = "Profit", levelup = "Level Up", name = "A-Z" }

CraftPanel.SORT_ORDER = SORT_ORDER

--- What a craft is worth *right now*, as against what one sells for.
--
-- The pane was sorting on raw profit, so a craft with nine already sitting on
-- the auction house ranked level with an identical one you hold none of. It is
-- not: the tenth only sells once the other nine have, so the gold comes back
-- roughly ten times slower. The Profit tab has ranked this way since the stock
-- penalty landed, and two lists answering "what should I make next" in
-- different orders is worse than either order on its own.
--
-- Guarded rather than called outright so the pane still draws if the profit
-- engine is ever loaded without it.
local function RankOf(analysis)
    if not analysis then return -math.huge end

    local rank = ns.Profit and ns.Profit._RankValue
    if rank then return rank(analysis, "profit") end

    return analysis.profit or -math.huge
end

--- How much room the limit leaves, counted in crafts rather than in units.
--
-- The limit is a number of items, but this pane queues crafts, and one craft
-- can produce several items. Clamping a craft count against a unit count is how
-- a limit of ten turns into fifty Rough Sharpening Stones.
--
-- Rounded down, with a floor of one: a limit with any room left in it should
-- never refuse the smallest thing you can actually make.
--
-- Profit works the same figure out, and the two panes have to agree about the
-- same recipe, so its answer is preferred and this is the fallback for a
-- caller holding a recipe but no analysis.
local function RoomInCrafts(room, recipe)
    if ns.Profit and ns.Profit.RoomInCrafts then
        return ns.Profit.RoomInCrafts(room, recipe)
    end

    if room == nil then return nil end
    if room <= 0 then return 0 end

    local perCraft = math.max(1, (recipe and recipe.quantityMin) or 1)

    return math.max(1, math.floor(room / perCraft))
end

--- The rows to draw: one per recipe, with what it is worth and what is queued.
--
-- @param opts { search, sortBy = "profit"|"levelup"|"name", ignoreLimit }
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

                local atLimit = (analysis and analysis.atPostLimit) == true

                -- Already holding as many as the limit in Settings allows.
                -- Suppressed here by the same setting as on the Profit tab,
                -- because the pane's whole job is answering "what should I
                -- make next" and a craft you have enough of is not an answer.
                --
                -- A search is not a suggestion, though: someone typing a name
                -- is looking for that one recipe, and hiding the thing they
                -- just named would read as the pane having lost it.
                --
                -- Nor is a row already on screen: queueing up to the limit
                -- would otherwise make the row vanish under the cursor.
                local suppressed = atLimit
                    and search == ""
                    and not opts.ignoreLimit
                    and not (opts.keepOrder and opts.keepOrder[recipeID])
                    and ns.Config:Get("hideAtPostLimit") ~= false

                if not suppressed then
                    rows[#rows + 1] = {
                        recipeID = recipeID,
                        name = name,
                        outputItemID = recipe.outputItemID,
                        priceable = (analysis and analysis.priceable) == true,
                        profit = (analysis and analysis.profit) or 0,

                        -- Does it still skill you up, and is it worth a star.
                        skillUpTier = analysis and analysis.skillUp
                            and analysis.skillUp.tier or nil,
                        skillUpStale = analysis and analysis.skillUp
                            and analysis.skillUp.stale or nil,
                        recommended = (analysis and analysis.recommended) == true,
                        materialCost = analysis and analysis.cost
                            and analysis.cost.priceable and analysis.cost.total or nil,
                        rank = RankOf(analysis),
                        reason = analysis and analysis.reason or nil,
                        soulbound = (analysis and analysis.soulbound) == true,
                        craftable = ns.Profit:GetCraftableCount(recipeID) or 0,
                        queued = (queued and queued.quantity) or 0,

                        -- What you already hold of it, which is the number
                        -- that was missing from this pane entirely.
                        posted = (analysis and analysis.posted) or 0,
                        stock = (analysis and analysis.stock) or 0,
                        postLimit = (analysis and analysis.postLimit) or 0,
                        atPostLimit = atLimit,
                        roomInCrafts = RoomInCrafts(
                            analysis and analysis.postRoom, recipe),
                    }
                end
            end
        end
    end

    local sort = SORTS[opts.sortBy] or SORTS.profit
    local keep = opts.keepOrder

    if keep then
        -- Rows already on screen keep their places; anything new goes after
        -- them, in the chosen order.
        table.sort(rows, function(a, b)
            local ka, kb = keep[a.recipeID], keep[b.recipeID]
            if ka and kb then return ka < kb end
            if ka or kb then return ka ~= nil end
            return sort(a, b)
        end)
    else
        table.sort(rows, sort)
    end

    return rows
end

--- What the list's order was worked out for. While this stays the same, rows
--- keep their places.
--
-- Queueing a craft counts it as stock you will have, and the profit order
-- ranks a craft lower the more of it you have coming (see RankOf). So adding
-- a row to the queue used to drop it down the list the moment it was clicked.
-- The order is now worked out once and held until the sort, the search, the
-- Ignore max on hand box or the profession changes, or the pane closes.
function CraftPanel:OrderKey(opts)
    local open = self:GetOpenRecipeIDs()
    local count, sum = 0, 0
    for recipeID in pairs(open or {}) do
        count, sum = count + 1, sum + recipeID
    end

    return table.concat({ tostring(opts.sortBy), opts.search or "",
        tostring(opts.ignoreLimit), count, sum }, "|")
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

--- Is the player part-way through typing a number into this box?
--
-- Guarded rather than called outright: this client has gaps in the frame API,
-- and a missing HasFocus would turn a redraw into an error.
local function BeingTyped(box)
    return box.editBox.HasFocus and box.editBox:HasFocus()
end

--- Is the "Ignore max on hand" box ticked?
function CraftPanel:IgnoringLimit()
    return ns.Config:Get("craftPaneIgnoreLimit") == true
end

--- Queue this many more of the row's recipe, within the Keep in stock limit.
local function QueueMore(line, quantity)
    quantity = math.max(1, math.floor(tonumber(quantity) or 1))

    -- The limit is the player's own answer to "how many of these do I want",
    -- so queueing past it is nearly always a slip -- and a slip that costs
    -- materials and a deposit, not just a wrong number on a screen. Said out
    -- loud either way: a button that silently queues fewer than asked for
    -- looks broken.
    -- Unless the player has ticked the box that says to ignore it.
    local room = not CraftPanel:IgnoringLimit() and line.roomInCrafts or nil

    if room then
        if room <= 0 then
            ns.Warn(("%s: you already have %d and your limit is %d, so none were queued."):format(
                line.name, line.stock or 0, line.postLimit or 0))
            return
        end

        if quantity > room then
            quantity = room
            ns.Print(("%s: queued %d, your limit of %d has room for no more."):format(
                line.name, quantity, line.postLimit or 0))
        end
    end

    ns.Queue:Add(line.recipeID, quantity)
end

--- Set this recipe's own queue entry to exactly this many.
--
-- The box on each row shows how many are queued, so typing into it or
-- pressing - and + all come here. Only the entry the player queued is
-- changed. A sub-craft the queue added to make something else is sized from
-- that parent and would come straight back, so it is left alone and the
-- player is told where to change it instead.
function CraftPanel:SetQueued(line, wanted)
    wanted = math.max(0, math.floor(tonumber(wanted) or 0))

    local _, entry = ns.Queue:Find(line.recipeID, true)
    local current = entry and entry.quantity or 0

    if wanted > current then
        QueueMore(line, wanted - current)
    elseif wanted < current then
        -- SetQuantity takes the entry off the queue once it reaches zero.
        ns.Queue:SetQuantity(line.recipeID, wanted)
    elseif not entry and wanted == 0 and ns.Queue:Find(line.recipeID) then
        ns.Print(("%s is only queued as a material for another craft. Lower that craft to need fewer."):format(line.name))
    end
end

--- The row's Craft button: make this recipe's queued crafts now.
--
-- A real click, so the game accepts it, the same as Craft next. One click
-- makes as many of the queued number as the bags have materials for.
function CraftPanel:CraftRow(line)
    if ns.Crafting:IsBusy() then
        ns.Crafting:Stop()
        self:Refresh()
        return
    end

    local _, entry = ns.Queue:Find(line.recipeID)
    if not entry then return end

    self:CraftEntry(entry)
end

--- Start one queue entry, from a row here or in the queued crafts list.
function CraftPanel:CraftEntry(entry)
    if ns.Crafting:IsBusy() then
        ns.Crafting:Stop()
    else
        ns.Crafting:Start(entry.recipeID, entry.quantity)
    end
    self:Refresh()
end

-- Room at the left of every row for the skill-up star, reserved whether one is
-- shown or not so the names stay in a straight line.
local MARK_GUTTER = 15

CraftPanel.MARK_GUTTER = MARK_GUTTER

local function CreateRow(row)
    -- The left inset clears the skill-up star's gutter; the right edge is
    -- anchored to the row rather than given a width worked out from
    -- PANEL_WIDTH. A row is not the panel's width: the list is inset 14 either
    -- side, and the scroll bar takes another 10 when it appears. The old sum
    -- came to 214 in a space 194 wide -- 184 with the bar -- so every recipe
    -- name and every detail line ran on underneath the quantity box and the
    -- Add button. Anchoring makes the width follow the row it is actually in,
    -- scroll bar and all, so the overrun cannot come back however the gutter
    -- on the left changes.
    row.mark = Theme.CreateMark(row)
    row.mark:SetPoint("TOPLEFT", 7, -4)

    -- The made item's icon at the start of the name line, as the bags draw it.
    row.icon = Theme.CreateItemIcon(row, 13)
    row.icon:SetPoint("TOPLEFT", 8 + MARK_GUTTER, -3)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("TOPLEFT", 8 + MARK_GUTTER + 17, -4)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -TEXT_INSET, -4)

    -- Full width: nothing stands to the right of this line any more, and it
    -- is the one that carries the numbers.
    row.detail = Theme.CreateLabel(row, "tiny", "muted")
    row.detail:SetPoint("TOPLEFT", 8 + MARK_GUTTER, -17)
    row.detail:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -17)

    -- Reads - [box] +, the way a number you nudge up and down usually looks.
    -- The box is how many are queued: + and - change it by one, or type the
    -- number you want.
    row.add = Widgets.CreateButton(row, "+", function()
        if row.data then QueueMore(row.data, 1) end
    end, { width = STEP_WIDTH, height = 15, primary = true })
    row.add:SetPoint("TOPRIGHT", -8, -1)

    row.quantity = Widgets.CreateNumberBox(row, {
        width = QUANTITY_WIDTH,
        height = 15,
        background = "panel",
        min = 0,
        onChange = function(value)
            if row.data then CraftPanel:SetQueued(row.data, value) end
        end,
    })
    row.quantity:SetPoint("RIGHT", row.add, "LEFT", -STEP_GAP, 0)

    row.remove = Widgets.CreateButton(row, "-", function()
        if row.data then CraftPanel:SetQueued(row.data, row.data.queued - 1) end
    end, { width = STEP_WIDTH, height = 15 })
    row.remove:SetPoint("RIGHT", row.quantity, "LEFT", -STEP_GAP, 0)

    -- Only on rows with something queued, so the names on the rest keep
    -- their room.
    row.craft = Widgets.CreateButton(row, "Craft", function()
        if row.data then CraftPanel:CraftRow(row.data) end
    end, { width = CRAFT_WIDTH, height = 15, primary = true })
    row.craft:SetPoint("RIGHT", row.remove, "LEFT", -CRAFT_GAP, 0)
    row.craft:Hide()
end

--- How much of this you already have, as a phrase, or nil for none.
--
-- Listed is called out separately from the rest because the two mean different
-- things when deciding what to make: stock in your bags is ready to list, and
-- stock on the auction house is already competing with anything else you post.
local function StockText(line)
    local stock = line.stock or 0

    -- Nothing held says nothing: "have 0 of 5" on every row was most of what
    -- pushed the line off the end.
    if line.postLimit and line.postLimit > 0 and (stock > 0 or line.atPostLimit) then
        local text = ("have %d of %d"):format(stock, line.postLimit)
        if line.atPostLimit then return text .. ", at your limit" end
        return text
    end

    if stock <= 0 then return nil end

    if line.postLimit and line.postLimit > 0 then return nil end

    if (line.posted or 0) > 0 then
        return ("have %d, %d listed"):format(stock, line.posted)
    end

    return ("have %d"):format(stock)
end

local function UpdateRow(row, line)
    row.name:SetText(line.name)
    Theme.SetItemIcon(row.icon, line.outputItemID)

    -- Not while it is being typed into: overwriting someone mid-number is how
    -- a field ends up refusing to accept what they meant.
    if not BeingTyped(row.quantity) then
        row.quantity:SetValue(line.queued, true)
    end

    -- A queued number stands out from the zeros around it.
    row.quantity.editBox:SetTextColor(Theme.Unpack(line.queued > 0 and "accent" or "dim"))

    -- The Craft button, and room for it on the name line, only while there
    -- is something of this queued.
    local canCraftRow = line.queued > 0
    row.craft:SetShown(canCraftRow)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT",
        -(TEXT_INSET + (canCraftRow and CRAFT_INSET or 0)), -4)

    if canCraftRow then
        local busy = ns.Crafting:IsBusy()
        local ready, reason = ns.Crafting:GetReadiness(line.recipeID)
        local open = CraftPanel:GetOpenRecipeIDs()
        local here = not open or open[line.recipeID]

        row.craft:SetText(busy and "Stop" or "Craft")
        row.craft:SetEnabledState(busy or (ready and here) or false)
        row.craft.tooltipText = busy and "Stop crafting"
            or not here and "Open the profession that makes this to craft it"
            or not ready and (reason or "Nothing to make it with yet")
            or ("Craft the %d queued, as many as your materials make"):format(line.queued)
    end

    -- Rarity, the same as the Profit tab and the sell list, so the three read
    -- alike. A recipe with no sellable output has no colour to take.
    local r, g, b = Util.GetItemQualityColor(line.outputItemID)

    if r then
        row.name:SetTextColor(r, g, b)
    else
        row.name:SetTextColor(Theme.Unpack("text"))
    end

    -- The star marks every recipe that can still level you, orange, yellow or
    -- green, the way the game's own list does, sized by how likely the point
    -- is. Here, beside the profession window, the question is often "what
    -- levels me" rather than "what pays", so the Profit tab's rule (a skill
    -- up that also pays) hid nearly every star. Grey never gets one.
    local tier = line.skillUpTier
    Theme.SetMark(row.mark, tier ~= "trivial" and tier or nil)

    -- What it is worth, and whether you can make one right now: the two things
    -- that decide whether this recipe is the one you want.
    local parts = {}

    if line.priceable then
        parts[#parts + 1] = ("%s each"):format(
            Util.FormatMoney(line.profit, { noColor = true, short = true }))
    elseif line.soulbound then
        -- The whole reason is in the tooltip; the row has room for one word.
        parts[#parts + 1] = "soulbound"
    else
        parts[#parts + 1] = line.reason or "no price data"
    end

    parts[#parts + 1] = line.craftable > 0
        and ("can make %d"):format(line.craftable)
        or "no materials"

    -- What you already hold, listed or otherwise. This is the number the pane
    -- was missing: "9 listed" changes the answer to "what should I make next"
    -- more than anything else on the row does.
    local stockText = StockText(line)
    if stockText then parts[#parts + 1] = stockText end

    if line.queued > 0 then
        parts[#parts + 1] = ("queued %d"):format(line.queued)
    end

    row.detail:SetText(table.concat(parts, " · "))

    local limitApplies = line.atPostLimit and not CraftPanel:IgnoringLimit()

    if limitApplies then
        row.detail:SetTextColor(Theme.Unpack("warn"))
    elseif line.priceable and line.profit < 0 then
        row.detail:SetTextColor(Theme.Unpack("loss"))
    elseif line.queued > 0 then
        row.detail:SetTextColor(Theme.Unpack("accent"))
    else
        row.detail:SetTextColor(Theme.Unpack("muted"))
    end

    if limitApplies then
        row.add.tooltipText = ("You already have %d %s, which is your limit. Tick Ignore max on hand, or raise it in Settings, to queue more."):format(
            line.stock or 0, line.name)
    else
        row.add.tooltipText = ("Queue one more %s. Or type how many you want in the box."):format(line.name)
    end

    -- Greyed out with nothing of this recipe's own in the queue, so the
    -- button never looks like it did something when it could not.
    row.remove:SetEnabledState(line.queued > 0)
    row.remove.tooltipText = line.queued > 0
        and ("Queue one fewer %s. Right-click the row to take all of it off."):format(line.name)
        or "Nothing of this queued yet"
end

local function ShowRowTooltip(row, line)
    ns.Widgets.ShowItemTooltip(row, "ANCHOR_LEFT", line.outputItemID, line.name)
    GameTooltip:AddLine(" ")

    if line.priceable then
        GameTooltip:AddDoubleLine("Profit each",
            Util.FormatMoney(line.profit, { noColor = true }), 0.7, 0.7, 0.7, 1, 1, 1)
    else
        GameTooltip:AddLine(line.reason or "No price data for this yet", 0.9, 0.38, 0.31)
    end

    -- Above materials, because on a profession still climbing it is the thing
    -- that decides what to make with them.
    if line.skillUpTier then
        local r, g, b = ns.SkillUp:GetTierColor(line.skillUpTier)
        GameTooltip:AddDoubleLine("Skill up",
            ns.SkillUp:GetTierLabel(line.skillUpTier), 0.7, 0.7, 0.7, r, g, b)

        if line.skillUpStale then
            GameTooltip:AddLine("Read at a lower skill. It may have gone green since.",
                0.91, 0.76, 0.35, true)
        end
    end

    GameTooltip:AddDoubleLine("Materials for", tostring(line.craftable),
        0.7, 0.7, 0.7, 1, 1, 1)

    -- Stock first: it is the thing that decides whether to make more at all,
    -- where the profit above only says what one is worth.
    local stockText = StockText(line)

    if stockText then
        if line.atPostLimit then
            GameTooltip:AddDoubleLine("Already have", stockText,
                0.7, 0.7, 0.7, 0.95, 0.65, 0.25)
        else
            GameTooltip:AddDoubleLine("Already have", stockText, 0.7, 0.7, 0.7, 1, 1, 1)
        end
    end

    if line.queued > 0 then
        GameTooltip:AddDoubleLine("Already queued", tostring(line.queued),
            0.7, 0.7, 0.7, 0.78, 0.64, 0.30)
    end

    GameTooltip:AddLine("Left-click to queue, right-click to remove.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

--- Left-click queues, right-click takes it back off.
--
-- The + button is the discoverable way in; this is for working down a list
-- quickly, where reaching for the same small button every time is the slow part.
local function OnRowClick(line, _, mouseButton, row)
    if mouseButton == "RightButton" then
        ns.Queue:Remove(line.recipeID)
        return
    end

    QueueMore(line, 1)
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

    -- Opening the pane again sorts afresh (see CraftPanel:OrderKey).
    frame:HookScript("OnHide", function()
        CraftPanel.orderKey, CraftPanel.heldOrder = nil, nil
    end)

    Theme.Fill(frame, "window")
    Theme.AddGameOutline(frame, { style = "dialog", color = "natural" })

    local header, title = ns.Collapse.CreateHeader(frame, "Craft queue")
    self.title = title

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
            CraftPanel:ApplyHeight()
            CraftPanel:Refresh()
        end,
    })

    -- Profit order is the useful default -- it answers "what should I make" --
    -- but a pane you came to in order to find one specific recipe needs the
    -- alphabet, so the order is a single click away rather than a setting.
    self.sortBy = self.sortBy or "profit"

    local sort = Widgets.CreateButton(body, "", function()
        local nextIndex = 1
        for index, key in ipairs(SORT_ORDER) do
            if key == CraftPanel.sortBy then nextIndex = index % #SORT_ORDER + 1 end
        end
        CraftPanel.sortBy = SORT_ORDER[nextIndex]
        CraftPanel:UpdateSortButton()
        CraftPanel:Refresh()
    end, { width = 116, height = 18, tooltip = "Change the order of this list" })
    -- On the header strip, though it folds away with the body.
    sort:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    self.sortButton = sort
    self:UpdateSortButton()

    -- Coalesced rather than refreshed per keystroke: every refresh prices
    -- every recipe the profession is showing, and typing "copper" would
    -- otherwise do that six times before the word is finished.
    local search = Widgets.CreateSearchBox(body, "Search recipes", function()
        CraftPanel:RequestRefresh()
    end)
    -- One anchor and an explicit size. A TOPLEFT under the title plus a
    -- TOPRIGHT on the frame would set this box's top twice, from two frames
    -- that disagree about where it is, and the client resolves that by
    -- quietly dropping one of the two.
    search:SetPoint("TOPLEFT", 14, ns.Collapse.CONTENT_TOP)
    search:SetSize(PANEL_WIDTH - 28, 22)
    self.search = search

    local divider = Theme.CreateDivider(body)
    divider:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, 0)

    local list = Widgets.CreateScrollList(body, {
        rowHeight = ROW_HEIGHT,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onClick = OnRowClick,
        onEnter = ShowRowTooltip,
        onLeave = function() GameTooltip:Hide() end,
    })
    list:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 94)
    self.list = list

    local empty = Theme.CreateLabel(body, "small", "dim", "CENTER")
    empty:SetPoint("CENTER", list, "CENTER")
    empty:SetWidth(PANEL_WIDTH - 40)
    empty:SetWordWrap(true)
    self.empty = empty

    -- Crafting needs a hardware event, so this is a real click each time: one
    -- click runs one queue entry to completion. Same call the Queue tab makes,
    -- so working from either place behaves identically.
    -- A shelf behind the controls along the bottom, under a lit rule, so the
    -- list ends clearly where the buttons begin.
    ns.Collapse.CreateFooter(body, 78)

    local craft = Widgets.CreateButton(body, "Craft next", function()
        if ns.Crafting:IsBusy() then
            ns.Crafting:Stop()
        else
            -- The same scoped lookup the button's label came from, so a
            -- click can never start something other than what it offered.
            local entry = CraftPanel:GetNextReadyHere()
            if entry then
                ns.Crafting:Start(entry.recipeID, entry.quantity)
            end
        end

        CraftPanel:Refresh()
    end, { width = PANEL_WIDTH - 28, height = 24, primary = true })
    craft:SetPoint("BOTTOMLEFT", 14, 40)
    self.craftButton = craft

    -- The Keep in stock limit (Settings) hides crafts you already hold enough
    -- of and caps what + will queue. Ticking this lifts both, for this pane
    -- only, without changing the limit itself. Remembered between sessions.
    local ignoreLimit = Widgets.CreateCheckbox(body, "Ignore max on hand", function(checked)
        ns.Config:Set("craftPaneIgnoreLimit", checked)
        CraftPanel:Refresh()
    end, self:IgnoringLimit())
    ignoreLimit:SetPoint("BOTTOMLEFT", 14, 70)
    ignoreLimit:HookScript("OnEnter", function(box)
        GameTooltip:SetOwner(box, "ANCHOR_TOP")
        GameTooltip:SetText("Ignore max on hand", 1, 1, 1)
        GameTooltip:AddLine("Ticked: every craft is listed, even ones you already hold your Keep in stock amount of, and the boxes queue the full number you type. Your setting is not changed.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    ignoreLimit:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.ignoreLimitBox = ignoreLimit

    -- Room left of the two buttons at the bottom right.
    local summaryWidth = PANEL_WIDTH - 28 - QUEUE_TAB_WIDTH - CLEAR_WIDTH - 12

    local summary = Theme.CreateLabel(body, "tiny", "muted")
    summary:SetPoint("BOTTOMLEFT", 14, 22)
    summary:SetWidth(summaryWidth)
    self.summary = summary

    -- While a craft casts, a progress bar takes the summary line's place.
    local progress = ns.CraftProgress:Create(body, {
        width = summaryWidth, height = 16, covers = summary,
    })
    progress:SetPoint("LEFT", summary, "LEFT", 0, 0)
    self.progress = progress

    local openQueue = Widgets.CreateButton(body, "Queue tab", function()
        ns.UI:Show()
        ns.UI:SelectTab("queue")
    end, { width = QUEUE_TAB_WIDTH, height = 18, tooltip = "Open the full queue, with its shopping list" })
    openQueue:SetPoint("BOTTOMRIGHT", -14, 18)

    -- A queue can take a while to build, so emptying it takes a second click.
    local clear = Widgets.CreateButton(body, "Clear queue", function()
        CraftPanel:OnClearClicked()
    end, { width = CLEAR_WIDTH, height = 18 })
    clear:SetPoint("RIGHT", openQueue, "LEFT", -6, 0)
    self.clearButton = clear

    self.frame = frame
    return frame
end

--- Clear queue: the first click asks, a second click within a few seconds
--- empties the queue. Left alone, the button goes back to how it was.
function CraftPanel:OnClearClicked()
    local now = GetTime()

    if self.clearArmedUntil and now < self.clearArmedUntil then
        self.clearArmedUntil = nil
        local count = ns.Queue:Count()
        ns.Queue:Clear()
        ns.Print(("Craft queue cleared (%d entr%s)."):format(count, count == 1 and "y" or "ies"))
        self:UpdateClearButton()
        return
    end

    self.clearArmedUntil = now + CLEAR_CONFIRM_SECONDS
    self:UpdateClearButton()

    if C_Timer and C_Timer.After then
        C_Timer.After(CLEAR_CONFIRM_SECONDS, function()
            if CraftPanel.clearArmedUntil and GetTime() >= CraftPanel.clearArmedUntil then
                CraftPanel.clearArmedUntil = nil
            end
            CraftPanel:UpdateClearButton()
        end)
    end
end

function CraftPanel:UpdateClearButton()
    local button = self.clearButton
    if not button then return end

    local empty = ns.Queue:Count() == 0
    if empty then self.clearArmedUntil = nil end

    local armed = self.clearArmedUntil ~= nil and GetTime() < self.clearArmedUntil

    button:SetText(armed and "Click to clear" or "Clear queue")
    button:SetEnabledState(not empty)
    if armed then button.label:SetTextColor(Theme.Unpack("loss")) end

    button.tooltipText = empty and "The queue is empty"
        or armed and "Click again to empty the whole craft queue"
        or "Empty the whole craft queue. Asks you to click again first."
end

function CraftPanel:UpdateSortButton()
    if not self.sortButton then return end

    self.sortButton:SetText("Sort by: " .. (SORT_LABEL[self.sortBy] or "Profit"))
    self.sortButton.tooltipText = ({
        profit = "Best-paying crafts first. Click to sort by Level Up.",
        levelup = "Best chance of a skill up first (orange, yellow, green), cheapest materials first within each colour. Click to sort by name.",
        name = "Sorted by name. Click to sort by profit.",
    })[self.sortBy]
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
        --
        -- Offset past the profession tabs down the window's right-hand edge,
        -- which stick out beyond the frame GetRight() reports. Still anchored
        -- to the frame rather than to a screen position, so the pane keeps
        -- moving with the window.
        local overhang = self:RightOverhang(tradeSkillFrame)

        frame:SetPoint("TOPLEFT", tradeSkillFrame, "TOPRIGHT", overhang + PANEL_GAP, 0)
        frame:SetHeight(ns.Collapse.Height(COLLAPSE_KEY,
            self:DesiredHeight(tradeSkillFrame) or PANEL_FALLBACK_HEIGHT))

        ns.Debug("docked craft pane to", frameName, "clearing", overhang)
    else
        -- Blizzard's profession UI is load-on-demand and may not exist yet.
        -- A pane in a slightly odd place beats one that silently never appears.
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
        frame:SetHeight(ns.Collapse.Height(COLLAPSE_KEY, PANEL_FALLBACK_HEIGHT))

        ns.Debug("no profession frame found; using fallback position")
    end

    frame:Show()
    self:Refresh()
end

function CraftPanel:IsCollapsed()
    return ns.Collapse.IsCollapsed(COLLAPSE_KEY)
end

--- Set the height outright, after folding or unfolding.
function CraftPanel:ApplyHeight()
    if not self.frame then return end

    local tradeSkillFrame = self:FindTradeSkillFrame()
    local full = tradeSkillFrame and self:DesiredHeight(tradeSkillFrame)

    self.frame:SetHeight(ns.Collapse.Height(COLLAPSE_KEY, full or PANEL_FALLBACK_HEIGHT))
end

--- Re-measure, for a profession window that changed size after it opened.
function CraftPanel:Reflow()
    if not self.frame or not self.frame:IsShown() then return end

    local tradeSkillFrame = self:FindTradeSkillFrame()
    if not tradeSkillFrame then return end

    local height = self:DesiredHeight(tradeSkillFrame)
    if height then height = ns.Collapse.Height(COLLAPSE_KEY, height) end

    -- Only when it actually moved: setting the height relayouts the list, and
    -- this runs on every refresh.
    if height and math.abs(height - self.frame:GetHeight()) > 0.5 then
        self.frame:SetHeight(height)
    end

    -- The tabs are not always laid out at the moment the window first opens,
    -- so the clearance is re-measured rather than settled once at attach.
    local point, relativeTo, relativePoint, x, y = self.frame:GetPoint()

    -- Only ever adjusts the docked anchor. Attached before the profession
    -- window existed, the pane is pinned to the screen edge instead, and
    -- writing a dock offset into that anchor would fling it across the screen.
    -- Attach puts it right; this must not be what moves it.
    if point ~= "TOPLEFT" or relativeTo ~= tradeSkillFrame then return end

    local wanted = self:RightOverhang(tradeSkillFrame) + PANEL_GAP

    if x and math.abs(wanted - x) > 0.5 then
        self.frame:SetPoint(point, relativeTo, relativePoint, wanted, y or 0)
    end
end

--- The next queued craft *this* profession window can actually make.
--
-- `Crafting:GetNextReady` walks the whole queue and asks only whether the
-- character could make each entry, which is the right question for the Queue
-- tab and the wrong one here. Standing at Enchanting with tailoring queued, it
-- answered "Bolt of Linen Cloth", and `C_TradeSkillUI.CraftRecipe` on a recipe
-- the open window does not have fails without saying anything -- this client
-- shows no Lua error unless scriptErrors is on, so the button would simply
-- have done nothing, forever, with no way to tell that from a dead button.
--
-- Scoped by the open window's own recipe list rather than by comparing skill
-- line IDs: this client reports each profession under two different ID spaces
-- (a modern one and a legacy one), so an ID comparison is a trap.
--
-- @return entry, readyElsewhere -- a ready craft for another profession is
--   counted rather than offered, so the button can say which.
function CraftPanel:GetNextReadyHere()
    local open = self:GetOpenRecipeIDs()
    local readyElsewhere = 0

    for _, entry in ipairs(ns.Queue:GetAll()) do
        if ns.Crafting:GetReadiness(entry.recipeID) then
            -- No open set means the client would not say which profession is
            -- showing. Offering the craft is then the best available guess,
            -- and matches what the Queue tab does.
            if not open or open[entry.recipeID] then
                return entry, readyElsewhere
            end

            readyElsewhere = readyElsewhere + 1
        end
    end

    return nil, readyElsewhere
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

    local entry, readyElsewhere = self:GetNextReadyHere()

    if not entry then
        button:SetText("Craft next")
        button:SetEnabledState(false)

        if readyElsewhere > 0 then
            -- Ready, but not at this window. Say so, rather than reporting the
            -- first entry's obstacle: "need materials" would be a lie about a
            -- craft whose materials are sitting in the bags.
            button.tooltipText = ("%d queued craft%s ready, but for another profession. Open that profession to make %s."):format(
                readyElsewhere, readyElsewhere == 1 and " is" or "s are",
                readyElsewhere == 1 and "it" or "them")
            return
        end

        -- Report the first entry's actual obstacle rather than a generic one.
        local _, reason = ns.Crafting:GetReadiness(ns.Queue:GetAll()[1].recipeID)
        button.tooltipText = reason or "Nothing here can be made yet"
        return
    end

    local recipe = ns.Recipes:GetAny(entry.recipeID)
    local canMake = math.min(entry.quantity, ns.Profit:GetCraftableCount(entry.recipeID))

    button:SetText(("Craft %dx %s"):format(canMake, (recipe and recipe.name) or "item"))
    button:SetEnabledState(true)
    button.tooltipText = "One click makes every craft in this entry"
end

function CraftPanel:Refresh()
    if not self.frame or not self.frame:IsShown() then return end

    self:Reflow()

    -- Folded away there is nothing to fill in, and filling it in prices every
    -- recipe the profession shows. The title carries the queue count instead.
    if self:IsCollapsed() then
        local queued = ns.Queue:Count()
        self.title:SetText(queued > 0
            and ("Craft queue (%d queued)"):format(queued)
            or "Craft queue")
        self:RefreshQueued()
        return
    end

    self.title:SetText("Craft queue")

    local opts = {
        search = self.search and self.search:GetText() or "",
        sortBy = self.sortBy,
        ignoreLimit = self:IgnoringLimit(),
    }

    local key = self:OrderKey(opts)
    if key ~= self.orderKey then
        self.orderKey, self.heldOrder = key, nil
    end
    opts.keepOrder = self.heldOrder

    local rows = self:GetRows(opts)

    self.heldOrder = {}
    for index, row in ipairs(rows) do
        self.heldOrder[row.recipeID] = index
    end

    self.list:SetData(rows)
    self.empty:SetShown(#rows == 0)

    if #rows == 0 then
        local searching = self.search and self.search:GetText() ~= ""

        self.empty:SetText(searching
            and "Nothing here matches that."
            or "No recipes read for this profession yet.\n\nThey are read as the window opens; give it a moment.")
    end

    self:UpdateCraftButton()
    self:UpdateClearButton()
    self:RefreshQueued()

    local queued = ns.Queue:Count()

    if queued == 0 then
        self.summary:SetText("Nothing queued")
        self.summary:SetTextColor(Theme.Unpack("dim"))
        return
    end

    local totals = ns.Queue:GetTotals()

    -- The profit in its own colour: green when the queue pays, red when not.
    -- Kept short: it shares the bottom line with Clear queue and Queue tab.
    self.summary:SetText(("%d queued · profit |c%s%s|r%s"):format(
        totals.crafts,
        (totals.profit or 0) < 0 and ns.COLORS.loss or ns.COLORS.profit,
        Util.FormatMoney(totals.profit, { noColor = true, short = true }),
        totals.priceable and "" or " (some unpriced)"))
    self.summary:SetTextColor(Theme.Unpack("muted"))
end

--------------------------------------------------------------------------------
-- Queued crafts, beside the pane
--------------------------------------------------------------------------------

-- Trent, 2026-09-28: "show the crafting queue out to the right of this Craft
-- queue window once things are queued." The queue itself, in the order it is
-- worked through, each entry with its own Craft button, so nothing here needs
-- the main window. A child of the pane, so it hides whenever the pane does.

local QUEUED_WIDTH = 250
local QUEUED_ROW_HEIGHT = 30
local QUEUED_GAP = 4

CraftPanel.QUEUED_WIDTH = QUEUED_WIDTH

--- What the queued list says under an entry's name, and whether its Craft
--- button can be pressed.
--
-- @param open the open profession's recipe set, or nil when the game will not say
-- @return text, colour key, craftable here
function CraftPanel:QueuedStatus(entry, open)
    local active = ns.Crafting.active
    if active and active.recipeID == entry.recipeID then
        return "crafting now", "accent", true
    end

    local ready, reason = ns.Crafting:GetReadiness(entry.recipeID)
    local here = not open or open[entry.recipeID]

    if ready and here then
        local canMake = math.min(entry.quantity,
            ns.Profit:GetCraftableCount(entry.recipeID) or 0)
        return ("ready, materials for %d"):format(canMake), "profit", true
    end

    if ready then return "ready, in another profession", "muted", false end

    return reason or "missing materials", "muted", false
end

local function CreateQueuedRow(row)
    row.icon = Theme.CreateItemIcon(row, 13)
    row.icon:SetPoint("TOPLEFT", 8, -3)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("TOPLEFT", 25, -4)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(8 + 16 + 4 + CRAFT_WIDTH + 6), -4)

    row.detail = Theme.CreateLabel(row, "tiny", "muted")
    row.detail:SetPoint("TOPLEFT", 8, -17)
    row.detail:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -17)

    row.remove = Widgets.CreateButton(row, "x", function()
        if row.data then ns.Queue:Remove(row.data.recipeID) end
    end, { width = 16, height = 15, tooltip = "Take this off the queue" })
    row.remove:SetPoint("TOPRIGHT", -8, -1)

    row.craft = Widgets.CreateButton(row, "Craft", function()
        if row.data then CraftPanel:CraftEntry(row.data) end
    end, { width = CRAFT_WIDTH, height = 15, primary = true })
    row.craft:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
end

local function UpdateQueuedRow(row, entry)
    local recipe = ns.Recipes:GetAny(entry.recipeID)

    row.name:SetText(("%dx %s"):format(entry.quantity,
        (recipe and recipe.name) or ("recipe " .. tostring(entry.recipeID))))
    Theme.SetItemIcon(row.icon, recipe and recipe.outputItemID)

    local r, g, b = Util.GetItemQualityColor(recipe and recipe.outputItemID)
    if r then row.name:SetTextColor(r, g, b) else row.name:SetTextColor(Theme.Unpack("text")) end

    local status, colour, craftable = CraftPanel:QueuedStatus(entry, CraftPanel.queuedOpen)

    -- A material the queue added for another craft says which, as the Queue
    -- tab does, and has no x: it is sized from that craft.
    if entry.isDependency then
        local parents = ns.Queue:GetDependencyParents(entry)
        status = ("for %s · %s"):format(
            #parents > 0 and table.concat(parents, ", ") or "another craft", status)
    end

    row.detail:SetText(status)
    row.detail:SetTextColor(Theme.Unpack(colour))

    row.remove:SetShown(not entry.isDependency)

    local busy = ns.Crafting:IsBusy()
    row.craft:SetText(busy and "Stop" or "Craft")
    row.craft:SetEnabledState(busy or craftable)
    row.craft.tooltipText = busy and "Stop crafting"
        or craftable and "Craft these now, as many as your materials make"
        or status
end

function CraftPanel:BuildQueued()
    if self.queuedFrame then return self.queuedFrame end

    local frame = CreateFrame("Frame", nil, self.frame)
    frame:SetWidth(QUEUED_WIDTH)
    frame:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", QUEUED_GAP, 0)
    frame:EnableMouse(true)
    frame:Hide()

    Theme.Fill(frame, "window")
    Theme.AddGameOutline(frame, { style = "dialog", color = "natural" })

    local _, title = ns.Collapse.CreateHeader(frame, "Queued crafts")
    self.queuedTitle = title

    local list = Widgets.CreateScrollList(frame, {
        rowHeight = QUEUED_ROW_HEIGHT,
        createRow = CreateQueuedRow,
        updateRow = UpdateQueuedRow,
        onClick = function(entry, _, mouseButton)
            if mouseButton == "RightButton" and not entry.isDependency then
                ns.Queue:Remove(entry.recipeID)
            end
        end,
    })
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, ns.Collapse.CONTENT_TOP)
    list:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    self.queuedList = list

    self.queuedFrame = frame
    return frame
end

--- Show the queued crafts beside the pane while anything is queued.
function CraftPanel:RefreshQueued()
    local wanted = self.frame and self.frame:IsShown()
        and not self:IsCollapsed() and ns.Queue:Count() > 0

    if not wanted then
        if self.queuedFrame then self.queuedFrame:Hide() end
        return
    end

    local entries = ns.Queue:GetAll()

    local frame = self:BuildQueued()
    frame:SetHeight(self.frame:GetHeight())
    frame:Show()

    self.queuedTitle:SetText(("Queued crafts (%d)"):format(#entries))
    self.queuedOpen = self:GetOpenRecipeIDs()
    self.queuedList:SetData(entries)
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
            #self:GetRows({ sortBy = self.sortBy, ignoreLimit = self:IgnoringLimit() })))
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
