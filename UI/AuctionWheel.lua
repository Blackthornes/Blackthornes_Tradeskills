-- The mouse wheel at the auction house (a player asked, the owner said
-- build it, 2026-10-16). With "Mouse Wheel" ticked (Settings > Auction
-- house, `mouseWheelListing`, off unless ticked, never rename it), while
-- the drawer is up, the wheel does the job of the tab showing (see below).
-- When the drawer goes, the wheel is the player's again.
--
-- How: the game asks for a real click or key press for each listing and
-- each cancel. A wheel turn bound to a button is one, so two named buttons
-- (never shown, never take the mouse) get the wheel through override
-- bindings, held by our own owner frame only while the drawer shows. A list
-- under the mouse still takes the wheel first, so scrolling still works;
-- a drawer list with nothing more to show lets the turn through.
-- Bindings can't change in a fight: the change waits for its end.
--
-- Kept working (the owner's report, 2026-11-07: "keeps breaking and stops
-- working randomly"): the wheel used to be bound once and then trusted.
-- Another addon or the game binding the wheel later took it away for good,
-- since nothing looked again until the drawer closed. Now the binding the
-- game would really use (`GetBindingAction(key, true)`) is checked as the
-- drawer opens, when bindings change, at the auction house, after a fight
-- and once every `CHECK_EVERY` seconds while the drawer shows, and taken
-- back when it isn't ours. The drawer counts only while it can be seen
-- (inside a hidden One Window it can't), and a view change re-checks.
--
-- Each tab gives the wheel one job (the owner, 2026-11-09: on Sell a turn
-- said nothing was undercut instead of listing). On Sell either turn lists
-- the next stack, on Auctions either turn cancels the next undercut one,
-- on Snipe wheel up buys. On the other tabs the wheel stays the player's.

local _, ns = ...

local AuctionWheel = ns.NewModule("AuctionWheel")

-- A flick of the wheel sends several notches at once: one action this far
-- apart, so a flick lists one stack, not five.
AuctionWheel.GAP = 0.35

AuctionWheel.LIST_BUTTON = "BlackthornesTSWheelList"
AuctionWheel.CANCEL_BUTTON = "BlackthornesTSWheelCancel"

-- How often the binding is looked at again while the drawer shows.
AuctionWheel.CHECK_EVERY = 1

-- What the game reports for each wheel key while it is ours.
AuctionWheel.ACTIONS = {
    MOUSEWHEELUP = "CLICK " .. AuctionWheel.LIST_BUTTON .. ":LeftButton",
    MOUSEWHEELDOWN = "CLICK " .. AuctionWheel.CANCEL_BUTTON .. ":LeftButton",
}

local function Now()
    return type(GetTime) == "function" and GetTime() or 0
end

local function InFight()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

--- Whether the setting is on.
function AuctionWheel:IsOn()
    return ns.Config ~= nil and ns.Config:Get("mouseWheelListing") == true
end

-- What the wheel does on each tab while "Mouse Wheel" is ticked.
AuctionWheel.JOBS = { sell = "list", auctions = "cancel" }

--- What a turn does on the tab showing: "list", "cancel", "buy" or nil.
function AuctionWheel:Job()
    local panel = ns.PostPanel
    if not panel then return nil end
    if panel.view == "snipe" then return "buy" end
    return self.JOBS[panel.view or "sell"]
end

--- Whether the wheel should be ours right now.
function AuctionWheel:Wanted()
    local panel = ns.PostPanel
    if not (panel ~= nil and panel.IsShown ~= nil and panel:IsShown() == true) then return false end
    -- Shown but inside a closed window (One Window hidden) is not on screen.
    local frame = panel.frame
    if frame and frame.IsVisible and frame:IsVisible() ~= true then return false end
    -- The Snipe view has its own switch: wheel up buys the best find.
    if panel.view == "snipe" then
        return ns.Config ~= nil and ns.Config:Get("snipeWheel") == true
            and ns.Config:Get("snipeTab") == true
    end
    return self:IsOn() and self:Job() ~= nil
end

-- A notch too soon after the last one does nothing.
function AuctionWheel:Ready()
    local now = Now()
    if self.lastAt and now - self.lastAt < self.GAP then return false end
    self.lastAt = now
    return true
end

-- Does the tab's job for one turn. Snipe buys on wheel up only.
function AuctionWheel:Turn(up)
    if not self:Wanted() or not self:Ready() then return false end
    local job = self:Job()
    if job == "buy" then
        if not up then return false end
        -- One notch, one buy click; a big buy still asks "Confirm".
        if ns.Snipe and ns.Snipe.BuyNext then ns.Snipe:BuyNext() end
        return true
    elseif job == "list" then
        ns.PostPanel:ListNext()
        return true
    elseif job == "cancel" then
        if not (ns.MyAuctions and ns.MyAuctions.CancelNext) then return false end
        ns.MyAuctions:CancelNext()
        return true
    end
    return false
end

--- Wheel up: the tab's job (lists on Sell, cancels on Auctions, buys on Snipe).
function AuctionWheel:List()
    return self:Turn(true)
end

--- Wheel down: the tab's job (lists on Sell, cancels on Auctions).
function AuctionWheel:Cancel()
    return self:Turn(false)
end

local function MakeButton(name, onClick)
    local button = CreateFrame("Button", name, UIParent)
    button:SetSize(1, 1)
    button:SetAlpha(0)
    button:EnableMouse(false)
    button:RegisterForClicks("AnyUp", "AnyDown")
    -- A binding clicks on the press and the release: act on one only.
    button:SetScript("OnClick", function(_, _, down)
        if down == false then return end
        onClick()
    end)
    return button
end

function AuctionWheel:Build()
    if self.owner then return end
    self.owner = CreateFrame("Frame", nil, UIParent)
    self.listButton = MakeButton(self.LIST_BUTTON, function() AuctionWheel:List() end)
    self.cancelButton = MakeButton(self.CANCEL_BUTTON, function() AuctionWheel:Cancel() end)
end

--- Whether the game would send both wheel turns to our buttons. Unknown
--- (no way to ask) counts as ours, so nothing is bound again and again.
function AuctionWheel:Holds()
    if type(GetBindingAction) ~= "function" then return true end
    for key, action in pairs(self.ACTIONS) do
        local ok, now = pcall(GetBindingAction, key, true)
        if ok and now ~= action then return false end
    end
    return true
end

-- Drawer lists let a turn through only while the wheel is ours.
function AuctionWheel:PassLists(on)
    local lists = {}
    local panel = ns.PostPanel
    if panel then
        lists[#lists + 1] = panel.list
        lists[#lists + 1] = panel.shoppingList
    end
    for _, name in ipairs({ "AuctionsView", "SnipeView", "FavorsView", "ShoppingListsView" }) do
        local view = ns[name]
        if view then lists[#lists + 1] = view.list end
    end
    for _, list in pairs(lists) do
        if type(list) == "table" and list.WheelPass then pcall(list.WheelPass, list, on) end
    end
end

--- Take the wheel or give it back, to match the setting and the drawer.
--- While it should be ours, also takes it back from anything that bound
--- the wheel since.
function AuctionWheel:Update()
    local want = self:Wanted()
    if want == (self.bound == true) and (not want or self:Holds()) then return end

    if InFight() then
        self.waiting = true
        return
    end
    self.waiting = false

    self:Build()
    if want then
        if type(SetOverrideBindingClick) ~= "function" then return end
        -- Cleared first, so setting them again makes ours the newest.
        if self.bound and type(ClearOverrideBindings) == "function" then pcall(ClearOverrideBindings, self.owner) end
        pcall(SetOverrideBindingClick, self.owner, true, "MOUSEWHEELUP", self.LIST_BUTTON, "LeftButton")
        pcall(SetOverrideBindingClick, self.owner, true, "MOUSEWHEELDOWN", self.CANCEL_BUTTON, "LeftButton")
        self.bound = true
    else
        if type(ClearOverrideBindings) == "function" then pcall(ClearOverrideBindings, self.owner) end
        self.bound = false
    end
    self:PassLists(self.bound)
end

-- A cheap look while the drawer shows: the drawer's OnUpdate runs only then.
function AuctionWheel:Tick(elapsed)
    self.sinceCheck = (self.sinceCheck or 0) + (tonumber(elapsed) or 0)
    if self.sinceCheck < self.CHECK_EVERY then return end
    self.sinceCheck = 0
    self:Update()
end

--- Follow the drawer: called once it is built.
function AuctionWheel:Watch(frame)
    if not frame or self.watching == frame then return end
    self.watching = frame
    frame:HookScript("OnShow", function() AuctionWheel:Update() end)
    frame:HookScript("OnHide", function() AuctionWheel:Update() end)
    frame:HookScript("OnUpdate", function(_, elapsed) AuctionWheel:Tick(elapsed) end)
    self:Update()
end

if ns.RegisterEvent then
    -- After a fight, and whenever something may have moved the wheel's
    -- binding or the drawer, look again.
    local function Again() AuctionWheel:Update() end
    ns.RegisterEvent(AuctionWheel, "PLAYER_REGEN_ENABLED", Again)
    ns.RegisterEvent(AuctionWheel, "UPDATE_BINDINGS", Again)
    ns.RegisterEvent(AuctionWheel, "AUCTION_HOUSE_SHOW", Again)
    ns.RegisterEvent(AuctionWheel, "PLAYER_ENTERING_WORLD", Again)
end
