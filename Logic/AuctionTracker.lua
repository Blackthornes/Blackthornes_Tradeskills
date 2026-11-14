-- Blackthornes Tradeskills -- Logic/AuctionTracker.lua
-- My Auctions: a small window listing what you have up on the auction
-- house. When something sells it lights up, pops its gold and leaves.
--
-- Asked 2026-11-11, from a mockup the owner approved with its words. Off
-- until ticked ("Auction Tracker:" on the Auction page).
--
-- What the game lets us see:
--   * Your whole list is read only while the auction house is open
--     (Data/Auctions.lua, `Auctions.live`). Away from it the list is what it
--     saw last (this session's read, else the saved listings of the
--     character playing) and the time left counts down on its own.
--   * A sale is heard anywhere through the sale alarm's "a buyer has been
--     found" line (SaleAlarm:LogHeard calls AuctionTracker:Sold). That line
--     names the item only, never the price, so the gold shown is the
--     listing's buyout less the 5% cut. The sale mail an hour later has the
--     exact amount.
--   * Two listings of the same item: the cheapest one leaves. Part of a
--     stack sold (a count in the line): the row stays with fewer, and the
--     next look at the auction house sets it right.
--   * An auction that runs out leaves with no gold.
--
-- Saved, account wide, never renamed: `auctionTrackerSold[character key] =
-- { day, copper, count }`, today's sales, started again each day. The
-- settings are in Core/Config.lua. UI/AuctionTracker.lua draws it.

local _, ns = ...

local AuctionTracker = ns.NewModule("AuctionTracker")

-- What the auction house keeps of a sale.
AuctionTracker.CUT = 0.05
-- The longest each rough time band can be, when the game gave no seconds.
AuctionTracker.BAND_MOST = { [0] = 30 * 60, [1] = 2 * 3600, [2] = 12 * 3600, [3] = 48 * 3600 }
-- Moved whenever the rows or Sold Today may have changed, so the window
-- draws again only then.
AuctionTracker.version = 0

local function Now() return time() end

local function CharacterKey()
    local ok, key = pcall(function() return ns.Config:GetCharacterKey() end)
    return ok and key or "?"
end

function AuctionTracker:IsOn()
    return ns.Config and ns.Config:Get("auctionTracker") == true or false
end

function AuctionTracker:SetOn(on)
    ns.Config:Set("auctionTracker", on and true or false)
    self:Changed()
    if ns.AuctionTrackerUI and ns.AuctionTrackerUI.Apply then ns.AuctionTrackerUI:Apply() end
end

--- "full", "subtle" or "off": the tracker's own Sold Effects, never more
--- than the Effects setting allows.
function AuctionTracker:EffectsLevel()
    local own = ns.Config and ns.Config:Get("auctionTrackerEffects") or "full"
    if own ~= "subtle" and own ~= "off" then own = "full" end
    local window = ns.Motion and ns.Motion.Level and ns.Motion.Level() or "full"
    local rank = { off = 0, subtle = 1, full = 2 }
    if (rank[window] or 2) < rank[own] then return window end
    return own
end

function AuctionTracker:Changed()
    self.version = (self.version or 0) + 1
end

-- This session's word on each row: gone (sold or ran out) or how many are
-- left after part of a stack sold. Forgotten when the auction house is read
-- again, since that read is the truth.
local function Session(self)
    self.gone = self.gone or {}
    self.left = self.left or {}
    return self.gone, self.left
end

--- A new read of your auctions (Data/Auctions.lua).
function AuctionTracker:OnRead()
    self.gone, self.left = {}, {}
    self:Changed()
end

--- Your auctions, soonest to end first:
--- { key, itemID, link, quantity, unit, ends, roughEnd }.
function AuctionTracker:Rows()
    local now = Now()
    local gone, left = Session(self)
    local out = {}
    local Auctions = ns.Auctions

    local function Add(key, row)
        if gone[key] then return end
        if row.ends and row.ends <= now then return end
        row.key = key
        if left[key] then row.quantity = left[key] end
        out[#out + 1] = row
    end

    if Auctions and Auctions.ownedIDs and type(Auctions.live) == "table" then
        local readAt = Auctions.liveAt or now
        for _, live in ipairs(Auctions.live) do
            local ends = live.ends
            local rough = false
            if not ends and live.band and self.BAND_MOST[live.band] then
                ends, rough = readAt + self.BAND_MOST[live.band], true
            end
            Add("a:" .. tostring(live.auctionID), {
                itemID = live.itemID, link = live.link, quantity = live.quantity or 1,
                unit = live.unit, ends = ends, roughEnd = rough,
            })
        end
    elseif Auctions and Auctions.GetListings then
        local ok, listings = pcall(Auctions.GetListings, Auctions)
        local me = CharacterKey()
        if ok and type(listings) == "table" then
            for index, listing in ipairs(listings) do
                if listing.who == me and not listing.ended then
                    Add(("s:%s:%s:%s:%d"):format(tostring(listing.itemID), tostring(listing.unit),
                        tostring(listing.ends), index), {
                        itemID = listing.itemID, quantity = listing.quantity or 1,
                        unit = listing.unit, ends = listing.ends, roughEnd = listing.roughEnd,
                    })
                end
            end
        end
    end

    table.sort(out, function(a, b)
        local x, y = a.ends or math.huge, b.ends or math.huge
        if x ~= y then return x < y end
        return a.key < b.key
    end)
    return out
end

--- The count a sale line carries ("Linen Cloth (5)", "Linen Cloth x5"),
--- and the name without it.
function AuctionTracker.ParseItem(item)
    if type(item) ~= "string" then return nil, nil end
    local ok, plain, count = pcall(function()
        local text = item:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        text = text:match("%[(.-)%]") or text
        local n = text:match("%((%d+)%)%s*$") or text:match("%s[xX]%s?(%d+)%s*$")
        text = text:gsub("%s*%(%d+%)%s*$", ""):gsub("%s+[xX]%s?%d+%s*$", "")
        return text, tonumber(n)
    end)
    if not ok then return item, nil end
    if ns.Mail and ns.Mail.PlainName then
        local named = ns.Mail.PlainName(plain)
        if type(named) == "string" and named ~= "" then plain = named end
    end
    return plain, count
end

local function NameOf(itemID)
    if not itemID then return nil end
    if ns.Util and ns.Util.GetItemName then
        local ok, name = pcall(ns.Util.GetItemName, itemID)
        if ok and type(name) == "string" then return name end
    end
    return nil
end

--- The gold one sale brings in, after the auction house's cut.
function AuctionTracker:Net(unit, count)
    if not unit or unit <= 0 then return 0 end
    return math.floor(unit * (count or 1) * (1 - self.CUT))
end

--- Today's sales for the character playing: copper, count.
function AuctionTracker:SoldToday()
    local db = ns.db
    if type(db) ~= "table" then return 0, 0 end
    local all = db.auctionTrackerSold
    local entry = type(all) == "table" and all[CharacterKey()] or nil
    if type(entry) ~= "table" or entry.day ~= date("%Y-%m-%d") then return 0, 0 end
    return tonumber(entry.copper) or 0, tonumber(entry.count) or 0
end

local function AddToday(copper)
    local db = ns.db
    if type(db) ~= "table" then return end
    db.auctionTrackerSold = type(db.auctionTrackerSold) == "table" and db.auctionTrackerSold or {}
    local key = CharacterKey()
    local today = date("%Y-%m-%d")
    local entry = db.auctionTrackerSold[key]
    if type(entry) ~= "table" or entry.day ~= today then
        entry = { day = today, copper = 0, count = 0 }
        db.auctionTrackerSold[key] = entry
    end
    entry.copper = (tonumber(entry.copper) or 0) + copper
    entry.count = (tonumber(entry.count) or 0) + 1
end

--- A sale was heard (SaleAlarm:LogHeard). Takes the row that sold off the
--- list and adds its gold to Sold Today. Returns the row and the gold, or
--- nil when no row of yours matches (no gold is made up then).
function AuctionTracker:Sold(item, itemID)
    local plain, count = self.ParseItem(item)
    local wanted = plain and plain:lower() or nil
    local best
    for _, row in ipairs(self:Rows()) do
        local match = itemID and row.itemID == itemID
        if not match and wanted then
            local name = NameOf(row.itemID)
            match = name ~= nil and name:lower() == wanted
        end
        if match and (not best or (row.unit or math.huge) < (best.unit or math.huge)) then
            best = row
        end
    end
    if not best then return nil end

    local gone, left = Session(self)
    local partial = count ~= nil and count < (best.quantity or 1)
    local sold = partial and count or (best.quantity or 1)
    if partial then
        left[best.key] = (best.quantity or 1) - count
    else
        gone[best.key] = "sold"
    end

    local net = self:Net(best.unit, sold)
    if net > 0 then AddToday(net) end
    self:Changed()
    if ns.AuctionTrackerUI and ns.AuctionTrackerUI.OnSold then
        pcall(ns.AuctionTrackerUI.OnSold, ns.AuctionTrackerUI, best, net, partial, sold)
    end
    return best, net, partial
end

function AuctionTracker:OnEnable()
    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function()
                if ns.AuctionTrackerUI and ns.AuctionTrackerUI.Apply then ns.AuctionTrackerUI:Apply() end
            end)
        end
    end)
end
