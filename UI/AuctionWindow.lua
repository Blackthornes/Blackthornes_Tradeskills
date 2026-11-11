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
-- The window, its veil, its tabs and its way out are here. Browse is
-- UI/AuctionBrowse.lua with its buy panel UI/AuctionBuy.lua. Sell, My
-- Auctions and Snipe are the drawer's own lists laid into this window
-- (PostPanel:IntoOwn); Deals and Settings are the main window's own pages,
-- borrowed while their tab shows and given back after. So while this window
-- is up nothing opens beside the auction house: no drawer and no one window
-- (HoldsDrawer, asked by UI/PostPanel.lua and UI/Main.lua).

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

-- The tabs, in order. Sell, My Auctions and Snipe are views of the drawer;
-- Deals and Settings are pages of the main window. Settings is always last.
local TABS = {
    { key = "browse", text = L["Browse"] },
    { key = "sell", text = L["Sell"], view = "sell" },
    { key = "auctions", text = L["My Auctions"], view = "auctions" },
    { key = "deals", text = L["Deals"], page = "deals" },
    { key = "snipe", text = L["Snipe"], view = "snipe" },
    { key = "settings", text = L["Settings"], page = "settings", right = true },
}
local BY_KEY = {}
for _, tab in ipairs(TABS) do BY_KEY[tab.key] = tab end

--- The Snipe tab shows only while its setting is ticked, as in the drawer.
local function ShowsSnipe()
    local PostPanel = ns.PostPanel
    if not (PostPanel and PostPanel.ShowsSnipe) then return false end
    local ok, shows = pcall(PostPanel.ShowsSnipe)
    return ok and shows == true
end

--- True while this window stands in for the game's: the drawer's lists are
--- its tabs then, so no drawer and no one window open beside the auction
--- house. It does not wait for the open event, since the drawer may hear
--- that event first.
function AuctionWindow:HoldsDrawer()
    return Setting() and not self.gameWindow
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

    -- The well the Browse list sits in.
    local well = CreateFrame("Frame", nil, frame)
    well:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -60)
    well:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    Theme.Recess(well)
    frame.well = well
    -- The Browse tab draws itself into the well (UI/AuctionBrowse.lua).
    if ns.AuctionBrowse then ns.AuctionBrowse:Build(well) end

    -- Where the other tabs lie: the drawer's lists and the borrowed pages.
    -- A little wider than the well, so Settings' two columns fit.
    local host = CreateFrame("Frame", nil, frame)
    host:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -60)
    host:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 14)
    Theme.Recess(host)
    host:Hide()
    frame.host = host

    frame.strips = {}

    self.frame = frame
    return frame
end

--- The row of tabs, with Snipe only while its setting is ticked. The strip
--- cannot drop a tab, so there is one with Snipe and one without, each made
--- when first needed.
function AuctionWindow:Strip(room)
    local frame = self.frame
    if not frame then return nil end
    local withSnipe = ShowsSnipe()
    local strip = frame.strips[withSnipe]
    if not strip then
        local defs = {}
        for _, tab in ipairs(TABS) do
            if tab.key ~= "snipe" or withSnipe then
                defs[#defs + 1] = { key = tab.key, text = tab.text, right = tab.right }
            end
        end
        strip = Widgets.CreateTabStrip(frame, defs, function(key)
            AuctionWindow:SelectTab(key)
        end, { width = room or 800, hanging = true })
        strip:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", TAB_INSET, 0)
        frame.strips[withSnipe] = strip
    end
    local other = frame.strips[not withSnipe]
    if other then other:Hide() end
    strip:Show()
    if room and strip.SetRoom then strip:SetRoom(room) end
    frame.strip = strip
    return strip
end

--- Give a borrowed page back to the main window, where it was.
function AuctionWindow:GiveBack()
    local key = self.borrowed
    if not key then return end
    self.borrowed = nil
    local UI = ns.UI
    local tab = UI and UI.tabs and UI.tabs[key]
    local page = tab and tab.container
    if not (page and UI.content) then return end
    page:SetParent(UI.content)
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", 1, -1)
    page:SetPoint("BOTTOMRIGHT", -1, 1)
    page:SetShown(UI.activeTab == key)
end

--- Lay one of the main window's own pages (Deals, Settings) into our
--- window while its tab shows. Only our own frames are moved.
-- @return true when the page is in
function AuctionWindow:Borrow(key)
    local UI = ns.UI
    local frame = self.frame
    if not (UI and frame and frame.host) then return false end
    if not UI.window and UI.Build then pcall(UI.Build, UI) end
    local tab = UI.tabs and UI.tabs[key]
    local page = tab and tab.container
    if not page then return false end
    if self.borrowed ~= key then
        self:GiveBack()
        page:SetParent(frame.host)
        page:ClearAllPoints()
        page:SetAllPoints(frame.host)
        self.borrowed = key
    end
    page:Show()
    if tab.onShow then pcall(tab.onShow) end
    if tab.refresh then pcall(tab.refresh) end
    return true
end

--- Show one tab. A tab that cannot show (Snipe unticked, a page not there)
--- falls back to Browse.
function AuctionWindow:SelectTab(key)
    local frame = self.frame
    if not frame then return end
    local PostPanel = ns.PostPanel
    local tab = BY_KEY[key] or BY_KEY.browse
    if tab.key == "snipe" and not ShowsSnipe() then tab = BY_KEY.browse end
    if tab.view and not (PostPanel and PostPanel.IntoOwn) then tab = BY_KEY.browse end

    local paged = false
    if tab.page then
        paged = self:Borrow(tab.page)
        if not paged then tab = BY_KEY.browse end
    end
    if not paged then self:GiveBack() end

    self.tab = tab.key
    self.lent = true
    frame.well:SetShown(tab.key == "browse")
    frame.host:SetShown(tab.key ~= "browse")

    if PostPanel then
        if tab.view and PostPanel.IntoOwn then
            pcall(PostPanel.IntoOwn, PostPanel, frame.host, tab.view)
        elseif PostPanel.inOwn and PostPanel.OwnAway then
            pcall(PostPanel.OwnAway, PostPanel)
        elseif PostPanel.StepAside then
            -- Ticked in the middle of a visit: the drawer beside the
            -- game's window goes, and comes back as our tabs.
            pcall(PostPanel.StepAside, PostPanel)
        end
    end

    if frame.strip and frame.strip.Select then frame.strip:Select(tab.key) end
end

--- Everything lent to our window goes back where it lives: the drawer to
--- its own frame, a borrowed page to the main window.
function AuctionWindow:Release()
    self.lent = false
    self:GiveBack()
    local PostPanel = ns.PostPanel
    if PostPanel and PostPanel.OutOfOwn then pcall(PostPanel.OutOfOwn, PostPanel) end
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
        if self.lent then
            self:Release()
            -- The game's window for the rest of the visit: the drawer comes
            -- back beside it, as it always was.
            local UI = ns.UI
            if self.open and UI and UI.AttachToAuctionHouse then pcall(UI.AttachToAuctionHouse, UI) end
        end
        return
    end

    -- The game's window is not built yet: the looks after the event find it.
    if not game or not Veil then return end

    if Veil:Cover(game) == false then self.waiting = true end

    local frame = self:Build()
    frame:ClearAllPoints()
    frame:SetAllPoints(game)
    local room
    local ok, width = pcall(game.GetWidth, game)
    if ok and type(width) == "number" and width > 2 * TAB_INSET then room = width - 2 * TAB_INSET end
    local had = frame.strip
    local strip = self:Strip(room)

    if not frame:IsShown() then
        frame:Show()
        self:SelectTab(self.tab or "browse")
    elseif strip ~= had or (self.tab == "snipe" and not ShowsSnipe()) then
        -- Snipe was ticked or unticked while the window is up.
        self:SelectTab(self.tab or "browse")
    end
end

function AuctionWindow:Opened()
    self.open = true
    self.gameWindow = false
    self.visit = (self.visit or 0) + 1
    -- Every visit starts on Browse, as the game's window does.
    self.tab = "browse"
    self:Update()

    local visit = self.visit
    for index, seconds in ipairs(LOOK_AGAIN) do
        After(seconds, function()
            if not (AuctionWindow.open and AuctionWindow.visit == visit) then return end
            AuctionWindow:Update()
            -- The game's window never turned up, so ours has nothing to lie
            -- over: the drawer comes up as it always did, for this visit.
            if index == #LOOK_AGAIN and AuctionWindow:Wanted() and not AuctionWindow:IsShown() then
                AuctionWindow.gameWindow = true
                AuctionWindow:Update()
                local UI = ns.UI
                if UI and UI.AttachToAuctionHouse then pcall(UI.AttachToAuctionHouse, UI) end
            end
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
