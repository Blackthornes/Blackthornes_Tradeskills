-- The Tradeskills tab under the auction house (UI/AuctionTab.lua), outside WoW.
--
-- What must hold:
--   1. The tab is the default; "side" is the way back to the docked panels.
--   2. The tab goes past the game's tab furthest right, and only listens to
--      the game's tabs: a click on any of them puts the game's page back.
--   3. The auction house opens with the game's page showing: the bar and the
--      sell list stay hidden until our tab is clicked, and then the list is
--      laid over the auction window with the bar at its foot.
--   4. A search, or the auction house closing, puts the game's page back.
--   5. Changing the layout with the auction house shut only saves it.

-- Tests share one Lua state, so every global replaced here is put back.
local GLOBALS = { "UIParent", "GameTooltip", "AuctionHouseFrameBuyTab", "AuctionHouseFrameSellTab",
    "AuctionHouseFrameAuctionsTab" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local passed, failed = 0, 0
local function check(label, got, want)
  local ok = got == want
  if ok then passed = passed + 1 else failed = failed + 1 end
  print(string.format("  %-60s %s", label, ok and "ok" or
    ("WRONG, got " .. tostring(got) .. ", wanted " .. tostring(want))))
end

local function Frame(right)
  local f = { shown = true, scripts = {}, hooks = {} }
  function f:GetObjectType() return "Button" end
  function f:IsShown() return self.shown end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:GetRight() return right end
  function f:ClearAllPoints() self.points = {} end
  function f:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
  function f:SetFrameStrata(s) self.strata = s end
  function f:GetFrameStrata() return "HIGH" end
  function f:SetFrameLevel(l) self.level = l end
  function f:GetFrameLevel() return 5 end
  function f:HookScript(name, fn) self.hooks[name] = fn end
  function f:Click() if self.hooks.OnClick then self.hooks.OnClick(self) end end
  return f
end

local config = {}
local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Config = { Get = function(_, key) return config[key] end, Set = function(_, key, value) config[key] = value end }

local strip
ns.Widgets = {
  CreateTabStrip = function(_, tabs, onSelect)
    strip = Frame(0)
    strip.shown = true
    strip.tabs = { Frame(0) }
    strip.onSelect = onSelect
    function strip:Select(key) self.selected = key end
    return strip
  end,
}

local calls = {}
local bar = Frame(0)
local page = Frame(0)
ns.PostPanel = {
  Hide = function() calls.postHide = (calls.postHide or 0) + 1 end,
  ShowInPage = function(_, ah, inset) calls.inPage = ah; calls.inset = inset; return page end,
  LeavePage = function() calls.leave = (calls.leave or 0) + 1 end,
}
ns.Scanner = { isAuctionHouseOpen = false }
ns.UI = {
  auctionBar = bar,
  FindAuctionFrame = function() return nil end,
  PlaceAuctionBarIn = function(_, where) calls.barIn = where end,
  AttachToAuctionHouse = function() calls.attachAH = (calls.attachAH or 0) + 1 end,
}

UIParent = Frame(0)
GameTooltip = Frame(0)

local chunk = assert(loadfile(lfs_cwd .. "/UI/AuctionTab.lua"))
chunk("Blackthornes_TS", ns)
local AuctionTab = ns.AuctionTab

print("")

-- 1
check("no setting yet: the tab", AuctionTab.Layout(), "tab")
config.auctionLayout = "side"
check("Beside it", AuctionTab.Layout(), "side")
config.auctionLayout = "nonsense"
check("anything else: the tab", AuctionTab.On(), true)
config.auctionLayout = nil

-- 2
local buy, sell, auctions = Frame(100), Frame(200), Frame(300)
local ah = Frame(800)
ah.Tabs = { buy, sell, auctions }
check("past the tab furthest right", AuctionTab.LastBlizzardTab(AuctionTab.BlizzardTabs(ah)), auctions)

AuctionHouseFrameBuyTab, AuctionHouseFrameSellTab, AuctionHouseFrameAuctionsTab = buy, sell, auctions
local bare = Frame(800)
check("found by name when the window has no Tabs list", #AuctionTab.BlizzardTabs(bare), 3)

-- 3
bar.shown = true
AuctionTab:Attach(ah)
check("the tab shows", strip.shown, true)
check("anchored beside the Auctions tab", strip.points[1][2], auctions)
check("the bar waits for the click", bar.shown, false)
check("the docked sell list is not shown", calls.postHide, 1)
check("nothing open yet", AuctionTab:IsOpen(), false)
check("the game's tabs are listened to", buy.hooks.OnClick ~= nil and auctions.hooks.OnClick ~= nil, true)

strip.onSelect("tradeskills")
check("our tab opens the page", AuctionTab:IsOpen(), true)
check("laid over the auction window", calls.inPage, ah)
check("under its title bar", calls.inset.top > 0, true)
check("the bar goes in the page", calls.barIn, page)
check("our tab lit", strip.selected, "tradeskills")

sell:Click()
check("Blizzard's Sell tab puts the game's page back", AuctionTab:IsOpen(), false)
check("the list leaves the page", calls.leave, 1)
check("our tab put out", strip.selected, nil)

-- 4
AuctionTab:Open()
AuctionTab:Close()
check("closing twice leaves the page once more only", calls.leave, 2)
AuctionTab:Close()
check("and a close with nothing open does nothing", calls.leave, 2)

AuctionTab:Open()
AuctionTab:Detach()
check("the auction house closing hides the tab", strip.shown, false)
check("and the page", AuctionTab:IsOpen(), false)

-- 5
AuctionTab:SetLayout("side")
check("saved", config.auctionLayout, "side")
check("auction house shut: nothing re-attached", calls.attachAH, nil)
ns.Scanner.isAuctionHouseOpen = true
AuctionTab:SetLayout("tab")
check("open: re-attached at once", calls.attachAH, 1)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

print("")
if failed > 0 then
  error(string.format("FAIL -- %d of %d auction tab checks wrong", failed, passed + failed))
end
print(string.format("PASS -- the Tradeskills tab under the auction house (%d checks)", passed))
print("")
