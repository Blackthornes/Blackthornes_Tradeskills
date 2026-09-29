-- Blackthornes Tradeskills -- UI/ItemTooltip.lua
-- What an item is worth on the auction house, on the item's own tooltip.
--
-- The Profit tab answers "what should I make", and UI/RecipeValue.lua answers
-- "what does this recipe sell for" in the profession window. This answers the
-- same question about a thing you are already pointing at: a stack in your
-- bags, a reagent on a vendor's list, a link somebody pasted in chat.
--
-- Two things shape every decision below.
--
-- **The hook is not assumed.** Retail grew a data-driven tooltip system
-- (`TooltipDataProcessor`) in 10.0 and the older `OnTooltipSetItem` script is
-- gone there; Classic still has the script and nothing else. This client has
-- retail's auction and profession APIs on a 1.60 interface number, so it is
-- not safely either one. Every shape known to work is installed, whichever of
-- them the client actually fires does the work, and `/bts tip` reports which
-- one fired and how many tooltips have actually carried a value -- not which
-- hook was installed, because a hook that never fires installs perfectly.
--
-- **Answered in game 2026-09-22: it is `TooltipDataProcessor`**, 113 tooltips
-- in one session, with the other two installed alongside and never firing.
-- They stay installed anyway -- that is one measurement on one build, and the
-- guard below already makes carrying them free.
--
-- **A price is not the same claim as no price.** An item nothing has been seen
-- selling for prints "not scanned yet", never a zero and never silence: on a
-- crowded recipe row silence is the only option, but a tooltip has room to say
-- which of the two it means. That line is held back for items that cannot be
-- auctioned at all -- soulbound gear, quest items -- so hovering your own
-- equipment does not produce a running commentary about the auction house.
--
-- Blizzard's tooltips are hooked and appended to. None is assigned to and no
-- field of ours is written onto one: what has already been decorated lives in
-- a weak table keyed by the tooltip.

local _, ns = ...

local ItemTooltip = ns.NewModule("ItemTooltip")

local Util = ns.Util

-- Tooltips worth decorating by name, for the clients where hooking is done
-- per frame. GameTooltip covers bags, bank, merchants, the auction house and
-- the character sheet; ItemRefTooltip is the one a chat link opens.
local TOOLTIP_NAMES = { "GameTooltip", "ItemRefTooltip" }

-- Blizzard's item class for quest items, which have no auction value by
-- definition. Read from Enum when the client offers it; this is the fallback.
local CLASS_QUEST = 12

-- `bindType` 1 is bind-on-pickup. Anything carrying it in a bag is already
-- bound and cannot be listed.
local BIND_ON_PICKUP = 1

-- A price older than the "stale" setting still gets shown -- it is the best
-- anyone has -- but it says how old it is, because acting on a week-old price
-- is a different decision from acting on this morning's.
local STALE_COLOR = "muted"

--------------------------------------------------------------------------------
-- Talking to frames that may not answer
--------------------------------------------------------------------------------

-- Same pair as UI/RecipeValue.lua, and for the same reason: a missing method
-- on this client raises rather than returning nil, and a bare
-- `select(2, pcall(...))` hands back the *error message*, which is truthy.

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
-- The setting
--------------------------------------------------------------------------------

--- Is the decoration switched on?
--
-- `~= false` rather than `== true`: a setting never written is nil, and this
-- one is on by default.
function ItemTooltip:IsEnabled()
    if not ns.Config then return true end
    return ns.Config:Get("showValueOnItemTooltips") ~= false
end

--------------------------------------------------------------------------------
-- Which item a tooltip is showing
--------------------------------------------------------------------------------

--- A positive item ID as a plain number, or nil.
-- type() says "number" even for a value the game will not let the addon read,
-- and the first comparison or table lookup with one raises. So the test and
-- a copy happen inside a pcall.
local function PlainID(value)
    if type(value) ~= "number" then return nil end
    local ok, id = pcall(function() if value > 0 then return value + 0 end end)
    if ok then return id end
    return nil
end
ItemTooltip.PlainID = PlainID

--- The item ID inside an item link, or nil.
--
-- A link is `|cff...|Hitem:2589:0:0:...|h[Linen Cloth]|h|r`. Matching on the
-- `item:` prefix rather than the first run of digits keeps the colour code out
-- of it, and refuses a spell or enchant link outright rather than reading its
-- ID as an item's.
function ItemTooltip.ItemIDFromLink(link)
    if type(link) ~= "string" then return nil end

    -- Matched inside a pcall: a link the game will not let the addon read (a
    -- tooltip in a dungeon) raises when matched, and is simply no item.
    local ok, id = pcall(function()
        return link:match("|Hitem:(%d+)") or link:match("^item:(%d+)")
    end)
    if not ok or not id then return nil end

    return tonumber(id)
end

--- The item a tooltip is currently describing.
--
-- Three ways, because which of them exists is exactly what is unknown about
-- this client:
--   * the data table a modern post-call is handed, which carries the ID
--   * `TooltipUtil.GetDisplayedItem`, retail's replacement for GetItem
--   * `tooltip:GetItem()`, which Classic still has
--
-- Both of the last two answer `name, link` and the first of those is no use
-- here, so they are called through pcall rather than Try -- Try forwards one
-- return value, and taking the first of a pair would read the item's *name*
-- as its link and find no item at all. That is what this looks like in game:
-- an addon that loads, hooks everything, and decorates nothing.
function ItemTooltip:ItemForTooltip(tooltip, data)
    local fromData = PlainID(Field(data, "id"))
    if fromData then return fromData end

    local displayed = Field(_G.TooltipUtil, "GetDisplayedItem")

    if type(displayed) == "function" then
        local ok, _, link, id = pcall(displayed, tooltip)

        if ok then
            local plainID = PlainID(id)
            if plainID then return plainID end

            local fromLink = self.ItemIDFromLink(link)
            if fromLink then return fromLink end
        end
    end

    local getItem = Field(tooltip, "GetItem")

    if type(getItem) == "function" then
        local ok, _, link = pcall(getItem, tooltip)

        if ok then
            local fromGetItem = self.ItemIDFromLink(link)
            if fromGetItem then return fromGetItem end
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- How many of it
--------------------------------------------------------------------------------

--- How many sit in this bag slot, or nil for one (or none we can read).
--
-- The tooltip itself does not carry the count -- only the call that was handed
-- a bag and a slot knows it -- which is why `SetBagItem` is hooked even on a
-- client where something else is doing the decorating.
function ItemTooltip.StackCountIn(bag, slot)
    local container = _G.C_Container

    local get = Field(container, "GetContainerItemInfo")
    if type(get) ~= "function" then return nil end

    -- Called through pcall directly rather than Try, which forwards only the
    -- first return value and would throw the legacy signature's count away.
    local ok, first, second = pcall(get, bag, slot)
    if not ok then return nil end

    -- Modern: one table, with the count on it. Older: a list, count second.
    local count = Field(first, "stackCount")
    if type(count) ~= "number" then count = second end

    if type(count) ~= "number" or count <= 1 then return nil end

    return count
end

--------------------------------------------------------------------------------
-- What to say
--------------------------------------------------------------------------------

--- Could this item be sold at auction at all?
--
-- Only used to decide whether *silence* or *"not scanned yet"* is the honest
-- answer for an item with no price. Getting it wrong costs a line of noise on
-- a tooltip, never a wrong number.
--
-- An item the client has not cached yet answers nil, and nil is treated as
-- "do not say anything": the next hover has the data and can speak then.
function ItemTooltip.IsAuctionable(itemID)
    if not itemID then return nil end
    if not Util.HasFunction("C_Item.GetItemInfo") then return nil end

    local ok, name, _, _, _, _, _, _, _, _, _, _, classID, _, bindType =
        pcall(C_Item.GetItemInfo, itemID)

    if not ok or not name then return nil end

    local questClass = CLASS_QUEST
    local enum = _G.Enum
    local itemClass = Field(enum, "ItemClass")
    local fromEnum = Field(itemClass, "Questitem") or Field(itemClass, "QuestItem")
    if type(fromEnum) == "number" then questClass = fromEnum end

    if classID == questClass then return false end
    if bindType == BIND_ON_PICKUP then return false end

    return true
end

--- The lines to append for one item, in order.
--
-- Each is `{ label, value, muted }`. Returning an empty list means "say
-- nothing at all", which is a different outcome from a list holding the
-- not-scanned line, and the diagnostic counts them separately.
--
-- The value is the smoothed market value of one unit -- the same number
-- UI/RecipeValue.lua puts beside a recipe -- rather than the cheapest current
-- listing. "What is this worth" is the question a tooltip is asked; what it
-- would cost to buy one right now is a question asked at the auction house,
-- where the Prices tab answers it with the whole book.
function ItemTooltip:LinesFor(itemID, count)
    local lines = {}

    if not itemID or not ns.Prices then return lines end

    -- Grey (poor) items are worth what a vendor pays, never an auction
    -- price (a standing rule for both addons), and the game's own tooltip
    -- already gives the vendor price. So nothing is added for them.
    -- Read and compared inside the pcall: in a dungeon the game can hand
    -- back values that raise when compared.
    local poorOk, poor = pcall(function()
        local _, _, quality = C_Item.GetItemInfo(itemID)
        return quality == 0
    end)
    if poorOk and poor then return lines end

    local value = ns.Prices:GetValue(itemID, "market")

    -- A stored zero is a scan that saw no listings, not an item the market
    -- values at nothing.
    if not value or value <= 0 then
        if self.IsAuctionable(itemID) then
            -- Searched and found empty is not the same as never looked at.
            local record = ns.Prices.Get and ns.Prices:Get(itemID)
            lines[#lines + 1] = { "Auction value",
                (record and record.quantity == 0) and "none listed" or "not scanned yet", true }
        end

        local disenchant = self:DisenchantLine(itemID)
        if disenchant then lines[#lines + 1] = disenchant end

        return lines
    end

    local text = Util.FormatMoney(value, { short = true })

    -- An old price is still the best anyone has, so it is shown -- with its
    -- age, which is the part that decides whether to trust it.
    if ns.Prices.IsStale and ns.Prices:IsStale(itemID) then
        local age = ns.Prices:GetAge(itemID)
        if age then
            text = ("%s  (%s)"):format(text, Util.FormatAgeAgo(age))
        end
    end

    lines[#lines + 1] = { "Auction value", text }

    local lowest = self:LowestLine(itemID)
    if lowest then lines[#lines + 1] = lowest end

    if count and count > 1 then
        lines[#lines + 1] = {
            ("Stack of %d"):format(count),
            Util.FormatMoney(value * count, { short = true }),
            stack = true,
        }
    end

    local disenchant = self:DisenchantLine(itemID)
    if disenchant then lines[#lines + 1] = disenchant end

    return lines
end

--- What one of the item is worth disenchanted, for anything that can be.
--- Nothing at all for an item that cannot, or when none of what it breaks
--- into has been scanned yet.
function ItemTooltip:DisenchantLine(itemID)
    if not ns.Disenchant then return nil end

    local value, partial = ns.Disenchant:GetValue(itemID)
    if not value then return nil end

    local text = Util.FormatMoney(value, { short = true })
    if partial then text = text .. " or more" end

    return { "Disenchant value", text }
end

--- The cheapest listing the last scan saw, beside the smoothed value (Trent,
--- 2026-09-26: "items should show the lowest seller value in addition to
--- auction value"). The same number the List confirmation calls the lowest
--- posting, marked when the cheapest one is your own.
function ItemTooltip:LowestLine(itemID)
    if type(ns.Prices.Get) ~= "function" then return nil end

    local record = ns.Prices:Get(itemID)
    if type(record) ~= "table" then return nil end

    local lowest = record.min
    if not lowest or lowest <= 0 then
        -- Scanned, and nobody had one up: say so rather than leave it out.
        return { "Lowest posting", "none listed", true }
    end

    local text = Util.FormatMoney(lowest, { short = true })

    if record.ownMin and record.ownMin <= lowest then
        text = text .. "  (yours)"
    end

    return { "Lowest posting", text }
end

--------------------------------------------------------------------------------
-- Writing it on
--------------------------------------------------------------------------------

-- What has already been decorated. Weak keys, so a tooltip the client throws
-- away takes its entry with it, and no field of ours is written onto a
-- Blizzard frame.
--
-- More than one hook is installed on purpose -- see the header -- so more than
-- one of them may fire for the same tooltip. This is what stops that showing
-- up as the line appearing twice: a tooltip is marked with the item and the
-- line count it had once we were finished, and a later call for the same item
-- that finds the tooltip no shorter than that has nothing left to do. Clearing
-- the tooltip drops the mark, so the next draw is decorated again.
local decorated = setmetatable({}, { __mode = "k" })

function ItemTooltip.Forget(tooltip)
    decorated[tooltip] = nil
end

function ItemTooltip:AlreadyOn(tooltip, itemID)
    local mark = decorated[tooltip]

    if not mark or mark.itemID ~= itemID then return false end

    local now = Try(Field(tooltip, "NumLines"), tooltip)

    -- Cannot tell: assume it is already there. A missing line is a smaller
    -- fault than the same line printed twice.
    if type(now) ~= "number" then return true end

    return now >= mark.lines
end

-- AddDoubleLine takes colour components, not escape codes, so the hex the rest
-- of the addon works in is split out here. Bytes 1-2 are alpha.
local function Component(hex, first)
    return (tonumber(hex:sub(first, first + 1), 16) or 255) / 255
end

--- Put one `{ label, value, muted }` line on a tooltip.
local function WriteLine(tooltip, line)
    local add = Field(tooltip, "AddDoubleLine")
    if type(add) ~= "function" then return end

    local labelColor = ns.COLORS.accent
    local valueColor = line[3] and ns.COLORS[STALE_COLOR] or ns.COLORS.text

    Try(add, tooltip, line[1], line[2],
        Component(labelColor, 3), Component(labelColor, 5), Component(labelColor, 7),
        Component(valueColor, 3), Component(valueColor, 5), Component(valueColor, 7))
end

--- Append one item's lines to a tooltip.
-- @return "valued", "unscanned", "quiet", "duplicate" or "noitem"
function ItemTooltip:Decorate(tooltip, data, count)
    if type(tooltip) ~= "table" then return "noitem" end
    if not self:IsEnabled() then return "quiet" end

    -- Adding lines makes the tooltip taller, which means showing it again; on
    -- a client where that re-enters the hook, this is what stops it.
    if self.writing then return "duplicate" end

    local itemID = self:ItemForTooltip(tooltip, data)
    if not itemID then return "noitem" end

    if self:AlreadyOn(tooltip, itemID) then return "duplicate" end

    local lines = self:LinesFor(itemID, count)
    if #lines == 0 then return "quiet" end

    if type(Field(tooltip, "AddDoubleLine")) ~= "function" then return "noitem" end

    self.writing = true

    for i = 1, #lines do
        WriteLine(tooltip, lines[i])
    end

    -- A tooltip that has grown has to be told to resize. Harmless where the
    -- client does it already, required where a hooked setter is what got us
    -- here.
    Try(Field(tooltip, "Show"), tooltip)

    self.writing = false

    decorated[tooltip] = {
        itemID = itemID,
        count = count,
        lines = Try(Field(tooltip, "NumLines"), tooltip) or 0,
    }

    self.seen = (self.seen or 0) + 1

    local outcome = lines[1][3] and "unscanned" or "valued"
    self.counts[outcome] = (self.counts[outcome] or 0) + 1

    return outcome
end

--- Add the stack total to a tooltip that was already given its unit value.
--
-- The count arrives late and there is nothing to be done about it. Every hook
-- available here fires *after* the call that built the tooltip, and only that
-- call was told which bag slot it was drawing -- so by the time the count is
-- readable, whichever hook fired first has already written the unit value.
-- Rather than fight the ordering, the stack line is a second, separate append.
--
-- Assigning a field on `GameTooltip` to pre-empt the count would taint it, so
-- that is not an option this addon has.
--
-- @return true if a line was added
function ItemTooltip:AddStackLine(tooltip, count)
    if not count or count <= 1 then return false end
    if not self:IsEnabled() then return false end
    if self.writing then return false end

    local mark = decorated[tooltip]

    -- Nothing decorated yet, or the stack total is already on: either way
    -- there is nothing for this to do.
    if not mark or mark.count then return false end

    -- The tooltip may have moved on to another item since it was marked.
    if self:ItemForTooltip(tooltip) ~= mark.itemID then return false end

    local lines = self:LinesFor(mark.itemID, count)

    -- No stack line means the item has no price, and "a stack of 20 of
    -- nothing" is not worth saying.
    local stackLine
    for _, line in ipairs(lines) do
        if line.stack then stackLine = line end
    end
    if not stackLine then return false end

    self.writing = true

    WriteLine(tooltip, stackLine)
    Try(Field(tooltip, "Show"), tooltip)

    self.writing = false

    mark.count = count
    mark.lines = Try(Field(tooltip, "NumLines"), tooltip) or mark.lines

    return true
end

--- The entry point every hook funnels into, so the counting is in one place.
function ItemTooltip:OnTooltip(tooltip, data, source, count)
    -- A backstop: whatever this tooltip holds, a value the game will not let
    -- the addon read costs the price line, never a Lua error on hover. And
    -- `writing` is cleared, or one error would silently stop every tooltip
    -- for the rest of the session.
    local ok, outcome = pcall(self.Decorate, self, tooltip, data, count)
    if not ok then
        self.writing = false
        return "noitem"
    end

    if outcome == "valued" or outcome == "unscanned" then
        self.fired[source] = (self.fired[source] or 0) + 1
    end

    return outcome
end

--------------------------------------------------------------------------------
-- Getting told about a tooltip
--------------------------------------------------------------------------------

-- Retail 10.0 replaced the `OnTooltipSetItem` script with a data-driven
-- post-call; Classic has the script and nothing else. Which of the two this
-- client has cannot be established from outside the game, so both are
-- installed and whichever fires does the work -- the duplicate guard above is
-- what makes installing both safe.

--- Retail 10.0 and later: the tooltip announces its own data.
function ItemTooltip:InstallDataProcessor()
    local processor = _G.TooltipDataProcessor
    local dataType = Field(Field(_G.Enum, "TooltipDataType"), "Item")

    if type(processor) ~= "table" or dataType == nil then return false end

    local add = Field(processor, "AddTooltipPostCall")
    if type(add) ~= "function" then return false end

    return (pcall(add, dataType, function(tooltip, data)
        ItemTooltip:OnTooltip(tooltip, data, "TooltipDataProcessor")
    end))
end

--- Classic, and retail before 10.0: a script on each tooltip frame.
function ItemTooltip:InstallScriptHooks()
    local installed = 0

    for i = 1, #TOOLTIP_NAMES do
        local tooltip = _G[TOOLTIP_NAMES[i]]
        local hook = Field(tooltip, "HookScript")

        if type(hook) == "function" then
            local ok = pcall(hook, tooltip, "OnTooltipSetItem", function(shown)
                ItemTooltip:OnTooltip(shown, nil, "OnTooltipSetItem")
            end)

            if ok then installed = installed + 1 end

            -- Forgetting on clear is what lets the same item be decorated
            -- again on its next draw.
            pcall(hook, tooltip, "OnTooltipCleared", function(shown)
                ItemTooltip.Forget(shown)
            end)
        end
    end

    return installed > 0
end

-- The calls that put an item into GameTooltip. `SetBagItem` is hooked whatever
-- else took, because it is the only place a stack count can be read. The rest
-- are a fallback for a client that fires neither hook above, and are skipped
-- when one of them did -- eleven post-hooks on every tooltip is not a cost to
-- pay for nothing.
local STACK_SETTER = "SetBagItem"

local FALLBACK_SETTERS = {
    "SetInventoryItem", "SetHyperlink", "SetLootItem", "SetMerchantItem",
    "SetBuybackItem", "SetQuestItem", "SetTradePlayerItem",
    "SetTradeTargetItem", "SetAuctionItem", "SetGuildBankItem",
}

--- Hook one GameTooltip setter, post-call.
local function HookSetter(hook, tooltip, name, handler)
    if type(Field(tooltip, name)) ~= "function" then return false end

    return (pcall(hook, tooltip, name, handler))
end

--- Hook the calls that put an item into a tooltip.
-- @param fallback  also hook the setters that are only needed when no other
--                  hook fired
function ItemTooltip:InstallSetterHooks(fallback)
    local hook = _G.hooksecurefunc
    local tooltip = _G.GameTooltip

    if type(hook) ~= "function" or type(tooltip) ~= "table" then return false end

    local installed = 0

    if HookSetter(hook, tooltip, STACK_SETTER, function(shown, bag, slot)
        local count = ItemTooltip.StackCountIn(bag, slot)

        -- Decorate first: on a client with no other hook this is what puts the
        -- value on at all, and it can take the count with it.
        ItemTooltip:OnTooltip(shown, nil, "setter hooks", count)

        -- On a client that does have one, the value went on before the count
        -- was readable, so the stack total follows separately.
        ItemTooltip:AddStackLine(shown, count)
    end) then
        installed = installed + 1
    end

    if fallback then
        for i = 1, #FALLBACK_SETTERS do
            if HookSetter(hook, tooltip, FALLBACK_SETTERS[i], function(shown)
                ItemTooltip:OnTooltip(shown, nil, "setter hooks")
            end) then
                installed = installed + 1
            end
        end
    end

    return installed > 0
end

function ItemTooltip:InstallHooks()
    local installed = {}

    installed["TooltipDataProcessor"] = self:InstallDataProcessor()
    installed["OnTooltipSetItem"] = self:InstallScriptHooks()

    local fallback = not installed["TooltipDataProcessor"]
        and not installed["OnTooltipSetItem"]

    installed["setter hooks"] = self:InstallSetterHooks(fallback)

    self.installed = installed

    return installed
end

--------------------------------------------------------------------------------
-- Diagnostic
--------------------------------------------------------------------------------

-- `/bts tip` reports what has actually happened, not what was set up. A hook
-- that never fires installs perfectly, and "hooked the tooltip" would be true
-- of a client that never calls it -- which is the failure this exists to
-- catch. Every number below was counted on a real tooltip.
--
-- `/bts tip <link or id>` answers the other question: not whether the hook
-- works, but what the addon would say about that item. The two failures look
-- identical in game -- nothing on the tooltip -- and this tells them apart.

local function DescribeItem(itemID)
    ns.Print(("|c%s%s|r"):format(ns.COLORS.accent, Util.GetItemLabel(itemID)))

    local lines = ItemTooltip:LinesFor(itemID, nil)

    if #lines == 0 then
        ns.PrintRaw(("  |c%snothing would be shown: no price, and it is not"
            .. " something you could auction|r"):format(ns.COLORS.muted))
        return
    end

    for i = 1, #lines do
        ns.PrintRaw(("  |c%s%s|r  %s"):format(
            ns.COLORS.muted, lines[i][1], lines[i][2]))
    end
end

function ItemTooltip:PrintReport(input)
    local itemID = tonumber(input) or self.ItemIDFromLink(input)

    if itemID then
        DescribeItem(itemID)
        return
    end

    ns.Print(("|c%sAuction value on item tooltips|r"):format(ns.COLORS.accent))

    if not self:IsEnabled() then
        ns.PrintRaw(("  |c%sswitched off in Settings|r"):format(ns.COLORS.muted))
        return
    end

    local firing = {}
    for source, count in pairs(self.fired) do
        firing[#firing + 1] = ("%s (%d)"):format(source, count)
    end

    table.sort(firing)

    ns.PrintRaw(("  |c%stooltip types seen|r  %s"):format(
        ns.COLORS.muted, #firing > 0 and table.concat(firing, ", ") or "none yet"))

    ns.PrintRaw(("  |c%sitem tooltips checked|r  %d"):format(
        ns.COLORS.muted, self.seen or 0))

    ns.PrintRaw(("  |c%sshowing a value|r  %d"):format(
        ns.COLORS.muted, self.counts.valued or 0))

    ns.PrintRaw(("  |c%ssaying not scanned yet|r  %d"):format(
        ns.COLORS.muted, self.counts.unscanned or 0))

    if (self.seen or 0) == 0 then
        local installed = {}
        for source, ok in pairs(self.installed or {}) do
            if ok then installed[#installed + 1] = source end
        end

        table.sort(installed)

        ns.PrintRaw(("  |c%stooltip types watched|r  %s"):format(
            ns.COLORS.muted, #installed > 0 and table.concat(installed, ", ") or "none"))

        ns.PrintRaw(("  |c%sHover an item, then run this again.|r"):format(
            ns.COLORS.muted))
    end

    ns.PrintRaw(("  |c%s/bts tip <item link> says what one item would show.|r"):format(
        ns.COLORS.muted))
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function ItemTooltip:OnEnable()
    self.fired = {}
    self.counts = {}
    self.seen = 0

    self:InstallHooks()

    ns.RegisterCommand("tip",
        "show what the auction value on item tooltips is doing", function(input)
            ItemTooltip:PrintReport((input or ""):gsub("^%s+", ""):gsub("%s+$", ""))
        end)
end
