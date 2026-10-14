-- Blackthornes Tradeskills -- UI/BuyQuantity.lua
-- Fills the auction house's quantity box with what the queue still needs.
--
-- Asked on 2026-10-06: searching for a material from the Buy list, the
-- Queue tab or the Gather tab put the item in front of you, but Blizzard's
-- buy window still opened at a quantity of 1. Now a search from one of those
-- lists remembers the item, and when you pick that item in Blizzard's
-- results its quantity box is set to what the queue is still short of: the
-- same red number the shopping list shows, after bags and bank.
--
-- Nothing is bought. The number goes in the box and the Buy Now click stays
-- the player's. The box is only filled for the item the list searched for,
-- and only while it still shows the 1 Blizzard opens it at, so a number the
-- player typed is never written over.
--
-- Commodities only: materials are unit-priced pools on Forever (see
-- docs/FOREVER_API_FINDINGS.md), and an item auction has no quantity box.
-- The buy window's parts are read by name inside a pcall, as on retail;
-- `/bts probe` says whether this client has them.
--
-- Fixed 2026-10-10: the box jumped to the number, then back to 1. The buy
-- window has two halves that each keep a quantity: the box, and the list of
-- listings beside it, which Blizzard sets to 1 for each new item. Every time
-- the list redraws (its results arriving, more rows loading) it tells the
-- box its own number, so a number written into the box alone was put back
-- to 1. Now the number goes in the way typing in the box does: through the
-- auction house's "quantity changed" message, which both halves listen to,
-- so the list keeps it too and its redraws say the same number.

--
-- Fixed 2026-10-14: a search of a whole list at once (the Lists view's
-- Search, "From your craft queue" among them, and Butler's quest items)
-- went through ShoppingLists:SearchMany, which remembered nothing, so
-- picking an item in the results left the box at 1. Now it remembers every
-- item it searched for with its count (WantMany), and the box fills for
-- whichever one the player picks, the same number the Buy tab gives.
--
-- Added 2026-10-11: a warning line under the Buy Now button. Buying a
-- queue material can cost far more than the shopping list said, when the
-- cheap listings went since the last scan or the amount reaches up into
-- dearer ones. Whenever the buy window changes (its item, the number in the
-- box, the listings arriving), the live cost of that many is counted up the
-- listings shown and held against the shopping list's estimate from before
-- the search (AHBuys:Estimate). Past "Warn when buying costs more" percent
-- the line shows both and the difference, in coin colours. It is the
-- addon's own frame, placed by the button; the button still buys. The
-- search itself already refreshed the saved price (Scanner's passive
-- capture), so the next estimate starts from what was just seen.

local _, ns = ...

local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local BuyQuantity = ns.NewModule("BuyQuantity")

-- The item a list searched for: { itemID, quantity }, or nil.
BuyQuantity.want = nil
-- The items a whole-list search looked for: [itemID] = quantity, or nil.
BuyQuantity.wants = nil
-- What the last fill did, for the probe: "filled 12", "no quantity box", ...
BuyQuantity.lastResult = nil

-- Blizzard re-sets the box as its results arrive; look again this soon after.
local SETTLE = 0.4

-- Frames already hooked. Kept here rather than marked on Blizzard's frame:
-- the addon never writes to the game's own tables.
local hooked = setmetatable({}, { __mode = "k" })

local function Field(t, key)
    if type(t) ~= "table" then return nil end
    local ok, value = pcall(function() return t[key] end)
    if ok then return value end
end

local function Call(t, method, ...)
    local fn = Field(t, method)
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(fn, t, ...)
    return ok, result
end

--- Blizzard's commodity buy window, if this client has one loaded.
function BuyQuantity:BuyFrame()
    return Field(Field(_G, "AuctionHouseFrame"), "CommoditiesBuyFrame")
end

--- Its buy display, the part holding the quantity box.
function BuyQuantity:Display()
    local frame = self:BuyFrame()
    return Field(frame, "BuyDisplay") or frame
end

--- The item the buy window is showing.
function BuyQuantity:ShownItemID()
    local display = self:Display()
    local ok, itemID = Call(display, "GetItemID")
    if ok and type(itemID) == "number" then return itemID end

    itemID = Field(display, "itemID")
    if type(itemID) == "number" then return itemID end

    ok, itemID = Call(self:BuyFrame(), "GetItemID")
    if ok and type(itemID) == "number" then return itemID end
end

--- The number in the quantity box, or nil when it cannot be read.
function BuyQuantity:ShownQuantity()
    local display = self:Display()
    local ok, quantity = Call(display, "GetQuantitySelected")
    if ok and type(quantity) == "number" then return quantity end

    local input = Field(display, "QuantityInput")
    ok, quantity = Call(input, "GetQuantity")
    if ok and type(quantity) == "number" then return quantity end

    ok, quantity = Call(Field(input, "InputBox"), "GetNumber")
    if ok and type(quantity) == "number" then return quantity end
end

--- The auction house's "quantity changed" message, which the box sends when
--- the player types and both halves of the buy window listen to.
function BuyQuantity:QuantityEvent()
    local events = Field(Field(_G, "AuctionHouseFrameMixin"), "Event")
    return Field(events, "CommoditiesQuantitySelectionChanged")
end

--- Put a number in the quantity box, by the first way this client offers.
-- @return true when one of them took it
function BuyQuantity:SetShownQuantity(quantity)
    -- As the player's typing does, so the list beside the box keeps it too.
    local event = self:QuantityEvent()
    local house = Field(_G, "AuctionHouseFrame")
    if event ~= nil and Call(house, "TriggerEvent", event, quantity) then
        if self:ShownQuantity() == quantity then return true end
    end

    local display = self:Display()
    if Call(display, "SetQuantitySelected", quantity) then return true end

    local input = Field(display, "QuantityInput")
    if Call(input, "SetQuantity", quantity) then return true end

    return (Call(Field(input, "InputBox"), "SetNumber", quantity))
end

--- Does this client's buy window have a quantity box the addon can set?
function BuyQuantity:HasQuantityBox()
    local display = self:Display()
    if type(Field(display, "SetQuantitySelected")) == "function" then return true end
    local input = Field(display, "QuantityInput")
    return type(Field(input, "SetQuantity")) == "function"
        or type(Field(Field(input, "InputBox"), "SetNumber")) == "function"
end

--------------------------------------------------------------------------------
-- What to fill
--------------------------------------------------------------------------------

--- Remember what a list searched for. A quantity under 1, or none, forgets:
--- any other search is not the list's, and fills nothing.
function BuyQuantity:Want(itemID, quantity)
    self.wants = nil
    quantity = tonumber(quantity)
    if type(itemID) ~= "number" or not quantity or quantity < 1 then
        self.want = nil
        return
    end
    self.want = { itemID = itemID, quantity = math.floor(quantity) }
end

--- Remember every item a whole-list search looked for: counts is
--- [itemID] = quantity. Items with no count, or under 1, are left out, and
--- nothing left (or no table) forgets, as Want does.
function BuyQuantity:WantMany(counts)
    self.want = nil
    self.wants = nil
    if type(counts) ~= "table" then return end
    local wants
    for itemID, quantity in pairs(counts) do
        quantity = tonumber(quantity)
        if type(itemID) == "number" and quantity and quantity >= 1 then
            wants = wants or {}
            wants[itemID] = math.floor(quantity)
        end
    end
    self.wants = wants
end

--- What a search remembered for this item: { itemID, quantity }, or nil.
function BuyQuantity:WantFor(itemID)
    local want = self.want
    if want and (itemID == nil or itemID == want.itemID) then return want end
    local wants = self.wants
    if wants and itemID ~= nil and wants[itemID] then
        return { itemID = itemID, quantity = wants[itemID] }
    end
end

--- How many of the item the queue is still short of right now.
--
-- Asked again at the moment of filling, because the player may have bought
-- some since the search: buying 12 of 20 and picking the item again should
-- say 8. The number the list had at the search stands in if the item has
-- dropped off the list or the list cannot be read.
function BuyQuantity:StillNeeded(itemID, fallback)
    local queue = ns.Queue
    if queue and type(queue.GetShoppingList) == "function" then
        local ok, lines = pcall(queue.GetShoppingList, queue)
        if ok and type(lines) == "table" then
            for _, line in ipairs(lines) do
                if type(line) == "table" and line.itemID == itemID then
                    return math.max(0, math.floor(tonumber(line.shortfall) or 0))
                end
            end
        end
    end
    return fallback
end

--- Fill the box if it shows the item a list searched for.
-- @param itemID the item the buy window was just set to, when known
-- @return true when the box was filled
function BuyQuantity:Fill(itemID)
    if not (self.want or self.wants) then return false end
    if ns.Config and ns.Config:Get("fillBuyQuantity") == false then return false end

    itemID = itemID or self:ShownItemID()
    local want = self:WantFor(itemID)
    if not want or itemID ~= want.itemID then return false end

    local needed = self:StillNeeded(want.itemID, want.quantity)
    if not needed or needed < 1 then
        self.lastResult = "nothing still needed"
        return false
    end

    -- Opened at 1 (or empty, before its results are in). Anything else is
    -- the player's own number, or ours already.
    local shown = self:ShownQuantity()
    if shown ~= nil and shown > 1 then return false end
    if needed == 1 then return false end

    if self:SetShownQuantity(needed) then
        self.lastResult = ("filled %d"):format(needed)
        return true
    end

    self.lastResult = "no quantity box"
    return false
end

--- Fill now, and once more after Blizzard has had its results in.
function BuyQuantity:FillSoon(itemID)
    self:Fill(itemID)
    if C_Timer and C_Timer.After then
        C_Timer.After(SETTLE, function() self:Fill() end)
    end
end

--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------

--- Watch Blizzard's buy window. Its auction UI loads on demand, so this runs
--- each time the auction house opens and hooks a frame only once.
function BuyQuantity:Hook()
    local frame = self:BuyFrame()
    if type(frame) ~= "table" or hooked[frame] then return false end
    if type(hooksecurefunc) ~= "function" then return false end

    hooked[frame] = true

    -- Picking a result in Blizzard's list sets the buy window's item.
    if type(Field(frame, "SetItemIDAndPrice")) == "function" then
        pcall(hooksecurefunc, frame, "SetItemIDAndPrice", function(_, itemID)
            BuyQuantity.quoted = nil
            BuyQuantity:FillSoon(type(itemID) == "number" and itemID or nil)
            BuyQuantity:CheckCostSoon()
        end)
    end

    -- And in case this client sets it some other way, whenever it shows.
    if type(Field(frame, "HookScript")) == "function" then
        pcall(frame.HookScript, frame, "OnShow", function()
            BuyQuantity:FillSoon()
            BuyQuantity:CheckCostSoon()
        end)
        pcall(frame.HookScript, frame, "OnHide", function() BuyQuantity:HideWarning() end)
    end

    -- The number in the box, typed or filled: cost it again.
    local box = Field(Field(self:Display(), "QuantityInput"), "InputBox")
    if type(box) == "table" and not hooked[box] and type(Field(box, "HookScript")) == "function" then
        hooked[box] = true
        pcall(box.HookScript, box, "OnTextChanged", function() BuyQuantity:CheckCostSoon() end)
    end

    -- The list of listings only hears the quantity message while it shows,
    -- and may show after the window does: fill once more when it does.
    local list = Field(frame, "ItemList")
    if type(Field(list, "HookScript")) == "function" then
        pcall(list.HookScript, list, "OnShow", function() BuyQuantity:Fill() end)
    end

    return true
end

--------------------------------------------------------------------------------
-- Costs more than expected
--------------------------------------------------------------------------------

-- Below this many copper of difference the line stays away: 30% over on a
-- few copper is not worth a warning.
BuyQuantity.WARN_MIN_COPPER = 100
-- Coalesce a burst of updates (typing, results paging in) into one look.
local WARN_DELAY = 0.2

-- The warning's frame, made the first time it is needed.
BuyQuantity.warnFrame = nil
-- What the line said last, for the probe: "+1g 20s on 20", "none", ...
BuyQuantity.lastWarn = nil
-- The auction house's own total for a purchase it priced:
-- { itemID, quantity, total }, from COMMODITY_PRICE_UPDATED.
BuyQuantity.quoted = nil

--- What buying `quantity` costs up a list of listings, cheapest first, past
--- the player's own units.
-- @param listings { { unitPrice, quantity, own }, ... } in price order
-- @return copper, or nil when the listings hold fewer than `quantity`
function BuyQuantity.CostUp(listings, quantity)
    quantity = math.floor(tonumber(quantity) or 0)
    if quantity < 1 or type(listings) ~= "table" then return nil end
    local left, total = quantity, 0
    for _, listing in ipairs(listings) do
        local price = tonumber(listing.unitPrice)
        local units = math.max(0, (tonumber(listing.quantity) or 0) - (tonumber(listing.own) or 0))
        if price and price > 0 and units > 0 then
            local take = math.min(units, left)
            total = total + take * price
            left = left - take
            if left == 0 then return total end
        end
    end
    return nil
end

--- The listings the auction house holds for a commodity right now.
function BuyQuantity:LiveListings(itemID)
    local house = Field(_G, "C_AuctionHouse")
    local num = Field(house, "GetNumCommoditySearchResults")
    local info = Field(house, "GetCommoditySearchResultInfo")
    if type(num) ~= "function" or type(info) ~= "function" then return nil end

    local ok, count = pcall(num, itemID)
    if not ok or type(count) ~= "number" or count < 1 then return nil end

    local listings = {}
    for i = 1, count do
        local got, row = pcall(info, itemID, i)
        if got and type(row) == "table" then
            local price = tonumber(row.unitPrice)
            if price and ns.Prices and ns.Prices.IsCredible and not ns.Prices.IsCredible(price) then
                price = nil
            end
            if price then
                listings[#listings + 1] = {
                    unitPrice = price,
                    quantity = tonumber(row.quantity) or 0,
                    own = tonumber(row.numOwnerItems) or 0,
                }
            end
        end
    end
    return listings
end

--- Is the item one the shopping list is buying?
function BuyQuantity:OnShoppingList(itemID)
    local queue = ns.Queue
    if not (queue and type(queue.GetShoppingList) == "function") then return false end
    local ok, lines = pcall(queue.GetShoppingList, queue)
    if not ok or type(lines) ~= "table" then return false end
    for _, line in ipairs(lines) do
        if type(line) == "table" and line.itemID == itemID then return true end
    end
    return false
end

--- The warning for buying `quantity` of a material, or nil when it costs
--- about what the shopping list said.
-- @param live copper for that many now, from the listings or the auction
--   house's own quote
-- @return { live, estimate, more, percent } or nil
function BuyQuantity:Judge(itemID, quantity, live)
    local percent = ns.Config and tonumber(ns.Config:Get("buyWarnPercent"))
    if percent == nil then percent = 25 end
    if percent <= 0 or not live or live <= 0 then return nil end

    local estimate
    if ns.AHBuys and ns.AHBuys.Estimate then
        local ok, value = pcall(ns.AHBuys.Estimate, ns.AHBuys, itemID, quantity)
        estimate = ok and tonumber(value) or nil
    end
    if not estimate or estimate <= 0 then return nil end

    local more = live - estimate
    if more < self.WARN_MIN_COPPER then return nil end
    if live < estimate * (1 + percent / 100) then return nil end

    return {
        live = live, estimate = estimate, more = more,
        percent = math.floor(more / estimate * 100 + 0.5),
    }
end

--- The line's words: "Buying 20 costs 5g 20s 00c. The shopping list said
--- 3g 90s 00c: 1g 30s 00c more (33% over)."
function BuyQuantity.WarnText(quantity, warning)
    local money = ns.Util.FormatMoney
    local warn = "|c" .. ns.COLORS.warn
    -- Each sum is drawn in its own colour, then the warning colour again.
    local function Sum(copper) return "|r" .. money(copper) .. warn end
    return warn .. L.Format("Buying %d costs %s. The shopping list said %s: %s more (%d%% over).",
        quantity, Sum(warning.live), Sum(warning.estimate), Sum(warning.more), warning.percent) .. "|r"
end

function BuyQuantity:WarnFrame()
    if self.warnFrame then return self.warnFrame end
    local Theme = ns.Theme
    if not (Theme and CreateFrame) then return nil end

    local frame = Theme.CreatePanel(UIParent, "panel", "warn")
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    local label = Theme.CreateLabel(frame, "small", "text", "CENTER")
    label:SetPoint("TOPLEFT", 8, -5)
    label:SetPoint("TOPRIGHT", -8, -5)
    if label.SetWordWrap then label:SetWordWrap(true) end
    frame.label = label

    self.warnFrame = frame
    return frame
end

function BuyQuantity:HideWarning()
    if self.warnFrame then self.warnFrame:Hide() end
end

--- Place and fill the line, under the Buy Now button.
function BuyQuantity:ShowWarning(quantity, warning)
    local frame = self:WarnFrame()
    if not frame then return end

    local display = self:Display()
    local button = Field(display, "BuyButton")
    local anchor = type(button) == "table" and button or display
    if type(anchor) ~= "table" then return end

    local width = 260
    local ok, w = Call(display, "GetWidth")
    if ok and type(w) == "number" and w > 80 then width = math.min(w - 16, 320) end

    frame:ClearAllPoints()
    frame:SetPoint("TOP", anchor, "BOTTOM", 0, -6)
    frame:SetWidth(width)
    frame.label:SetText(self.WarnText(quantity, warning))
    local textHeight = frame.label.GetStringHeight and frame.label:GetStringHeight() or 24
    frame:SetHeight(math.max(24, (tonumber(textHeight) or 24) + 10))
    frame:Show()
end

--- Look at the buy window now and show or hide the line.
function BuyQuantity:CheckCost()
    self.checkPending = nil
    local frame = self:BuyFrame()
    local ok, shown = Call(frame, "IsVisible")
    if not (ok and shown) then
        self:HideWarning()
        return
    end

    local itemID = self:ShownItemID()
    local quantity = self:ShownQuantity()
    if not itemID or not quantity or quantity < 1 or not self:OnShoppingList(itemID) then
        self.lastWarn = "none"
        self:HideWarning()
        return
    end

    local live
    local quoted = self.quoted
    if quoted and quoted.itemID == itemID and quoted.quantity == quantity then
        live = quoted.total
    else
        live = self.CostUp(self:LiveListings(itemID), quantity)
    end

    local warning = self:Judge(itemID, quantity, live)
    if not warning then
        self.lastWarn = "none"
        self:HideWarning()
        return
    end

    self.lastWarn = ("+%s on %d"):format(ns.Util.FormatMoney(warning.more, { noColor = true }), quantity)
    self:ShowWarning(quantity, warning)
end

--- Look once, a moment after a burst of changes settles.
function BuyQuantity:CheckCostSoon()
    if self.checkPending then return end
    if not (C_Timer and C_Timer.After) then return self:CheckCost() end
    self.checkPending = true
    C_Timer.After(WARN_DELAY, function() BuyQuantity:CheckCost() end)
end

--- The probe's line: can this client's buy window be filled?
function BuyQuantity:ProbeText()
    if not self:BuyFrame() then return "open the auction house and run this again" end
    local text = self:HasQuantityBox() and "yes" or "no quantity box found"
    if self.lastResult then text = text .. ", last: " .. self.lastResult end
    if self.lastWarn then text = text .. ", cost warning: " .. self.lastWarn end
    return text
end

function BuyQuantity:OnEnable()
    ns.RegisterEvent(self, "AUCTION_HOUSE_SHOW", function()
        BuyQuantity:Hook()
        -- The auction UI may not exist yet on the first open of a session.
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, function() BuyQuantity:Hook() end)
        end
    end)

    -- A want is for this visit only.
    ns.RegisterEvent(self, "AUCTION_HOUSE_CLOSED", function()
        BuyQuantity.want = nil
        BuyQuantity.wants = nil
        BuyQuantity.quoted = nil
        BuyQuantity:HideWarning()
    end)

    -- The listings for the item in the buy window arrived or changed.
    ns.RegisterEvent(self, "COMMODITY_SEARCH_RESULTS_UPDATED", function(_, _, itemID)
        if not BuyQuantity:BuyFrame() then return end
        if itemID ~= nil and itemID ~= BuyQuantity:ShownItemID() then return end
        BuyQuantity.quoted = nil
        BuyQuantity:CheckCostSoon()
    end)

    -- Buy Now asked the auction house for the total: its own number beats
    -- the listings counted up.
    ns.RegisterEvent(self, "COMMODITY_PRICE_UPDATED", function(_, _, _, total)
        local quote = ns.AHBuys and ns.AHBuys.quote
        if type(quote) ~= "table" or type(total) ~= "number" then return end
        BuyQuantity.quoted = { itemID = quote.itemID, quantity = quote.quantity, total = total }
        BuyQuantity:CheckCostSoon()
    end)
end
