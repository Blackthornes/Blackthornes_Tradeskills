-- Blackthornes Tradeskills -- UI/AuctionWindow.lua
-- Our own auction house window, in place of the game's. Off unless ticked
-- ("Blackthornes UI Auction House:" on the Auction page of Settings, ownAuctionHouse).
--
-- The game's auction window is never hidden, moved or re-parented, and none
-- of its own functions are called: it is made see-through with the mouse off
-- (UI/Veil.lua), and our window lies exactly over it, so everything that
-- sits beside the game's window (the drawer, the one window) stays where it
-- was. Closing our window closes the auction house the game's way, and "Use
-- The Game's Window" lifts the veil for the rest of the visit.
--
-- This is the first piece: the window, its veil and its way out. The Browse
-- list, the buy panel and the other tabs come in later steps; until then
-- Sell, My Auctions, Deals and Snipe stay in the drawer beside it.

local _, ns = ...

local AuctionWindow = ns.NewModule("AuctionWindow")

local L = ns.L
local Theme = ns.Theme
local Widgets = ns.Widgets

-- The tabs hang this far in from the window's corners, as the main window's.
local TAB_INSET = 34
-- The game can build its window, and pieces of it, after it says it opened.
local LOOK_AGAIN = { 0.5, 2 }

-- True from AUCTION_HOUSE_SHOW to AUCTION_HOUSE_CLOSED.
AuctionWindow.open = false
-- True once "Use The Game's Window" was clicked this visit.
AuctionWindow.gameWindow = false

local function Setting()
    local Config = ns.Config
    return Config ~= nil and Config:Get("ownAuctionHouse") == true
end

local function After(seconds, fn)
    local timer = _G.C_Timer
    if timer and timer.After then timer.After(seconds, fn) else fn() end
end

local function GameFrame()
    local UI = ns.UI
    if UI and UI.FindAuctionFrame then return (UI:FindAuctionFrame()) end
    return nil
end

--- Whether our window should be up right now.
function AuctionWindow:Wanted()
    return Setting() and self.open and not self.gameWindow
end

--- Whether our window is the one showing.
function AuctionWindow:IsShown()
    return self.frame ~= nil and self.frame:IsShown() == true
end

--- Close the auction house the game's way. AUCTION_HOUSE_CLOSED then lifts
--- the veil and puts our window away.
function AuctionWindow:CloseAuctionHouse()
    local api = _G.C_AuctionHouse
    if api and api.CloseAuctionHouse then
        pcall(api.CloseAuctionHouse)
    elseif type(_G.CloseAuctionHouse) == "function" then
        pcall(_G.CloseAuctionHouse)
    end
end

--- "Use The Game's Window": the game's window comes back for this visit.
function AuctionWindow:UseGameWindow()
    self.gameWindow = true
    self:Update()
end

function AuctionWindow:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesTSAuctionWindow", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    frame:Hide()
    Theme.Fill(frame, "window")

    ns.Titanforged:Dress(frame, {
        title = L["Auction House"],
        close = function() AuctionWindow:CloseAuctionHouse() end,
    })

    local back = Widgets.CreateButton(frame, L["Use The Game's Window"], function()
        AuctionWindow:UseGameWindow()
    end, { height = 22 })
    -- Wide enough for its words in every language.
    if back.label then
        local wide = Theme.TextWidth(back.label)
        if type(wide) == "number" and wide > 0 then back:SetWidth(wide + 24) end
    end
    back:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -44, -30)
    frame.back = back

    -- The well the Browse list will sit in.
    local well = CreateFrame("Frame", nil, frame)
    well:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -60)
    well:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    Theme.Recess(well)
    frame.well = well

    local strip = Widgets.CreateTabStrip(frame, {
        { key = "browse", text = L["Browse"], width = 96 },
    }, function() end, { width = 400, hanging = true })
    strip:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", TAB_INSET, 0)
    strip:Select("browse")
    frame.strip = strip

    self.frame = frame
    return frame
end

--- Lay the veil and our window as the setting and the visit say. Safe to
--- call at any time; it changes only what is not already so.
function AuctionWindow:Update()
    local Veil = ns.Veil
    local game = GameFrame()

    if not self:Wanted() then
        if game and Veil and Veil:Covers(game) then
            -- A guarded piece waits for the fight to end.
            if Veil:Uncover(game) == false then self.waiting = true end
        end
        if self.frame then self.frame:Hide() end
        return
    end

    -- The game's window is not built yet: the looks after the event find it.
    if not game or not Veil then return end

    if Veil:Cover(game) == false then self.waiting = true end

    local frame = self:Build()
    frame:ClearAllPoints()
    frame:SetAllPoints(game)
    if frame.strip and frame.strip.SetRoom then
        local ok, width = pcall(game.GetWidth, game)
        if ok and type(width) == "number" and width > 2 * TAB_INSET then
            frame.strip:SetRoom(width - 2 * TAB_INSET)
        end
    end

    if not frame:IsShown() then frame:Show() end
end

function AuctionWindow:Opened()
    self.open = true
    self.gameWindow = false
    self.visit = (self.visit or 0) + 1
    self:Update()

    local visit = self.visit
    for _, seconds in ipairs(LOOK_AGAIN) do
        After(seconds, function()
            if AuctionWindow.open and AuctionWindow.visit == visit then AuctionWindow:Update() end
        end)
    end
end

function AuctionWindow:Closed()
    self.open = false
    self.gameWindow = false
    self:Update()
end

function AuctionWindow:OnEnable()
    ns.RegisterEvent(self, "AUCTION_HOUSE_SHOW", function() AuctionWindow:Opened() end)
    ns.RegisterEvent(self, "AUCTION_HOUSE_CLOSED", function() AuctionWindow:Closed() end)
    ns.RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
        if AuctionWindow.waiting then
            AuctionWindow.waiting = false
            AuctionWindow:Update()
        end
    end)
end
