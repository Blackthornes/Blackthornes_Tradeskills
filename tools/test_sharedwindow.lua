-- The one Blackthornes window (UI/SharedWindow.lua), outside WoW. The same
-- test in all five Blackthornes addons.
--
-- What must hold:
--   1. On unless unticked; a choice writes every save, and the newest wins.
--   2. Only an addon whose pages moved in (host) is hosted, and only while on.
--   3. The rail has a button for each addon, in order.
--   4. Picking an addon that moved in lays its pages in and lets the last
--      one go; one that has not opens its own window.
--   5. The pick, place and scale are kept in every save; closing lets the
--      pages go; unticking closes the window.
--   6. Docking: up when the game's auction house, mailbox, vendor or
--      trainer opens, it sits beside it with the rail as a row along the
--      top, the area the same size; moving it there keeps its own place;
--      when the game's window closes it goes back to its place and the
--      addon open before, and stays closed when it was closed before.
--   7. At the auction house, while Tradeskills shows, the row of addon
--      buttons is left out; another addon picked there brings it back.
--   8. Forever: PLAYER_INTERACTION_MANAGER_FRAME_HIDE undocks too, by the
--      client's Enum or the numbers kept for a client without one.
--   9. An open letter: docked at the mailbox, the window moves beside the
--      letter while it shows and back beside the mailbox when it closes;
--      watchers hear each dock, move and undock, and DockedFrame gives the
--      window only while it is docked.
--  10. Kept beside: while a game window is open, the window docks once the
--      game shows its window late, and is placed beside it again when the
--      game's window moves or this one changes width; nothing else moves it.
--  11. Closed by the player while a game window is open, it stays closed
--      when that window goes; only an addon's close on leaving (Close(true))
--      lets it go back to the addon open before.
--  12. Dragged while docked it keeps that spot by the game's window; a small
--      window keeps where it was dragged; Set Default puts every one back.
--  13. The free side: it docks on the right when that fits, on the left
--      when only that fits, and shrinks to the bigger gap when neither
--      does (a little only; with far too little room it keeps its size and
--      overlaps; once resized by hand it never shrinks); undocked it has
--      its own size.
--  15. Shelves: pieces in their first spot line up down the top shelf in
--      order, a dragged or hidden one takes no room, the ones after it are
--      laid again when one shows, hides or changes height, the right shelf
--      stands left of the game's quest list, and nothing moves in a fight.
--  16. The gear at the foot of the rail shows once an addon has the All
--      Addons page and opens it there, on the addon showing when it can.
--  17. A place's own addon (`prefer`): up on another addon as a vendor
--      opens, the window turns to Butler when it has moved in and wants
--      the vendor, and goes back to the addon open before as it closes,
--      every visit; Butler opening it first changes nothing; without
--      Butler, or with Butler not wanting it, it stays where it was.
--  14. Two game windows at once (the character sheet at a vendor, heard by
--      HookScript): it docks beside the newest and goes back beside the
--      other when that one closes.

local NAMES = { "CreateFrame", "UIParent", "C_Timer", "time", "BlackthornesWindow",
    "UISpecialFrames", "GetCursorPosition", "GetTime", "MailFrame", "OpenMailFrame", "MerchantFrame", "AuctionHouseFrame", "Enum", "CharacterFrame", "ContainerFrame1", "BlackthornesShelves", "ObjectiveTrackerFrame" }
local saved = {}
for _, name in ipairs(NAMES) do saved[name] = _G[name] end

local function Object()
    local o = { shown = true, scripts = {}, scale = 1, left = 100, top = 600 }
    function o:Show() self.shown = true end
    function o:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function o:IsShown() return self.shown end
    function o:SetScript(name, fn) self.scripts[name] = fn end
    function o:HookScript(name, fn)
        self.hooks = rawget(self, "hooks") or {}
        self.hooks[name] = self.hooks[name] or {}
        table.insert(self.hooks[name], fn)
    end
    function o:Fire(name)
        for _, fn in ipairs((rawget(self, "hooks") or {})[name] or {}) do fn(self) end
    end
    function o:SetText(text) self.text = text end
    function o:SetTexture(texture) self.texture = texture end
    function o:SetScale(scale) self.scale = scale end
    function o:GetScale() return self.scale end
    function o:GetLeft() return self.left end
    function o:GetTop() return self.top end
    function o:GetEffectiveScale() return 1 end
    function o:GetFrameLevel() return 1 end
    function o:IsMouseOver() return false end
    function o:CreateTexture() return Object() end
    function o:CreateFontString() return Object() end
    function o:SetSize(w, h) self.width, self.height = w, h end
    function o:SetWidth(w) self.width = w end
    function o:SetHeight(h) self.height = h end
    function o:GetWidth() return self.width or 0 end
    function o:GetHeight() return self.height or 0 end
    function o:GetRight() return self.right end
    function o:ClearAllPoints() self.point = nil end
    function o:SetPoint(...) self.point = { ... } end
    function o:GetPoint() if self.point then return unpack(self.point) end end
    return setmetatable(o, { __index = function() return function() end end })
end

CreateFrame = function() local f = Object(); f.shown = true; return f end
UIParent = Object()
C_Timer = nil
UISpecialFrames = {}
local clock = 1000
time = function() return clock end
BlackthornesWindow = nil
local now = 50
GetTime = function() return now end

local ns = {
    Theme = {
        Unpack = function() return 0, 0, 0, 1 end,
        Fill = function() end,
        Border = function() end,
        CreateLabel = function() return Object() end,
    },
}
local chunk = assert(loadfile(lfs_cwd .. "/UI/SharedWindow.lua"))
chunk("Blackthornes_Test", ns)
local SW = ns.SharedWindow
assert(SW, "SharedWindow loads")

local log = {}
local function Entry(key, order, db, hosted)
    local entry = {
        key = key, order = order, name = key, icon = "icon-" .. key,
        db = function() return db end,
        open = function() log[#log + 1] = "open " .. key end,
        settings = function() log[#log + 1] = "settings " .. key end,
    }
    if hosted then
        entry.host = {
            enter = function(area) assert(area, "enter gets the area"); log[#log + 1] = "enter " .. key end,
            leave = function() log[#log + 1] = "leave " .. key end,
        }
    end
    return entry
end

-- 1. On unless unticked.
local dbA, dbB, dbC = {}, {}, {}
local a = Entry("alpha", 1, dbA, true)
local b = Entry("beta", 2, dbB, false)
local c = Entry("gamma", 3, dbC, true)
SW:Join(c)
SW:Join(a)
SW:Join(b)
assert(SW.On(), "on unless unticked")
assert(dbA.oneWindow == nil, "nothing is written until a choice")
SW.SetOn(false)
assert(not SW.On(), "unticked")
assert(dbA.oneWindow == false and dbC.oneWindow == false, "every save says off")
SW.SetOn(true)
assert(SW.On(), "ticked")
assert(dbA.oneWindow == true and dbB.oneWindow == true and dbC.oneWindow == true, "every save says on")
assert(dbA.oneWindowAt == clock, "the time is kept")
dbB.oneWindow, dbB.oneWindowAt = false, clock + 10
assert(not SW.On(), "the newest answer wins")
SW.SetOn(true)

-- 2. Only an addon that moved in is hosted.
assert(SW.Hosts("alpha") and not SW.Hosts("beta"), "only hosts moved-in pages")
assert(not SW.Hosts("nobody"), "an unknown addon is not hosted")

-- 3 and 4. Open on the first that moved in; the rail is in order.
assert(SW.Open(), "opens")
assert(SW.IsOpen(), "shown")
local frame = BlackthornesWindow.frame
assert(frame.rail.buttons[1].entry == a and frame.rail.buttons[2].entry == b
    and frame.rail.buttons[3].entry == c, "rail in order")
assert(frame.rail.buttons[3].icon.texture == "icon-gamma", "rail shows the icon")
assert(log[#log] == "enter alpha", "the first that moved in shows")
assert(dbA.oneWindowPick == "alpha" and dbC.oneWindowPick == "alpha", "the pick is kept everywhere")

assert(not SW.Pick("beta"), "one that has not moved in is not picked")
assert(log[#log] == "open beta", "it opens its own window")

-- A tall addon stretched the window; the next one starts from the usual
-- size, its top left corner kept (2026-11-16).
frame:SetHeight(1000)
frame.left, frame.top = 100, 600
assert(SW.Pick("gamma"), "picks the next")
assert(frame:GetHeight() == SW.HEIGHT and frame:GetWidth() == SW.WIDTH, "back to the usual size for the next addon")
assert(frame.point and frame.point[1] == "TOPLEFT" and frame.point[4] == 100 and frame.point[5] == 600,
    "its top left corner stays put")
assert(select(2, SW.BaseSize()) == SW.HEIGHT, "the usual height undocked")
assert(log[#log - 1] == "leave alpha" and log[#log] == "enter gamma", "the last one lets go first")
frame.rail.buttons[1].scripts.OnClick(frame.rail.buttons[1], "RightButton")
assert(log[#log] == "settings alpha", "right-click opens its settings")

-- 5. Place and scale.
frame.scripts.OnDragStop(frame)
assert(dbA.oneWindowLeft == 100 and dbB.oneWindowTop == 600, "the place is kept everywhere")
frame.grip.scripts.OnClick(frame.grip, "RightButton")
assert(dbA.oneWindowScale == 100, "right-click is the normal size")
assert(SW.Clamp(10) == 50 and SW.Clamp(400) == 150 and SW.Clamp(nil) == 100, "the scale stays in range")

SW.Close()
assert(log[#log] == "leave gamma", "closing lets the pages go")
assert(SW.Open(), "opens again")
assert(log[#log] == "enter gamma", "on the addon picked last")
-- 6. Docking. Up on gamma, the game's mailbox opens.
MailFrame = Object()
MailFrame.right, MailFrame.top = 500, 700
OpenMailFrame = Object()
OpenMailFrame.shown = false
OpenMailFrame.right, OpenMailFrame.top = 860, 690
local width, height = frame:GetWidth(), frame:GetHeight()
dbA.oneWindowLeft, dbA.oneWindowTop = 100, 600
local heard = 0
SW.Watch(function() heard = heard + 1 end)
SW.Watch(function() error("a broken watcher") end)
assert(SW.DockedFrame() == nil, "nothing docked yet")
now = now + 5
SW.Arrived("mail")
assert(SW.Docked() and SW.Place() == "mail", "docks at the mailbox")
assert(SW.DockedFrame() == frame and heard == 1, "watchers hear it dock, past a broken one")
-- 9. A letter opens beside the mailbox: the window steps past it, and back.
OpenMailFrame.shown = true
OpenMailFrame:Fire("OnShow")
assert(frame.point and frame.point[4] == 860 + SW.DOCK_GAP and frame.point[5] == 690, "beside the open letter")
assert(heard == 2, "watchers hear it move")
OpenMailFrame:Hide()
OpenMailFrame:Fire("OnHide")
assert(frame.point and frame.point[4] == 500 + SW.DOCK_GAP and frame.point[5] == 700, "back beside the mailbox")
SW.Arrived("mail")
assert(#OpenMailFrame.hooks.OnShow == 1, "the letter is watched once")
assert(frame:GetWidth() == width - SW.RAIL_WIDTH - 8 and frame:GetHeight() == height + SW.ROW_HEIGHT + 8,
    "narrower by the rail, taller by the row")
assert(frame.point and frame.point[4] == 500 + SW.DOCK_GAP and frame.point[5] == 700, "beside the game's window")
assert(frame.rail.buttons[1].name.shown == false, "the row shows emblems only")
SW.Open("alpha")
assert(SW.Docked() and BlackthornesWindow.current == a, "an addon can take it over while docked")
frame.left = 1
frame.scripts.OnDragStop(frame)
assert(dbA.oneWindowLeft == 100, "moving it while docked keeps its own place")
heard = 0
SW.Left("mail")
assert(not SW.Docked() and frame:GetWidth() == width and frame:GetHeight() == height, "back to its own size")
assert(heard == 1 and SW.DockedFrame() == nil, "watchers hear it undock")
OpenMailFrame.shown = true
OpenMailFrame:Fire("OnShow")
assert(not SW.Docked() and frame.point[4] == 100, "a letter after the mailbox closed moves nothing")
OpenMailFrame.shown = false
assert(frame.point and frame.point[4] == 100 and frame.point[5] == 600, "back to its own place")
assert(BlackthornesWindow.current == c and log[#log] == "enter gamma", "back on the addon open before")
assert(frame.rail.buttons[1].name.shown == true, "the rail again")

-- Closed, an addon opens it at the vendor and closes it as it leaves.
MerchantFrame = Object()
MerchantFrame.right, MerchantFrame.top = 400, 650
SW.Close()
SW.Arrived("vendor")
assert(not SW.Docked(), "nothing to dock while closed")
now = now + 5
SW.Open("alpha")
assert(SW.Docked(), "opened at the vendor, it docks")
SW.Close()
SW.Left("vendor")
assert(not SW.IsOpen() and not SW.Docked(), "closed before, it stays closed")

-- Up on gamma, the addon opens before the game's event is heard.
now = now + 5
SW.Open("gamma")
SW.Open("alpha")
SW.Arrived("vendor")
assert(SW.Docked(), "docks when the event comes after")
SW.Close(true)
SW.Left("vendor")
assert(SW.IsOpen() and BlackthornesWindow.current == c and not SW.Docked(), "reopens on the addon open before")

-- 11. Up on gamma at the vendor, the player closes it (its close gem, or
-- Escape, which closes the vendor too): it stays closed as the vendor goes.
now = now + 5
SW.Arrived("vendor")
assert(SW.Docked(), "up on gamma, it docks at the vendor")
frame:Hide()
SW.Left("vendor")
assert(not SW.IsOpen(), "closed by the player at the vendor, it stays closed")
SW.Open("gamma")
now = now + 5
SW.Open("alpha")
SW.Arrived("vendor")
SW.Close()
SW.Left("vendor")
assert(not SW.IsOpen(), "closed without byItself, it stays closed")
SW.Open("gamma")

-- At the auction house too.
AuctionHouseFrame = Object()
AuctionHouseFrame.right, AuctionHouseFrame.top = 840, 720
now = now + 5
SW.Arrived("auction")
assert(SW.Docked() and SW.Place() == "auction", "docks at the auction house")
assert(frame.point and frame.point[4] == 840 + SW.DOCK_GAP and frame.point[5] == 720, "beside the auction house")
assert(SW.RowShown() and frame.rail.shown ~= false, "another addon keeps its row there")
SW.Left("auction")
assert(not SW.Docked() and SW.IsOpen() and BlackthornesWindow.current == c, "back on its own after the auction house")

-- 7. Tradeskills alone at the auction house.
local dbT = {}
local t = Entry("tradeskills", 5, dbT, true)
SW:Join(t)
now = now + 5
width, height = frame:GetWidth(), frame:GetHeight()
SW.Arrived("auction")
SW.Open("tradeskills")
assert(SW.Docked() and BlackthornesWindow.current == t, "Tradeskills shows at the auction house")
assert(not SW.RowShown() and frame.rail.shown == false, "no row of addon buttons there")
assert(frame:GetWidth() == width - SW.RAIL_WIDTH - 8 and frame:GetHeight() == height,
    "narrower by the rail, no taller")
SW.Pick("alpha")
assert(SW.RowShown() and frame.rail.shown == true and frame:GetHeight() == height + SW.ROW_HEIGHT + 8,
    "another addon picked there brings the row back")
SW.Pick("tradeskills")
assert(frame.rail.shown == false and frame:GetHeight() == height, "and Tradeskills leaves it out again")
SW.Left("auction")
assert(not SW.Docked() and frame:GetWidth() == width and frame:GetHeight() == height
    and frame.rail.shown == true, "back to its own size, rail and all")
assert(BlackthornesWindow.current == c, "back on the addon open before")

-- Opened by Tradeskills as the auction house opens, with the event first.
SW.Close()
now = now + 5
SW.Arrived("auction")
SW.Open("tradeskills")
assert(SW.Docked() and frame.rail.shown == false and frame:GetHeight() == height, "no row when opened there")
SW.Close()
SW.Left("auction")
assert(not SW.Docked() and frame:GetHeight() == height and frame.rail.shown == true, "its own size again")
SW.Open("gamma")

-- 10. Kept beside the auction house. The game shows its window late.
AuctionHouseFrame.shown = false
now = now + 5
SW.Arrived("auction")
SW.Open("tradeskills")
assert(not SW.Docked(), "nothing to sit beside yet")
assert(frame.watch and frame.watch.scripts.OnUpdate, "a watcher looks while shown")
AuctionHouseFrame.shown = true
frame.watch.wait = 0
frame.watch.scripts.OnUpdate(frame.watch, 0.05)
assert(SW.Docked() and frame.point[4] == 840 + SW.DOCK_GAP, "docks once the game's window shows")
heard = 0
assert(SW.Keep() == false and heard == 0, "nothing moved, nothing placed")
frame.point = { "TOPLEFT", UIParent, "BOTTOMLEFT", 300, 720 }
assert(SW.Keep() == false and frame.point[4] == 300, "dragged by hand, it stays")
AuctionHouseFrame.right = 860
assert(SW.Keep() and frame.point[4] == 860 + SW.DOCK_GAP and heard == 1, "the game's window moved: beside it again")
frame.point = { "TOPLEFT", UIParent, "BOTTOMLEFT", 300, 720 }
frame:SetWidth(frame:GetWidth() - 200)
assert(SW.Keep() and frame.point[4] == 860 + SW.DOCK_GAP, "narrower: placed beside it again")
frame:SetWidth(frame:GetWidth() + 200)
AuctionHouseFrame.right = 840
SW.Close()
SW.Left("auction")
assert(not SW.Docked() and SW.Keep() == false, "nothing to keep once it closes")
SW.Open("gamma")

-- 8. The interaction manager's hide undocks as the close event does.
Enum = nil
assert(SW.InteractionPlace(17) == "mail" and SW.InteractionPlace(5) == "vendor"
    and SW.InteractionPlace(7) == "trainer" and SW.InteractionPlace(21) == "auction",
    "the numbers stand in without an Enum")
assert(SW.InteractionPlace(8) == "bank" and SW.InteractionPlace(22) == "stable", "the bank and stable too")
assert(SW.InteractionPlace(3) == nil and SW.InteractionPlace("mail") == nil, "a gossip or junk is no place")
Enum = { PlayerInteractionType = { MailInfo = 40, Merchant = 41, Trainer = 42, Auctioneer = 43 } }
assert(SW.InteractionPlace(40) == "mail" and SW.InteractionPlace(17) == nil, "the client's Enum wins")
now = now + 5
SW.Arrived("mail")
assert(SW.Docked(), "docks at the mailbox")
SW.events.scripts.OnEvent(SW.events, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 41)
assert(SW.Docked(), "a vendor closing leaves the mailbox dock alone")
SW.events.scripts.OnEvent(SW.events, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 40)
assert(not SW.Docked() and SW.Place() == nil, "the mailbox closing undocks")
SW.events.scripts.OnEvent(SW.events, "MAIL_CLOSED")
assert(not SW.Docked() and SW.IsOpen(), "the close event after it changes nothing")
Enum = nil

-- 11. Folded with the gem, it docks and undocks and opens back at its size.
do
    local fullW, fullH = frame:GetWidth(), frame:GetHeight()
    local state = { folded = true, width = fullW, full = fullH }
    rawset(frame, "blackthornesFold", state)
    local setSize, setHeight = frame.SetSize, frame.SetHeight
    -- What FoldWindow's hooks do: keep the size for the unfold, stay a strip.
    frame.SetSize = function(self, w, h)
        if state.folded then state.width, state.full = w, h; return setHeight(self, 38) end
        return setSize(self, w, h)
    end
    frame.SetHeight = function(self, h)
        if state.folded then state.full = h; return setHeight(self, 38) end
        return setHeight(self, h)
    end
    setHeight(frame, 38)
    now = now + 5
    SW.Arrived("mail")
    assert(SW.Docked() and state.width == fullW - SW.RAIL_WIDTH - 8 and state.full == fullH + SW.ROW_HEIGHT + 8,
        "docked while folded, it keeps the docked size to open to")
    assert(frame:GetHeight() == 38, "and stays folded")
    SW.Left("mail")
    assert(not SW.Docked() and state.width == fullW and state.full == fullH,
        "undocked while folded, it opens back at its own size")
    state.folded = false
    frame.SetSize, frame.SetHeight = setSize, setHeight
    rawset(frame, "blackthornesFold", nil)
    frame:SetSize(fullW, fullH)
end

-- 12. Dragged while docked, it keeps that spot beside the game's window,
-- kept for each place; Set Default puts every window back.
do
    now = now + 5
    SW.Arrived("auction")
    SW.Open("tradeskills")
    assert(SW.Docked() and SW.Place() == "auction", "docked at the auction house")
    frame.left, frame.top = 900, 650
    frame.scripts.OnDragStop(frame)
    local spot = dbA.oneWindowDockSpots and dbA.oneWindowDockSpots.auction
    assert(spot and spot.x == 60 and spot.y == -70, "the drop is kept from the game window's corner")
    assert(dbC.oneWindowDockSpots ~= dbA.oneWindowDockSpots or dbC.oneWindowDockSpots.auction.x == 60,
        "every save has it")
    assert(SW.Keep() == false, "dropped by hand, nothing moves it back")
    AuctionHouseFrame.right = 860
    assert(SW.Keep() and frame.point[4] == 920 and frame.point[5] == 650,
        "the game's window moved: the window keeps its spot from it")
    SW.Close()
    SW.Left("auction")
    AuctionHouseFrame.right = 840
    now = now + 5
    SW.Arrived("auction")
    SW.Open("tradeskills")
    assert(SW.Docked() and frame.point[4] == 900 and frame.point[5] == 650, "next visit, the same spot")
    -- Mid-drag, nothing puts it back, even when the game's window or the
    -- bags shift under it (players saw it snap back at the profession
    -- window, 2026-11-17); the drop is kept as before.
    frame.scripts.OnDragStart(frame)
    assert(SW.Dragging(), "a drag is heard")
    frame.point = { "TOPLEFT", UIParent, "BOTTOMLEFT", 500, 500 }
    AuctionHouseFrame.right = 850
    assert(SW.Keep() == false and frame.point[4] == 500, "the watcher leaves it alone while dragged")
    assert(SW.Dock(true) == false and frame.point[4] == 500, "nothing docks it mid-drag")
    frame.left, frame.top = 500, 500
    frame.scripts.OnDragStop(frame)
    assert(not SW.Dragging(), "the drag ends on the drop")
    assert(SW.Keep() == false and frame.point[4] == 500, "dropped there, it stays")
    AuctionHouseFrame.right = 840
    assert(SW.Keep() and frame.point[4] == 490 and frame.point[5] == 500,
        "the game's window moved back: the drop's spot from it")
    -- A drop never heard ends once the mouse button is up.
    frame.scripts.OnDragStart(frame)
    _G.IsMouseButtonDown = function() return false end
    assert(not SW.Dragging(), "button up: the drag is over")
    _G.IsMouseButtonDown = nil
    local ran = 0
    SW.AddSpotReset("beta", function() ran = ran + 1 end)
    SW.AddSpotReset("alpha", function() error("broken") end)
    dbA.oneWindowScale = 120
    SW.ResetAllSpots()
    assert(ran == 1, "every addon's reset runs, past a broken one")
    assert(dbA.oneWindowDockSpots == nil and dbC.oneWindowDockSpots == nil
        and dbA.oneWindowLeft == nil and dbB.oneWindowTop == nil, "the spots go")
    assert(dbA.oneWindowScale == 120, "the size stays")
    assert(frame.point[4] == 840 + SW.DOCK_GAP, "docked, it goes back beside the game's window")
    SW.Close()
    SW.Left("auction")
    frame.left, frame.top = 100, 600
    SW.Open("gamma")

    -- A small window keeps where it was dragged; Set Default puts it back.
    local hookBefore = _G.hooksecurefunc
    _G.hooksecurefunc = function(t, name, fn)
        local old = t[name]
        t[name] = function(...) old(...) fn(...) end
    end
    local small = Object()
    small.shown = false
    small:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    SW.KeepSpot(small, "alpha.export")
    _G.hooksecurefunc = hookBefore
    small.left, small.top = 300, 500
    small:StopMovingOrSizing()
    assert(dbA.windowSpots and dbA.windowSpots["alpha.export"].x == 300
        and dbB.windowSpots["alpha.export"].y == 500, "the drop is kept in every save")
    small:ClearAllPoints()
    small:Show()
    small:Fire("OnShow")
    assert(small.point and small.point[1] == "TOPLEFT" and small.point[4] == 300 and small.point[5] == 500,
        "shown again, it goes where it was left")
    SW.ResetAllSpots()
    assert(dbA.windowSpots == nil, "Set Default forgets it")
    assert(small.point[1] == "CENTER" and small.point[5] == 40, "and puts it back where it started")
end

-- 13. The free side.
do
    local savedW, savedS = UIParent.width, UIParent.GetEffectiveScale
    MerchantFrame.left, MerchantFrame.right, MerchantFrame.top = 100, 400, 650
    UIParent.width = 5000
    now = now + 5
    SW.Arrived("vendor")
    SW.Open("alpha")
    assert(SW.Docked() and frame.point[4] == 400 + SW.DOCK_GAP, "room on the right: the right")
    local w = frame:GetWidth()
    local own = SW.Clamp(dbA.oneWindowScale) / 100
    MerchantFrame.left, MerchantFrame.right = 2000, 2300
    UIParent.width = 2350
    assert(SW.Keep() and frame.point[4] == 2000 - w - SW.DOCK_GAP, "room on the left only: the left")
    -- A little short on both sides: a little smaller, on the right.
    local gap = math.floor(w * 0.95)
    MerchantFrame.left, MerchantFrame.right = gap, gap + 300
    UIParent.width = 2 * gap + 300
    assert(SW.Keep() and math.abs(frame.point[4] - ((gap + 300) * own / frame.scale + SW.DOCK_GAP)) < 1e-6,
        "neither fits: the right, the bigger gap on a tie")
    assert(frame.scale < own and frame.scale >= own * SW.SHRINK_LEAST - 1e-9, "shrunk a little to fit")
    -- Far too little room: it keeps its size and stays on the screen.
    MerchantFrame.left, MerchantFrame.right = 300, 600
    UIParent.width = 900
    SW.Keep()
    assert(frame.scale == own, "never shrunk out of reading: it keeps its size")
    -- (The stand-in frames give an effective scale of 1.)
    assert(frame.point[4] >= 0 and frame.point[4] + w <= 900 + 1e-6, "and stays on the screen")
    -- Resized by hand while docked: that size wins, even with no room.
    MerchantFrame.left, MerchantFrame.right = gap, gap + 300
    UIParent.width = 2 * gap + 300
    SW.Keep()
    assert(frame.scale < own, "shrunk a little before the grip")
    local shrunk = frame.scale
    local grip = frame.grip
    -- Grabbing the grip starts from the saved size, not the shrunk one.
    local savedCursor = GetCursorPosition
    GetCursorPosition = function() return 500, 500 end
    grip.scripts.OnMouseDown(grip, "LeftButton")
    grip.scripts.OnUpdate(grip)
    grip.scripts.OnMouseUp(grip)
    GetCursorPosition = savedCursor
    assert(dbA.oneWindowScale == own * 100 and frame.scale == own,
        "a grab with no move keeps the saved size and shows it")
    SW.Undock()
    SW.Dock()
    assert(frame.scale < own, "shrunk a little again on a fresh dock")
    grip.scripts.OnClick(grip, "RightButton")
    assert(dbA.oneWindowScale == 100 and frame.scale == 1, "the grip's size is kept, not the shrunk one")
    dbA.oneWindowScale = own * 100
    SW.Dock(true)
    assert(frame.scale == own and shrunk < own, "after the grip it no longer shrinks")
    SW.Undock()
    UIParent.width = 5000
    assert(SW.Keep() and frame.scale == own, "room again: its own size")
    MerchantFrame.left, MerchantFrame.right = 1000, 1300
    ContainerFrame1 = Object()
    ContainerFrame1.left = 1500
    assert(SW.Keep() and frame.point[4] == 1000 - w - SW.DOCK_GAP, "bags open on the right: the left")
    ContainerFrame1:Hide()
    assert(SW.Keep() and frame.point[4] == 1300 + SW.DOCK_GAP, "bags shut: the right again")
    ContainerFrame1 = nil
    MerchantFrame.left, MerchantFrame.right = 2000, 2300
    UIParent.width = 2350
    SW.Keep()
    -- 14. The character sheet opens at the vendor.
    CharacterFrame = Object()
    CharacterFrame.left, CharacterFrame.right, CharacterFrame.top = 50, 380, 700
    SW.HookPlaces()
    SW.HookPlaces()
    assert(#CharacterFrame.hooks.OnShow == 1, "the sheet is watched once")
    UIParent.width = 5000
    CharacterFrame:Fire("OnShow")
    assert(SW.Place() == "character" and SW.Docked() and frame.point[4] == 380 + SW.DOCK_GAP,
        "beside the character sheet")
    CharacterFrame:Fire("OnHide")
    assert(SW.Place() == "vendor" and SW.Docked() and frame.point[4] == 2300 + SW.DOCK_GAP,
        "back beside the vendor")
    SW.Close()
    SW.Left("vendor")
    assert(not SW.Docked() and SW.Place() == nil, "the vendor closes: no place")
    CharacterFrame:Fire("OnShow")
    assert(SW.Place() == "character" and not SW.Docked(), "closed, the sheet docks nothing")
    CharacterFrame:Fire("OnHide")
    assert(SW.Place() == nil, "and lets go")
    UIParent.width = savedW
    SW.Open("gamma")
end

-- 15. Shelves.
do
    BlackthornesShelves.pieces = {}
    UIParent.width = 1000
    local function Piece(h)
        local f = Object()
        f.height = h
        return f
    end
    local arrow, bar, gold = Piece(160), Piece(30), Piece(20)
    local laid = {}
    local barFree = true
    SW.ShelfJoin("arrow.test", { frame = arrow, place = function() laid[#laid + 1] = "arrow" end })
    SW.ShelfJoin("xpbar.test", { frame = bar, free = function() return barFree end,
        place = function() laid[#laid + 1] = "bar" end })
    SW.ShelfJoin("goldbar.test", { frame = gold, place = function() laid[#laid + 1] = "gold" end })
    local stack = 0
    SW.ShelfJoin("notice", { shown = function() return stack > 0 end, height = function() return stack end })
    local top = SW.SHELVES.top
    local point, x, y = SW.ShelfSpot("goldbar.test")
    assert(point == "TOP" and x == 0 and y == top.y, "the first piece takes the shelf's top")
    local _, _, ya = SW.ShelfSpot("arrow.test")
    assert(ya == top.y - 20 - top.gap, "the arrow under the gold bar")
    local _, _, yb = SW.ShelfSpot("xpbar.test")
    assert(yb == ya - 160 - top.gap, "the bar under the arrow")
    local _, _, yn = SW.ShelfSpot("notice")
    assert(yn == yb - 30 - top.gap, "notes last")
    barFree = false
    local _, _, yn2 = SW.ShelfSpot("notice")
    assert(yn2 == yb, "a dragged piece takes no room")
    barFree = true
    arrow:Hide()
    local _, _, yb2 = SW.ShelfSpot("xpbar.test")
    assert(yb2 == ya, "a hidden piece takes no room")
    laid = {}
    SW.ShelfChanged("arrow.test")
    assert(#laid == 1 and laid[1] == "bar", "only the shown pieces after it are laid again")
    laid = {}
    arrow:Show()
    arrow:Fire("OnShow")
    assert(#laid == 1 and laid[1] == "bar", "showing is heard by itself")
    SW.ShelfJoin("arrow.test", { frame = arrow, place = function() end })
    assert(#arrow.hooks.OnShow == 1, "joined again, it is watched once")
    local fight = _G.InCombatLockdown
    _G.InCombatLockdown = function() return true end
    laid = {}
    SW.ShelfChanged("goldbar.test")
    assert(#laid == 0, "nothing moves in a fight")
    _G.InCombatLockdown = fight
    SW.events.scripts.OnEvent(SW.events, "PLAYER_REGEN_ENABLED")
    assert(#laid >= 1, "laid once the fight ends")
    local card = Object()
    card.height = 80
    SW.ShelfJoin("travel.test", { shelf = "right", frame = card })
    local rp, rx, ry = SW.ShelfSpot("travel.test")
    assert(rp == "TOPRIGHT" and rx == SW.SHELVES.right.x and ry == SW.SHELVES.right.y, "the right shelf, in from the edge")
    ObjectiveTrackerFrame = Object()
    ObjectiveTrackerFrame.left = 760
    local _, rx2 = SW.ShelfSpot("travel.test")
    assert(rx2 == 760 - 1000 - SW.SHELVES.right.gap, "left of the quest list")
    ObjectiveTrackerFrame:Hide()
    local _, rx3 = SW.ShelfSpot("travel.test")
    assert(rx3 == SW.SHELVES.right.x, "quest list hidden: in from the edge")
    BlackthornesShelves.pieces = {}
end

-- 16. The gear.
do
    SW.FillRail()
    assert(not rawget(frame.rail, "gear") or not frame.rail.gear:IsShown(), "no gear while no addon has the page")
    local opened = {}
    b.allAddons = function() opened[#opened + 1] = "beta" end
    c.allAddons = function() opened[#opened + 1] = "gamma" end
    SW.FillRail()
    local gear = rawget(frame.rail, "gear")
    assert(gear and gear:IsShown() and gear.point[1] == "BOTTOM", "the gear at the foot of the rail")
    SW.Open("gamma")
    gear.scripts.OnClick(gear, "LeftButton")
    assert(opened[#opened] == "gamma", "opened on the addon showing")
    SW.Open("alpha")
    gear.scripts.OnClick(gear, "LeftButton")
    assert(opened[#opened] == "beta", "else the first that has it")
    b.allAddons, c.allAddons = nil, nil
    SW.FillRail()
    assert(not gear:IsShown(), "gone again with the page")
    SW.Open("gamma")
end

-- 17. Butler at the vendor (a player saw Farmer instead, 2026-11-17).
do
    assert(SW.PLACES.vendor.prefer == "butler", "the vendor names Butler")
    assert(SW.PLACES.vendor.only == nil, "the rail stays at the vendor")
    SW.Open("gamma")
    assert(not SW.Docked(), "up on gamma, away from any vendor")
    -- Without Butler the vendor changes nothing.
    now = now + 5
    SW.Arrived("vendor")
    assert(SW.Docked() and BlackthornesWindow.current == c, "no Butler: it stays on gamma")
    SW.Left("vendor")
    assert(BlackthornesWindow.current == c and not SW.Docked(), "still gamma after")

    local dbBu = {}
    local wantsVendor = true
    local bu = Entry("butler", 6, dbBu, true)
    bu.host.wants = function(place) return place == "vendor" and wantsVendor end
    SW:Join(bu)
    -- Twice over: the second visit must be Butler too.
    for visit = 1, 2 do
        now = now + 5
        SW.Arrived("vendor")
        assert(SW.Docked(), "docks at the vendor, visit " .. visit)
        assert(BlackthornesWindow.current == bu, "turns to Butler, visit " .. visit)
        SW.Left("vendor")
        assert(SW.IsOpen() and not SW.Docked() and BlackthornesWindow.current == c,
            "back on gamma as the vendor closes, visit " .. visit)
    end
    -- Butler opened it a moment before the event: nothing turns twice.
    now = now + 5
    local enters = 0
    for _, line in ipairs(log) do if line == "enter butler" then enters = enters + 1 end end
    SW.Open("butler")
    SW.Arrived("vendor")
    local after = 0
    for _, line in ipairs(log) do if line == "enter butler" then after = after + 1 end end
    assert(after == enters + 1, "Butler laid in once")
    SW.Left("vendor")
    assert(BlackthornesWindow.current == c, "back on gamma after Butler opened it")
    -- Butler's "open at vendors" unticked: it stays on gamma.
    wantsVendor = false
    now = now + 5
    SW.Arrived("vendor")
    assert(BlackthornesWindow.current == c, "Butler not wanting the vendor: still gamma")
    SW.Left("vendor")
    -- A broken answer changes nothing either.
    bu.host.wants = function() error("broken") end
    now = now + 5
    SW.Arrived("vendor")
    assert(BlackthornesWindow.current == c, "a broken answer: still gamma")
    SW.Left("vendor")
    -- Only the vendor turns to Butler.
    bu.host.wants = nil
    now = now + 5
    SW.Arrived("mail")
    assert(BlackthornesWindow.current == c, "the mailbox keeps gamma")
    SW.Left("mail")
    -- Closed, the vendor opens nothing by itself.
    SW.Close()
    now = now + 5
    SW.Arrived("vendor")
    assert(not SW.IsOpen(), "closed, it stays closed at the vendor")
    SW.Left("vendor")
    SW.Open("gamma")
end

SW.SetOn(false)
assert(not SW.IsOpen(), "unticking closes it")
assert(not SW.Hosts("gamma"), "nothing is hosted while off")

for _, name in ipairs(NAMES) do _G[name] = saved[name] end
print("test_sharedwindow: ok")
