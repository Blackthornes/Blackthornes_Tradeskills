-- The mouse wheel at the auction house (2026-10-16).
--
-- What must hold:
--   1. Off unless ticked: nothing is bound, whatever the drawer does.
--   2. Ticked, the wheel is bound only while the drawer shows, and given
--      back when it goes.
--   3. The tab picks the job: on Sell either turn lists, on Auctions
--      either turn cancels the next undercut, other tabs leave the wheel be.
--   4. A flick (notches close together) does one thing, not several.
--   5. In a fight the bindings wait for the fight to end.
--   6. A press and its release do one thing.
--   7. Something else binding the wheel later doesn't take it for good: it
--      is taken back on the next look (drawer tick, binding change, ...).
--   8. A drawer shown inside a hidden window doesn't hold the wheel.
--   9. While the wheel is ours, drawer lists with nothing more to show let
--      the turn through; when it goes back they take it again.

local GLOBALS = { "CreateFrame", "UIParent", "GetTime", "InCombatLockdown",
    "SetOverrideBindingClick", "ClearOverrideBindings", "GetBindingAction" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

local named = {}
local function Frame(name)
    local frame = { scripts = {}, hooks = {} }
    function frame:SetScript(which, fn) self.scripts[which] = fn end
    function frame:HookScript(which, fn) self.hooks[which] = fn end
    for _, method in ipairs({ "SetSize", "SetAlpha", "EnableMouse", "RegisterForClicks" }) do
        frame[method] = noop
    end
    if name then named[name] = frame end
    return frame
end
CreateFrame = function(_, name) return Frame(name) end
UIParent = {}

local clock = 100
GetTime = function() return clock end
local fighting = false
InCombatLockdown = function() return fighting end

local bindings = {}
SetOverrideBindingClick = function(_, _, key, button) bindings[key] = button end
ClearOverrideBindings = function() bindings = {} end
-- What the game would really do with a key: another addon can take it.
local stolen = {}
GetBindingAction = function(key)
    if stolen[key] then return stolen[key] end
    if bindings[key] then return "CLICK " .. bindings[key] .. ":LeftButton" end
    return ""
end

local handlers = {}
local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterEvent = function(_, event, fn) handlers[event] = fn; return true end

local settings = {}
ns.Config = { Get = function(_, k) return settings[k] end, Set = function(_, k, v) settings[k] = v end }

local shown = false
local visible = true
local listed, cancelled = 0, 0
local passed = nil
ns.PostPanel = {
    view = "sell",
    frame = { IsVisible = function() return shown and visible end },
    list = { WheelPass = function(_, on) passed = on end },
    IsShown = function() return shown end,
    ListNext = function() listed = listed + 1 end,
}
ns.MyAuctions = { CancelNext = function() cancelled = cancelled + 1 end }

assert(loadfile(lfs_cwd .. "/UI/AuctionWheel.lua"))("Blackthornes_TS", ns)
local Wheel = ns.AuctionWheel

local drawer = Frame()
local function Show() shown = true; drawer.hooks.OnShow() end
local function Hide() shown = false; drawer.hooks.OnHide() end
Wheel:Watch(drawer)

-- 1. Off unless ticked.
Show()
assert(next(bindings) == nil, "nothing is bound while the setting is off")
Hide()

-- 2. Ticked: bound only while the drawer shows.
settings.mouseWheelListing = true
Wheel:Update()
assert(next(bindings) == nil, "nothing is bound away from the auction house")
Show()
assert(bindings.MOUSEWHEELUP == Wheel.LIST_BUTTON, "wheel up is bound to the list button")
assert(bindings.MOUSEWHEELDOWN == Wheel.CANCEL_BUTTON, "wheel down is bound to the cancel button")

-- 3. The tab showing picks the job, through the named buttons a binding
-- clicks. On Sell either turn lists; nothing cancels there.
named[Wheel.LIST_BUTTON].scripts.OnClick(nil, "LeftButton", true)
assert(listed == 1, "wheel up lists the next stack on Sell")
clock = clock + 1
named[Wheel.CANCEL_BUTTON].scripts.OnClick(nil, "LeftButton", true)
assert(listed == 2 and cancelled == 0, "wheel down lists on Sell too, and never cancels there")
listed = 1
-- On Auctions either turn cancels the next undercut one; nothing lists.
ns.PostPanel.view = "auctions"
clock = clock + 1
named[Wheel.CANCEL_BUTTON].scripts.OnClick(nil, "LeftButton", true)
clock = clock + 1
named[Wheel.LIST_BUTTON].scripts.OnClick(nil, "LeftButton", true)
assert(cancelled == 2 and listed == 1, "on Auctions both turns cancel and nothing lists")
-- On a tab with no wheel job, the wheel is the player's.
ns.PostPanel.view = "buy"
Wheel:Update()
assert(next(bindings) == nil, "the wheel isn't taken on Buy")
clock = clock + 1
assert(Wheel:List() == false and listed == 1, "nothing lists from Buy")
ns.PostPanel.view = "sell"
Wheel:Update()
assert(bindings.MOUSEWHEELUP == Wheel.LIST_BUTTON, "taken again back on Sell")

-- 6. The release of the same press does nothing more.
clock = clock + 1
named[Wheel.LIST_BUTTON].scripts.OnClick(nil, "LeftButton", true)
named[Wheel.LIST_BUTTON].scripts.OnClick(nil, "LeftButton", false)
assert(listed == 2, "a press and its release list once")

-- 4. A flick: notches close together do one thing.
clock = clock + 1
for _ = 1, 5 do
    named[Wheel.LIST_BUTTON].scripts.OnClick(nil, "LeftButton", true)
    clock = clock + 0.05
end
assert(listed == 3, "a flick lists one stack, got " .. listed)

clock = clock + 1
named[Wheel.LIST_BUTTON].scripts.OnClick(nil, "LeftButton", true)
assert(listed == 4, "Sell lists again")

-- 2. The drawer goes: the wheel is given back, and a stray click does nothing.
Hide()
assert(next(bindings) == nil, "the wheel is given back when the drawer goes")
clock = clock + 1
assert(Wheel:List() == false and listed == 4, "nothing lists away from the auction house")

-- Unticked while open: given back at once.
Show()
assert(bindings.MOUSEWHEELUP, "bound again on the next visit")
settings.mouseWheelListing = false
Wheel:Update()
assert(next(bindings) == nil, "unticking gives the wheel back")
settings.mouseWheelListing = true
Hide()

-- 5. In a fight the change waits for the fight to end.
fighting = true
Show()
assert(next(bindings) == nil, "bindings wait out a fight")
fighting = false
handlers.PLAYER_REGEN_ENABLED()
assert(bindings.MOUSEWHEELUP, "bound once the fight ends")
Hide()

-- 7. Another addon binds the wheel after we did: taken back on the next look.
Show()
assert(bindings.MOUSEWHEELUP and Wheel:Holds(), "ours to start")
stolen.MOUSEWHEELUP = "CAMERAZOOMIN"
assert(not Wheel:Holds(), "the game would send wheel up elsewhere now")
local setAgain = 0
local realSet = SetOverrideBindingClick
SetOverrideBindingClick = function(...) setAgain = setAgain + 1; realSet(...) end
drawer.hooks.OnUpdate(drawer, 0.4)
assert(setAgain == 0, "no look before CHECK_EVERY")
-- The other addon lets go, but ours must be the newest again.
stolen.MOUSEWHEELUP = nil
bindings = {}
drawer.hooks.OnUpdate(drawer, 0.7)
assert(setAgain == 2 and bindings.MOUSEWHEELUP == Wheel.LIST_BUTTON, "the drawer's tick takes the wheel back")
-- Held: a tick binds nothing again.
drawer.hooks.OnUpdate(drawer, 2)
assert(setAgain == 2, "a tick leaves a held wheel alone")
-- A binding change taking it is noticed at once.
bindings = {}
handlers.UPDATE_BINDINGS()
assert(bindings.MOUSEWHEELDOWN == Wheel.CANCEL_BUTTON, "a binding change takes it back")
-- In a fight it waits, then comes back.
bindings = {}
fighting = true
drawer.hooks.OnUpdate(drawer, 2)
assert(next(bindings) == nil and Wheel.waiting, "a fight makes it wait")
fighting = false
handlers.PLAYER_REGEN_ENABLED()
assert(bindings.MOUSEWHEELUP, "taken back after the fight")
SetOverrideBindingClick = realSet

-- 9. Lists let a turn through only while the wheel is ours.
assert(passed == true, "drawer lists let the wheel through while it is ours")

-- 8. The drawer still "shown" but its window hidden: the wheel goes back.
visible = false
drawer.hooks.OnHide()
assert(next(bindings) == nil, "a drawer out of sight gives the wheel back")
assert(passed == false, "lists take the wheel again once it is given back")
visible = true
drawer.hooks.OnShow()
assert(bindings.MOUSEWHEELUP, "seen again, bound again")
Hide()

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end
print("test_auctionwheel: all passed")
