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
ns.UI = { FindAuctionFrame = function() return game end }
ns.Theme = { Fill = function() end, Recess = function() end, TextWidth = function() return 120 end }
local dressed, backClick
ns.Titanforged = { Dress = function(_, _, opts) dressed = opts end }
ns.Widgets = {
    CreateButton = function(_, _, onClick) backClick = onClick; return Frame() end,
    CreateTabStrip = function() return Frame() end,
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

dressed.close()
check("the close gem closes the auction house the game's way", closed == 1)
check("our window waits for the game to say it closed", AW:IsShown())
events.AUCTION_HOUSE_CLOSED()
check("closed: the game's window is back as it was", game.alpha == 1 and game.mouse and row.mouse)
check("closed: our window is away", not AW:IsShown())

events.AUCTION_HOUSE_SHOW()
check("the next visit covers it again", game.alpha == 0 and AW:IsShown())
backClick()
check("Use The Game's Window brings the game's window back", game.alpha == 1 and game.mouse and row.mouse)
check("Use The Game's Window puts ours away", not AW:IsShown())
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
