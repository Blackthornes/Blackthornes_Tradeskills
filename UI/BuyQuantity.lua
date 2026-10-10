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

local _, ns = ...

local BuyQuantity = ns.NewModule("BuyQuantity")

-- The item a list searched for: { itemID, quantity }, or nil.
BuyQuantity.want = nil
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
    quantity = tonumber(quantity)
    if type(itemID) ~= "number" or not quantity or quantity < 1 then
        self.want = nil
        return
    end
    self.want = { itemID = itemID, quantity = math.floor(quantity) }
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
    local want = self.want
    if not want then return false end
    if ns.Config and ns.Config:Get("fillBuyQuantity") == false then return false end

    itemID = itemID or self:ShownItemID()
    if itemID ~= want.itemID then return false end

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
            BuyQuantity:FillSoon(type(itemID) == "number" and itemID or nil)
        end)
    end

    -- And in case this client sets it some other way, whenever it shows.
    if type(Field(frame, "HookScript")) == "function" then
        pcall(frame.HookScript, frame, "OnShow", function() BuyQuantity:FillSoon() end)
    end

    -- The list of listings only hears the quantity message while it shows,
    -- and may show after the window does: fill once more when it does.
    local list = Field(frame, "ItemList")
    if type(Field(list, "HookScript")) == "function" then
        pcall(list.HookScript, list, "OnShow", function() BuyQuantity:Fill() end)
    end

    return true
end

--- The probe's line: can this client's buy window be filled?
function BuyQuantity:ProbeText()
    if not self:BuyFrame() then return "open the auction house and run this again" end
    local text = self:HasQuantityBox() and "yes" or "no quantity box found"
    if self.lastResult then text = text .. ", last: " .. self.lastResult end
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
    end)
end
