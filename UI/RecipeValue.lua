-- Blackthornes Tradeskills -- UI/RecipeValue.lua
-- What each recipe is worth, written into Blizzard's own profession list.
--
-- The craft pane beside the profession window already answers "what should I
-- make next". This answers a smaller question in the place you are already
-- looking: standing in front of the recipe list, what does one of these sell
-- for. A value beside the name means not having to read across to another
-- frame to find out.
--
-- Nothing here is assumed about the shape of Blizzard's list, because this
-- client is not retail and a wrong guess about a frame is silent: the value
-- simply never appears, which looks exactly like the addon not being loaded.
-- So the list is *discovered* -- several shapes are tried in order, each one
-- is judged by whether its rows actually name recipes this character knows,
-- and the one that worked is remembered. `/bts value` then reports which it
-- was and how many rows are carrying a value right now. That report is the
-- observation; everything else here is a guess until it has been read in game.
--
-- Blizzard's frames are read, hooked and given a child FontString. None of
-- them is assigned to, and no field is written onto one: the labels live in a
-- weak table keyed by the row, so a Blizzard frame carries nothing of ours.

local _, ns = ...

local RecipeValue = ns.NewModule("RecipeValue")

local Util = ns.Util

-- Candidate globals for Blizzard's profession window, the same two
-- UI/CraftPanel.lua docks against. Both are load-on-demand, so either may be
-- absent until the player first opens a profession this session.
local FRAME_NAMES = { "ProfessionsFrame", "TradeSkillFrame" }

-- Paths from the profession window down to whatever holds the recipe rows.
-- Tried in order; the first one whose rows name recipes is remembered.
local LIST_PATHS = {
    "CraftingPage.RecipeList.ScrollBox",
    "CraftingPage.RecipeList",
    "RecipeList.ScrollBox",
    "RecipeList",
    "RecipeListContainer.ScrollBox",
    "ScrollBox",
}

-- Legacy lists number their rows as globals instead of parenting them to a
-- scroll box. Far more than any client shows at once; the walk stops at the
-- first name that does not exist.
local LEGACY_ROW_PREFIX = "TradeSkillSkill"
local LEGACY_ROW_LIMIT = 40

-- Gap between the end of the recipe name and the value.
local NAME_GAP = 8

-- Used when the row's name cannot be found, or the name is long enough that a
-- value beside it would run off the row.
local RIGHT_INSET = 6

-- How often the visible rows are re-read while a profession window is open.
-- Scrolling recycles rows rather than firing an event, so a row that was
-- "Copper Chain Belt" a moment ago is now a different recipe with our old
-- value still on it. The work is a table lookup per visible row.
local REFRESH_SECONDS = 0.25

-- A recipe name owned by two recipes cannot be matched back to one of them, so
-- the name fallback drops it rather than guessing.
local AMBIGUOUS = "ambiguous"

-- Caps on the last-resort walk of Blizzard's frame tree. An unbounded walk of
-- somebody else's UI is not something to run beside a game.
local SEARCH_DEPTH = 5
local SEARCH_NODES = 400

--------------------------------------------------------------------------------
-- Talking to frames that may not answer
--------------------------------------------------------------------------------

-- This client has gaps in the frame API, and a missing method turns a refresh
-- into an error rather than a blank row. Every call into a Blizzard frame goes
-- through one of these two, which return nil rather than raising -- and nil
-- rather than the *error message*, which is what a bare
-- `select(2, pcall(...))` hands back and is truthy.

local function Try(fn, ...)
    if type(fn) ~= "function" then return nil end

    local ok, value = pcall(fn, ...)
    if ok then return value end

    return nil
end

local function Field(object, key)
    if type(object) ~= "table" then return nil end

    local ok, value = pcall(function() return object[key] end)
    if not ok then return nil end

    return value
end

--------------------------------------------------------------------------------
-- What a recipe is worth
--------------------------------------------------------------------------------

--- Market value of one of what this recipe makes, or nil when unknown.
--
-- Deliberately the per-item market value rather than the profit: the question
-- asked at the profession window is "what does this sell for", and profit has
-- a column of its own in the craft pane.
--
-- Nil covers three different unknowns -- no such recipe, a recipe that makes
-- no sellable item, and an item nothing has ever been seen selling for -- and
-- all three print nothing at all. A zero would read as "worthless", which is a
-- different and much more expensive claim.
function RecipeValue:ValueFor(recipeID)
    if not recipeID then return nil end
    if not ns.Recipes or not ns.Prices then return nil end

    local recipe = ns.Recipes:GetAny(recipeID)
    if not recipe or not recipe.outputItemID then return nil end

    local value = ns.Prices:GetValue(recipe.outputItemID, "market")

    -- A stored zero is a price record that never saw a listing, not an item
    -- somebody is selling for nothing.
    if not value or value <= 0 then return nil end

    return value, recipe.outputItemID
end

--- The text to put beside the name, or nil to leave the row alone.
function RecipeValue:TextFor(recipeID)
    local value = self:ValueFor(recipeID)
    if not value then return nil end

    return Util.FormatMoney(value, { short = true })
end

--- Is the decoration switched on?
--
-- `~= false` rather than `== true`: a setting that has never been written is
-- nil, and this one is on by default.
function RecipeValue:IsEnabled()
    if not ns.Config then return true end
    return ns.Config:Get("showValueInProfessionWindow") ~= false
end

--------------------------------------------------------------------------------
-- Which recipe a row is showing
--------------------------------------------------------------------------------

--- Every place a recipe ID has been found hiding on or under a row.
--
-- A modern list hands each row an element data node; the node may be the
-- recipe info, may hold it, or may have to be asked for it. None of that is
-- worth asserting from here, so all of it is tried and the first answer wins.
local function RecipeIDFromData(data, depth)
    depth = depth or 0

    if type(data) ~= "table" or depth > 3 then return nil end

    if type(data.recipeID) == "number" then return data.recipeID end

    local info = Field(data, "recipeInfo")
    if type(info) == "table" and type(info.recipeID) == "number" then
        return info.recipeID
    end

    -- A tree node wraps the real thing.
    local inner = Try(Field(data, "GetData"), data)
    local found = RecipeIDFromData(inner, depth + 1)
    if found then return found end

    return RecipeIDFromData(Field(data, "data"), depth + 1)
end

--- Name -> recipe ID, for rows that will not say which recipe they are.
--
-- Built from the addon's recipe cache rather than from the client, so it
-- covers exactly the recipes the addon can price anyway. A name owned by two
-- recipes matches neither: putting one recipe's price on another's row would
-- be worse than printing nothing.
function RecipeValue:BuildNameIndex()
    local index = {}

    if ns.Recipes then
        for recipeID, recipe in pairs(ns.Recipes:GetAll()) do
            local name = recipe.name

            if type(name) == "string" and name ~= "" then
                local key = name:lower()

                if index[key] == nil then
                    index[key] = recipeID
                elseif index[key] ~= recipeID then
                    index[key] = AMBIGUOUS
                end
            end
        end
    end

    self.nameIndex = index
    self.nameIndexFor = ns.Recipes and ns.Recipes:Count() or 0

    return index
end

--- The name index, rebuilt only when the recipe cache has changed size.
--
-- The cache fills as the client hands recipes over, so an index built once at
-- the first refresh would leave rows blank for the rest of the session. It is
-- also read four times a second while a profession window is open, and
-- rebuilding it from several hundred recipes that often is work nobody asked
-- for.
function RecipeValue:EnsureNameIndex()
    local count = ns.Recipes and ns.Recipes:Count() or 0

    if not self.nameIndex or self.nameIndexFor ~= count then
        return self:BuildNameIndex()
    end

    return self.nameIndex
end

--- The recipe a row's visible text names, or nil.
--
-- Blizzard decorates its own row text -- a colour escape, a count in brackets,
-- padding -- so the text is stripped back to a name before it is looked up.
function RecipeValue:RecipeIDForName(text)
    if type(text) ~= "string" then return nil end

    local name = text
        :gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", "")
        :gsub("%s*%[%s*%d+%s*/%s*%d+%s*%]%s*$", "")
        :gsub("%s*%[%s*%d+%s*%]%s*$", "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")

    if name == "" then return nil end

    local index = self:EnsureNameIndex()
    local found = index[name:lower()]

    if found == AMBIGUOUS then return nil end

    return found
end

-- Named fields first, because a row offering one is telling us where its name
-- is; the scan below is for rows that do not.
local NAME_FIELDS = { "Text", "Label", "Name", "SkillName", "text", "name" }

local function IsFontString(region)
    return type(region) == "table"
        and type(Field(region, "GetStringWidth")) == "function"
        and type(Field(region, "GetText")) == "function"
end

local function TextOf(region)
    if not IsFontString(region) then return nil end

    local text = Try(Field(region, "GetText"), region)
    if type(text) ~= "string" or text == "" then return nil end

    return text
end

--- The leftmost piece of text on a row, which is the recipe's name.
local function NameRegion(row)
    if type(row) ~= "table" then return nil end

    for i = 1, #NAME_FIELDS do
        local region = Field(row, NAME_FIELDS[i])
        if TextOf(region) then return region end
    end

    local regions = Try(function() return { row:GetRegions() } end)
    if type(regions) ~= "table" then return nil end

    local best, bestLeft

    for i = 1, #regions do
        local region = regions[i]

        if TextOf(region) then
            local left = Try(Field(region, "GetLeft"), region)

            if type(left) == "number" then
                if not bestLeft or left < bestLeft then
                    best, bestLeft = region, left
                end
            elseif not best then
                best = region
            end
        end
    end

    return best
end

RecipeValue.NameRegion = NameRegion

--- Which recipe this row is showing: from its data if it says, else its name.
--
-- @return recipeID, how it was found ("data" or "name")
function RecipeValue:RecipeForRow(row)
    if type(row) ~= "table" then return nil end

    local fromData = RecipeIDFromData(Field(row, "recipeInfo"))
        or RecipeIDFromData(Field(row, "elementData"))
        or RecipeIDFromData(Try(Field(row, "GetElementData"), row))

    if fromData then return fromData, "data" end

    local text = TextOf(NameRegion(row))
    if not text then return nil end

    local byName = self:RecipeIDForName(text)
    if byName then return byName, "name" end

    return nil
end

--------------------------------------------------------------------------------
-- Finding the rows
--------------------------------------------------------------------------------

--- Blizzard's profession window, read only and never assigned to.
function RecipeValue:FindProfessionFrame()
    for i = 1, #FRAME_NAMES do
        local frame = _G[FRAME_NAMES[i]]

        if type(frame) == "table" and Field(frame, "GetObjectType") then
            if Try(Field(frame, "GetObjectType"), frame) then
                return frame, FRAME_NAMES[i]
            end
        end
    end
end

local function Descend(frame, path)
    local current = frame

    for segment in path:gmatch("[^%.]+") do
        current = Field(current, segment)
        if current == nil then return nil end
    end

    return current
end

local function ChildrenOf(frame)
    if type(frame) ~= "table" then return nil end
    if type(Field(frame, "GetChildren")) ~= "function" then return nil end

    local children = Try(function() return { frame:GetChildren() } end)
    if type(children) ~= "table" or #children == 0 then return nil end

    return children
end

--- The row frames a list container is currently showing.
--
-- @return rows, how they were reached
local function RowsIn(container)
    if type(container) ~= "table" then return nil end

    local frames = Try(Field(container, "GetFrames"), container)
    if type(frames) == "table" and #frames > 0 then
        return frames, "GetFrames"
    end

    -- A scroll box keeps its rows on an inner frame that it slides about.
    local target = Field(container, "ScrollTarget")
    local children = ChildrenOf(target)

    if children then return children, "ScrollTarget children" end

    children = ChildrenOf(container)
    if children then return children, "children" end

    return nil
end

--- How many of these rows this addon can name a recipe for.
--
-- This is what separates the recipe list from the six other frames that also
-- have children: a candidate whose rows name nothing is not the list, however
-- promising its path looked.
function RecipeValue:CountRecipes(rows)
    local found = 0

    for i = 1, #rows do
        if self:RecipeForRow(rows[i]) then found = found + 1 end
    end

    return found
end

--- Legacy lists number their rows as globals.
local function LegacyRows()
    local rows = {}

    for i = 1, LEGACY_ROW_LIMIT do
        local row = _G[LEGACY_ROW_PREFIX .. i]
        if type(row) ~= "table" then break end
        rows[#rows + 1] = row
    end

    if #rows == 0 then return nil end

    return rows
end

--- Last resort: the frames under the profession window that name a recipe.
--
-- Slower than a named path, so its answer is remembered as a container and
-- this only runs again if that container stops producing recipes.
--
-- @return rows, their shared parent
function RecipeValue:SearchForRows(frame)
    local seen = 0
    local best, bestParent, bestCount

    local function walk(node, depth)
        if depth > SEARCH_DEPTH or seen > SEARCH_NODES then return end

        local children = ChildrenOf(node)
        if not children then return end

        local matches = {}

        for i = 1, #children do
            seen = seen + 1
            if seen > SEARCH_NODES then break end

            if self:RecipeForRow(children[i]) then
                matches[#matches + 1] = children[i]
            end
        end

        -- The parent with the most recipe-naming children is the list.
        if #matches > 0 and (not bestCount or #matches > bestCount) then
            best, bestParent, bestCount = matches, node, #matches
        end

        for i = 1, #children do
            walk(children[i], depth + 1)
        end
    end

    walk(frame, 1)

    return best, bestParent
end

--- Find the recipe rows, remembering what worked.
--
-- The remembered container is re-judged every time rather than trusted: the
-- profession window is load-on-demand and rebuilt between professions, so a
-- container that answered a minute ago can be holding nothing now.
--
-- @return rows, a phrase describing where they came from
function RecipeValue:FindRows()
    local frame, frameName = self:FindProfessionFrame()

    if not frame then return nil, "no profession window" end

    if not Try(Field(frame, "IsShown"), frame) then
        return nil, ("%s is not open"):format(frameName)
    end

    -- The name fallback reads this, and every candidate below is judged by it.
    self:EnsureNameIndex()

    -- Rows that exist but name nothing: kept only if nothing better turns up,
    -- so the report can say "12 rows, none matched a recipe" rather than
    -- "no rows found", which would send the reader looking in the wrong place.
    local emptyRows, emptyWhere

    local function consider(rows, where)
        if not rows then return nil end

        if self:CountRecipes(rows) > 0 then return rows, where end

        if not emptyRows then emptyRows, emptyWhere = rows, where end

        return nil
    end

    -- What worked last time, first.
    if self.container then
        local rows, how = RowsIn(self.container)
        local kept, where = consider(rows, ("%s via %s"):format(self.containerPath or "?", how or "?"))
        if kept then return kept, where end
    end

    for i = 1, #LIST_PATHS do
        local rows, how = RowsIn(Descend(frame, LIST_PATHS[i]))
        local path = frameName .. "." .. LIST_PATHS[i]
        local kept, where = consider(rows, ("%s via %s"):format(path, how or "?"))

        if kept then
            self.container = Descend(frame, LIST_PATHS[i])
            self.containerPath = path
            self:HookContainer(self.container)

            return kept, where
        end
    end

    local kept, where = consider(LegacyRows(), "old-style recipe rows")
    if kept then
        self.container = nil
        self.containerPath = LEGACY_ROW_PREFIX .. "1.."
        return kept, where
    end

    local found, parent = self:SearchForRows(frame)
    if found then
        self.container = parent
        self.containerPath = "found by recipe name"
        return found, "found by recipe name"
    end

    if emptyRows then
        return emptyRows, ("%s, no row named a known recipe"):format(emptyWhere)
    end

    return nil, ("no recipe rows found under %s"):format(frameName)
end

--------------------------------------------------------------------------------
-- The label
--------------------------------------------------------------------------------

-- Weak keys: the label belongs to the row, but the row is Blizzard's and gets
-- no field of ours written onto it. When the client throws a row away, the
-- entry goes with it.
local labels = setmetatable({}, { __mode = "k" })

local function LabelFor(row)
    local label = labels[row]
    if label then return label end

    local create = Field(row, "CreateFontString")
    if type(create) ~= "function" then return nil end

    local created = Try(create, row, nil, "OVERLAY", "GameFontNormalSmall")
    if not created then return nil end

    labels[row] = created
    return created
end

--- Put the value just right of the name, or against the row's right edge.
--
-- `GetStringWidth` is how far the *text* reaches, which is not where the
-- name's own region ends: Blizzard gives that region the width of the whole
-- row, so anchoring to its RIGHT would put the value out past the list.
--
-- If the name is long enough that a value beside it would run off the row, the
-- value goes to the right edge instead. Overlapping the name would cost the
-- reader the thing they came for.
local function PositionLabel(label, row, region)
    label:ClearAllPoints()

    local nameWidth = region and Try(Field(region, "GetStringWidth"), region)

    if type(nameWidth) ~= "number" then
        label:SetJustifyH("RIGHT")
        label:SetPoint("RIGHT", row, "RIGHT", -RIGHT_INSET, 0)
        return
    end

    local valueWidth = Try(Field(label, "GetStringWidth"), label) or 0
    local rowRight = Try(Field(row, "GetRight"), row)
    local nameLeft = Try(Field(region, "GetLeft"), region)

    local fits = true

    if type(rowRight) == "number" and type(nameLeft) == "number" then
        fits = (nameLeft + nameWidth + NAME_GAP + valueWidth) < (rowRight - RIGHT_INSET)
    end

    if fits then
        label:SetJustifyH("LEFT")
        label:SetPoint("LEFT", region, "LEFT", nameWidth + NAME_GAP, 0)
    else
        label:SetJustifyH("RIGHT")
        label:SetPoint("RIGHT", row, "RIGHT", -RIGHT_INSET, 0)
    end
end

--- Write one row's value, or take it away.
-- @return "valued", "unpriced", "unresolved" or "nolabel"
function RecipeValue:DecorateRow(row)
    local recipeID = self:RecipeForRow(row)
    local text = recipeID and self:TextFor(recipeID) or nil

    local label = labels[row]

    if not text then
        -- Quiet, not a zero: no price data is not a price of nothing.
        if label then Try(Field(label, "Hide"), label) end
        return recipeID and "unpriced" or "unresolved"
    end

    label = label or LabelFor(row)
    if not label then return "nolabel" end

    label:SetText(text)
    PositionLabel(label, row, NameRegion(row))
    label:Show()

    return "valued"
end

--------------------------------------------------------------------------------
-- Keeping it current
--------------------------------------------------------------------------------

--- Re-read the visible rows and write their values.
--
-- @return a report: { source, rows, valued, unpriced, unresolved, nolabel }
function RecipeValue:Refresh()
    local report = { rows = 0, valued = 0, unpriced = 0, unresolved = 0, nolabel = 0 }

    if not self:IsEnabled() then
        self:HideAll()
        report.source = "switched off in Settings"
        self.lastReport = report
        return report
    end

    local rows, source = self:FindRows()
    report.source = source

    if not rows then
        self.lastReport = report
        return report
    end

    for i = 1, #rows do
        local row = rows[i]

        if Try(Field(row, "IsShown"), row) then
            report.rows = report.rows + 1

            local outcome = self:DecorateRow(row)
            report[outcome] = (report[outcome] or 0) + 1
        elseif labels[row] then
            Try(Field(labels[row], "Hide"), labels[row])
        end
    end

    self.lastReport = report
    return report
end

function RecipeValue:HideAll()
    for _, label in pairs(labels) do
        Try(Field(label, "Hide"), label)
    end
end

--- Refresh when the list redraws, as well as on the ticker.
--
-- The hook is the responsive half -- a redraw is the moment a row stops being
-- the recipe it was -- and the ticker is the half that does not depend on this
-- client having the method we hooked. Either alone has been wrong before.
function RecipeValue:HookContainer(container)
    if type(container) ~= "table" then return false end

    self.hooked = self.hooked or setmetatable({}, { __mode = "k" })
    if self.hooked[container] ~= nil then return self.hooked[container] ~= false end

    local hook = _G.hooksecurefunc

    if type(hook) ~= "function" or type(Field(container, "Update")) ~= "function" then
        self.hooked[container] = false
        return false
    end

    local ok = pcall(hook, container, "Update", function()
        RecipeValue:Refresh()
    end)

    self.hooked[container] = ok

    return ok
end

function RecipeValue:Start()
    if self.ticker then return end

    if not C_Timer or type(C_Timer.NewTicker) ~= "function" then
        self:Refresh()
        return
    end

    self.ticker = C_Timer.NewTicker(REFRESH_SECONDS, function()
        RecipeValue:Refresh()
    end)

    self:Refresh()
end

function RecipeValue:Stop()
    if self.ticker then
        Try(Field(self.ticker, "Cancel"), self.ticker)
        self.ticker = nil
    end

    -- The container belongs to a window that has closed; the next open may
    -- build a different one.
    self.container = nil
    self.containerPath = nil

    self:HideAll()
end

--------------------------------------------------------------------------------
-- Diagnostic
--------------------------------------------------------------------------------

--- What the decoration is actually doing, right now.
--
-- Reports the outcome rather than the attempt: "hooked the recipe list" would
-- be true of a list showing nothing, and that is the failure this is for.
-- Every line here is a count taken this instant.
function RecipeValue:PrintReport()
    local report = self:Refresh()

    ns.Print(("|c%sRecipe values in the profession window|r"):format(ns.COLORS.accent))

    ns.PrintRaw(("  |c%srows found|r  %s"):format(ns.COLORS.muted, report.source or "none"))

    if report.rows == 0 then
        ns.PrintRaw(("  |c%sOpen a profession window and run this again.|r"):format(
            ns.COLORS.muted))
        return
    end

    ns.PrintRaw(("  |c%svisible rows|r  %d"):format(ns.COLORS.muted, report.rows))
    ns.PrintRaw(("  |c%sshowing a value|r  %d"):format(ns.COLORS.muted, report.valued))

    if report.unpriced > 0 then
        ns.PrintRaw(("  |c%sno price data yet|r  %d  |c%s(scan the auction house)|r"):format(
            ns.COLORS.muted, report.unpriced, ns.COLORS.muted))
    end

    if report.unresolved > 0 then
        ns.PrintRaw(("  |c%srows not matched to a recipe|r  %d"):format(
            ns.COLORS.muted, report.unresolved))
    end

    if report.nolabel > 0 then
        ns.PrintRaw(("  |c%srows a value could not be added to|r  %d"):format(
            ns.COLORS.muted, report.nolabel))
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function RecipeValue:OnEnable()
    ns.RegisterEvent(self, "TRADE_SKILL_SHOW", function()
        RecipeValue:Start()

        -- The window is load-on-demand, so on the first open of a session its
        -- list may not exist yet when this event arrives.
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, function() RecipeValue:Refresh() end)
        end
    end)

    ns.RegisterEvent(self, "TRADE_SKILL_CLOSE", function()
        RecipeValue:Stop()
    end)

    ns.RegisterCommand("value",
        "show what the recipe values in the profession window are doing", function()
            RecipeValue:PrintReport()
        end)
end
