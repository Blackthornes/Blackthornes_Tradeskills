-- Blackthornes Tradeskills -- UI/AuctionTab.lua
-- A Tradeskills tab under the auction house, beside Buy, Sell and Auctions.
--
-- Asked 2026-10-13: the sell list and the Scan bar sat off to the side of the
-- auction house, "maybe my problem is how it sits off to the side. Could we
-- add our own tab below the blizzard AH UI instead". So, unless Settings says
-- "Beside it", the auction house opens looking just as the game draws it,
-- with one more tab in its row. Clicking that tab lays the sell list over
-- the auction house's own page, the same size, with Scan and Post Crafted at
-- its foot; clicking Buy, Sell or Auctions puts the game's page back.
--
-- Nothing of Blizzard's is changed. The tab is our own button placed beside
-- theirs by its corner (never added to their tab list, which would taint the
-- auction house's buying and posting), the page is our own frame drawn over
-- theirs, and their tab clicks are only listened to, through HookScript,
-- which runs after the game's own script.

local _, ns = ...

local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local AuctionTab = ns.NewModule("AuctionTab")

-- How far in from the auction window's edges the page sits: under its title
-- bar, inside its rim. In the window's own units.
AuctionTab.PAGE_INSET = { left = 4, right = 4, top = 24, bottom = 4 }

-- The page sits this far above the auction window's own frames, so their
-- lists and buttons are never drawn over it.
local PAGE_LEVEL_ABOVE = 100

-- The game's auction tabs, last first: the tab is placed past the last one
-- found. Retail's auction house keeps them in AuctionHouseFrame.Tabs too.
local BLIZZARD_TAB_NAMES = {
    "AuctionHouseFrameAuctionsTab", "AuctionHouseFrameSellTab", "AuctionHouseFrameBuyTab",
    "AuctionFrameTab3", "AuctionFrameTab2", "AuctionFrameTab1",
}

local TAB_KEY = "tradeskills"

--- The layout picked in Settings: "tab" (the default) or "side", the sell
--- list docked beside the auction house as it was before.
function AuctionTab.Layout()
    local value = ns.Config and ns.Config:Get("auctionLayout")
    return value == "side" and "side" or "tab"
end

function AuctionTab.On()
    return AuctionTab.Layout() == "tab"
end

local function IsFrame(value)
    return type(value) == "table" and type(value.GetObjectType) == "function"
end

--- The game's tabs under the auction window, in their order.
function AuctionTab.BlizzardTabs(auctionFrame)
    local tabs = {}

    local ok, list = pcall(function() return auctionFrame and auctionFrame.Tabs end)
    if ok and type(list) == "table" then
        for _, tab in ipairs(list) do
            if IsFrame(tab) then tabs[#tabs + 1] = tab end
        end
    end

    if #tabs == 0 then
        for index = #BLIZZARD_TAB_NAMES, 1, -1 do
            local tab = _G[BLIZZARD_TAB_NAMES[index]]
            if IsFrame(tab) then tabs[#tabs + 1] = tab end
        end
    end

    return tabs
end

--- The game's tab furthest right, the one ours goes beside. Measured, since
--- a client may lay them out in another order than their names say.
function AuctionTab.LastBlizzardTab(tabs)
    local best, bestRight
    for _, tab in ipairs(tabs) do
        local shown = true
        if type(tab.IsShown) == "function" then
            local ok, isShown = pcall(tab.IsShown, tab)
            shown = not ok or isShown ~= false
        end
        if shown then
            local ok, right = pcall(tab.GetRight, tab)
            right = ok and type(right) == "number" and right or nil
            if not best or (right and (not bestRight or right > bestRight)) then
                best, bestRight = tab, right
            end
        end
    end
    return best
end

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

function AuctionTab:BuildTab()
    if self.strip then return self.strip end

    local Widgets = ns.Widgets
    local strip = Widgets.CreateTabStrip(UIParent, {
        { key = TAB_KEY, text = L["Tradeskills"] },
    }, function()
        AuctionTab:Toggle()
    end, { hanging = true })
    strip:Hide()

    local button = strip.tabs[1]
    if button then
        button:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Blackthornes Tradeskills")
            GameTooltip:AddLine(L["Your sell list and shopping list, with Scan and Post Crafted. Click Buy, Sell or Auctions to go back."], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    self.strip = strip
    return strip
end

--- Light our tab, or put it out, without its gold line staying behind.
function AuctionTab:MarkTab(on)
    local strip = self.strip
    if not strip then return end

    strip:Select(on and TAB_KEY or nil)
    if not on then
        if strip.line then strip.line:Hide() end
        if strip.lineGlow then strip.lineGlow:Hide() end
        strip.lineX, strip.lineWidth = nil, nil
    end
end

--- Listen to the game's own tabs, once each: a click on any of them puts
--- the game's page back.
function AuctionTab:WatchBlizzardTabs(tabs)
    self.watched = self.watched or {}
    for _, tab in ipairs(tabs) do
        if not self.watched[tab] and type(tab.HookScript) == "function" then
            local ok = pcall(tab.HookScript, tab, "OnClick", function() AuctionTab:Close() end)
            if ok then self.watched[tab] = true end
        end
    end
end

--- Put the tab in the auction window's tab row, past the game's own.
function AuctionTab:PlaceTab(auctionFrame)
    local strip = self:BuildTab()
    local tabs = AuctionTab.BlizzardTabs(auctionFrame)
    local last = AuctionTab.LastBlizzardTab(tabs)

    strip:ClearAllPoints()
    if last then
        strip:SetPoint("TOPLEFT", last, "TOPRIGHT", 4, 0)
    else
        -- No tabs to stand beside: under the window's bottom right corner.
        strip:SetPoint("TOPRIGHT", auctionFrame, "BOTTOMRIGHT", -24, 2)
    end

    -- In the window's layer, a little above it, so the window's own frames
    -- never cover the tab and other windows still do.
    local okStrata, strata = pcall(auctionFrame.GetFrameStrata, auctionFrame)
    if okStrata and type(strata) == "string" then strip:SetFrameStrata(strata) end
    local okLevel, level = pcall(auctionFrame.GetFrameLevel, auctionFrame)
    if okLevel and type(level) == "number" then strip:SetFrameLevel(level + 10) end

    self:WatchBlizzardTabs(tabs)
    return strip
end

--------------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------------

--- The auction house opened (UI:AttachToAuctionHouse): show the tab, with
--- the game's page showing, as the game opens it.
function AuctionTab:Attach(auctionFrame)
    self.auctionFrame = auctionFrame
    self.open = false

    local strip = self:PlaceTab(auctionFrame)
    self:MarkTab(false)
    strip:Show()

    if ns.UI and ns.UI.auctionBar then ns.UI.auctionBar:Hide() end
    if ns.PostPanel then ns.PostPanel:Hide() end
end

--- The auction house closed, or the layout went back to "Beside it".
function AuctionTab:Detach()
    self:Close()
    self.auctionFrame = nil
    if self.strip then self.strip:Hide() end
end

function AuctionTab:IsOpen()
    return self.open == true
end

function AuctionTab:Toggle()
    if self.open then self:Close() else self:Open() end
end

--- Lay the sell list over the auction house's page.
function AuctionTab:Open()
    local auctionFrame = self.auctionFrame or (ns.UI and ns.UI:FindAuctionFrame())
    if not auctionFrame or not ns.PostPanel then return end

    self.open = true
    self:MarkTab(true)

    local page = ns.PostPanel:ShowInPage(auctionFrame, AuctionTab.PAGE_INSET, PAGE_LEVEL_ABOVE)
    if page and ns.UI and ns.UI.PlaceAuctionBarIn then ns.UI:PlaceAuctionBarIn(page) end
end

--- Put the game's page back. Safe to call when nothing is open.
function AuctionTab:Close()
    if not self.open then return end
    self.open = false
    self:MarkTab(false)

    if ns.PostPanel then ns.PostPanel:LeavePage() end
    if ns.UI and ns.UI.auctionBar then ns.UI.auctionBar:Hide() end
end

--- Settings changed the layout. With the auction house open, it changes at
--- once: the docked panels come back, or the tab takes their place.
function AuctionTab:SetLayout(value)
    if ns.Config then ns.Config:Set("auctionLayout", value == "side" and "side" or "tab") end

    if not (ns.Scanner and ns.Scanner.isAuctionHouseOpen) then return end

    self:Detach()
    if ns.UI and ns.UI.AttachToAuctionHouse then ns.UI:AttachToAuctionHouse() end
end
