-- Blackthornes Tradeskills -- Logic/MyAuctions.lua
-- The auction house drawer's Auctions view (a player asked, the owner
-- agreeing 2026-10-14, from a mockup): every auction you have up, the ones
-- someone has undercut first, each with a Cancel button.
--
-- What it reads is what Data/Auctions.lua already reads at the auction house
-- (QueryOwnedAuctions, GetOwnedAuctionInfo), kept for the session with each
-- auction's ID (`Auctions.live`). Other characters' auctions come from their
-- last reading (`Auctions:GetListings`), shown but never cancellable here.
--
-- Undercut means your price for one is above the cheapest listing that is not
-- yours (`Prices:GetScanValue(id, "rival")`), from a scan no older than
-- FRESH. An older scan says nothing rather than guess.
--
-- Cancelling: C_AuctionHouse.CancelAuction wants a real click for each
-- auction, so it is only ever called straight from a button's click, one
-- auction a click, never queued and never in a loop. Whether it went through
-- is read back from your auctions, as a listing is. A cancelled auction's
-- item comes back in the mail, and its deposit is not returned, so listing it
-- again costs a new one: each row says about how much.

local _, ns = ...

local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local MyAuctions = ns.NewModule("MyAuctions")

local Util = ns.Util

-- How old a scan may be and still say whether you were undercut.
MyAuctions.FRESH = 3600

-- How long a cancel may go unseen before it is called a failure.
MyAuctions.CANCEL_WAIT = 6

-- Moves when something the list shows changed (a read, a cancel).
MyAuctions.version = 0

local function CharacterKey()
    return ns.Config and ns.Config.GetCharacterKey and ns.Config:GetCharacterKey() or nil
end

local function IsPlaying(who)
    if ns.Characters and ns.Characters.IsPlaying then
        local ok, playing = pcall(ns.Characters.IsPlaying, ns.Characters, who)
        if ok then return playing and true or false end
    end
    return who ~= nil and who == CharacterKey()
end

local function AuctionHouseOpen()
    return ns.Scanner ~= nil and ns.Scanner.isAuctionHouseOpen == true
end

--- What the scans say about one of your auctions.
-- @return state ("undercut", "cheapest" or "unknown"), the cheapest price
--         not yours (nil when none), and how far under you it is
function MyAuctions:Judge(itemID, unit)
    local Prices = ns.Prices
    if not (Prices and itemID) then return "unknown" end

    local age = Prices.GetAge and Prices:GetAge(itemID)
    if not age or age > self.FRESH then return "unknown" end

    if not unit then return "unknown" end
    local rival = Prices:GetScanValue(itemID, "rival")
    if not rival or rival <= 0 then return "cheapest", rival end
    if unit > rival then return "undercut", rival, unit - rival end
    return "cheapest", rival
end

--- Your other characters' listings as last read (never raises).
function MyAuctions:Listings()
    local Auctions = ns.Auctions
    if not (Auctions and Auctions.GetListings) then return {} end
    local ok, listings = pcall(Auctions.GetListings, Auctions)
    return ok and type(listings) == "table" and listings or {}
end

--- itemID -> the prices each of every auction of yours up, on any character.
function MyAuctions:OwnUnits(listings)
    local own = {}
    local function Note(itemID, unit)
        if itemID and type(unit) == "number" then
            own[itemID] = own[itemID] or {}
            own[itemID][#own[itemID] + 1] = unit
        end
    end
    for _, auction in ipairs((ns.Auctions and ns.Auctions.live) or {}) do Note(auction.itemID, auction.unit) end
    for _, listing in ipairs(listings or self:Listings()) do
        if not listing.ended then Note(listing.itemID, listing.unit) end
    end
    return own
end

--- Judge, but the scan's "not yours" leaves out only the character that
--- scanned: a cheaper auction of your own on another character is not
--- someone undercutting you.
function MyAuctions:JudgeOwn(itemID, unit, ownUnits)
    local state, rival, gap = self:Judge(itemID, unit)
    if state == "undercut" and rival and ownUnits then
        for _, own in ipairs(ownUnits[itemID] or {}) do
            if own < unit and math.abs(own - rival) <= 1 then return "cheapest", rival end
        end
    end
    return state, rival, gap
end

--- About what listing it again would cost: the client's own cancel cost when
--- it has one, else the deposit Tradeskills remembers for that item.
-- @return copper or nil, and whether it is only an estimate
function MyAuctions:Deposit(row)
    if not row then return nil end

    local AH = _G.C_AuctionHouse
    if row.auctionID and type(AH) == "table" and type(AH.GetCancelCost) == "function" then
        local ok, cost = pcall(AH.GetCancelCost, row.auctionID)
        cost = ok and tonumber(cost) or nil
        if cost and cost > 0 then return cost, false end
    end

    local record = ns.db and ns.db.deposits and ns.db.deposits[row.itemID]
    if type(record) == "table" and tonumber(record.unit) then
        return math.max(1, math.floor(record.unit * (row.quantity or 1) + 0.5)), true
    end
    return nil
end

--- A cancel that costs more in a new deposit than the gap it closes.
function MyAuctions:GapSmallerThanDeposit(row)
    if not (row and row.gap) then return false end
    local deposit = self:Deposit(row)
    return deposit ~= nil and row.gap * (row.quantity or 1) < deposit
end

--- Every auction to show, in the order the view draws them.
-- @return rows, and a summary { up, undercut, worth, alts, read }
function MyAuctions:Rows()
    local rows = {}
    local summary = { up = 0, undercut = 0, worth = 0, alts = 0, read = false }
    local Auctions = ns.Auctions
    if not Auctions then return rows, summary end

    local now = time()
    local cancelling = self.cancelling or {}

    local listings = self:Listings()
    local ownUnits = self:OwnUnits(listings)
    local function JudgeRow(row) return self:JudgeOwn(row.itemID, row.unit, ownUnits) end

    if Auctions.live then
        summary.read = true
        for _, auction in ipairs(Auctions.live) do
            local row = {}
            for k, v in pairs(auction) do row[k] = v end
            row.mine = true
            row.state, row.rival, row.gap = JudgeRow(row)
            row.cancelling = cancelling[row.auctionID] ~= nil
            rows[#rows + 1] = row
            summary.up = summary.up + 1
            if row.state == "undercut" and not row.cancelling then summary.undercut = summary.undercut + 1 end
            summary.worth = summary.worth + (row.unit or 0) * (row.quantity or 1)
        end
    end

    -- Other characters, as last read: never this one, which is read live.
    for _, listing in ipairs(listings) do
        if not listing.ended and not IsPlaying(listing.who) then
            local row = {}
            for k, v in pairs(listing) do row[k] = v end
            row.alt = true
            row.state, row.rival, row.gap = JudgeRow(row)
            rows[#rows + 1] = row
            summary.alts = summary.alts + 1
        end
    end

    local order = { undercut = 1, cheapest = 2, unknown = 3 }
    table.sort(rows, function(a, b)
        if (a.alt or false) ~= (b.alt or false) then return not a.alt end
        local oa, ob = order[a.state] or 9, order[b.state] or 9
        if oa ~= ob then return oa < ob end
        -- Most money under first, then soonest to end.
        local ga = (a.gap or 0) * (a.quantity or 1)
        local gb = (b.gap or 0) * (b.quantity or 1)
        if ga ~= gb then return ga > gb end
        return (a.ends or math.huge) < (b.ends or math.huge)
    end)

    for _, row in ipairs(rows) do
        row.left = row.ends and math.max(0, row.ends - now) or nil
    end

    return rows, summary
end

--- Whether the player can cancel right now, and why not.
function MyAuctions:CanCancel(row)
    if not AuctionHouseOpen() then return false, L["the auction house must be open"] end
    if not Util.HasFunction("C_AuctionHouse.CancelAuction") then
        return false, L["the game will not let addons cancel auctions"]
    end
    if row and row.alt then return false, L["Log in on that character to cancel it."] end
    if row and not row.auctionID then return false, L["Scan your auctions again first."] end
    if row and (row.cancelling or (row.auctionID and self.cancelling and self.cancelling[row.auctionID])) then
        return false, L["Already cancelling that one."]
    end
    if ns.Scanner and ns.Scanner.isScanning then return false, L["wait for the scan to finish"] end
    if ns.Posting and ns.Posting.IsThrottled and ns.Posting:IsThrottled() then
        return false, L["the auction house is busy, try again in a moment"]
    end

    local AH = _G.C_AuctionHouse
    if row and type(AH.CanCancelAuction) == "function" then
        local ok, can = pcall(AH.CanCancelAuction, row.auctionID)
        if ok and can == false then return false, L["The auction house won't let you cancel that one."] end
    end
    return true
end

local function StillUp(auctionID)
    for _, auction in ipairs((ns.Auctions and ns.Auctions.live) or {}) do
        if auction.auctionID == auctionID then return auction end
    end
end

--- Cancel one auction. Call it only from a click: the game asks for one.
-- @return true, or false and why
function MyAuctions:Cancel(row)
    if type(row) ~= "table" then return false end

    -- Read again: the row may be from before the last read.
    local auction = row.auctionID and StillUp(row.auctionID)
    if row.mine and not auction then
        return false, L["That auction is gone already."]
    end

    local allowed, reason = self:CanCancel(row)
    if not allowed then return false, reason end

    local ok, err = pcall(C_AuctionHouse.CancelAuction, row.auctionID)
    if not ok then
        ns.Debug("cancel failed: " .. tostring(err))
        return false, L["The game would not cancel it."]
    end

    if ns.AHQueue and ns.AHQueue.NoteSend then ns.AHQueue:NoteSend() end
    self.cancelling = self.cancelling or {}
    self.cancelling[row.auctionID] = { at = GetTime(), itemID = row.itemID, quantity = row.quantity }
    self.cancelCount = (self.cancelCount or 0) + 1
    self.version = self.version + 1

    -- Read back whether it went, as a listing is.
    if ns.Auctions and ns.Auctions.Refresh then
        C_Timer.After(0.5, function() ns.Auctions:Refresh({ force = true }) end)
    end
    return true
end

--- The undercut auction the foot button cancels next: the most money under.
function MyAuctions:NextUndercut(rows)
    rows = rows or self:Rows()
    local AH = _G.C_AuctionHouse
    for _, row in ipairs(rows) do
        if row.mine and row.state == "undercut" and not row.cancelling then
            -- One the game won't cancel would be picked on every click.
            local refused = false
            if row.auctionID and type(AH) == "table" and type(AH.CanCancelAuction) == "function" then
                local ok, can = pcall(AH.CanCancelAuction, row.auctionID)
                refused = ok and can == false
            end
            if not refused then return row end
        end
    end
end

--- Cancel the next undercut auction, from the foot button's click.
function MyAuctions:CancelNext()
    local row = self:NextUndercut()
    if not row then
        ns.Print(L["None of your auctions are undercut."])
        return false
    end
    local ok, reason = self:Cancel(row)
    if not ok and reason then ns.Print(reason) end
    return ok
end

--- A read of your auctions: settle what was being cancelled.
function MyAuctions:OnRead(live, final, sold)
    local cancelling = self.cancelling
    self.version = self.version + 1
    if not cancelling or next(cancelling) == nil then return end

    local up = {}
    for _, auction in ipairs(live or {}) do up[auction.auctionID] = true end

    local now = GetTime()
    for auctionID, pending in pairs(cancelling) do
        local label = Util.GetItemLabel(pending.itemID) or L["that item"]
        if sold and sold[auctionID] then
            cancelling[auctionID] = nil
            ns.Print(L.Format("%s sold before the cancel went through.", label))
        elseif not up[auctionID] then
            cancelling[auctionID] = nil
            self.cancelledCount = (self.cancelledCount or 0) + 1
            ns.Print(L.Format("Cancelled %s. It comes back to you in the mail.", label))
        elseif final and now - pending.at >= self.CANCEL_WAIT then
            cancelling[auctionID] = nil
            ns.Print(L.Format("%s is still up. The cancel didn't go through.", label))
        end
    end
end

--- For /bts probe: which cancel calls this client has, and what happened.
function MyAuctions:ProbeText()
    local AH = _G.C_AuctionHouse
    local function Has(name) return type(AH) == "table" and type(AH[name]) == "function" end
    local parts = {
        Has("CancelAuction") and "cancel yes" or "cancel NO",
        Has("GetCancelCost") and "cancel cost yes" or "cancel cost NO",
        Has("CanCancelAuction") and "can cancel yes" or "can cancel NO",
    }
    parts[#parts + 1] = ("tried %d, went %d"):format(self.cancelCount or 0, self.cancelledCount or 0)
    return table.concat(parts, ", ")
end
