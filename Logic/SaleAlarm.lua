-- Blackthornes Tradeskills -- Logic/SaleAlarm.lua
-- Plays a sound the moment the game says one of your auctions has sold.
--
-- The game tells the seller about a sale straight away, wherever they are in
-- the world, and it can do so in one of two ways depending on the version:
--
--   * a system chat line built from ERR_AUCTION_SOLD_S ("A buyer has been
--     found for your auction of %s."), arriving as CHAT_MSG_SYSTEM;
--   * an auction house notice, AUCTION_HOUSE_SHOW_NOTIFICATION or its
--     _FORMATTED_ twin, carrying Enum.AuctionHouseNotification.AuctionSold.
--
-- Which of these this version of the game sends has not been seen yet, so both
-- are listened for and each one is counted separately. `/bts salealarm` reports
-- the counts, which is what settles the question after a real sale -- a signal
-- that registered without complaint is not proof that it ever arrives.
--
-- The chat line is matched against the game's own ERR_AUCTION_SOLD_S, never
-- against English text, so it works in any language the game runs in. Where
-- that global is missing the chat route is simply off rather than guessed at.
--
-- The sale mail is deliberately NOT a signal: it turns up an hour later, and
-- only at a mailbox. An alarm is only useful at the moment of the sale.

local _, ns = ...

local SaleAlarm = ns.NewModule("SaleAlarm")

-- RAID_WARNING: loud, short and unlike anything the auction house plays itself,
-- so it cannot be mistaken for the window opening or a click. Read from the
-- game's own table when it has one.
local RAID_WARNING_SOUND = 8959

-- Two routes can report the same sale within a moment of each other, and so
-- can a buyer taking several of your auctions at once. One alarm per burst.
local QUIET_SECONDS = 2

SaleAlarm.heard = { chat = 0, notice = 0 }
SaleAlarm.listening = { chat = false, notice = false }
SaleAlarm.played = 0
SaleAlarm.lastPlayAt = nil
SaleAlarm.lastSale = nil       -- { item = name or nil, at = time(), via = "chat"|"notice" }
SaleAlarm.lastPlayAccepted = nil

local function Now()
    if type(GetTime) == "function" then return GetTime() end
    return time()
end

function SaleAlarm:IsOn()
    return ns.Config:Get("saleAlarm") ~= false
end

--------------------------------------------------------------------------------
-- Recognising a sale
--------------------------------------------------------------------------------

local soldPattern

--- The game's own "a buyer has been found" line, as a Lua pattern.
local function GetSoldPattern()
    if soldPattern ~= nil then return soldPattern or nil end

    local format = _G.ERR_AUCTION_SOLD_S
    if type(format) ~= "string" or format == "" then
        soldPattern = false
        return nil
    end

    -- Escape everything the pattern language would read, then put a capture
    -- for the item name back where the %s was.
    local escaped = format:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    soldPattern = "^" .. escaped:gsub("%%%%s", "(.+)") .. "$"
    return soldPattern
end

--- Let the tests rebuild the pattern after changing the game's globals.
function SaleAlarm:InvalidatePattern()
    soldPattern = nil
end

--- The item name if this chat line is the game announcing one of your sales.
function SaleAlarm:MatchSoldLine(text)
    local pattern = GetSoldPattern()
    if not pattern or type(text) ~= "string" then return nil end

    -- Inside a dungeon a system line can be one the game will not let the
    -- addon read, and matching it would raise. Such a line is not a sale.
    local ok, item = pcall(string.match, text, pattern)
    if not ok or item == nil then return nil end

    -- Hand back a plain string, or nothing.
    local plain, copy = pcall(function() return item .. "" end)
    return plain and copy or nil
end

--- Whether an auction house notice is the "sold" one.
-- Compared against the game's own enum. Without the enum there is no way to
-- know which number means sold, and guessing would sound the alarm on outbids.
function SaleAlarm:IsSoldNotice(notification)
    local names = _G.Enum and _G.Enum.AuctionHouseNotification
    local sold = names and names.AuctionSold
    return sold ~= nil and notification == sold
end

--------------------------------------------------------------------------------
-- The sound
--------------------------------------------------------------------------------

--- Play the alarm now. Returns whether the game said it would play it.
-- The "Master" channel is used so it still sounds with game effects turned
-- down or off; only the game's master volume, or the game being in the
-- background with background sound off, silences it.
function SaleAlarm:Play()
    if type(PlaySound) ~= "function" then
        self.lastPlayAccepted = false
        return false
    end

    local kit = (_G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING) or RAID_WARNING_SOUND
    local ok, willPlay = pcall(PlaySound, kit, "Master")

    -- Older versions return nothing at all, which is not a refusal.
    if not ok then
        self.lastPlayAccepted = false
    elseif willPlay == nil then
        self.lastPlayAccepted = "unknown"
    else
        self.lastPlayAccepted = willPlay and true or false
    end

    self.played = self.played + 1
    self.lastPlayAt = Now()
    return self.lastPlayAccepted
end

--- Record a sale from either route and sound the alarm, once per burst.
function SaleAlarm:OnSale(via, item)
    self.heard[via] = (self.heard[via] or 0) + 1
    self.lastSale = { item = item, at = time(), via = via }

    if not self:IsOn() then return false end

    local now = Now()
    if self.lastPlayAt and now - self.lastPlayAt < QUIET_SECONDS then
        return false
    end

    self:Play()
    return true
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function SaleAlarm:CHAT_MSG_SYSTEM(_, text)
    local item = self:MatchSoldLine(text)
    if item then self:OnSale("chat", item) end
end

--- Every notice the auction house sends, sold or not.
-- Counted so that /bts salealarm can tell "the notice never fired" from "it
-- fired and was not the sold one", which the sold count alone cannot.
function SaleAlarm:CountNotice(notification)
    self.heard.anyNotice = (self.heard.anyNotice or 0) + 1
    self.lastNotice = notification
end

function SaleAlarm:AUCTION_HOUSE_SHOW_NOTIFICATION(_, notification)
    self:CountNotice(notification)
    if self:IsSoldNotice(notification) then self:OnSale("notice") end
end

function SaleAlarm:AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION(_, notification, text)
    self:CountNotice(notification)
    if self:IsSoldNotice(notification) then
        self:OnSale("notice", type(text) == "string" and text or nil)
    end
end

function SaleAlarm:OnEnable()
    -- The chat route is only worth listening to if there is a line to match.
    if GetSoldPattern() then
        self.listening.chat = ns.RegisterEvent(self, "CHAT_MSG_SYSTEM", self.CHAT_MSG_SYSTEM) and true or false
    end

    local plain = ns.RegisterEvent(self, "AUCTION_HOUSE_SHOW_NOTIFICATION",
        self.AUCTION_HOUSE_SHOW_NOTIFICATION)
    local formatted = ns.RegisterEvent(self, "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION",
        self.AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION)
    self.listening.notice = (plain or formatted) and true or false
end

--------------------------------------------------------------------------------
-- /bts salealarm
--------------------------------------------------------------------------------

local function Yes(value) return value and "yes" or "no" end

--- Whether the game plays sound while its window is not in front.
-- nil when it cannot be read.
local function BackgroundSound()
    local name = "Sound_EnableSoundWhenGameIsInBG"
    if C_CVar and C_CVar.GetCVarBool then
        local ok, on = pcall(C_CVar.GetCVarBool, name)
        if ok and on ~= nil then return on end
    end
    if type(GetCVar) == "function" then
        local ok, value = pcall(GetCVar, name)
        if ok and value ~= nil then return value == "1" end
    end
    return nil
end

function SaleAlarm:Report()
    local accent, muted = ns.COLORS.accent, ns.COLORS.muted

    ns.Print(("Sale alarm: |c%s%s|r"):format(accent, self:IsOn() and "on" or "off"))

    ns.PrintRaw(("  |c%slistening for the sold chat line:|r %s"):format(
        muted, Yes(self.listening.chat)))
    ns.PrintRaw(("  |c%slistening for the auction house notice:|r %s"):format(
        muted, Yes(self.listening.notice)))
    ns.PrintRaw(("  |c%ssales heard this session:|r chat line %d, notice %d"):format(
        muted, self.heard.chat or 0, self.heard.notice or 0))

    -- Which number means "sold" comes from the game's enum. Without it every
    -- notice is ignored, and that has to be said, or "notice 0" reads as the
    -- event never firing.
    local names = _G.Enum and _G.Enum.AuctionHouseNotification
    local sold = names and names.AuctionSold
    ns.PrintRaw(("  |c%sauction house notices of any kind this session:|r %d%s"):format(
        muted, self.heard.anyNotice or 0,
        self.lastNotice ~= nil and (", last was %s"):format(tostring(self.lastNotice)) or ""))
    ns.PrintRaw(("  |c%sthe game says the sold notice is:|r %s"):format(
        muted, sold ~= nil and tostring(sold) or "unknown (no enum), so the notice route cannot fire"))
    ns.PrintRaw(("  |c%salarms played this session:|r %d"):format(muted, self.played))

    if self.lastSale then
        ns.PrintRaw(("  |c%slast sale:|r %s, %s, heard by the %s"):format(
            muted, self.lastSale.item or "an item",
            ns.Util.FormatAgeAgo(time() - self.lastSale.at),
            self.lastSale.via == "chat" and "chat line" or "notice"))
    end

    local background = BackgroundSound()
    if background == false then
        ns.PrintRaw(("  |c%sSound in Background is off, so the alarm is silent while the game is not the window in front. Turn it on in Options > Sound.|r"):format(
            ns.COLORS.warn))
    end
end

ns.RegisterCommand("salealarm", "sound an alarm when an auction sells: /bts salealarm [on|off|test]",
    function(args)
        local word = (args or ""):lower():match("^(%S+)")

        if word == "on" or word == "off" then
            ns.Config:Set("saleAlarm", word == "on")
            ns.Print(("Sale alarm %s."):format(word))
            if ns.UI and ns.UI.RefreshActiveTab then ns.UI:RefreshActiveTab() end
            return
        end

        if word == "test" then
            local accepted = SaleAlarm:Play()
            if accepted == false then
                ns.Warn("The game refused to play the alarm sound.")
            else
                ns.Print("Played the sale alarm. If you heard nothing, check the game's master volume.")
            end
            return
        end

        SaleAlarm:Report()
    end)
