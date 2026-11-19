-- Blackthornes -- UI/SharedWindow.lua
-- One window for every Blackthornes addon (the owner approved the mockups
-- and said build it, 2026-10-30, first on Classic, then copied here by hand
-- for Forever): a house-look window with a rail down its
-- left side, a button for each addon loaded, and the picked addon's pages
-- beside it. One size, one size grip, one fold gem, one place. A swap gem
-- beside the fold gem splits it back into each addon's own window, and the
-- same gem on those windows joins them again (SharedWindow.AddSwap).
--
-- The same file in all five addons; a fix to it belongs in all five. There
-- is no shared core addon, so, like UI/SharedMinimap.lua, every copy signs
-- up in one global table, `_G.BlackthornesWindow`, as it loads, and each
-- addon joins with `SharedWindow:Join`. The copy with the highest
-- FILE_VERSION builds and draws the window (the first to load on a tie), so
-- raise it when a change needs the newer copy.
--
-- An addon whose pages have moved in gives `host = { enter, leave }`:
-- `enter(area)` lays its pages into the window's content frame, `leave()`
-- takes them back. An addon without one still has its rail button, which
-- opens the addon's own window, so each addon works whatever has moved in.
--
-- On unless unticked ("One Window:", nil reads as on; the owner, 2026-10-30:
-- a player who ticked or unticked it keeps that). Saved in every loaded
-- addon's account save, account wide, never rename them: `oneWindow` (true
-- or false), `oneWindowAt` (when it was set; the newest wins), `oneWindowPick`
-- (the addon picked last), `oneWindowLeft`, `oneWindowTop` (its top left
-- corner) and `oneWindowScale` (the size grip's percent).
--
-- Docking (the owner said build it, 2026-10-30, mockup B): while the game's
-- auction house, mailbox, vendor or trainer window is open and the one
-- window is up, it sits beside the game's window, its rail turned into a
-- small row of addon buttons along the top so it stays narrow. When the
-- game's window closes it goes back to its own place, on the addon that was
-- open before. Which addon shows there is each addon's own doing (Tradeskills
-- at the auction house, Butler at the mailbox and the vendor). At the
-- auction house only Tradeskills is needed (the owner, 2026-10-30), so while
-- it shows there the row of addon buttons is left out (`only`). The game's
-- frames are only read for where they stand, never shown, hidden, moved or
-- written; ours is placed by screen position.
--
-- Forever is a retail engine (Interface 16001): beside the close events, a
-- game window going away is also heard as PLAYER_INTERACTION_MANAGER_FRAME_HIDE
-- (by its Enum.PlayerInteractionType), in case the client says only that.
-- Every event is registered in a pcall, so one this client does not know
-- costs nothing. This Forever copy has its own FILE_VERSION count; it never
-- meets the Classic copy, which runs on another client.

local ADDON, ns = ...

local SharedWindow = {}
ns.SharedWindow = SharedWindow

local FILE_VERSION = 14
SharedWindow.FILE_VERSION = FILE_VERSION

local PLATE = "Blackthornes"
-- The words through the addon's translation table where it has one.
local L = ns.L or setmetatable({}, { __index = function(_, key) return key end })
-- The gear at the foot of the rail: the settings every Blackthornes addon
-- shares, shown once (2026-11-16, the owner said build it).
SharedWindow.GEAR_ICON = [[Interface\Icons\INV_Misc_Gear_01]]
SharedWindow.RAIL_WIDTH = 84
SharedWindow.RAIL_BUTTON = 76
SharedWindow.WIDTH = 860
SharedWindow.HEIGHT = 520
SharedWindow.SCALE_MIN = 50
SharedWindow.SCALE_MAX = 150
local EDGE = 8
local TOP = 30
local ICON = 34
SharedWindow.ROW_HEIGHT = 40
SharedWindow.ROW_BUTTON = 34
SharedWindow.ROW_ICON = 26
SharedWindow.DOCK_GAP = 6
-- Docked with no room on either side, the window may shrink to this share
-- of the player's own size and no smaller; past that it keeps its size and
-- sits over the game's window's edge instead (2026-11-16: it had shrunk
-- too small to read beside the auction house).
SharedWindow.SHRINK_LEAST = 0.85
-- And never under this size in percent (the grip's 100 is the normal size),
-- whatever the player's own: other docked pieces read it too.
SharedWindow.DOCK_SCALE_MIN = 75
-- How often, while a game window is open, the window looks that it still
-- sits beside it.
SharedWindow.KEEP_EVERY = 0.2
-- How soon after a game window closes the one window goes back to the addon
-- open before, so the addons' own closing comes first.
SharedWindow.BACK_WAIT = 0.1
-- How long an Open counts as "just before" a game window opened.
SharedWindow.PRIOR_FOR = 0.5

-- The game's windows the one window docks beside: the events that open and
-- close each, and the frames it may be (read only). `only` is the one addon
-- needed there: while it shows, the row of addon buttons is left out.
-- `prefer` is the addon the place is for, the row kept: up on another addon
-- as the place opens, the window turns to it (SharedWindow.Preferred).
-- `interaction` names the window's Enum.PlayerInteractionType, with the
-- number to use when the client has no Enum. The first frame shown wins,
-- so an open letter, which stands right of the mailbox, comes before it;
-- `follow` are the frames that come and go while the place stays open
-- (watched by HookScript, read only), so the window moves with them.
SharedWindow.PLACES = {
    auction = { show = "AUCTION_HOUSE_SHOW", hide = "AUCTION_HOUSE_CLOSED", frames = { "AuctionHouseFrame" }, only = "tradeskills",
        interaction = { "Auctioneer", 21 } },
    mail = { show = "MAIL_SHOW", hide = "MAIL_CLOSED", frames = { "OpenMailFrame", "MailFrame" },
        follow = { "OpenMailFrame" }, interaction = { "MailInfo", 17 } },
    vendor = { show = "MERCHANT_SHOW", hide = "MERCHANT_CLOSED", frames = { "MerchantFrame" },
        prefer = "butler", interaction = { "Merchant", 5 } },
    trainer = { show = "TRAINER_SHOW", hide = "TRAINER_CLOSED", frames = { "ClassTrainerFrame" },
        interaction = { "Trainer", 7 } },
    -- Added 2026-11-16 (the owner said build it, from the UI cleanup
    -- mockups): the bank, the stable, and the character sheet, which has
    -- no event of its own and is heard by HookScript on its frame (`hook`,
    -- read only, never shown, hidden or moved).
    bank = { show = "BANKFRAME_OPENED", hide = "BANKFRAME_CLOSED", frames = { "BankFrame" },
        interaction = { "Banker", 8 } },
    stable = { show = "PET_STABLE_SHOW", hide = "PET_STABLE_CLOSED", frames = { "PetStableFrame", "StableFrame" },
        interaction = { "StableMaster", 22 } },
    character = { hook = "CharacterFrame", frames = { "CharacterFrame" } },
    -- The profession window (Tradeskills' craft pane moves in as a tab).
    profession = { show = "TRADE_SKILL_SHOW", hide = "TRADE_SKILL_CLOSE",
        frames = { "ProfessionsFrame", "TradeSkillFrame" } },
}

--- The place a PLAYER_INTERACTION_MANAGER_FRAME_HIDE kind closes, or nil.
function SharedWindow.InteractionPlace(kind)
    if type(kind) ~= "number" then return nil end
    local enum = rawget(_G, "Enum")
    local types = type(enum) == "table" and rawget(enum, "PlayerInteractionType") or nil
    for key, place in pairs(SharedWindow.PLACES) do
        if place.interaction then
            local name, fallback = place.interaction[1], place.interaction[2]
            local value = type(types) == "table" and rawget(types, name) or fallback
            if value == kind then return key end
        end
    end
    return nil
end

local hub = _G.BlackthornesWindow
if type(hub) ~= "table" then
    hub = {}
    _G.BlackthornesWindow = hub
end
hub.entries = hub.entries or {}
hub.copies = hub.copies or {}
hub.copies[#hub.copies + 1] = { version = FILE_VERSION, api = SharedWindow, ns = ns }

--- The copy that draws: the highest FILE_VERSION, the first loaded on a tie.
function SharedWindow.Drawer()
    local best
    for _, copy in ipairs(hub.copies) do
        if not best or (copy.version or 0) > (best.version or 0) then best = copy end
    end
    return best
end

local function IsDrawer()
    local best = SharedWindow.Drawer()
    return best and best.api == SharedWindow
end

--- Every addon that joined, in rail order.
function SharedWindow.Entries()
    local list = {}
    for _, entry in pairs(hub.entries) do list[#list + 1] = entry end
    table.sort(list, function(a, b)
        if (a.order or 99) ~= (b.order or 99) then return (a.order or 99) < (b.order or 99) end
        return tostring(a.key) < tostring(b.key)
    end)
    return list
end

local function SaveOf(entry)
    if type(entry.db) ~= "function" then return nil end
    local ok, db = pcall(entry.db)
    if ok and type(db) == "table" then return db end
    return nil
end

--- The first value any save holds for `key`, in rail order.
local function Read(key)
    for _, entry in ipairs(SharedWindow.Entries()) do
        local db = SaveOf(entry)
        if db and db[key] ~= nil then return db[key] end
    end
    return nil
end

--- Write `key` in every loaded addon's save.
local function WriteAll(key, value)
    for _, entry in pairs(hub.entries) do
        local db = SaveOf(entry)
        if db then db[key] = value end
    end
end

--- Whether the one window is on: the newest answer any save holds, on when
--- none says.
function SharedWindow.On()
    local value, at = nil, -1
    for _, entry in pairs(hub.entries) do
        local db = SaveOf(entry)
        if db and db.oneWindow ~= nil then
            local when = tonumber(db.oneWindowAt) or 0
            if when > at then value, at = db.oneWindow, when end
        end
    end
    return value ~= false
end

--- Tick or untick it, in every loaded addon's save at once. Unticked, the
--- window closes and each addon's pages go back to their own windows.
function SharedWindow.SetOn(on)
    local now = (time and time()) or 0
    for _, entry in pairs(hub.entries) do
        local db = SaveOf(entry)
        if db then
            db.oneWindow = on and true or false
            db.oneWindowAt = now
        end
    end
    if not on then SharedWindow.Close() end
end

--- An addon signs up. `entry` holds key, order, name (shown on the rail),
--- icon, open (its own window), settings, db (its account save) and, once
--- its pages have moved in, host = { enter(area), leave() }.
function SharedWindow:Join(entry)
    if type(entry) ~= "table" or not entry.key then return end
    hub.entries[entry.key] = entry
    if hub.frame and hub.frame:IsShown() then SharedWindow.FillRail() end
end

--- True when this addon's pages show in the one window rather than its own.
function SharedWindow.Hosts(key)
    local entry = hub.entries[key]
    return entry ~= nil and type(entry.host) == "table" and SharedWindow.On()
end

--------------------------------------------------------------------------------
-- Picking an addon
--------------------------------------------------------------------------------

--- The addon picked last, else the first that has moved in.
function SharedWindow.Picked()
    local key = Read("oneWindowPick")
    local entry = key and hub.entries[key]
    if entry and entry.host then return entry end
    for _, each in ipairs(SharedWindow.Entries()) do
        if each.host then return each end
    end
    return nil
end

--- Show `key`'s pages. One that has not moved in opens its own window.
function SharedWindow.Pick(key)
    local entry = hub.entries[key]
    if not entry then return false end
    if type(entry.host) ~= "table" then
        if type(entry.open) == "function" then pcall(entry.open) end
        return false
    end
    local frame = SharedWindow.Build()
    if not frame then return false end
    if hub.current and hub.current ~= entry and type(hub.current.host.leave) == "function" then
        pcall(hub.current.host.leave)
    end
    hub.current = entry
    WriteAll("oneWindowPick", key)
    SharedWindow.Settle(frame)
    if type(entry.host.enter) == "function" then pcall(entry.host.enter, frame.area) end
    if hub.docked then SharedWindow.Refit() end
    SharedWindow.FillRail()
    return true
end

--- Open the window on `key`, or on the addon picked last.
function SharedWindow.Open(key)
    local entry = key and hub.entries[key] or SharedWindow.Picked()
    if not entry then return false end
    local frame = SharedWindow.Build()
    if not frame then return false end
    local wasOpen = frame:IsShown() and true or false
    hub.prior = { key = hub.current and hub.current.key, open = wasOpen, at = SharedWindow.Now() }
    if ns.FoldWindow and ns.FoldWindow.Unfold then pcall(ns.FoldWindow.Unfold, ns.FoldWindow, frame) end
    frame:Show()
    local picked = SharedWindow.Pick(entry.key)
    if hub.place then
        if not hub.docked then
            hub.back = wasOpen and { key = hub.prior.key, open = true } or nil
        end
        SharedWindow.Dock()
    elseif hub.docked then
        SharedWindow.Undock()
    end
    return picked
end

--- Close the window. `byItself` is true when an addon closes it because the
--- game's window it came up for closed; then it may go back to what was
--- open before. Any other close (the player's) stays closed.
function SharedWindow.Close(byItself)
    if not hub.frame then return end
    hub.byItself = byItself and true or nil
    hub.frame:Hide()
    hub.byItself = nil
end

function SharedWindow.IsOpen()
    return hub.frame ~= nil and hub.frame:IsShown() and true or false
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local function Clamp(percent)
    percent = tonumber(percent)
    -- Not a number (0/0) fails every comparison below and would come back
    -- as the window's size; a bad save reads as the first size instead.
    if not percent or percent ~= percent then percent = 100 end
    if percent < SharedWindow.SCALE_MIN then return SharedWindow.SCALE_MIN end
    if percent > SharedWindow.SCALE_MAX then return SharedWindow.SCALE_MAX end
    return percent
end
SharedWindow.Clamp = Clamp

local function SavePlace(frame)
    local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
    if ok and type(left) == "number" and type(top) == "number" then
        WriteAll("oneWindowLeft", left)
        WriteAll("oneWindowTop", top)
    end
end

--- How tall the window may be at its scale: the screen's height less a
--- margin, never under MIN_ROOM. Nothing taller than the screen is drawn.
SharedWindow.SCREEN_MARGIN = 60
SharedWindow.MIN_ROOM = 320
function SharedWindow.Room(frame)
    local ok, room = pcall(function()
        local ui = UIParent:GetHeight() * UIParent:GetEffectiveScale()
        return math.floor(ui / frame:GetEffectiveScale()) - SharedWindow.SCREEN_MARGIN
    end)
    if not ok or type(room) ~= "number" or room <= 0 then return nil end
    return math.max(room, SharedWindow.MIN_ROOM)
end

--- The size the window has, or while folded (the fold gem) the size it
--- opens back up to. Sizes worked out from the folded strip's height made
--- the window open squashed after docking or undocking while folded
--- (2026-11-05); set while folded, FoldWindow keeps them for the unfold.
function SharedWindow.FullSize(frame)
    local state = rawget(frame, "blackthornesFold")
    if type(state) == "table" and state.folded
        and type(state.width) == "number" and type(state.full) == "number" then
        return state.width, state.full
    end
    local okW, width = pcall(frame.GetWidth, frame)
    local okH, height = pcall(frame.GetHeight, frame)
    return (okW and type(width) == "number") and width or nil,
        (okH and type(height) == "number") and height or nil
end

--- Keep the window inside the screen's height; its pages scroll instead.
function SharedWindow.Fit(frame)
    frame = frame or hub.frame
    if not frame then return end
    local room = SharedWindow.Room(frame)
    local _, height = SharedWindow.FullSize(frame)
    if room and height and height > room then
        frame:SetHeight(room)
    end
end

--- The window's own size before any addon grows it: the usual one, or
--- docked, less the rail and plus the row of addon buttons when it shows.
function SharedWindow.BaseSize()
    local width, height = SharedWindow.WIDTH, SharedWindow.HEIGHT
    if hub.docked then
        width = width - SharedWindow.RAIL_WIDTH - EDGE
        if hub.row then height = height + SharedWindow.ROW_HEIGHT + EDGE end
    end
    return width, height
end

--- Back to the window's own size, its top left corner kept, so the addon
--- shown next grows it only as far as it needs. Every addon only grows
--- the window, so before this one tall page (Butler with gold goals) left
--- its height behind for every addon after it, with empty room at the
--- bottom (2026-11-16). Folded, the fold keeps the size it opens back to.
function SharedWindow.Settle(frame)
    frame = frame or hub.frame
    if not frame then return end
    local state = rawget(frame, "blackthornesFold")
    if type(state) == "table" and state.folded then return end
    local width, height = SharedWindow.BaseSize()
    local okW, oldW = pcall(frame.GetWidth, frame)
    local okH, oldH = pcall(frame.GetHeight, frame)
    if okW and okH and oldW == width and oldH == height then return end
    local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
    frame:SetSize(width, height)
    if ok and type(left) == "number" and type(top) == "number" then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    SharedWindow.Fit(frame)
end

local function Place(frame)
    frame:SetScale(Clamp(Read("oneWindowScale")) / 100)
    frame:ClearAllPoints()
    local left, top = Read("oneWindowLeft"), Read("oneWindowTop")
    if type(left) == "number" and type(top) == "number" then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
    SharedWindow.Fit(frame)
end

--- The house size grip below the bottom right corner: drag to scale the
--- window from its top left corner, right-click for the normal size.
local function MakeGrip(frame)
    local Theme = ns.Theme
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -6, -3)
    grip:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
    grip:RegisterForClicks("RightButtonUp")
    Theme.Fill(grip, "panel")
    Theme.Border(grip, "borderLit")
    local dots = {}
    for row = 0, 2 do
        for column = 2 - row, 2 do
            local dot = grip:CreateTexture(nil, "ARTWORK")
            dot:SetSize(3, 3)
            dot:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -3 - (2 - column) * 5, 3 + (2 - row) * 5)
            dot:SetColorTexture(Theme.Unpack("accent"))
            dots[#dots + 1] = dot
        end
    end
    local function Light(on)
        for _, dot in ipairs(dots) do dot:SetColorTexture(Theme.Unpack(on and "accentHi" or "accent")) end
    end
    local function Resize(percent)
        local old = frame:GetScale() or 1
        local ok, left, top = pcall(function() return frame:GetLeft(), frame:GetTop() end)
        frame:SetScale(percent / 100)
        if ok and type(left) == "number" and type(top) == "number" then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / (percent / 100), top * old / (percent / 100))
        end
        WriteAll("oneWindowScale", percent)
        SharedWindow.Fit(frame)
        -- A size picked by hand wins: docked, it no longer shrinks to fit.
        if hub.docked then hub.sized = true; SharedWindow.Dock(true) else SavePlace(frame) end
    end
    grip:SetScript("OnEnter", function() Light(true) end)
    grip:SetScript("OnLeave", function() if not grip.dragging then Light(false) end end)
    grip:SetScript("OnClick", function() Resize(100) end)
    grip:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        self.dragging = true
        local startX = GetCursorPosition()
        -- From the saved size, not the size shown: docked, it may be
        -- shrunk to fit, and starting there would save the shrunk size.
        local startScale = Clamp(Read("oneWindowScale"))
        local width = SharedWindow.WIDTH
        self:SetScript("OnUpdate", function()
            local x = GetCursorPosition()
            local ui = UIParent:GetEffectiveScale() or 1
            local grow = ((x - startX) / ui) / width * 100
            Resize(Clamp(math.floor(startScale + grow + 0.5)))
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        Light(self:IsMouseOver())
    end)
    return grip
end

function SharedWindow.Build()
    if hub.frame then return hub.frame end
    if not IsDrawer() or not CreateFrame or not UIParent then return nil end
    local Theme = ns.Theme

    local frame = CreateFrame("Frame", "BlackthornesOneWindow", UIParent)
    frame:SetSize(SharedWindow.WIDTH, SharedWindow.HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    -- While the player drags it, nothing places it (SharedWindow.Dragging):
    -- the watcher below put it back beside the game's window mid-drag, so
    -- it snapped back under the cursor (players saw it at the profession
    -- window, 2026-11-17).
    frame:SetScript("OnDragStart", function(self)
        hub.dragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        hub.dragging = nil
        -- Moved while docked, it keeps that spot beside this game window
        -- (SharedWindow.Dropped); its own place is kept for when the game's
        -- window closes.
        if not hub.docked then
            SavePlace(self)
        else
            SharedWindow.Dropped(self)
        end
    end)
    frame:Hide()
    Theme.Fill(frame, "window")

    -- The house frame: gold rim, the name on a plate, the red close gem and,
    -- left of it, the gold fold gem.
    if ns.Titanforged and ns.Titanforged.Dress then
        local ok, trim = pcall(ns.Titanforged.Dress, ns.Titanforged, frame, {
            title = PLATE,
            close = function() frame:Hide() end,
        })
        if ok and type(trim) == "table" then
            frame.trim = trim
            if ns.Titanforged.Reach and frame.SetClampRectInsets then
                local left, right, top, bottom = ns.Titanforged.Reach(trim)
                frame:SetClampRectInsets(-left, right, top, -bottom)
            end
        end
    else
        Theme.Border(frame, "borderLit")
    end
    if ns.FoldWindow and ns.FoldWindow.Add and rawget(frame, "trim") then
        pcall(ns.FoldWindow.Add, ns.FoldWindow, frame, {})
    end
    -- And left of that, the swap gem: it splits the addons back into their
    -- own windows (SharedWindow.AddSwap).
    if rawget(frame, "trim") then pcall(SharedWindow.AddSwap, frame, nil) end

    -- The rail down the left side, and the area the picked addon's pages fill.
    local rail = CreateFrame("Frame", nil, frame)
    rail.buttons = {}
    frame.rail = rail

    local area = CreateFrame("Frame", nil, frame)
    frame.area = area
    SharedWindow.Lay(frame, false)

    frame.grip = MakeGrip(frame)

    -- While a game window is open, look now and then that this one still
    -- sits beside it: the game lays its window out a moment late, and a
    -- page that narrows the window after it was placed left it where the
    -- screen's edge had pulled it, over the game's window. Only while shown.
    local watch = CreateFrame("Frame", nil, frame)
    watch.wait = 0
    watch:SetScript("OnUpdate", function(self, elapsed)
        if not hub.place then return end
        self.wait = (self.wait or 0) - (elapsed or 0)
        if self.wait > 0 then return end
        self.wait = SharedWindow.KEEP_EVERY
        SharedWindow.Keep()
    end)
    frame.watch = watch

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BlackthornesOneWindow")
    end
    frame:SetScript("OnHide", function()
        hub.dragging = nil
        -- Closed by the player while a game window is open (its close gem,
        -- Escape, which closes the vendor too): it stays closed when that
        -- game window goes, never coming back by itself (a player saw it
        -- open as a vendor closed, 2026-11-01).
        if hub.place and not hub.byItself then
            hub.back = nil
            hub.prior = nil
        end
        if hub.current and type(hub.current.host) == "table" and type(hub.current.host.leave) == "function" then
            pcall(hub.current.host.leave)
        end
        hub.current = nil
    end)

    hub.frame = frame
    Place(frame)
    return frame
end

--- Lay the rail down the left side, or, docked, as a row along the top.
--- The area keeps its size either way, so the pages in it stay as they are:
--- the window loses the rail's width and gains the row's height.
--- `noRow` (docked only) leaves the row out, the area taking its place.
function SharedWindow.Lay(frame, docked, noRow)
    local rail, area = frame.rail, frame.area
    rail:ClearAllPoints()
    area:ClearAllPoints()
    if docked and noRow then
        rail:Hide()
        area:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE, -TOP)
    elseif docked then
        rail:Show()
        rail:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE, -TOP)
        rail:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -EDGE, -TOP)
        rail:SetHeight(SharedWindow.ROW_HEIGHT)
        area:SetPoint("TOPLEFT", rail, "BOTTOMLEFT", 0, -EDGE)
    else
        rail:Show()
        rail:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE, -TOP)
        rail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", EDGE, EDGE)
        rail:SetWidth(SharedWindow.RAIL_WIDTH)
        area:SetPoint("TOPLEFT", rail, "TOPRIGHT", EDGE, 0)
    end
    area:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -EDGE, EDGE)
    frame.docked = docked and true or false
end

--------------------------------------------------------------------------------
-- The rail
--------------------------------------------------------------------------------

local function PaintButton(button, hovered)
    local Theme = ns.Theme
    local picked = button.entry ~= nil and button.entry == hub.current
    local key = picked and "glassActive" or (hovered and "glassHover" or (button.index % 2 == 1 and "glass" or "glassAlt"))
    button.fill:SetColorTexture(Theme.Unpack(key))
    if picked or hovered then button.edge:Show() else button.edge:Hide() end
    button.edge:SetColorTexture(Theme.Unpack(picked and "accentHi" or "accent"))
    button.name:SetTextColor(Theme.Unpack(picked and "accentHi" or "muted"))
end

local function MakeButton(rail, index)
    local Theme = ns.Theme
    local button = CreateFrame("Button", nil, rail)
    button:SetSize(SharedWindow.RAIL_BUTTON, SharedWindow.RAIL_BUTTON)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.index = index

    button.fill = button:CreateTexture(nil, "BACKGROUND")
    button.fill:SetAllPoints()

    local line = button:CreateTexture(nil, "BORDER")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetColorTexture(Theme.Unpack("border", 0.6))

    button.edge = button:CreateTexture(nil, "ARTWORK")
    button.edge:SetWidth(2)
    button.edge:SetPoint("TOPLEFT")
    button.edge:SetPoint("BOTTOMLEFT")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(ICON, ICON)
    button.icon:SetPoint("TOP", 0, -10)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.name = Theme.CreateLabel(button, "small", "muted", "CENTER")
    button.name:SetWordWrap(true)
    button.name:SetPoint("TOPLEFT", button.icon, "BOTTOMLEFT", -16, -4)
    button.name:SetPoint("TOPRIGHT", button.icon, "BOTTOMRIGHT", 16, -4)

    button:SetScript("OnEnter", function(self)
        PaintButton(self, true)
        -- In the row along the top only the emblem shows: the name is the hover.
        local tip = rawget(_G, "GameTooltip")
        if hub.docked and tip and self.entry then
            pcall(function()
                tip:SetOwner(self, "ANCHOR_BOTTOM")
                tip:SetText(self.entry.name or self.entry.key)
                tip:Show()
            end)
        end
    end)
    button:SetScript("OnLeave", function(self)
        PaintButton(self, false)
        local tip = rawget(_G, "GameTooltip")
        if tip and tip.GetOwner and tip:GetOwner() == self then pcall(tip.Hide, tip) end
    end)
    button:SetScript("OnClick", function(self, mouseButton)
        local entry = self.entry
        if not entry then return end
        if mouseButton == "RightButton" and type(entry.settings) == "function" then
            pcall(entry.settings)
        else
            SharedWindow.Pick(entry.key)
        end
    end)
    return button
end

--- A button for each addon that joined, in rail order.
function SharedWindow.FillRail()
    local frame = hub.frame
    if not frame then return end
    local rail = frame.rail
    local docked = hub.docked
    local size = docked and SharedWindow.ROW_BUTTON or SharedWindow.RAIL_BUTTON
    local icon = docked and SharedWindow.ROW_ICON or ICON
    local step = 0
    local list = SharedWindow.Entries()
    for index, entry in ipairs(list) do
        local button = rail.buttons[index] or MakeButton(rail, index)
        rail.buttons[index] = button
        button.entry = entry
        button:SetSize(size, size)
        button.icon:SetSize(icon, icon)
        button.icon:ClearAllPoints()
        button.icon:SetTexture(entry.icon)
        button.name:SetText(entry.name or entry.key)
        button:ClearAllPoints()
        if docked then
            button.icon:SetPoint("CENTER")
            button.name:Hide()
            button:SetPoint("LEFT", rail, "LEFT", step, 0)
        else
            button.icon:SetPoint("TOP", 0, -10)
            button.name:Show()
            button:SetPoint("TOP", rail, "TOP", 0, -step)
        end
        PaintButton(button, false)
        button:Show()
        step = step + size + (docked and 6 or 4)
    end
    for index = #list + 1, #rail.buttons do rail.buttons[index]:Hide() end
    SharedWindow.PlaceGear(rail, docked, size, icon, step)
end

--- The addon whose Settings show the All Addons page: the one showing now
--- when it can, else the first on the rail that can.
function SharedWindow.AllAddonsEntry()
    if hub.current and type(hub.current.allAddons) == "function" then return hub.current end
    for _, entry in ipairs(SharedWindow.Entries()) do
        if type(entry.allAddons) == "function" then return entry end
    end
    return nil
end

--- Open the settings every Blackthornes addon shares.
function SharedWindow.OpenAllAddons()
    local entry = SharedWindow.AllAddonsEntry()
    if not entry then return false end
    if hub.current ~= entry and SharedWindow.On() then SharedWindow.Pick(entry.key) end
    return pcall(entry.allAddons)
end

--- The gear: at the foot of the rail, or the end of the row when docked.
--- Shown while any addon has the All Addons page.
function SharedWindow.PlaceGear(rail, docked, size, icon, step)
    local gear = rawget(rail, "gear")
    if not SharedWindow.AllAddonsEntry() then
        if gear then gear:Hide() end
        return
    end
    if not gear then
        gear = MakeButton(rail, 0)
        gear.gear = true
        gear:SetScript("OnClick", function() SharedWindow.OpenAllAddons() end)
        gear:SetScript("OnEnter", function(self)
            PaintButton(self, true)
            local tip = rawget(_G, "GameTooltip")
            if hub.docked and tip then
                pcall(function()
                    tip:SetOwner(self, "ANCHOR_BOTTOM")
                    tip:SetText(L["All Addons"])
                    tip:Show()
                end)
            end
        end)
        rail.gear = gear
    end
    gear.entry = nil
    gear:SetSize(size, size)
    gear.icon:SetSize(icon, icon)
    gear.icon:ClearAllPoints()
    gear.icon:SetTexture(SharedWindow.GEAR_ICON)
    gear.name:SetText(L["All Addons"])
    gear:ClearAllPoints()
    if docked then
        gear.icon:SetPoint("CENTER")
        gear.name:Hide()
        gear:SetPoint("LEFT", rail, "LEFT", step, 0)
    else
        gear.icon:SetPoint("TOP", 0, -10)
        gear.name:Show()
        gear:SetPoint("BOTTOM", rail, "BOTTOM", 0, 0)
    end
    PaintButton(gear, false)
    gear:Show()
end

--------------------------------------------------------------------------------
-- Docking beside the game's windows
--------------------------------------------------------------------------------

function SharedWindow.Now()
    local GetTime = rawget(_G, "GetTime")
    if type(GetTime) == "function" then
        local ok, now = pcall(GetTime)
        if ok and type(now) == "number" then return now end
    end
    return 0
end

local function InFight()
    local fn = rawget(_G, "InCombatLockdown")
    if type(fn) ~= "function" then return false end
    local ok, fighting = pcall(fn)
    return ok and fighting and true or false
end

--- The game's window for the place open now, read only, or nil.
local function GameFrame()
    local place = hub.place and SharedWindow.PLACES[hub.place]
    if not place then return nil end
    for _, name in ipairs(place.frames) do
        local game = rawget(_G, name)
        if type(game) == "table" then
            local ok, shown = pcall(game.IsShown, game)
            if ok and shown then return game end
        end
    end
    return nil
end

--- True while the window sits beside one of the game's windows.
function SharedWindow.Docked()
    return hub.docked == true
end

--- The one window while it is docked and up, else nil. Another panel that
--- sits beside the game's window (Tradeskills' mail panel, Butler's buy
--- box) goes beside this instead, so the two never cover each other.
function SharedWindow.DockedFrame()
    local frame = hub.frame
    if not (hub.docked and frame) then return nil end
    local ok, shown = pcall(frame.IsShown, frame)
    if ok and shown then return frame end
    return nil
end

--- Call fn() each time the window docks, moves while docked or undocks.
--- Kept on the shared table, so whichever copy draws calls it.
function SharedWindow.Watch(fn)
    if type(fn) ~= "function" then return end
    hub.watchers = hub.watchers or {}
    hub.watchers[#hub.watchers + 1] = fn
end

local function Tell()
    for _, fn in ipairs(hub.watchers or {}) do pcall(fn) end
end

--- The place open now ("auction", "mail", "vendor", "trainer", "bank",
--- "stable", "character" or "profession"), or nil.
function SharedWindow.Place()
    return hub.place
end

--- True when, docked here, the row of addon buttons shows: always, but
--- where only one addon is needed and that one is showing.
function SharedWindow.RowShown()
    local place = hub.place and SharedWindow.PLACES[hub.place]
    if place and place.only and hub.current and hub.current.key == place.only then
        return false
    end
    return true
end

local function RowRoom()
    return SharedWindow.ROW_HEIGHT + EDGE
end

--- Docked, the row comes or goes as the addon shown changes (another
--- addon picked at the auction house brings the row back). The area keeps
--- its size: the window gains or loses the row's height.
function SharedWindow.Refit()
    local frame = hub.frame
    if not (frame and hub.docked) then return end
    local row = SharedWindow.RowShown()
    if row == hub.row then return end
    local _, height = SharedWindow.FullSize(frame)
    if height then
        frame:SetHeight(height + (row and RowRoom() or -RowRoom()))
    end
    hub.row = row
    SharedWindow.Fit(frame)
    SharedWindow.Lay(frame, true, not row)
end

--- How wide the screen is in screen pixels, or nil when the client won't say.
local function ScreenWidth()
    local ok, width = pcall(function() return UIParent:GetWidth() * UIParent:GetEffectiveScale() end)
    if ok and type(width) == "number" and width > 0 then return width end
    return nil
end

-- The game's bags, read only: open on the right of the game's window they
-- take that room, so the window goes left of it (the mockup's vendor).
SharedWindow.BAG_FRAMES = { "ContainerFrameCombinedBags" }
for i = 1, 13 do SharedWindow.BAG_FRAMES[#SharedWindow.BAG_FRAMES + 1] = "ContainerFrame" .. i end

--- Where the room right of the game's window ends, in screen pixels: the
--- screen's edge, or the left edge of the nearest open bag past it.
local function RightEdge(gameRight, screen)
    if not screen then return nil end
    local edge = screen
    for _, name in ipairs(SharedWindow.BAG_FRAMES) do
        local bag = rawget(_G, name)
        if type(bag) == "table" then
            local ok, shown, left, scale = pcall(function()
                return bag:IsShown(), bag:GetLeft(), bag:GetEffectiveScale()
            end)
            if ok and shown and type(left) == "number" and type(scale) == "number" then
                local x = left * scale
                if x >= gameRight - 1 and x < edge then edge = x end
            end
        end
    end
    return edge
end

--- Which side of the game's window the one window goes, and the scale it
--- takes there (2026-11-16, the owner said build it): the right when it
--- fits, as before; else the left when that fits (bags open on the
--- right); else the side with more room, scaled down to fit the gap, never
--- under SHRINK_LEAST of its own size (it keeps its size and overlaps
--- then). Once resized by hand while docked it never shrinks (`sized`).
--- All in screen pixels. Gives side ("right" or "left")
--- and the effective scale to use.
function SharedWindow.PickSide(gameLeft, gameRight, width, ours, reach, screen, sized)
    reach = reach or 0
    local need = (width + reach) * ours + SharedWindow.DOCK_GAP
    if not screen or type(gameLeft) ~= "number" then return "right", ours end
    local rightRoom = screen - gameRight
    local leftRoom = gameLeft
    if rightRoom >= need then return "right", ours end
    if leftRoom >= need then return "left", ours end
    local side = leftRoom > rightRoom and "left" or "right"
    if sized then return side, ours end
    local room = math.max(leftRoom, rightRoom) - SharedWindow.DOCK_GAP
    local fit = room / (width + reach)
    -- Never much smaller than the player's own size: when it would be,
    -- it keeps its size and overlaps rather than shrink out of reading.
    local least = math.max(ours * SharedWindow.SHRINK_LEAST,
        ours * SharedWindow.DOCK_SCALE_MIN / Clamp(Read("oneWindowScale")))
    if fit < least then return side, ours end
    if fit > ours then fit = ours end
    return side, fit
end

--- Put the window beside the game's window, by screen position: its left
--- edge (portrait and all) just past the game's right edge, the tops level,
--- or on the left when only that side has room (see PickSide).
local function Beside(frame, game)
    local ok, left, right, top, scale = pcall(function()
        return game:GetLeft(), game:GetRight(), game:GetTop(), game:GetEffectiveScale()
    end)
    if not ok or type(right) ~= "number" or type(top) ~= "number" then return false end
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    -- Measured at the window's own size each time, so it grows back when
    -- the room comes back; Place puts the saved size back on undocking.
    pcall(frame.SetScale, frame, Clamp(Read("oneWindowScale")) / 100)
    local okOurs, ours = pcall(frame.GetEffectiveScale, frame)
    if not okOurs or type(ours) ~= "number" or ours <= 0 then ours = 1 end
    local reach = 0
    local trim = rawget(frame, "trim")
    if trim and ns.Titanforged and ns.Titanforged.Reach then
        local okReach, edge = pcall(ns.Titanforged.Reach, trim)
        if okReach and type(edge) == "number" then reach = edge end
    end
    frame:ClearAllPoints()
    local spots = Read("oneWindowDockSpots")
    local spot = type(spots) == "table" and hub.place and spots[hub.place]
    if type(spot) == "table" and type(spot.x) == "number" and type(spot.y) == "number" then
        -- Dragged here by hand before: the same spot from the game's window.
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            (right * scale + spot.x) / ours, (top * scale + spot.y) / ours)
        return true
    end
    local width = SharedWindow.FullSize(frame)
    local side, fit = "right", ours
    if type(width) == "number" and width > 0 then
        side, fit = SharedWindow.PickSide(type(left) == "number" and left * scale or nil,
            right * scale, width, ours, reach, RightEdge(right * scale, ScreenWidth()), hub.sized)
    end
    if fit < ours then
        local okScale, own = pcall(frame.GetScale, frame)
        if okScale and type(own) == "number" and own > 0 then
            pcall(frame.SetScale, frame, own * fit / ours)
            ours = fit
        end
    end
    if side == "left" then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            math.max(0, left * scale / ours - width - reach - SharedWindow.DOCK_GAP / ours), top * scale / ours)
    else
        local x = right * scale / ours + reach + SharedWindow.DOCK_GAP
        -- Too wide for the gap: slide back over the game's window, never
        -- off the screen's right edge.
        local screen = ScreenWidth()
        if screen and type(width) == "number" then
            local last = screen / ours - width
            if x > last then x = math.max(0, last) end
        end
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, top * scale / ours)
    end
    return true
end

--- Dragged while docked: keep where it was dropped, measured from the
--- game window's top right corner in screen pixels, for this place
--- (auction, mail, vendor, trainer). Every save gets a fresh table.
local function SaveDockSpot(frame, game)
    if not (hub.place and game) then return end
    local ok, left, top, ours, right, gtop, scale = pcall(function()
        return frame:GetLeft(), frame:GetTop(), frame:GetEffectiveScale(),
            game:GetRight(), game:GetTop(), game:GetEffectiveScale()
    end)
    if not ok then return end
    for _, v in ipairs({ left, top, ours, right, gtop, scale }) do
        if type(v) ~= "number" then return end
    end
    if ours <= 0 then ours = 1 end
    if scale <= 0 then scale = 1 end
    local spots = {}
    local old = Read("oneWindowDockSpots")
    if type(old) == "table" then
        for key, value in pairs(old) do spots[key] = value end
    end
    spots[hub.place] = { x = left * ours - right * scale, y = top * ours - gtop * scale }
    WriteAll("oneWindowDockSpots", spots)
end

--- A number as the key holds it: to a tenth, so the client's last-digit
--- wobble in a frame's edges never reads as a move.
local function Tenth(value)
    if type(value) ~= "number" then return tostring(value) end
    return string.format("%.1f", value)
end

--- Where the game's window and this one stand and how wide this one is:
--- when any of it moves, the window is placed beside it again.
local function Spot(frame, game)
    local ok, key = pcall(function()
        return table.concat({ tostring(game), Tenth(game:GetRight()), Tenth(game:GetTop()),
            Tenth(game:GetEffectiveScale()), Tenth(frame:GetWidth()),
            Tenth(frame:GetScale()), Tenth(RightEdge(game:GetRight() * game:GetEffectiveScale(),
            ScreenWidth())) }, ":")
    end)
    return ok and key or nil
end

--- True while the player is dragging the window. A drag whose stop was
--- never heard (the button let go off the game's window) ends here once
--- the mouse button is up.
function SharedWindow.Dragging()
    if not hub.dragging then return false end
    local down = rawget(_G, "IsMouseButtonDown")
    if type(down) == "function" then
        local ok, held = pcall(down, "LeftButton")
        if ok and not held then
            hub.dragging = nil
            return false
        end
    end
    return true
end

--- Dock beside the game's window open now. `again` only places it anew
--- (after a resize). Nothing moves in a fight.
function SharedWindow.Dock(again)
    local frame = hub.frame
    if not (frame and frame:IsShown() and hub.place) or InFight() then return false end
    if SharedWindow.Dragging() then return false end
    local game = GameFrame()
    if not game then return false end
    if not hub.docked then
        hub.docked = true
        hub.row = SharedWindow.RowShown()
        local width, height = SharedWindow.FullSize(frame)
        if width and height then
            frame:SetSize(width - SharedWindow.RAIL_WIDTH - EDGE,
                height + (hub.row and RowRoom() or 0))
            SharedWindow.Fit(frame)
        end
        SharedWindow.Lay(frame, true, not hub.row)
        SharedWindow.FillRail()
    elseif not again then
        return true
    end
    local placed = Beside(frame, game)
    hub.spot = placed and Spot(frame, game) or nil
    Tell()
    return placed
end

--- Dropped by hand while docked: remember the spot for this place.
function SharedWindow.Dropped(frame)
    frame = frame or hub.frame
    if not (frame and hub.docked) then return end
    local game = GameFrame()
    if not game then return end
    SaveDockSpot(frame, game)
    hub.spot = Spot(frame, game)
end

--- Every window back where it first stood: the one window's own place and
--- its spots beside the game's windows go (its size stays), then every
--- addon's own windows (SharedWindow.AddSpotReset). Nothing else changes.
function SharedWindow.ResetSpots()
    WriteAll("oneWindowDockSpots", nil)
    WriteAll("oneWindowLeft", nil)
    WriteAll("oneWindowTop", nil)
    local frame = hub.frame
    if frame and not InFight() then
        if hub.docked then SharedWindow.Dock(true)
        else pcall(Place, frame) end
    end
end

--- Each addon signs up what puts its own windows back; Set Default in any
--- addon runs them all, each in a pcall.
function SharedWindow.AddSpotReset(name, fn)
    if type(name) ~= "string" or type(fn) ~= "function" then return end
    hub.spotResets = hub.spotResets or {}
    hub.spotResets[name] = fn
end

--- A small window of any addon remembers where it was dragged (a player
--- asked, the owner said build it, 2026-11-12): kept account wide in
--- every save as windowSpots[key] = { x, y }, its top left in screen
--- pixels; laid again each time it shows, kept on the screen. Its first
--- place is noted so Set Default can put it back.
local function PutAt(frame, spot)
    local ok, scale = pcall(frame.GetEffectiveScale, frame)
    if not (ok and type(scale) == "number" and scale > 0) then scale = 1 end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", spot.x / scale, spot.y / scale)
end

local function KeptSpot(key)
    local spots = Read("windowSpots")
    local spot = type(spots) == "table" and spots[key]
    if type(spot) == "table" and type(spot.x) == "number" and type(spot.y) == "number" then
        return spot
    end
    return nil
end

function SharedWindow.KeepSpot(frame, key)
    if type(frame) ~= "table" or type(key) ~= "string" then return end
    hub.kept = hub.kept or {}
    if hub.kept[key] and hub.kept[key].frame == frame then return end
    local first = { pcall(frame.GetPoint, frame, 1) }
    hub.kept[key] = { frame = frame, first = first[1] and first[2] and
        { first[2], first[3], first[4], first[5], first[6] } or nil }
    if frame.SetClampedToScreen then pcall(frame.SetClampedToScreen, frame, true) end
    if frame.SetMovable then pcall(frame.SetMovable, frame, true) end
    local function Lay()
        if InFight() then return end
        local spot = KeptSpot(key)
        if spot then pcall(PutAt, frame, spot) end
    end
    if frame.HookScript then
        frame:HookScript("OnShow", function()
            Lay()
            -- A window that places itself after showing is laid again.
            if C_Timer and C_Timer.After then C_Timer.After(0, Lay) end
        end)
    end
    -- Saved however the window was dragged: by itself, or by a title bar
    -- that moves it.
    local function Save()
        local ok, left, top, scale = pcall(function()
            return frame:GetLeft(), frame:GetTop(), frame:GetEffectiveScale()
        end)
        if not (ok and left and top and scale) then return end
        local spots, old = {}, Read("windowSpots")
        if type(old) == "table" then for k, v in pairs(old) do spots[k] = v end end
        spots[key] = { x = left * scale, y = top * scale }
        WriteAll("windowSpots", spots)
    end
    -- A drag script can hold the game's StopMovingOrSizing from before the
    -- hook, so the drag stop is heard too; saving twice does no harm.
    if type(hooksecurefunc) == "function" and type(frame.StopMovingOrSizing) == "function" then
        pcall(hooksecurefunc, frame, "StopMovingOrSizing", Save)
    end
    if frame.HookScript then frame:HookScript("OnDragStop", Save) end
    local ok, shown = pcall(frame.IsShown, frame)
    if ok and shown then Lay() end
end

function SharedWindow.ResetAllSpots()
    SharedWindow.ResetSpots()
    WriteAll("windowSpots", nil)
    if not InFight() then
        for _, kept in pairs(hub.kept or {}) do
            local first = kept.first
            if first then
                pcall(function()
                    kept.frame:ClearAllPoints()
                    kept.frame:SetPoint(first[1], first[2], first[3], first[4], first[5])
                end)
            end
        end
    end
    local names = {}
    for name in pairs(hub.spotResets or {}) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do pcall(hub.spotResets[name]) end
end

--- While a game window is open: up but not docked yet (the game showed
--- its window late), dock; docked, place it beside again when the game's
--- window moved or this one changed width or size. Dragged there by
--- hand, it stays. Nothing moves in a fight.
function SharedWindow.Keep()
    local frame = hub.frame
    if not (frame and hub.place) or InFight() then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    if not (ok and shown) then return false end
    if SharedWindow.Dragging() then return false end
    if not hub.docked then return SharedWindow.Dock() end
    local game = GameFrame()
    if not game or Spot(frame, game) == hub.spot then return false end
    return SharedWindow.Dock(true)
end

--- Back to its own place, with the rail down the left side.
function SharedWindow.Undock()
    local frame = hub.frame
    if not (frame and hub.docked) then return end
    hub.docked = false
    hub.spot = nil
    hub.sized = nil
    local row = hub.row ~= false
    hub.row = nil
    local width, height = SharedWindow.FullSize(frame)
    if width and height then
        frame:SetSize(width + SharedWindow.RAIL_WIDTH + EDGE,
            height - (row and RowRoom() or 0))
    end
    SharedWindow.Lay(frame, false)
    Place(frame)
    SharedWindow.FillRail()
    Tell()
end

--- Watch the place's coming and going frames (an open letter), once each:
--- shown or hidden, the docked window takes its place beside the one shown.
local function Follow(place)
    hub.followed = hub.followed or {}
    for _, name in ipairs(place.follow or {}) do
        local game = rawget(_G, name)
        if not hub.followed[name] and type(game) == "table" and type(game.HookScript) == "function" then
            local function Again()
                if not hub.docked then return end
                local drawer = SharedWindow.Drawer()
                local api = drawer and drawer.api or SharedWindow
                pcall(api.Dock, true)
            end
            local okShow = pcall(game.HookScript, game, "OnShow", Again)
            local okHide = pcall(game.HookScript, game, "OnHide", Again)
            if okShow and okHide then hub.followed[name] = true end
        end
    end
end

--- The addon `key`'s place is for (`prefer`), or nil: only when it has
--- moved in and, if its host has `wants(place)`, that says yes (Butler's
--- "open at vendors" box). A host whose answer fails is left alone.
function SharedWindow.Preferred(key)
    local place = SharedWindow.PLACES[key]
    local want = place and place.prefer
    if not (want and SharedWindow.Hosts(want)) then return nil end
    local entry = hub.entries[want]
    local wants = entry.host.wants
    if type(wants) == "function" then
        local ok, yes = pcall(wants, key)
        if not (ok and yes) then return nil end
    end
    return entry
end

--- One of the game's windows opened.
function SharedWindow.Arrived(key)
    if not SharedWindow.PLACES[key] then return end
    -- Two can be open at once (the character sheet at a vendor): each is
    -- kept with when it opened, and the newest is the one docked beside.
    hub.opened = hub.opened or {}
    hub.openCount = (hub.openCount or 0) + 1
    hub.opened[key] = hub.openCount
    local was = hub.place
    hub.place = key
    Follow(SharedWindow.PLACES[key])
    local frame = hub.frame
    if hub.docked and was ~= key and frame and frame:IsShown() then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() SharedWindow.Dock(true) end)
        else
            SharedWindow.Dock(true)
        end
        return
    end
    if not (frame and frame:IsShown()) or hub.docked then return end
    -- Up already: what it showed before is what it goes back to. An addon
    -- that opened it a moment ago (Butler at the vendor) left a note of
    -- what was there before it.
    local prior = hub.prior
    if prior and SharedWindow.Now() - (prior.at or 0) <= SharedWindow.PRIOR_FOR then
        hub.back = prior.open and { key = prior.key, open = true } or nil
    else
        hub.back = { key = hub.current and hub.current.key, open = true }
    end
    -- Up on another addon at a place that is for one (Butler at the vendor;
    -- a player saw Farmer come up there instead, 2026-11-17): turn to it.
    -- hub.back still takes it back to the addon open before.
    local preferred = SharedWindow.Preferred(key)
    if preferred and hub.current ~= preferred then SharedWindow.Pick(preferred.key) end
    -- The game shows its window on the same event: place ours a moment after.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() SharedWindow.Dock() end)
    else
        SharedWindow.Dock()
    end
end

--- The game's window closed: back to its own place, and, a moment later,
--- back to the addon that was open before.
function SharedWindow.Left(key)
    if hub.opened then hub.opened[key] = nil end
    if hub.place ~= key then return end
    hub.place = nil
    -- Another game window still open: dock beside that one instead.
    local newest, best = nil, -1
    for other, order in pairs(hub.opened or {}) do
        if order > best then newest, best = other, order end
    end
    if newest then
        hub.place = newest
        if hub.docked then
            if not SharedWindow.Dock(true) then SharedWindow.Undock() end
        end
        return
    end
    local back = hub.back
    hub.back = nil
    if hub.docked then SharedWindow.Undock() end
    if not (back and back.open and back.key and SharedWindow.On()) then return end
    local function Return()
        if hub.place then return end
        local frame = hub.frame
        if frame and frame:IsShown() then
            if not (hub.current and hub.current.key == back.key) then SharedWindow.Pick(back.key) end
        else
            SharedWindow.Open(back.key)
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(SharedWindow.BACK_WAIT, Return)
    else
        Return()
    end
end

--------------------------------------------------------------------------------
-- Shelves for small pieces (the owner said build it, 2026-11-16, from the
-- Pets and Tradeskills UI cleanup mockups). Before, every addon picked its
-- own first spot for its arrow, notices, bars and cards, and several were
-- the same spot. Now a piece the player has not dragged asks a shelf for
-- the next free place: the top shelf runs down from the top middle, the
-- right shelf down the right side, left of the game's quest list. A dragged
-- piece keeps its spot and leaves the shelf alone; no saved key changes.
--
-- The board is shared by every copy in `_G.BlackthornesShelves`, so
-- pieces from all five addons line up together. Each piece joins with
--   SharedWindow.ShelfJoin(key, { shelf = "top" or "right", order = n,
--       frame = f, free = fn, shown = fn, height = fn, place = fn })
-- `free()` is true while it sits in its first spot (not dragged);
-- `place()` is called to lay it again when a piece above it comes, goes or
-- changes height. `frame`, `shown` and `height` are optional: without a
-- frame, `shown` and `height` (in UIParent units) say how much room it
-- takes (the notice stack).
--------------------------------------------------------------------------------

SharedWindow.SHELVES = {
    top = { anchor = "TOP", x = 0, y = -120, gap = 8 },
    right = { anchor = "TOPRIGHT", x = -40, y = -250, gap = 8 },
}
-- Pieces on each shelf, in order. Pieces that come and go a lot (notices)
-- sit last, so nothing above them jumps when one shows.
SharedWindow.SHELF_ORDER = {
    goldbar = 10, arrow = 20, xpbar = 30, shards = 40, sellmarked = 50, mailtally = 55,
    goldgoal = 60, upgrade = 70, notice = 90,
    auctions = 10, travel = 20, upgrades = 30, upgradequest = 40,
}
-- The game's quest list, read only: the right shelf stands left of it.
SharedWindow.QUEST_LIST = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }

local shelves = rawget(_G, "BlackthornesShelves")
if type(shelves) ~= "table" then
    shelves = {}
    _G.BlackthornesShelves = shelves
end
shelves.pieces = shelves.pieces or {}

local function ParentScale()
    local ok, scale = pcall(UIParent.GetEffectiveScale, UIParent)
    if ok and type(scale) == "number" and scale > 0 then return scale end
    return 1
end

local function PieceShown(piece)
    if type(piece.shown) == "function" then
        local ok, shown = pcall(piece.shown)
        return ok and shown and true or false
    end
    local frame = piece.frame
    if type(frame) ~= "table" then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown and true or false
end

local function PieceFree(piece)
    if type(piece.free) ~= "function" then return true end
    local ok, free = pcall(piece.free)
    return ok and free and true or false
end

--- How tall a piece stands, in UIParent units.
local function PieceHeight(piece)
    if type(piece.height) == "function" then
        local ok, height = pcall(piece.height)
        if ok and type(height) == "number" then return height end
    end
    local frame = piece.frame
    if type(frame) ~= "table" then return 0 end
    local ok, height, scale = pcall(function() return frame:GetHeight(), frame:GetEffectiveScale() end)
    if not (ok and type(height) == "number") then return 0 end
    if type(scale) ~= "number" or scale <= 0 then scale = ParentScale() end
    return height * scale / ParentScale()
end

--- Where the right shelf stands across: left of the game's quest list
--- when that shows, else in from the right edge. In UIParent units, from
--- the right edge (so negative).
local function RightShelfX()
    local shelf = SharedWindow.SHELVES.right
    local okW, width = pcall(UIParent.GetWidth, UIParent)
    if not (okW and type(width) == "number" and width > 0) then return shelf.x end
    for _, name in ipairs(SharedWindow.QUEST_LIST) do
        local list = rawget(_G, name)
        if type(list) == "table" then
            local ok, shown, left, scale = pcall(function()
                return list:IsShown(), list:GetLeft(), list:GetEffectiveScale()
            end)
            if ok and shown and type(left) == "number" and type(scale) == "number" then
                local x = left * scale / ParentScale() - width - shelf.gap
                if x < shelf.x then return x end
            end
        end
    end
    return shelf.x
end

--- Join a shelf, or update a piece that joined before (the newest copy's
--- functions win). Gives the piece's first place.
function SharedWindow.ShelfJoin(key, piece)
    if type(key) ~= "string" or type(piece) ~= "table" then return end
    local kind = key:match("^([^%.]+)")
    piece.key = key
    piece.shelf = SharedWindow.SHELVES[piece.shelf] and piece.shelf or "top"
    piece.order = tonumber(piece.order) or SharedWindow.SHELF_ORDER[kind] or 80
    local old = shelves.pieces[key]
    shelves.pieces[key] = piece
    local frame = piece.frame
    if type(frame) == "table" and type(frame.HookScript) == "function"
        and not (old and old.frame == frame and old.hooked) then
        local function Moved() SharedWindow.ShelfChanged(key) end
        pcall(frame.HookScript, frame, "OnShow", Moved)
        pcall(frame.HookScript, frame, "OnHide", Moved)
        pcall(frame.HookScript, frame, "OnSizeChanged", Moved)
        piece.hooked = true
    elseif old and old.hooked and old.frame == frame then
        piece.hooked = true
    end
end

--- The place a piece takes on its shelf: anchor point, x and y, in
--- UIParent units (divide by the piece's own scale before SetPoint).
--- Pieces before it that show and sit in their first spot take room.
function SharedWindow.ShelfSpot(key)
    local piece = shelves.pieces[key]
    local name = piece and piece.shelf or "top"
    local shelf = SharedWindow.SHELVES[name]
    local order = piece and piece.order or 0
    local y = shelf.y
    local list = {}
    for other, entry in pairs(shelves.pieces) do
        if other ~= key and entry.shelf == name then list[#list + 1] = entry end
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)
    for _, entry in ipairs(list) do
        if entry.order > order or (entry.order == order and entry.key > key) then break end
        if PieceShown(entry) and PieceFree(entry) then
            local height = PieceHeight(entry)
            if height > 0 then y = y - height - shelf.gap end
        end
    end
    local x = name == "right" and RightShelfX() or shelf.x
    return shelf.anchor, x, y
end

--- Join and stand at the shelf place in one call, for a piece's "no saved
--- spot" branch. Gives true when placed. `piece.place` is what lays it
--- again later (usually the piece's own restore, which comes back here).
function SharedWindow.ShelfPlace(frame, key, piece)
    if type(frame) ~= "table" or type(key) ~= "string" then return false end
    piece = piece or {}
    piece.frame = piece.frame or frame
    SharedWindow.ShelfJoin(key, piece)
    local point, x, y = SharedWindow.ShelfSpot(key)
    local ok, scale = pcall(frame.GetEffectiveScale, frame)
    if not (ok and type(scale) == "number" and scale > 0) then scale = ParentScale() end
    scale = scale / ParentScale()
    local placed = pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint(point, UIParent, point, x / scale, y / scale)
    end)
    return placed
end

--- Something on a shelf came, went or changed height: lay again every
--- piece after it that sits in its first spot. Put off a moment so a burst
--- lays once, and never in a fight.
function SharedWindow.ShelfChanged(key)
    if shelves.pending then return end
    shelves.pending = true
    local function Lay()
        shelves.pending = nil
        if InFight() then
            shelves.afterFight = true
            return
        end
        SharedWindow.ShelfLay(key)
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, Lay) else Lay() end
end

function SharedWindow.ShelfLay(key)
    local from = key and shelves.pieces[key]
    for other, piece in pairs(shelves.pieces) do
        local after = not from or (piece.shelf == from.shelf and other ~= key
            and (piece.order > from.order or (piece.order == from.order and other > key)))
        if after and type(piece.place) == "function" and PieceShown(piece) and PieceFree(piece) then
            pcall(piece.place)
        end
    end
end

--- One ladder of layers for every addon's frames (Farmer's UI cleanup,
--- 2026-11-16): panels that stay up while you play sit low, pieces that
--- pop up on their own (arrows, notes, the loot feed) in the middle, and
--- windows the player opens on purpose on top. Menus and tooltips are the
--- game's own, above all of them.
SharedWindow.LAYERS = { panel = "LOW", popup = "MEDIUM", window = "DIALOG" }
function SharedWindow.Layer(frame, kind)
    local strata = SharedWindow.LAYERS[kind]
    if type(frame) == "table" and strata and frame.SetFrameStrata then
        pcall(frame.SetFrameStrata, frame, strata)
    end
end

--- Places with no event of their own (the character sheet) are heard by
--- HookScript on the game's frame, read only, once for every copy. A hook
--- set by an older copy is never doubled: the shared table remembers it.
function SharedWindow.HookPlaces()
    hub.hookedPlaces = hub.hookedPlaces or {}
    for key, place in pairs(SharedWindow.PLACES) do
        local name = place.hook
        local game = name and rawget(_G, name)
        if name and not hub.hookedPlaces[name] and type(game) == "table"
            and type(game.HookScript) == "function" then
            local function Act(open)
                local drawer = SharedWindow.Drawer()
                local api = drawer and drawer.api or SharedWindow
                if open then pcall(api.Arrived, key) else pcall(api.Left, key) end
            end
            local okShow = pcall(game.HookScript, game, "OnShow", function() Act(true) end)
            local okHide = pcall(game.HookScript, game, "OnHide", function() Act(false) end)
            if okShow and okHide then hub.hookedPlaces[name] = true end
        end
    end
end
pcall(SharedWindow.HookPlaces)

--------------------------------------------------------------------------------
-- The swap gem (the owner said build it, 2026-11-19, from the mockup): a
-- gold gem left of the fold gem, so a window's gems run swap, fold, close.
-- On the one window it shows two panes side by side and splits the addons
-- back into their own windows; on an addon's own window it shows one pane
-- with a rail line and joins them into the one window. Either way it is the
-- one choice for all five addons, `SetOn`, the same as the "One Window:"
-- box on the All Addons page (which reads it as it shows). No new setting
-- and no new saved key.
--
-- Only real windows get it: the one window and the windows an addon lays
-- into it, each signed up with `SharedWindow.AddSwap(frame, key)` after its
-- fold gem. Floating arrows, bars and trackers do not.
--
-- A host may give three more calls for the swap, each optional:
--   tab()      the tab showing now, or nil
--   show(tab)  open on that tab (nil: where it would open anyway), in the
--              one window or its own as the choice now stands
--   hide()     close its own windows
-- Without `show` the swap falls back to `open` (split) or `Open` (join).
--------------------------------------------------------------------------------

SharedWindow.SWAP_GEM = 22
SharedWindow.SWAP_GAP = 2

local SWAP_MEDIA = ([[Interface\AddOns\%s\Media\Frame\]]):format(tostring(ADDON))
local SWAP_INK = { 0.165, 0.110, 0.024 }
local SWAP_GOLD = { 0.910, 0.784, 0.451 }
-- How thick the panes' lines are drawn on the gem's face.
local SWAP_LINE = 1.5

local function Width(object)
    if not object then return nil end
    local ok, width = pcall(object.GetWidth, object)
    if ok and type(width) == "number" and width > 0 then return width end
    return nil
end

-- One ink line on the gem's face, its top left corner `x`, `y` from the
-- middle (y up).
local function SwapInk(button, x, y, width, height)
    local ink = button:CreateTexture(nil, "OVERLAY", nil, 2)
    ink:SetColorTexture(SWAP_INK[1], SWAP_INK[2], SWAP_INK[3], 1)
    ink:SetSize(width, height)
    ink:SetPoint("TOPLEFT", button, "CENTER", x, y)
    return ink
end

-- A pane: the outline of a box.
local function SwapPane(button, x, y, width, height, glyph)
    glyph[#glyph + 1] = SwapInk(button, x, y, width, SWAP_LINE)
    glyph[#glyph + 1] = SwapInk(button, x, y - height + SWAP_LINE, width, SWAP_LINE)
    glyph[#glyph + 1] = SwapInk(button, x, y, SWAP_LINE, height)
    glyph[#glyph + 1] = SwapInk(button, x + width - SWAP_LINE, y, SWAP_LINE, height)
end

--- The gold gem with its glow and a lit copy for the mouse, as the fold gem
--- has, and its panes: two side by side (split) or one with a rail line
--- (join).
local function SwapGem(button, join)
    local glow = button:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(SWAP_MEDIA .. "Glow")
    glow:SetPoint("CENTER")
    local size = Width(button) or SharedWindow.SWAP_GEM
    glow:SetSize(size * 2.2, size * 2.2)
    glow:SetVertexColor(SWAP_GOLD[1], SWAP_GOLD[2], SWAP_GOLD[3], 1)
    pcall(glow.SetBlendMode, glow, "ADD")

    local gem = button:CreateTexture(nil, "ARTWORK")
    gem:SetTexture(SWAP_MEDIA .. "FoldGem")
    gem:SetAllPoints(button)

    local lit = button:CreateTexture(nil, "ARTWORK", nil, 1)
    lit:SetTexture(SWAP_MEDIA .. "FoldGem")
    lit:SetAllPoints(button)
    pcall(lit.SetBlendMode, lit, "ADD")

    local glyph = {}
    if join then
        SwapPane(button, -6, 5, 12, 10, glyph)
        glyph[#glyph + 1] = SwapInk(button, -3, 5, SWAP_LINE, 10)
    else
        SwapPane(button, -6, 5, 5, 10, glyph)
        SwapPane(button, 1, 5, 5, 10, glyph)
    end

    local function Light(p)
        glow:SetAlpha(0.25 + 0.55 * p)
        lit:SetAlpha(0.45 * p)
    end
    Light(0)
    button.Light = Light
    button.glyph = glyph
end

--- The gem's card: what a click does, and that the same gem undoes it.
function SharedWindow.SwapTooltip(button)
    if not (GameTooltip and button) then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    if rawget(button, "join") then
        GameTooltip:SetText(L["Join Into One Window"], 1, 1, 1)
        GameTooltip:AddLine(L["Puts every Blackthornes addon in one window, with a button for each down the side."],
            0.9, 0.88, 0.81, true)
        GameTooltip:AddLine(L["You can split them again with this same button."], 0.5, 0.82, 0.5, true)
    else
        GameTooltip:SetText(L["Split Into Own Windows"], 1, 1, 1)
        GameTooltip:AddLine(L["Gives each addon its own window again."], 0.9, 0.88, 0.81, true)
        GameTooltip:AddLine(L["You can join them back with this same button."], 0.5, 0.82, 0.5, true)
    end
    GameTooltip:Show()
end

--- Give a dressed window its swap gem, left of its fold gem (or of its
--- close gem when it has none). `key` is the addon whose own window this
--- is; nil for the one window. Returns the button, once per window.
function SharedWindow.AddSwap(frame, key)
    if type(frame) ~= "table" or type(CreateFrame) ~= "function" then return nil end
    local trim = rawget(frame, "titan")
    if type(trim) ~= "table" then return nil end
    local have = rawget(frame, "blackthornesSwap")
    if have then return have end

    local join = key ~= nil
    local ok, button = pcall(CreateFrame, "Button", nil, trim)
    if not (ok and button) then return nil end
    frame.blackthornesSwap = button
    button.swapKey = key
    button.join = join

    local fold = rawget(frame, "blackthornesFold")
    fold = type(fold) == "table" and fold.button or nil
    local beside = fold or rawget(trim, "closeButton")
    local size = SharedWindow.SWAP_GEM
    -- The Blizzard window style's buttons are the game's size: match them.
    if rawget(trim, "blizzard") then size = Width(beside) or size end
    button:SetSize(size, size)
    if beside then
        local besideSize = Width(beside) or size
        button:SetPoint("CENTER", beside, "CENTER", -(besideSize / 2 + size / 2 + SharedWindow.SWAP_GAP), 0)
    else
        button:SetPoint("CENTER", trim, "TOPRIGHT", -(8 + size + SharedWindow.SWAP_GAP), -8)
    end
    SwapGem(button, join)

    button:SetScript("OnEnter", function(self)
        self.hovered = true
        if ns.Motion and type(ns.Motion.Blend) == "function" then
            ns.Motion:Blend(self, "hover", 1, 0.12, self.Light)
        else
            self.Light(1)
        end
        SharedWindow.SwapTooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        self.hovered = false
        if ns.Motion and type(ns.Motion.Blend) == "function" then
            ns.Motion:Blend(self, "hover", 0, 0.18, self.Light)
        else
            self.Light(0)
        end
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnClick", function(self)
        if GameTooltip then GameTooltip:Hide() end
        local drawer = SharedWindow.Drawer()
        local api = drawer and drawer.api or SharedWindow
        local swap = type(api.Swap) == "function" and api.Swap or SharedWindow.Swap
        swap(rawget(self, "swapKey"), rawget(self, "join"))
    end)
    return button
end

-- A host's swap call, in a pcall: true and its answer when it has one.
local function HostCall(entry, name, ...)
    local host = entry and entry.host
    local fn = type(host) == "table" and host[name]
    if type(fn) ~= "function" then return false, nil end
    local ok, answer = pcall(fn, ...)
    if not ok then
        if ns.Debug then pcall(ns.Debug, "one window swap:", tostring(answer)) end
        return false, nil
    end
    return true, answer
end

--- The swap gem's click. `join` true: from `key`'s own window, every own
--- window closes and the one window opens on `key`, on the same tab.
--- `join` false: from the one window, it closes and the addon showing opens
--- in its own window, on the same tab, at its own spot. In a fight nothing
--- moves; it happens as the fight ends.
function SharedWindow.Swap(key, join)
    if InFight() then
        hub.swapAfterFight = { key = key, join = join and true or false }
        return false
    end
    hub.swapAfterFight = nil
    if join then
        local entry = key and hub.entries[key] or nil
        local _, tab = HostCall(entry, "tab")
        for _, each in pairs(hub.entries) do HostCall(each, "hide") end
        SharedWindow.SetOn(true)
        if entry and type(entry.host) == "table" then
            HostCall(entry, "show", tab)
            if not SharedWindow.IsOpen() then SharedWindow.Open(entry.key) end
        else
            SharedWindow.Open(key)
        end
        return true
    end
    local entry = hub.current or SharedWindow.Picked()
    local _, tab = HostCall(entry, "tab")
    SharedWindow.SetOn(false)
    if entry then
        local shown = HostCall(entry, "show", tab)
        if not shown and type(entry.open) == "function" then pcall(entry.open) end
    end
    return true
end


-- Every copy listens; only the one that draws acts.
if CreateFrame then
    local events = CreateFrame("Frame")
    local which = {}
    for key, place in pairs(SharedWindow.PLACES) do
        if place.show then
            which[place.show] = { key = key, open = true }
            which[place.hide] = { key = key, open = false }
            pcall(events.RegisterEvent, events, place.show)
            pcall(events.RegisterEvent, events, place.hide)
        end
    end
    pcall(events.RegisterEvent, events, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    pcall(events.RegisterEvent, events, "PLAYER_LOGIN")
    pcall(events.RegisterEvent, events, "PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event, kind)
        if event == "PLAYER_LOGIN" then SharedWindow.HookPlaces() return end
        if event == "PLAYER_REGEN_ENABLED" then
            -- The swap gem clicked in a fight happens now.
            local swap = hub.swapAfterFight
            if swap and IsDrawer() then SharedWindow.Swap(swap.key, swap.join) end
            if shelves.afterFight and IsDrawer() then
                shelves.afterFight = nil
                SharedWindow.ShelfLay()
            end
            return
        end
        if not IsDrawer() then return end
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
            local ok, key = pcall(SharedWindow.InteractionPlace, kind)
            if ok and key then SharedWindow.Left(key) end
            return
        end
        local what = which[event]
        if not what then return end
        if what.open then SharedWindow.Arrived(what.key) else SharedWindow.Left(what.key) end
    end)
    SharedWindow.events = events
end
