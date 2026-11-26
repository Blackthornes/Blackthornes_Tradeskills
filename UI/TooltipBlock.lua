-- Blackthornes Tradeskills -- UI/TooltipBlock.lua
-- One tidy block for every Blackthornes line on an item tooltip (the owner
-- said build it, 2026-11-21, from the UI pass mockup). One thin gold line
-- starts the block, then every addon's lines in one fixed order with no
-- blank rows between them, each a yellow name on the left and a white
-- answer on the right:
--
--   1. price    what it's worth (Tradeskills, then Butler's vendor prices)
--   2. source   where it comes from (Farmer, then Equipment's boss drop)
--   3. advice   what to do with it (Equipment, then Butler)
--   4. holders  who has it (Butler)
--
-- Lines shown only because Shift is held (`shift = true` on the line) go
-- after all the others, under a second thin gold line, in the same order
-- (the owner said build it, 2026-11-26). Holding Shift adds to the bottom;
-- nothing above moves.
--
-- "Hold Shift for more." goes last, once, when any addon held a line back.
--
-- The same file in Farmer, Tradeskills, Equipment and Butler (a fix to it
-- belongs in all four). Each addon still works out its own lines; it hands
-- the board a function with `TooltipBlock:Provide(part, section, order, fn)`
-- and stops writing item lines itself. `fn(tooltip, data)` returns a list
-- of lines and whether it held one back for Shift. A line is
--   { left, right, leftColor = {r,g,b}, rightColor = {r,g,b}, wrap = true,
--     shift = true }
-- with `right` left out for a line on its own (wrapped when `wrap`), and
-- `shift` set on a line that shows only while Shift is held.
--
-- One shared table, `_G.BlackthornesTooltipBlock`, ties the copies together.
-- The first copy to load hooks item tooltips, once; the hook calls the
-- writer behind the table (`shared.handlers`, `FILE_VERSION`), so the newest
-- copy's writer wins whatever order the addons load in.
--
-- Reads only. Never touches a Blizzard frame beyond adding lines, one
-- texture of its own over the blank row that starts the block (hidden when
-- the tooltip clears), and HookScript on OnTooltipCleared. Every value read
-- from the client is read inside a pcall: inside a dungeon the game hands
-- out secret values that raise when touched.

local addonName, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local TooltipBlock = {}
ns.TooltipBlock = TooltipBlock

-- Raise this when the writer below changes, in every copy.
TooltipBlock.FILE_VERSION = 2

TooltipBlock.SECTIONS = { price = 1, source = 2, advice = 3, holders = 4 }

-- The game's own tooltip colors: yellow names, white answers.
TooltipBlock.NAME_COLOR = { 1, 0.82, 0 }
TooltipBlock.ANSWER_COLOR = { 1, 1, 1 }
TooltipBlock.HINT_COLOR = { 0.55, 0.57, 0.62 }
-- The house gold, for the line that starts the block.
TooltipBlock.RULE_COLOR = { 0.91, 0.76, 0.35, 0.85 }

local shared = _G.BlackthornesTooltipBlock
if type(shared) ~= "table" then
    shared = {}
    _G.BlackthornesTooltipBlock = shared
end
shared.providers = shared.providers or {}
shared.handlers = shared.handlers or { version = 0 }
shared.decorated = shared.decorated or setmetatable({}, { __mode = "k" })
shared.rules = shared.rules or setmetatable({}, { __mode = "k" })
shared.shiftRules = shared.shiftRules or setmetatable({}, { __mode = "k" })
shared.hooked = shared.hooked or setmetatable({}, { __mode = "k" })
TooltipBlock.shared = shared

--------------------------------------------------------------------------------
-- Signing up
--------------------------------------------------------------------------------

--- Hand the board this addon's lines for one section. `part` names them
--- ("Tradeskills:price"); signing up again under the same part replaces the
--- old function. `order` sorts parts within a section, lowest first.
function TooltipBlock:Provide(part, section, order, fn)
    if type(part) ~= "string" or type(fn) ~= "function" then return false end
    local rank = self.SECTIONS[section]
    if not rank then return false end
    shared.providers[part] = { part = part, rank = rank, order = tonumber(order) or 0, fn = fn }
    shared.sorted = nil
    return true
end

--- True when some copy of the board has signed this part up.
function TooltipBlock:Provides(part)
    return shared.providers[part] ~= nil
end

local function Sorted()
    if shared.sorted then return shared.sorted end
    local list = {}
    for _, provider in pairs(shared.providers) do list[#list + 1] = provider end
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        if a.order ~= b.order then return a.order < b.order end
        return a.part < b.part
    end)
    shared.sorted = list
    return list
end
TooltipBlock.Sorted = Sorted

--------------------------------------------------------------------------------
-- Gathering the lines
--------------------------------------------------------------------------------

--- Every signed-up part's lines for this tooltip, in the block's order, and
--- whether any part held a line back. A part that raises adds nothing.
function TooltipBlock.Gather(tooltip, data)
    local all, held = {}, false
    for _, provider in ipairs(Sorted()) do
        local ok, lines, wasHeld = pcall(provider.fn, tooltip, data)
        if ok then
            if wasHeld then held = true end
            if type(lines) == "table" then
                for _, line in ipairs(lines) do
                    if type(line) == "table" and type(line[1]) == "string" then all[#all + 1] = line end
                end
            end
        end
    end
    return all, held
end

--------------------------------------------------------------------------------
-- Writing them
--------------------------------------------------------------------------------

local function Count(tooltip)
    local ok, count = pcall(tooltip.NumLines, tooltip)
    if ok and type(count) == "number" then return count end
    return nil
end

--- The item a tooltip shows, as the key that tells one showing from the
--- next: the data's ID, else the item link. Nil when it can't be read.
function TooltipBlock.ItemKey(tooltip, data)
    local ok, key = pcall(function()
        if type(data) == "table" then
            local id = data.id
            if type(id) == "number" then return "id:" .. id end
            local link = data.hyperlink
            if type(link) == "string" then return link end
        end
        if type(tooltip.GetItem) == "function" then
            local _, link = tooltip:GetItem()
            if type(link) == "string" then return link end
        end
        return nil
    end)
    if ok and type(key) == "string" then return key end
    return nil
end

local function Forget(tooltip)
    shared.decorated[tooltip] = nil
    -- The hint the block put on goes with it.
    local shift = _G.BlackthornesTooltipShift
    if type(shift) == "table" and type(shift.hinted) == "table" then shift.hinted[tooltip] = nil end
    local rule = shared.rules[tooltip]
    if rule then pcall(rule.Hide, rule) end
    local shiftRule = shared.shiftRules[tooltip]
    if shiftRule then pcall(shiftRule.Hide, shiftRule) end
end
TooltipBlock.Forget = Forget

local function HookClear(tooltip)
    if shared.hooked[tooltip] then return true end
    if type(tooltip.HookScript) ~= "function" then return false end
    -- The newest copy's Forget, so a later file's own textures go too.
    local ok = pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", function(shown)
        local forget = shared.handlers.Forget
        if type(forget) ~= "function" then forget = Forget end
        forget(shown)
    end)
    if ok then shared.hooked[tooltip] = true end
    return ok
end

--- The left text of line `index`, for the gold line to sit on. Nil when
--- the tooltip has no name or the line can't be found.
local function LeftText(tooltip, index)
    local ok, text = pcall(function()
        local name = tooltip:GetName()
        if type(name) ~= "string" then return nil end
        return _G[name .. "TextLeft" .. index]
    end)
    if ok and type(text) == "table" then return text end
    return nil
end

--- The thin gold line over the blank row that starts the block (or, with
--- `store` set to `shared.shiftRules`, the one over the Shift lines): a
--- texture of our own, made once per tooltip and shown only while needed.
local function PlaceRule(tooltip, index, store)
    store = store or shared.rules
    local anchor = LeftText(tooltip, index)
    if not anchor then return false end
    local rule = store[tooltip]
    if not rule then
        local ok, made = pcall(tooltip.CreateTexture, tooltip, nil, "ARTWORK")
        if not ok or type(made) ~= "table" then return false end
        rule = made
        store[tooltip] = rule
    end
    local c = TooltipBlock.RULE_COLOR
    return (pcall(function()
        rule:ClearAllPoints()
        rule:SetColorTexture(c[1], c[2], c[3], c[4])
        rule:SetHeight(1)
        rule:SetPoint("LEFT", anchor, "LEFT", 0, 0)
        rule:SetPoint("RIGHT", tooltip, "RIGHT", -10, 0)
        rule:Show()
    end))
end
TooltipBlock.PlaceRule = PlaceRule

local function Unpack3(color, fallback)
    color = type(color) == "table" and color or fallback
    return color[1], color[2], color[3]
end

--- Put one line on the tooltip.
function TooltipBlock.WriteLine(tooltip, line)
    local lr, lg, lb = Unpack3(line.leftColor, TooltipBlock.NAME_COLOR)
    if type(line[2]) == "string" and line[2] ~= "" then
        local rr, rg, rb = Unpack3(line.rightColor, TooltipBlock.ANSWER_COLOR)
        pcall(tooltip.AddDoubleLine, tooltip, line[1], line[2], lr, lg, lb, rr, rg, rb)
    else
        pcall(tooltip.AddLine, tooltip, line[1], lr, lg, lb, line.wrap and true or false)
    end
end

--- "Hold Shift for more.", once a tooltip, shared with the Shift board so an
--- older copy of an addon that still writes its own lines doesn't add it twice.
local function Hint(tooltip)
    local shift = _G.BlackthornesTooltipShift
    local hinted = type(shift) == "table" and type(shift.hinted) == "table" and shift.hinted or nil
    if hinted and hinted[tooltip] then return end
    if hinted then hinted[tooltip] = true end
    local c = TooltipBlock.HINT_COLOR
    pcall(tooltip.AddLine, tooltip, L["Hold Shift for more."], c[1], c[2], c[3])
end

--- Write the whole block on an item tooltip, once a showing.
-- @return "added", "held", "quiet", "duplicate" or "noitem"
local function Write(tooltip, data)
    if type(tooltip) ~= "table" then return "noitem" end
    if shared.writing then return "duplicate" end
    if type(tooltip.AddLine) ~= "function" or type(tooltip.AddDoubleLine) ~= "function" then return "noitem" end

    local key = TooltipBlock.ItemKey(tooltip, data)
    if not key then return "noitem" end

    -- The game can call the hook twice for one showing; the second time the
    -- block is already on, as long as the tooltip still holds every line.
    local mark = shared.decorated[tooltip]
    if mark and mark.key == key then
        local now = Count(tooltip)
        if not now or now >= mark.lines then return "duplicate" end
    end

    local lines, held = TooltipBlock.Gather(tooltip, data)
    if #lines == 0 and not held then return "quiet" end

    -- Shift lines after the rest, each group in the block's order.
    local always, extra = {}, {}
    for _, line in ipairs(lines) do
        if line.shift then extra[#extra + 1] = line else always[#always + 1] = line end
    end

    HookClear(tooltip)
    shared.writing = true
    local shiftRule = shared.shiftRules[tooltip]
    if shiftRule then pcall(shiftRule.Hide, shiftRule) end
    if #lines > 0 then
        pcall(tooltip.AddLine, tooltip, " ")
        local ruleAt = Count(tooltip)
        if ruleAt then PlaceRule(tooltip, ruleAt) end
        for _, line in ipairs(always) do TooltipBlock.WriteLine(tooltip, line) end
        if #extra > 0 and #always > 0 then
            pcall(tooltip.AddLine, tooltip, " ")
            local shiftAt = Count(tooltip)
            if shiftAt then PlaceRule(tooltip, shiftAt, shared.shiftRules) end
        end
        for _, line in ipairs(extra) do TooltipBlock.WriteLine(tooltip, line) end
    end
    if held then Hint(tooltip) end
    -- A tooltip that has grown is told to size itself again.
    pcall(function() if tooltip:IsShown() then tooltip:Show() end end)
    shared.writing = false

    shared.decorated[tooltip] = { key = key, lines = Count(tooltip) or 0 }
    return #lines > 0 and "added" or "held"
end
TooltipBlock.Write = Write

--------------------------------------------------------------------------------
-- The one hook
--------------------------------------------------------------------------------

-- The newest copy's writer, whatever order the addons loaded in.
if (shared.handlers.version or 0) < TooltipBlock.FILE_VERSION then
    shared.handlers.version = TooltipBlock.FILE_VERSION
    shared.handlers.Write = Write
    shared.handlers.Forget = Forget
end

local function OnItem(tooltip, data)
    local write = shared.handlers.Write
    if type(write) ~= "function" then return end
    local ok = pcall(write, tooltip, data)
    if not ok then shared.writing = false end
end
TooltipBlock.OnItem = OnItem

-- Tooltips that show items, for a client without the data post-call.
TooltipBlock.TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }

--- Hook item tooltips, once for every copy. True when a hook took.
function TooltipBlock:Install()
    if shared.installed then return true end
    -- The named tooltips forget their block when they clear from the start.
    for _, name in ipairs(self.TOOLTIPS) do
        local tooltip = rawget(_G, name)
        if type(tooltip) == "table" then HookClear(tooltip) end
    end
    local processor = rawget(_G, "TooltipDataProcessor")
    local enum = rawget(_G, "Enum")
    local itemType = type(enum) == "table" and type(enum.TooltipDataType) == "table" and enum.TooltipDataType.Item or nil
    if type(processor) == "table" and type(processor.AddTooltipPostCall) == "function" and itemType ~= nil then
        if pcall(processor.AddTooltipPostCall, itemType, function(tooltip, data) OnItem(tooltip, data) end) then
            shared.installed = "post-call"
            return true
        end
    end
    local any = false
    for _, name in ipairs(self.TOOLTIPS) do
        local tooltip = rawget(_G, name)
        if type(tooltip) == "table" and type(tooltip.HookScript) == "function" then
            if pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(shown) OnItem(shown, nil) end) then
                any = true
            end
        end
    end
    if any then shared.installed = "scripts" end
    return any
end
