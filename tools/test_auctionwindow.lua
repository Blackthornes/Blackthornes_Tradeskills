-- Our auction house window (UI/AuctionWindow.lua, UI/Veil.lua).
--
-- Off, nothing is touched. On, the game's window goes see-through with the
-- mouse off and ours shows over it; "Use The Game's Window" and the closed
-- event put the game's window back as it was; the close gem closes the
-- auction house the game's way. Hide, Show and SetParent are never called
-- on the game's frame.

local failures = 0
local function check(name, ok)
    if ok then print("  ok   " .. name) else failures = failures + 1; print("  FAIL " .. name) end
end

-- A frame that keeps what the window and the veil read back.
local function Frame(strict)
    local f = { shown = false, alpha = 1, mouse = false, children = {}, calls = {} }
    function f:GetObjectType() return "Frame" end
    function f:Show() self.calls.Show = true; self.shown = true end
    function f:Hide() self.calls.Hide = true; self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetParent() self.calls.SetParent = true end
    function f:SetAlpha(a) self.alpha = a end
    function f:GetAlpha() return self.alpha end
    function f:EnableMouse(on) self.mouse = on and true or false end
    function f:IsMouseEnabled() return self.mouse end
    function f:IsMouseClickEnabled() return self.mouse end
    function f:IsMouseMotionEnabled() return self.mouse end
    function f:SetMouseClickEnabled(on) self.mouse = on and true or false end
    function f:SetMouseMotionEnabled() end
    function f:IsProtected() return false end
    function f:GetChildren() return (table.unpack or unpack)(self.children) end
    function f:GetWidth() return 800 end
    function f:SetAllPoints(to) self.over = to end
    function f:SetShown(on) self.shown = on and true or false end
    if not strict then
        for _, m in ipairs({ "SetFrameStrata", "ClearAllPoints", "SetPoint", "SetWidth",
            "SetHeight", "SetSize", "Select", "SetRoom", "SetFrameLevel" }) do
            f[m] = function() end
        end
    end
    return f
end

local game = Frame(true)
game.shown = true
game.mouse = true
local row = Frame(true)
row.mouse = true
game.children = { row }

local events, closed, settings = {}, 0, {}
_G.UIParent = Frame()
_G.CreateFrame = function() return Frame() end
_G.InCombatLockdown = function() return false end
_G.C_Timer = { After = function() end }
_G.C_AuctionHouse = { CloseAuctionHouse = function() closed = closed + 1 end }

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterEvent = function(_, event, fn) events[event] = fn end
ns.L = setmetatable({}, { __index = function(_, key) return key end })
ns.Config = { Get = function(_, key) return settings[key] end }
-- The main window's own pages, which our window borrows for a tab.
local content, attached = Frame(), 0
local function Page()
    local page = Frame()
    function page:SetParent(to) self.parent = to end
    page.parent = content
    return page
end
ns.UI = {
    FindAuctionFrame = function() return game end,
    window = Frame(), content = content, activeTab = "queue",
    tabs = { deals = { container = Page() }, settings = { container = Page() } },
    AttachToAuctionHouse = function() attached = attached + 1 end,
}
-- The drawer, as far as our window asks it.
local snipe = false
local drawer = { calls = {} }
ns.PostPanel = {
    ShowsSnipe = function() return snipe end,
    IntoOwn = function(self, container, view)
        self.inOwn = true; drawer.container = container; drawer.view = view
    end,
    OwnAway = function() drawer.view = nil; drawer.calls.away = (drawer.calls.away or 0) + 1 end,
    StepAside = function() drawer.calls.aside = (drawer.calls.aside or 0) + 1 end,
    OutOfOwn = function(self) self.inOwn = false; drawer.view = nil; drawer.calls.out = (drawer.calls.out or 0) + 1 end,
}
ns.Theme = { Fill = function() end, Recess = function() end, TextWidth = function() return 120 end }
local dressed, backClick
ns.Titanforged = { Dress = function(_, _, opts) dressed = opts end }
ns.Widgets = {
    CreateButton = function(_, _, onClick) backClick = onClick; return Frame() end,
    CreateTabStrip = function(_, defs, onSelect)
        local strip = Frame()
        strip.defs, strip.onSelect = defs, onSelect
        function strip:Select(key) self.picked = key end
        function strip:SetRoom(room) self.room = room end
        return strip
    end,
}

assert(loadfile("UI/Veil.lua"))("Blackthornes_TS", ns)
assert(loadfile("UI/AuctionWindow.lua"))("Blackthornes_TS", ns)
local AW = ns.AuctionWindow
AW:OnEnable()

print("")
print("our auction house window")

events.AUCTION_HOUSE_SHOW()
check("off: the game's window is left alone", game.alpha == 1 and game.mouse and row.mouse)
check("off: our window is never built", AW.frame == nil)
events.AUCTION_HOUSE_CLOSED()

settings.ownAuctionHouse = true
events.AUCTION_HOUSE_SHOW()
check("on: the game's window is see-through", game.alpha == 0)
check("on: the game's window and its rows take no mouse", not game.mouse and not row.mouse)
check("on: our window shows over it", AW:IsShown() and AW.frame.over == game)
check("on: our window takes the mouse", AW.frame.mouse == true)
check("the plate says Auction House", dressed and dressed.title == "Auction House")

-- The tabs
local strip = AW.frame.strip
local keys = {}
for i, def in ipairs(strip.defs) do keys[i] = def.key end
check("the tabs are Browse, Sell, My Auctions, Deals, then Settings on the right",
    table.concat(keys, " ") == "browse sell auctions deals settings" and strip.defs[5].right == true)
check("a visit starts on Browse", AW.tab == "browse" and strip.picked == "browse" and AW.frame.well.shown == true)
check("no drawer and no one window beside the auction house", AW:HoldsDrawer() == true)

strip.onSelect("sell")
check("Sell lays the drawer's Sell list in our window",
    drawer.view == "sell" and drawer.container == AW.frame.host and AW.frame.host.shown == true
    and AW.frame.well.shown == false)
strip.onSelect("auctions")
check("My Auctions is the drawer's own list", drawer.view == "auctions" and strip.picked == "auctions")
strip.onSelect("deals")
local deals = ns.UI.tabs.deals.container
check("Deals borrows the main window's page", deals.parent == AW.frame.host and deals.shown == true)
check("and the drawer steps out of the way", drawer.view == nil)
strip.onSelect("settings")
check("Settings gives Deals back and borrows its own page",
    deals.parent == content and deals.shown == false and ns.UI.tabs.settings.container.parent == AW.frame.host)
strip.onSelect("snipe")
check("Snipe unticked falls back to Browse", AW.tab == "browse" and strip.picked == "browse")
check("and the borrowed page went home", ns.UI.tabs.settings.container.parent == content)

snipe = true
AW:Update()
keys = {}
for i, def in ipairs(AW.frame.strip.defs) do keys[i] = def.key end
check("Snipe ticked adds its tab before Settings",
    table.concat(keys, " ") == "browse sell auctions deals snipe settings" and strip.shown == false)
AW.frame.strip.onSelect("snipe")
check("and it shows the drawer's Snipe list", drawer.view == "snipe" and AW.tab == "snipe")
snipe = false
AW:Update()
check("unticked while it shows, back to Browse", AW.tab == "browse" and AW.frame.strip == strip)
strip.onSelect("deals")

dressed.close()
check("the close gem closes the auction house the game's way", closed == 1)
check("our window waits for the game to say it closed", AW:IsShown())
events.AUCTION_HOUSE_CLOSED()
check("closed: the game's window is back as it was", game.alpha == 1 and game.mouse and row.mouse)
check("closed: our window is away", not AW:IsShown())
check("closed: the drawer and the borrowed page are their own again",
    (drawer.calls.out or 0) == 1 and deals.parent == content and ns.PostPanel.inOwn == false)
check("closed: nothing is asked to open beside the game's window", attached == 0)

events.AUCTION_HOUSE_SHOW()
check("the next visit covers it again", game.alpha == 0 and AW:IsShown())
backClick()
check("Use The Game's Window brings the game's window back", game.alpha == 1 and game.mouse and row.mouse)
check("Use The Game's Window puts ours away", not AW:IsShown())
check("the next visit starts on Browse again", AW.tab == "browse")
check("the game's window gets its drawer back beside it",
    attached == 1 and AW:HoldsDrawer() == false and (drawer.calls.out or 0) == 2)
AW:Update()
check("it stays the game's window for the rest of the visit", game.alpha == 1 and not AW:IsShown())
events.AUCTION_HOUSE_CLOSED()
events.AUCTION_HOUSE_SHOW()
check("a new visit opens ours again", game.alpha == 0 and AW:IsShown())

settings.ownAuctionHouse = false
AW:Update()
check("unticked at the auction house, the game's window comes back at once",
    game.alpha == 1 and game.mouse and not AW:IsShown())
events.AUCTION_HOUSE_CLOSED()

check("Hide, Show and SetParent are never called on the game's window",
    not game.calls.Hide and not game.calls.Show and not game.calls.SetParent
    and not row.calls.Hide and not row.calls.Show and not row.calls.SetParent)

print("")
if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("all checks passed")
